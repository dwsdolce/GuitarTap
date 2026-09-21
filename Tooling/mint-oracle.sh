#!/usr/bin/env bash
# mint-oracle.sh — regenerate the parity oracle from the canonical Swift implementation.
#
# SWIFT REPO ONLY, and deliberately NOT part of sync-oracle.sh: that script is the
# canonical copy shared verbatim by every repo and carries no per-repo knowledge.
# Minting is Swift-only (only the canonical edition may mint — a tracking edition
# minting would make the oracle record what the tracking edition does), so it lives
# in its own script here.
#
#   ./Tooling/mint-oracle.sh            # regenerate and show the diff
#   ./Tooling/mint-oracle.sh --dry-run  # regenerate, diff, leave the tree untouched
#
# Why a wrapper rather than a documented xcodebuild line: three details of that line
# are easy to get wrong, and EVERY ONE of them yields "** TEST SUCCEEDED **" while
# minting nothing —
#
#   - the scheme is `guitar_tap`; `GuitarTap` is a target name and fails differently;
#   - `-only-testing` wants the type name GenerateParityOracleTests, not the
#     @Suite("GenerateParityOracle") display name. A mismatch runs "Executed 0 tests"
#     and reports success;
#   - xcodebuild does not forward the shell environment to a hosted test runner, so
#     the flag must be TEST_RUNNER_GENERATE_PARITY_ORACLE. Unprefixed, the gated test
#     is skipped — and reports success.
#
# This script gets all three right and then checks that a file actually appeared,
# so a silent no-op cannot be read as a clean run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="$REPO_ROOT/GuitarTapTests/parity-oracle.json"

DRY_RUN=0
case "${1:-}" in
  --dry-run) DRY_RUN=1 ;;
  "")        ;;
  *)         echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

[[ -f "$DEST" ]] || { echo "ERROR: $DEST not found." >&2; exit 2; }

# The generator picks its own output path and prints it. It must: the test process
# runs inside the app's sandbox, whose temporary directory is the app CONTAINER's,
# not the shell's — a path from `mktemp -d` here is outside the container and is
# refused exactly like the source tree was.
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

# The SHA is computed HERE and passed in: the test process runs inside the app sandbox,
# which denies spawning git. Stamping it is the whole point of oracleVersion — without
# it the file cannot say which build produced its numbers.
SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain -- GuitarTap GuitarTapTests 2>/dev/null)" ]]; then
  SHA="$SHA-dirty"
  echo "⚠️  Uncommitted changes under GuitarTap/ or GuitarTapTests/ — minting as $SHA."
  echo "   The recorded oracleVersion will not describe a commit anyone else can check out."
fi
echo "Minting from the Swift implementation at $SHA (builds and briefly launches the app)…"
set +e
TEST_RUNNER_GENERATE_PARITY_ORACLE=1 \
TEST_RUNNER_PARITY_ORACLE_VERSION="$SHA" \
xcodebuild test \
  -project "$REPO_ROOT/GuitarTap.xcodeproj" \
  -scheme guitar_tap \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:GuitarTapTests/GenerateParityOracleTests >"$LOG" 2>&1
status=$?
set -e

# xcodebuild's exit status is not sufficient on its own: a filter that matches nothing,
# or a skipped test, both exit 0. The generated file is the only honest signal, and the
# generator tells us where it put it.
OUT="$(grep -m1 '^PARITY_ORACLE_WROTE ' "$LOG" | sed 's/^PARITY_ORACLE_WROTE //' || true)"
if [[ -z "$OUT" || ! -f "$OUT" ]]; then
  echo "❌ The generator did not produce a file — nothing was minted." >&2
  echo "   xcodebuild exit status: $status (0 here means it ran and minted NOTHING)." >&2
  grep -E "Executed [0-9]+ test|Test run with|error:|TEST (SUCCEEDED|FAILED)" "$LOG" | tail -10 >&2 || true
  echo "   Full log: $LOG" >&2
  trap - EXIT   # keep the log for inspection
  exit 1
fi

if [[ $status -ne 0 ]]; then
  echo "❌ The generator ran but the test reported a failure." >&2
  grep -E "recorded an issue|error:|Test run with" "$LOG" | tail -10 >&2 || true
  exit 1
fi

# diff's exit status is THREE-valued: 0 same, 1 different, 2 error. Testing only for
# "non-zero" reports an error as a difference — which is exactly what happened when this
# script could not read $OUT out of the app's sandbox container: it announced "Regenerated
# output differs from the committed oracle" having compared nothing at all, and the diff
# that should have shown what differed was an "Operation not permitted" line. A script whose
# stated purpose is that a silent no-op cannot be read as a clean run must not let a failed
# comparison be read as a finding either.
#
# `|| diff_status=$?` rather than a bare call: `set -e` is in force and would abort on the
# non-zero that simply means "these files differ".
diff_status=0
diff -q "$OUT" "$DEST" >/dev/null 2>&1 || diff_status=$?
if [[ $diff_status -eq 0 ]]; then
  echo "✅ Regenerated — identical to the committed oracle. No values moved."
  exit 0
elif [[ $diff_status -gt 1 ]]; then
  echo "❌ Could not compare the regenerated output against $DEST — diff exited $diff_status." >&2
  echo "   The files were NOT compared, so this is not a finding about the oracle." >&2
  echo "   Usually permissions: $OUT lives in the app's sandbox container, which macOS" >&2
  echo "   protects from other processes. Grant Full Disk Access to the terminal or IDE" >&2
  echo "   running this script, relaunch it (TCC is captured at process start), and retry." >&2
  exit 1
fi

echo "Regenerated output differs from the committed oracle:"
diff -u "$DEST" "$OUT" || true
echo
echo "NOTE: re-serialisation sorts keys and rounds to 5 dp, so ordering and decimal"
echo "      places may move. A changed VALUE is a real finding about Swift versus the"
echo "      recorded goldens — investigate it, do not just commit it."

if [[ $DRY_RUN -eq 1 ]]; then
  echo "(--dry-run: tree left untouched)"
  exit 0
fi

cp "$OUT" "$DEST"
echo "✅ Updated $DEST"
echo "   Next: ORACLE_SRC=<hub checkout> ./Tooling/sync-oracle.sh --publish"
