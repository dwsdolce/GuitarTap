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
    let fft = RealtimeFFTAnalyzer()
    let sut = TapToneAnalyzer(fftAnalyzer: fft)
    sut.numberOfTaps = numberOfTaps
    sut.tapDetectionThreshold = -40
    sut.warmupStartAudioTime = -2  // audio clock: warm-up already elapsed
    sut.justExitedWarmup = false
    TapDisplaySettings.measurementType = .generic
    sut.cancellables.removeAll()
    return sut
}

private func fakeTap() -> (magnitudes: [Float], frequencies: [Float], captureTime: Date) {
    var mags = [Float](repeating: -80, count: 64)
    mags[16] = -30
    let freqs = (0..<64).map { Float($0) * 31.25 }
    return (magnitudes: mags, frequencies: freqs, captureTime: Date())
}

// ---------------------------------------------------------------------------
// MARK: - Scenarios
// ---------------------------------------------------------------------------

@Suite("ScenarioStateTrace", .serialized)
@MainActor
struct ScenarioStateTraceTests {

    init() { TapDisplaySettings.measurementType = .generic }

    // S1: Clean single-tap guitar measurement.
    @Test func scenario_cleanSingleTap_guitar() async throws {
        let sut = makeSUT(numberOfTaps: 1)
        var trace: [StateSnapshot] = []
        trace.append(snap("init", sut))

        sut.startTapSequence()
        try await Task.sleep(for: .milliseconds(50))
        trace.append(snap("postStart", sut))

        // Simulate tap → gated capture → completion.
        sut.detectionState = .idle                 // handleTapDetection
        sut.capturedTaps = [fakeTap()]
        sut.currentTapCount = 1
        trace.append(snap("postCapture", sut))

        sut.processMultipleTaps()
        trace.append(snap("postProcess", sut))

        let expected: [StateSnapshot] = [
            StateSnapshot(label: "init",        isDetecting: false, isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 0, capturedTapsCount: 0),
            StateSnapshot(label: "postStart",   isDetecting: true,  isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 0, capturedTapsCount: 0),
            StateSnapshot(label: "postCapture", isDetecting: false, isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 1, capturedTapsCount: 1),
            StateSnapshot(label: "postProcess", isDetecting: false, isDetectionPaused: false, isMeasurementComplete: true,  currentTapCount: 1, capturedTapsCount: 1),
        ]
        #expect(trace == expected, "trace mismatch:\n  got: \(trace)\n  exp: \(expected)")
    }

    // S2: Spurious-tap-on-measurement-type-change — the iPad bug scenario.
    // Identical trace to S1 because the fix removed the divergence.  This
    // scenario exists to document that the bug scenario now produces the
    // same trace as a clean single-tap.
    @Test func scenario_spuriousTapOnTypeChange_matchesCleanSingleTap() async throws {
        let sut = makeSUT(numberOfTaps: 1)
        var trace: [StateSnapshot] = []
        trace.append(snap("init", sut))

        sut.startTapSequence()                  // triggered by type-change handler
        // Spurious tap fires BEFORE the async housekeeping block runs.
        sut.detectionState = .idle                 // handleTapDetection effect
        // NOW the housekeeping runs (post-fix: must not clobber isDetecting).
        try await Task.sleep(for: .milliseconds(50))
        trace.append(snap("postStart", sut))

        sut.capturedTaps = [fakeTap()]
        sut.currentTapCount = 1
        trace.append(snap("postCapture", sut))

        sut.processMultipleTaps()
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

        // First tap captured; re-arm for next.
        sut.capturedTaps = [fakeTap()]
        sut.currentTapCount = 1
        sut.detectionState = .listening   // scheduleGuitarReEnable result
        trace.append(snap("postTap1", sut))

        sut.pauseTapDetection()
        trace.append(snap("postPause", sut))

        sut.resumeTapDetection()
        trace.append(snap("postResume", sut))

        // Remaining taps captured; final processing.
        sut.capturedTaps = [fakeTap(), fakeTap(), fakeTap()]
        sut.currentTapCount = 3
        sut.detectionState = .idle
        sut.processMultipleTaps()
        trace.append(snap("postProcess", sut))

        let expected: [StateSnapshot] = [
            StateSnapshot(label: "init",        isDetecting: false, isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 0, capturedTapsCount: 0),
            StateSnapshot(label: "postStart",   isDetecting: true,  isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 0, capturedTapsCount: 0),
            StateSnapshot(label: "postTap1",    isDetecting: true,  isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 1, capturedTapsCount: 1),
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

        sut.capturedTaps = [fakeTap()]
        sut.currentTapCount = 1
        sut.detectionState = .listening
        trace.append(snap("postTap1", sut))

        sut.cancelTapSequence()
        try await Task.sleep(for: .milliseconds(50))
        trace.append(snap("postCancel", sut))

        let expected: [StateSnapshot] = [
            StateSnapshot(label: "init",       isDetecting: false, isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 0, capturedTapsCount: 0),
            StateSnapshot(label: "postStart",  isDetecting: true,  isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 0, capturedTapsCount: 0),
            StateSnapshot(label: "postTap1",   isDetecting: true,  isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 1, capturedTapsCount: 1),
            StateSnapshot(label: "postCancel", isDetecting: true,  isDetectionPaused: false, isMeasurementComplete: false, currentTapCount: 0, capturedTapsCount: 0),
        ]
        #expect(trace == expected, "trace mismatch:\n  got: \(trace)\n  exp: \(expected)")
    }
}
