//
//  ScenarioStateTraceTests.swift
//  GuitarTapTests
//
//  Drives the analyzer through end-to-end scenarios and asserts that the
//  sequence of (isDetecting, isDetectionPaused, isMeasurementComplete,
//  currentTapCount, capturedTapsCount) tuples matches a canonical trace.
//
//  These tests pin the state path, not just the final outcome.  Two
//  implementations (Swift, Python) can produce the same final result via
//  different intermediate states; the parity bar requires the intermediate
//  states match too, because UI behavior is driven by them in real time.
//
//  Mirror in Python: tests/test_scenario_state_trace.py.  The canonical
//  trace for each scenario is hardcoded identically in both languages — if
//  one side changes, the other must follow.
//
// @parity test/scenario-trace

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Snapshot
// ---------------------------------------------------------------------------

struct StateSnapshot: Equatable, CustomStringConvertible {
    let label: String
    let isDetecting: Bool
    let isDetectionPaused: Bool
    let isMeasurementComplete: Bool
    let currentTapCount: Int
    let capturedTapsCount: Int

    var description: String {
        "\(label): det=\(isDetecting) paused=\(isDetectionPaused) complete=\(isMeasurementComplete) tapCount=\(currentTapCount) capt=\(capturedTapsCount)"
    }

    static func == (a: StateSnapshot, b: StateSnapshot) -> Bool {
        return a.label == b.label &&
               a.isDetecting == b.isDetecting &&
               a.isDetectionPaused == b.isDetectionPaused &&
               a.isMeasurementComplete == b.isMeasurementComplete &&
               a.currentTapCount == b.currentTapCount &&
               a.capturedTapsCount == b.capturedTapsCount
    }
}

@MainActor
private func snap(_ label: String, _ a: TapToneAnalyzer) -> StateSnapshot {
    StateSnapshot(label: label,
                  isDetecting: a.isDetecting,
                  isDetectionPaused: a.isDetectionPaused,
                  isMeasurementComplete: a.isMeasurementComplete,
                  currentTapCount: a.currentTapCount,
                  capturedTapsCount: a.capturedTaps.count)
}

@MainActor
private func makeSUT(numberOfTaps: Int = 1) -> TapToneAnalyzer {
    let fft = RealtimeFFTAnalyzer.forTesting()
    let sut = TapToneAnalyzer(fftAnalyzer: fft)
    sut.numberOfTaps = numberOfTaps
    sut.tapDetectionThreshold = -40
    sut.warmupStartAudioTime = -2  // audio clock: warm-up already elapsed
    sut.justExitedWarmup = false
    TapDisplaySettings.measurementType = .generic
    sut.cancellables.removeAll()
    // An unstarted analyzer has no frequency bins (all 0 Hz), so a real capture would put every peak
    // at 0 Hz. Build them as starting the engine does. They are published asynchronously on the main
    // queue, so each scenario's wait after startTapSequence is what lets them land (#17 F46).
    sut.fftAnalyzer.actualSampleRate = 48000
    sut.fftAnalyzer.updateFrequencyBins()
    return sut
}

/// A decaying sinusoid the length of one guitar capture — a synthetic tap at 100 Hz.
@MainActor
private func tapSamples(_ sut: TapToneAnalyzer) -> [Float] {
    (0..<sut.fftAnalyzer.fftSize).map { i in
        let t = Float(i) / 48000
        return 0.5 * expf(-t * 6) * sinf(2 * .pi * 100 * t)
    }
}

/// Capture one tap through the REAL completion path — the merge point of both detection paths.
@MainActor
private func captureTap(_ sut: TapToneAnalyzer) {
    sut.finishGuitarGatedCapture(samples: tapSamples(sut), sampleRate: 48000)
}

// ---------------------------------------------------------------------------
// MARK: - Scenarios
// ---------------------------------------------------------------------------

// Every tap goes through the real `finishGuitarGatedCapture`, and the waits are the real ones — the
// tap cooldown before re-arming, the capture window before averaging — measured, as the app measures
// them, in AUDIO fed through `onChunkLevel` (#19). The traces used to assign the
// "tap happened" state by hand, so their capture rows recorded what the TEST wrote; and S3/S4's
// `postTap1` said detection was back on the instant a tap was captured, a path the app never takes
// (#17 F46). These traces are identical in Swift, Python and web.
@Suite("ScenarioStateTrace", .serialized)
@MainActor
struct ScenarioStateTraceTests {

    init() { TapDisplaySettings.measurementType = .generic }

    private func afterCooldown(_ sut: TapToneAnalyzer) {
        advanceAudio(sut, by: sut.tapCooldown)
    }
    private func afterCaptureWindow(_ sut: TapToneAnalyzer) {
        advanceAudio(sut, by: sut.captureWindow)
    }

    // S1: Clean single-tap guitar measurement.
    @Test func scenario_cleanSingleTap_guitar() async throws {
        let sut = makeSUT(numberOfTaps: 1)
        var trace: [StateSnapshot] = []
        trace.append(snap("init", sut))

        sut.startTapSequence()
        try await Task.sleep(for: .milliseconds(50))
        trace.append(snap("postStart", sut))

        captureTap(sut)
        trace.append(snap("postCapture", sut))

        afterCaptureWindow(sut)          // completion averages after the capture window
        trace.append(snap("postProcess", sut))

        let expected: [StateSnapshot] = [
            StateSnapshot(label: "init",        isDetecting: false, isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 0, capturedTapsCount: 0),
            StateSnapshot(label: "postStart",   isDetecting: true,  isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 0, capturedTapsCount: 0),
            StateSnapshot(label: "postCapture", isDetecting: false, isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 1, capturedTapsCount: 1),
            StateSnapshot(label: "postProcess", isDetecting: false, isDetectionPaused: false, isMeasurementComplete: true,  currentTapCount: 1, capturedTapsCount: 1),
        ]
        #expect(trace == expected, "trace mismatch:\n  got: \(trace)\n  exp: \(expected)")
    }

    // S2: Spurious-tap-on-measurement-type-change — the iPad bug scenario. The stray DETECTION is
    // simulated (it is the scenario); the capture that follows is real. Same trace as S1.
    @Test func scenario_spuriousTapOnTypeChange_matchesCleanSingleTap() async throws {
        let sut = makeSUT(numberOfTaps: 1)
        var trace: [StateSnapshot] = []
        trace.append(snap("init", sut))

        sut.startTapSequence()                  // triggered by type-change handler
        // Spurious tap fires BEFORE the async housekeeping block runs.
        sut.detectionState = .idle              // handleTapDetection effect
        // NOW the housekeeping runs (post-fix: must not clobber isDetecting).
        try await Task.sleep(for: .milliseconds(50))
        trace.append(snap("postStart", sut))

        captureTap(sut)
        trace.append(snap("postCapture", sut))

        afterCaptureWindow(sut)
        trace.append(snap("postProcess", sut))

        let expected: [StateSnapshot] = [
            StateSnapshot(label: "init",        isDetecting: false, isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 0, capturedTapsCount: 0),
            StateSnapshot(label: "postStart",   isDetecting: false, isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 0, capturedTapsCount: 0),
            StateSnapshot(label: "postCapture", isDetecting: false, isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 1, capturedTapsCount: 1),
            StateSnapshot(label: "postProcess", isDetecting: false, isDetectionPaused: false, isMeasurementComplete: true,  currentTapCount: 1, capturedTapsCount: 1),
        ]
        #expect(trace == expected, "REGRESSION: spurious-tap trace must end in `.idle` at every checkpoint; if the state is `.listening` at postStart, the line-304 race has been reintroduced")
    }

    // S3: Multi-tap with mid-sequence pause/resume.
    @Test func scenario_multiTap_pauseResume() async throws {
        let sut = makeSUT(numberOfTaps: 3)
        var trace: [StateSnapshot] = []
        trace.append(snap("init", sut))

        sut.startTapSequence()
        try await Task.sleep(for: .milliseconds(50))
        trace.append(snap("postStart", sut))

        captureTap(sut)                            // tap 1: detection rests through the cooldown
        trace.append(snap("postTap1", sut))

        advanceAudio(sut, by: sut.tapCooldown / 2)   // halfway: still resting
        trace.append(snap("midCooldown", sut))

        advanceAudio(sut, by: sut.tapCooldown / 2)   // ...then re-arms
        trace.append(snap("postReArm", sut))

        sut.pauseTapDetection()
        trace.append(snap("postPause", sut))

        sut.resumeTapDetection()
        trace.append(snap("postResume", sut))

        captureTap(sut)                            // tap 2
        afterCooldown(sut)
        captureTap(sut)                            // tap 3 — the last
        afterCaptureWindow(sut)
        trace.append(snap("postProcess", sut))

        let expected: [StateSnapshot] = [
            StateSnapshot(label: "init",        isDetecting: false, isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 0, capturedTapsCount: 0),
            StateSnapshot(label: "postStart",   isDetecting: true,  isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 0, capturedTapsCount: 0),
            StateSnapshot(label: "postTap1",    isDetecting: false, isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 1, capturedTapsCount: 1),
            StateSnapshot(label: "midCooldown", isDetecting: false, isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 1, capturedTapsCount: 1),
            StateSnapshot(label: "postReArm",   isDetecting: true,  isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 1, capturedTapsCount: 1),
            StateSnapshot(label: "postPause",   isDetecting: false, isDetectionPaused: true,  isMeasurementComplete: false, currentTapCount: 1, capturedTapsCount: 1),
            StateSnapshot(label: "postResume",  isDetecting: true,  isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 1, capturedTapsCount: 1),
            StateSnapshot(label: "postProcess", isDetecting: false, isDetectionPaused: false, isMeasurementComplete: true,  currentTapCount: 3, capturedTapsCount: 3),
        ]
        #expect(trace == expected, "trace mismatch:\n  got: \(trace)\n  exp: \(expected)")
    }

    // S4: Multi-tap cancelled mid-sequence.  Cancel is a restart — cancelTapSequence
    // re-arms a fresh sequence (≡ New Tap): detectionState = .listening, isMeasurementComplete=false,
    // counts reset to 0.
    @Test func scenario_multiTap_cancel() async throws {
        let sut = makeSUT(numberOfTaps: 3)
        var trace: [StateSnapshot] = []
        trace.append(snap("init", sut))

        sut.startTapSequence()
        try await Task.sleep(for: .milliseconds(50))
        trace.append(snap("postStart", sut))

        captureTap(sut)
        trace.append(snap("postTap1", sut))

        advanceAudio(sut, by: sut.tapCooldown / 2)   // halfway: still resting
        trace.append(snap("midCooldown", sut))

        advanceAudio(sut, by: sut.tapCooldown / 2)
        trace.append(snap("postReArm", sut))

        sut.cancelTapSequence()
        try await Task.sleep(for: .milliseconds(50))
        trace.append(snap("postCancel", sut))

        let expected: [StateSnapshot] = [
            StateSnapshot(label: "init",       isDetecting: false, isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 0, capturedTapsCount: 0),
            StateSnapshot(label: "postStart",  isDetecting: true,  isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 0, capturedTapsCount: 0),
            StateSnapshot(label: "postTap1",   isDetecting: false, isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 1, capturedTapsCount: 1),
            StateSnapshot(label: "midCooldown",isDetecting: false, isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 1, capturedTapsCount: 1),
            StateSnapshot(label: "postReArm",  isDetecting: true,  isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 1, capturedTapsCount: 1),
            StateSnapshot(label: "postCancel", isDetecting: true,  isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 0, capturedTapsCount: 0),
        ]
        #expect(trace == expected, "trace mismatch:\n  got: \(trace)\n  exp: \(expected)")
    }
}
