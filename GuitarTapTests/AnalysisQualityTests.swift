//
//  AnalysisQualityTests.swift
//  GuitarTapTests
//
//  The guitar tap-tone quality helpers: the per-type ring-out (decay) thresholds and their labels and
//  colours, the tap-tone-ratio bands, values outside every band, and the pinned palette the colours come
//  from (Float.decayQuality(for:) / decayQualityColor(for:) / tapToneRatioQuality /
//  tapToneRatioQualityColor in Extensions.swift, GuitarType.decayThresholds, Palette). The Python and web
//  suites have the same cases.
//
// @parity test/analysis-quality

import Testing
import SwiftUI
@testable import GuitarTap

@Suite("AnalysisQuality")
struct AnalysisQualityTests {

    // MARK: - Thresholds

    @Test func decayThresholds_everyType() {
        let expected: [(GuitarType, [Float])] = [
            (.classical, [0.15, 0.35, 0.60, 1.0]),
            (.flamenco, [0.08, 0.20, 0.35, 0.55]),
            (.acoustic, [0.10, 0.25, 0.45, 0.75]),
            (.generic, [0.10, 0.25, 0.45, 0.75]),
        ]
        for (type, values) in expected {
            let t = type.decayThresholds
            #expect([t.veryShort, t.short, t.moderate, t.good] == values, "\(type)")
        }
    }

    // MARK: - Decay labels

    @Test func decayLabels_classicalAtEveryBoundary() {
        let cases: [(Float, String)] = [
            (0, "Very Short"), (0.14, "Very Short"), (0.15, "Short"), (0.34, "Short"), (0.35, "Moderate"),
            (0.59, "Moderate"), (0.6, "Good"), (0.99, "Good"), (1.0, "Excellent"), (2.0, "Excellent"),
        ]
        for (value, label) in cases {
            #expect(value.decayQuality(for: .classical) == label, "\(value)")
        }
    }

    @Test func decayLabels_eachTypeAtItsThresholds() {
        let labels = ["Short", "Moderate", "Good", "Excellent"]
        for type in [GuitarType.flamenco, .acoustic, .generic] {
            let t = type.decayThresholds
            for (threshold, label) in zip([t.veryShort, t.short, t.moderate, t.good], labels) {
                #expect(threshold.decayQuality(for: type) == label, "\(type) \(threshold)")
            }
            #expect(Float(0).decayQuality(for: type) == "Very Short", "\(type)")
        }
    }

    // MARK: - Decay colours

    @Test func decayColors_everyBand() {
        let cases: [(Float, Color)] = [
            (0.10, Palette.gray), (0.20, Palette.orange), (0.50, Palette.yellow),
            (0.80, Palette.green), (1.20, Palette.blue),
        ]
        for (value, color) in cases {
            #expect(value.decayQualityColor(for: .classical) == color, "\(value)")
        }
    }

    // MARK: - Ratio

    @Test func ratioLabels_atEveryBoundary() {
        let cases: [(Float, String)] = [
            (0, "Low"), (1.69, "Low"), (1.7, "Below Target"), (1.89, "Below Target"), (1.9, "Ideal"),
            (2.0, "Ideal"), (2.1, "Ideal"), (2.2, "Above Target"), (2.29, "Above Target"), (2.3, "High"),
            (3.0, "High"),
        ]
        for (value, label) in cases {
            #expect(value.tapToneRatioQuality == label, "\(value)")
        }
    }

    @Test func ratioColors_everyBand() {
        let cases: [(Float, Color)] = [
            (1.6, Palette.red), (1.8, Palette.orange), (2.0, Palette.green), (2.2, Palette.orange), (2.4, Palette.red),
        ]
        for (value, color) in cases {
            #expect(value.tapToneRatioQualityColor == color, "\(value)")
        }
    }

    // MARK: - Outside every band

    @Test func negativeOrNaN_isUnknownAndGray() {
        for value in [Float(-0.1), .nan] {
            #expect(value.decayQuality(for: .classical) == "Unknown", "\(value)")
            #expect(value.decayQualityColor(for: .classical) == Palette.gray, "\(value)")
            #expect(value.tapToneRatioQuality == "Unknown", "\(value)")
            #expect(value.tapToneRatioQualityColor == Palette.gray, "\(value)")
        }
    }

    // MARK: - Palette

    @Test func palette_lightAndDarkValues() {
        let expected: [(Color, String, String)] = [
            (Palette.gray, "#8E8E93FF", "#8E8E93FF"),
            (Palette.orange, "#FF9500FF", "#FF9F0AFF"),
            (Palette.yellow, "#FFCC00FF", "#FFD60AFF"),
            (Palette.green, "#34C759FF", "#30D158FF"),
            (Palette.blue, "#007AFFFF", "#0A84FFFF"),
            (Palette.red, "#FF3B30FF", "#FF453AFF"),
        ]
        var light = EnvironmentValues()
        light.colorScheme = .light
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        for (color, lightHex, darkHex) in expected {
            #expect(color.resolve(in: light).description == lightHex)
            #expect(color.resolve(in: dark).description == darkHex)
        }
    }
}
