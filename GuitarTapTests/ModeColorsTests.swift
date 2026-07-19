//
//  ModeColorsTests.swift
//  GuitarTapTests
//
//  Locks GuitarMode.color against silent drift — the class of bug that hit the material quality
//  colors (a copy drifted to wrong hues with nothing to catch it). Swift uses semantic SwiftUI
//  Colors; Python/web pin their own RGB/hex maps in the same parity group.
//
// @parity test/mode-colors

import Testing
import SwiftUI
@testable import GuitarTap

@Suite("ModeColors")
struct ModeColorsTests {

    @Test func perModeColor() {
        #expect(GuitarMode.air.color        == .cyan)
        #expect(GuitarMode.top.color        == .green)
        #expect(GuitarMode.back.color       == .orange)
        #expect(GuitarMode.dipole.color     == .red)
        #expect(GuitarMode.ringMode.color   == .purple)
        #expect(GuitarMode.upperModes.color == .gray)
        #expect(GuitarMode.unknown.color    == .secondary)
    }
}