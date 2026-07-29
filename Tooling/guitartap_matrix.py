#!/usr/bin/env python3
"""guitartap_matrix.py — cross-platform / cross-device comparison matrix from .guitartap files.

Scans a directory of ``.guitartap`` files (each is a JSON array; the FIRST element is used),
groups them by *sample* (the filename stem before the platform/device tokens), and writes a
Markdown file with one table per sample:
  * columns  = each capture, labelled ``<platform>/<device>`` (e.g. ``swift/mac``)
  * rows     = key measured values + material inputs (material) or modes + decay/ratio (guitar)
  * a trailing **range** column = max − min across the numeric cells (the cross-capture spread)

Material inputs come straight from the snapshot; ``f_vs`` (panel stiffness) is *derived* — there is
no ``f_vs`` field, only ``plateStiffnessPreset`` + ``customPlateStiffness``. Effective f_vs = the
preset's value, or ``customPlateStiffness`` when the preset is "Custom".

Pure standard-library; no repo imports. Rerun it after new captures land.

Usage:
    python3 guitartap_matrix.py [DIR] [-o OUT.md]

Defaults:
    DIR = /Users/dws/src/GuitarTap/Tests/All Platforms
    OUT = <DIR>/comparison-matrix.md
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

DEFAULT_DIR = "/Users/dws/src/GuitarTap/Tests/All Platforms"

PLATFORMS = ["swift", "python", "web"]
DEVICES = ["mac", "ipad", "iphone", "windows", "linux"]

# Swift PlateStiffnessPreset.value (raw rawValue name -> f_vs). "Custom" defers to customPlateStiffness.
STIFFNESS_VALUE = {
    "Steel String Top": 75.0,
    "Steel String Back": 55.0,
    "Classical Top": 60.0,
    "Classical Back": 50.0,
    "Custom": None,
}

SNAPSHOT_KEYS = ("longitudinalSnapshot", "spectrumSnapshot", "crossSnapshot", "flcSnapshot")


# ── parsing helpers ──────────────────────────────────────────────────────────

def parse_name(stem: str):
    """(sample, platform, device) from a filename stem like 'plate-umik-1-3-tap-swift-mac-1785359465'."""
    toks = stem.split("-")
    for i, t in enumerate(toks):
        if t in PLATFORMS:
            sample = "-".join(toks[:i]) or stem
            device = toks[i + 1] if i + 1 < len(toks) and toks[i + 1] in DEVICES else "?"
            return sample, t, device
    return stem, "?", "?"


def col_sort_key(label: str):
    plat, _, dev = label.partition("/")
    p = PLATFORMS.index(plat) if plat in PLATFORMS else len(PLATFORMS)
    d = DEVICES.index(dev) if dev in DEVICES else len(DEVICES)
    return (p, d, label)


def all_snaps(m: dict):
    return [m[k] for k in SNAPSHOT_KEYS if isinstance(m.get(k), dict)]


def snap_get(m: dict, key: str):
    for s in all_snaps(m):
        v = s.get(key)
        if v is not None:
            return v
    return None


def resolved_type(m: dict) -> str:
    return snap_get(m, "measurementType") or m.get("measurementType") or "?"


def peak_freq(m: dict, pid):
    if not pid:
        return None
    for p in m.get("peaks", []):
        if p.get("id") == pid:
            return p.get("frequency")
    return None


def density_g_cm3(mass_g, length_mm, width_mm, thickness_mm):
    try:
        vol = length_mm * width_mm * thickness_mm
        if not vol:
            return None
        return mass_g / vol * 1000.0  # g / mm^3 -> g / cm^3
    except (TypeError, ZeroDivisionError):
        return None


def effective_fvs(preset, custom):
    if preset is None:
        return None
    v = STIFFNESS_VALUE.get(preset)
    return custom if v is None else v


# ── per-file extraction ──────────────────────────────────────────────────────

def extract(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    m = data[0] if isinstance(data, list) else data
    sample, platform, device = parse_name(path.stem)
    mt = resolved_type(m)
    is_material = mt.startswith("Material")
    is_brace = mt == "Material (Brace)"

    rec = {
        "sample": sample, "platform": platform, "device": device,
        "col": f"{platform}/{device}", "type": mt, "is_material": is_material,
        "name": m.get("measurementName") or "", "notes": m.get("notes") or "",
        "num_taps": m.get("numberOfTaps"),
        "fields": {},   # row label -> value (number or str)
    }
    f = rec["fields"]

    if is_material:
        f["fL"] = peak_freq(m, m.get("selectedLongitudinalPeakID"))
        if not is_brace:
            f["fC"] = peak_freq(m, m.get("selectedCrossPeakID"))
            f["fLC"] = peak_freq(m, m.get("selectedFlcPeakID"))
        pre = "brace" if is_brace else "plate"
        L = snap_get(m, f"{pre}Length"); W = snap_get(m, f"{pre}Width")
        T = snap_get(m, f"{pre}Thickness"); M = snap_get(m, f"{pre}Mass")
        f["Length (mm)"] = L
        f["Width (mm)"] = W
        f["Thickness (mm)"] = T
        f["Mass (g)"] = M
        f["Density (g/cm3)"] = density_g_cm3(M, L, W, T)
        if not is_brace:
            f["Body Length a (mm)"] = snap_get(m, "guitarBodyLength")
            f["Body Width b (mm)"] = snap_get(m, "guitarBodyWidth")
            preset = snap_get(m, "plateStiffnessPreset")
            custom = snap_get(m, "customPlateStiffness")
            f["Stiffness preset"] = preset
            f["f_vs (eff.)"] = effective_fvs(preset, custom)
    else:
        f["decayTime (s)"] = m.get("decayTime")
        f["tapToneRatio"] = m.get("tapToneRatio")
        selected = set(m.get("selectedPeakIDs") or [])
        by_mode: dict[str, list[float]] = {}
        for p in m.get("peaks", []):
            if selected and p.get("id") not in selected:
                continue
            lbl = p.get("modeLabel") or "?"
            by_mode.setdefault(lbl, []).append(p.get("frequency"))
        for lbl, freqs in by_mode.items():
            f[lbl] = freqs[0] if len(freqs) == 1 else ", ".join(f"{x:.1f}" for x in freqs)
        f["peaks det/sel"] = f"{len(m.get('peaks', []))}/{len(selected) if selected else 0}"

    return rec


# ── rendering ────────────────────────────────────────────────────────────────

def fmt_num(kind: str, v):
    """Format a cell by row *kind*: freq 1dp, decay/density 3dp, ratio 2dp, dim as-stored, text verbatim."""
    if v is None:
        return "—"
    if isinstance(v, str):
        return v
    if kind == "dens" or kind == "decay":
        return f"{v:.3f}"
    if kind == "ratio":
        return f"{v:.2f}"
    if kind == "freq":
        return f"{v:.1f}"
    # dim / f_vs / mass: show as stored, trimming a trailing .0
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v)


def fmt_range(kind: str, diff: float) -> str:
    if kind in ("dens", "decay"):
        return f"{diff:.3f}"
    if kind == "ratio":
        return f"{diff:.2f}"
    if kind == "freq":
        return f"{diff:.1f}"
    return f"{diff:.2f}"  # dim spread (should normally be 0)


def numeric_cells(label, recs, cols):
    out = []
    for c in cols:
        v = recs[c]["fields"].get(label)
        if isinstance(v, (int, float)) and not isinstance(v, bool):
            out.append(float(v))
    return out


def render_sample(sample: str, recs_by_col: dict) -> str:
    cols = sorted(recs_by_col, key=col_sort_key)
    any_rec = next(iter(recs_by_col.values()))
    is_material = any_rec["is_material"]

    # Row order, each as (label, kind).
    if is_material:
        is_brace = any_rec["type"] == "Material (Brace)"
        rows = [("fL", "freq")]
        if not is_brace:
            rows += [("fC", "freq"), ("fLC", "freq")]
        rows += [("Length (mm)", "dim"), ("Width (mm)", "dim"), ("Thickness (mm)", "dim"),
                 ("Mass (g)", "dim"), ("Density (g/cm3)", "dens")]
        if not is_brace:
            rows += [("Body Length a (mm)", "dim"), ("Body Width b (mm)", "dim"),
                     ("Stiffness preset", "text"), ("f_vs (eff.)", "dim")]
    else:
        # Guitar mode rows: order by ascending frequency (robust to label wording, e.g.
        # "Air (Helmholtz)"), so Air→Top→Back→… falls out naturally.
        seen = set()
        for r in recs_by_col.values():
            seen.update(k for k in r["fields"] if k not in
                        ("decayTime (s)", "tapToneRatio", "peaks det/sel"))

        def mode_freq(lbl):
            nums = [r["fields"].get(lbl) for r in recs_by_col.values()]
            nums = [v for v in nums if isinstance(v, (int, float)) and not isinstance(v, bool)]
            return min(nums) if nums else float("inf")

        ordered_modes = sorted(seen, key=mode_freq)
        rows = [("decayTime (s)", "decay"), ("tapToneRatio", "ratio")]
        rows += [(m, "freq") for m in ordered_modes]
        rows += [("peaks det/sel", "text")]

    mt = any_rec["type"]
    lines = [f"### {sample}  —  {mt}", ""]
    header = "| Field | " + " | ".join(cols) + " | range |"
    sep = "|" + "---|" * (len(cols) + 2)
    lines += [header, sep]
    for row, kind in rows:
        cells = [fmt_num(kind, recs_by_col[c]["fields"].get(row)) for c in cols]
        nums = numeric_cells(row, recs_by_col, cols)
        diff = (max(nums) - min(nums)) if len(nums) >= 2 else 0.0
        rng = fmt_range(kind, diff) if diff else ""
        lines.append(f"| {row} | " + " | ".join(cells) + f" | {rng} |")
    lines.append("")
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Build a cross-platform/device matrix from .guitartap files.")
    ap.add_argument("directory", nargs="?", default=DEFAULT_DIR, help="folder of .guitartap files")
    ap.add_argument("-o", "--out", default=None, help="output markdown path (default <dir>/comparison-matrix.md)")
    args = ap.parse_args(argv)

    d = Path(args.directory)
    if not d.is_dir():
        print(f"error: not a directory: {d}", file=sys.stderr)
        return 2
    files = sorted(d.glob("*.guitartap"))
    if not files:
        print(f"error: no .guitartap files in {d}", file=sys.stderr)
        return 2

    out_path = Path(args.out) if args.out else d / "comparison-matrix.md"

    # sample -> {col -> record}
    samples: dict[str, dict] = {}
    problems = []
    for p in files:
        try:
            rec = extract(p)
        except Exception as exc:  # keep going; report at the end
            problems.append(f"{p.name}: {exc}")
            continue
        samples.setdefault(rec["sample"], {})[rec["col"]] = rec

    body = [
        "# GuitarTap comparison matrix",
        "",
        f"Source: `{d}` · {len(files)} file(s) · {len(samples)} sample(s).",
        "Frequencies in Hz (1 dp); dimensions as stored (mm); density g/cm³; `f_vs` is the derived "
        "effective panel stiffness (preset value, or customPlateStiffness when preset = Custom). "
        "The **range** column is max − min across the numeric cells (cross-capture spread).",
        "",
    ]
    # Material samples first, then guitar; alphabetical within each.
    def sample_key(name):
        recs = samples[name]
        mat = next(iter(recs.values()))["is_material"]
        return (0 if mat else 1, name)

    for name in sorted(samples, key=sample_key):
        body.append(render_sample(name, samples[name]))

    if problems:
        body += ["## Files that could not be parsed", ""] + [f"- {p}" for p in problems] + [""]

    out_path.write_text("\n".join(body), encoding="utf-8")
    print(f"wrote {out_path}  ({len(files)} files, {len(samples)} samples"
          + (f", {len(problems)} problem(s)" if problems else "") + ")")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
