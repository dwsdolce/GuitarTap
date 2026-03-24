//
//  GuitarModeTests.swift
//  GuitarTapTests
//
//  Tests for GuitarMode classification, normalization, display names,
//  ideal frequency ranges, and the context-aware classifyAll algorithm.
//  Uses the two-argument classify overload (frequency + explicit GuitarType)
//  so tests are independent of UserDefaults state.
//
//  Test plan coverage: G1–G19
//

import Testing
import Foundation
@testable import GuitarTap

@Suite("GuitarModeClassification")
struct GuitarModeClassificationTests {

    // MARK: - Acoustic guitar classification

    @Test func acoustic_airRange_classifiesAsAir() {
        // Acoustic air range: 90–120 Hz
        #expect(GuitarMode.classify(frequency: 100, guitarType: .acoustic) == .air)
        #expect(GuitarMode.classify(frequency: 90, guitarType: .acoustic) == .air)
        #expect(GuitarMode.classify(frequency: 120, guitarType: .acoustic) == .air)
    }

    @Test func acoustic_topRange_classifiesAsTop() {
        // Acoustic top range: 150–210 Hz
        #expect(GuitarMode.classify(frequency: 180, guitarType: .acoustic) == .top)
    }

    @Test func acoustic_backRange_classifiesAsBack() {
        // Acoustic back range: 210–290 Hz
        #expect(GuitarMode.classify(frequency: 250, guitarType: .acoustic) == .back)
    }

    @Test func acoustic_dipoleRange_classifiesAsDipole() {
        #expect(GuitarMode.classify(frequency: 400, guitarType: .acoustic) == .dipole)
    }

    @Test func acoustic_ringModeRange_classifiesAsRingMode() {
        #expect(GuitarMode.classify(frequency: 700, guitarType: .acoustic) == .ringMode)
    }

    @Test func acoustic_upperModesRange_classifiesAsUpperModes() {
        #expect(GuitarMode.classify(frequency: 1200, guitarType: .acoustic) == .upperModes)
    }

    // A frequency that falls between defined ranges should return .unknown.
    @Test func acoustic_betweenRanges_classifiesAsUnknown() {
        // Between acoustic back (290) and dipole (360): e.g. 320 Hz
        #expect(GuitarMode.classify(frequency: 320, guitarType: .acoustic) == .unknown)
    }

    // MARK: - Classical guitar classification

    @Test func classical_airRange_classifiesAsAir() {
        // Classical air range: 80–110 Hz
        #expect(GuitarMode.classify(frequency: 95, guitarType: .classical) == .air)
    }

    @Test func classical_topRange_classifiesAsTop() {
        // Classical top range: 170–230 Hz
        #expect(GuitarMode.classify(frequency: 200, guitarType: .classical) == .top)
    }

    // MARK: - Flamenco guitar classification

    @Test func flamenco_airRange_classifiesAsAir() {
        // Flamenco air range: 85–115 Hz
        #expect(GuitarMode.classify(frequency: 100, guitarType: .flamenco) == .air)
    }

    // MARK: - Mode normalization (legacy cases)

    @Test func helmholtz_normalizesToAir() {
        #expect(GuitarMode.helmholtz.normalized == .air)
    }

    @Test func crossGrain_normalizesToAir() {
        #expect(GuitarMode.crossGrain.normalized == .air)
    }

    @Test func longGrain_normalizesToTop() {
        #expect(GuitarMode.longGrain.normalized == .top)
    }

    @Test func monopole_normalizesToBack() {
        #expect(GuitarMode.monopole.normalized == .back)
    }

    @Test func air_normalizesToAir() {
        // Modern cases normalize to themselves
        #expect(GuitarMode.air.normalized == .air)
    }

    @Test func dipole_normalizesToDipole() {
        #expect(GuitarMode.dipole.normalized == .dipole)
    }

    // MARK: - Display names

    @Test func displayName_legacyHelmholtz_showsAirHelmholtz() {
        #expect(GuitarMode.helmholtz.displayName == "Air (Helmholtz)")
    }

    @Test func displayName_legacyLongGrain_showsTop() {
        #expect(GuitarMode.longGrain.displayName == "Top")
    }

    @Test func displayName_legacyMonopole_showsBack() {
        #expect(GuitarMode.monopole.displayName == "Back")
    }

    @Test func displayName_unknown_showsUnknown() {
        #expect(GuitarMode.unknown.displayName == "Unknown")
    }

    // MARK: - modeRange convenience accessor

    // modeRange(for:) must return the same range as modeRanges.<mode> for each guitar type.
    @Test func modeRange_classicalAir_matchesModeRanges() {
        #expect(GuitarMode.air.modeRange(for: .classical) == GuitarType.classical.modeRanges.air)
    }

    @Test func modeRange_acousticTop_matchesModeRanges() {
        #expect(GuitarMode.top.modeRange(for: .acoustic) == GuitarType.acoustic.modeRanges.top)
    }

    // MARK: - Annotation visibility mode cycle

    @Test func annotationVisibilityCycle_allToSelectedToNoneToAll() {
        var mode = AnnotationVisibilityMode.all
        mode = mode.next
        #expect(mode == .selected)
        mode = mode.next
        #expect(mode == .none)
        mode = mode.next
        #expect(mode == .all)
    }

    @Test func annotationVisibility_iconNames_nonEmpty() {
        for mode in AnnotationVisibilityMode.allCases {
            #expect(!mode.iconName.isEmpty, "Icon name for \(mode) should not be empty")
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - classifyAll (context-aware, overlap-resolving)
// ---------------------------------------------------------------------------

@Suite("GuitarModeClassifyAll")
struct GuitarModeClassifyAllTests {

    // Two peaks both inside the classical Top range (170–230) AND the classical
    // Back range (190–280) should get different labels: the stronger one is Top,
    // the weaker one is Back.  This is the core regression case that prompted
    // the classifyAll algorithm.
    @Test func classical_twoOverlapPeaks_getDistinctTopAndBackLabels() {
        let strongerPeak = ResonantPeak(frequency: 210, magnitude: -18) // higher magnitude → Top
        let weakerPeak   = ResonantPeak(frequency: 225, magnitude: -25) // lower magnitude → Back
        let result = GuitarMode.classifyAll([strongerPeak, weakerPeak], guitarType: .classical)
        #expect(result[strongerPeak.id] == .top,  "Stronger peak in overlap zone should be Top")
        #expect(result[weakerPeak.id]   == .back,  "Weaker peak in overlap zone should be Back")
    }

    // The weaker peak gets Back even when it is also inside the Top range,
    // because Top was already claimed by the stronger peak.
    @Test func classical_overlapZone_weakerPeakIsBack_evenIfInsideTopRange() {
        let strongerPeak = ResonantPeak(frequency: 195, magnitude: -20)
        let weakerPeak   = ResonantPeak(frequency: 205, magnitude: -30)
        let result = GuitarMode.classifyAll([strongerPeak, weakerPeak], guitarType: .classical)
        #expect(result[strongerPeak.id] == .top)
        #expect(result[weakerPeak.id]   == .back)
    }

    // A single peak in the overlap zone should always be Top (not Back),
    // because Top is the first mode claimed.
    @Test func classical_singleOverlapPeak_isTop() {
        let peak = ResonantPeak(frequency: 210, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .classical)
        #expect(result[peak.id] == .top)
    }

    // Peaks outside all mode ranges should fall back to .unknown via classify().
    @Test func classifyAll_unknownPeak_fallsBackToClassify() {
        // 320 Hz is between acoustic back (210–290) and dipole (360–500) → unknown
        let peak = ResonantPeak(frequency: 320, magnitude: -30)
        let result = GuitarMode.classifyAll([peak], guitarType: .acoustic)
        #expect(result[peak.id] == .unknown)
    }

    // Each peak in a non-overlapping set should get the same label as classify().
    @Test func classifyAll_nonOverlappingPeaks_matchClassify() {
        let airPeak  = ResonantPeak(frequency: 100, magnitude: -30)
        let topPeak  = ResonantPeak(frequency: 180, magnitude: -25)
        let backPeak = ResonantPeak(frequency: 250, magnitude: -28)
        let result = GuitarMode.classifyAll([airPeak, topPeak, backPeak], guitarType: .acoustic)
        #expect(result[airPeak.id]  == GuitarMode.classify(frequency: 100, guitarType: .acoustic))
        #expect(result[topPeak.id]  == GuitarMode.classify(frequency: 180, guitarType: .acoustic))
        #expect(result[backPeak.id] == GuitarMode.classify(frequency: 250, guitarType: .acoustic))
    }

    // Empty input should return an empty map without crashing.
    @Test func classifyAll_emptyInput_returnsEmptyMap() {
        let result = GuitarMode.classifyAll([], guitarType: .acoustic)
        #expect(result.isEmpty)
    }
}
