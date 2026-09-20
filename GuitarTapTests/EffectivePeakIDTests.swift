//
//  EffectivePeakIDTests.swift
//  GuitarTapTests
//
// @parity test/effective-peak-id
//
// Resolution of the identified material peak: `effectiveLongitudinalPeakID`,
// `effectiveCrossPeakID`, `effectiveFlcPeakID`.
//
//   selected<Phase>Peak?.id — the dominant peak stored when the phase FINALISES.
//
// It was a three-layer resolution until 2026-09-20: a user-override tier (UI removed in April 2026,
// replaced by redoing the phase) over the phase peak over `autoSelected<Phase>PeakID`. Both extra
// layers are gone — the auto arm was unreachable, because both are assigned on adjacent lines in
// the phase handlers and the phase peak is never nil when the auto id is set.
//
// Swift had NO test for any of this, while Python had nine in an untagged, Python-only file
// (test_wi2_effective_peak_id.py). Written 2026-09-20 as its twin (project issue #8) under a
// shared slug, so the pair is visible to gen_parity_map.
//
// WEB HAS NO COUNTERPART, and that is structural rather than a gap: `identifyMaterialPeak` stores
// exactly ONE peak per phase in `matPeaks`, so there is no intermediate auto-selection to resolve
// against. Its `selectedLongitudinalPeakID` is a persisted FILE field, not a live two-layer read.

import Testing
import Foundation
@testable import GuitarTap

@Suite("EffectivePeakID", .serialized)
@MainActor
struct EffectivePeakIDTests {

    private func makeSUT() -> TapToneAnalyzer {
        TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer())
    }

    // MARK: - Longitudinal (fL)

    @Test func longitudinal_returnsTheFinalisedPhasePeak() {
        let sut = makeSUT()
        let phase = ResonantPeak(frequency: 100, magnitude: -20)
        sut.selectedLongitudinalPeak = phase

        #expect(sut.effectiveLongitudinalPeakID == phase.id,
                "the finalised phase peak is the identified peak")
    }

    @Test func longitudinal_nilBeforeThePhaseFinalises() {
        let sut = makeSUT()
        #expect(sut.effectiveLongitudinalPeakID == nil)
    }

    // MARK: - Cross-grain (fC)

    @Test func cross_returnsTheFinalisedPhasePeak() {
        let sut = makeSUT()
        let phase = ResonantPeak(frequency: 200, magnitude: -20)
        sut.selectedCrossPeak = phase

        #expect(sut.effectiveCrossPeakID == phase.id)
    }

    @Test func cross_nilBeforeThePhaseFinalises() {
        let sut = makeSUT()
        #expect(sut.effectiveCrossPeakID == nil)
    }

    // MARK: - Diagonal (fLC)

    @Test func flc_returnsTheFinalisedPhasePeak() {
        let sut = makeSUT()
        let phase = ResonantPeak(frequency: 300, magnitude: -20)
        sut.selectedFlcPeak = phase

        #expect(sut.effectiveFlcPeakID == phase.id)
    }

    @Test func flc_nilBeforeThePhaseFinalises() {
        let sut = makeSUT()
        #expect(sut.effectiveFlcPeakID == nil)
    }
}
