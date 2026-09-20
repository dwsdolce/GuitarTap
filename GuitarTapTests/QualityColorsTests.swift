//
//  QualityColorsTests.swift
//  GuitarTapTests
//
//  Locks WoodQuality's display colour (+ the raw label) against silent drift. The material
//  quality colours are the bug that motivated this whole parity group — a copy drifted to a
//  wrong hue with nothing to catch it.
//
//  Until the #17 sweep this suite asserted `WoodQuality.excellent.color == .green`: a semantic
//  identity, which stays true no matter what hue the OS resolves `.green` to. It therefore could
//  not detect the thing the group exists to detect, and did not. macOS 26 revised the system
//  palette, moving Swift to `.blue = #0088FF` and `.orange = #FF8D28` while Python and the web
//  still pinned #007AFF and #FF9500 — so the macOS app, the Python app and the web's PDF report,
//  all of them white surfaces, rendered two visibly different blues and oranges.
//
//  The colours are now absolute (see `WoodQuality.hex`) and this suite pins the hex, which is the
//  same thing Python's test_quality_colors.py and web's quality-colors.test.ts pin. All three
//  editions now compare the same values, so a drift in any one of them fails a test.
//
// @parity test/quality-colors

import Testing
import SwiftUI
@testable import GuitarTap

@Suite("QualityColors")
struct QualityColorsTests {

    // The canonical table. Python's `WoodQuality.color` and web's `WOOD_QUALITY_COLOR.light`
    // carry exactly these five values.
    @Test func perQualityHex() {
        #expect(WoodQuality.excellent.hex == "#34C759")
        #expect(WoodQuality.veryGood.hex  == "#00C7BE")
        #expect(WoodQuality.good.hex      == "#007AFF")
        #expect(WoodQuality.fair.hex      == "#FF9500")
        #expect(WoodQuality.poor.hex      == "#FF3B30")
    }

    // Five grades must be five distinguishable colours — the only thing the hue has to do.
    @Test func everyGradeHasItsOwnColour() {
        let hexes = WoodQuality.allCases.map(\.hex)
        #expect(Set(hexes).count == WoodQuality.allCases.count,
                "each quality grade needs its own colour, got \(hexes)")
    }

    // `color` is derived from `hex`, so the drawn colour cannot diverge from the pinned value.
    @Test func colorIsBuiltFromTheHex() {
        for q in WoodQuality.allCases {
            #expect(q.color == Color(sRGBHex: q.hex),
                    "\(q.rawValue): color should be built from hex \(q.hex)")
        }
    }

    // A colour built from hex must not be a semantic system colour — that is the regression this
    // suite exists to prevent, and the one the old `== .green` assertion could not see.
    @Test func coloursAreAbsolute_notSemantic() {
        #expect(WoodQuality.good.color != .blue,
                "Good must be an absolute #007AFF, not the OS's .blue, which moved in macOS 26")
        #expect(WoodQuality.fair.color != .orange,
                "Fair must be an absolute #FF9500, not the OS's .orange")
    }

    @Test func rawLabel() {
        #expect(WoodQuality.excellent.rawValue == "Excellent")
        #expect(WoodQuality.veryGood.rawValue  == "Very Good")
        #expect(WoodQuality.good.rawValue      == "Good")
        #expect(WoodQuality.fair.rawValue      == "Fair")
        #expect(WoodQuality.poor.rawValue      == "Poor")
    }
}
