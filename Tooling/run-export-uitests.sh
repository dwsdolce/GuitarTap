#!/bin/bash
# Run the export UI tests (GuitarTapUITests.xctestplan), lay their exports out for the export checker —
#   <out>/<case>/<main|saved>/<file>   and   <out>/manifest.json
# — and check them against Swift's expected values (Tooling/export-check/), with this repo's .venv.
#
# The UI tests drive the real app through Import and both export paths. The test runner is sandboxed, so
# each export leaves the run as an attachment of the test result; this script extracts them.
#
# Usage: Tooling/run-export-uitests.sh [out-dir]   (default: build/export-uitests)
# The tests take over the mouse and keyboard for about ten minutes.

set -euo pipefail
cd "$(dirname "$0")/.."

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

# The result bundle is kept beside the exports, so a failing run can be looked into.
tests=0
xcodebuild test -scheme guitar_tap -testPlan GuitarTapUITests -destination 'platform=macOS' \
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
