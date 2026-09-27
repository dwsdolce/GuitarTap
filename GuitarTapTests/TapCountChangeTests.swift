//
//  TapCountChangeTests.swift
//  GuitarTapTests
//
//  Pins the model-level tap-count-change behavior: when numberOfTaps changes
//  while armed-and-waiting for the first tap, the status prompt refreshes to the
//  new count; an idle change does nothing.  This is Swift numberOfTaps.didSet —
//  the canonical behavior the Python (set_tap_num) and web
//  (TapToneAnalyzer.setNumberOfTaps) twins mirror.
//
//  There is no "reduce the count mid-sequence → finalise with the taps already
//  captured" behaviour on any platform.  The Taps stepper is disabled from the first
//  captured tap (.disabled(currentTapCount > 0 && !isMeasurementComplete)) on every
//  platform, so the count cannot change mid-sequence — you cancel first.
//  NoImplicitFinaliseTests below pins that a count change never finalises.
//
//  NOTE: there is deliberately no "unchanged value → no refresh" case: Swift's
//  didSet (and Python's set_tap_num) fire on every assignment, so an unchanged
//  write still refreshes to the identical string.  The web's ENGINE refire
//  (RealtimeFFTAnalyzer.setConfig → onProgress) does gate on changed-ness — that
//  is a web-only progress-bar optimization, tested in test/tap-count-change on the
//  web, not a cross-platform model behavior.
//
// @parity test/tap-count-change

import Testing
import Foundation
@testable import GuitarTap

@MainActor
private func makeSUT(numberOfTaps: Int = 1) -> TapToneAnalyzer {
    let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
    sut.numberOfTaps = numberOfTaps
    sut.tapDetectionThreshold = -40
    sut.warmupStartAudioTime = -2  // audio clock: warm-up already elapsed
    sut.justExitedWarmup = false
    TapDisplaySettings.measurementType = .generic
    return sut
}

@Suite("TapCountChange", .serialized)
@MainActor
struct TapCountChangeTests {

    init() { TapDisplaySettings.measurementType = .generic }

    // Raising the count while armed-and-waiting refreshes the prompt.
    @Test func raisingCountWhileArmedIdle_refreshesPrompt() {
        let sut = makeSUT(numberOfTaps: 1)
        sut.detectionState = .listening       // armed, waiting for the first tap
        sut.currentTapCount = 0
        sut.numberOfTaps = 3         // didSet → refresh
        #expect(sut.statusMessage == "Tap the guitar 3 times...")
    }

    // Lowering it back also refreshes — "3-tap brace → Generic → Taps=1" must not leave
    // the prompt on the old count.
    @Test func loweringCountWhileArmedIdle_refreshesPrompt() {
        let sut = makeSUT(numberOfTaps: 4)
        sut.detectionState = .listening
        sut.currentTapCount = 0
        sut.numberOfTaps = 1
        #expect(sut.statusMessage == "Tap the guitar...")
    }

    // An idle change (before arming / a frozen loaded result) must NOT refresh.
    @Test func changingCountWhileIdle_doesNotRefresh() {
        let sut = makeSUT(numberOfTaps: 1) // detectionState = .idle
        let before = sut.statusMessage
        sut.numberOfTaps = 5
        #expect(sut.statusMessage == before)
    }

}

/// The same hook, on a MATERIAL measurement.
///
/// Every case above is guitar, in all three editions, and the hook is shared by plate and brace.
/// At the start of a material sequence no tap has been captured, so the Taps control is still
/// unlocked (`currentTapCount > 0 && !isMeasurementComplete` is false) and detection is listening:
/// the count CAN change here, and it is the one phase whose prompt names the count.
@Suite("TapCountChange — material", .serialized)
@MainActor
struct TapCountChangeMaterialTests {

    private func plateSUT(numberOfTaps: Int, measureFlc: Bool) -> TapToneAnalyzer {
        TapDisplaySettings.measurementType = .plate
        TapDisplaySettings.measureFlc = measureFlc
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        sut.numberOfTaps = numberOfTaps
        sut.materialTapPhase = .capturingLongitudinal
        sut.currentTapCount = 0
        sut.detectionState = .listening
        return sut
    }

    @Test("raising Taps at the start of a plate sequence refreshes the fL arm prompt")
    func raisingCountAtPlateStart_refreshesTheMaterialArmPrompt() {
        let sut = plateSUT(numberOfTaps: 1, measureFlc: false)

        sut.numberOfTaps = 3

        #expect(sut.statusMessage == "Ready for fL tap (×3 each for L, C)",
                "REGRESSION: the hook called the GUITAR prompt, so changing Taps during a plate measurement said \"Tap the guitar 3 times...\"")
    }

    @Test("the FLC setting is reflected in the refreshed prompt")
    func raisingCountAtPlateStart_withFlc_namesAllThreePhases() {
        let sut = plateSUT(numberOfTaps: 1, measureFlc: true)

        sut.numberOfTaps = 2

        #expect(sut.statusMessage == "Ready for fL tap (×2 each for L, C, FLC)")
    }

    @Test("a brace sequence gets the brace variant, which names no phases")
    func raisingCountAtBraceStart_usesTheBracePrompt() {
        TapDisplaySettings.measurementType = .brace
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        sut.numberOfTaps = 1
        sut.materialTapPhase = .capturingLongitudinal
        sut.currentTapCount = 0
        sut.detectionState = .listening

        sut.numberOfTaps = 4

        #expect(sut.statusMessage == "Ready for fL tap (×4)")
    }

    /// The guard, not the prompt. `currentTapCount` is CUMULATIVE across L → C → FLC while
    /// `capturedTaps` is the within-phase buffer, cleared at every phase completion — so a guard
    /// written against the buffer reads "nothing captured yet" at the start of every phase, and would
    /// rewrite the fC instruction mid-measurement.
    @Test("mid-sequence, at a later phase, the hook stays silent")
    func countChangeAtALaterPhase_doesNotRewriteTheInstruction() {
        TapDisplaySettings.measurementType = .plate
        TapDisplaySettings.measureFlc = false
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        sut.numberOfTaps = 3
        sut.materialTapPhase = .capturingCross
        sut.capturedTaps = []            // the phase buffer is empty — L's taps were consumed
        sut.currentTapCount = 3          // but three taps ARE captured for this measurement
        sut.detectionState = .listening
        // The string a REDO leaves on screen — deliberately NOT what the hook would derive for this
        // phase, so "the hook stayed silent" and "the hook fired" are distinguishable. Asserting the
        // derived string here passed under both, which is an assertion true by construction.
        sut.statusMessage = "Ready for fC tap — tap again"

        sut.numberOfTaps = 5

        #expect(sut.statusMessage == "Ready for fC tap — tap again",
                "REGRESSION: the guard read the within-phase buffer, which is empty at every phase boundary, so the hook fired mid-measurement and overwrote the instruction")
    }
}

/// A count change with taps already in hand must NOT finalise the measurement, stop detection,
/// or drop captured taps (see the file header).
@Suite("TapCountChange — no implicit finalise", .serialized)
@MainActor
struct NoImplicitFinaliseTests {

    init() { TapDisplaySettings.measurementType = .generic }

    private func armedWithTaps(total: Int, taps: Int) -> TapToneAnalyzer {
        let sut = makeSUT(numberOfTaps: total)
        let mags = [Float](repeating: -60, count: 64)
        let freqs = (0..<64).map { Float($0) * 30 }
        sut.capturedTaps = (0..<taps).map { _ in
            (magnitudes: mags, frequencies: freqs, captureTime: Date())
        }
        sut.currentTapCount = taps
        sut.detectionState = .listening
        return sut
    }

    @Test("lowering the count TO the captured tap count does not complete the measurement")
    func loweringToCapturedCount_doesNotComplete() {
        let sut = armedWithTaps(total: 4, taps: 2) // 2 of 4 captured

        sut.numberOfTaps = 2 // count == captured

        #expect(sut.isMeasurementComplete == false)
        #expect(sut.isDetecting == true)
        #expect(sut.capturedTaps.count == 2) // not averaged away
    }

    @Test("lowering the count BELOW the captured tap count does not complete or truncate")
    func loweringBelowCapturedCount_doesNotCompleteOrTruncate() {
        let sut = armedWithTaps(total: 4, taps: 3)

        sut.numberOfTaps = 1 // captured (3) > new total (1)

        #expect(sut.isMeasurementComplete == false)
        #expect(sut.isDetecting == true)
        #expect(sut.capturedTaps.count == 3) // not truncated to the new count
    }

    @Test("raising the count keeps the taps already captured")
    func raisingCount_keepsCapturedTaps() {
        let sut = armedWithTaps(total: 3, taps: 2)

        sut.numberOfTaps = 5

        #expect(sut.isMeasurementComplete == false)
        #expect(sut.capturedTaps.count == 2)
        #expect(sut.numberOfTaps == 5)
    }
}