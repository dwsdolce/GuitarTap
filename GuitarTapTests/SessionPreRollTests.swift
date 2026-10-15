//
//  SessionPreRollTests.swift
//  GuitarTapTests
//
//  Pins the bounded pre-roll for the session WAV:
//  the head is trimmed to ~2 s ONLY before the first tap; everything after — subsequent taps,
//  plate phases, and the gaps between them — is completely live. How Dump Capture Audio decides
//  whether the recording is saved, and what changing it does, are the shared cases in
//  `session-pre-roll.json` (SR1–SR11). Three-way with Python test_session_pre_roll.py and web
//  session-pre-roll.test.ts.
//
// @parity test/session-pre-roll

import Testing
import Foundation
@testable import GuitarTap

private final class SessionPreRollAnchor {}

@Suite("SessionPreRoll", .serialized)
struct SessionPreRollTests {

    private func makeSUT(rate: Double = 48000) -> TapToneAnalyzer {
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        sut.sessionRecordingSampleRate = rate
        sut.isSessionRecording = true
        sut.isSessionRecordingEnabled = true
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

    // MARK: - Dump Capture Audio — the shared cases in `session-pre-roll.json` (SR1–SR11)

    nonisolated private struct Step: Decodable {
        let start: Bool?, chunks: Int?, tap: Bool?, dump: Bool?, pause: Bool?, resume: Bool?
    }
    nonisolated private struct Expect: Decodable { let saved: Bool, recording: Bool, samples: Int }
    nonisolated private struct Case: Decodable { let id: String, steps: [Step], expect: Expect }
    nonisolated private struct Cases: Decodable { let rate: Double, chunk: Int, cases: [Case] }

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default.
    nonisolated private static let shared: Cases = {
        let url = Bundle(for: SessionPreRollAnchor.self).url(forResource: "session-pre-roll", withExtension: "json")!
        return try! JSONDecoder().decode(Cases.self, from: Data(contentsOf: url))
    }()

    @Test(arguments: shared.cases.map(\.id))
    func dumpCaptureAudio(id: String) {
        let data = Self.shared
        let c = data.cases.first { $0.id == id }!
        let savedDump = TapDisplaySettings.dumpCaptureAudio
        defer { TapDisplaySettings.dumpCaptureAudio = savedDump }
        let sut = TapToneAnalyzer.forTesting()
        let samples = [Float](repeating: 0.1, count: data.chunk)
        for step in c.steps {
            if let dump = step.start {
                TapDisplaySettings.dumpCaptureAudio = dump
                sut.startTapSequence()
                sut.sessionRecordingSampleRate = data.rate
                sut.gatedCaptureActive = false
            } else if let n = step.chunks {
                for _ in 0..<n { sut.maintainSessionRecording(appending: samples) }
            } else if step.tap == true {
                sut.gatedCaptureActive = true
                sut.maintainSessionRecording(appending: samples)
            } else if let dump = step.dump {
                TapDisplaySettings.dumpCaptureAudio = dump
                sut.applyDumpCaptureAudioSetting()
            } else if step.pause == true {
                sut.pauseTapDetection()
            } else if step.resume == true {
                sut.resumeTapDetection()
            }
        }
        #expect(sut.isSessionRecordingEnabled == c.expect.saved, "\(id) saved")
        #expect(sut.isSessionRecording == c.expect.recording, "\(id) recording")
        #expect(sut.sessionRecordingBuffer.count == c.expect.samples, "\(id) samples")
    }

    // The capture probe's records follow the recording: a sequence saved because Dump Capture Audio was
    // turned on before its first tap has its probe file too. Runs only in a build with the probe on.
    @Test(.enabled(if: CaptureProbe.liveProbe))
    func captureProbe_followsTheRecording() {
        let savedDump = TapDisplaySettings.dumpCaptureAudio
        let savedSession = CaptureProbe.liveSession
        defer { TapDisplaySettings.dumpCaptureAudio = savedDump; CaptureProbe.liveSession = savedSession }
        let sut = TapToneAnalyzer.forTesting()
        TapDisplaySettings.dumpCaptureAudio = false
        sut.startTapSequence()
        #expect(!CaptureProbe.liveSession)
        TapDisplaySettings.dumpCaptureAudio = true
        sut.applyDumpCaptureAudioSetting()
        #expect(CaptureProbe.liveSession, "turned on before the first tap")
        TapDisplaySettings.dumpCaptureAudio = false
        sut.applyDumpCaptureAudioSetting()
        #expect(!CaptureProbe.liveSession, "turned off")
        sut.gatedCaptureActive = true
        sut.maintainSessionRecording(appending: [Float](repeating: 0.1, count: 1024))
        TapDisplaySettings.dumpCaptureAudio = true
        sut.applyDumpCaptureAudioSetting()
        #expect(!CaptureProbe.liveSession, "turned on after the first tap")
    }
}
