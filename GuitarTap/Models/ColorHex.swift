//
//  ColorHex.swift
//  GuitarTap
//
//  Builds a SwiftUI `Color` from an absolute sRGB hex string.
//
//  Display colours in GuitarTap are absolute, not semantic. A semantic colour (`.blue`) is
//  resolved by the OS, so what the app draws changes when Apple revises the system palette —
//  macOS 26 did, moving `.blue` from #007AFF to #0088FF and `.orange` from #FF9500 to #FF8D28.
//  Python and the web pin hex and cannot follow that, so the three editions silently stopped
//  agreeing on the same white surface. See `WoodQuality.hex` for the full account.
//
//  Hue carries no meaning in this app — a colour only has to separate values and be the same
//  everywhere — so fixing the value costs nothing and makes cross-edition parity testable.
//  The theme work owns *scheme selection*, a second table for dark surfaces;
//  it does not change the fact that each entry is an absolute value.
//
//  No counterpart: Python and TypeScript take hex strings directly.
// @parity none

import SwiftUI

extension Color {

    /// A colour from an absolute sRGB hex string, `"#RRGGBB"` or `"RRGGBB"`.
    ///
    /// Malformed input yields black rather than trapping: these strings are compile-time
    /// constants in this codebase, so a bad one is a build-time typo that the paired
    /// `test/quality-colors` and `test/mode-colors` suites catch by comparing the hex itself.
    init(sRGBHex hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt32(cleaned, radix: 16) ?? 0
        self.init(
            .sRGB,
            red:   Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8)  & 0xFF) / 255.0,
            blue:  Double(value         & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}
