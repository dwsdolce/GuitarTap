//
//  ComparisonModeTests.swift
//  GuitarTapTests
//
//  Tests for the spectrum comparison overlay feature:
//  loadComparison(), clearComparison(), comparisonSpectra, and displayMode.
//
//  All tests operate on TapToneAnalyzer state directly;
//  no audio hardware or async timing is involved.
//
//  Test plan coverage: CP1–CP5 (unit-testable subset)
//

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

private func makeSUT() -> TapToneAnalyzer {
    let fft = RealtimeFFTAnalyzer()
    return TapToneAnalyzer(fftAnalyzer: fft)
}

private func makeSnapshot(
    minFreq: Float = 80, maxFreq: Float = 1200,
    minDB: Float = -90, maxDB: Float = -10
) -> SpectrumSnapshot {
    let freqs: [Float] = [100, 200, 300, 400]
    let mags:  [Float] = [-40, -35, -45, -50]
    return SpectrumSnapshot(
        frequencies: freqs, magnitudes: mags,
        minFreq: minFreq, maxFreq: maxFreq,
        minDB: minDB, maxDB: maxDB,
        isLogarithmic: false
    )
}

private func makeMeasurement(
    tapLocation: String? = nil,
    withSnapshot: Bool = true
) -> TapToneMeasurement {
    TapToneMeasurement(
        peaks: [],
        tapLocation: tapLocation,
        spectrum: withSnapshot ? makeSnapshot() : nil
    )
}

// ---------------------------------------------------------------------------
// MARK: - loadComparison tests  (CP-U1–CP-U4)
// ---------------------------------------------------------------------------

@Suite("ComparisonLoad")
@MainActor
struct ComparisonLoadTests {

    // CP-U1: Loading 2 measurements populates comparisonSpectra with 2 entries.
    @Test func loadComparison_twoMeasurements_producesTwoEntries() {
        let sut = makeSUT()
        let m1 = makeMeasurement(tapLocation: "Bridge")
        let m2 = makeMeasurement(tapLocation: "Neck")

        sut.loadComparison(measurements: [m1, m2])

        #expect(sut.comparisonSpectra.count == 2, "Expected 2 comparison entries, got \(sut.comparisonSpectra.count)")
        #expect(sut.displayMode == .comparison, "displayMode should be .comparison after loadComparison")
    }

    // CP-U2: Labels use tapLocation when present; fall back to formatted timestamp.
    @Test func loadComparison_usesLocationLabelWhenPresent() {
        let sut = makeSUT()
        let m = makeMeasurement(tapLocation: "Bridge Area")

        sut.loadComparison(measurements: [m])

        let label = sut.comparisonSpectra.first?.label ?? ""
        #expect(label == "Bridge Area", "Expected label 'Bridge Area', got '\(label)'")
    }

    // CP-U3: Measurements without a spectrum snapshot are silently filtered out.
    @Test func loadComparison_skipsMeasurementsWithoutSnapshot() {
        let sut = makeSUT()
        let withSnap    = makeMeasurement(tapLocation: "With", withSnapshot: true)
        let withoutSnap = makeMeasurement(tapLocation: "Without", withSnapshot: false)

        sut.loadComparison(measurements: [withSnap, withoutSnap])

        #expect(sut.comparisonSpectra.count == 1, "Should only include measurement with a snapshot")
        #expect(sut.comparisonSpectra.first?.label == "With")
    }

    // CP-U4: Colors cycle through the 5-color palette without crashing for > 5 entries.
    @Test func loadComparison_paletteWrapsFor6Measurements() {
        let sut = makeSUT()
        let measurements = (1...6).map { makeMeasurement(tapLocation: "M\($0)") }

        // Should not crash and should produce 6 entries
        sut.loadComparison(measurements: measurements)

        #expect(sut.comparisonSpectra.count == 6)
    }

    // CP-U5: Axis bounds are set to the union of all snapshot ranges.
    @Test func loadComparison_setsAxisRangesToUnionOfSnapshots() {
        let sut = makeSUT()
        let m1 = TapToneMeasurement(peaks: [], tapLocation: "A",
                                    spectrum: makeSnapshot(minFreq: 50,  maxFreq: 800,  minDB: -95, maxDB: -15))
        let m2 = TapToneMeasurement(peaks: [], tapLocation: "B",
                                    spectrum: makeSnapshot(minFreq: 100, maxFreq: 1200, minDB: -80, maxDB: -5))

        sut.loadComparison(measurements: [m1, m2])

        #expect(sut.loadedMinFreq == 50,   "Expected minFreq 50, got \(String(describing: sut.loadedMinFreq))")
        #expect(sut.loadedMaxFreq == 1200, "Expected maxFreq 1200, got \(String(describing: sut.loadedMaxFreq))")
        #expect(sut.loadedMinDB   == -95,  "Expected minDB -95, got \(String(describing: sut.loadedMinDB))")
        #expect(sut.loadedMaxDB   == -5,   "Expected maxDB -5, got \(String(describing: sut.loadedMaxDB))")
    }
}

// ---------------------------------------------------------------------------
// MARK: - clearComparison tests  (CP-U6–CP-U7)
// ---------------------------------------------------------------------------

@Suite("ComparisonClear")
@MainActor
struct ComparisonClearTests {

    // CP-U6: clearComparison empties comparisonSpectra.
    @Test func clearComparison_emptiesSpectra() {
        let sut = makeSUT()
        sut.loadComparison(measurements: [makeMeasurement(), makeMeasurement()])
        #expect(sut.comparisonSpectra.count == 2)

        sut.clearComparison()

        #expect(sut.comparisonSpectra.isEmpty, "comparisonSpectra should be empty after clearComparison()")
        #expect(sut.displayMode == .live, "displayMode should be .live after clearComparison()")
    }

    // CP-U7: Loading an empty array also results in empty comparisonSpectra.
    @Test func loadComparison_emptyArray_producesEmptySpectra() {
        let sut = makeSUT()
        sut.loadComparison(measurements: [makeMeasurement(), makeMeasurement()])

        sut.loadComparison(measurements: [])

        #expect(sut.comparisonSpectra.isEmpty, "Loading an empty array should clear comparisonSpectra")
    }
}

// ---------------------------------------------------------------------------
// MARK: - displayMode transition tests
// ---------------------------------------------------------------------------

@Suite("DisplayModeTransitions")
@MainActor
struct DisplayModeTransitionTests {

    // displayMode starts as .live on a fresh analyzer.
    @Test func initialDisplayMode_isLive() {
        let sut = makeSUT()
        #expect(sut.displayMode == .live)
    }

    // loadComparison sets displayMode to .comparison.
    @Test func loadComparison_setsDisplayModeToComparison() {
        let sut = makeSUT()
        sut.loadComparison(measurements: [makeMeasurement(), makeMeasurement()])
        #expect(sut.displayMode == .comparison)
    }

    // clearComparison sets displayMode back to .live.
    @Test func clearComparison_setsDisplayModeToLive() {
        let sut = makeSUT()
        sut.loadComparison(measurements: [makeMeasurement(), makeMeasurement()])
        sut.clearComparison()
        #expect(sut.displayMode == .live)
    }

    // loadMeasurement sets displayMode to .frozen.
    @Test func loadMeasurement_setsDisplayModeToFrozen() {
        let sut = makeSUT()
        let m = makeMeasurement(tapLocation: "Bridge")
        sut.loadMeasurement(m)
        #expect(sut.displayMode == .frozen)
    }

    // loadMeasurement while in comparison also exits comparison and sets .frozen.
    @Test func loadMeasurement_duringComparison_setsDisplayModeToFrozen() {
        let sut = makeSUT()
        sut.loadComparison(measurements: [makeMeasurement(), makeMeasurement()])
        #expect(sut.displayMode == .comparison)

        sut.loadMeasurement(makeMeasurement(tapLocation: "Neck"))

        #expect(sut.displayMode == .frozen)
        #expect(sut.comparisonSpectra.isEmpty, "comparisonSpectra should be cleared when loading a measurement")
    }
}
