//
//  SessionPreRollTests.swift
//  GuitarTapTests
//
//  Pins the bounded pre-roll for the session WAV:
//  the head is trimmed to ~2 s ONLY before the first tap; everything after — subsequent taps,
//  plate phases, and the gaps between them — is completely live. Three-way with Python
//  test_session_pre_roll.py and web session-pre-roll.test.ts.
//
// @parity test/session-pre-roll

import Testing
import Foundation
@testable import GuitarTap

@Suite("SessionPreRoll", .serialized)
struct SessionPreRollTests {

    private func makeSUT(rate: Double = 48000) -> TapToneAnalyzer {
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        sut.sessionRecordingSampleRate = rate
        sut.isSessionRecording = true
        sut.sessionPreRollActive = true
        sut.gatedCaptureActive = false
        sut.sessionRecordingBuffer = []
        return sut
    }

    /// One ~21 ms chunk at 48 kHz.
    private let chunk = [Float](repeating: 0, count: 1024)

    // MARK: - Before the first tap: the head is bounded

    @Test func idleBeforeFirstTap_isBoundedToPreRoll() {
        let sut = makeSUT()
        // Feed far more than 2 s of idle (2 s ≈ 96000 samples ≈ 94 chunks). 300 chunks ≈ 6.4 s.
        for _ in 0..<300 { sut.maintainSessionRecording(appending: chunk) }
        #expect(sut.sessionRecordingBuffer.count <= sut.sessionPreRollSamples,
                "Idle before the first tap must be bounded to ~2 s, not accumulate every chunk")
        // And it keeps at least a chunk under the cap — it retains the recent tail.
        #expect(sut.sessionRecordingBuffer.count > sut.sessionPreRollSamples - chunk.count)
    }

    // MARK: - The first tap freezes the latch

    @Test func firstTap_freezesPreRoll() {
        let sut = makeSUT()
        for _ in 0..<300 { sut.maintainSessionRecording(appending: chunk) }
        #expect(sut.sessionPreRollActive == true)

        sut.gatedCaptureActive = true                 // first tap begins
        sut.maintainSessionRecording(appending: chunk)
        #expect(sut.sessionPreRollActive == false, "The first gated capture must freeze the pre-roll latch")
    }

    // MARK: - THE INVARIANT: everything after the first tap is completely live

    @Test func multiTapMultiPhase_afterFirstTap_isFullyLive() {
        let sut = makeSUT()

        // Idle, then the first tap freezes the pre-roll.
        for _ in 0..<300 { sut.maintainSessionRecording(appending: chunk) }
        sut.gatedCaptureActive = true
        sut.maintainSessionRecording(appending: chunk)   // freezes
        let afterFreeze = sut.sessionRecordingBuffer.count

        // Now simulate a long multi-tap / multi-phase session with big idle GAPS between taps —
        // the kind of idle that WOULD be trimmed if the latch were still armed. Toggle
        // gatedCaptureActive on/off like real taps; none of it may be trimmed.
        var expected = afterFreeze
        for tap in 0..<5 {
            // gap between taps: 200 chunks (~4 s) of idle — far more than the 2 s pre-roll
            sut.gatedCaptureActive = false
            for _ in 0..<200 { sut.maintainSessionRecording(appending: chunk); expected += chunk.count }
            // the tap itself
            sut.gatedCaptureActive = (tap % 2 == 0)
            sut.maintainSessionRecording(appending: chunk); expected += chunk.count
        }

        #expect(sut.sessionRecordingBuffer.count == expected,
                "After the first tap the session must be COMPLETELY LIVE — no chunk trimmed across any subsequent tap, phase, or idle gap")
        #expect(sut.sessionPreRollActive == false, "The latch must stay frozen for the rest of the session")
    }

    // MARK: - The ≥ 0.5 s lead-in guarantee (playback fixtures)

    @Test func preRollExceedsWarmup() {
        let sut = makeSUT()
        // 2 s of retained pre-roll must comfortably exceed the 0.5 s warm-up the playback path needs.
        #expect(Double(sut.sessionPreRollSamples) / sut.sessionRecordingSampleRate >= 0.5)
        #expect(TapToneAnalyzer.sessionPreRollDuration >= 0.5)
    }
}