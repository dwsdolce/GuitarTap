//
//  AudioClockTimerTests.swift
//  GuitarTapTests
//
//  The tap lifecycle's delays — the rest between material taps, the FLC hold, the capture window —
//  run on the AUDIO clock, so file playback, which advances audio faster or slower than real time,
//  moves them with the audio. The shared cases in `audio-clock-timers.json` (AT1–AT6), the same as
//  Python and the web, advance only audio. Below them, the safety timeout, which runs on the wall
//  clock by design and so waits in real time.
//
// @parity test/audio-clock-timers

import Testing
import Foundation
@testable import GuitarTap

private final class AudioClockTimerAnchor {}

@Suite("AudioClockTimers", .serialized)
@MainActor
struct AudioClockTimerTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: AudioClockTimerAnchor.self).url(forResource: "audio-clock-timers", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids() -> [String] {
        (data["cases"] as! [[String: Any]]).map { $0["id"] as! String }
    }

    static func check(_ fields: [String: Any], _ sut: TapToneAnalyzer, notedWarmup: Double?, _ id: String) {
        for (field, want) in fields {
            switch field {
            case "detecting": #expect(sut.isDetecting == want as? Bool, "\(id) \(field)")
            case "phase": #expect(sut.materialTapPhase.rawValue == want as? String, "\(id) \(field): \(sut.materialTapPhase)")
            case "complete": #expect(sut.isMeasurementComplete == want as? Bool, "\(id) \(field)")
            case "gatedCapture": #expect(sut.gatedCaptureActive == want as? Bool, "\(id) \(field)")
            case "aboveThreshold": #expect(sut.isAboveThreshold == want as? Bool, "\(id) \(field)")
            case "warmupAtLastChunk":
                #expect((sut.warmupStartAudioTime == sut.lastAudioTime) == want as? Bool, "\(id) \(field)")
            case "warmupUnchanged":
                #expect((sut.warmupStartAudioTime == notedWarmup) == want as? Bool, "\(id) \(field)")
            default: Issue.record("\(id): unknown field \(field)")
            }
        }
    }

    @Test(arguments: ids())
    func audioClock(_ id: String) {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let saved = (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc)
        defer { (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc) = saved }

        let sut = makeStepsAnalyzer()
        var notedWarmup: Double?
        for step in row["steps"] as! [[String: Any]] {
            if step["fileEnd"] as? Bool == true {
                sut.flushGatedCaptureOnFileEnd()
            } else if step["playingFile"] as? Bool == true {
                sut.fftAnalyzer.isPlayingFile = true
            } else if step["noteWarmup"] as? Bool == true {
                notedWarmup = sut.warmupStartAudioTime
            } else if let fields = step["check"] as? [String: Any] {
                Self.check(fields, sut, notedWarmup: notedWarmup, id)
            } else {
                #expect(runAnalyzerStep(step, on: sut), "\(id): unknown step \(step)")
            }
        }
        Self.check(row["expect"] as! [String: Any], sut, notedWarmup: notedWarmup, id)
    }

    // T6: a capture the audio stops filling is closed on the WALL clock — it exists for when the audio
    // stops, and then the audio clock stops too. After it, detection rests and re-arms as usual.
    @Test("the safety timeout closes a capture the audio stopped filling")
    func safetyTimeoutClosesAnUnfilledCapture() async throws {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        TapDisplaySettings.measurementType = .plate
        let sut = makeStepsAnalyzer()
        sut.startTapSequence()
        advanceAudio(sut, by: sut.warmupPeriod + 0.1)
        advanceAudio(sut, by: 2 * audioFeedChunkSeconds, level: -10)   // a tap opens the capture...
        #expect(sut.gatedCaptureActive == true)
        // ...and then no more audio arrives.
        try await Task.sleep(for: .milliseconds(2300))
        #expect(sut.gatedCaptureActive == false, "closed by the wall-clock safety timeout")

        advanceAudio(sut, by: sut.tapCooldown)
        #expect(sut.isDetecting == true, "and detection rests, then re-arms, as after any capture")
    }

    // T6 measures SILENCE, not time since the capture started: while audio keeps arriving — however
    // slowly, as under throttled playback — it does not fire. Measured from the capture's start, it
    // would close captures early whenever playback runs slower than real time.
    @Test("the safety timeout does not fire while audio keeps arriving")
    func safetyTimeoutWaitsForSilence() async throws {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        TapDisplaySettings.measurementType = .plate
        let sut = makeStepsAnalyzer()
        sut.startTapSequence()
        advanceAudio(sut, by: sut.warmupPeriod + 0.1)
        advanceAudio(sut, by: 2 * audioFeedChunkSeconds, level: -10)   // a tap opens the capture
        #expect(sut.gatedCaptureActive == true)
        // Slow audio: one quiet chunk every 0.4 s of wall time, for 2.8 s — longer than the 2 s timeout.
        for _ in 0..<7 {
            try await Task.sleep(for: .milliseconds(400))
            advanceAudio(sut, by: audioFeedChunkSeconds)
        }
        #expect(sut.gatedCaptureActive == true, "audio kept arriving, so the capture is still open")
    }
}
