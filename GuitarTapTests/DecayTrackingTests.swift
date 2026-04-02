//
//  DecayTrackingTests.swift
//  GuitarTapTests
//
//  Tests for TapToneAnalyzer+DecayTracking:
//  measureDecayTime edge cases and trackDecayFast guard behaviour.
//
//  All tests operate directly on TapToneAnalyzer's published state;
//  no audio hardware or real timing is involved.
//
//  Test plan coverage: DK1–DK7
//

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

@MainActor
private func makeSUT() -> TapToneAnalyzer {
    let fft = RealtimeFFTAnalyzer()
    let sut = TapToneAnalyzer(fftAnalyzer: fft)
    sut.cancellables.removeAll()
    return sut
}

/// Builds a history array of (time, magnitude) tuples centred on `referenceDate`.
/// Samples are spaced `intervalSeconds` apart, starting at `referenceDate`.
private func makeHistory(
    startingAt referenceDate: Date,
    intervalSeconds: TimeInterval = 0.1,
    magnitudes: [Float]
) -> [(time: Date, magnitude: Float)] {
    magnitudes.enumerated().map { index, mag in
        (time: referenceDate.addingTimeInterval(Double(index) * intervalSeconds), magnitude: mag)
    }
}

// ---------------------------------------------------------------------------
// MARK: - DK1–DK5: measureDecayTime edge cases
// ---------------------------------------------------------------------------

@Suite("DecayTracking")
@MainActor
struct DecayTrackingTests {

    // DK1: Empty history → nil (no samples to analyse).
    @Test func measureDecayTime_emptyHistory_returnsNil() {
        let sut = makeSUT()
        sut.peakMagnitudeHistory = []
        let tapTime = Date()
        let result = sut.measureDecayTime(tapTime: tapTime)
        #expect(result == nil, "Expected nil for empty history")
    }

    // DK2: All samples are before tapTime → postTapHistory is empty → nil.
    @Test func measureDecayTime_allSamplesBeforeTap_returnsNil() {
        let sut = makeSUT()
        let tapTime = Date()
        // Place all samples 1 s before the tap
        sut.peakMagnitudeHistory = makeHistory(
            startingAt: tapTime.addingTimeInterval(-1.0),
            magnitudes: [-20, -25, -30, -35, -40, -50]
        )
        let result = sut.measureDecayTime(tapTime: tapTime)
        #expect(result == nil, "Expected nil when all samples precede tapTime")
    }

    // DK3: Signal never decays by decayThreshold → nil (threshold not crossed).
    @Test func measureDecayTime_signalNeverDecays_returnsNil() {
        let sut = makeSUT()
        sut.decayThreshold = 30  // require 30 dB drop
        let tapTime = Date()
        // Peak is −20 dB; subsequent samples only drop to −25 dB (5 dB, not 30)
        sut.peakMagnitudeHistory = makeHistory(
            startingAt: tapTime,
            magnitudes: [-20, -22, -24, -25, -25, -25, -25]
        )
        let result = sut.measureDecayTime(tapTime: tapTime)
        #expect(result == nil, "Expected nil when signal never decays enough")
    }

    // DK4: Signal decays past threshold → returns positive elapsed time.
    @Test func measureDecayTime_normalDecay_returnsPositiveTime() {
        let sut = makeSUT()
        sut.decayThreshold = 20  // require 20 dB drop
        let tapTime = Date()
        // Peak at index 0 = −10 dB; target = −30 dB; crossing at index 5 = −31 dB
        // Time between index 0 and index 5 = 5 × 0.1 s = 0.5 s
        sut.peakMagnitudeHistory = makeHistory(
            startingAt: tapTime,
            magnitudes: [-10, -15, -20, -24, -28, -31, -35]
        )
        let result = sut.measureDecayTime(tapTime: tapTime)
        #expect(result != nil, "Expected a decay time value")
        if let t = result {
            #expect(t > 0, "Decay time must be positive, got \(t)")
            // 5 intervals × 0.1 s = 0.5 s; allow ±0.05 s for floating-point
            #expect(abs(t - 0.5) < 0.05, "Expected ≈0.5 s, got \(t)")
        }
    }

    // DK5: Decay crossing immediately after the peak → very short but positive time.
    @Test func measureDecayTime_immediateDecay_returnsShortPositiveTime() {
        let sut = makeSUT()
        sut.decayThreshold = 10
        let tapTime = Date()
        // Peak at −10 dB; second sample at −21 dB already crosses (target = −20 dB)
        sut.peakMagnitudeHistory = makeHistory(
            startingAt: tapTime,
            intervalSeconds: 0.1,
            magnitudes: [-10, -21, -30, -40]
        )
        let result = sut.measureDecayTime(tapTime: tapTime)
        #expect(result != nil, "Expected a decay time for immediate drop")
        if let t = result {
            #expect(t > 0, "Decay time must be positive, got \(t)")
        }
    }

    // ---------------------------------------------------------------------------
    // MARK: - DK6–DK7: trackDecayFast guard behaviour
    // ---------------------------------------------------------------------------

    // DK6: When isTrackingDecay is false, trackDecayFast is a no-op —
    //      peakMagnitudeHistory is not modified.
    @Test func trackDecayFast_notTracking_isNoOp() {
        let sut = makeSUT()
        sut.isTrackingDecay = false
        let initialHistory = sut.peakMagnitudeHistory
        sut.trackDecayFast(inputLevel: -20)
        #expect(sut.peakMagnitudeHistory.count == initialHistory.count,
                "History must not grow when isTrackingDecay is false")
    }

    // DK7: When isTrackingDecay is true but lastTapTime is nil,
    //      samples accumulate but currentDecayTime stays nil
    //      (requires > minimumDecayHistoryCount samples before any measurement attempt).
    @Test func trackDecayFast_tracking_noTapTime_accumulates() {
        let sut = makeSUT()
        sut.isTrackingDecay = true
        sut.lastTapTime = nil
        sut.currentDecayTime = nil
        let before = sut.peakMagnitudeHistory.count
        sut.trackDecayFast(inputLevel: -30)
        #expect(sut.peakMagnitudeHistory.count == before + 1,
                "Sample should be appended when tracking is active")
        #expect(sut.currentDecayTime == nil,
                "currentDecayTime stays nil when lastTapTime is not set")
    }
}
