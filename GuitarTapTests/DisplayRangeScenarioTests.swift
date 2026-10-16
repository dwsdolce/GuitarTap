//
//  DisplayRangeScenarioTests.swift
//  GuitarTapTests
//
//  The analyzer's side of the chart's range: the range a load publishes for the chart (a measurement's
//  snapshot range exactly, or the saved range when it has none) without moving the analysis range, and
//  the announcements of the three material peaks the chart widens onto. The 'scenarios' of the shared
//  `display-range.json` (DR1–DR6; DR7 is the web's own), the same as Python and the web. The widening
//  decision itself is DisplayRangeExpansionTests.
//
// @parity test/display-range

import Combine
import Foundation
import Testing
@testable import GuitarTap

private final class DisplayRangeScenarioAnchor {}

@Suite("DisplayRangeScenarios", .serialized)
@MainActor
struct DisplayRangeScenarioTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: DisplayRangeScenarioAnchor.self).url(forResource: "display-range", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    /// The scenarios for Swift: all but those marked for the web alone.
    nonisolated static func ids() -> [String] {
        (data["scenarios"] as! [[String: Any]]).filter { $0["only"] as? String != "web" }.map { $0["id"] as! String }
    }

    /// Each phase's peak frequencies, as announced after `listen`.
    final class Announcements {
        var byPhase: [String: [Double?]] = ["L": [], "C": [], "FLC": []]
        var bag: Set<AnyCancellable> = []
        init(_ sut: TapToneAnalyzer) {
            sut.$selectedLongitudinalPeak.dropFirst().sink { [unowned self] in byPhase["L"]!.append($0.map { Double($0.frequency) }) }.store(in: &bag)
            sut.$selectedCrossPeak.dropFirst().sink { [unowned self] in byPhase["C"]!.append($0.map { Double($0.frequency) }) }.store(in: &bag)
            sut.$selectedFlcPeak.dropFirst().sink { [unowned self] in byPhase["FLC"]!.append($0.map { Double($0.frequency) }) }.store(in: &bag)
        }
    }

    static func check(_ fields: [String: Any], _ sut: TapToneAnalyzer, _ heard: Announcements?, _ id: String) {
        for (field, want) in fields {
            switch field {
            case "loadedRange":
                let r = sut.loadedAxisRange
                let got = r.map { [Double($0.minFreq), Double($0.maxFreq), Double($0.minDB), Double($0.maxDB)] }
                let wanted: [Double]
                if want as? String == "saved" {
                    wanted = [Double(TapDisplaySettings.minFrequency), Double(TapDisplaySettings.maxFrequency),
                              Double(TapDisplaySettings.minMagnitude), Double(TapDisplaySettings.maxMagnitude)]
                } else {
                    wanted = (want as! [NSNumber]).map(\.doubleValue)
                }
                #expect(got.map { zip($0, wanted).allSatisfy { abs($0 - $1) < 1e-4 } } == true, "\(id) \(field): \(String(describing: got))")
            case "analysisRange":
                let wanted = (want as! [NSNumber]).map(\.doubleValue)
                #expect([Double(sut.minFrequency), Double(sut.maxFrequency)] == wanted, "\(id) \(field)")
            case "lastAnnounced":
                for (phase, hz) in want as! [String: NSNumber] {
                    let last = heard?.byPhase[phase]?.last ?? nil
                    #expect(last.map { abs($0 - hz.doubleValue) < 1e-3 } == true, "\(id) \(field) \(phase): \(String(describing: last))")
                }
            case "announced":
                for (phase, list) in want as! [String: [Any]] {
                    let wanted = list.map { ($0 as? NSNumber)?.doubleValue }
                    #expect(heard?.byPhase[phase] == wanted, "\(id) \(field) \(phase): \(String(describing: heard?.byPhase[phase]))")
                }
            case "peaksFromLoad":
                #expect(sut.materialPeaksFromLoad == want as? Bool, "\(id) \(field)")
            default:
                Issue.record("\(id): unknown field \(field)")
            }
        }
    }

    @Test(arguments: ids())
    func scenario(_ id: String) throws {
        let row = (Self.data["scenarios"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let saved = (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc)
        defer { (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc) = saved }

        let sut = makeStepsAnalyzer()
        var heard: Announcements?
        for step in row["steps"] as! [[String: Any]] {
            if let name = step["load"] as? String {
                let file = (Self.data["files"] as! [String: Any])[name]!
                sut.loadMeasurement(try #require(try TapToneAnalyzer.decodeMeasurements(
                    JSONSerialization.data(withJSONObject: file)).first))
            } else if step["listen"] as? Bool == true {
                heard = Announcements(sut)
            } else if let fields = step["check"] as? [String: Any] {
                Self.check(fields, sut, heard, id)
            } else {
                #expect(runAnalyzerStep(step, on: sut), "\(id): unknown step \(step)")
            }
        }
        Self.check(row["expect"] as! [String: Any], sut, heard, id)
    }
}
