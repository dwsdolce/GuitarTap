//
//  TapDetectionTests.swift
//  GuitarTapTests
//
//  Tests for the tap detection hysteresis logic in TapToneAnalyzer+TapDetection.
//
//  Strategy: `detectTap` is directly callable as a method on TapToneAnalyzer.
//  We manipulate its internal guard state (analyzerStartTime, isAboveThreshold,
//  lastTapTime) directly via @testable import so the method exercises pure logic
//  without a real audio engine.  The `fftAnalyzer.peakMagnitude` and `recentPeakLevelDB`
//  properties are read by `handleTapDetection`, so we construct a no-op
//  RealtimeFFTAnalyzer that never starts.
//
//  Test plan coverage: T1–T9
//

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helper
// ---------------------------------------------------------------------------

/// Build a non-running TapToneAnalyzer in guitar mode (absolute threshold)
/// with its warm-up period satisfied so detectTap can fire.
private func makeSUT(
    threshold: Float = -40,
    hysteresis: Float = 5,
    numberOfTaps: Int = 1
) -> TapToneAnalyzer {
    let fft = RealtimeFFTAnalyzer()
    let sut = TapToneAnalyzer(fftAnalyzer: fft)
    sut.tapDetectionThreshold = threshold
    sut.hysteresisMargin = hysteresis
    sut.numberOfTaps = numberOfTaps
    // Defeat the warmup guard by setting the start time 2 s in the past
    sut.analyzerStartTime = Date(timeIntervalSinceNow: -2)
    // Defeat the post-warmup sync frame
    sut.justExitedWarmup = false
    // Ensure guitar mode (absolute threshold path)
    TapDisplaySettings.measurementType = .acoustic
    // Disconnect Combine subscriptions so that the $magnitudes publisher
    // cannot fire analyzeMagnitudes (which resets tapDetected when isRunning==false)
    // between detectTap() returning and the #expect assertion reading the value.
    // On device with Swift Testing on the main thread, queued main-actor Combine
    // deliveries drain before the next statement when the test is already on main.
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
struct TapDetectionTests {

    // T1: Rising edge above threshold sets tapDetected = true.
    @Test func aboveThreshold_setsTapDetected() {
        let sut = makeSUT(threshold: -40)
        sut.isDetecting = true
        sut.isAboveThreshold = false   // currently below

        sut.detectTap(peakMagnitude: -35, magnitudes: fakeMags, frequencies: fakeFreqs)

        #expect(sut.tapDetected == true, "tapDetected should be true after crossing rising threshold")
    }

    // T1b: lastTapTime is set when a tap is detected.
    @Test func aboveThreshold_setsLastTapTime() {
        let sut = makeSUT(threshold: -40)
        sut.isDetecting = true
        sut.isAboveThreshold = false

        let before = Date()
        sut.detectTap(peakMagnitude: -35, magnitudes: fakeMags, frequencies: fakeFreqs)
        let after = Date()

        #expect(sut.lastTapTime != nil, "lastTapTime should be set on detection")
        if let t = sut.lastTapTime {
            #expect(t >= before && t <= after)
        }
    }

    // T2: Signal below threshold leaves tapDetected = false.
    @Test func belowThreshold_doesNotDetect() {
        let sut = makeSUT(threshold: -40)
        sut.isDetecting = true
        sut.isAboveThreshold = false

        sut.detectTap(peakMagnitude: -50, magnitudes: fakeMags, frequencies: fakeFreqs)

        #expect(sut.tapDetected == false, "Signal below threshold must not trigger detection")
    }

    // T3: Calls during warm-up period suppress detection entirely.
    @Test func duringWarmup_suppressesDetection() {
        let sut = makeSUT()
        sut.isDetecting = true
        sut.isAboveThreshold = false
        // Set start time to "now" so warmup is still active
        sut.analyzerStartTime = Date()

        sut.detectTap(peakMagnitude: -20, magnitudes: fakeMags, frequencies: fakeFreqs)

        #expect(sut.tapDetected == false, "Should not detect during warm-up")
    }

    // T4: A second detectTap call within tapCooldown (0.5 s) is rejected.
    @Test func duringCooldown_suppressesDetection() {
        let sut = makeSUT(threshold: -40)
        sut.isDetecting = true
        sut.isAboveThreshold = false

        // Simulate that a tap was just recorded 0.1 s ago
        sut.lastTapTime = Date(timeIntervalSinceNow: -0.1)

        sut.detectTap(peakMagnitude: -30, magnitudes: fakeMags, frequencies: fakeFreqs)

        #expect(sut.tapDetected == false, "Should not fire while in cooldown window")
    }

    // T5: Hysteresis — signal that rises above risingThreshold but then only
    // drops to fallingThreshold+ε should keep isAboveThreshold = true and
    // should NOT trigger a new tap.
    @Test func hysteresis_preventsBouncingOnFallingEdge() {
        let sut = makeSUT(threshold: -40, hysteresis: 5)
        sut.isDetecting = true

        // First call: rising edge fires the tap
        sut.isAboveThreshold = false
        sut.detectTap(peakMagnitude: -35, magnitudes: fakeMags, frequencies: fakeFreqs)
        // tapDetected == true, isAboveThreshold == true

        // Advance lastTapTime past cooldown so next call isn't blocked by cooldown
        sut.lastTapTime = Date(timeIntervalSinceNow: -1)

        // Second call: signal at -43 dB — between fallingThreshold (-45) and
        // risingThreshold (-40). Should stay "above" and not fire a new tap.
        sut.tapDetected = false
        sut.detectTap(peakMagnitude: -43, magnitudes: fakeMags, frequencies: fakeFreqs)

        // isAboveThreshold should still be true (signal > fallingThreshold -45)
        #expect(sut.isAboveThreshold == true,
                "Signal above fallingThreshold should keep isAboveThreshold = true")
        #expect(sut.tapDetected == false,
                "No new tap should fire when still above falling threshold")
    }

    // T5b: Once signal drops below fallingThreshold, isAboveThreshold becomes false
    // (ready for the next rising edge).
    @Test func hysteresis_signalBelowFallingThreshold_resetsAboveThreshold() {
        let sut = makeSUT(threshold: -40, hysteresis: 5)
        sut.isDetecting = true
        sut.isAboveThreshold = true   // currently above

        // Signal drops below fallingThreshold (-45)
        sut.detectTap(peakMagnitude: -50, magnitudes: fakeMags, frequencies: fakeFreqs)

        #expect(sut.isAboveThreshold == false,
                "Signal below fallingThreshold should set isAboveThreshold = false")
    }

    // T8: The first frame after warm-up exits syncs isAboveThreshold but does not
    // fire tapDetected.
    @Test func justExitedWarmup_syncsThenSkips() {
        let sut = makeSUT(threshold: -40)
        sut.isDetecting = true
        sut.justExitedWarmup = true
        // analyzerStartTime is 2 s ago → warmup check passes

        sut.detectTap(peakMagnitude: -30, magnitudes: fakeMags, frequencies: fakeFreqs)

        // tapDetected must NOT fire on the first sync frame
        #expect(sut.tapDetected == false,
                "First frame after warmup should sync state but not fire a tap")
        // justExitedWarmup should be cleared
        #expect(sut.justExitedWarmup == false,
                "justExitedWarmup flag should be cleared after sync frame")
    }

    // T6: Material mode uses relative detection (noiseFloor + headroom), not the
    // absolute tapDetectionThreshold.
    @Test func materialMode_usesRelativeNoiseFloor() {
        TapDisplaySettings.measurementType = .material
        defer { TapDisplaySettings.measurementType = .acoustic }

        let fft = RealtimeFFTAnalyzer()
        let sut = TapToneAnalyzer(fftAnalyzer: fft)
        sut.tapDetectionThreshold = -40
        sut.hysteresisMargin = 5
        sut.numberOfTaps = 1
        sut.analyzerStartTime = Date(timeIntervalSinceNow: -2)
        sut.justExitedWarmup = false
        sut.isDetecting = true
        sut.isAboveThreshold = false
        // Put the analyzer in the correct material phase so handleMaterialTapDetection
        // doesn't fall through to the .notStarted warning branch and discard the tap.
        sut.materialTapPhase = .capturingLongitudinal
        // Disconnect Combine subscriptions (same reason as makeSUT)
        sut.cancellables.removeAll()

        // Set a controlled noise floor estimate
        sut.noiseFloorEstimate = -70
        // headroom = max(-40 - (-70), 10) = 30 dB
        // effectiveRisingThreshold = -70 + 30 = -40 dB
        // So a signal at -35 dB should fire
        sut.detectTap(peakMagnitude: -35, magnitudes: fakeMags, frequencies: fakeFreqs)

        #expect(sut.tapDetected == true,
                "Material mode: signal above noise floor + headroom should fire")
    }

    // T7: Noise floor EMA converges toward signal when below threshold.
    @Test func noiseFloorEMA_convergesWithRepeatedBelowThresholdFrames() {
        TapDisplaySettings.measurementType = .material
        defer { TapDisplaySettings.measurementType = .acoustic }

        let fft = RealtimeFFTAnalyzer()
        let sut = TapToneAnalyzer(fftAnalyzer: fft)
        sut.tapDetectionThreshold = -40
        sut.hysteresisMargin = 5
        sut.analyzerStartTime = Date(timeIntervalSinceNow: -2)
        sut.justExitedWarmup = false
        sut.isAboveThreshold = false  // stays below threshold

        let startEstimate = sut.noiseFloorEstimate  // initial value (-60)
        let target: Float = -55  // ambient level we'll feed in

        // Feed 50 frames at -55 dB (below threshold → EMA updates)
        for _ in 0..<50 {
            sut.detectTap(peakMagnitude: target, magnitudes: fakeMags, frequencies: fakeFreqs)
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
