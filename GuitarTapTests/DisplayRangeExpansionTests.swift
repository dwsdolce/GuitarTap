//
//  DisplayRangeExpansionTests.swift
//  GuitarTapTests
//
// @parity test/display-range
//
// The chart's display range (DisplayRange) against the shared case file `display-range.json` — the same cases
// the Python and web suites run: widening onto a newly identified plate / brace peak (a guitar's range is the
// user's analysis window and is never widened; a load shows the range it was saved with), when the chart's
// range moves, a zoom or pan step of an axis, and the spectrum points drawn for a range. The analyzer's
// announcing each peak is tested in MaterialPeakAnnouncementTests.

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

    static func axis(_ name: Any?) -> (bounds: ClosedRange<Float>, minSpan: Float) {
        name as? String == "magnitude" ? (DisplayRange.magnitudeBounds, DisplayRange.minMagnitudeSpan)
                                       : (DisplayRange.frequencyBounds, DisplayRange.minFrequencySpan)
    }
    static func near(_ got: (lo: Float, hi: Float)?, _ want: Any?) -> Bool {
        guard let w = want as? [Double] else { return got == nil }
        guard let g = got else { return false }
        return abs(Double(g.lo) - w[0]) <= 1e-3 && abs(Double(g.hi) - w[1]) <= 1e-3
    }

    @Test func zoom() {
        for row in Self.data["zoom"] as! [[String: Any]] {
            let r = row["range"] as! [Double], a = Self.axis(row["axis"])
            let got = DisplayRange.zoomed(Float(r[0]), Float(r[1]), about: Self.f(row["anchor"]!),
                                          scale: Float((row["scale"] as! NSNumber).doubleValue),
                                          within: a.bounds, minSpan: a.minSpan)
            #expect(Self.near(got, row["expect"]), "\(row["id"]!): \(String(describing: got))")
        }
    }

    @Test func pan() {
        for row in Self.data["pan"] as! [[String: Any]] {
            let r = row["range"] as! [Double]
            let got = DisplayRange.panned(Float(r[0]), Float(r[1]), by: Float((row["delta"] as! NSNumber).doubleValue),
                                          within: Self.axis(row["axis"]).bounds)
            #expect(Self.near(got, row["expect"]), "\(row["id"]!): \(got)")
        }
    }

    @Test func drawnIndices() {
        for row in Self.data["drawnIndices"] as! [[String: Any]] {
            let r = row["range"] as! [Double], w = row["expect"] as! [Int]
            let got = DisplayRange.drawnIndices(of: (row["frequencies"] as! [Double]).map { Float($0) },
                                                min: Float(r[0]), max: Float(r[1]))
            #expect(got == w[0]..<w[1], "\(row["id"]!): \(got)")
        }
    }
}
