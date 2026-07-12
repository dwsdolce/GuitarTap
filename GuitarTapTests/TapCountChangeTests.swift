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
//  OUT-5: the "reduce the count mid-sequence → finalise with the taps already
//  captured" branch has been REMOVED from didSet (and from Python; the web never
//  had it).  The Taps stepper is disabled from the first captured tap
//  (.disabled(currentTapCount > 0 && !isMeasurementComplete)) on every platform, so
//  the count cannot change mid-sequence — you cancel first.  The branch was therefore
//  unreachable, and being unreachable it had drifted three ways: Swift deferred by
//  captureWindow and averaged ALL captured taps; Python finalised synchronously and
//  TRUNCATED to the new count; the web did nothing.  Removed rather than reconciled.
//  NoImplicitFinaliseTests below pins the removal.
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
    let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer())
    sut.numberOfTaps = numberOfTaps
    sut.tapDetectionThreshold = -40
    sut.analyzerStartTime = Date(timeIntervalSinceNow: -2)
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
        sut.isDetecting = true       // armed, waiting for the first tap
        sut.currentTapCount = 0
        sut.numberOfTaps = 3         // didSet → refresh
        #expect(sut.statusMessage == "Tap the guitar 3 times...")
    }

    // Lowering it back also refreshes (the regression the web's PC-4 fixed:
    // "3-tap brace → Generic → Taps=1" left the bar stuck on the old count).
    @Test func loweringCountWhileArmedIdle_refreshesPrompt() {
        let sut = makeSUT(numberOfTaps: 4)
        sut.isDetecting = true
        sut.currentTapCount = 0
        sut.numberOfTaps = 1
        #expect(sut.statusMessage == "Tap the guitar...")
    }

    // An idle change (before arming / a frozen loaded result) must NOT refresh.
    @Test func changingCountWhileIdle_doesNotRefresh() {
        let sut = makeSUT(numberOfTaps: 1) // isDetecting = false
        let before = sut.statusMessage
        sut.numberOfTaps = 5
        #expect(sut.statusMessage == before)
    }

}

/// OUT-5 — a count change with taps already in hand must NOT finalise the measurement.
///
/// Guards the removal of the unreachable reduce-mid-sequence branch (see the file header).
/// Before the removal, `didSet` set `isDetecting = false`, wrote "All taps captured. Processing...",
/// and deferred `processMultipleTaps()` by `captureWindow` — averaging ALL captured taps, not the
/// newly-requested count. Python truncated instead. Neither was reachable.
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
        sut.isDetecting = true
        return sut
    }

    @Test("lowering the count TO the captured tap count does not complete the measurement")
    func loweringToCapturedCount_doesNotComplete() {
        let sut = armedWithTaps(total: 4, taps: 2) // 2 of 4 captured

        sut.numberOfTaps = 2 // count == captured — the old branch finalised here

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
        #expect(sut.capturedTaps.count == 3) // Python used to truncate to the new count
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