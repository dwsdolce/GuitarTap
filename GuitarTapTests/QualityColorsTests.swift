//
//  QualityColorsTests.swift
//  GuitarTapTests
//
//  Locks WoodQuality.color (+ the raw label) against silent drift. The material quality colors are
//  the bug that motivated this whole parity group — a copy drifted to a wrong hue with nothing to
//  catch it. Swift uses semantic SwiftUI Colors; Python pins hex, the web a per-scheme hex table.
//
// @parity test/quality-colors

import Testing
import SwiftUI
@testable import GuitarTap

@Suite("QualityColors")
struct QualityColorsTests {

    @Test func perQualityColor() {
        #expect(WoodQuality.excellent.color == .green)
        #expect(WoodQuality.veryGood.color  == .mint)
        #expect(WoodQuality.good.color      == .blue)
        #expect(WoodQuality.fair.color      == .orange)
        #expect(WoodQuality.poor.color      == .red)
    }

    @Test func rawLabel() {
        #expect(WoodQuality.excellent.rawValue == "Excellent")
        #expect(WoodQuality.veryGood.rawValue  == "Very Good")
        #expect(WoodQuality.good.rawValue      == "Good")
        #expect(WoodQuality.fair.rawValue      == "Fair")
        #expect(WoodQuality.poor.rawValue      == "Poor")
    }
}