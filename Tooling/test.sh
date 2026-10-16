#!/usr/bin/env bash
# The full test run: the guitar_tap test plan on macOS, then each skipped test and why. xcodebuild's log
# reports a skip on a line of its own, somewhere among thousands; this lists them at the end, as the
# Python and web runs do. Tooling/test-fast.sh runs through this too.
#
# Usage:  Tooling/test.sh [--bundle path.xcresult] [xcodebuild args…]
#         --bundle keeps the result bundle there (CI uploads it); otherwise it is temporary.
set -u
cd "$(dirname "$0")/.." || exit 1          # repo root

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

if [[ "${1:-}" == "--bundle" ]]; then
    bundle="${2:?--bundle needs a path}"
    shift 2
else
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
    bundle="$work/test.xcresult"
fi
rm -rf "$bundle"

xcodebuild test -scheme guitar_tap -testPlan guitar_tap -destination 'platform=macOS' \
    -resultBundlePath "$bundle" "$@"
status=$?

if [ -d "$bundle" ]; then
    xcrun xcresulttool get test-results tests --path "$bundle" | "$PYTHON" -c '
import json, sys

def walk(node, found):
    if node.get("nodeType") == "Test Case" and node.get("result") == "Skipped":
        reasons = [c["name"] for c in node.get("children", []) if c.get("nodeType") == "Skip Message"]
        reason = reasons[0] if reasons else ""
        reason = reason.removeprefix("Test skipped").removeprefix(":").strip()
        found.append((node.get("nodeIdentifier", node["name"]), reason))
    for child in node.get("children", []):
        walk(child, found)

found = []
for node in json.load(sys.stdin).get("testNodes", []):
    walk(node, found)
if found:
    print(f"Skipped ({len(found)}):")
    for identifier, reason in found:
        print(f"  {identifier}" + (f" — {reason}" if reason else ""))
'
fi
exit $status
