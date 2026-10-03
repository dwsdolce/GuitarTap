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

private final class DecayTrackingTestsAnchor {}

@Suite("DecayTracking")
@MainActor
struct DecayTrackingTests {

    // MARK: - measureDecayTime — the shared cases in `decay-tracking.json` (DK1–DK5, DK8–DK10)

    static let data: [String: Any] = {
        let url = Bundle(for: DecayTrackingTestsAnchor.self).url(forResource: "decay-tracking", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    @Test func defaultThreshold() {
        #expect(makeSUT().decayThreshold == Float(Self.data["defaultThreshold"] as! Double))
    }

    @Test(arguments: (data["measureDecayTime"] as! [[String: Any]]).map { $0["id"] as! String })
    func measureDecayTime(_ id: String) {
        let row = (Self.data["measureDecayTime"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let entries = history((row["magnitudes"] as! [Double]).map { Float($0) },
                              interval: row["interval"] as! Double, start: row["start"] as! Double)
        let t = measure(entries, tapTime: row["tapTime"] as! Double, threshold: (row["threshold"] as? Double).map { Float($0) })
        if let expected = row["expect"] as? Double {
            #expect(t.map { abs(Double($0) - expected) < (Self.data["tolerance"] as! Double) } == true, "\(id): got \(String(describing: t))")
        } else {
            #expect(t == nil, "\(id)")
        }
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
