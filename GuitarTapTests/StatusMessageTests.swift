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
//  paused/resume, completion (frozen across recalc), loaded, plate completion — plus:
//
//  1. Material phase-guidance — "Ready for fL tap", "Rotate 90° and tap for fC" — which
//     stays VISIBLE because the warm-up is silent. Pinned below by the "survives the
//     warm-up" cases, which feed a warm-up frame and assert the guidance persists. The
//     redo / FLC phase strings follow the same mechanism and are covered by the material
//     accept/redo transitions.
//
//  2. Per-tap capture PROGRESS transients — "Tap n/N capturing...",
//     "Tap n/N captured. Tap again...", "All taps captured. Processing...", the
//     material "fL/fC/fLC tap n/N captured..." / review / "No resonance detected"
//     strings — pinned below, in StatusMessageCaptureProgressTests. The handlers take a
//     spectrum and a peak, so they are driven directly, without audio.
//
// @parity test/status-message

import Testing
import Foundation
@testable import GuitarTap

@MainActor
private func makeSUT(numberOfTaps: Int = 1,
                     measurementType: MeasurementType = .generic) -> TapToneAnalyzer {
    let fft = RealtimeFFTAnalyzer.forTesting()
    let sut = TapToneAnalyzer(fftAnalyzer: fft)
    sut.numberOfTaps = numberOfTaps
    sut.tapDetectionThreshold = -40
    sut.warmupStartAudioTime = -2  // audio clock: warm-up already elapsed
    sut.justExitedWarmup = false
    TapDisplaySettings.measurementType = measurementType
    // NOTE: unlike ScenarioStateTraceTests, keep `cancellables` intact — the
    // clipping override is a Combine sink we need.
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
    sut.onChunkLevel(level, audioTime: 0)                           // → warm-up exit sets the resting prompt
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
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
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

    // ── two writes in one pass settle on the second ─────────────────────────
    // Arming straight after the analyzer is made writes the armed prompt in the same pass of the main
    // queue as the initial status. The status must settle on the prompt and stay there — it once
    // alternated between the two, hundreds of thousands of times a second, for good.
    @Test func twoWritesInOnePass_settleOnTheSecondAndStay() async throws {
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())  // subscriptions kept
        TapDisplaySettings.measurementType = .generic
        sut.numberOfTaps = 1
        sut.startTapSequence(skipWarmup: true)
        try await Task.sleep(for: .milliseconds(50))
        #expect(sut.statusMessage == "Tap the guitar...")

        var writes = 0
        let token = sut.$statusMessage.dropFirst().sink { _ in writes += 1 }
        defer { token.cancel() }
        try await Task.sleep(for: .milliseconds(50))

        #expect(sut.statusMessage == "Tap the guitar...")
        #expect(writes == 0, "REGRESSION: the status kept changing with nothing happening — \(writes) writes in 50 ms")
    }

    // ── clipping override / restore (a Combine sink, receive(on: .main)) ─────
    @Test func clipping_overridesDisplayAndRestoresLatestRealStatus() async throws {
        let sut = makeSUT(numberOfTaps: 1)
        armAndSettle(sut)
        #expect(sut.statusMessage == "Tap the guitar...")

        sut.fftAnalyzer.level.isClipping = true
        try await Task.sleep(for: .milliseconds(50))
        #expect(sut.statusMessage == TapToneAnalyzer.clippingWarningStatus)

        // A real write while clipping stays pinned to the warning but is stashed:
        // setting numberOfTaps while armed+idle rewrites the prompt (numberOfTaps.didSet).
        sut.numberOfTaps = 3 // real write "Tap the guitar 3 times..."
        try await Task.sleep(for: .milliseconds(50))
        #expect(sut.statusMessage == TapToneAnalyzer.clippingWarningStatus)

        sut.fftAnalyzer.level.isClipping = false
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

    // ── Material phase-guidance survives the (silent) warm-up ───────────────────────
    // Each phase-arm restarts the warm-up; feed a warm-up frame and assert the guidance
    // persists rather than being replaced by "Initializing…" or "Tap the guitar…".
    @Test func materialArm_readyForLTap_survivesWarmup() {
        let sut = makeSUT(numberOfTaps: 1, measurementType: .plate)
        sut.startTapSequence()
        #expect(sut.statusMessage == "Ready for fL tap")
        sut.onChunkLevel(-80, audioTime: 0) // a warm-up frame (warm-up clock just armed at the current audio time)
        #expect(sut.statusMessage == "Ready for fL tap")
    }

    @Test func acceptL_rotate90_survivesWarmup() {
        let sut = makeSUT(numberOfTaps: 1, measurementType: .plate)
        sut.materialTapPhase = .reviewingLongitudinal
        sut.acceptCurrentPhase() // → "Rotate 90° and tap for fC" + warm-up restart
        #expect(sut.statusMessage == "Rotate 90° and tap for fC")
        sut.onChunkLevel(-80, audioTime: 0) // a warm-up frame
        #expect(sut.statusMessage == "Rotate 90° and tap for fC")
    }

    /// The OTHER accept transition: fC → the FLC set-up prompt, shown during the disarmed cooldown.
    /// It is the prompt the FLC cooldown guard hands the user.
    @Test func acceptC_promptsToSetUpForFlc_andSurvivesWarmup() {
        let saved = TapDisplaySettings.measureFlc
        TapDisplaySettings.measureFlc = true
        defer { TapDisplaySettings.measureFlc = saved }

        let sut = makeSUT(numberOfTaps: 1, measurementType: .plate)
        sut.materialTapPhase = .reviewingCross
        sut.acceptCurrentPhase()
        #expect(sut.statusMessage == "Set up for fLC tap, then tap")
        sut.onChunkLevel(-80, audioTime: 0) // a warm-up frame must not overwrite it
        #expect(sut.statusMessage == "Set up for fLC tap, then tap")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Capture-progress strings
// ---------------------------------------------------------------------------
//
// The file-playback regression tests RUN the pipeline but do not assert `statusMessage`, so these
// strings are pinned here. Every case below drives a method a sibling test file already calls without audio:
// FrozenPeakRecalculationTests drives handleLongitudinalGatedProgress the same way.

/// The re-arm after a guitar tap's cooldown does not touch the status: the capture set the loop prompt
/// ("Tap 1/3 captured. Tap again...") and it stays, even while the level is still high.
@Suite("StatusMessage — guitar re-arm", .serialized)
@MainActor
struct StatusMessageReArmTests {
    @Test func reArm_leavesStatusAsTheCaptureSetIt() async throws {
        let sut = makeSUT(numberOfTaps: 3)
        // Drop the Combine sinks: neither input-condition override is in play here, and without
        // them the status can only change by a direct write, which is exactly what this test is about.
        sut.cancellables.removeAll()
        sut.fftAnalyzer.actualSampleRate = 48000   // an unstarted analyzer has no frequency bins
        sut.fftAnalyzer.updateFrequencyBins()
        sut.startTapSequence()
        try await Task.sleep(for: .milliseconds(50))
        let n = sut.fftAnalyzer.fftSize
        let tap = (0..<n).map { i -> Float in
            let t = Float(i) / 48000
            return 0.5 * expf(-t * 6) * sinf(2 * .pi * 100 * t)
        }
        sut.finishGuitarGatedCapture(samples: tap, sampleRate: 48000)
        let afterCapture = sut.statusMessage
        #expect(afterCapture == sut.guitarLoopStatus(capturing: false))

        // The rest runs on the audio clock; the audio is still ringing, above the falling
        // threshold, when the re-arm falls due.
        advanceAudio(sut, by: sut.tapCooldown, level: -20)
        #expect(sut.isDetecting, "re-armed")
        #expect(sut.statusMessage == afterCapture, "the re-arm leaves the status alone")
    }
}

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
