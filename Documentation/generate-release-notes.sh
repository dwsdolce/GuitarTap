#!/usr/bin/env bash
# generate-release-notes.sh
# Generate the release-notes PDF, stamped with version + build numbers, from the single
# build-less source Documentation/ReleaseNotes.md. Mirrors the Python
# packaging/generate_release_notes.sh.
#
# Only the NEWEST section carries placeholders, filled from git:
#   {{version}} = MARKETING_VERSION (GuitarTap.xcodeproj)
#   {{build}}   = git commit count at HEAD                     (this build's number)
#   {{since}}   = git commit count at the previous release tag (the "since" build)
# Historical sections keep their literal numbers. Cutting the next release: freeze the current
# top section to its shipped literals and add a new placeholder top section.
#
# Runs automatically from generate-help.sh on the macOS build (and standalone). A condition it can't
# satisfy (no pandoc, no tag, current version already tagged) is an Xcode WARNING and a skip (exit 0);
# pandoc failing on the notes is an Xcode ERROR and fails the build — a broken release-notes PDF must
# not pass unnoticed.
#
# ORDERING: at release, generate BEFORE tagging — {{since}} is the count at the latest existing
# tag, which must still be the PREVIOUS release.
#
# Prerequisite: pandoc with xelatex (brew install pandoc; brew install --cask basictex), as for the
# Quick Start guide: the notes hold Unicode ("−∞", "→", "·") that pandoc's default engine cannot set.

set -uo pipefail   # not -e: each condition below decides between a warning-and-skip and an error

# Homebrew/TeX on PATH for non-interactive Xcode build phases (mirrors generate-help.sh).
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$SCRIPT_DIR/ReleaseNotes.md"
PBXPROJ="$ROOT/GuitarTap.xcodeproj/project.pbxproj"

command -v pandoc &>/dev/null || { echo "warning: generate-release-notes.sh: pandoc not found — no release-notes PDF." >&2; exit 0; }
[ -f "$SRC" ] || { echo "warning: generate-release-notes.sh: $SRC not found — no release-notes PDF." >&2; exit 0; }

VERSION="$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed -E 's/.*= *([^;]+);.*/\1/' | tr -d ' ')"
BUILD="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null)"
LAST_TAG="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null)"

if [ -z "$VERSION" ] || [ -z "$BUILD" ] || [ -z "$LAST_TAG" ]; then
    echo "warning: generate-release-notes.sh: missing version/build/tag — no release-notes PDF." >&2; exit 0
fi
if [ "$LAST_TAG" = "$VERSION" ]; then
    echo "warning: generate-release-notes.sh: latest tag ($LAST_TAG) == current version — generate BEFORE tagging; no release-notes PDF." >&2
    exit 0
fi
SINCE="$(git -C "$ROOT" rev-list --count "$LAST_TAG" 2>/dev/null)"

OUT_MD="$SCRIPT_DIR/ReleaseNotes-${VERSION}-${BUILD}.md"
OUT_PDF="$SCRIPT_DIR/ReleaseNotes-${VERSION}-${BUILD}.pdf"

# Drop prior stamped outputs for THIS version so a rolling build number doesn't pile up files.
rm -f "$SCRIPT_DIR/ReleaseNotes-${VERSION}-"*.md "$SCRIPT_DIR/ReleaseNotes-${VERSION}-"*.pdf

# Fill the newest section's placeholders (tokens appear only there; history is literal).
sed -e "s/{{version}}/${VERSION}/g" \
    -e "s/{{build}}/${BUILD}/g" \
    -e "s/{{since}}/${SINCE}/g" \
    "$SRC" > "$OUT_MD"

# Arial: it has every character the notes use, "→" included, which Helvetica lacks. A character the font
# lacks is only a warning to xelatex and would vanish from the PDF, so it is an error here.
LOG="$(mktemp)"
if ! pandoc "$OUT_MD" --pdf-engine=xelatex --variable "mainfont=Arial" -o "$OUT_PDF" 2> "$LOG"; then
    cat "$LOG" >&2; rm -f "$LOG"
    echo "error: generate-release-notes.sh: pandoc could not make $(basename "$OUT_PDF") (see above)." >&2; exit 1
fi
if grep -q "Missing character" "$LOG"; then
    cat "$LOG" >&2; rm -f "$LOG" "$OUT_PDF"
    echo "error: generate-release-notes.sh: the font has no glyph for a character in the notes (see above)." >&2; exit 1
fi
rm -f "$LOG"

echo "generate-release-notes.sh: wrote $(basename "$OUT_MD") and $(basename "$OUT_PDF")"
echo "  version=${VERSION} build=${BUILD} since=${SINCE} (previous tag ${LAST_TAG})"
