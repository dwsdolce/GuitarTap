//
//  SessionPreRollTests.swift
//  GuitarTapTests
//
//  The session WAV: its head is trimmed to a 2 s pre-roll only before the first tap — everything
//  after, later taps and the gaps between them, is completely live — and Dump Capture Audio decides
//  whether it is saved. The shared cases in `session-pre-roll.json` (SR1–SR14), the same as Python and
//  the web; and the capture probe's case, which runs only in a build with the probe on.
//
// @parity test/session-pre-roll

import Testing
import Foundation
@testable import GuitarTap

private final class SessionPreRollAnchor {}

@Suite("SessionPreRoll", .serialized)
struct SessionPreRollTests {

    // MARK: - The shared cases in `session-pre-roll.json` (SR1–SR14)

    nonisolated private struct Step: Decodable {
        let start: Bool?, chunks: Int?, tap: Bool?, release: Bool?, dump: Bool?, pause: Bool?, resume: Bool?
    }
    nonisolated private struct Expect: Decodable { let saved: Bool?, recording: Bool?, samples: Int?, preRoll: Bool? }
    nonisolated private struct Case: Decodable { let id: String, steps: [Step], expect: Expect }
    nonisolated private struct Cases: Decodable { let rate: Double, chunk: Int, preRollSeconds: Double, cases: [Case] }

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
            } else if step.release == true {
                sut.gatedCaptureActive = false
            } else if let dump = step.dump {
                TapDisplaySettings.dumpCaptureAudio = dump
                sut.applyDumpCaptureAudioSetting()
            } else if step.pause == true {
                sut.pauseTapDetection()
            } else if step.resume == true {
                sut.resumeTapDetection()
            }
        }
        if let saved = c.expect.saved { #expect(sut.isSessionRecordingEnabled == saved, "\(id) saved") }
        if let recording = c.expect.recording { #expect(sut.isSessionRecording == recording, "\(id) recording") }
        if let samples = c.expect.samples {
            #expect(sut.sessionRecordingBuffer.count == samples, "\(id) samples: \(sut.sessionRecordingBuffer.count)")
        }
        if let preRoll = c.expect.preRoll { #expect(sut.sessionPreRollActive == preRoll, "\(id) preRoll") }
    }

    /// The pre-roll's length: the file's `preRollSeconds`.
    @Test func preRollLength() {
        #expect(TapToneAnalyzer.sessionPreRollDuration == Self.shared.preRollSeconds)
    }

    // The capture probe's records follow the recording: a sequence saved because Dump Capture Audio was
    // turned on before its first tap has its probe file too. Runs only in a build with the probe on.
    @Test(.enabled(if: CaptureProbe.liveProbe, "the capture probe is switched off"))
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
