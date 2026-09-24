//
//  StartTapSequenceRaceTests.swift
//  GuitarTapTests
//
//  Regression tests for the bug where startTapSequence()'s deferred async
//  housekeeping block at TapToneAnalyzer+Control.swift:304 redundantly re-set
//  `detectionState = .listening`, clobbering a legitimate `.idle` set by
//  `handleTapDetection` from the audio thread between the sync arming and the
//  async block running.
//
//  Repro on iPad: load a plate measurement, lower the threshold to fire on
//  background noise, switch measurement type to Generic.  A spurious tap fired
//  on the type change auto-restarted detection, the gated capture completed,
//  processMultipleTaps set isMeasurementComplete=true, but the now-stale async
//  block had already reasserted `.listening` — leaving the analyzer in the
//  impossible state (isDetecting && isMeasurementComplete) which made Pause
//  enabled and New Tap disabled even though the measurement was done.
//
//  The fix was to delete the redundant async assignment; these tests guard
//  against any reintroduction of an async path that re-asserts isDetecting in
//  startTapSequence.
//
// @parity test/start-tap-race

import Testing
import Foundation
@testable import GuitarTap

@MainActor
private func makeSUT(numberOfTaps: Int = 1) -> TapToneAnalyzer {
    let fft = RealtimeFFTAnalyzer()
    let sut = TapToneAnalyzer(fftAnalyzer: fft)
    sut.numberOfTaps = numberOfTaps
    sut.tapDetectionThreshold = -40
    sut.warmupStartAudioTime = -2  // audio clock: warm-up already elapsed
    sut.justExitedWarmup = false
    TapDisplaySettings.measurementType = .generic
    sut.cancellables.removeAll()
    // An unstarted analyzer has no frequency bins (all 0 Hz); build them as starting the engine does.
    // They are published asynchronously, so each test's wait after startTapSequence lets them land.
    sut.fftAnalyzer.actualSampleRate = 48000
    sut.fftAnalyzer.updateFrequencyBins()
    return sut
}

/// Capture one tap through the REAL completion path — the merge point of both detection paths.
@MainActor
private func captureTap(_ sut: TapToneAnalyzer) {
    let samples = (0..<sut.fftAnalyzer.fftSize).map { i -> Float in
        let t = Float(i) / 48000
        return 0.5 * expf(-t * 6) * sinf(2 * .pi * 100 * t)
    }
    sut.finishGuitarGatedCapture(samples: samples, sampleRate: 48000)
}

@Suite("StartTapSequenceRace", .serialized)
@MainActor
struct StartTapSequenceRaceTests {

    init() { TapDisplaySettings.measurementType = .generic }

    // R1: After startTapSequence arms detection synchronously, a subsequent
    // handleTapDetection-style flip to `.idle` must survive the
    // deferred async housekeeping block.  This is the exact race the line-304
    // fix addresses.
    @Test func isDetectingFalse_survives_asyncHousekeeping() async throws {
        let sut = makeSUT(numberOfTaps: 1)

        sut.startTapSequence()
        #expect(sut.isDetecting == true, "Sync arming must set detectionState = .listening")

        // Simulate the audio thread firing handleTapDetection between the sync
        // arming and the deferred housekeeping block running.  The real handler
        // sets detectionState = .idle to gate the capture window; we mirror that
        // state change directly so the test doesn't depend on the audio pipeline.
        sut.detectionState = .idle

        // Drain the deferred housekeeping block.
        try await Task.sleep(for: .milliseconds(50))

        #expect(sut.isDetecting == false,
                "Async housekeeping must NOT re-assert `.listening`; doing so clobbers handleTapDetection's intentional `.idle` and leaves the analyzer stuck in 'detecting' after the gated capture and processMultipleTaps complete.")
    }

    // R2: End-to-end repro for the iPad bug — startTapSequence, spurious tap
    // (handleTapDetection sets detectionState = .idle), the gated capture completes through the REAL
    // path, and the measurement completes on its own after the capture window. Final state must
    // satisfy the guitar-mode invariants: complete, not detecting, not paused. (The capture used to be
    // simulated by populating capturedTaps and calling processMultipleTaps by hand — #17 F48.)
    @Test func spuriousTap_onTypeChange_settles_to_complete_not_detecting() async throws {
        let sut = makeSUT(numberOfTaps: 1)

        sut.startTapSequence()
        sut.detectionState = .idle                 // handleTapDetection effect
        try await Task.sleep(for: .milliseconds(50))   // drain housekeeping
        captureTap(sut)
        try await Task.sleep(for: .seconds(sut.captureWindow + 0.3))

        #expect(sut.isMeasurementComplete == true)
        #expect(sut.isDetecting == false,
                "REGRESSION: isDetecting must be false once measurement completes")
        #expect(sut.isDetectionPaused == false)
    }

    // R3: For multi-tap guitar (numberOfTaps > 1), the same race must not strand the analyzer: three
    // real captures, the real cooldowns between them, and the real completion.
    @Test func spuriousTap_multiTap_eventually_completes_cleanly() async throws {
        let sut = makeSUT(numberOfTaps: 3)

        sut.startTapSequence()
        try await Task.sleep(for: .milliseconds(50))   // drain housekeeping
        for tap in 1...3 {
            captureTap(sut)
            if tap < 3 { try await Task.sleep(for: .seconds(sut.tapCooldown + 0.3)) }
        }
        try await Task.sleep(for: .seconds(sut.captureWindow + 0.3))

        #expect(sut.currentTapCount == 3)
        #expect(sut.isMeasurementComplete == true)
        #expect(sut.isDetecting == false)
        #expect(sut.isDetectionPaused == false)
    }

    // R4: Audio-queue gated-capture path regression — the actual iPad bug.
    //
    // The audio-queue levelCrossingHandler starts a gated capture directly
    // (sets gatedCaptureActive=true, seeds gatedAccumBuffer) without ever
    // calling handleTapDetection.  So isDetecting stays true through the
    // capture window.  When finishGuitarGatedCapture eventually runs and the
    // measurement completes, isDetecting must be false — otherwise the UI shows
    // the impossible (detecting && complete) state with Pause enabled and New
    // Tap disabled.
    //
    // This test drives the audio-queue path: it never calls handleTapDetection,
    // it goes straight from startTapSequence to finishGuitarGatedCapture (the
    // function called by both paths once the capture buffer fills), then lets the
    // measurement complete on its own — processMultipleTaps is scheduled by the
    // capture itself; calling it here as well ran it twice (#17 F48).
    @Test func audioQueueGatedCapturePath_clearsIsDetecting() async throws {
        let sut = makeSUT(numberOfTaps: 1)

        sut.startTapSequence()
        // NOTE: we intentionally do NOT simulate handleTapDetection here.
        #expect(sut.isDetecting == true, "post-startTapSequence: isDetecting must be true (detection armed)")

        let samples = [Float](repeating: 0, count: sut.fftAnalyzer.fftSize)
        sut.finishGuitarGatedCapture(samples: samples, sampleRate: 48000)

        #expect(sut.isDetecting == false,
                "REGRESSION: finishGuitarGatedCapture must clear isDetecting so the audio-queue path doesn't leave the analyzer stuck in 'detecting' through measurement completion")

        try await Task.sleep(for: .seconds(sut.captureWindow + 0.3))
        #expect(sut.isMeasurementComplete == true)
        #expect(sut.isDetecting == false)
        #expect(sut.isDetectionPaused == false)
    }

    // R5: A restart from PAUSED must end LISTENING, not paused.
    //
    // startTapSequence used to clear the pause flag up front; with one detection state it
    // simply moves to `.listening` at the arming step, and nothing in between may leave
    // `.paused` standing.  Cancel is the reachable route: the button rule DISABLES New Tap
    // while paused (a paused sequence is still in flight, B6) and ENABLES Cancel, which
    // delegates to startTapSequence in all three editions.
    @Test func restartFromPaused_endsListening() async throws {
        let sut = makeSUT(numberOfTaps: 3)

        sut.startTapSequence()
        try await Task.sleep(for: .milliseconds(50))   // drain housekeeping
        sut.currentTapCount = 1
        sut.pauseTapDetection()
        #expect(sut.isDetectionPaused == true, "precondition: the sequence is paused")

        sut.cancelTapSequence()
        try await Task.sleep(for: .milliseconds(50))

        #expect(sut.detectionState == .listening,
                "REGRESSION: a restart from paused must arm; leaving it `.paused` strands the user with a sequence they cannot resume or restart")
        #expect(sut.isDetectionPaused == false)
        #expect(sut.currentTapCount == 0)
    }
}
