//
//  ModeColorsTests.swift
//  GuitarTapTests
//
//  Locks GuitarMode's display colour against silent drift.
//
//  Until the #17 sweep this asserted `GuitarMode.air.color == .cyan` — a semantic identity that
//  stays true whatever hue the OS resolves `.cyan` to, and so could not detect drift at all. It is
//  the same defect the material quality colours had (see QualityColorsTests), and it mattered more
//  here: Python's palette had never matched Swift's on the same white background, and Python drew
//  Upper Modes and Unknown in one grey where Swift and the web separate them.
//
//  The values are now absolute, and Python carries this exact table. The web keeps its own
//  brightened shades only where its dark chart needs them. See SLUG-SWEEP.md F9.
//
// @parity test/mode-colors

import Testing
import SwiftUI
@testable import GuitarTap

@Suite("ModeColors")
struct ModeColorsTests {

    // The canonical table. Python's GuitarMode.hex carries these exactly.
    @Test func perModeHex() {
        #expect(GuitarMode.air.hex        == "#00C0E8")
        #expect(GuitarMode.top.hex        == "#34C759")
        #expect(GuitarMode.back.hex       == "#FF8D28")
        #expect(GuitarMode.dipole.hex     == "#FF383C")
        #expect(GuitarMode.ringMode.hex   == "#CB30E0")
        #expect(GuitarMode.upperModes.hex == "#8E8E93")
        #expect(GuitarMode.unknown.hex    == "#808080")
    }

    // Seven modes must be seven tellable-apart colours — the only thing the hue has to do.
    // Upper Modes and Unknown are the close pair, and Python had them identical until #17.
    @Test func everyModeHasItsOwnColour() {
        let hexes = GuitarMode.currentCases.map(\.hex)
        #expect(Set(hexes).count == GuitarMode.currentCases.count,
                "each mode needs its own colour, got \(hexes)")
        #expect(GuitarMode.upperModes.hex != GuitarMode.unknown.hex,
                "Upper Modes and Unknown must stay distinguishable")
    }

    // Legacy cases collapse to their canonical equivalent's colour, via `normalized`.
    @Test func legacyCasesShareTheirCanonicalColour() {
        #expect(GuitarMode.helmholtz.hex  == GuitarMode.air.hex)
        #expect(GuitarMode.crossGrain.hex == GuitarMode.air.hex)
        #expect(GuitarMode.longGrain.hex  == GuitarMode.top.hex)
        #expect(GuitarMode.monopole.hex   == GuitarMode.back.hex)
    }

    // `color` is derived from `hex`, so what is drawn cannot diverge from the pinned value.
    @Test func colorIsBuiltFromTheHex() {
        for m in GuitarMode.currentCases {
            #expect(m.color == Color(sRGBHex: m.hex), "\(m.rawValue): color should come from hex")
        }
    }

    // A colour built from hex must not be a semantic system colour — the regression this suite
    // exists to prevent, and the one the old `== .cyan` assertion could not see.
    @Test func coloursAreAbsolute_notSemantic() {
        #expect(GuitarMode.air.color != .cyan,
                "Air must be an absolute #00C0E8, not the OS's .cyan, which can move")
        #expect(GuitarMode.unknown.color != .secondary,
                "Unknown must be an absolute #808080, not .secondary, which composites")
    }
}
