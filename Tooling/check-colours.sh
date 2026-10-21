#!/bin/bash
# check-colours.sh
#
# Refuses to build when a colour or an opacity is written outside the palette. Mirrors the Python
# edition's src/guitar_tap/_colour_guard.py and the web edition's
# tooling/check-colours.mjs — same rule.
#
# The rule: every colour the app draws is a role in GuitarTap/Views/Utilities/Palette.swift,
# with its own light and dark value. A colour written anywhere else — a Color(red:…)
# literal, a system colour (.blue, .secondary, .accentColor), a material, an NSColor /
# UIColor — does not follow the Appearance setting, or follows the OS instead of it,
# and differs from the Python and web editions.
#
# The same for an opacity: every opacity the app applies is a named one in Palette.swift (shared in theme.json);
# a number in `.opacity(…)` or `opacity:` anywhere else is refused — 0 and 1 (shown / hidden) excepted.
#
# Allowed: Color.clear (no colour), anything inside Palette.swift, and the chart-style opacities in
# ChartStyle.swift (shared in chart-style.json). Comment lines are skipped.
#
# OUTPUT: under Xcode this writes "file:line: error:" lines to STDOUT, which Xcode
# turns into clickable issues; from a terminal it prints them to stderr.
#
# Called by: the "Check Colours" build phase (every build of the GuitarTap target).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/GuitarTap"

IN_XCODE=0
[ -n "${XCODE_VERSION_ACTUAL:-}" ] && IN_XCODE=1

SYSTEM='blue|red|green|orange|yellow|gray|grey|purple|pink|teal|cyan|mint|indigo|brown|black|white|primary|secondary|tertiary|quaternary|accentColor'
MATERIAL='ultraThinMaterial|thinMaterial|regularMaterial|thickMaterial|ultraThickMaterial|bar'
PATTERN="Color\((red|white|hue|hex|sRGB|\.sRGB|displayP3|\.displayP3|nsColor|uiColor|cgColor)\b|Color\.($SYSTEM)\b|\(\.($SYSTEM|$MATERIAL)\)|NSColor\.|UIColor\.|CGColor\("

OPACITY='\.opacity\([^)]*\b0?\.[0-9]*[1-9]|[Oo]pacity:[[:space:]]*0?\.[0-9]*[1-9]'

FOUND="$( { grep -rnE "$PATTERN" "$SRC" --include='*.swift'
            grep -rnE "$OPACITY" "$SRC" --include='*.swift' | grep -v '/Views/Utilities/ChartStyle.swift:'; } \
    | grep -v '/Views/Utilities/Palette.swift:' \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//')"

[ -z "$FOUND" ] && exit 0

if [ "$IN_XCODE" = "1" ]; then
    while IFS= read -r line; do
        file="${line%%:*}"; rest="${line#*:}"; num="${rest%%:*}"; text="${rest#*:}"
        echo "$file:$num: error: Colour or opacity outside the palette — use a Palette role or opacity: $(echo "$text" | sed -E 's/^[[:space:]]+//')"
    done <<< "$FOUND"
else
    {
        echo "BLOCKED — a colour or an opacity is written outside the palette (GuitarTap/Views/Utilities/Palette.swift):"
        echo "$FOUND" | sed "s|^$ROOT/||"
    } >&2
fi
exit 1
