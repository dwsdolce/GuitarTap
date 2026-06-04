//
//  StartTapSequenceRaceTests.swift
//  GuitarTapTests
//
//  Regression tests for the bug where startTapSequence()'s deferred async
//  housekeeping block at TapToneAnalyzer+Control.swift:304 redundantly re-set
//  `isDetecting = true`, clobbering a legitimate `false` set by
//  `handleTapDetection` from the audio thread between the sync arming and the
//  async block running.
//
//  Repro on iPad: load a plate measurement, lower the threshold to fire on
//  background noise, switch measurement type to Generic.  A spurious tap fired
//  on the type change auto-restarted detection, the gated capture completed,
//  processMultipleTaps set isMeasurementComplete=true, but the now-stale async
//  block had already reasserted isDetecting=true — leaving the analyzer in the
//  impossible state (isDetecting && isMeasurementComplete) which made Pause
//  enabled and New Tap disabled even though the measurement was done.
//
//  The fix was to delete the redundant async assignment; these tests guard
//  against any reintroduction of an async path that re-asserts isDetecting in
//  startTapSequence.
//

import Testing
import Foundation
@testable import GuitarTap

@MainActor
private func makeSUT(numberOfTaps: Int = 1) -> TapToneAnalyzer {
    let fft = RealtimeFFTAnalyzer()
    let sut = TapToneAnalyzer(fftAnalyzer: fft)
    sut.numberOfTaps = numberOfTaps
    sut.tapDetectionThreshold = -40
    sut.analyzerStartTime = Date(timeIntervalSinceNow: -2)
    sut.justExitedWarmup = false
    TapDisplaySettings.measurementType = .generic
    sut.cancellables.removeAll()
    return sut
}

private func fakeTap(n: Int = 64, peakDB: Float = -30) -> (magnitudes: [Float], frequencies: [Float], captureTime: Date) {
    var mags = [Float](repeating: -80, count: n)
    mags[n / 4] = peakDB
    let freqs = (0..<n).map { Float($0) * 31.25 }
    return (magnitudes: mags, frequencies: freqs, captureTime: Date())
}

@Suite("StartTapSequenceRace", .serialized)
@MainActor
struct StartTapSequenceRaceTests {

    init() { TapDisplaySettings.measurementType = .generic }

    // R1: After startTapSequence arms detection synchronously, a subsequent
    // handleTapDetection-style flip of isDetecting=false must survive the
    // deferred async housekeeping block.  This is the exact race the line-304
    // fix addresses.
    @Test func isDetectingFalse_survives_asyncHousekeeping() async throws {
        let sut = makeSUT(numberOfTaps: 1)

        sut.startTapSequence()
        #expect(sut.isDetecting == true, "Sync arming must set isDetecting=true")

        // Simulate the audio thread firing handleTapDetection between the sync
        // arming and the deferred housekeeping block running.  The real handler
        // sets isDetecting=false to gate the capture window; we mirror that
        // state change directly so the test doesn't depend on the audio pipeline.
        sut.isDetecting = false

        // Drain the deferred housekeeping block.
        try await Task.sleep(for: .milliseconds(50))

        #expect(sut.isDetecting == false,
                "Async housekeeping must NOT re-assert isDetecting=true; doing so clobbers handleTapDetection's intentional false and leaves the analyzer stuck in 'detecting' after the gated capture and processMultipleTaps complete.")
    }

    // R2: End-to-end repro for the iPad bug — startTapSequence, spurious tap
    // (handleTapDetection sets isDetecting=false), gated capture completes
    // (we simulate by populating capturedTaps), processMultipleTaps finishes
    // the measurement.  Final state must satisfy the guitar-mode invariants:
    // measurement complete, not detecting, not paused.
    @Test func spuriousTap_onTypeChange_settles_to_complete_not_detecting() async throws {
        let sut = makeSUT(numberOfTaps: 1)

        sut.startTapSequence()
        sut.isDetecting = false                 // handleTapDetection effect
        try await Task.sleep(for: .milliseconds(50))   // drain housekeeping
        sut.capturedTaps = [fakeTap()]          // gated capture finished
        sut.processMultipleTaps()

        #expect(sut.isMeasurementComplete == true)
        #expect(sut.isDetecting == false,
                "REGRESSION: isDetecting must be false once measurement completes")
        #expect(sut.isDetectionPaused == false)
    }

    // R3: For multi-tap guitar (numberOfTaps > 1), the same race must not
    // strand the analyzer.  Mid-sequence we expect (isDetecting=true,
    // isMeasurementComplete=false); after completion we expect
    // (isDetecting=false, isMeasurementComplete=true).
    @Test func spuriousTap_multiTap_eventually_completes_cleanly() async throws {
        let sut = makeSUT(numberOfTaps: 3)

        sut.startTapSequence()
        try await Task.sleep(for: .milliseconds(50))   // drain housekeeping

        // Simulate three taps captured by the gated path.
        sut.capturedTaps = [fakeTap(), fakeTap(), fakeTap()]
        sut.currentTapCount = 3
        sut.isDetecting = false
        sut.processMultipleTaps()

        #expect(sut.isMeasurementComplete == true)
        #expect(sut.isDetecting == false)
        #expect(sut.isDetectionPaused == false)
    }

    // R4: Audio-queue gated-capture path regression — the actual iPad bug.
    //
    // The audio-queue levelCrossingHandler starts a gated capture directly
    // (sets gatedCaptureActive=true, seeds gatedAccumBuffer) without ever
    // calling handleTapDetection.  So isDetecting stays true through the
    // capture window.  When finishGuitarGatedCapture eventually runs and
    // processMultipleTaps completes the measurement, isDetecting must be
    // false — otherwise the UI shows the impossible (detecting && complete)
    // state with Pause enabled and New Tap disabled.
    //
    // R1–R3 above drive the MODEL through the RMS path (they directly mutate
    // isDetecting=false to simulate handleTapDetection); they passed even
    // with the iPad bug present because they bypass the audio-queue path
    // that exhibited it.  This test drives the audio-queue path: it never
    // calls handleTapDetection, it goes straight from startTapSequence to
    // finishGuitarGatedCapture (the function called by both paths once the
    // capture buffer fills).
    @Test func audioQueueGatedCapturePath_clearsIsDetecting() async throws {
        let sut = makeSUT(numberOfTaps: 1)

        sut.startTapSequence()
        // NOTE: we intentionally do NOT simulate handleTapDetection here.
        // This mirrors the audio-queue path where the level-crossing handler
        // starts a gated capture directly and the RMS handler never runs.
        #expect(sut.isDetecting == true, "post-startTapSequence: isDetecting must be true (detection armed)")

        // finishGuitarGatedCapture is the merge point for both paths.
        // Pass a synthetic raw-sample buffer of fftSize length.
        let fftSize = sut.fftAnalyzer.fftSize
        let samples = [Float](repeating: 0, count: fftSize)
        sut.finishGuitarGatedCapture(samples: samples, sampleRate: 48000)

        #expect(sut.isDetecting == false,
                "REGRESSION: finishGuitarGatedCapture must clear isDetecting so the audio-queue path doesn't leave the analyzer stuck in 'detecting' through measurement completion")

        // Now run processMultipleTaps to finish the measurement.  The end
        // state must satisfy the invariants — isMeasurementComplete=true,
        // isDetecting=false, isDetectionPaused=false.
        sut.processMultipleTaps()
        #expect(sut.isMeasurementComplete == true)
        #expect(sut.isDetecting == false)
        #expect(sut.isDetectionPaused == false)
    }
}
