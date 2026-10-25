//
//  LiveFrameTests.swift
//  GuitarTapTests
//
//  One contract, three mechanisms: a live FFT frame is announced on the live frame alone.
//
//  A frame comes several times a second. Whatever announces it is redrawn that often, so only the views that
//  draw a frame may hear it: announced on the engine, or by the analyzer, every frame would rebuild every view
//  that observes them — the whole main window, and a menu open in it, which then snaps back under the user's
//  finger. The values were right all along when that happened; only who was told was wrong, so the value tests
//  could not see it.
//
//  Swift checks `objectWillChange` on each object, Python which signals fire, the web which listeners and
//  callbacks are called.
//
//  Mirrors: tests/test_live_frame.py · test/live-frame.test.ts
//
// @parity test/live-frame

import Testing
import Foundation
import Combine
@testable import GuitarTap

@Suite("LiveFrame", .serialized)
@MainActor
struct LiveFrameTests {

    /// Drains the main queue, where the engine publishes.
    private func drainMain() async {
        for _ in 0..<20 { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    /// A little more than one FFT frame (65 536 samples) at 48 kHz of a quiet 1 kHz sine: well below any
    /// detection threshold.
    private func quietFrame() -> [Float] {
        (0..<70_000).map { 0.001 * sin(2 * .pi * 1000 * Float($0) / 48000) }
    }

    // LF1: a frame, while a completed measurement is on screen, is announced on the live frame and by nothing
    // else. (While a sequence runs, a frame's live peaks are announced on the detected peaks — DetectedPeaksTests.)
    @Test func frame_isAnnouncedOnTheLiveFrameAlone() async {
        let fft = RealtimeFFTAnalyzer.forTesting()
        let sut = TapToneAnalyzer(fftAnalyzer: fft)
        TapDisplaySettings.measurementType = .classical
        fft.actualSampleRate = 48000
        fft.updateFrequencyBins()
        sut.numberOfTaps = 1
        sut.capturedTaps = [MeasurementCompleteTransitionTests.capturedTap(peakDB: -30)]
        sut.processMultipleTaps()
        await drainMain()
        #expect(sut.isMeasurementComplete)

        var frame = 0, engine = 0, analyzer = 0
        let tokens = [
            fft.frame.objectWillChange.sink { _ in frame += 1 },
            fft.objectWillChange.sink { _ in engine += 1 },
            sut.objectWillChange.sink { _ in analyzer += 1 },
        ]
        defer { tokens.forEach { $0.cancel() } }

        fft.processRawSamples(quietFrame())
        await drainMain()

        #expect(frame > 0, "the frame must reach the live frame, or the chart stands still")
        #expect(engine == 0,
                "REGRESSION: the engine announced a change for one frame — every view observing it is rebuilt on every frame")
        #expect(analyzer == 0,
                "REGRESSION: the analyzer announced a change for one frame — every view observing it is rebuilt on every frame")
    }
}
