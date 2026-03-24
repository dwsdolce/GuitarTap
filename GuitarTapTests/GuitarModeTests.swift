//
//  GuitarModeTests.swift
//  GuitarTapTests
//
//  Tests for GuitarMode classification, normalization, display names,
//  ideal frequency ranges, and the context-aware classifyAll algorithm.
//  All range-classification tests go through classifyAll (single-peak form)
//  so that classify() can remain private to GuitarMode.swift.
//
//  Test plan coverage: G1–G20
//

import Testing
import Foundation
@testable import GuitarTap

@Suite("GuitarModeClassification")
struct GuitarModeClassificationTests {

    // MARK: - Acoustic guitar classification
    //
    // Each test passes a single peak to classifyAll so the range lookup is
    // exercised without calling the private classify() directly.

    @Test func acoustic_airRange_classifiesAsAir() {
        // Acoustic air range: 90–120 Hz; test lower bound, mid, and upper bound
        let lo  = ResonantPeak(frequency:  90, magnitude: -20)
        let mid = ResonantPeak(frequency: 100, magnitude: -20)
        let hi  = ResonantPeak(frequency: 120, magnitude: -20)
        let rLo  = GuitarMode.classifyAll([lo],  guitarType: .acoustic)
        let rMid = GuitarMode.classifyAll([mid], guitarType: .acoustic)
        let rHi  = GuitarMode.classifyAll([hi],  guitarType: .acoustic)
        #expect(rLo[lo.id]   == .air)
        #expect(rMid[mid.id] == .air)
        #expect(rHi[hi.id]   == .air)
    }

    @Test func acoustic_topRange_classifiesAsTop() {
        // Acoustic top range: 150–210 Hz
        let peak = ResonantPeak(frequency: 180, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .acoustic)
        #expect(result[peak.id] == .top)
    }

    @Test func acoustic_backRange_classifiesAsBack() {
        // Acoustic back range: 210–290 Hz (no overlap with top for acoustic)
        let peak = ResonantPeak(frequency: 250, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .acoustic)
        #expect(result[peak.id] == .back)
    }

    @Test func acoustic_dipoleRange_classifiesAsDipole() {
        let peak = ResonantPeak(frequency: 400, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .acoustic)
        #expect(result[peak.id] == .dipole)
    }

    @Test func acoustic_ringModeRange_classifiesAsRingMode() {
        let peak = ResonantPeak(frequency: 700, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .acoustic)
        #expect(result[peak.id] == .ringMode)
    }

    @Test func acoustic_upperModesRange_classifiesAsUpperModes() {
        let peak = ResonantPeak(frequency: 1200, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .acoustic)
        #expect(result[peak.id] == .upperModes)
    }

    // A frequency that falls between defined ranges should return .unknown.
    @Test func acoustic_betweenRanges_classifiesAsUnknown() {
        // Between acoustic back (290) and dipole (360): 320 Hz is a gap frequency.
        // classifyAll step 3 calls classify() internally; classify returns .unknown.
        let peak = ResonantPeak(frequency: 320, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .acoustic)
        #expect(result[peak.id] == .unknown)
    }

    // MARK: - Classical guitar classification

    @Test func classical_airRange_classifiesAsAir() {
        // Classical air range: 80–110 Hz
        let peak = ResonantPeak(frequency: 95, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .classical)
        #expect(result[peak.id] == .air)
    }

    @Test func classical_topRange_classifiesAsTop() {
        // Classical top range: 170–230 Hz; no Back peak present, so Top claims this.
        let peak = ResonantPeak(frequency: 200, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .classical)
        #expect(result[peak.id] == .top)
    }

    // MARK: - Flamenco guitar classification

    @Test func flamenco_airRange_classifiesAsAir() {
        // Flamenco air range: 85–115 Hz
        let peak = ResonantPeak(frequency: 100, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .flamenco)
        #expect(result[peak.id] == .air)
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

    // Each peak in a non-overlapping set should get the expected mode label.
    // Acoustic top (150–210) and back (210–290) don't overlap, so all three
    // peaks are claimed unambiguously in step 1 of the algorithm.
    @Test func classifyAll_nonOverlappingPeaks_classifyCorrectly() {
        let airPeak  = ResonantPeak(frequency: 100, magnitude: -30)
        let topPeak  = ResonantPeak(frequency: 180, magnitude: -25)
        let backPeak = ResonantPeak(frequency: 250, magnitude: -28)
        let result = GuitarMode.classifyAll([airPeak, topPeak, backPeak], guitarType: .acoustic)
        #expect(result[airPeak.id]  == .air)
        #expect(result[topPeak.id]  == .top)
        #expect(result[backPeak.id] == .back)
    }

    // Empty input should return an empty map without crashing.
    @Test func classifyAll_emptyInput_returnsEmptyMap() {
        let result = GuitarMode.classifyAll([], guitarType: .acoustic)
        #expect(result.isEmpty)
    }

    // Two peaks in the same non-overlapping range: the stronger one is claimed
    // in step 1; the weaker one falls through to step 3 where the private
    // classify() path is exercised.  Both should resolve to the same mode
    // (not .unknown), confirming step 3 classifies by range, not by "leftover".
    @Test func classifyAll_secondPeakInSameRange_stillClassifiedCorrectly() {
        // Acoustic air range: 90–120 Hz; two peaks, both unambiguously in Air.
        let strongerAir = ResonantPeak(frequency:  95, magnitude: -15) // claimed in step 1
        let weakerAir   = ResonantPeak(frequency: 110, magnitude: -28) // falls to step 3
        let result = GuitarMode.classifyAll([strongerAir, weakerAir], guitarType: .acoustic)
        #expect(result[strongerAir.id] == .air, "Stronger Air peak claimed in step 1")
        #expect(result[weakerAir.id]   == .air, "Weaker Air peak classified via step 3 (private classify path)")
    }
}
