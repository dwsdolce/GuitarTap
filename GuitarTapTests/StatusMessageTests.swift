//
//  StatusMessageTests.swift
//  GuitarTapTests
//
//  Pins the analyzer's @Published `statusMessage` to its canonical strings by
//  DRIVING TRANSITIONS on a real TapToneAnalyzer and asserting the field — the
//  same behavior the web pins in test/status-message.test.ts and Python pins in
//  tests/test_status_message.py.  The three suites assert identical strings; only
//  the per-platform driving differs (see ScenarioStateTraceTests for the same
//  idiom on state tuples).
//
//  SCOPE: the state-reachable strings — arm/rest, clipping, device-change begin,
//  paused/resume, completion (frozen across recalc), loaded, plate completion.
//  Two families are intentionally NOT pinned here:
//
//  1. Material phase-guidance — "Ready for fL tap", "Rotate 90° and tap for fC" — is now
//     VISIBLE (OUT-1 fixed by the status state-machine alignment: the warm-up is silent).
//     Pinned below by the "survives the warm-up" cases, which feed a warm-up frame and
//     assert the guidance persists (these FAILED before the alignment — the warm-up
//     overwrote them with "Initializing…"). The redo / FLC phase strings follow the same
//     mechanism and are covered by the material accept/redo transitions.
//
//  2. Per-tap capture PROGRESS transients — "Tap n/N capturing...",
//     "Tap n/N captured. Tap again...", "All taps captured. Processing...", the
//     material "fL/fC/fLC tap n/N captured..." / review / "No resonance detected"
//     strings — are pinned below, in StatusMessageCaptureProgressTests.
//
//     This used to say they were written too deep in the gated-capture pipeline for a
//     state-driven suite to reach, and were covered by the file-playback regression tests.
//     Neither held (#17 F29): those tests RUN the pipeline but assert no status at all, and
//     the handlers take a spectrum and a peak, which FrozenPeakRecalculationTests has always
//     called directly.  The strings were pinned in no edition but web.
//
// @parity test/status-message

import Testing
import Foundation
@testable import GuitarTap

@MainActor
private func makeSUT(numberOfTaps: Int = 1,
                     measurementType: MeasurementType = .generic) -> TapToneAnalyzer {
    let fft = RealtimeFFTAnalyzer()
    let sut = TapToneAnalyzer(fftAnalyzer: fft)
    sut.numberOfTaps = numberOfTaps
    sut.tapDetectionThreshold = -40
    sut.warmupStartAudioTime = -2  // audio clock: warm-up already elapsed
    sut.justExitedWarmup = false
    TapDisplaySettings.measurementType = measurementType
    // NOTE: unlike ScenarioStateTraceTests, keep `cancellables` intact — the
    // clipping override + latestRealStatus tracking are Combine sinks we need.
    return sut
}

private func fakeTap() -> (magnitudes: [Float], frequencies: [Float], captureTime: Date) {
    var mags = [Float](repeating: -80, count: 64)
    mags[16] = -30
    let freqs = (0..<64).map { Float($0) * 31.25 }
    return (magnitudes: mags, frequencies: freqs, captureTime: Date())
}

/// Drive the analyzer to its *settled* armed resting prompt.  `startTapSequence()`
/// arms detection but does NOT set "Tap the guitar..." — that string is written by
/// the detection loop's warm-up exit (`detectTap`), not the arm call.  So force past
/// warm-up and feed one below-threshold frame, exactly what the running app does once
/// audio flows.  (`level` stays under the -40 dB threshold so no tap fires.)
@MainActor
private func armAndSettle(_ sut: TapToneAnalyzer, level: Float = -80) {
    sut.startTapSequence()
    sut.warmupStartAudioTime = -2  // audio clock: warm-up already elapsed // past the warm-up window
    sut.justExitedWarmup = true                            // next frame is the first post-warm-up
    sut.onRmsLevelChanged(level, audioTime: 0)                           // → warm-up exit sets the resting prompt
}

@Suite("StatusMessage", .serialized)
@MainActor
struct StatusMessageTests {

    init() {
        TapDisplaySettings.measurementType = .generic
        TapDisplaySettings.measureFlc = false
    }

    // ── initial ────────────────────────────────────────────────────────────
    @Test func initial_isCanonicalBeginMessage() {
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer())
        #expect(sut.statusMessage == "Tap the guitar to begin")
    }

    // ── guitar detection-loop resting prompts ───────────────────────────────
    @Test func guitarArmed_singleTap_restsAtTapPrompt() {
        let sut = makeSUT(numberOfTaps: 1)
        armAndSettle(sut)
        #expect(sut.statusMessage == "Tap the guitar...")
    }

    @Test func guitarArmed_multiTap_restsAtCountPrompt() {
        let sut = makeSUT(numberOfTaps: 3)
        armAndSettle(sut)
        #expect(sut.statusMessage == "Tap the guitar 3 times...")
    }

    // ── clipping override / restore (Combine sink, receive(on: .main)) ───────
    @Test func clipping_overridesDisplayAndRestoresLatestRealStatus() async throws {
        let sut = makeSUT(numberOfTaps: 1)
        armAndSettle(sut)
        #expect(sut.statusMessage == "Tap the guitar...")
        try await Task.sleep(for: .milliseconds(50)) // let $statusMessage cache latestRealStatus

        sut.fftAnalyzer.isClipping = true
        try await Task.sleep(for: .milliseconds(50))
        #expect(sut.statusMessage == TapToneAnalyzer.clippingWarningStatus)

        // A real write while clipping stays pinned to the warning but is stashed:
        // setting numberOfTaps while armed+idle rewrites the prompt (numberOfTaps.didSet).
        sut.numberOfTaps = 3 // real write "Tap the guitar 3 times..."
        try await Task.sleep(for: .milliseconds(50))
        #expect(sut.statusMessage == TapToneAnalyzer.clippingWarningStatus)

        sut.fftAnalyzer.isClipping = false
        try await Task.sleep(for: .milliseconds(50))
        #expect(sut.statusMessage == "Tap the guitar 3 times...")
    }

    // ── device change (route restart) — BEGIN only ──────────────────────────
    // The settled restore ("Tap the guitar...") runs 3 s later, gated on a live
    // $magnitudes frame + isRunning, so it is not reachable in a headless test;
    // it is covered at the integration level.  (The web asserts the restore too
    // because its handleDeviceChange is synchronous/imperative — a per-platform
    // driving difference, not a string difference.)
    @Test func deviceChange_showsReinitializing() async throws {
        let sut = makeSUT(numberOfTaps: 1)
        sut.startTapSequence()
        try await Task.sleep(for: .milliseconds(50))
        sut.handleRouteChangeRestart()
        #expect(sut.statusMessage == "Audio device changed - reinitializing...")
    }

    // ── paused / resume ─────────────────────────────────────────────────────
    @Test func paused_thenResume_restoresPrompt() async throws {
        let sut = makeSUT(numberOfTaps: 1)
        sut.startTapSequence()
        try await Task.sleep(for: .milliseconds(50))
        sut.pauseTapDetection()
        #expect(sut.statusMessage == "Detection paused – tap freely, then resume") // en-dash U+2013
        sut.resumeTapDetection()
        #expect(sut.statusMessage == "Tap the guitar...")
    }

    // ── completion — announced once, FROZEN across a Peak-Min recalc ─────────
    @Test func completion_announcedOnce_frozenAcrossRecalc() async throws {
        let sut = makeSUT(numberOfTaps: 2)
        sut.capturedTaps = [fakeTap(), fakeTap()]
        sut.currentTapCount = 2
        sut.detectionState = .idle
        sut.processMultipleTaps()

        let announced = sut.statusMessage
        #expect(announced.hasPrefix("Analysis complete! "))
        #expect(announced.hasSuffix(" (from 2 averaged taps)."))

        // A Peak-Min slider move recomputes peaks but must NOT re-announce.
        sut.peakMinThreshold = -30
        #expect(sut.statusMessage == announced)
    }

    // ── loaded measurement (frozen) ─────────────────────────────────────────
    @Test func loadedMeasurement_showsFrozenLoadedPrompt() {
        let sut = makeSUT(numberOfTaps: 1)
        // A prior completed fresh capture, then a load.
        sut.capturedTaps = [fakeTap()]
        sut.isMeasurementComplete = true
        sut.loadMeasurement(TapToneMeasurement(peaks: [], measurementName: "Loaded", notes: ""))
        #expect(sut.statusMessage == "Loaded measurement (frozen). Press \u{2018}New Tap\u{2019} to start a new measurement.")

        // A recalc on the loaded measurement must NOT re-announce "Analysis complete".
        sut.peakMinThreshold = -30
        #expect(sut.statusMessage == "Loaded measurement (frozen). Press \u{2018}New Tap\u{2019} to start a new measurement.")
    }

    // ── material completion (warm-up-independent: no re-arm after complete) ──
    @Test func plateComplete_noFLC_listsFLandFC() {
        let sut = makeSUT(numberOfTaps: 1, measurementType: .plate)
        TapDisplaySettings.measureFlc = false
        sut.selectedLongitudinalPeak = ResonantPeak(frequency: 100, magnitude: -40)
        sut.selectedCrossPeak = ResonantPeak(frequency: 200, magnitude: -40)
        sut.materialTapPhase = .reviewingCross
        sut.acceptCurrentPhase() // no FLC → finalisePlateNoFLC
        #expect(sut.statusMessage == "Complete — fL: 100.0 Hz, fC: 200.0 Hz") // em-dash U+2014
    }

    @Test func plateComplete_withFLC_showsCheckResults() {
        let sut = makeSUT(numberOfTaps: 1, measurementType: .plate)
        TapDisplaySettings.measureFlc = true
        sut.materialTapPhase = .reviewingFlc
        sut.acceptCurrentPhase() // → finalisePlateWithFLC
        #expect(sut.statusMessage == "Complete - check Results") // ASCII hyphen
    }

    // ── OUT-1 fixed: material phase-guidance survives the (now silent) warm-up ───
    // Each phase-arm restarts the warm-up; feed a warm-up frame and assert the guidance
    // persists. These FAILED before the state-machine alignment (the warm-up overwrote
    // them with "Initializing…" → "Tap the guitar…").
    @Test func materialArm_readyForLTap_survivesWarmup() {
        let sut = makeSUT(numberOfTaps: 1, measurementType: .plate)
        sut.startTapSequence(initialPhase: .capturingLongitudinal)
        #expect(sut.statusMessage == "Ready for fL tap")
        sut.onRmsLevelChanged(-80, audioTime: 0) // a warm-up frame (warm-up clock just armed at the current audio time)
        #expect(sut.statusMessage == "Ready for fL tap")
    }

    @Test func acceptL_rotate90_survivesWarmup() {
        let sut = makeSUT(numberOfTaps: 1, measurementType: .plate)
        sut.materialTapPhase = .reviewingLongitudinal
        sut.acceptCurrentPhase() // → "Rotate 90° and tap for fC" + warm-up restart
        #expect(sut.statusMessage == "Rotate 90° and tap for fC")
        sut.onRmsLevelChanged(-80, audioTime: 0) // a warm-up frame
        #expect(sut.statusMessage == "Rotate 90° and tap for fC")
    }

    /// The OTHER accept transition: fC → the FLC set-up prompt, shown during the disarmed cooldown.
    /// Web covered both in one case; the natives covered only the first, so this string was asserted
    /// in no edition but web (#17 F29). It is the prompt the FLC cooldown guard hands the user.
    @Test func acceptC_promptsToSetUpForFlc_andSurvivesWarmup() {
        let saved = TapDisplaySettings.measureFlc
        TapDisplaySettings.measureFlc = true
        defer { TapDisplaySettings.measureFlc = saved }

        let sut = makeSUT(numberOfTaps: 1, measurementType: .plate)
        sut.materialTapPhase = .reviewingCross
        sut.acceptCurrentPhase()
        #expect(sut.statusMessage == "Set up for fLC tap, then tap")
        sut.onRmsLevelChanged(-80, audioTime: 0) // a warm-up frame must not overwrite it
        #expect(sut.statusMessage == "Set up for fLC tap, then tap")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Capture-progress strings  (#17 F29)
// ---------------------------------------------------------------------------
//
// These were excluded for years on the grounds that they are "written deep in the gated-capture
// pipeline … so a state-driven suite can't reach them cleanly", and were credited to the
// file-playback regression tests. Those tests RUN the pipeline, so the strings are certainly set —
// but `statusMessage` is asserted in exactly two test files in this target, and neither is one of
// them. Deleting `No signal detected — tap again` from all five of its sites left both native
// suites green. Web pinned them all along; the spread read 12/12/16 as though web had extras.
//
// Every case below drives a method a sibling test file already calls without audio:
// FrozenPeakRecalculationTests drives handleLongitudinalGatedProgress the same way.

@Suite("StatusMessage — capture progress")
@MainActor
struct StatusMessageCaptureProgressTests {

    /// A synthetic spectrum with one gaussian peak, enough for findDominantPeak to bite.
    private func peakSpectrum(at freq: Float, from minHz: Float, to maxHz: Float)
        -> (magnitudes: [Float], frequencies: [Float]) {
        let n = 512
        let freqs = (0..<n).map { minHz + (maxHz - minHz) * Float($0) / Float(n - 1) }
        let mags = freqs.map { f -> Float in
            let d = (f - freq) / 8
            return -80 + 50 * expf(-0.5 * d * d)
        }
        return (magnitudes: mags, frequencies: freqs)
    }

    // The guitar loop's two strings, from the helper the capture transitions call.
    @Test func guitarLoop_capturingAndBetweenTaps() {
        let sut = makeSUT(numberOfTaps: 3)
        sut.currentTapCount = 0
        #expect(sut.guitarLoopStatus(capturing: true) == "Tap 1/3 capturing...")
        sut.currentTapCount = 1
        #expect(sut.guitarLoopStatus(capturing: false) == "Tap 1/3 captured. Tap again...")
        sut.currentTapCount = 2
        #expect(sut.guitarLoopStatus(capturing: true) == "All taps captured. Processing...",
                "the last tap's provisional string announces processing, not 3/3 capturing")
    }

    // Redo re-arms the phase with its own prompt — the "— tap again" family.
    @Test func redoLongitudinal_promptsToTapAgain() {
        let sut = makeSUT(numberOfTaps: 1, measurementType: .plate)
        sut.materialTapPhase = .reviewingLongitudinal
        sut.redoCurrentPhase()
        #expect(sut.statusMessage == "Ready for fL tap — tap again")
    }

    // Multi-tap material progress: a tap short of the total re-arms and counts.
    @Test func materialProgress_countsAndAsksForAnother() throws {
        let sut = makeSUT(numberOfTaps: 3, measurementType: .brace)
        sut.minFrequency = 100
        sut.maxFrequency = 1200
        let spec = peakSpectrum(at: 300, from: 100, to: 1200)
        let dominant = try #require(sut.findDominantPeak(magnitudes: spec.magnitudes,
                                                        frequencies: spec.frequencies,
                                                        minHz: 100, maxHz: 1200,
                                                        preferLowestSignificant: false))
        sut.materialCapturedTaps = [(magnitudes: spec.magnitudes, frequencies: spec.frequencies, captureTime: Date())]
        sut.handleLongitudinalGatedProgress(magnitudes: spec.magnitudes,
                                            frequencies: spec.frequencies,
                                            dominantPeak: dominant,
                                            minHz: 100, maxHz: 1200,
                                            preferLowest: false)
        #expect(sut.statusMessage == "fL tap 1/3 captured. Tap again...")
    }

    // A tap with no resonance in the phase's band re-arms WITHOUT counting.
    @Test func noResonanceInBand_asksToTapAgain() {
        let sut = makeSUT(numberOfTaps: 1, measurementType: .plate)
        let silence = [Float](repeating: 0, count: 24_000)
        sut.finishGatedFFTCapture(samples: silence, sampleRate: 48_000, phase: .capturingLongitudinal)
        #expect(sut.statusMessage.hasSuffix("— tap again"),
                "a tap with nothing in band must prompt again, not advance")
        #expect(sut.materialCapturedTaps.isEmpty, "and it must not count toward the phase")
    }

    // File playback auto-advances L → C with its own transition string.
    @Test func filePlayback_announcesTheAutoAdvance() throws {
        let sut = makeSUT(numberOfTaps: 1, measurementType: .plate)
        sut.fftAnalyzer.isPlayingFile = true
        defer { sut.fftAnalyzer.isPlayingFile = false }
        sut.minFrequency = 100
        sut.maxFrequency = 1200
        let spec = peakSpectrum(at: 300, from: 100, to: 1200)
        let dominant = try #require(sut.findDominantPeak(magnitudes: spec.magnitudes,
                                                        frequencies: spec.frequencies,
                                                        minHz: 100, maxHz: 1200,
                                                        preferLowestSignificant: false))
        sut.materialCapturedTaps = [(magnitudes: spec.magnitudes, frequencies: spec.frequencies, captureTime: Date())]
        sut.handleLongitudinalGatedProgress(magnitudes: spec.magnitudes,
                                            frequencies: spec.frequencies,
                                            dominantPeak: dominant,
                                            minHz: 100, maxHz: 1200,
                                            preferLowest: false)
        #expect(sut.statusMessage == "File: fL complete, capturing fC...")
    }
}
