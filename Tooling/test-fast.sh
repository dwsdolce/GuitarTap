#!/bin/zsh
# The fast test run: the whole GuitarTapTests suite on macOS except the recording-playback regression
# (FilePlaybackRegressionTests), which plays every recording through the full pipeline and is most of
# the suite's time. It is also Swift's zero-tolerance self-regression, which Python and the web keep as
# a separate test and skip in their fast runs too. Use it while working; run the full suite before a commit or after a change to
# capture, detection or peak finding, which the playback regression covers.
#
# The same split in the other editions: web `npm run test:fast`, Python `Tooling/test-fast.sh`.
#
# Usage:  Tooling/test-fast.sh [xcodebuild args…]
set -u
cd "$(dirname "$0")/.." || exit 1          # repo root

exec xcodebuild test -scheme guitar_tap -destination 'platform=macOS' \
  -skip-testing:GuitarTapTests/FilePlaybackRegressionTests "$@"
