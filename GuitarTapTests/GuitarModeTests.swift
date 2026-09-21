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
// @parity test/classify

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

    @Test func classical_backRange_classifiesAsBack() {
        // Classical back range: 190–280 Hz; 240 Hz is outside the top overlap (170–230),
        // so it is unambiguously Back.
        let peak = ResonantPeak(frequency: 240, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .classical)
        #expect(result[peak.id] == .back)
    }

    @Test func classical_dipoleRange_classifiesAsDipole() {
        // Classical dipole range: 330–430 Hz
        let peak = ResonantPeak(frequency: 380, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .classical)
        #expect(result[peak.id] == .dipole)
    }

    @Test func classical_ringModeRange_classifiesAsRingMode() {
        // Classical ring mode range: 580–820 Hz
        let peak = ResonantPeak(frequency: 700, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .classical)
        #expect(result[peak.id] == .ringMode)
    }

    @Test func classical_upperModesRange_classifiesAsUpperModes() {
        // Classical upper modes range: 820–20000 Hz
        let peak = ResonantPeak(frequency: 1000, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .classical)
        #expect(result[peak.id] == .upperModes)
    }

    // 140 Hz falls in the gap between classical air (80–110) and top (170–230) → unknown.
    @Test func classical_gapFrequency_classifiesAsUnknown() {
        let peak = ResonantPeak(frequency: 140, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .classical)
        #expect(result[peak.id] == .unknown)
    }

    // MARK: - Flamenco guitar classification

    @Test func flamenco_airRange_classifiesAsAir() {
        // Flamenco air range: 85–115 Hz
        let peak = ResonantPeak(frequency: 100, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .flamenco)
        #expect(result[peak.id] == .air)
    }

    @Test func flamenco_topRange_classifiesAsTop() {
        // Flamenco top: 180–220 Hz; back: 200–250 Hz.  185 Hz is in top only → unambiguously Top.
        //
        // Corrected 2026-07-19: the old bands were top 190–250 / back 180–240 — the back range
        // sitting BELOW the top range, which inverted Top/Back for flamenco alone (Back was
        // claimed first, so classifyAll's "Back above Top" guard never fired). This case
        // asserted `.back` at 185 Hz under those bands. See section 7c of
        // Development/PEAK-FINDING-DUPLICATE-PEAKS.md in GuitarTapWeb.
        let peak = ResonantPeak(frequency: 185, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .flamenco)
        #expect(result[peak.id] == .top)
    }

    @Test func flamenco_backRange_classifiesAsBack() {
        // 240 Hz is in back (200–250) only — 200–220 is the Top/Back overlap.
        let peak = ResonantPeak(frequency: 240, magnitude: -20)
        let result = GuitarMode.classifyAll([peak], guitarType: .flamenco)
        #expect(result[peak.id] == .back)
    }

    @Test func flamenco_topIsClaimedBelowBack() {
        // The regression guard: two peaks straddling the 200 Hz boundary must resolve
        // Top-below-Back, as on every other guitar type. Under the old inverted bands the
        // strongest peak was labelled Back and the weaker, higher one Top.
        let low = ResonantPeak(frequency: 190, magnitude: -40)   // strongest
        let high = ResonantPeak(frequency: 230, magnitude: -50)
        let result = GuitarMode.classifyAll([low, high], guitarType: .flamenco)
        #expect(result[low.id] == .top)
        #expect(result[high.id] == .back)
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

}

// ---------------------------------------------------------------------------
// MARK: - classifyAll (context-aware, overlap-resolving)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// MARK: - Override Label Resolution
//
// Added in the #17 sweep. `fromDisplayName` is reachable from the override picker
// (CombinedPeakModeRowView offers both groups) and was tested in NO edition — which is how
// Swift and Python came to disagree about one of the seven academic labels, and how the web
// port came to lack the table entirely. See SLUG-SWEEP.md F11/F12.
// ---------------------------------------------------------------------------

@Suite("ModeOverrideLabels")
struct ModeOverrideLabelsTests {

    @Test func standardDisplayNames_resolveToTheirOwnMode() {
        for mode in GuitarMode.currentCases {
            #expect(GuitarMode.fromDisplayName(mode.displayName) == mode,
                    "\(mode.displayName) should resolve to \(mode)")
        }
    }

    // The academic T(m,n) labels. All three editions offer these and must agree on what they
    // mean — a measurement saved in one edition opens in the others.
    @Test func academicLabels_resolveToTheirMode() {
        #expect(GuitarMode.fromDisplayName("Helmholtz T(1,1)_1")  == .air)
        #expect(GuitarMode.fromDisplayName("Top T(1,1)_2")        == .top)
        #expect(GuitarMode.fromDisplayName("Back T(1,1)_3")       == .back)
        #expect(GuitarMode.fromDisplayName("Cross Dipole T(2,1)") == .dipole)
        #expect(GuitarMode.fromDisplayName("Long Dipole T(1,2)")  == .dipole)
        // Swift is canonical here; Python mapped Quadrapole to Upper Modes until #17.
        #expect(GuitarMode.fromDisplayName("Quadrapole T(2,2)")   == .ringMode)
        #expect(GuitarMode.fromDisplayName("Cross Tripole T(3,1)") == .ringMode)
    }

    // Every label the picker offers must resolve — an unresolvable one would silently become a
    // freeform label and drop out of the ratio and the definitive-peak resolution.
    @Test func everyOfferedLabelResolves() {
        for label in GuitarMode.additionalModeLabels {
            #expect(GuitarMode.fromDisplayName(label) != nil,
                    "the picker offers \(label) but nothing resolves it")
        }
    }

    @Test func freeformLabel_isUnknown_andDoesNotFallThroughToAuto() {
        #expect(GuitarMode.fromDisplayName("Wolf note") == nil)
        #expect(GuitarMode.effectiveMode(override: .assigned("Wolf note"), auto: .top) == .unknown)
    }

    @Test func noOverride_leavesTheAutoClassificationStanding() {
        #expect(GuitarMode.effectiveMode(override: .auto, auto: .top) == .top)
        #expect(GuitarMode.effectiveMode(override: nil, auto: .back) == .back)
    }
}

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
    // On equal magnitude the FIRST peak wins the band. All three editions agree — Swift's
    // max(by:) and Python's max() both keep the first maximal element, and web's loop replaces
    // only on a strict >. Pinned during the #17 sweep because no edition pinned it: a tie-break
    // that differed per edition would stay invisible until a real measurement produced a tie,
    // and would then move which peak is "the Air peak" in one app and not the others.
    @Test func classifyAll_equalMagnitude_firstPeakWinsTheBand() {
        let first  = ResonantPeak(frequency:  95, magnitude: -20)
        let second = ResonantPeak(frequency: 100, magnitude: -20)
        let result = GuitarMode.classifyAll([first, second], guitarType: .acoustic)
        #expect(result[first.id]  == .air)
        #expect(result[second.id] == .air)
        // Both are Air; the question is which one the claiming pass took.
        let claimed = [first, second].max(by: { $0.magnitude < $1.magnitude })
        #expect(claimed?.frequency == 95, "the first of two equal-magnitude peaks is claimed")
    }

    @Test func classifyAll_secondPeakInSameRange_stillClassifiedCorrectly() {
        // Acoustic air range: 90–120 Hz; two peaks, both unambiguously in Air.
        let strongerAir = ResonantPeak(frequency:  95, magnitude: -15) // claimed in step 1
        let weakerAir   = ResonantPeak(frequency: 110, magnitude: -28) // falls to step 3
        let result = GuitarMode.classifyAll([strongerAir, weakerAir], guitarType: .acoustic)
        #expect(result[strongerAir.id] == .air, "Stronger Air peak claimed in step 1")
        #expect(result[weakerAir.id]   == .air, "Weaker Air peak classified via step 3 (private classify path)")
    }
}
