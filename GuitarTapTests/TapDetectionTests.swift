//
//  TapDetectionTests.swift
//  GuitarTapTests
//
//  Tests for the tap detection hysteresis logic in TapToneAnalyzer+TapDetection.
//
//  Strategy: `detectTap` is directly callable as a method on TapToneAnalyzer.
//  We manipulate its internal guard state (warmupStartAudioTime, isAboveThreshold)
//  directly via @testable import so the method exercises pure logic
//  without a real audio engine.  The `fftAnalyzer.peakMagnitude` and `recentPeakLevelDB`
//  properties are read by `handleTapDetection`, so we construct a no-op
//  RealtimeFFTAnalyzer that never starts.
//
//  Test plan coverage: T1–T9 (T4, the cooldown gate, removed in #19 — nothing reached it)
//
// @parity test/tap-decisions

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helper
// ---------------------------------------------------------------------------

/// Build a non-running TapToneAnalyzer in guitar mode (absolute threshold)
/// with its warm-up period satisfied so detectTap can fire.
///
@MainActor
private func makeSUT(
    threshold: Float = -40,
    numberOfTaps: Int = 1
) -> TapToneAnalyzer {
    let fft = RealtimeFFTAnalyzer.forTesting()
    let sut = TapToneAnalyzer(fftAnalyzer: fft)
    sut.tapDetectionThreshold = threshold
    sut.numberOfTaps = numberOfTaps
    // Defeat the warmup guard by setting the start time 2 s in the past
    sut.warmupStartAudioTime = -2  // audio clock: warm-up already elapsed
    // Defeat the post-warmup sync frame
    sut.justExitedWarmup = false
    // Guitar mode (absolute threshold path) — suite init() ensures this is
    // already set; explicit assignment here is a belt-and-suspenders guard.
    TapDisplaySettings.measurementType = .acoustic
    // Disconnect Combine subscriptions so the $magnitudes publisher cannot fire analyzeMagnitudes
    // between detectTap() returning and the assertion.
    //
    // These tests observe `decayTapAudioTime`, which a confirmed tap sets to its own audio time and
    // nothing clears. (They observed `lastTapTime` until #19 removed it with the cooldown gate it
    // fed — a gate no production path reached.) They used to
    // observe a `tapDetected` flag that existed on the analyzer for no other purpose: no view and no
    // model logic ever read it, in any edition — Python alone had wired a status-dot flash to it.
    // A production field kept alive to make tests observable is the application bending to the
    // suite, so it was removed and the assertions moved to state the app actually keeps (#17 F43).
    // It also read better than the flag did: `tapDetected` was true for ONE frame and the next frame
    // cleared it, so a test feeding one chunk too many failed while the code was right.
    // @MainActor on the suite ensures tests run on the main thread, so all
    // DispatchQueue.main deliveries queued during init() have already drained
    // before we reach cancellables.removeAll().
    sut.cancellables.removeAll()
    return sut
}

// Synthetic spectrum with a single bin of data — sufficient for the detection path.
private let fakeMags: [Float] = [Float](repeating: -80, count: 64)
private let fakeFreqs: [Float] = (0..<64).map { Float($0) * 375 }

// ---------------------------------------------------------------------------
// MARK: - T1: Signal crossing rising threshold fires tap
// ---------------------------------------------------------------------------

@Suite("TapDetection", .serialized)
@MainActor
struct TapDetectionTests {

    // TapDisplaySettings is redirected to an isolated UserDefaults suite by
    // TestRunner.setUp() so test runs never touch real user settings.
    // Reset to .acoustic before each test so tests that set .plate don't
    // affect subsequent tests in the same run.
    init() { TapDisplaySettings.measurementType = .acoustic }

    // T1: Rising edge above threshold records a tap.
    @Test func aboveThreshold_setsTapDetected() {
        let sut = makeSUT(threshold: -40)
        sut.detectionState = .listening
        sut.isAboveThreshold = false   // currently below

        // Rising-edge fires after RealtimeFFTAnalyzer.levelCrossingConfirmationChunks
        // consecutive above-rising-threshold calls — see TapToneAnalyzer+TapDetection.
        for _ in 0..<RealtimeFFTAnalyzer.levelCrossingConfirmationChunks {
            sut.detectTap(level: -35, audioTime: 0, magnitudes: fakeMags, frequencies: fakeFreqs)
        }

        #expect(sut.decayTapAudioTime != nil, "a tap should be recorded after crossing the rising threshold")
    }

    // T1c-T1e: the detector must use the threshold the APPLICATION configured.
    //
    // The `test/tap-decisions` DSP cases pin the detection rule with the threshold handed to them as
    // an argument, which says nothing about whether the shipping path delivers the right number.
    // PARITY-TEST-METHOD rule 1 — check what the APPLICATION passes, not what the test does. Here
    // the application's path IS `tapDetectionThreshold` on the analyzer: the slider binds to it and
    // `detectTap` reads it. These pass in Swift and Python for that reason, and failed on the web,
    // where #17 F30 moved the detector onto the analyzer and left the threshold behind in the
    // engine's config — the slider went dead and detection sat at the -40 dB default.

    // T1c: a level BELOW the configured threshold must not fire.
    @Test func belowConfiguredThreshold_doesNotFire() {
        let sut = makeSUT(threshold: -30)
        sut.detectionState = .listening
        sut.isAboveThreshold = false

        // -35 is quieter than the configured -30, but LOUDER than the -40 default. An edition that
        // ignores the configured value and falls back to its default fires here.
        for _ in 0..<RealtimeFFTAnalyzer.levelCrossingConfirmationChunks {
            sut.detectTap(level: -35, audioTime: 0, magnitudes: fakeMags, frequencies: fakeFreqs)
        }

        #expect(sut.decayTapAudioTime == nil,
                "a tap quieter than the configured threshold must not fire — if this fails, the detector is not reading the configured value")
    }

    // T1d: the control — a level above it still fires, so T1c cannot pass by detecting nothing.
    @Test func aboveConfiguredThreshold_fires() {
        let sut = makeSUT(threshold: -30)
        sut.detectionState = .listening
        sut.isAboveThreshold = false

        for _ in 0..<RealtimeFFTAnalyzer.levelCrossingConfirmationChunks {
            sut.detectTap(level: -25, audioTime: 0, magnitudes: fakeMags, frequencies: fakeFreqs)
        }

        #expect(sut.decayTapAudioTime != nil)
    }

    // T1e: the same tap, judged against two thresholds, must be decided differently.
    @Test func theSameTapIsAcceptedOrRejectedByTheThreshold() {
        let lenient = makeSUT(threshold: -50)
        lenient.detectionState = .listening
        lenient.isAboveThreshold = false
        for _ in 0..<RealtimeFFTAnalyzer.levelCrossingConfirmationChunks {
            lenient.detectTap(level: -45, audioTime: 0, magnitudes: fakeMags, frequencies: fakeFreqs)
        }
        #expect(lenient.decayTapAudioTime != nil, "-45 clears a -50 threshold")

        let strict = makeSUT(threshold: -35)
        strict.detectionState = .listening
        strict.isAboveThreshold = false
        for _ in 0..<RealtimeFFTAnalyzer.levelCrossingConfirmationChunks {
            strict.detectTap(level: -45, audioTime: 0, magnitudes: fakeMags, frequencies: fakeFreqs)
        }
        #expect(strict.decayTapAudioTime == nil, "the same tap is too quiet for a -35 threshold")
    }

    // T1f: the re-arm rule — a ring-out above the falling threshold is not a new tap.
    //
    // Between taps in a multi-tap sequence the detector sits LATCHED ABOVE with no capture running.
    // Hysteresis says the ring-out must fall below `falling` (threshold - hysteresisMargin) before
    // anything counts as a new strike; a decay that dips past `rising` but stays above `falling` is
    // the SAME tap still sounding. Here `isAboveThreshold` is both the latch and the gate, so while
    // it is up no counting happens at all. Web splits the two — its latch is `isAboveThreshold` but
    // firing is gated by `prevAbove`, which clears as soon as the level drops below `rising` — so a
    // ring-out that never reaches `falling` re-arms it. Paired with Python test_T1f and web's
    // "the re-arm rule" cases.
    @Test func ringOutAboveFallingThreshold_isNotANewTap() {
        let sut = makeSUT(threshold: -40)   // rising -40, falling -43
        sut.detectionState = .listening
        sut.isAboveThreshold = true         // the between-taps state: fired, capture done, not settled

        for _ in 0..<3 {  // ring-out: below rising, ABOVE falling — still the same tap
            sut.detectTap(level: -42, audioTime: 0, magnitudes: fakeMags, frequencies: fakeFreqs)
        }
        for _ in 0..<3 {  // the decay swings back up
            sut.detectTap(level: -20, audioTime: 0, magnitudes: fakeMags, frequencies: fakeFreqs)
        }

        #expect(sut.decayTapAudioTime == nil,
                "a ring-out that never fell below the falling threshold must not be taken as a new tap")
    }

    // T1g: the control — a dip BELOW falling does re-arm, so T1f cannot pass by never firing.
    @Test func dipBelowFallingThreshold_doesReArm() {
        let sut = makeSUT(threshold: -40)
        sut.detectionState = .listening
        sut.isAboveThreshold = true

        for _ in 0..<3 {  // the signal genuinely settled
            sut.detectTap(level: -60, audioTime: 0, magnitudes: fakeMags, frequencies: fakeFreqs)
        }
        for _ in 0..<RealtimeFFTAnalyzer.levelCrossingConfirmationChunks {
            sut.detectTap(level: -20, audioTime: 0, magnitudes: fakeMags, frequencies: fakeFreqs)
        }

        #expect(sut.decayTapAudioTime != nil)
    }

    // T1b: a detected tap is stamped with the AUDIO time of the chunk that confirmed it.
    @Test func aboveThreshold_stampsTheTapsAudioTime() {
        let sut = makeSUT(threshold: -40)
        sut.detectionState = .listening
        sut.isAboveThreshold = false

        let chunks = RealtimeFFTAnalyzer.levelCrossingConfirmationChunks
        for k in 0..<chunks {
            sut.detectTap(level: -35, audioTime: 2.0 + Double(k) * 0.02, magnitudes: fakeMags, frequencies: fakeFreqs)
        }

        #expect(sut.decayTapAudioTime == 2.0 + Double(chunks - 1) * 0.02,
                "the tap's time is the confirming chunk's audio time")
    }

    // T2: Signal below threshold records no tap.
    @Test func belowThreshold_doesNotDetect() {
        let sut = makeSUT(threshold: -40)
        sut.detectionState = .listening
        sut.isAboveThreshold = false

        sut.detectTap(level: -50, audioTime: 0, magnitudes: fakeMags, frequencies: fakeFreqs)

        #expect(sut.decayTapAudioTime == nil, "Signal below threshold must not trigger detection")
    }

    // T3: Calls during warm-up period suppress detection entirely.
    @Test func duringWarmup_suppressesDetection() {
        let sut = makeSUT()
        sut.detectionState = .listening
        sut.isAboveThreshold = false
        // Warm-up still active: start the window at the engine's current audio time (0 in tests, and
        // detectTap is called directly so the audio clock never advances → still inside the window).
        sut.warmupStartAudioTime = sut.fftAnalyzer.audioElapsed

        sut.detectTap(level: -20, audioTime: 0, magnitudes: fakeMags, frequencies: fakeFreqs)

        #expect(sut.decayTapAudioTime == nil, "Should not detect during warm-up")
    }

    // T5: Hysteresis — signal that rises above risingThreshold but then only
    // drops to fallingThreshold+ε should keep isAboveThreshold = true and
    // should NOT trigger a new tap.  hysteresisMargin is hardcoded to 3 dB.
    @Test func hysteresis_preventsBouncingOnFallingEdge() {
        let sut = makeSUT(threshold: -40)
        sut.detectionState = .listening

        // First sequence: rising-edge confirmation requires N consecutive
        // above-rising-threshold calls before firing — feed enough to latch.
        sut.isAboveThreshold = false
        for _ in 0..<RealtimeFFTAnalyzer.levelCrossingConfirmationChunks {
            sut.detectTap(level: -35, audioTime: 0, magnitudes: fakeMags, frequencies: fakeFreqs)
        }
        // A tap has fired; isAboveThreshold == true.

        // The anchor: the first tap was stamped at audio time 0; a second tap, fed at 1, would move it.
        let anchor = sut.decayTapAudioTime

        // Second call: signal at -42 dB — between fallingThreshold (-43) and
        // risingThreshold (-40). Should stay "above" and not fire a new tap.
        sut.detectTap(level: -42, audioTime: 1, magnitudes: fakeMags, frequencies: fakeFreqs)

        // isAboveThreshold should still be true (signal > fallingThreshold -43)
        #expect(sut.isAboveThreshold == true,
                "Signal above fallingThreshold should keep isAboveThreshold = true")
        #expect(anchor == 0 && sut.decayTapAudioTime == anchor,
                "No new tap should fire when still above falling threshold")
    }

    // T5b: Once signal drops below fallingThreshold, isAboveThreshold becomes false
    // (ready for the next rising edge).
    @Test func hysteresis_signalBelowFallingThreshold_resetsAboveThreshold() {
        let sut = makeSUT(threshold: -40)
        sut.detectionState = .listening
        sut.isAboveThreshold = true   // currently above

        // Signal drops below fallingThreshold (-43)
        sut.detectTap(level: -50, audioTime: 0, magnitudes: fakeMags, frequencies: fakeFreqs)

        #expect(sut.isAboveThreshold == false,
                "Signal below fallingThreshold should set isAboveThreshold = false")
    }

    // T8: The first frame after warm-up exits syncs isAboveThreshold but does not fire a tap.
    @Test func justExitedWarmup_syncsThenSkips() {
        let sut = makeSUT(threshold: -40)
        sut.detectionState = .listening
        sut.justExitedWarmup = true
        // warmupStartAudioTime is 2 audio-seconds ago → warm-up check passes

        sut.detectTap(level: -30, audioTime: 0, magnitudes: fakeMags, frequencies: fakeFreqs)

        // No tap must fire on the first sync frame
        #expect(sut.decayTapAudioTime == nil,
                "First frame after warmup should sync state but not fire a tap")
        // justExitedWarmup should be cleared
        #expect(sut.justExitedWarmup == false,
                "justExitedWarmup flag should be cleared after sync frame")
    }

    // T6: Plate mode uses relative detection (noiseFloor + headroom), not the
    // absolute tapDetectionThreshold.
    @Test func plateMode_usesRelativeNoiseFloor() {
        TapDisplaySettings.measurementType = .plate
        defer { TapDisplaySettings.measurementType = .acoustic }

        let fft = RealtimeFFTAnalyzer.forTesting()
        let sut = TapToneAnalyzer(fftAnalyzer: fft)
        sut.tapDetectionThreshold = -40
        sut.numberOfTaps = 1
        sut.warmupStartAudioTime = -2  // audio clock: warm-up already elapsed
        sut.justExitedWarmup = false
        sut.detectionState = .listening
        sut.isAboveThreshold = false
        // Put the analyzer in the correct plate phase so handlePlateTapDetection
        // doesn't fall through to the .notStarted warning branch and discard the tap.
        sut.materialTapPhase = .capturingLongitudinal
        // Disconnect Combine subscriptions (same reason as makeSUT)
        sut.cancellables.removeAll()

        // Set a controlled noise floor estimate
        sut.noiseFloorEstimate = -70
        // headroom = max(-40 - (-70), 10) = 30 dB
        // effectiveRisingThreshold = -70 + 30 = -40 dB
        // So a signal at -35 dB should fire after N consecutive above-threshold calls.
        for _ in 0..<RealtimeFFTAnalyzer.levelCrossingConfirmationChunks {
            sut.detectTap(level: -35, audioTime: 0, magnitudes: fakeMags, frequencies: fakeFreqs)
        }

        // Plate taps do not start ring-out tracking, so `decayTapAudioTime` is not set here; the tap's
        // own effect is that detection stops while its gated capture runs.
        #expect(sut.detectionState == .idle,
                "Plate mode: signal above noise floor + headroom should fire")
    }

    // T7: Noise floor EMA converges toward signal when below threshold.
    @Test func noiseFloorEMA_convergesWithRepeatedBelowThresholdFrames() {
        TapDisplaySettings.measurementType = .plate
        defer { TapDisplaySettings.measurementType = .acoustic }

        let fft = RealtimeFFTAnalyzer.forTesting()
        let sut = TapToneAnalyzer(fftAnalyzer: fft)
        sut.tapDetectionThreshold = -40
        sut.warmupStartAudioTime = -2  // audio clock: warm-up already elapsed
        sut.justExitedWarmup = false
        sut.isAboveThreshold = false  // stays below threshold

        let startEstimate = sut.noiseFloorEstimate  // initial value (-60)
        let target: Float = -55  // ambient level we'll feed in

        // Feed 50 frames at -55 dB (below threshold → EMA updates)
        for _ in 0..<50 {
            sut.detectTap(level: target, audioTime: 0, magnitudes: fakeMags, frequencies: fakeFreqs)
        }

        // EMA with α=0.05, 50 steps from -60 toward -55:
        // After 50 steps: estimate ≈ -60 + (-55 - -60) × (1 - (1-0.05)^50) ≈ -57.4
        // The estimate should have moved noticeably toward -55 (i.e. > -58)
        #expect(sut.noiseFloorEstimate > startEstimate,
                "Noise floor should increase toward ambient level after repeated frames")
        #expect(sut.noiseFloorEstimate > -58,
                "Noise floor after 50 frames at -55 dB should be close to -55 (got \(sut.noiseFloorEstimate))")
    }
}
