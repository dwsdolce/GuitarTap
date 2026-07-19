//
//  AnalysisQualityTests.swift
//  GuitarTapTests
//
//  Locks the guitar tap-tone quality helpers (canonical): the per-type ring-out (decay) thresholds
//  and their labels/colors, and the tap-tone-ratio bands. Float.decayQuality(for:) /
//  decayQualityColor(for:) / tapToneRatioQuality (Extensions.swift) + GuitarType.decayThresholds.
//  Python/web port these exactly and pin the same boundaries in the parity group.
//
// @parity test/analysis-quality

import Testing
import SwiftUI
@testable import GuitarTap

@Suite("AnalysisQuality")
struct AnalysisQualityTests {

    @Test func classicalDecayThresholds() {
        let t = GuitarType.classical.decayThresholds
        #expect(t.veryShort == 0.15)
        #expect(t.short     == 0.35)
        #expect(t.moderate  == 0.6)
        #expect(t.good      == 1.0)
    }

    @Test func decayLabelsAtBoundaries() {
        #expect(Float(0.14).decayQuality(for: .classical) == "Very Short")
        #expect(Float(0.15).decayQuality(for: .classical) == "Short")     // >= veryShort
        #expect(Float(0.35).decayQuality(for: .classical) == "Moderate")
        #expect(Float(0.6).decayQuality(for: .classical)  == "Good")
        #expect(Float(1.0).decayQuality(for: .classical)  == "Excellent")
    }

    @Test func decayLabelsAreTypeSpecific() {
        // 0.5 s: Good for flamenco (good=0.55) but Moderate for classical (moderate=0.6).
        #expect(Float(0.5).decayQuality(for: .flamenco)  == "Good")
        #expect(Float(0.5).decayQuality(for: .classical) == "Moderate")
    }

    @Test func decayColors() {
        #expect(Float(0.10).decayQualityColor(for: .classical) == .gray)
        #expect(Float(0.20).decayQualityColor(for: .classical) == .orange)
        #expect(Float(0.50).decayQualityColor(for: .classical) == .yellow)
        #expect(Float(0.80).decayQualityColor(for: .classical) == .green)
        #expect(Float(1.20).decayQualityColor(for: .classical) == .blue)
    }

    @Test func ratioLabels() {
        #expect(Float(1.6).tapToneRatioQuality == "Low")
        #expect(Float(1.8).tapToneRatioQuality == "Below Target")
        #expect(Float(1.9).tapToneRatioQuality == "Ideal")
        #expect(Float(2.1).tapToneRatioQuality == "Ideal")
        #expect(Float(2.2).tapToneRatioQuality == "Above Target")
        #expect(Float(2.4).tapToneRatioQuality == "High")
    }

    @Test func ratioColors() {
        #expect(Float(1.6).tapToneRatioQualityColor == .red)
        #expect(Float(1.8).tapToneRatioQualityColor == .orange)
        #expect(Float(2.0).tapToneRatioQualityColor == .green)
        #expect(Float(2.4).tapToneRatioQualityColor == .red)
    }
}