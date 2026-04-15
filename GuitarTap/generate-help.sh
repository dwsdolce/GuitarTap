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
OUTPUT_MD="$SCRIPT_DIR/../Documentation/GuitarTap-Quick-Start-Guide.md"
OUTPUT_PDF="$SCRIPT_DIR/../Documentation/GuitarTap-Quick-Start-Guide.pdf"
SYMBOL_DIR="/tmp/guitar-tap-symbols"
SYMBOLS_LIST_FILE="/tmp/guitar-tap-symbols-list.txt"
RENDER_SCRIPT="/tmp/guitar-tap-render-symbols.swift"

if [ ! -f "$SWIFT_SOURCE" ]; then
    echo "ERROR: HelpView.swift not found at $SWIFT_SOURCE" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_MD")"

# ---------------------------------------------------------------------------
# Step 1: Parse HelpView.swift → Markdown
# ---------------------------------------------------------------------------

python3 - "$SWIFT_SOURCE" "$SYMBOL_DIR" "$SYMBOLS_LIST_FILE" > "$OUTPUT_MD" <<'PYEOF'
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
    return f"![]({symbol_dir}/{sym}.png){{height={height}pt width={height}pt}}"

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
out.append("# GuitarTap Quick-Start Guide")
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

if [ -f "$SYMBOLS_LIST_FILE" ] && [ -s "$SYMBOLS_LIST_FILE" ]; then
    echo "Rendering SF Symbol PNGs to $SYMBOL_DIR ..."
    mkdir -p "$SYMBOL_DIR"

    cat > "$RENDER_SCRIPT" << 'SWEOF'
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: swift render.swift <outputDir> [symbol ...]\n", stderr)
    exit(1)
}
let outputDir = args[1]
let symbols   = Array(args.dropFirst(2))

func renderSymbol(_ name: String, to path: String, canvasSize: Int = 64, pointSize: CGFloat = 40) {
    let sizeConfig  = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
    let colorConfig = NSImage.SymbolConfiguration(paletteColors: [
        NSColor(calibratedRed: 0.333, green: 0.333, blue: 0.333, alpha: 1.0)
    ])
    let config = sizeConfig.applying(colorConfig)
    guard let sym        = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let configured = sym.withSymbolConfiguration(config) else {
        fputs("WARNING: Symbol not found: \(name)\n", stderr)
        return
    }
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: canvasSize, pixelsHigh: canvasSize,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
    let drawSize = CGFloat(canvasSize) * 0.80
    let origin   = (CGFloat(canvasSize) - drawSize) / 2.0
    configured.draw(in: NSRect(x: origin, y: origin, width: drawSize, height: drawSize),
                    from: .zero, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.current = nil
    if let pngData = rep.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: path))
    }
}

for symbol in symbols {
    renderSymbol(symbol, to: (outputDir as NSString).appendingPathComponent("\(symbol).png"))
}
SWEOF

    SYMS_ARR=()
    while IFS= read -r sym; do
        [[ -n "$sym" ]] && SYMS_ARR+=("$sym")
    done < "$SYMBOLS_LIST_FILE"

    if [ ${#SYMS_ARR[@]} -gt 0 ]; then
        swift "$RENDER_SCRIPT" "$SYMBOL_DIR" "${SYMS_ARR[@]}"
        echo "Rendered ${#SYMS_ARR[@]} symbols to $SYMBOL_DIR"
    fi
    rm -f "$RENDER_SCRIPT"
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
TEXEOF

    pandoc "$OUTPUT_MD" \
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
        -o "$OUTPUT_PDF"
    rm -f "$LATEX_HEADER"
    echo "PDF written to $OUTPUT_PDF"
else
    echo "pandoc not found — skipping PDF generation."
    echo "Install with: brew install pandoc  (and brew install --cask basictex for xelatex)"
fi
