#!/usr/bin/env python3
"""embed-images.py — make a generated manual HTML self-contained.

Rewrites every ``<img src="images/…">`` reference in the HTML as an inline base64
``data:`` URI, so the deployed HTML needs no ``images/`` folder alongside it. This is what
lets each versioned manual be a permanent, correct snapshot (like the PDF already is): a later
release can overwrite the shared source screenshots without changing what an older HTML shows.

Screenshots AND the SF-Symbol inline icons are both under ``images/``, so both get embedded.
The CSS is already inlined by generate-manual.sh and references no images.

Usage:
    embed-images.py <html-file> [base-dir]

Rewrites <html-file> in place. Image paths resolve relative to <base-dir> (default: the HTML
file's own directory, which is how the manual build runs it).
"""
import base64
import mimetypes
import os
import re
import sys

html_path = sys.argv[1]
base_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(os.path.abspath(html_path))

with open(html_path, encoding="utf-8") as f:
    html = f.read()

cache: dict[str, str | None] = {}


def data_uri(rel_path: str) -> str | None:
    if rel_path in cache:
        return cache[rel_path]
    full = os.path.join(base_dir, rel_path)
    if not os.path.isfile(full):
        print(f"  WARN: image not found, leaving external: {rel_path}", file=sys.stderr)
        cache[rel_path] = None
        return None
    mime = mimetypes.guess_type(full)[0] or "application/octet-stream"
    with open(full, "rb") as im:
        b64 = base64.b64encode(im.read()).decode("ascii")
    uri = f"data:{mime};base64,{b64}"
    cache[rel_path] = uri
    return uri


def replace(m: "re.Match[str]") -> str:
    quote, path = m.group(1), m.group(2)
    uri = data_uri(path)
    return m.group(0) if uri is None else f"src={quote}{uri}{quote}"


# Only src="images/…" / src='images/…' — HTML comments like "File: images/…" have no src= and are left alone.
new_html = re.sub(r"""src=(["'])(images/[^"']+)\1""", replace, html)

with open(html_path, "w", encoding="utf-8") as f:
    f.write(new_html)

inlined = sum(1 for v in cache.values() if v)
print(f"embed-images.py: inlined {inlined}/{len(cache)} images in {os.path.basename(html_path)}")
