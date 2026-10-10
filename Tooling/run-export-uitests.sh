#!/bin/bash
# Run the export UI tests (GuitarTapUITests.xctestplan), lay their exports out for the export checker —
#   <out>/<case>/<main|saved>/<file>   and   <out>/manifest.json
# — and check them against Swift's expected values (Tooling/export-check/), with this repo's .venv.
#
# The UI tests drive the real app through Import and both export paths. Each export leaves the run as an
# attachment of the test result; this script extracts them.
#
# Usage: Tooling/run-export-uitests.sh [--simulator <name or id>] [out-dir]   (default: build/export-uitests)
#   On the Mac (the default) the tests take over the mouse and keyboard for about eight minutes.
#   --simulator runs them on an iPad or iPhone simulator ("iPad Air 11-inch (M4)", "iPhone 17", or its id):
#   the script boots it, grants the microphone (the state of a user who has allowed it — the app asks
#   before it starts listening), and tells the test where the simulator keeps its own files, which the
#   document picker and Save to Files use.

set -euo pipefail
cd "$(dirname "$0")/.."

simulator=""
if [[ "${1:-}" == "--simulator" ]]; then
    simulator="${2:?--simulator needs a simulator name or id}"
    shift 2
fi
out="${1:-build/export-uitests}"
# Python: this repo's own .venv (.venv/bin on macOS and Linux, .venv/Scripts on Windows); PYTHON names another.
if [ -z "${PYTHON:-}" ]; then
    for candidate in .venv/bin/python .venv/Scripts/python.exe .venv/Scripts/python; do
        if [ -x "$candidate" ]; then PYTHON="$candidate"; break; fi
    done
fi
if [ -z "${PYTHON:-}" ]; then
    echo "No .venv: set it up as the README's \"Setting up on a new machine\" says." >&2
    exit 1
fi
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
rm -rf "$out"
mkdir -p "$out"

destination='platform=macOS'
if [[ -n "$simulator" ]]; then
    udid="$(xcrun simctl list devices available -j | "$PYTHON" -c '
import json, sys
want = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if want in (d["name"], d["udid"]):
            print(d["udid"]); sys.exit()
sys.exit("no available simulator named " + want)' "$simulator")"
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" > /dev/null
    xcrun simctl privacy "$udid" grant microphone com.dolcesfogato.GuitarTap
    group="$(xcrun simctl get_app_container "$udid" com.apple.DocumentsApp groups \
        | awk '$1 == "group.com.apple.FileProvider.LocalStorage" { $1 = ""; sub(/^ /, ""); print }')"
    files="$group/File Provider Storage"
    mkdir -p "$files"
    # Earlier exports would make Save to Files ask to replace them.
    find "$files" -maxdepth 1 \( -name '*.png' -o -name '*.pdf' \) -delete
    destination="platform=iOS Simulator,id=$udid"
    # The test reads GT_FILES_DIR; xcodebuild passes TEST_RUNNER_-prefixed variables to it.
    export TEST_RUNNER_GT_FILES_DIR="$files"
fi

# The result bundle is kept beside the exports, so a failing run can be looked into.
tests=0
xcodebuild test -scheme guitar_tap -testPlan GuitarTapUITests -destination "$destination" \
    -derivedDataPath "$work/dd" -resultBundlePath "$out/result.xcresult" | tail -5 || tests=1

xcrun xcresulttool export attachments --path "$out/result.xcresult" --output-path "$work/attachments" > /dev/null
"$PYTHON" - "$work/attachments" "$out" <<'EOF'
import json, os, shutil, sys

attachments, out = sys.argv[1], sys.argv[2]
files = []
for test in json.load(open(os.path.join(attachments, "manifest.json"))):
    for a in test["attachments"]:
        # The test names each export <case>--<main|saved>--<file>; XCTest appends _<n>_<uuid>.<ext>.
        name = a.get("suggestedHumanReadableName", "")
        if "--" not in name:
            continue
        case, path, rest = name.split("--", 2)
        ext = os.path.splitext(rest)[1]
        file = rest.rsplit("_0_", 1)[0]
        if not file.endswith(ext):
            file += ext
        dest = os.path.join(out, case, path)
        os.makedirs(dest, exist_ok=True)
        shutil.copy(os.path.join(attachments, a["exportedFileName"]), os.path.join(dest, file))
        files.append({"case": case, "path": path, "format": ext.lstrip("."),
                      "file": f"{case}/{path}/{file}"})
files.sort(key=lambda f: f["file"])
json.dump({"edition": "swift", "files": files}, open(os.path.join(out, "manifest.json"), "w"), indent=2)
print(f"{len(files)} exports → {out}")
EOF

check=0
"$PYTHON" Tooling/export-check/check_exports.py check "$out" || check=1
[[ $tests -eq 0 ]] || echo "The export UI tests failed — see $out/result.xcresult"
exit $(( tests || check ))
