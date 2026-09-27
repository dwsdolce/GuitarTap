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
// There is no user-override tier: a wrong peak is fixed by redoing the phase.
//
// Twin of Python test_wi2_effective_peak_id.py, under a shared slug so the pair is visible to
// gen_parity_map.
//
// WEB HAS NO COUNTERPART: it holds the same three `selected…Peak`s but reads them directly and has
// no `effective…PeakID` wrapper to test.

import Testing
import Foundation
@testable import GuitarTap

@Suite("EffectivePeakID", .serialized)
@MainActor
struct EffectivePeakIDTests {

    private func makeSUT() -> TapToneAnalyzer {
        TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
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
