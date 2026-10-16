//
//  StatusMessageTests.swift
//  GuitarTapTests
//
//  The status line's words, each reached through the app's own path. The shared cases in
//  `status-message.json` (SM1–SM24), the same as Python and the web.
//
// @parity test/status-message

import Testing
import Foundation
import Combine
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

    static func check(_ fields: [String: Any], _ sut: TapToneAnalyzer, before: String, writes: Int, _ id: String) {
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
            case "statusWrites": #expect(writes == want as? Int, "\(id) \(field): \(writes)")
            default: Issue.record("\(id): unknown field \(field)")
            }
        }
    }

    @Test(arguments: ids())
    func status(_ id: String) async throws {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let saved = (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc)
        defer { (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc) = saved }

        let sut = makeStepsAnalyzer()
        var before = sut.statusMessage
        var writes = 0
        var counting: AnyCancellable?
        defer { counting?.cancel() }
        for step in row["steps"] as! [[String: Any]] {
            if let fields = step["check"] as? [String: Any] {
                Self.check(fields, sut, before: before, writes: writes, id)
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
            } else if step["drainMainQueue"] as? Bool == true {
                // Each pass waits for everything queued on the main thread before it.
                for _ in 0..<10 {
                    await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
                }
            } else if step["countStatusWrites"] as? Bool == true {
                counting = sut.$statusMessage.dropFirst().sink { _ in writes += 1 }
            } else {
                #expect(runAnalyzerStep(step, on: sut), "\(id): unknown step \(step)")
            }
        }
        Self.check(row["expect"] as! [String: Any], sut, before: before, writes: writes, id)
    }
}
