//
//  StateInvariantTests.swift
//  GuitarTapTests
//
//  Asserts state-machine invariants that must hold across every code path in
//  TapToneAnalyzer.  These tests don't drive a specific scenario — they verify
//  that the analyzer's own state, after any sequence of operations, never
//  enters a combination the design forbids.
//
//  The invariants here are the load-bearing rules that govern Pause / New Tap
//  / Cancel button enablement and the audio-thread detection guards.  A
//  refactor that accidentally violates one of these would produce a UI bug
//  like the iPad type-change race even if individual functions still look
//  correct in isolation.
//
//  Mirror in Python: tests/test_state_invariants.py.  If either side's set of
//  invariants changes, the other must follow.
//
// @parity test/state-invariants

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
    return sut
}

/// Checks that `analyzer` does not violate any of the documented state-machine
/// invariants.  Returns nil when all invariants hold, or a string describing
/// the first violation found.
///
/// Test files can call this after any operation to enforce that no path leaves
/// the analyzer in an impossible state.
@MainActor
func stateInvariantViolation(_ a: TapToneAnalyzer) -> String? {
    let isGuitar = TapDisplaySettings.measurementType.isGuitar

    // I1: For guitar mode, isDetecting && isMeasurementComplete is illegal.
    // The detector cannot be armed for a sequence that has already concluded.
    // This is the invariant the iPad bug violated.
    if isGuitar && a.isDetecting && a.isMeasurementComplete {
        return "I1: isDetecting && isMeasurementComplete is illegal in guitar mode"
    }

    // I2: isDetectionPaused implies the analyzer was actively detecting when
    // it was paused.  Pausing from a non-detecting state is meaningless.
    // Once paused, a complete measurement should drop the paused flag.
    if a.isDetectionPaused && a.isMeasurementComplete {
        return "I2: isDetectionPaused && isMeasurementComplete is illegal (cannot be paused once measurement is done)"
    }

    // I3: capturedTaps.count must never exceed numberOfTaps.  The gated
    // capture pipeline enforces this; a violation means a stray append.
    if a.capturedTaps.count > a.numberOfTaps {
        return "I3: capturedTaps.count (\(a.capturedTaps.count)) > numberOfTaps (\(a.numberOfTaps))"
    }

    // I4: currentTapCount must match capturedTaps.count for guitar mode.
    // (Plate/brace counts taps across phases differently and is excluded.)
    if isGuitar && a.currentTapCount != a.capturedTaps.count {
        return "I4: currentTapCount (\(a.currentTapCount)) != capturedTaps.count (\(a.capturedTaps.count)) in guitar mode"
    }

    // I5: tapProgress must be in [0, 1].
    if a.tapProgress < 0 || a.tapProgress > 1 {
        return "I5: tapProgress (\(a.tapProgress)) outside [0, 1]"
    }

    // I6: During a plate/brace review phase, isDetecting must be false.
    // The audio thread checks materialTapPhase.isCapturing; firing a tap during
    // a review phase would corrupt the captured spectrum.
    if !isGuitar {
        switch a.materialTapPhase {
        case .reviewingLongitudinal, .reviewingCross, .reviewingFlc:
            if a.isDetecting {
                return "I6: isDetecting must be false during a plate/brace review phase (phase=\(a.materialTapPhase))"
            }
        default:
            break
        }
    }

    return nil
}

@Suite("StateInvariants", .serialized)
@MainActor
struct StateInvariantTests {

    init() { TapDisplaySettings.measurementType = .generic }

    // V1: Fresh analyzer is in a valid state.
    @Test func freshAnalyzer_holdsInvariants() {
        let sut = makeSUT()
        #expect(stateInvariantViolation(sut) == nil)
    }

    // V2: After startTapSequence, invariants hold.
    @Test func afterStartTapSequence_holdsInvariants() async throws {
        let sut = makeSUT()
        sut.startTapSequence()
        try await Task.sleep(for: .milliseconds(50))
        #expect(stateInvariantViolation(sut) == nil)
    }

    // V3: After a single-tap guitar measurement completes via processMultipleTaps,
    // invariants hold.  This is the iPad-bug scenario's end state.
    @Test func afterSingleTapComplete_holdsInvariants() async throws {
        let sut = makeSUT(numberOfTaps: 1)
        sut.startTapSequence()
        try await Task.sleep(for: .milliseconds(50))
        sut.detectionState = .idle
        sut.capturedTaps = [fakeTap()]
        sut.currentTapCount = 1
        sut.processMultipleTaps()
        #expect(stateInvariantViolation(sut) == nil,
                "Single-tap completion must not leave the analyzer in an impossible state")
    }

    // V4: Mid-sequence for a multi-tap guitar measurement, invariants hold — reached through the
    // REAL capture path (finishGuitarGatedCapture: the merge point of both detection paths), not
    // by assigning capturedTaps / currentTapCount / detectionState by hand, which would only test
    // the checker on a state the test invented (#17 F45). Checked twice: resting through the tap
    // cooldown, and re-armed after it.
    @Test func midMultiTapSequence_holdsInvariants() async throws {
        let sut = makeSUT(numberOfTaps: 3)
        // An unstarted analyzer has no frequency bins (all 0 Hz), so a real spectrum would put every
        // peak at 0 Hz; set them up as starting the engine or file playback does.
        sut.fftAnalyzer.actualSampleRate = 48000
        sut.fftAnalyzer.updateFrequencyBins()
        sut.startTapSequence()
        try await Task.sleep(for: .milliseconds(50))
        sut.finishGuitarGatedCapture(samples: tapSamples(100, count: sut.fftAnalyzer.fftSize),
                                     sampleRate: 48000)
        #expect(sut.capturedTaps.count == 1)
        #expect(sut.isDetecting == false, "detection rests through the tap cooldown")
        #expect(stateInvariantViolation(sut) == nil, "mid-sequence, resting")

        try await Task.sleep(for: .seconds(sut.tapCooldown + 0.3))
        #expect(sut.isDetecting == true, "re-armed for the next tap once the cooldown has passed")
        #expect(stateInvariantViolation(sut) == nil, "mid-sequence, re-armed")
    }

    // V5: Cancel mid-sequence holds invariants.
    @Test func afterCancel_holdsInvariants() async throws {
        let sut = makeSUT(numberOfTaps: 3)
        sut.startTapSequence()
        try await Task.sleep(for: .milliseconds(50))
        sut.cancelTapSequence()
        try await Task.sleep(for: .milliseconds(50))
        #expect(stateInvariantViolation(sut) == nil)
    }

    // V6: Pause invariant — pausing during active detection is valid; the
    // paused state itself must hold invariants.
    @Test func afterPause_holdsInvariants() async throws {
        let sut = makeSUT(numberOfTaps: 3)
        sut.startTapSequence()
        try await Task.sleep(for: .milliseconds(50))
        sut.pauseTapDetection()
        #expect(stateInvariantViolation(sut) == nil)
    }

    // V7: Direct construction of the impossible state the iPad bug produced
    // must be flagged by the invariant checker.  If this test ever passes
    // with violation == nil, the checker itself has regressed.
    @Test func impossibleState_detectingAndComplete_isFlagged() {
        let sut = makeSUT(numberOfTaps: 1)
        sut.detectionState = .listening
        sut.isMeasurementComplete = true
        #expect(stateInvariantViolation(sut) != nil,
                "Invariant checker must reject (isDetecting && isMeasurementComplete) in guitar mode")
    }

    // V8: A plate capture reaches its REVIEW phase through the real gated path, and invariants hold
    // there — including I6 (no detection while reviewing), which no guitar case can reach (#17 F45).
    @Test func plateReviewPhase_holdsInvariants() {
        let sut = makeSUT(numberOfTaps: 1)
        TapDisplaySettings.measurementType = .plate
        defer { TapDisplaySettings.measurementType = .generic }
        sut.tapDetectionThreshold = -90 // accept the synthetic tap
        sut.startTapSequence()
        sut.finishGatedFFTCapture(samples: tapSamples(60, count: 24_000), sampleRate: 48000,
                                  phase: .capturingLongitudinal)
        #expect(sut.materialTapPhase == .reviewingLongitudinal, "one L tap completes the phase → review")
        #expect(sut.isDetecting == false)
        #expect(stateInvariantViolation(sut) == nil)
    }

    // V9–V13: each invariant the checker enforces REPORTS its forbidden state. V7 did this for I1
    // alone, so nothing showed that I2–I6 could ever fire (#17 F45).
    @Test func I2_pausedAndComplete_isFlagged() {
        let sut = makeSUT()
        sut.detectionState = .paused
        sut.isMeasurementComplete = true
        #expect(stateInvariantViolation(sut)?.hasPrefix("I2") == true)
    }

    @Test func I3_moreTapsThanRequested_isFlagged() {
        let sut = makeSUT(numberOfTaps: 1)
        sut.capturedTaps = [fakeTap(), fakeTap()]
        #expect(stateInvariantViolation(sut)?.hasPrefix("I3") == true)
    }

    @Test func I4_countOutOfStepWithTaps_isFlagged() {
        let sut = makeSUT(numberOfTaps: 3)
        sut.capturedTaps = [fakeTap()]
        sut.currentTapCount = 0
        #expect(stateInvariantViolation(sut)?.hasPrefix("I4") == true)
    }

    @Test func I5_progressOutOfRange_isFlagged() {
        let sut = makeSUT()
        sut.tapProgress = 1.5
        #expect(stateInvariantViolation(sut)?.hasPrefix("I5") == true)
    }

    @Test func I6_detectingWhileReviewing_isFlagged() {
        let sut = makeSUT()
        TapDisplaySettings.measurementType = .plate
        defer { TapDisplaySettings.measurementType = .generic }
        sut.materialTapPhase = .reviewingLongitudinal
        sut.detectionState = .listening
        #expect(stateInvariantViolation(sut)?.hasPrefix("I6") == true)
    }

    /// A decaying sinusoid — a synthetic tap with one resonance at `freqHz`.
    private func tapSamples(_ freqHz: Float, count: Int, sampleRate: Float = 48000) -> [Float] {
        (0..<count).map { i in
            let t = Float(i) / sampleRate
            return 0.5 * expf(-t * 6.0) * sinf(2 * .pi * freqHz * t)
        }
    }

    private func fakeTap(n: Int = 64) -> (magnitudes: [Float], frequencies: [Float], captureTime: Date) {
        var mags = [Float](repeating: -80, count: n)
        mags[n / 4] = -30
        let freqs = (0..<n).map { Float($0) * 31.25 }
        return (magnitudes: mags, frequencies: freqs, captureTime: Date())
    }
}
