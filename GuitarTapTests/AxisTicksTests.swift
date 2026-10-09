//
//  AxisTicksTests.swift
//  GuitarTapTests
//
//  The chart's axis ticks — its grid lines — against the shared case file `axis-ticks.json`: the frequency ticks
//  and their labels (the same on screen and in the export), and the magnitude tick spacing. The same cases the
//  Python and web suites run.
//
// @parity test/axis-ticks

import Foundation
import Testing
@testable import GuitarTap

private final class AxisTicksTestsAnchor {}

@Suite("AxisTicks")
struct AxisTicksTests {

    static let data: [String: Any] = {
        let url = Bundle(for: AxisTicksTestsAnchor.self).url(forResource: "axis-ticks", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    @Test func frequencyTicksAndLabels() {
        for row in Self.data["frequency"] as! [[Any]] {
            let range = row[0] as! [Double]
            let ticks = AxisTickGenerator.generateTicks(min: range[0], max: range[1], maxTicks: 8)
            let expected = row[1] as! [Double]
            #expect(ticks.count == expected.count, "\(range)")
            for (t, e) in zip(ticks, expected) { #expect(abs(t - e) <= 1e-9 * max(1, abs(e)), "\(range)") }
            let visible = ticks.filter { $0 >= range[0] && $0 <= range[1] }
            let labels = AxisTickGenerator.formatTickLabels(visible)
            #expect(visible.map { labels[$0]! } == row[2] as! [String], "\(range)")
        }
    }

    @Test func magnitudeStride() {
        for row in Self.data["magnitude"] as! [[Any]] {
            let range = row[0] as! [Double]
            #expect(AxisTickGenerator.magnitudeStride(range: range[1] - range[0]) == row[1] as! Double, "\(range)")
        }
    }
}
