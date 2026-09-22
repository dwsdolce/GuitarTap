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
// @parity test/comparison

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
    measurementName: String? = nil,
    withSnapshot: Bool = true
) -> TapToneMeasurement {
    TapToneMeasurement(
        peaks: [],
        measurementName: measurementName,
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
        let m1 = makeMeasurement(measurementName: "Bridge")
        let m2 = makeMeasurement(measurementName: "Neck")

        sut.loadComparison(measurements: [m1, m2])

        #expect(sut.comparisonSpectra.count == 2, "Expected 2 comparison entries, got \(sut.comparisonSpectra.count)")
        #expect(sut.displayMode == .comparison, "displayMode should be .comparison after loadComparison")
    }

    // CP-U2: Labels use measurementName when present; fall back to formatted timestamp.
    @Test func loadComparison_usesMeasurementNameLabelWhenPresent() {
        let sut = makeSUT()
        let m = makeMeasurement(measurementName: "Bridge Area")

        sut.loadComparison(measurements: [m])

        let label = sut.comparisonSpectra.first?.label ?? ""
        #expect(label == "Bridge Area", "Expected label 'Bridge Area', got '\(label)'")
    }

    // CP-U3: Measurements without a spectrum snapshot are silently filtered out.
    @Test func loadComparison_skipsMeasurementsWithoutSnapshot() {
        let sut = makeSUT()
        let withSnap    = makeMeasurement(measurementName: "With", withSnapshot: true)
        let withoutSnap = makeMeasurement(measurementName: "Without", withSnapshot: false)

        sut.loadComparison(measurements: [withSnap, withoutSnap])

        #expect(sut.comparisonSpectra.count == 1, "Should only include measurement with a snapshot")
        #expect(sut.comparisonSpectra.first?.label == "With")
    }

    // CP-U4: Colors cycle through the 5-color palette without crashing for > 5 entries.
    @Test func loadComparison_paletteWrapsFor6Measurements() {
        let sut = makeSUT()
        let measurements = (1...6).map { makeMeasurement(measurementName: "M\($0)") }

        // Should not crash and should produce 6 entries
        sut.loadComparison(measurements: measurements)

        #expect(sut.comparisonSpectra.count == 6)
    }

    // CP-U5: Axis bounds are set to the union of all snapshot ranges.
    @Test func loadComparison_setsAxisRangesToUnionOfSnapshots() {
        let sut = makeSUT()
        let m1 = TapToneMeasurement(peaks: [], measurementName: "A",
                                    spectrum: makeSnapshot(minFreq: 50,  maxFreq: 800,  minDB: -95, maxDB: -15))
        let m2 = TapToneMeasurement(peaks: [], measurementName: "B",
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
        #expect(sut.displayMode == .live, "displayMode should be .live when no spectra are loaded")
    }

    // CP-U8: All measurements lacking snapshots also leave displayMode as .live.
    @Test func loadComparison_noSnapshots_leavesDisplayModeAsLive() {
        let sut = makeSUT()
        sut.loadComparison(measurements: [makeMeasurement(withSnapshot: false), makeMeasurement(withSnapshot: false)])

        #expect(sut.comparisonSpectra.isEmpty)
        #expect(sut.displayMode == .live, "displayMode should be .live when no measurements have snapshots")
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
        let m = makeMeasurement(measurementName: "Bridge")
        sut.loadMeasurement(m)
        #expect(sut.displayMode == .frozen)
    }

    // loadMeasurement while in comparison also exits comparison and sets .frozen.
    @Test func loadMeasurement_duringComparison_setsDisplayModeToFrozen() {
        let sut = makeSUT()
        sut.loadComparison(measurements: [makeMeasurement(), makeMeasurement()])
        #expect(sut.displayMode == .comparison)

        sut.loadMeasurement(makeMeasurement(measurementName: "Neck"))

        #expect(sut.displayMode == .frozen)
        #expect(sut.comparisonSpectra.isEmpty, "comparisonSpectra should be cleared when loading a measurement")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Multi-tap to saved comparison transition tests  (MT-SC-U1 to MT-SC-U3)
// ---------------------------------------------------------------------------

private func makeTapEntry(tapIndex: Int) -> TapEntry {
    TapEntry(
        id: UUID(),
        tapIndex: tapIndex,
        snapshot: makeSnapshot(),
        peaks: [],
        selectedPeakIDs: []
    )
}

@Suite("MultiTapToSavedComparisonTransition")
@MainActor
struct MultiTapToSavedComparisonTransitionTests {

    // MT-SC-U1: loadComparison while multi-tap comparison is active resets
    // showingMultiTapComparison and tapEntries.
    //
    // Guards the invariant that entering a saved-measurement comparison always
    // tears down multi-tap state, regardless of whether the per-tap table was
    // open beforehand.
    @Test func loadComparison_whileMultiTapActive_resetsMultiTapState() {
        let sut = makeSUT()
        sut.tapEntries = [makeTapEntry(tapIndex: 1), makeTapEntry(tapIndex: 2)]
        sut.showingMultiTapComparison = true
        sut.applyMultiTapComparisonOverlays(enabled: true)
        #expect(sut.displayMode == .comparison, "Precondition: multi-tap comparison active")
        #expect(sut.showingMultiTapComparison == true, "Precondition: showingMultiTapComparison true")

        sut.loadComparison(measurements: [makeMeasurement(measurementName: "A"),
                                          makeMeasurement(measurementName: "B")])

        #expect(sut.showingMultiTapComparison == false,
                "loadComparison should reset showingMultiTapComparison")
        #expect(sut.tapEntries.isEmpty,
                "loadComparison should clear tapEntries")
    }

    // MT-SC-U2: After the transition displayMode stays .comparison and
    // isSavedMeasurementComparison becomes true.
    @Test func loadComparison_whileMultiTapActive_setsIsSavedMeasurementComparison() {
        let sut = makeSUT()
        sut.tapEntries = [makeTapEntry(tapIndex: 1), makeTapEntry(tapIndex: 2)]
        sut.showingMultiTapComparison = true
        sut.applyMultiTapComparisonOverlays(enabled: true)

        sut.loadComparison(measurements: [makeMeasurement(measurementName: "A"),
                                          makeMeasurement(measurementName: "B")])

        #expect(sut.displayMode == .comparison,
                "displayMode should remain .comparison after saved-measurement load")
        #expect(sut.isSavedMeasurementComparison == true,
                "isSavedMeasurementComparison should be true after transitioning from multi-tap")
        #expect(sut.comparisonSpectra.count == 2,
                "comparisonSpectra should contain the two loaded measurements")
    }

    // MT-SC-U3: Without an active multi-tap comparison, loadComparison behaves
    // normally: showingMultiTapComparison stays false and isSavedMeasurementComparison is true.
    @Test func loadComparison_withoutMultiTap_isSavedMeasurementComparison() {
        let sut = makeSUT()
        #expect(sut.showingMultiTapComparison == false, "Precondition: no multi-tap active")

        sut.loadComparison(measurements: [makeMeasurement(measurementName: "X")])

        #expect(sut.showingMultiTapComparison == false)
        #expect(sut.isSavedMeasurementComparison == true)
        #expect(sut.comparisonSpectra.count == 1)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Definitive modes persisted in a comparison  (Phase 6b)
// ---------------------------------------------------------------------------
//
// A comparison MEASUREMENT aggregates other measurements, so their override context is not otherwise
// in this file. Each ComparisonEntry stores the resolved definitive Air/Top/Back as mode→peakID,
// computed from the source's selection AND overrides, so the saved file is self-describing: a reader
// reproduces the table by peak-ID lookup, without re-running classifyAll and without the source's
// overrides (which are absent from the file).

@Suite("ComparisonModePersistence", .serialized)
@MainActor
struct ComparisonModePersistenceTests {

    private func classicalSnapshotWith(_ peaks: [ResonantPeak]) -> SpectrumSnapshot {
        SpectrumSnapshot(
            frequencies: [], magnitudes: [],
            minFreq: 50, maxFreq: 500, minDB: -100, maxDB: 0, isLogarithmic: false,
            guitarType: .classical, measurementType: .classical
        )
    }

    // The user's requirement end-to-end: a source measurement whose Top is user-overridden onto a
    // peak that is NOT the auto Top must have the comparison show THAT peak as Top.
    @Test func comparison_reflectsSourceOverride() {
        let saved = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .classical
        defer { TapDisplaySettings.measurementType = saved }
        let sut = makeSUT()

        let air = ResonantPeak(frequency: 95,  magnitude: -28)
        let autoTop = ResonantPeak(frequency: 210, magnitude: -20) // classical Top by position
        let far     = ResonantPeak(frequency: 400, magnitude: -22) // not Top by position
        let source = TapToneMeasurement(
            peaks: [air, autoTop, far],
            spectrum: classicalSnapshotWith([air, autoTop, far]),
            selectedPeakIDs: [air.id, far.id],                       // far is selected, autoTop is not
            peakModeOverrides: [far.id: GuitarMode.top.displayName]  // far renamed to Top
        )

        sut.loadComparison(measurements: [source])

        let modeIDs = sut.comparisonSpectra.first?.modeIDs ?? [:]
        #expect(modeIDs[GuitarMode.top.rawValue] == far.id,
                "the comparison's Top must be the user's overridden+selected peak, not the auto Top")
        #expect(modeIDs[GuitarMode.air.rawValue] == air.id)
    }

    // The stored map is authoritative: modeFrequency reads it, and does NOT re-derive via classifyAll.
    @Test func modeFrequency_readsStoredMap_notClassification() {
        let air = ResonantPeak(frequency: 95,  magnitude: -28)
        let realTop = ResonantPeak(frequency: 210, magnitude: -20) // classifyAll would pick THIS as Top
        let entry = ComparisonEntry(
            id: UUID(), label: "x", colorComponents: [0, 0, 1, 1],
            snapshot: classicalSnapshotWith([air, realTop]),
            peaks: [air, realTop], guitarType: .classical, sourceMeasurementID: nil,
            modePeakIDs: [GuitarMode.top.rawValue: air.id]   // deliberately points Top at the AIR peak
        )
        #expect(entry.modeFrequency(.top) == 95,
                "the stored map wins — the file is authoritative, not re-classified at render")
    }

    @Test func comparisonEntry_modePeakIDs_roundTrip() throws {
        let air = ResonantPeak(frequency: 95, magnitude: -28)
        let top = ResonantPeak(frequency: 210, magnitude: -20)
        let entry = ComparisonEntry(
            id: UUID(), label: "e", colorComponents: [0, 0, 1, 1],
            snapshot: classicalSnapshotWith([air, top]),
            peaks: [air, top], guitarType: .classical, sourceMeasurementID: nil,
            modePeakIDs: [GuitarMode.air.rawValue: air.id, GuitarMode.top.rawValue: top.id]
        )
        let record = TapToneMeasurement(peaks: [], comparisonEntries: [entry])
        let data = try TapToneAnalyzer.encodeMeasurements([record])
        let decoded = try TapToneAnalyzer.decodeMeasurements(data)[0]
        let e = try #require(decoded.comparisonEntries?.first)
        #expect(e.modePeakIDs?[GuitarMode.air.rawValue] == air.id)
        #expect(e.modePeakIDs?[GuitarMode.top.rawValue] == top.id)
    }

    // A pre-6b saved comparison (no modePeakIDs) is healed on decode and flagged for re-save.
    @Test func legacyComparisonEntry_isHealedOnDecode() throws {
        let air = ResonantPeak(frequency: 95,  magnitude: -28)
        let top = ResonantPeak(frequency: 210, magnitude: -20)
        let legacy = ComparisonEntry(
            id: UUID(), label: "legacy", colorComponents: [0, 0, 1, 1],
            snapshot: classicalSnapshotWith([air, top]),
            peaks: [air, top], guitarType: .classical, sourceMeasurementID: nil
            // modePeakIDs omitted → nil, as an old file has it
        )
        let record = TapToneMeasurement(peaks: [], comparisonEntries: [legacy])
        let data = try TapToneAnalyzer.encodeMeasurements([record])
        let decoded = try TapToneAnalyzer.decodeMeasurements(data)[0]

        #expect(decoded.wasHealed, "a legacy comparison entry must flag for re-save")
        let e = try #require(decoded.comparisonEntries?.first)
        #expect(e.modePeakIDs?[GuitarMode.air.rawValue] == air.id, "healed Air (positional)")
        #expect(e.modePeakIDs?[GuitarMode.top.rawValue] == top.id, "healed Top (positional)")
    }
}
