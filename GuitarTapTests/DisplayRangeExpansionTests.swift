//
//  DisplayRangeExpansionTests.swift
//  GuitarTapTests
//
// @parity test/display-range
//
// The chart's display range (DisplayRange) against the shared case file `display-range.json` — the same cases
// the Python and web suites run: widening onto a newly identified plate / brace peak (a guitar's range is the
// user's analysis window and is never widened; a load shows the range it was saved with), and when the
// chart's range moves. The analyzer's announcing each peak is tested in MaterialPeakAnnouncementTests.

import Foundation
import Testing
@testable import GuitarTap

private final class DisplayRangeExpansionTestsAnchor {}

@Suite("DisplayRangeExpansion")
struct DisplayRangeExpansionTests {

    static let data: [String: Any] = {
        let url = Bundle(for: DisplayRangeExpansionTestsAnchor.self).url(forResource: "display-range", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    static func f(_ v: Any) -> Float { Float(v as! Double) }
    static func range(_ v: Any?) -> DisplayRange.ChartRange? {
        guard let a = v as? [Double] else { return nil }
        return DisplayRange.ChartRange(minFreq: Float(a[0]), maxFreq: Float(a[1]), minDB: Float(a[2]), maxDB: Float(a[3]))
    }
    static func type(_ name: String) -> MeasurementType { MeasurementType.allCases.first { "\($0)" == name }! }

    @Test func expandedToInclude() {
        for row in Self.data["expandedToInclude"] as! [[Any]] {
            let r = DisplayRange.expanded(toInclude: Self.f(row[0]), min: Self.f(row[1]), max: Self.f(row[2]))
            #expect(r.min == Self.f(row[3]) && r.max == Self.f(row[4]), "\(row)")
        }
    }

    @Test func widenedOnto() {
        for row in Self.data["widenedOnto"] as! [[Any]] {
            let r = DisplayRange.widened(onto: Self.f(row[0]), for: Self.type(row[1] as! String), fromLoad: row[2] as! Bool,
                                         min: Self.f(row[3]), max: Self.f(row[4]))
            #expect(r.min == Self.f(row[5]) && r.max == Self.f(row[6]), "\(row)")
        }
    }

    @Test func onSettingsDone() {
        for row in Self.data["onSettingsDone"] as! [[String: Any]] {
            let r = DisplayRange.onSettingsDone(saved: Self.range(row["saved"])!, previouslySaved: Self.range(row["previouslySaved"])!,
                                                typeChanged: row["typeChanged"] as! Bool)
            #expect(r == Self.range(row["expect"]), "\(row)")
        }
    }

    @Test func onNewMeasurement() {
        for row in Self.data["onNewMeasurement"] as! [[String: Any]] {
            let r = DisplayRange.onNewMeasurement(current: Self.range(row["current"])!, loaded: Self.range(row["loaded"]),
                                                  saved: Self.range(row["saved"])!)
            #expect(r == Self.range(row["expect"]), "\(row)")
        }
    }

    @Test func loadedAfterWidening() {
        for row in Self.data["loadedAfterWidening"] as! [[String: Any]] {
            let r = DisplayRange.loadedAfterWidening(loaded: Self.range(row["loaded"])!, before: Self.range(row["before"])!,
                                                     after: Self.range(row["after"])!)
            #expect(r == Self.range(row["expect"]), "\(row)")
        }
    }
}
