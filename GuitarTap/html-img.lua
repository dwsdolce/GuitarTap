--[[
html-img.lua — make raw HTML <img> tags survive the LaTeX/PDF writer.

The Quick-Start markdown embeds its SF Symbol icons as raw HTML:

    ## <img src="Manual/images/symbols/hand.tap.png" width="24" height="24" alt="hand.tap"> New Tap

which is deliberate: GitHub, VS Code and any other markdown previewer honour the
tag and its pixel dimensions, and so does WeasyPrint (the path the user manual
takes). Pandoc, however, parses it as a RawInline of format "html", and pandoc's
LaTeX writer DISCARDS raw HTML silently. The PDF therefore came out with every
icon missing and no warning of any kind — 29 references, zero images embedded.

This filter rewrites those raw tags into real pandoc Image elements before the
writer runs, so the LaTeX path emits \includegraphics. The markdown itself is not
touched, so every other consumer behaves exactly as before.

Only `width` is carried over. The symbols are square, and giving LaTeX a single
dimension keeps the aspect ratio intact rather than letting a width/height pair
disagree.
]]

function RawInline(el)
  if el.format ~= "html" then return nil end

  local src = el.text:match('<img%s[^>]-src="([^"]+)"')
  if not src then return nil end

  local alt   = el.text:match('alt="([^"]*)"') or ""
  local width = el.text:match('width="(%d+)"')
  local attrs = width and {{"width", width .. "px"}} or {}

  return pandoc.Image({pandoc.Str(alt)}, src, "", pandoc.Attr("", {}, attrs))
end
