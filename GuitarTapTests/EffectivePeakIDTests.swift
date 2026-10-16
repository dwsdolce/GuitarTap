//
//  EffectivePeakIDTests.swift
//  GuitarTapTests
//
//  The id each material phase's peak is saved and exported under — `effectiveLongitudinalPeakID`,
//  `effectiveCrossPeakID`, `effectiveFlcPeakID`: none until the phase's peak is chosen, then that peak's
//  id. The shared cases in `effective-peak-id.json` (EP1–EP4), the same as Python and the web, through
//  real plate taps.
//
// @parity test/effective-peak-id

import Testing
import Foundation
@testable import GuitarTap

private final class EffectivePeakIDAnchor {}

@Suite("EffectivePeakID", .serialized)
@MainActor
struct EffectivePeakIDTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: EffectivePeakIDAnchor.self).url(forResource: "effective-peak-id", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids() -> [String] {
        (data["cases"] as! [[String: Any]]).map { $0["id"] as! String }
    }

    @Test(arguments: ids())
    func effectivePeakID(_ id: String) {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let saved = (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc)
        defer { (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc) = saved }

        let sut = makeStepsAnalyzer()
        for step in row["steps"] as! [[String: Any]] {
            #expect(runAnalyzerStep(step, on: sut), "\(id): unknown step \(step)")
        }
        let phases: [String: (effective: UUID?, selected: ResonantPeak?)] = [
            "L": (sut.effectiveLongitudinalPeakID, sut.selectedLongitudinalPeak),
            "C": (sut.effectiveCrossPeakID, sut.selectedCrossPeak),
            "FLC": (sut.effectiveFlcPeakID, sut.selectedFlcPeak),
        ]
        for (phase, want) in row["expect"] as! [String: Any] {
            let (effective, selected) = phases[phase]!
            if want as? String == "selected" {
                #expect(effective != nil && effective == selected?.id, "\(id) \(phase): \(String(describing: effective))")
            } else {
                #expect(effective == nil, "\(id) \(phase): \(String(describing: effective))")
            }
        }
    }
}
