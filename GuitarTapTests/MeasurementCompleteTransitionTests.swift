//
//  MeasurementCompleteTransitionTests.swift
//  GuitarTapTests
//
//  Tests for isMeasurementComplete state transitions in TapToneAnalyzer.
//
//  ## Why this file exists
//
//  `isMeasurementComplete` is the single boolean that gates whether the
//  spectrum display freezes or continues to render live FFT frames.  It must
//  be set true by every capture-completion path and false by every
//  reset/cancel path.
//
//  The same bug class was found in the Python port (frozen spectrum not
//  freezing after guitar tap) because _finish_capture() set frozenMagnitudes
//  directly but never called set_measurement_complete(True).  These tests
//  are the guard in both codebases against that regression.
//
//  ## Critical-flag rule (audit guidelines Rule 8)
//
//  For `isMeasurementComplete` — and any other critical state flag — EVERY
//  code path that should set it true or false must have a test here.
//  Adding a new completion path in Swift without adding a test here is a gap.
//
//  Test plan coverage: MC1–MC9
//
// @parity test/measurement-complete

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

/// Build a non-running TapToneAnalyzer in guitar mode with warm-up satisfied.
@MainActor
private func makeSUT(numberOfTaps: Int = 1) -> TapToneAnalyzer {
    let fft = RealtimeFFTAnalyzer()
    let sut = TapToneAnalyzer(fftAnalyzer: fft)
    sut.numberOfTaps = numberOfTaps
    sut.tapDetectionThreshold = -40
    sut.warmupStartAudioTime = -2  // audio clock: warm-up already elapsed
    sut.justExitedWarmup = false
    TapDisplaySettings.measurementType = .classical
    // Disconnect Combine subs so $magnitudes cannot race with test assertions.
    sut.cancellables.removeAll()
    return sut
}

/// A synthetic captured tap: one bin of -30 dBFS at index 16, rest at -80.
private func fakeTap(n: Int = 64, peakDB: Float = -30) -> (magnitudes: [Float], frequencies: [Float], captureTime: Date) {
    var mags = [Float](repeating: -80, count: n)
    mags[n / 4] = peakDB
    let freqs = (0..<n).map { Float($0) * 31.25 }
    return (magnitudes: mags, frequencies: freqs, captureTime: Date())
}

// ---------------------------------------------------------------------------
// MARK: - Suite
// ---------------------------------------------------------------------------

@Suite("MeasurementCompleteTransitions", .serialized)
@MainActor
struct MeasurementCompleteTransitionTests {

    init() { TapDisplaySettings.measurementType = .classical }

    // MC1: processMultipleTaps sets isMeasurementComplete = true
    @Test func processMultipleTaps_setsIsMeasurementComplete() {
        let sut = makeSUT(numberOfTaps: 1)
        sut.capturedTaps = [fakeTap()]
        sut.processMultipleTaps()
        #expect(sut.isMeasurementComplete == true,
                "processMultipleTaps must set isMeasurementComplete = true")
    }

    // MC2: processMultipleTaps populates frozenMagnitudes and frozenFrequencies
    @Test func processMultipleTaps_populatesFrozenSpectrum() {
        let sut = makeSUT(numberOfTaps: 1)
        sut.capturedTaps = [fakeTap()]
        sut.processMultipleTaps()
        #expect(!sut.frozenMagnitudes.isEmpty,
                "frozenMagnitudes must be populated after processMultipleTaps")
        #expect(!sut.frozenFrequencies.isEmpty,
                "frozenFrequencies must be populated after processMultipleTaps")
    }

    // MC3: processMultipleTaps with two taps still sets isMeasurementComplete
    @Test func processMultipleTaps_multiTap_setsIsMeasurementComplete() {
        let sut = makeSUT(numberOfTaps: 2)
        sut.capturedTaps = [fakeTap(peakDB: -32), fakeTap(peakDB: -28)]
        sut.processMultipleTaps()
        #expect(sut.isMeasurementComplete == true)
    }

    // MC4: startTapSequence sets isMeasurementComplete = false.
    // startTapSequence dispatches to DispatchQueue.main.async, so the test
    // must be async and yield before reading back state.
    @Test func startTapSequence_clearsMeasurementComplete() async {
        let sut = makeSUT(numberOfTaps: 1)
        // Simulate a completed measurement
        sut.capturedTaps = [fakeTap()]
        sut.processMultipleTaps()
        #expect(sut.isMeasurementComplete == true)

        sut.startTapSequence()
        await Task.yield()   // let the main.async block execute
        #expect(sut.isMeasurementComplete == false,
                "startTapSequence must reset isMeasurementComplete to false")
    }

    // MC5: Cancel is a restart — it re-arms a fresh sequence (≡ New Tap), which clears
    // the frozen spectrum, resets isMeasurementComplete to false, and re-arms detection.
    @Test func cancelTapSequence_reArmsAndClearsFrozen() {
        let sut = makeSUT(numberOfTaps: 1)
        sut.capturedTaps = [fakeTap()]
        sut.processMultipleTaps()
        #expect(!sut.frozenMagnitudes.isEmpty)
        #expect(sut.isMeasurementComplete == true)

        sut.cancelTapSequence()
        #expect(sut.frozenMagnitudes.isEmpty, "cancel must clear frozenMagnitudes")
        #expect(sut.frozenFrequencies.isEmpty, "cancel must clear frozenFrequencies")
        #expect(sut.isMeasurementComplete == false, "cancel re-arms → measurement not complete")
        #expect(sut.isDetecting == true, "cancel re-arms detection")
    }

    // MC6: processMultipleTaps with empty capturedTaps does NOT set isMeasurementComplete
    @Test func processMultipleTaps_emptyTaps_doesNotComplete() {
        let sut = makeSUT(numberOfTaps: 1)
        // capturedTaps is empty — guard should bail out
        sut.capturedTaps = []
        sut.processMultipleTaps()
        #expect(sut.isMeasurementComplete == false,
                "processMultipleTaps with no taps must not set isMeasurementComplete")
    }

    // MC7: loadMeasurement sets isMeasurementComplete = true
    @Test func loadMeasurement_setsIsMeasurementComplete() {
        let sut = makeSUT()
        #expect(sut.isMeasurementComplete == false)

        // Build a minimal measurement with a spectrum snapshot.
        // SpectrumSnapshot requires axis range params; TapToneMeasurement.init
        // takes spectrum: (not spectrumSnapshot:) and has no measurementType param.
        let freqs = (0..<64).map { Float($0) * 31.25 }
        var mags = [Float](repeating: -80, count: 64)
        mags[16] = -30
        let snap = SpectrumSnapshot(
            frequencies: freqs,
            magnitudes: mags,
            minFreq: 0,
            maxFreq: 2000,
            minDB: -90,
            maxDB: -20,
            isLogarithmic: false,
            measurementType: .classical
        )
        let m = TapToneMeasurement(
            peaks: [],
            spectrum: snap,
            numberOfTaps: 1
        )
        sut.loadMeasurement(m)
        #expect(sut.isMeasurementComplete == true,
                "loadMeasurement must set isMeasurementComplete = true")
    }

    // MC8: isMeasurementComplete.didSet clears showLoadedSettingsWarning
    @Test func isMeasurementComplete_didSet_clearsSettingsWarning() {
        let sut = makeSUT()
        sut.showLoadedSettingsWarning = true
        sut.capturedTaps = [fakeTap()]
        sut.processMultipleTaps()
        #expect(sut.showLoadedSettingsWarning == false,
                "isMeasurementComplete = true must clear showLoadedSettingsWarning")
    }
}
