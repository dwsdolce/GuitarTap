//
//  ScenarioStateTraceTests.swift
//  GuitarTapTests
//
//  End-to-end scenarios, pinned by the state they pass through — detecting, paused, complete, the tap
//  count and the taps held — not only where they end: the app's behaviour on screen follows each
//  intermediate state, so two editions reaching the same result by different paths would differ. Every
//  tap is a real capture finish and every wait is audio fed through the analyzer's clock. The shared
//  cases in `scenario-trace.json` (S1–S9), the same as Python and the web.
//
// @parity test/scenario-trace

import Testing
import Foundation
@testable import GuitarTap

private final class ScenarioTraceAnchor {}

@Suite("ScenarioStateTrace", .serialized)
@MainActor
struct ScenarioStateTraceTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: ScenarioTraceAnchor.self).url(forResource: "scenario-trace", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids() -> [String] {
        (data["cases"] as! [[String: Any]]).map { $0["id"] as! String }
    }

    /// The state a `snap` step records, in the case file's form.
    static func snapshot(_ label: String, _ sut: TapToneAnalyzer) -> [String: AnyHashable] {
        ["label": label, "detecting": sut.isDetecting, "paused": sut.isDetectionPaused,
         "complete": sut.isMeasurementComplete, "tapCount": sut.currentTapCount,
         "capturedTaps": sut.capturedTaps.count]
    }

    @Test(arguments: ids())
    func scenario(_ id: String) {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let savedType = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeStepsAnalyzer()
        var trace: [[String: AnyHashable]] = []
        for step in row["steps"] as! [[String: Any]] {
            if let label = step["snap"] as? String {
                trace.append(Self.snapshot(label, sut))
            } else {
                #expect(runAnalyzerStep(step, on: sut), "\(id): unknown step \(step)")
            }
        }

        let expected = ((row["expect"] as! [String: Any])["trace"] as! [[String: Any]]).map { r in
            r.mapValues { $0 as! AnyHashable }
        }
        #expect(trace == expected, "\(id) trace:\n  got: \(trace)\n  exp: \(expected)")
    }
}
