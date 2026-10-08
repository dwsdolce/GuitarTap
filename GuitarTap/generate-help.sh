#!/usr/bin/env bash
# generate-help.sh
# Extracts help content from HelpView.swift into Markdown, then converts to PDF via pandoc/xelatex.
#
# Usage:  bash generate-help.sh
#
# Prerequisites (one-time):
#   brew install pandoc
#   brew install --cask basictex   # provides xelatex
#   # After basictex: sudo tlmgr update --self && sudo tlmgr install collection-fontsrecommended

set -euo pipefail

# Ensure Homebrew tools are on PATH (needed when invoked from Xcode build phases
# or other non-interactive shells that don't source the user profile)
# Add Homebrew and any installed TeX Live to PATH
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
for _texbin in /usr/local/texlive/*/bin/universal-darwin /usr/local/texlive/*/bin/arm64-darwin; do
    [ -d "$_texbin" ] && export PATH="$_texbin:$PATH"
done
unset _texbin

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFT_SOURCE="$SCRIPT_DIR/Views/HelpView.swift"
# BOTH OUTPUTS ARE GITIGNORED BUILD ARTIFACTS (.gitignore:47-48), untracked since
# ee1e4c5. So `git status` says nothing about them after a run — and that silence means
# "ignored", NOT "unchanged". Do not read a clean status as evidence that a change to
# HelpView.swift left the generated docs alone; diff the file or read it. A commit
# message in this repo (16474b2) claims the regenerated markdown was "byte-identical to
# the committed copy" — there is no committed copy, and the claim is false.
OUTPUT_MD="$SCRIPT_DIR/../Documentation/GuitarTap-Quick-Start-Guide.md"
OUTPUT_PDF="$SCRIPT_DIR/../Documentation/GuitarTap-Quick-Start-Guide.pdf"

# Persistent SF Symbol PNG cache.  Shared with the User Manual build
# (Documentation/Manual/generate-manual.sh) and committed to git so the
# Quick-Start markdown renders correctly on a fresh clone without an
# Xcode build.  Render-symbols.sh writes PNGs here.
#
# Two paths are needed:
#   SYMBOL_OUTPUT_DIR  — absolute path where PNGs are written.
#   SYMBOL_MD_PATH     — path embedded in the Quick-Start markdown's
#                        ![](…) tags, expressed RELATIVE to OUTPUT_MD's
#                        directory (Documentation/).  Pandoc resolves
#                        relative image paths against the markdown's
#                        directory.
SYMBOL_OUTPUT_DIR="$SCRIPT_DIR/../Documentation/Manual/images/symbols"
SYMBOL_MD_PATH="Manual/images/symbols"
SYMBOLS_LIST_FILE="$(mktemp -t guitar-tap-symbols-list-XXXXXX).txt"
RENDER_SYMBOLS_SCRIPT="$SCRIPT_DIR/../Documentation/Manual/render-symbols.sh"

if [ ! -f "$SWIFT_SOURCE" ]; then
    echo "ERROR: HelpView.swift not found at $SWIFT_SOURCE" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_MD")"

# ---------------------------------------------------------------------------
# Step 1: Parse HelpView.swift → Markdown
# ---------------------------------------------------------------------------

python3 - "$SWIFT_SOURCE" "$SYMBOL_MD_PATH" "$SYMBOLS_LIST_FILE" > "$OUTPUT_MD" <<'PYEOF'
import sys
import re

source_path  = sys.argv[1]
symbol_dir   = sys.argv[2]
symbols_file = sys.argv[3]

with open(source_path, 'r') as f:
    text = f.read()

# ---------------------------------------------------------------------------
# Strategy: SwiftUI Section { content } header: { Label("Title") } puts
# content BEFORE the header syntactically. We buffer each section's rows,
# then flush them after we see the } header: { Label(...) } line.
#
# Sections: [(title, section_symbol, [row_chunks])]
# A row_chunk is a plain string (body paragraph) or a tuple
# (row_title, row_body, ios_only, macos_only, [system_images]).
# ---------------------------------------------------------------------------

lines = text.splitlines()

platform  = 'all'   # 'all' | 'ios_only' | 'macos_only'
ios_depth = 0

accumulating = False
accum_buf    = ""
pending_rows = []
sections     = []
all_symbols  = set()  # collected for the PNG rendering step

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def extract_label_info(line):
    """Return (title, systemImage) from a Label("Title", systemImage: "name") call."""
    title_m = re.search(r'Label\s*\(\s*"([^"]+)"', line)
    title   = title_m.group(1) if title_m else None
    sym_m   = re.search(r'systemImage\s*:\s*"([^"]+)"', line)
    sym     = sym_m.group(1) if sym_m else None
    return title, sym

def process_help_row(raw):
    title_m = re.search(r'title\s*:\s*"((?:[^"\\]|\\.)*)"', raw)
    title   = title_m.group(1) if title_m else None

    body_tq = re.search(r'body\s*:\s*"""(.*?)"""', raw, re.DOTALL)
    if body_tq:
        body = body_tq.group(1).strip()
    else:
        body_sq = re.search(r'body\s*:\s*"((?:[^"\\]|\\.)*)"', raw)
        body    = body_sq.group(1) if body_sq else None

    # Extract systemImages: ["a", "b", ...]
    sim_m = re.search(r'systemImages\s*:\s*\[([^\]]*)\]', raw, re.DOTALL)
    system_images = re.findall(r'"([^"]+)"', sim_m.group(1)) if sim_m else []

    if title and body:
        title = title.replace('\\"', '"').replace('\\\\', '\\').replace('\\n', '\n')
        body  = body.replace('\\"', '"').replace('\\\\', '\\').replace('\\n', '\n')
        body  = re.sub(r'\\\n\s*', '', body)
        return title, body, system_images
    return None, None, []

def bullets_to_markdown(text):
    """Convert lines starting with • into Markdown list items."""
    result = []
    for line in text.split('\n'):
        result.append('- ' + line[1:].lstrip() if line.startswith('•') else line)
    return '\n'.join(result)

def img_tag(sym, height):
    # Emit a raw HTML <img> tag so it renders correctly in any markdown
    # previewer (GitHub, VS Code, etc.).  The size is given in pixels
    # (pt × 4/3) so the previewer respects it as a legacy HTML width/height
    # attribute; WeasyPrint (the manual) honours the same attributes.
    #
    # Pandoc does NOT: it parses this as raw inline HTML and its LaTeX writer
    # discards raw HTML silently, which left every icon out of the Quick-Start
    # PDF with no warning.  html-img.lua converts these tags back into real
    # pandoc Images for the PDF pass — see that file.  Do not assume a writer
    # honours an HTML attribute just because a browser does.
    px = int(round(height * 4 / 3))
    return f'<img src="{symbol_dir}/{sym}.png" width="{px}" height="{px}" alt="{sym}">'

def img_prefix(symbols, height):
    """Inline image tags for a list of symbols, followed by a space."""
    if not symbols:
        return ""
    return " ".join(img_tag(s, height) for s in symbols) + " "

# ---------------------------------------------------------------------------
# Parse
# ---------------------------------------------------------------------------

i = 0
while i < len(lines):
    line     = lines[i]
    stripped = line.strip()

    # Platform conditionals
    if stripped.startswith('#if os(iOS)'):
        platform = 'ios_only'; ios_depth += 1; i += 1; continue
    if stripped.startswith('#elseif os(macOS)') and ios_depth > 0:
        platform = 'macos_only'; i += 1; continue
    if stripped.startswith('#else') and ios_depth > 0:
        platform = 'macos_only'; i += 1; continue
    if stripped.startswith('#endif') and ios_depth > 0:
        ios_depth -= 1
        if ios_depth == 0:
            platform = 'all'
        i += 1; continue

    # Section header — flush pending_rows now that we know the title
    if stripped.startswith('} header:'):
        section_title = section_symbol = None
        for j in range(i, min(i + 5, len(lines))):
            t, s = extract_label_info(lines[j])
            if t:
                section_title, section_symbol = t, s
                break
        if section_title:
            if section_symbol:
                all_symbols.add(section_symbol)
            sections.append((section_title, section_symbol, pending_rows))
        pending_rows = []
        i += 1; continue

    # helpRow — may span multiple lines
    if 'helpRow(' in stripped and not accumulating:
        accumulating = True
        accum_buf    = line
        depth        = accum_buf.count('(') - accum_buf.count(')')
        if depth <= 0 and '"""' not in accum_buf:
            title, body, sim = process_help_row(accum_buf)
            if title:
                all_symbols.update(sim)
                pending_rows.append((title, body,
                                     platform == 'ios_only',
                                     platform == 'macos_only',
                                     sim))
            accumulating = False; accum_buf = ""
        i += 1; continue

    if accumulating:
        accum_buf += "\n" + line
        tq_count   = accum_buf.count('"""')
        in_triple  = (tq_count % 2 == 1)
        if not in_triple:
            depth = accum_buf.count('(') - accum_buf.count(')')
            if depth <= 0:
                title, body, sim = process_help_row(accum_buf)
                if title:
                    all_symbols.update(sim)
                    pending_rows.append((title, body,
                                         platform == 'ios_only',
                                         platform == 'macos_only',
                                         sim))
                accumulating = False; accum_buf = ""
        i += 1; continue

    # Plain Text("""...""") — the overview paragraph in "What Guitar Tap Does"
    if stripped.startswith('Text("""') and not accumulating:
        buf = line
        while '"""' not in buf[buf.index('"""')+3:]:
            i += 1
            buf += "\n" + lines[i]
        m = re.search(r'Text\s*\(\s*"""(.*?)"""', buf, re.DOTALL)
        if m:
            body = m.group(1).strip()
            body = re.sub(r'\\\n\s*', '', body)
            pending_rows.append(body)
        i += 1; continue

    i += 1

# ---------------------------------------------------------------------------
# Write symbols list for the Swift rendering step
# ---------------------------------------------------------------------------
with open(symbols_file, 'w') as sf:
    sf.write('\n'.join(sorted(all_symbols)) + '\n')

# ---------------------------------------------------------------------------
# Render Markdown
# ---------------------------------------------------------------------------

out = []
out.append("# GuitarTap Quick Start Guide")
out.append("")

for section_title, section_symbol, rows in sections:
    sec_prefix = img_prefix([section_symbol], 18) if section_symbol else ""
    out.append(f"## {sec_prefix}{section_title}")
    out.append("")
    for row in rows:
        if isinstance(row, str):
            out.append(bullets_to_markdown(row))
            out.append("")
        else:
            row_title, body, ios_only, macos_only, sim = row
            suffix     = " *(iOS only)*" if ios_only else (" *(macOS only)*" if macos_only else "")
            row_prefix = img_prefix(sim, 14)
            out.append(f"### {row_prefix}{row_title}{suffix}")
            out.append("")
            out.append(bullets_to_markdown(body))
            out.append("")

print("\n".join(out))
PYEOF

echo "Markdown written to $OUTPUT_MD"

# ---------------------------------------------------------------------------
# Step 1b: Render SF Symbol PNGs for inline icons
# ---------------------------------------------------------------------------
# Delegated to Documentation/Manual/render-symbols.sh so the User Manual
# build can use the same code path and identical rendering parameters.

if [ -f "$SYMBOLS_LIST_FILE" ] && [ -s "$SYMBOLS_LIST_FILE" ]; then
    echo "Rendering SF Symbol PNGs to $SYMBOL_OUTPUT_DIR ..."
    bash "$RENDER_SYMBOLS_SCRIPT" "$SYMBOL_OUTPUT_DIR" --from-file "$SYMBOLS_LIST_FILE"
    rm -f "$SYMBOLS_LIST_FILE"
else
    echo "No symbols list found — skipping symbol rendering."
fi

# ---------------------------------------------------------------------------
# Step 2: Convert Markdown → PDF via pandoc + xelatex
# ---------------------------------------------------------------------------

if command -v pandoc &>/dev/null; then
    # LaTeX header: use Arial Unicode MS (ships with macOS) as a fallback font
    # for the Unicode characters Helvetica Neue doesn't cover (arrows, modifiers, etc.)
    rm -f /tmp/guitar-tap-help-*.tex
    LATEX_HEADER="$(mktemp /tmp/guitar-tap-help-XXXXXX.tex)"
    cat > "$LATEX_HEADER" <<'TEXEOF'
\usepackage{fontspec}
\usepackage{newunicodechar}
\newfontfamily\unicodefallback{Arial Unicode MS}[Scale=MatchLowercase]
\DeclareTextFontCommand{\textuf}{\unicodefallback}
% A SECOND fallback: Arial Unicode MS is broad but lacks U+26A0 WARNING SIGN, and a
% fallback font that silently lacks the character it was chosen for fails exactly as
% loudly as no fallback at all — i.e. not at all, beyond one "Missing character" line.
% Apple Symbols has it. Probed against the installed fonts, not assumed.
\newfontfamily\symbolfallback{Apple Symbols}[Scale=MatchLowercase]
\DeclareTextFontCommand{\textsym}{\symbolfallback}
\newunicodechar{→}{\textuf{→}}
\newunicodechar{⇧}{\textuf{⇧}}
\newunicodechar{⌘}{\textuf{⌘}}
\newunicodechar{⌥}{\textuf{⌥}}
\newunicodechar{⌃}{\textuf{⌃}}
\newunicodechar{↺}{\textuf{↺}}
\newunicodechar{ⓘ}{\textuf{ⓘ}}
\newunicodechar{•}{\textuf{•}}
\newunicodechar{≈}{\textuf{≈}}
\newunicodechar{÷}{\textuf{÷}}
\newunicodechar{–}{\textuf{–}}
\newunicodechar{√}{\textuf{√}}
\newunicodechar{⋯}{\textuf{⋯}}
\newunicodechar{⚠}{\textsym{⚠}}
% U+FE0F VARIATION SELECTOR-16 asks for emoji presentation of the preceding
% character. It is a modifier, not a glyph: xelatex has nothing to draw for it and
% warns "Missing character". Map it to nothing so the warning sign above renders in
% its text form and the selector disappears silently, as it should. Written in TeX
% ^^^^ notation because the literal character is invisible in an editor.
\newunicodechar{^^^^fe0f}{}
TEXEOF

    # Resource path is the markdown's own directory so relative image
    # paths like Manual/images/symbols/<sym>.png resolve correctly
    # regardless of the caller's working directory.
    pandoc "$OUTPUT_MD" \
        --resource-path="$(dirname "$OUTPUT_MD")" \
        --from=markdown+link_attributes \
        --to=pdf \
        --pdf-engine=xelatex \
        --variable "geometry:top=1in, bottom=1in, left=1.1in, right=1in" \
        --variable "fontsize=11pt" \
        --variable "mainfont=Helvetica Neue" \
        --variable "sansfont=Helvetica Neue" \
        --variable "monofont=Menlo" \
        --variable "colorlinks=true" \
        --variable "linkcolor=NavyBlue" \
        --include-in-header="$LATEX_HEADER" \
        --lua-filter="$SCRIPT_DIR/html-img.lua" \
        -o "$OUTPUT_PDF"
    rm -f "$LATEX_HEADER"
    echo "PDF written to $OUTPUT_PDF"
else
    echo "pandoc not found — skipping PDF generation."
    echo "Install with: brew install pandoc  (and brew install --cask basictex for xelatex)"
fi

# ---------------------------------------------------------------------------
# Step 3: Release notes — generate the stamped PDF from Documentation/ReleaseNotes.md on the
# same macOS build (cheap: plain pandoc, the notes carry no icons). That script is best-effort
# and skips gracefully on its own; `|| true` also shields this script's `set -e`, so a
# release-notes hiccup never fails the build.
# ---------------------------------------------------------------------------
bash "$SCRIPT_DIR/../Documentation/generate-release-notes.sh" || true
