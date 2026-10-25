//
//  DetectedPeaksTests.swift
//  GuitarTapTests
//
//  One contract, three mechanisms: the detected peaks are announced on the detected peaks alone.
//
//  While a sequence waits for a tap, every live frame finds the peaks again. Whatever announces them is redrawn at
//  the frame rate, so only the views that show peaks may hear it: announced by the analyzer, every frame would
//  rebuild every view that observes it — the whole main window, and on iOS a menu open anywhere in the window,
//  which loses the item under the user's finger. The peaks were right all along when that happened; only who was
//  told was wrong, so the value tests could not see it.
//
//  Swift checks `objectWillChange` on each object, Python which signals fire, the web which listeners are called.
//
//  Mirrors: tests/test_detected_peaks.py · test/detected-peaks.test.ts
//
// @parity test/detected-peaks

import Testing
import Foundation
import Combine
@testable import GuitarTap

@Suite("DetectedPeaks", .serialized)
@MainActor
struct DetectedPeaksTests {

    /// A spectrum with one clear peak at bin 200 (about 146 Hz at 0.73 Hz a bin), on a −90 dB floor.
    private func spectrumWithPeak() -> (magnitudes: [Float], frequencies: [Float]) {
        PeakFindingTests.spectrum(["kind": "triangle", "binCount": 4096, "binSpacingHz": 0.732,
                                   "peakBin": 200, "peakDB": -30.0, "slopeDBPerBin": 2.0])
    }

    /// An analyzer waiting for a tap on a running engine, the way a live frame finds it.
    private func waitingForATap() -> TapToneAnalyzer {
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        TapDisplaySettings.measurementType = .classical
        sut.numberOfTaps = 1
        sut.startTapSequence(skipWarmup: true)
        sut.fftAnalyzer.isRunning = true   // a frame comes only from the running engine
        return sut
    }

    // DP1: while waiting for a tap, a frame's peaks are announced on the detected peaks, and the analyzer
    // announces nothing.
    @Test func livePeaks_areAnnouncedOnTheDetectedPeaksAlone() {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        let sut = waitingForATap()
        #expect(sut.isDetecting)

        var peaks = 0, analyzer = 0
        let tokens = [
            sut.peaks.objectWillChange.sink { _ in peaks += 1 },
            sut.objectWillChange.sink { _ in analyzer += 1 },
        ]
        defer { tokens.forEach { $0.cancel() } }

        let (magnitudes, frequencies) = spectrumWithPeak()
        for _ in 0..<3 {
            sut.analyzeMagnitudes(magnitudes, frequencies: frequencies, peakMagnitude: magnitudes.max()!)
        }

        #expect(!sut.allPeaks.isEmpty, "the frame must find its peak, or the test proves nothing")
        #expect(peaks > 0, "the peaks must reach the detected peaks, or the chart and Results stand still")
        #expect(analyzer == 0,
                "REGRESSION: the analyzer announced a change for a frame's peaks — every view observing it is rebuilt on every frame")
    }

    // DP2: a frame with no peaks, while waiting for a tap, is not announced by the analyzer either.
    @Test func noPeaks_areNotAnnouncedByTheAnalyzer() {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        let sut = waitingForATap()

        var analyzer = 0
        let token = sut.objectWillChange.sink { _ in analyzer += 1 }
        defer { token.cancel() }

        let (magnitudes, frequencies) = PeakFindingTests.spectrum(["kind": "flat", "binCount": 4096,
                                                                   "binSpacingHz": 0.732, "value": -100.0])
        for _ in 0..<3 {
            sut.analyzeMagnitudes(magnitudes, frequencies: frequencies, peakMagnitude: -100)
        }

        #expect(analyzer == 0,
                "REGRESSION: the analyzer announced a change for a frame with no peaks — every view observing it is rebuilt on every frame")
    }
}
