//
//  LoadedRangeTests.swift
//  GuitarTapTests
//
// @parity test/display-range
//
// Every load publishes the range the chart shows (the view remembers it as the loaded range, so a new
// measurement can return to the saved view): a measurement's snapshot range, exactly, or the saved range
// when it has none. A load never moves the analysis range — the fixed 30–2000 Hz peak detection
// searches.

import Testing
@testable import GuitarTap

@Suite("LoadedRange", .serialized)
struct LoadedRangeTests {

    private func plate(minFreq: Float, maxFreq: Float, minDB: Float, maxDB: Float) -> TapToneMeasurement {
        let snap = SpectrumSnapshot(
            frequencies: [100, 200], magnitudes: [-10, -20],
            minFreq: minFreq, maxFreq: maxFreq, minDB: minDB, maxDB: maxDB, isLogarithmic: false,
            measurementType: .plate)
        return TapToneMeasurement(peaks: [], longitudinalSnapshot: snap)
    }

    @Test func loadingAPlate_publishesItsSnapshotRange_exactly() {
        let sut = TapToneAnalyzer.forTesting()
        sut.loadMeasurement(plate(minFreq: 24.37, maxFreq: 46.81, minDB: -75.5, maxDB: -61.25))
        let r = sut.loadedAxisRange
        #expect(r?.minFreq == 24.37 && r?.maxFreq == 46.81)
        #expect(r?.minDB == -75.5 && r?.maxDB == -61.25)
    }

    @Test func loadingWithoutASnapshot_publishesTheSavedRange() {
        let sut = TapToneAnalyzer.forTesting()
        sut.loadMeasurement(TapToneMeasurement(peaks: []))
        let r = sut.loadedAxisRange
        #expect(r?.minFreq == TapDisplaySettings.minFrequency && r?.maxFreq == TapDisplaySettings.maxFrequency)
        #expect(r?.minDB == TapDisplaySettings.minMagnitude && r?.maxDB == TapDisplaySettings.maxMagnitude)
    }

    @Test func aLoad_leavesTheAnalysisRange() {
        let sut = TapToneAnalyzer.forTesting()
        sut.loadMeasurement(plate(minFreq: 24, maxFreq: 46, minDB: -75, maxDB: -61))
        #expect(sut.minFrequency == 30 && sut.maxFrequency == 2000)
    }
}
