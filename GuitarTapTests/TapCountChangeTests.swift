//
//  TapCountChangeTests.swift
//  GuitarTapTests
//
//  Changing Taps (`numberOfTaps.didSet`): while armed and waiting for the first tap the prompt follows
//  the new count; otherwise it is left alone; and a change never completes a measurement or drops
//  captured taps — there is no "lower the count mid-sequence → finalise with the taps in hand" rule.
//  The Taps stepper is disabled from the first captured tap
//  (`.disabled(currentTapCount > 0 && !isMeasurementComplete)`), so the count cannot change
//  mid-sequence in the app; these pin that the model would not finalise if it did. The shared cases in
//  `tap-count-change.json` (TC1–TC10), the same as Python and the web, through the app's own paths.
//
// @parity test/tap-count-change

import Testing
import Foundation
@testable import GuitarTap

private final class TapCountChangeAnchor {}

@Suite("TapCountChange", .serialized)
@MainActor
struct TapCountChangeTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: TapCountChangeAnchor.self).url(forResource: "tap-count-change", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids() -> [String] {
        (data["cases"] as! [[String: Any]]).map { $0["id"] as! String }
    }

    @Test(arguments: ids())
    func tapCountChange(_ id: String) {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let saved = (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc)
        defer { (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc) = saved }

        let sut = makeStepsAnalyzer()
        var statusBeforeStep = sut.statusMessage
        for step in row["steps"] as! [[String: Any]] {
            statusBeforeStep = sut.statusMessage
            #expect(runAnalyzerStep(step, on: sut), "\(id): unknown step \(step)")
        }

        for (field, want) in row["expect"] as! [String: Any] {
            switch field {
            case "statusMessage":
                #expect(sut.statusMessage == want as? String, "\(id) \(field): \(sut.statusMessage)")
            case "statusUnchangedByLastStep":
                #expect((sut.statusMessage == statusBeforeStep) == want as? Bool,
                        "\(id) \(field): \(statusBeforeStep) → \(sut.statusMessage)")
            case "phase":
                #expect(sut.materialTapPhase.rawValue == want as? String, "\(id) \(field): \(sut.materialTapPhase)")
            case "complete":
                #expect(sut.isMeasurementComplete == want as? Bool, "\(id) \(field)")
            case "detecting":
                #expect(sut.isDetecting == want as? Bool, "\(id) \(field)")
            case "capturedTaps":
                #expect(sut.capturedTaps.count == want as? Int, "\(id) \(field): \(sut.capturedTaps.count)")
            case "numberOfTaps":
                #expect(sut.numberOfTaps == want as? Int, "\(id) \(field)")
            default:
                Issue.record("\(id): unknown field \(field)")
            }
        }
    }
}
