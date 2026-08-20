#!/bin/bash
# check-release-ready.sh
#
# Refuses to build against a stale release identity. Mirrors the Python edition's
# src/guitar_tap/_release_guard.py and the web edition's tooling/check-release-ready.sh
# — same rule, same two conditions.
#
# The rule: **any development after a release must roll the version number AND
# roll the release notes.** Until both are done the tree claims to be a release
# that has already shipped, so everything it produces is mislabelled — About box,
# window title, a screenshot, a bug report, an App Store upload. The later that is
# caught the more confusion it has already caused, so this runs on EVERY build
# rather than only when packaging.
#
#   1. STALE VERSION — MARKETING_VERSION names a release already TAGGED in git and
#      HEAD has moved past that tag.
#   2. UN-ROLLED RELEASE NOTES — the newest tag has no frozen "## Version <tag> "
#      history entry in Documentation/ReleaseNotes.md, so the top {{placeholder}}
#      section still holds that shipped release's notes.
#
# Both are gated on HEAD having moved past the last release, so at the tag itself
# nothing fires: rebuilding, re-notarising or re-signing the release you just cut
# is legitimate work. They fire together on the first commit after a release and
# go quiet as soon as you bump the version and roll the notes — once per release
# cycle, not once per build.
#
# Reports BOTH conditions in one run so they can be fixed in one pass.
#
# OUTPUT: under Xcode this writes "error:" lines to STDOUT, which is the only form
# Xcode turns into a visible issue in the Issue navigator — a script that fails
# with output on stderr shows nothing but an exit code, buried in the build log.
# The notes error is anchored to Documentation/ReleaseNotes.md so the issue is
# clickable. Run from a terminal it prints the full explanation instead.
#
# Skips silently when it cannot evaluate (no git, no tags) so a fresh clone or an
# archive extracted without history still builds. There is deliberately NO
# override: an escape hatch is used once under time pressure and then shipped from.
#
# Called by: the "Check Release Readiness" build phase (every build of the
# GuitarTap target) and Distribution/build_mac.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$ROOT/GuitarTap.xcodeproj/project.pbxproj"
NOTES_REL="Documentation/ReleaseNotes.md"
NOTES="$ROOT/$NOTES_REL"

# XCODE_VERSION_ACTUAL is set only inside an Xcode build environment.
IN_XCODE=0
[ -n "${XCODE_VERSION_ACTUAL:-}" ] && IN_XCODE=1

# Not a git work tree — nothing to compare a version against. `git rev-parse`
# rather than a .git directory test, so a git worktree (where .git is a file) is
# still covered.
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || exit 0

LATEST_TAG="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null)" || exit 0
[ -n "$LATEST_TAG" ] || exit 0

# Nothing developed since the last release: nothing to roll yet.
AHEAD="$(git -C "$ROOT" rev-list --count "${LATEST_TAG}..HEAD" 2>/dev/null || echo 0)"
[ "${AHEAD:-0}" -gt 0 ] || exit 0

# Detail blocks for the terminal / build log, and one-line summaries for Xcode's
# Issue navigator (which shows a single line per issue and no blank lines).
FAILURES=""
SUMMARIES=""

add_summary() { SUMMARIES="${SUMMARIES}${1}
"; }

#===============================================
# 1. Stale version number.
#===============================================
VERSION="$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed -E 's/.*= *([^;]+);.*/\1/' | tr -d ' ')"
if [ -z "$VERSION" ]; then
    FAILURES="${FAILURES}
MARKETING_VERSION could not be read from GuitarTap.xcodeproj/project.pbxproj.
"
    add_summary "error: Release guard: MARKETING_VERSION could not be read from the project file."
elif git -C "$ROOT" rev-parse -q --verify "refs/tags/$VERSION" >/dev/null 2>&1; then
    VERSION_AHEAD="$(git -C "$ROOT" rev-list --count "${VERSION}..HEAD" 2>/dev/null || echo 0)"
    if [ "${VERSION_AHEAD:-0}" -gt 0 ]; then
        FAILURES="${FAILURES}
STALE VERSION NUMBER

  MARKETING_VERSION is $VERSION, which is already released (git tag
  '$VERSION' exists), but HEAD is $VERSION_AHEAD commit(s) newer.

  This build would be labelled as the released $VERSION everywhere it
  appears — About box, window title, DMG name, App Store upload.

  FIX: bump MARKETING_VERSION to the next release number (Xcode: target
       > General > Version, or edit the project file).
       Tag the new version only at release time.
"
        add_summary "error: Stale version: MARKETING_VERSION $VERSION is already released (tag '$VERSION'), but HEAD is $VERSION_AHEAD commit(s) newer. Bump the version in target > General > Version before building."
    fi
fi

#===============================================
# 2. Release notes never rolled over.
#===============================================
if [ ! -f "$NOTES" ]; then
    FAILURES="${FAILURES}
RELEASE NOTES MISSING

  $NOTES_REL could not be read, so the roll-over after $LATEST_TAG
  cannot be verified.
"
    add_summary "error: Release guard: $NOTES_REL is missing, so the roll-over after $LATEST_TAG cannot be verified."
elif ! grep -qE "^## Version ${LATEST_TAG//./\\.} " "$NOTES"; then
    # A frozen entry always reads "## Version <tag> · Build <n>". Requiring the
    # trailing space keeps 1.0.2 from matching 1.0.20.
    SHIPPED_BUILD="$(git -C "$ROOT" rev-list --count "$LATEST_TAG" 2>/dev/null)"
    FAILURES="${FAILURES}
RELEASE NOTES NOT ROLLED OVER after $LATEST_TAG

  $NOTES_REL has no frozen '## Version $LATEST_TAG' history entry, so its
  top {{placeholder}} section still holds $LATEST_TAG's own notes — already
  shipped. The next release would generate its notes from that stale content.

  FIX (see the Documentation/generate-release-notes.sh header):
    1. Freeze the current top section — replace {{version}}/{{build}}/{{since}}
       with the literals $LATEST_TAG shipped as, giving a
       '## Version $LATEST_TAG · Build ${SHIPPED_BUILD:-<n>}' history entry.
    2. Add a fresh top section with {{placeholders}} for the new release.
"
    # Anchored to the file:line so the Issue navigator entry is clickable and
    # lands on the section that has to be frozen.
    add_summary "$NOTES:5: error: Release notes not rolled over after $LATEST_TAG. Freeze this section as '## Version $LATEST_TAG · Build ${SHIPPED_BUILD:-<n>}' and add a fresh {{placeholder}} section above it."
fi

[ -z "$FAILURES" ] && exit 0

BAR="======================================================================"
if [ "$IN_XCODE" = "1" ]; then
    # STDOUT, and "error:"-prefixed — the only combination Xcode promotes to a
    # visible issue. The detail follows as plain log text for whoever opens the
    # full build log.
    printf '%s' "$SUMMARIES"
    echo "$BAR"
    echo "BLOCKED — this tree is not ready for development after a release."
    echo "$FAILURES"
    echo "$BAR"
else
    {
        echo "$BAR"
        echo "BLOCKED — this tree is not ready for development after a release."
        echo "$FAILURES"
        echo "$BAR"
    } >&2
fi
exit 1
