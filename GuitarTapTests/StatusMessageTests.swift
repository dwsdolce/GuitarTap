//
//  StatusMessageTests.swift
//  GuitarTapTests
//
//  The status line's words, each reached through the app's own path. The shared cases in
//  `status-message.json` (SM1–SM23), the same as Python and the web. Below them, the case that the
//  status settles and stays settled, which needs a quiet period of real time.
//
// @parity test/status-message

import Testing
import Foundation
@testable import GuitarTap

private final class StatusMessageAnchor {}

@Suite("StatusMessage", .serialized)
@MainActor
struct StatusMessageTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: StatusMessageAnchor.self).url(forResource: "status-message", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids() -> [String] {
        (data["cases"] as! [[String: Any]]).map { $0["id"] as! String }
    }

    static func check(_ fields: [String: Any], _ sut: TapToneAnalyzer, before: String, _ id: String) {
        let status = sut.statusMessage
        for (field, want) in fields {
            switch field {
            case "statusMessage": #expect(status == want as? String, "\(id) \(field): \(status)")
            case "statusPrefix": #expect(status.hasPrefix(want as! String), "\(id) \(field): \(status)")
            case "statusSuffix": #expect(status.hasSuffix(want as! String), "\(id) \(field): \(status)")
            case "statusContains": #expect(status.contains(want as! String), "\(id) \(field): \(status)")
            case "statusUnchangedByLastStep": #expect((status == before) == want as? Bool, "\(id) \(field): \(before) → \(status)")
            case "detecting": #expect(sut.isDetecting == want as? Bool, "\(id) \(field)")
            case "tapCount": #expect(sut.currentTapCount == want as? Int, "\(id) \(field)")
            default: Issue.record("\(id): unknown field \(field)")
            }
        }
    }

    @Test(arguments: ids())
    func status(_ id: String) throws {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let saved = (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc)
        defer { (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc) = saved }

        let sut = makeStepsAnalyzer()
        var before = sut.statusMessage
        for step in row["steps"] as! [[String: Any]] {
            if let fields = step["check"] as? [String: Any] {
                Self.check(fields, sut, before: before, id)
                continue
            }
            before = sut.statusMessage
            if let clipping = step["clipping"] as? Bool {
                sut.fftAnalyzer.level.isClipping = clipping
            } else if step["deviceChange"] as? Bool == true {
                sut.handleRouteChangeRestart()
            } else if let name = step["load"] as? String {
                let file = (Self.data["files"] as! [String: Any])[name]!
                sut.loadMeasurement(try #require(try TapToneAnalyzer.decodeMeasurements(
                    JSONSerialization.data(withJSONObject: file)).first))
            } else if step["playingFile"] as? Bool == true {
                sut.fftAnalyzer.isPlayingFile = true
            } else {
                #expect(runAnalyzerStep(step, on: sut), "\(id): unknown step \(step)")
            }
        }
        Self.check(row["expect"] as! [String: Any], sut, before: before, id)
    }

    // ── two writes in one pass settle on the second ─────────────────────────
    // Arming straight after the analyzer is made writes the armed prompt in the same pass of the main
    // queue as the initial status. The status must settle on the prompt and stay there — it once
    // alternated between the two, hundreds of thousands of times a second, for good.
    @Test func twoWritesInOnePass_settleOnTheSecondAndStay() async throws {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        TapDisplaySettings.measurementType = .generic
        let sut = TapToneAnalyzer.forTesting()
        sut.numberOfTaps = 1
        sut.startTapSequence(skipWarmup: true)
        #expect(sut.statusMessage == "Tap the guitar...")

        var writes = 0
        let token = sut.$statusMessage.dropFirst().sink { _ in writes += 1 }
        defer { token.cancel() }
        try await Task.sleep(for: .milliseconds(50))

        #expect(sut.statusMessage == "Tap the guitar...")
        #expect(writes == 0, "REGRESSION: the status kept changing with nothing happening — \(writes) writes in 50 ms")
    }
}
