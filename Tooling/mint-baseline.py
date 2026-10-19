#!/usr/bin/env python3
# @parity tooling/mint-baseline
"""Mint a Swift configuration's self-baseline — its zero-tolerance regression reference — on a simulator or a device.

    .venv/bin/python Tooling/mint-baseline.py --simulator "iPad Air 11-inch (M4)"           # mint (asks first)
    .venv/bin/python Tooling/mint-baseline.py --simulator "iPad Air 11-inch (M4)" --yes     # don't ask
    .venv/bin/python Tooling/mint-baseline.py --simulator "iPhone 17" --check               # diff, write nothing
    .venv/bin/python Tooling/mint-baseline.py --device "dws's iPad M5"                      # a connected device

Swift on macOS minted the oracle, so the oracle is that configuration's baseline. Every other Swift
configuration mints its own here, beside the tests (`GuitarTapTests/self-baseline-<os>-<arch>.json`), as
Python's and the web's `mint-baseline` do theirs: the iOS simulator (`ios-simulator`), whose runtime differs
from a device's in the last bit of a few values, and a physical iPad or iPhone (`ios`). A device must be
connected, unlocked, and set up for development; the file is copied off it with `xcrun devicectl`.

Deliberately separate from the test run: a suite that minted its own expectations could never fail. So
this is an explicit act, and the file it writes is committed and reviewed like any other change.

  * **No baseline yet.** There is no prior to compare against, so the first run is trusted — with the one
    check available: every value must clear the oracle's `bootstrapTolerances` against the oracle. Outside
    it there is no baseline to commit, there is a finding.
  * **A baseline exists.** Re-minting means the numbers moved deliberately, so the diff against the
    current baseline is printed and confirmed before anything is written. That diff is the review artifact.

The values come from the test target's own generator (`GenerateParityOracleTests.generateSelfBaseline`),
run on the simulator by `xcodebuild`: it computes every oracle case through the app, as the oracle's
generator does, and prints where it wrote the file — inside the simulator's container, on this Mac.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
import tempfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(REPO_ROOT, "GuitarTapTests")
ORACLE_PATH = os.path.join(TESTS, "parity-oracle.json")

# Which tolerance governs a value, by the leaf its path ends in — Python's and the web's table.
_TOLERANCE_KEYS = {
    "frequency": "freqHz",
    "magnitude": "magDb",
    "q": "q",
    "ringOutSec": "ringOutSec",
    "db": "gatedFftDb",
    "deltaDb": "gatedFftDb",
}

# JSON has no infinity: every oracle and baseline file stores a non-finite number as its string.
_NONFINITE = {"-Infinity": float("-inf"), "Infinity": float("inf"), "NaN": float("nan")}


def decode_nonfinite(node):
    if isinstance(node, dict):
        return {k: decode_nonfinite(v) for k, v in node.items()}
    if isinstance(node, list):
        return [decode_nonfinite(v) for v in node]
    if isinstance(node, str) and node in _NONFINITE:
        return _NONFINITE[node]
    return node


def flatten(values: dict) -> dict[str, float]:
    """Nested case values -> one flat {path: number} map, with the paths every edition produces."""
    flat: dict[str, float] = {}

    def label(item):
        if not isinstance(item, dict):
            return None
        if "role" in item:
            return str(item["role"])
        if "tap" in item:
            return f"tap{item['tap']}"
        if "hz" in item:
            hz = item["hz"]
            return f"{int(hz) if float(hz).is_integer() else hz}Hz"
        return None

    def walk(node, path: str) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                if key in ("role", "tap", "hz") or key.startswith("_"):
                    continue
                walk(value, f"{path}/{key}")
        elif isinstance(node, list):
            for index, item in enumerate(node):
                walk(item, f"{path}/{label(item) or index}")
        elif isinstance(node, (int, float)) and not isinstance(node, bool):
            flat[path] = float(node)

    for block in ("filePlayback", "gatedFft"):
        for name, body in values.get(block, {}).items():
            walk(body, name)
    return flat


def load_json(path: str):
    with open(path, encoding="utf-8") as fh:
        return decode_nonfinite(json.load(fh))


def check_against_oracle(oracle: dict, computed: dict[str, float]) -> list[str]:
    """Paths where this configuration falls outside the first-mint bar. Empty is a pass."""
    bootstrap = oracle.get("bootstrapTolerances", oracle["tolerances"])
    oracle_flat = flatten(oracle)
    failures = []
    for path, value in sorted(computed.items()):
        if path.endswith("/maxDb"):
            # Silence: the oracle records the exact value (-inf); no tolerance applies to it.
            want = float(oracle["gatedFft"][path.split("/", 1)[0]]["maxDb"])
            if not value == want:
                failures.append(f"  {path}: {value!r} is not the oracle's {want!r}")
            continue
        if path not in oracle_flat:
            continue
        key = _TOLERANCE_KEYS.get(path.rsplit("/", 1)[-1])
        if key is None:
            continue
        delta = abs(value - oracle_flat[path])
        if delta >= float(bootstrap[key]):
            failures.append(f"  {path}: oracle {oracle_flat[path]!r}, computed {value!r}, "
                            f"delta {delta:.6g} >= {bootstrap[key]} tolerance")
    return failures


def diff_against(previous: dict, computed: dict[str, float]) -> list[str]:
    was = flatten(previous["values"])
    lines = []
    for path in sorted(set(was) | set(computed)):
        before, after = was.get(path), computed.get(path)
        if before is None:
            lines.append(f"  + {path} = {after!r}")
        elif after is None:
            lines.append(f"  - {path} (was {before!r})")
        elif before != after and not (math.isnan(before) and math.isnan(after)):
            lines.append(f"  ~ {path}: {before!r} -> {after!r}  (delta {after - before:+.10g})")
    return lines


def simulator_udid(name: str) -> str:
    """The id of the available simulator called `name` (or with that id)."""
    listing = json.loads(subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                                        check=True, capture_output=True, text=True).stdout)
    for devices in listing["devices"].values():
        for device in devices:
            if name in (device["name"], device["udid"]):
                return device["udid"]
    sys.exit(f"No available simulator named {name!r} (xcrun simctl list devices available).")


def device_udid(name: str) -> str:
    """The UDID of the connected device called `name` (or with that UDID)."""
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as out:
        path = out.name
    subprocess.run(["xcrun", "devicectl", "list", "devices", "--json-output", path], check=True,
                   capture_output=True)
    with open(path, encoding="utf-8") as fh:
        listing = json.load(fh)
    os.unlink(path)
    for device in listing.get("result", {}).get("devices", []):
        udid = device.get("hardwareProperties", {}).get("udid")
        if name in (device.get("deviceProperties", {}).get("name"), udid):
            return udid
    sys.exit(f"No connected device named {name!r} (xcrun devicectl list devices).")


def copy_from_device(udid: str) -> str:
    """The generated file, copied out of the app's container on the device to a local temporary file. The
    tests run hosted in the app, so the generator's temporary directory is the app container's `tmp`."""
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as out:
        local = out.name
    subprocess.run(["xcrun", "devicectl", "device", "copy", "from", "--device", udid,
                    "--domain-type", "appDataContainer", "--domain-identifier", "com.dolcesfogato.GuitarTap",
                    "--source", "tmp/self-baseline.json", "--destination", local],
                   check=True, capture_output=True)
    return local


def generate(destination: str, device: str | None) -> tuple[dict, str]:
    """Run the generator on the simulator or device; the generated baseline and its raw text.

    xcodebuild's exit status is not enough: a filter that matches nothing, or a test that is skipped
    because its flag did not reach the runner, both "succeed". The generated file is the only honest
    signal, and the generator prints where it put it. The flag must carry the TEST_RUNNER_ prefix:
    xcodebuild forwards only those to a hosted test runner.
    """
    env = dict(os.environ, TEST_RUNNER_GENERATE_SELF_BASELINE="1")
    with tempfile.NamedTemporaryFile("w+", suffix=".log", delete=False) as log:
        status = subprocess.run(
            ["xcodebuild", "test",
             "-project", os.path.join(REPO_ROOT, "GuitarTap.xcodeproj"),
             "-scheme", "guitar_tap",
             "-destination", destination,
             "-only-testing:GuitarTapTests/GenerateParityOracleTests"]
            + (["-allowProvisioningUpdates"] if device else []),
            env=env, stdout=log, stderr=subprocess.STDOUT).returncode
        log.seek(0)
        text = log.read()
    wrote = [line.split(" ", 1)[1] for line in text.splitlines() if line.startswith("SELF_BASELINE_WROTE ")]
    if wrote and device:
        wrote = [copy_from_device(device)]   # the printed path is the device's own
    if not wrote or not os.path.exists(wrote[0]):
        print("❌ The generator did not produce a file — nothing was minted.", file=sys.stderr)
        print(f"   xcodebuild exit status: {status} (0 here means it ran and minted NOTHING).", file=sys.stderr)
        print(f"   Full log: {log.name}", file=sys.stderr)
        sys.exit(1)
    if status != 0:
        print(f"❌ The generator ran but the test reported a failure. Full log: {log.name}", file=sys.stderr)
        sys.exit(1)
    os.unlink(log.name)
    with open(wrote[0], encoding="utf-8") as fh:
        raw = fh.read()
    return decode_nonfinite(json.loads(raw)), raw


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    where = parser.add_mutually_exclusive_group(required=True)
    where.add_argument("--simulator", help="the simulator's name or id")
    where.add_argument("--device", help="a connected device's name or UDID")
    parser.add_argument("--yes", action="store_true", help="overwrite without asking")
    parser.add_argument("--check", action="store_true", help="report only; write nothing")
    args = parser.parse_args()

    if args.simulator:
        udid = simulator_udid(args.simulator)
        print(f"Simulator: {args.simulator} ({udid})")
        destination, device = f"platform=iOS Simulator,id={udid}", None
    else:
        udid = device_udid(args.device)
        print(f"Device: {args.device} ({udid})")
        destination, device = f"id={udid}", udid
    print("Running every oracle case on it (builds and briefly launches the app) …")
    generated, raw = generate(destination, device)
    configuration = generated["configuration"]
    if configuration.get("os") == "darwin":
        sys.exit("This is the oracle's configuration — Swift on macOS mints the oracle (Tooling/mint-oracle.sh).")
    path = os.path.join(TESTS, f"self-baseline-{configuration['os']}-{configuration['arch']}.json")
    print(f"Configuration: swift-{configuration['os']}-{configuration['arch']}")
    print(f"Baseline:      {path}")
    computed = flatten(generated["values"])
    print(f"Computed {len(computed)} values.")

    oracle = load_json(ORACLE_PATH)
    if not os.path.exists(path):
        print("\nNo baseline exists for this configuration — bootstrapping.")
        print("Checking the values against the oracle at the first-mint bar, since there is no prior.")
        failures = check_against_oracle(oracle, computed)
        if failures:
            print(f"\n❌ {len(failures)} value(s) fall outside the first-mint bar:")
            print("\n".join(failures[:20]))
            print("\nNo baseline written: freezing these would freeze a defect into the check meant to catch it.")
            return 1
        print("✅ Every value is within the first-mint bar.")
        if args.check:
            return 1
    else:
        lines = diff_against(load_json(path), computed)
        if not lines:
            print("\n✅ Identical to the committed baseline — nothing to do.")
            return 0
        print(f"\n{len(lines)} value(s) differ from the committed baseline:")
        print("\n".join(lines[:40]))
        if len(lines) > 40:
            print(f"  ... and {len(lines) - 40} more")
        print("\nThis diff is the review artifact. Adopt it only if a deliberate change explains every line;")
        print("otherwise it is a regression and re-minting hides it.")
        if args.check:
            return 1
        if not args.yes and input("\nOverwrite the baseline with these values? [y/N] ").strip().lower() != "y":
            print("Not written.")
            return 1

    with open(path, "w", encoding="utf-8") as fh:
        fh.write(raw)
    print(f"\nWrote {path}. Review and commit it; the hub collects it with tooling/collect-baselines.py.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
