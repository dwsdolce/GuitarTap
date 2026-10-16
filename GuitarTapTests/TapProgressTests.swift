//
//  TapProgressTests.swift
//  GuitarTapTests
//
//  The values the status bar's progress bar shows (`ProgressView(value: tap.tapProgress)`):
//
//      totalPlateTaps = numberOfTaps × (brace ? 1 : measureFlc ? 3 : 2)
//      tapProgress    = min(1, currentTapCount / (guitar ? numberOfTaps : totalPlateTaps)), stored at
//                       each capture, so a later Taps change cannot rewrite a finished measurement's bar
//      currentTapCount (material) is CUMULATIVE across L → C → FLC, and rebases to the earlier phases'
//                       taps on Redo
//
//  The cumulative count is the rule a phase boundary can break while the equations still hold, so the
//  cases drive real captures across Accepts. The shared cases in `tap-progress.json` (TP1–TP15), the
//  same as Python and the web.
//
// @parity test/tap-progress

import Testing
import Foundation
@testable import GuitarTap

private final class TapProgressAnchor {}

@Suite("TapProgress", .serialized)
@MainActor
struct TapProgressTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: TapProgressAnchor.self).url(forResource: "tap-progress", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids() -> [String] {
        (data["cases"] as! [[String: Any]]).map { $0["id"] as! String }
    }

    /// The measurement a `load` step names: an inline file of the case table, or a fixture.
    static func measurement(_ name: String) throws -> TapToneMeasurement {
        let fileData: Data
        if let inline = (data["files"] as? [String: Any])?[name] {
            fileData = try JSONSerialization.data(withJSONObject: inline)
        } else {
            let stem = (name as NSString).deletingPathExtension
            let url = try #require(Bundle(for: TapProgressAnchor.self).url(forResource: stem, withExtension: "guitartap"))
            fileData = try Data(contentsOf: url)
        }
        return try #require(try TapToneAnalyzer.decodeMeasurements(fileData).first)
    }

    /// Asserts the fields an expectation names.
    static func check(_ fields: [String: Any], _ sut: TapToneAnalyzer, _ id: String) {
        for (field, want) in fields {
            switch field {
            case "totalPlateTaps":
                #expect(sut.totalPlateTaps == want as? Int, "\(id) \(field)")
            case "tapProgress":
                let wanted = (want as! NSNumber).doubleValue
                #expect(abs(Double(sut.tapProgress) - wanted) < 0.0001, "\(id) \(field): \(sut.tapProgress)")
            case "tapCount":
                #expect(sut.currentTapCount == want as? Int, "\(id) \(field): \(sut.currentTapCount)")
            case "phase":
                #expect(sut.materialTapPhase.rawValue == want as? String, "\(id) \(field): \(sut.materialTapPhase)")
            case "complete":
                #expect(sut.isMeasurementComplete == want as? Bool, "\(id) \(field)")
            case "detecting":
                #expect(sut.isDetecting == want as? Bool, "\(id) \(field)")
            default:
                Issue.record("\(id): unknown field \(field)")
            }
        }
    }

    @Test(arguments: ids())
    func tapProgress(_ id: String) throws {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let saved = (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc)
        defer { (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc) = saved }

        let sut = makeStepsAnalyzer()
        for step in row["steps"] as! [[String: Any]] {
            if let fields = step["check"] as? [String: Any] {
                Self.check(fields, sut, id)
            } else if let name = step["load"] as? String {
                sut.loadMeasurement(try Self.measurement(name))
            } else {
                #expect(runAnalyzerStep(step, on: sut), "\(id): unknown step \(step)")
            }
        }
        Self.check(row["expect"] as! [String: Any], sut, id)
    }
}
