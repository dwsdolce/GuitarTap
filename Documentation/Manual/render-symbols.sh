#!/usr/bin/env bash
# render-symbols.sh — Render SF Symbols to PNG files for documentation.
#
# Used by:
#   - GuitarTap/generate-help.sh (Xcode build phase that produces the
#     Quick-Start Guide)
#   - generate-manual.sh (User Manual build)
#   - Manual editors adding new symbols by hand: see "Manual usage" below.
#
# The PNGs land in OUTPUT_DIR; the directory is created if it does not
# exist.  Rendering parameters (canvas 64 px, point size 40, medium
# weight, dark grey palette) match the existing Quick-Start output so
# icons look identical between the two documents.
#
# Usage:
#   bash render-symbols.sh OUTPUT_DIR SYMBOL [SYMBOL ...]
#   bash render-symbols.sh OUTPUT_DIR --from-file SYMBOL_LIST_FILE
#
# Examples:
#   bash render-symbols.sh ../symbols dot.viewfinder plus.viewfinder
#   bash render-symbols.sh ./images/symbols --from-file /tmp/syms.txt
#
# Manual usage — adding a new symbol to the User Manual:
#   cd Documentation/Manual
#   bash render-symbols.sh images/symbols <symbol-name>
#   git add images/symbols/<symbol-name>.png
#
# Requires macOS (uses AppKit + SF Symbols).  The resulting PNGs are
# cross-platform.

set -euo pipefail

if [[ $# -lt 2 ]]; then
    cat >&2 <<EOF
Usage: $0 OUTPUT_DIR SYMBOL [SYMBOL ...]
       $0 OUTPUT_DIR --from-file SYMBOL_LIST_FILE
EOF
    exit 1
fi

OUTPUT_DIR="$1"
shift

mkdir -p "$OUTPUT_DIR"

SYMBOLS=()
if [[ "${1:-}" == "--from-file" ]]; then
    [[ $# -ge 2 ]] || { echo "ERROR: --from-file requires a file path" >&2; exit 1; }
    LIST_FILE="$2"
    [[ -f "$LIST_FILE" ]] || { echo "ERROR: file not found: $LIST_FILE" >&2; exit 1; }
    while IFS= read -r sym; do
        [[ -n "$sym" ]] && SYMBOLS+=("$sym")
    done < "$LIST_FILE"
else
    SYMBOLS=("$@")
fi

if [[ ${#SYMBOLS[@]} -eq 0 ]]; then
    echo "ERROR: no symbols specified" >&2
    exit 1
fi

RENDER_SCRIPT="$(mktemp -t guitar-tap-render-symbols-XXXXXX).swift"
trap 'rm -f "$RENDER_SCRIPT"' EXIT

cat > "$RENDER_SCRIPT" <<'SWEOF'
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: swift render.swift <outputDir> [symbol ...]\n", stderr)
    exit(1)
}
let outputDir = args[1]
let symbols   = Array(args.dropFirst(2))

func renderSymbol(_ name: String,
                  to path: String,
                  canvasSize: Int = 64,
                  pointSize: CGFloat = 40) {
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

swift "$RENDER_SCRIPT" "$OUTPUT_DIR" "${SYMBOLS[@]}"
echo "Rendered ${#SYMBOLS[@]} symbol(s) to $OUTPUT_DIR"
