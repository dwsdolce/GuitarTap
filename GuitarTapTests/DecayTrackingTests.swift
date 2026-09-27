//
//  DecayTrackingTests.swift
//  GuitarTapTests
//
//  Tests for TapToneAnalyzer+DecayTracking: measureDecayTime on given histories (DK1–DK5, DK8–DK10)
//  and the tracker driven through production (DK6, DK7, DK11–DK13) — a fresh analyzer,
//  startDecayTracking, startTapSequence and the per-chunk entry onChunkLevel.
//
//  No audio hardware or real timing is involved: times are audio-clock seconds.
//
//  Test plan coverage: DK1–DK13 — the same list, ids and values as Python test_decay_tracking.py and
//  web test/decay-tracking.test.ts.
//
// @parity test/decay-tracking

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

@MainActor
private func makeSUT() -> TapToneAnalyzer {
    let fft = RealtimeFFTAnalyzer.forTesting()
    let sut = TapToneAnalyzer(fftAnalyzer: fft)
    sut.cancellables.removeAll()
    return sut
}

/// A history of (audioTime, magnitude) entries `interval` seconds apart, from `start`.
private func history(_ magnitudes: [Float], interval: Double = 0.1,
                     start: Double = 0) -> [(time: Double, magnitude: Float)] {
    magnitudes.enumerated().map { index, magnitude in
        (time: start + Double(index) * interval, magnitude: magnitude)
    }
}

/// measureDecayTime on an analyzer holding `entries`, with `threshold` if given.
@MainActor
private func measure(_ entries: [(time: Double, magnitude: Float)], tapTime: Double,
                     threshold: Float? = nil) -> Float? {
    let sut = makeSUT()
    if let threshold { sut.decayThreshold = threshold }
    sut.peakMagnitudeHistory = entries
    return sut.measureDecayTime(tapTime: tapTime)
}

private let exact: Float = 1e-6

@Suite("DecayTracking")
@MainActor
struct DecayTrackingTests {

    // MARK: - measureDecayTime

    // DK1: An empty history measures nothing.
    @Test func DK1_emptyHistory_returnsNil() {
        #expect(measure([], tapTime: 0) == nil)
    }

    // DK2: Every entry before the tap — nothing to measure after it.
    @Test func DK2_allSamplesBeforeTap_returnsNil() {
        #expect(measure(history([-20, -25, -30, -35, -40, -50], start: -1.0), tapTime: 0) == nil)
    }

    // DK3: The level never drops by the threshold (30 dB here; it falls 5 dB).
    @Test func DK3_signalNeverDecays_returnsNil() {
        #expect(measure(history([-20, -22, -24, -25, -25, -25, -25]), tapTime: 0, threshold: 30) == nil)
    }

    // DK4: Peak −10 at 0 s; target −30 (20 dB); the first entry below it is −31 at 0.5 s.
    @Test func DK4_normalDecay_isTimedFromPeakToCrossing() throws {
        let t = try #require(measure(history([-10, -15, -20, -24, -28, -31, -35]), tapTime: 0, threshold: 20))
        #expect(abs(t - 0.5) < exact, "expected 0.5 s, got \(t)")
    }

    // DK5: Peak −10 at 0 s; target −20 (10 dB); the very next entry, −21 at 0.1 s, crosses.
    @Test func DK5_immediateDecay_isTheNextEntry() throws {
        let t = try #require(measure(history([-10, -21, -30, -40]), tapTime: 0, threshold: 10))
        #expect(abs(t - 0.1) < exact, "expected 0.1 s, got \(t)")
    }

    // MARK: - Tracking, driven through production

    // DK6: A fresh analyzer is not tracking: a chunk is not recorded and no ring-out is measured.
    @Test func DK6_notTracking_recordsNothing() {
        let sut = makeSUT()
        sut.onChunkLevel(-50, audioTime: 0.1)
        #expect(sut.peakMagnitudeHistory.isEmpty, "nothing recorded before tracking starts")
        #expect(sut.currentDecayTime == nil)
    }

    // DK7: A new sequence within 3 s of a tap stops that tap's ring-out tracking and clears its history,
    //      so the chunks after it measure no ring-out from the old tap. The chunks are below the tap
    //      threshold, so no new tap is detected.
    @Test func DK7_newSequence_stopsThePreviousTapsRingOut() {
        let sut = makeSUT()
        sut.tapDetectionThreshold = -40
        sut.tapPeakLevel = -10
        sut.startDecayTracking(tapAudioTime: 0)
        sut.startTapSequence()
        for k in 1...12 {
            sut.onChunkLevel(-50, audioTime: 0.05 * Double(k))
        }
        #expect(!sut.isTrackingDecay, "a new sequence stops the ring-out tracking")
        #expect(sut.currentDecayTime == nil, "no ring-out is measured from the previous tap")
    }

    // MARK: - measureDecayTime, continued

    // DK8: The threshold is 15 dB unless set: peak −10 at 0 s; target −25; −26 at 0.3 s crosses.
    @Test func DK8_defaultThreshold_is15dB() throws {
        #expect(makeSUT().decayThreshold == 15)
        let t = try #require(measure(history([-10, -12, -20, -26, -40]), tapTime: 0))
        #expect(abs(t - 0.3) < exact, "expected 0.3 s, got \(t)")
    }

    // DK9: Timed from the post-tap PEAK, not the tap: the level rises to −8 at 0.1 s; target −23;
    //      −24 at 0.3 s crosses → 0.2 s.
    @Test func DK9_risingTransient_isTimedFromThePeak() throws {
        let t = try #require(measure(history([-12, -8, -15, -24, -40]), tapTime: 0))
        #expect(abs(t - 0.2) < exact, "expected 0.2 s, got \(t)")
    }

    // DK10: An entry before the tap is ignored even when it is loudest: −30 at −0.1 s is skipped; peak
    //       −10 at 0 s; −26 at 0.2 s crosses.
    @Test func DK10_preTapEntries_areIgnored() throws {
        let t = try #require(measure(history([-30, -10, -20, -26], start: -0.1), tapTime: 0))
        #expect(abs(t - 0.2) < exact, "expected 0.2 s, got \(t)")
    }

    // MARK: - Tracking, continued

    // DK11: A ring-out streamed through production: the tap seeds −10 at 0 s, then twelve chunks
    //       falling 2 dB each, 0.05 s apart; target −25; −26 at 0.4 s crosses.
    @Test func DK11_streamedRingOut_isMeasured() throws {
        let sut = makeSUT()
        sut.tapPeakLevel = -10
        sut.startDecayTracking(tapAudioTime: 0)
        for k in 1...12 {
            sut.onChunkLevel(-10 - 2 * Float(k), audioTime: 0.05 * Double(k))
        }
        let t = try #require(sut.currentDecayTime)
        #expect(abs(t - 0.4) < exact, "expected 0.4 s, got \(t)")
    }

    // DK12: Tracking stops at the first chunk 3 s of audio after the tap, without recording it.
    @Test func DK12_tracking_stopsAt3sOfAudio_withoutRecording() {
        let sut = makeSUT()
        sut.tapPeakLevel = -10
        sut.startDecayTracking(tapAudioTime: 0)
        sut.onChunkLevel(-40, audioTime: 2.99)
        #expect(sut.isTrackingDecay && sut.peakMagnitudeHistory.count == 2, "a chunk before 3 s is recorded")
        sut.onChunkLevel(-40, audioTime: 3.0)
        #expect(!sut.isTrackingDecay, "tracking stops at 3 s")
        #expect(sut.peakMagnitudeHistory.count == 2, "the 3 s chunk is not recorded")
    }

    // DK13: No ring-out is measured until the history holds more than 10 entries: the seed and nine
    //       chunks (10 entries) measure nothing; the tenth chunk (11 entries) measures −10 → −50 at 0.05 s.
    @Test func DK13_noRingOut_untilMoreThan10Entries() throws {
        let sut = makeSUT()
        sut.tapPeakLevel = -10
        sut.startDecayTracking(tapAudioTime: 0)
        for k in 1...9 {
            sut.onChunkLevel(-50, audioTime: 0.05 * Double(k))
        }
        #expect(sut.peakMagnitudeHistory.count == 10)
        #expect(sut.currentDecayTime == nil, "10 entries measure nothing")
        sut.onChunkLevel(-50, audioTime: 0.5)
        let t = try #require(sut.currentDecayTime, "11 entries measure the ring-out")
        #expect(abs(t - 0.05) < exact, "expected 0.05 s, got \(t)")
    }
}
