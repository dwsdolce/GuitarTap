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
#   before it starts listening), waits for its first-boot work to finish, and tells the test where the
#   simulator keeps its own files, which the document picker and Save to Files use.
#
# Each case is a test of its own, and a failed test is run once more: the share sheet and the document
# picker are the system's, and on a busy machine (a CI runner's simulator) one now and then never draws.
# A real failure fails both times; a test that passed only on its second run is listed at the end, so a
# stall stays visible.

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
    # Start the Files service once before the tests: on a freshly booted simulator (as on CI) the document
    # picker otherwise opens blank for longer than a test should wait.
    xcrun simctl launch "$udid" com.apple.DocumentsApp > /dev/null && sleep 10
    xcrun simctl terminate "$udid" com.apple.DocumentsApp > /dev/null 2>&1 || true
    # A freshly booted simulator spends its first minutes on system work (calls, notifications, wallpaper,
    # storage, permissions), and the system services the tests use — the share sheet, the document picker —
    # wait behind it: on a CI runner long enough that a test's query of them times out. Wait until the
    # simulator's processes are quiet (under 30 % of one core, three readings 5 s apart), at most 3 minutes.
    settle_start=$SECONDS quiet=0 load=0
    while (( SECONDS - settle_start < 180 )); do
        load="$(ps -Ao pcpu,command | awk '/\.simruntime\// { s += $1 } END { printf "%d", s }')"
        if (( load < 30 )); then
            quiet=$((quiet + 1))
            (( quiet >= 3 )) && break
        else
            quiet=0
        fi
        sleep 5
    done
    echo "Simulator settled after $((SECONDS - settle_start)) s (its processes at ${load} % CPU)." 
    # Earlier exports would make Save to Files ask to replace them.
    find "$files" -maxdepth 1 \( -name '*.png' -o -name '*.pdf' \) -delete
    destination="platform=iOS Simulator,id=$udid"
    # The test reads GT_FILES_DIR; xcodebuild passes TEST_RUNNER_-prefixed variables to it.
    export TEST_RUNNER_GT_FILES_DIR="$files"
fi

# The result bundle is kept beside the exports, so a failing run can be looked into.
tests=0
xcodebuild test -scheme guitar_tap -testPlan GuitarTapUITests -destination "$destination" \
    -retry-tests-on-failure -test-iterations 2 \
    -derivedDataPath "$work/dd" -resultBundlePath "$out/result.xcresult" | tail -5 || tests=1

xcrun xcresulttool export attachments --path "$out/result.xcresult" --output-path "$work/attachments" > /dev/null
"$PYTHON" - "$work/attachments" "$out" <<'EOF'
import json, os, shutil, sys

attachments, out = sys.argv[1], sys.argv[2]
files = {}
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
        # A retried case attaches again what its failed run had saved: one entry per file.
        files[f"{case}/{path}/{file}"] = {"case": case, "path": path, "format": ext.lstrip("."),
                                          "file": f"{case}/{path}/{file}"}
files = sorted(files.values(), key=lambda f: f["file"])
json.dump({"edition": "swift", "files": files}, open(os.path.join(out, "manifest.json"), "w"), indent=2)
print(f"{len(files)} exports → {out}")
EOF

# A test that failed and then passed on its second run: listed, so a stall is seen, not hidden by the retry.
xcrun xcresulttool get test-results tests --path "$out/result.xcresult" | "$PYTHON" -c '
import json, sys
retried = []
def walk(node):
    if node.get("nodeType") == "Test Case":
        runs = [c for c in node.get("children", []) if c.get("nodeType") == "Repetition"]
        if len(runs) > 1 and node.get("result") == "Passed":
            retried.append(node.get("name", "?"))
    for child in node.get("children", []):
        walk(child)
for node in json.load(sys.stdin).get("testNodes", []):
    walk(node)
if retried:
    print(f"⚠️  Passed only on a retry ({len(retried)}): " + ", ".join(retried))
' || true

check=0
"$PYTHON" Tooling/export-check/check_exports.py check "$out" || check=1
[[ $tests -eq 0 ]] || echo "The export UI tests failed — see $out/result.xcresult"
exit $(( tests || check ))
