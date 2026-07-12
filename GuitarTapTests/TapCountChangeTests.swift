//
//  TapCountChangeTests.swift
//  GuitarTapTests
//
//  Pins the model-level tap-count-change behavior: when numberOfTaps changes
//  while armed-and-waiting for the first tap, the status prompt refreshes to the
//  new count; reducing it to at-or-below the taps already captured mid-sequence
//  processes immediately; an idle change does nothing.  This is Swift
//  numberOfTaps.didSet — the canonical behavior the Python (set_tap_num) and web
//  (TapToneAnalyzer.setNumberOfTaps) twins mirror.
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

    // NB: the reduce-count-to-at-or-below-captured branch of numberOfTaps.didSet
    // (isDetecting off → finalise) is intentionally NOT pinned here: it is not part
    // of the web's tap-count-change slug, and it DIVERGES from Python — Swift sets
    // "All taps captured. Processing..." and defers processMultipleTaps by
    // captureWindow, whereas Python's set_tap_num calls process_multiple_taps
    // synchronously.  Tracked separately (6-TEST 4c note).
}