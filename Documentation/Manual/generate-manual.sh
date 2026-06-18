#!/usr/bin/env bash
# generate-manual.sh — Build GuitarTap User Manual (HTML and PDF)
#
# Outputs (X.Y is the MARKETING_VERSION read from the Xcode project):
#   GuitarTap-User-Manual-X.Y.html   — full HTML with sticky nav sidebar
#   GuitarTap-User-Manual-X.Y.pdf    — PDF with bookmark tree and TOC page
#
# Requirements:
#   - Python 3 venv at ../../.venv (relative to this script)
#     with weasyprint installed (see ../../requirements-docs.txt)
#   - Pango native library (brew install pango on macOS)
#
# macOS note: python.org Python cannot find Homebrew's libgobject/libpango
# without DYLD_FALLBACK_LIBRARY_PATH set (handled automatically below).
#
# Usage:
#   cd Documentation/Manual && bash generate-manual.sh
#   bash Documentation/Manual/generate-manual.sh   (from repo root)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VENV_PYTHON="$REPO_ROOT/.venv/bin/python3"
OUTPUT_DIR="$SCRIPT_DIR"

# Pull MARKETING_VERSION from the Xcode project so the manual filenames and
# title-page version stay in lock-step with the app's marketing version.
# The pbxproj has one entry per build configuration; both are kept equal so
# the first match is sufficient.
PBXPROJ="$REPO_ROOT/GuitarTap.xcodeproj/project.pbxproj"
MARKETING_VERSION="$(grep -m1 "MARKETING_VERSION" "$PBXPROJ" | sed 's/.*= //; s/;.*//' | tr -d ' ')"
if [[ -z "$MARKETING_VERSION" ]]; then
    echo "ERROR: Could not read MARKETING_VERSION from $PBXPROJ" >&2
    exit 1
fi
echo "Marketing version: $MARKETING_VERSION"

# macOS: ensure Homebrew libs are found by python.org Python
export DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew/lib:${DYLD_FALLBACK_LIBRARY_PATH:-}"

# Verify venv exists
if [[ ! -x "$VENV_PYTHON" ]]; then
    echo "ERROR: Python venv not found at $VENV_PYTHON" >&2
    echo "       Run: python3.14 -m venv .venv && .venv/bin/pip install -r requirements-docs.txt" >&2
    exit 1
fi

# Chapter files in order (ch00 is handled separately as a raw HTML fragment)
CHAPTERS=(
    "ch01-introduction.md"
    "ch02-getting-started.md"
    "ch03-guitar-mode.md"
    "ch04-plate-mode.md"
    "ch05-brace-mode.md"
    "ch06-spectrum.md"
    "ch07-save-export-share.md"
    "ch08-settings-reference.md"
    "ch09-controls-reference.md"
    "ch10-tips-and-troubleshooting.md"
    "ch11-glossary.md"
    "app-a-keyboard-shortcuts.md"
    "app-b-file-formats.md"
)

# Concatenate existing chapter files (skip missing stubs gracefully)
COMBINED="$SCRIPT_DIR/_combined.md"
> "$COMBINED"
for chapter in "${CHAPTERS[@]}"; do
    fpath="$SCRIPT_DIR/$chapter"
    if [[ -f "$fpath" ]]; then
        cat "$fpath" >> "$COMBINED"
        printf '\n\n' >> "$COMBINED"
    else
        echo "WARNING: Chapter file not found, skipping: $chapter" >&2
    fi
done

echo "Generating navigation and TOC..."

# Python pre-pass: extract headings → nav.html + ch00-toc.html + add ids to combined MD
"$VENV_PYTHON" - "$COMBINED" "$SCRIPT_DIR/nav.html" "$SCRIPT_DIR/ch00-toc.html" <<'PYEOF'
import sys, re, unicodedata, html

combined_path = sys.argv[1]
nav_path      = sys.argv[2]
toc_path      = sys.argv[3]

def slugify(text):
    text = unicodedata.normalize('NFKD', text)
    text = text.encode('ascii', 'ignore').decode('ascii')
    text = re.sub(r'[^\w\s-]', '', text).strip().lower()
    text = re.sub(r'[\s_-]+', '-', text)
    return text

with open(combined_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

headings = []  # (level, text, slug)
out_lines = []

for line in lines:
    m = re.match(r'^(#{1,3})\s+(.*)', line.rstrip('\n'))
    if m:
        level = len(m.group(1))
        text  = m.group(2).strip()
        slug  = slugify(text)
        headings.append((level, text, slug))
        # Emit heading with id anchor
        out_lines.append(f'<h{level} id="{slug}">{html.escape(text)}</h{level}>\n')
    else:
        out_lines.append(line)

# Write back modified combined (headings replaced with HTML so ids are preserved)
with open(combined_path, 'w', encoding='utf-8') as f:
    f.writelines(out_lines)

# --- Build nav.html ---
nav_lines = ['<nav id="sidebar">\n', '<ul>\n']
current_h1 = None
current_h2 = None

for level, text, slug in headings:
    escaped = html.escape(text)
    if level == 1:
        if current_h2 is not None:
            nav_lines.append('  </ul></li>\n')
            current_h2 = None
        if current_h1 is not None:
            nav_lines.append('</ul></li>\n')
        nav_lines.append(f'<li class="nav-h1"><a href="#{slug}">{escaped}</a>\n<ul>\n')
        current_h1 = slug
    elif level == 2:
        if current_h2 is not None:
            nav_lines.append('  </ul></li>\n')
        nav_lines.append(f'  <li class="nav-h2"><a href="#{slug}">{escaped}</a>\n  <ul>\n')
        current_h2 = slug
    elif level == 3:
        nav_lines.append(f'    <li class="nav-h3"><a href="#{slug}">{escaped}</a></li>\n')

if current_h2 is not None:
    nav_lines.append('  </ul></li>\n')
if current_h1 is not None:
    nav_lines.append('</ul></li>\n')
nav_lines.append('</ul>\n</nav>\n')

with open(nav_path, 'w', encoding='utf-8') as f:
    f.writelines(nav_lines)

# --- Build ch00-toc.html (PDF TOC page) ---
toc_lines = [
    '<div id="toc-page">\n',
    '<h1 class="toc-title">Contents</h1>\n',
    '<ul class="toc-list">\n',
]
for level, text, slug in headings:
    escaped = html.escape(text)
    cls = f'toc-h{level}'
    toc_lines.append(
        f'  <li class="{cls}"><a href="#{slug}">{escaped}'
        f'<span class="toc-page-num"></span></a></li>\n'
    )
toc_lines += ['</ul>\n', '</div>\n']

with open(toc_path, 'w', encoding='utf-8') as f:
    f.writelines(toc_lines)

print(f"  Found {len(headings)} headings.")
PYEOF

echo "Converting Markdown to HTML body..."

# Convert combined Markdown → HTML body using Python's markdown module if available,
# or fall back to a simple pandoc call, or built-in cmark.
# We prefer the Python markdown module (in the venv) for consistency.

HTML_BODY="$SCRIPT_DIR/_body.html"

"$VENV_PYTHON" - "$COMBINED" "$HTML_BODY" <<'PYEOF'
import sys

combined_path = sys.argv[1]
body_path     = sys.argv[2]

with open(combined_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Try Python Markdown library
try:
    import markdown
    body = markdown.markdown(
        content,
        extensions=['tables', 'fenced_code', 'toc', 'attr_list'],
        output_format='html'
    )
    with open(body_path, 'w', encoding='utf-8') as f:
        f.write(body)
    print("  Used Python Markdown library.")
    sys.exit(0)
except ImportError:
    pass

# Fall back: content is already partially HTML (headings converted by pre-pass),
# emit as-is (WeasyPrint will parse the HTML headings; raw MD paragraphs render as text).
# For production use, install markdown: .venv/bin/pip install markdown
with open(body_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("  WARNING: Python 'markdown' package not found. Install it for proper rendering.")
print("           .venv/bin/pip install markdown")
PYEOF

echo "Assembling full HTML document..."

NAV_HTML="$SCRIPT_DIR/nav.html"
TOC_HTML="$SCRIPT_DIR/ch00-toc.html"
TITLE_PAGE="$SCRIPT_DIR/ch00-front-matter.md"
FULL_HTML="$OUTPUT_DIR/GuitarTap-User-Manual-${MARKETING_VERSION}.html"
CSS_PATH="$SCRIPT_DIR/manual.css"

# Assemble the full HTML page
"$VENV_PYTHON" - "$NAV_HTML" "$TOC_HTML" "$TITLE_PAGE" "$HTML_BODY" "$CSS_PATH" "$FULL_HTML" "$MARKETING_VERSION" <<'PYEOF'
import sys, os

nav_path          = sys.argv[1]
toc_path          = sys.argv[2]
title_page_path   = sys.argv[3]
body_path         = sys.argv[4]
css_path          = sys.argv[5]
out_path          = sys.argv[6]
marketing_version = sys.argv[7]

def read(p):
    if os.path.exists(p):
        with open(p, encoding='utf-8') as f:
            return f.read()
    return ''

nav_html        = read(nav_path)
toc_html        = read(toc_path)
title_page_html = read(title_page_path)   # raw HTML fragment, not Markdown-processed
title_page_html = title_page_html.replace('{{VERSION}}', marketing_version)
body_html       = read(body_path)

# Inline CSS so the HTML file is self-contained
css = read(css_path)
style_block = f'<style>\n{css}\n</style>' if css else ''

html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>GuitarTap User Manual</title>
  {style_block}
</head>
<body>
  <div id="layout">
    {nav_html}
    <main id="content">
      {title_page_html}
      {toc_html}
      {body_html}
    </main>
  </div>
</body>
</html>
"""

with open(out_path, 'w', encoding='utf-8') as f:
    f.write(html)
print(f"  Written: {out_path}")
PYEOF

echo "Generating redirect index.html (points to latest version)..."

# Stable public URL: .../manual/ resolves to index.html, which redirects to the
# version-matched manual file. Keeps the App Store support link neutral to the
# latest release without code or link changes.
INDEX_OUT="$OUTPUT_DIR/index.html"
MANUAL_FILE="GuitarTap-User-Manual-${MARKETING_VERSION}.html"
cat > "$INDEX_OUT" <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Guitar Tap — User Manual</title>
<!-- Generated by generate-manual.sh; redirect target tracks MARKETING_VERSION. -->
<meta http-equiv="refresh" content="0; url=${MANUAL_FILE}">
<link rel="canonical" href="${MANUAL_FILE}">
<style>
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    line-height: 1.6; max-width: 40rem; margin: 4rem auto; padding: 0 1.25rem;
    color: #1d1d1f; text-align: center;
  }
  a { color: #0066cc; }
</style>
</head>
<body>
<p>Redirecting to the Guitar Tap User Manual&hellip;</p>
<p>If you are not redirected automatically,
   <a href="${MANUAL_FILE}">open the User Manual</a>.</p>
<script>location.replace("${MANUAL_FILE}");</script>
</body>
</html>
HTMLEOF
echo "  Written: $INDEX_OUT (-> $MANUAL_FILE)"

echo "Generating PDF via WeasyPrint..."

PDF_OUT="$OUTPUT_DIR/GuitarTap-User-Manual-${MARKETING_VERSION}.pdf"

"$VENV_PYTHON" - "$FULL_HTML" "$PDF_OUT" <<'PYEOF'
import sys
from weasyprint import HTML, CSS

html_path = sys.argv[1]
pdf_path  = sys.argv[2]

print(f"  Input:  {html_path}")
print(f"  Output: {pdf_path}")

HTML(filename=html_path).write_pdf(pdf_path)
print("  PDF written successfully.")
PYEOF

# Stable "latest" copies so published download links never go stale across
# version bumps. The versioned files are kept alongside them for history; the
# website links point at these neutral names.
LATEST_HTML="$OUTPUT_DIR/GuitarTap-User-Manual.html"
LATEST_PDF="$OUTPUT_DIR/GuitarTap-User-Manual.pdf"
cp "$FULL_HTML" "$LATEST_HTML"
cp "$PDF_OUT" "$LATEST_PDF"
echo "Wrote latest-pointer copies:"
echo "  $LATEST_HTML"
echo "  $LATEST_PDF"

# Clean up intermediary files
rm -f "$COMBINED" "$HTML_BODY" "$NAV_HTML" "$TOC_HTML"   # ch00-front-matter.md is a source file, not cleaned up

echo ""
echo "Done."
echo "  HTML:        $FULL_HTML"
echo "  PDF:         $PDF_OUT"
echo "  Latest HTML: $LATEST_HTML"
echo "  Latest PDF:  $LATEST_PDF"
