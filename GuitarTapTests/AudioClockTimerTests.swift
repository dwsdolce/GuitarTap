//
//  AudioClockTimerTests.swift
//  GuitarTapTests
//
//  The tap lifecycle's delays — the rest between material taps, the FLC hold, the capture window —
//  run on the AUDIO clock, so file playback, which advances audio faster or slower than real time,
//  moves them with the audio; the capture's safety timeout runs on the wall clock, which a test moves
//  by hand. The shared cases in `audio-clock-timers.json` (AT1–AT8), the same as Python and the web.
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
}
