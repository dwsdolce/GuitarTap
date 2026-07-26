#!/bin/zsh
# Deinit-race soak harness for GuitarTap (Swift) — a DEV TOOL, not a CI test.
#
# Purpose: surface the intermittent EXC_BAD_ACCESS in TapToneAnalyzer.deinit that only shows
# under swift-testing's PARALLEL execution of many analyzer-creating tests. Build once, then loop
# the fast unit suite (skip slow WAV playback) N times, hunting crashes.
#
# WHY IT SCANS CRASH REPORTS, NOT STDOUT (learned the hard way):
#   - swift-testing runs @Test cases on parallel cooperative workers. A TapToneAnalyzer that
#     crashes in deinit crashes a WORKER during teardown, OUT OF BAND — the run still prints
#     "Test run with N tests ... passed".
#   - macOS often writes the .ips crash report SILENTLY (no dialog) for a repeated background
#     test-host crash. So neither the test output nor a pop-up is reliable.
#   - The only faithful signal is a NEW GuitarTap*.ips in ~/Library/Logs/DiagnosticReports.
#   (Ports to Python/web: watch for crash ARTIFACTS, not the runner's exit text.)
#
# GOTCHA: do NOT edit source while this runs — it invalidates the baked test build, and
#         `test-without-building` then silently fails to execute (prints no "passed", no crash).
#
# Usage:  Tooling/deinit-soak.sh [N]      (default N=300; ~3.5 s/run serialized-ish)
set -u
cd "$(dirname "$0")/.." || exit 1          # repo root
DR="$HOME/Library/Logs/DiagnosticReports"
N="${1:-300}"

MARKER="$(mktemp)"          # mtime = loop start; `find -newer` flags reports created after it
echo "marker: $MARKER  (crash reports newer than this are ours)"
echo "pre-existing GuitarTap crash reports: $(find "$DR" -name 'GuitarTap*.ips' 2>/dev/null | wc -l | tr -d ' ')"

echo "building for testing (once)..."
xcodebuild build-for-testing -scheme guitar_tap -destination 'platform=macOS' 2>&1 | grep -E "TEST BUILD|error:" | head -3

PASS=0; NOPASS=0; CRASH=0
for i in $(seq 1 "$N"); do
  OUT=$(xcodebuild test-without-building -scheme guitar_tap -destination 'platform=macOS' \
        -skip-testing:GuitarTapTests/FilePlaybackRegressionTests 2>&1)
  if print -r -- "$OUT" | grep -q "passed after"; then PASS=$((PASS+1)); else NOPASS=$((NOPASS+1)); echo; echo "!!! RUN $i: no pass line"; fi
  NEW=$(find "$DR" -name 'GuitarTap*.ips' -newer "$MARKER" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$NEW" -gt "$CRASH" ]; then
    CRASH="$NEW"
    echo; echo "!!! RUN $i: NEW CRASH REPORT (total $CRASH) ->"
    find "$DR" -name 'GuitarTap*.ips' -newer "$MARKER" 2>/dev/null | tail -1
  fi
  # Live per-run tally (matches the Python/web soak scripts). Updates BETWEEN runs — a single
  # xcodebuild run is ~3.5 s of silence because its output is captured, not streamed.
  printf "\r%d/%d  pass=%d crash=%d nopass=%d " "$i" "$N" "$PASS" "$CRASH" "$NOPASS"
done

echo "=== DONE: $N runs | $PASS pass-lines | $CRASH CRASH REPORTS | $NOPASS no-pass ==="
echo "crash reports this run:"
find "$DR" -name 'GuitarTap*.ips' -newer "$MARKER" 2>/dev/null
# To inspect a report:  grep -E 'build_version|EXC_|TapToneAnalyzer.deinit' <report>.ips
