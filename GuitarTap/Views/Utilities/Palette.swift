//
//  Palette.swift
//  GuitarTap
//
// @parity view/palette tests=test/analysis-quality
//
// The app's fixed colours: each has one light value and one dark value, chosen by the colour scheme.
// They are pinned rather than taken from the system's semantic colours, which change between OS
// releases, so every edition shows the same colours on every OS. The colour only tells values apart;
// the exact shade does not matter, but it must be the same everywhere. A PDF is drawn in the light
// scheme, so it prints the light values.

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Palette {
    /// A colour's two values, as 0xRRGGBB.
    struct Pair: Equatable {
        let light: UInt32
        let dark: UInt32
    }

    static let grayPair = Pair(light: 0x8E8E93, dark: 0x8E8E93)
    static let orangePair = Pair(light: 0xFF9500, dark: 0xFF9F0A)
    static let yellowPair = Pair(light: 0xFFCC00, dark: 0xFFD60A)
    static let greenPair = Pair(light: 0x34C759, dark: 0x30D158)
    static let bluePair = Pair(light: 0x007AFF, dark: 0x0A84FF)
    static let redPair = Pair(light: 0xFF3B30, dark: 0xFF453A)

    static let gray = color(grayPair)
    static let orange = color(orangePair)
    static let yellow = color(yellowPair)
    static let green = color(greenPair)
    static let blue = color(bluePair)
    static let red = color(redPair)

    /// The colour for `pair`, light or dark by the colour scheme it is drawn in.
    static func color(_ pair: Pair) -> Color {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil) { appearance in
            platformColor(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? pair.dark : pair.light)
        })
        #else
        return Color(uiColor: UIColor { traits in
            platformColor(traits.userInterfaceStyle == .dark ? pair.dark : pair.light)
        })
        #endif
    }

    #if os(macOS)
    private static func platformColor(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed: component(rgb, 16), green: component(rgb, 8), blue: component(rgb, 0), alpha: 1)
    }
    #else
    private static func platformColor(_ rgb: UInt32) -> UIColor {
        UIColor(red: component(rgb, 16), green: component(rgb, 8), blue: component(rgb, 0), alpha: 1)
    }
    #endif

    private static func component(_ rgb: UInt32, _ shift: UInt32) -> CGFloat {
        CGFloat((rgb >> shift) & 0xFF) / 255
    }
}
