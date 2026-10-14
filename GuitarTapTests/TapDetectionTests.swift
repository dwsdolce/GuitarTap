//
//  TapDetectionTests.swift
//  GuitarTapTests
//
//  The tap detector's decisions — the rising edge, the threshold the application configured, the
//  hysteresis latch and the re-arm rule, the warm-up and its sync frame, relative detection and its
//  noise floor — and the gated capture's onset alignment.
//
//  Every case feeds audio through `onChunkLevel(_:audioTime:)`, the per-chunk entry audio takes, after
//  arming the way the app does: `startTapSequence()`, then the warm-up on quiet audio. No case sets the
//  detector's state by hand. A tap has fired when a capture has started (`gatedCaptureActive`) — the one
//  effect a tap has in both capture kinds; cases about the detector's state read that state. The same
//  cases, with the same numbers, are in Python tests/test_tap_detection.py and web
//  test/tap-decisions.test.ts.
//
// @parity test/tap-decisions

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

/// An analyzer armed the way the app arms it — warm-up included — with the threshold the app sets.
@MainActor
private func armed(threshold: Float, _ type: MeasurementType = .classical) -> TapToneAnalyzer {
    TapDisplaySettings.measurementType = type
    let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
    // Disconnect the Combine subscriptions so the $magnitudes publisher cannot run peak analysis
    // between a chunk and an assertion.
    sut.cancellables.removeAll()
    sut.tapDetectionThreshold = threshold
    sut.startTapSequence()
    return sut
}

/// Feed `n` chunks at `level`, each one chunk of audio after the last.
@MainActor
private func chunks(_ sut: TapToneAnalyzer, _ level: Float, _ n: Int) {
    for _ in 0..<n {
        sut.onChunkLevel(level, audioTime: sut.lastAudioTime + audioFeedChunkSeconds)
    }
}

/// Through the warm-up on quiet audio, and one chunk past it: the sync chunk sees quiet, so the latch is
/// down and the detector is ready for a rising edge.
@MainActor
private func settled(_ sut: TapToneAnalyzer, level: Float = -90) {
    advanceAudio(sut, by: sut.warmupPeriod + audioFeedChunkSeconds, level: level)
}

/// Through the warm-up on quiet audio, then a LOUD first chunk after it: the sync chunk latches the
/// detector above — the state between taps, a tap still sounding — without firing.
@MainActor
private func latchedAbove(_ sut: TapToneAnalyzer) {
    advanceAudio(sut, by: sut.warmupPeriod - 0.001)
    chunks(sut, -20, 1)
}

private let confirm = RealtimeFFTAnalyzer.levelCrossingConfirmationChunks

/// A decaying tone — a tap's ring-out — at 48 kHz. Computed in Float, as the other suites' tap helpers are.
private func decayingTone(_ hz: Float, count: Int) -> [Float] {
    (0..<count).map { i in
        let t = Float(i) / 48000
        return 0.5 * expf(-t * 6) * sinf(2 * .pi * hz * t)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Tests
// ---------------------------------------------------------------------------

@Suite("TapDetection", .serialized)
@MainActor
struct TapDetectionTests {

    // Settings live in this process's isolated UserDefaults suite; each case sets the measurement type
    // it needs (`armed`), and this puts back the default for the next.
    init() { TapDisplaySettings.measurementType = .classical }

    // T1: a rising edge above the threshold is a tap.
    @Test func t1_risingEdgeFiresATap() {
        let sut = armed(threshold: -40)
        settled(sut)
        chunks(sut, -35, confirm)
        #expect(sut.gatedCaptureActive, "a tap should start a capture after crossing the rising threshold")
    }

    // T1c–T1e: the detector uses the threshold the APPLICATION configured — `tapDetectionThreshold`, which
    // the slider writes — not a copy left behind in the engine's config, which would leave the slider dead
    // and detection at the -40 dB default.

    // T1c: a level below the configured threshold, but above the -40 default, is not a tap.
    @Test func t1c_belowTheConfiguredThreshold_doesNotFire() {
        let sut = armed(threshold: -30)
        settled(sut)
        chunks(sut, -35, confirm)
        #expect(!sut.gatedCaptureActive,
                "a tap quieter than the configured threshold must not fire — if this fails, the detector is not reading the configured value")
    }

    // T1d: the control — a level above it fires, so T1c cannot pass by detecting nothing.
    @Test func t1d_aboveTheConfiguredThreshold_fires() {
        let sut = armed(threshold: -30)
        settled(sut)
        chunks(sut, -25, confirm)
        #expect(sut.gatedCaptureActive)
    }

    // T1e: the same tap, judged against two thresholds, is decided differently.
    @Test func t1e_theSameTapIsAcceptedOrRejectedByTheThreshold() {
        let lenient = armed(threshold: -50)
        settled(lenient)
        chunks(lenient, -45, confirm)
        #expect(lenient.gatedCaptureActive, "-45 clears a -50 threshold")

        let strict = armed(threshold: -35)
        settled(strict)
        chunks(strict, -45, confirm)
        #expect(!strict.gatedCaptureActive, "the same tap is too quiet for a -35 threshold")
    }

    // T1f: the re-arm rule — while latched above, a ring-out that dips below the rising threshold but not
    // below the falling one (threshold − margin) is the same tap still sounding, so its next rise is not
    // a new tap. `isAboveThreshold` is both the latch and the gate.
    @Test func t1f_aRingOutAboveTheFallingThreshold_isNotANewTap() {
        let sut = armed(threshold: -40)   // rising -40, falling -43
        latchedAbove(sut)
        chunks(sut, -42, 3)               // below rising, ABOVE falling — still the same tap
        chunks(sut, -20, 3)               // the decay swings back up
        #expect(!sut.gatedCaptureActive,
                "a ring-out that never fell below the falling threshold must not be taken as a new tap")
    }

    // T1g: the control — a dip below the falling threshold does re-arm, so T1f cannot pass by never firing.
    @Test func t1g_aDipBelowTheFallingThreshold_reArms() {
        let sut = armed(threshold: -40)
        latchedAbove(sut)
        chunks(sut, -60, 3)               // the signal genuinely settled
        chunks(sut, -20, confirm)         // a real second strike
        #expect(sut.gatedCaptureActive)
    }

    // T2: a level below the threshold is not a tap.
    @Test func t2_belowTheThreshold_doesNotFire() {
        let sut = armed(threshold: -40)
        settled(sut)
        chunks(sut, -50, confirm)
        #expect(!sut.gatedCaptureActive, "a level below the threshold must not start a capture")
    }

    // T3: the warm-up suppresses detection.
    @Test func t3_theWarmUpSuppressesDetection() {
        let sut = armed(threshold: -40)
        chunks(sut, -20, confirm)         // loud, but inside the warm-up
        #expect(sut.lastAudioTime < sut.warmupPeriod)
        #expect(!sut.gatedCaptureActive, "no tap during the warm-up")
    }

    // T5: once latched above, a level between the falling and rising thresholds holds the latch.
    @Test func t5_betweenFallingAndRising_holdsTheLatch() {
        let sut = armed(threshold: -40)   // rising -40, falling -43
        latchedAbove(sut)
        chunks(sut, -42, 1)
        #expect(sut.isAboveThreshold, "above the falling threshold, the latch holds")
        #expect(!sut.gatedCaptureActive, "no new tap")
    }

    // T5b: a level below the falling threshold clears the latch.
    @Test func t5b_belowTheFallingThreshold_clearsTheLatch() {
        let sut = armed(threshold: -40)
        latchedAbove(sut)
        chunks(sut, -50, 1)
        #expect(!sut.isAboveThreshold, "below the falling threshold, the latch clears")
    }

    // T6: plate detection is RELATIVE to the noise floor. With the floor raised to -45 and the threshold
    // at -40, the relative rising threshold is -35 — above the absolute one — so a -38 level, which the
    // absolute rule fires on, is not a tap here, and -30 is. The plate is in a real capture phase, and the
    // tap must start a capture.
    @Test func t6_plateDetectionIsRelativeToTheNoiseFloor() {
        let guitar = armed(threshold: -40)
        settled(guitar)
        chunks(guitar, -38, confirm)
        #expect(guitar.gatedCaptureActive, "the control: -38 clears the absolute -40 threshold")

        let sut = armed(threshold: -40, .plate)
        #expect(sut.materialTapPhase == .capturingLongitudinal)
        settled(sut, level: -45)          // the warm-up, then the floor re-anchors at -45
        #expect(sut.noiseFloorEstimate == -45)

        chunks(sut, -38, 3)
        #expect(!sut.gatedCaptureActive, "-38 is below the relative threshold (-35): not a tap")

        chunks(sut, -30, confirm)
        #expect(sut.gatedCaptureActive, "-30 clears the relative threshold: a capture starts")
    }

    // T7: in plate mode the noise-floor estimate follows the ambient level while below the threshold.
    @Test func t7_theNoiseFloorConvergesTowardTheAmbientLevel() {
        let sut = armed(threshold: -40, .plate)
        settled(sut, level: -60)          // the floor re-anchors at -60
        let start = sut.noiseFloorEstimate
        #expect(start == -60)

        chunks(sut, -55, 50)              // α = 0.05, 50 steps from -60 toward -55: ≈ -57.4
        #expect(sut.noiseFloorEstimate > start, "the floor moves toward the ambient level")
        #expect(sut.noiseFloorEstimate > -58, "after 50 chunks at -55 dB it is close to -55 (got \(sut.noiseFloorEstimate))")
    }

    // T8: the first chunk after the warm-up syncs the latch from its level, and does not fire.
    @Test func t8_theFirstChunkAfterTheWarmUpSyncsTheLatch() {
        let sut = armed(threshold: -40)
        advanceAudio(sut, by: sut.warmupPeriod - 0.001)   // every chunk still inside the warm-up
        #expect(sut.justExitedWarmup)
        chunks(sut, -30, 1)               // the first chunk after it — loud
        #expect(!sut.justExitedWarmup, "the sync chunk clears the flag")
        #expect(sut.isAboveThreshold, "the latch is synced from the level")
        #expect(!sut.gatedCaptureActive, "the sync chunk does not fire")
    }

    // The settle — the latched ring-out falling below the falling threshold — leaves the prompt alone:
    // a plate's "fL tap 1/2 captured. Tap again..." is not replaced by the GUITAR loop status.
    @Test func settle_leavesAPlatePromptAlone() {
        let sut = armed(threshold: -40, .plate)
        sut.numberOfTaps = 2
        settled(sut, level: -60)
        chunks(sut, -10, confirm)                         // a tap: the capture opens
        #expect(sut.gatedCaptureActive)
        sut.finishGatedFFTCapture(samples: decayingTone(60, count: 24_000), sampleRate: 48000, phase: .capturingLongitudinal)
        let prompt = sut.statusMessage
        #expect(prompt.hasPrefix("fL tap 1/2"))
        advanceAudio(sut, by: sut.tapCooldown, level: -20)  // the rest ends while it still rings: latched above
        #expect(sut.isDetecting && sut.isAboveThreshold)
        chunks(sut, -60, 3)                               // the ring-out falls: the settle
        #expect(!sut.isAboveThreshold)
        #expect(sut.statusMessage == prompt, "the settle must leave the plate prompt alone")
    }

    @Test func settle_leavesAGuitarPromptAlone() async throws {
        let sut = armed(threshold: -40)
        sut.numberOfTaps = 2
        // An unstarted analyzer has no frequency bins (all 0 Hz), so the guitar finish's real spectrum
        // would put every peak at 0 Hz; set them up as starting the engine or file playback does, and let
        // the main queue publish them (as StateInvariantTests does).
        sut.fftAnalyzer.actualSampleRate = 48000
        sut.fftAnalyzer.updateFrequencyBins()
        try await Task.sleep(for: .milliseconds(50))
        settled(sut)
        chunks(sut, -10, confirm)
        #expect(sut.gatedCaptureActive)
        sut.finishGuitarGatedCapture(samples: decayingTone(100, count: sut.fftAnalyzer.fftSize), sampleRate: 48000)
        let prompt = sut.statusMessage
        #expect(prompt == "Tap 1/2 captured. Tap again...")
        advanceAudio(sut, by: sut.tapCooldown, level: -20)
        #expect(sut.isDetecting && sut.isAboveThreshold)
        chunks(sut, -60, 3)
        #expect(!sut.isAboveThreshold)
        #expect(sut.statusMessage == prompt)
    }

    // Arming and resuming. A new sequence seeds the noise floor from the current input
    // level — the engine's, here set as the engine sets it — and -100 when the warm-up is skipped.
    @Test func start_seedsTheNoiseFloorFromTheInputLevel() {
        TapDisplaySettings.measurementType = .plate
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        sut.cancellables.removeAll()
        sut.fftAnalyzer.level.inputLevelDB = -50
        sut.startTapSequence()
        #expect(sut.noiseFloorEstimate == -50)

        TapDisplaySettings.measurementType = .classical
        sut.startTapSequence(skipWarmup: true)
        #expect(sut.noiseFloorEstimate == -100, "the warm-up skipped (guitar file playback)")
    }

    // A resume restarts the tap confirmation: one chunk above the threshold before the pause and one after
    // it do not make a tap. Swift and Python kept the count across the pause, so a single loud chunk after
    // a resume could fire one.
    @Test func resume_restartsTheTapConfirmation() {
        let sut = armed(threshold: -40)
        settled(sut)
        chunks(sut, -35, 1)               // one chunk counted
        #expect(!sut.gatedCaptureActive)
        sut.pauseTapDetection()
        sut.resumeTapDetection()
        chunks(sut, -35, 1)               // one chunk after the resume
        #expect(!sut.gatedCaptureActive, "one chunk after the resume must not confirm a tap")
        chunks(sut, -35, 1)
        #expect(sut.gatedCaptureActive, "two chunks do")
    }

    // A new sequence restarts the tap confirmation too: a chunk counted before it cannot help confirm its
    // first tap.
    @Test func start_restartsTheTapConfirmation() {
        let sut = armed(threshold: -40)
        settled(sut)
        chunks(sut, -35, 1)               // one chunk counted
        sut.startTapSequence()
        // No quiet chunk in between — one would reset the count by itself. (The engine's clock stays at 0
        // in a test, so the new warm-up, anchored to it, has already run; the same holds for a resume.)
        chunks(sut, -35, 1)
        #expect(!sut.gatedCaptureActive, "one chunk of the new sequence must not confirm a tap")
        chunks(sut, -35, 1)
        #expect(sut.gatedCaptureActive, "two chunks do")
    }

    // A resume keeps the noise floor and puts the latch down.
    @Test func resume_keepsTheNoiseFloorAndPutsTheLatchDown() {
        let sut = armed(threshold: -40, .plate)
        latchedAbove(sut)
        let floor = sut.noiseFloorEstimate
        sut.pauseTapDetection()
        sut.resumeTapDetection()
        #expect(sut.noiseFloorEstimate == floor, "the floor is left as it was")
        #expect(!sut.isAboveThreshold, "the latch goes down")
    }

    // The gated capture's onset alignment: the transient lands at the pre-onset position plus the
    // backup, at full amplitude. `TapToneAnalyzer+SpectrumCapture`'s tag names this suite as one of the
    // gated capture's tests.
    @Test func onsetAlignment_placesTheTransientAtPreOnsetPlusBackup() throws {
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        var buf = [Float](repeating: 0, count: 10000)
        buf[5000] = 0.5  // a single transient after silence
        let out = sut.alignCaptureToOnset(buf, windowSize: 4096, preOnsetSamples: 1000)
        try #require(out.count == 4096)
        let argmax = out.indices.max(by: { abs(out[$0]) < abs(out[$1]) })!
        #expect(argmax == 1032, "the pre-onset 1000, plus the onset backed up 32 samples")
        #expect(abs(out[argmax] - 0.5) < 1e-6)
    }

    // The fallbacks: when the onset cannot be found, the start of the buffer, still window-sized — so the
    // tap reaches the transform at the same length as every other (same bin grid, same window gain).
    @Test func onsetAlignment_tooShort_returnsItsStartWindowSized() throws {
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        let buf = [Float](repeating: 0.25, count: 1000)  // shorter than the 2048-sample noise estimate
        let out = sut.alignCaptureToOnset(buf, windowSize: 4096, preOnsetSamples: 1000)
        // #require stops here if the length is wrong — reading out[1000] of a shorter buffer would trap
        // and take the whole test process down.
        try #require(out.count == 4096)
        #expect(out[0] == 0.25 && out[999] == 0.25)
        #expect(out[1000] == 0 && out[4095] == 0, "zero-padded after the buffer")
    }

    @Test func onsetAlignment_noOnset_returnsTheStartWindowSized() throws {
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        // A level that never rises 10x above its own RMS: no onset.
        let buf = (0..<10000).map { Float(0.1) + Float(0.00001) * Float($0) }
        let out = sut.alignCaptureToOnset(buf, windowSize: 4096, preOnsetSamples: 1000)
        try #require(out.count == 4096, "window-sized, not the whole buffer")
        #expect(out[0] == buf[0] && out[4095] == buf[4095], "the start of the buffer")
    }
}
