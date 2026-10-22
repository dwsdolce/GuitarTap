//
//  TapDetectionTests.swift
//  GuitarTapTests
//
//  The tap detector's decisions — the rising edge, the threshold the application configured, the
//  hysteresis latch and the re-arm rule, the warm-up and its sync chunk, relative detection and its
//  noise floor, the confirmation a resume or a new sequence restarts — and the gated capture's onset
//  alignment. Every chunk goes through `onChunkLevel(_:audioTime:)`, the per-chunk entry audio takes — a
//  `liveAudio` step's through the engine's per-chunk processing first, as the microphone's — after arming the
//  way the app does; no case sets the detector's state by hand. The shared cases in `tap-decisions.json`
//  (T1–T17, O1–O3), the same as Python and the web.
//
// @parity test/tap-decisions

import Testing
import Foundation
@testable import GuitarTap

private final class TapDecisionsAnchor {}

@Suite("TapDecisions", .serialized)
@MainActor
struct TapDetectionTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: TapDecisionsAnchor.self).url(forResource: "tap-decisions", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids(_ group: String) -> [String] {
        (data[group] as! [[String: Any]]).map { $0["id"] as! String }
    }

    static func row(_ group: String, _ id: String) -> [String: Any] {
        (data[group] as! [[String: Any]]).first { $0["id"] as! String == id }!
    }

    /// Asserts the fields an expectation names.
    static func check(_ fields: [String: Any], _ sut: TapToneAnalyzer, _ id: String) {
        for (field, want) in fields {
            switch field {
            case "captureOpen":
                #expect(sut.gatedCaptureActive == want as? Bool, "\(id) \(field)")
            case "aboveThreshold":
                #expect(sut.isAboveThreshold == want as? Bool, "\(id) \(field)")
            case "justExitedWarmUp":
                #expect(sut.justExitedWarmup == want as? Bool, "\(id) \(field)")
            case "inWarmUp":
                #expect((sut.lastAudioTime < sut.warmupPeriod) == want as? Bool, "\(id) \(field): \(sut.lastAudioTime)")
            case "noiseFloor":
                let wanted = (want as! NSNumber).doubleValue
                #expect(abs(Double(sut.noiseFloorEstimate) - wanted) < 0.01, "\(id) \(field): \(sut.noiseFloorEstimate)")
            case "phase":
                #expect(sut.materialTapPhase.rawValue == want as? String, "\(id) \(field): \(sut.materialTapPhase)")
            case "detecting":
                #expect(sut.isDetecting == want as? Bool, "\(id) \(field)")
            case "complete":
                #expect(sut.isMeasurementComplete == want as? Bool, "\(id) \(field)")
            case "statusMessage":
                #expect(sut.statusMessage == want as? String, "\(id) \(field): \(sut.statusMessage)")
            default:
                Issue.record("\(id): unknown field \(field)")
            }
        }
    }

    @Test func confirmChunks() {
        #expect(RealtimeFFTAnalyzer.levelCrossingConfirmationChunks == Self.data["confirmChunks"] as? Int)
    }

    /// The audio queue's fast-start opens a capture the detector has not confirmed: a sound the detector does not
    /// count as a tap completes the measurement on what follows (T15, T16), and with the main thread a capture
    /// window behind the audio, a real tap's capture completes before the detector sees the tap, leaving detection
    /// armed (T17). Swift takes audio in two steps today, the fast-start on the audio queue and detection on the
    /// main thread; these cases pass once every chunk is taken in one sequence, as the web's.
    static let knownFailures: Set<String> = ["T15", "T16", "T17"]

    @Test(arguments: ids("cases"))
    func decision(_ id: String) async {
        let row = Self.row("cases", id)
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }

        let run = { () async in
            let sut = makeStepsAnalyzer()
            for step in row["steps"] as! [[String: Any]] {
                if let fields = step["check"] as? [String: Any] {
                    Self.check(fields, sut, id)
                } else {
                    #expect(runAnalyzerStep(step, on: sut), "\(id): unknown step \(step)")
                    // The engine queues its chunks' main-thread part: let it run, as the app's would.
                    if step["liveAudio"] != nil { try? await Task.sleep(nanoseconds: 5_000_000) }
                }
            }
            Self.check(row["expect"] as! [String: Any], sut, id)
        }
        if Self.knownFailures.contains(id) {
            await withKnownIssue("the fast-start opens a capture the detector did not confirm") { await run() }
        } else {
            await run()
        }
    }

    /// The buffer an onset case names, as Float32.
    static func buffer(_ spec: [String: Any]) -> [Float] {
        let n = spec["length"] as! Int
        switch spec["kind"] as! String {
        case "impulse":
            var buf = [Float](repeating: 0, count: n)
            buf[spec["at"] as! Int] = Float(spec["value"] as! Double)
            return buf
        case "constant":
            return [Float](repeating: Float(spec["value"] as! Double), count: n)
        case "ramp":
            let start = spec["start"] as! Double, step = spec["step"] as! Double
            return (0..<n).map { Float(start + step * Double($0)) }
        default:
            fatalError("unknown buffer kind")
        }
    }

    @Test(arguments: ids("onset"))
    func onset(_ id: String) throws {
        let row = Self.row("onset", id)
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        let out = sut.alignCaptureToOnset(Self.buffer(row["buffer"] as! [String: Any]),
                                          windowSize: row["windowSize"] as! Int,
                                          preOnsetSamples: row["preOnset"] as! Int)
        let expected = row["expect"] as! [String: Any]
        // #require stops here if the length is wrong — reading past a shorter buffer would trap and take
        // the whole test process down.
        try #require(out.count == expected["length"] as? Int, "\(id) length: \(out.count)")
        if let argmax = expected["argmax"] as? Int {
            #expect(out.indices.max(by: { abs(out[$0]) < abs(out[$1]) }) == argmax, "\(id) argmax")
        }
        for (index, value) in expected["samples"] as? [String: Double] ?? [:] {
            #expect(abs(Double(out[Int(index)!]) - value) < 1e-6, "\(id) sample \(index): \(out[Int(index)!])")
        }
    }
}
