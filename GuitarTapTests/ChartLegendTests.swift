//
//  ChartLegendTests.swift
//  GuitarTapTests
//
//  The chart legend's lines against the shared case file `chart-legend.json`: the same entries on the same lines as
//  Python's and the web's for the same widths.
//
// @parity test/chart-legend

import CoreGraphics
import Foundation
import Testing
@testable import GuitarTap

private final class ChartLegendTestsAnchor {}

@Suite("ChartLegend")
struct ChartLegendTests {

    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: ChartLegendTestsAnchor.self).url(forResource: "chart-legend", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    static func ids() -> [String] { (data["lines"] as! [[Any]]).map { $0[0] as! String } }

    @Test(arguments: ids())
    func lines(_ id: String) {
        let row = (Self.data["lines"] as! [[Any]]).first { $0[0] as! String == id }!
        let widths = (row[1] as! [Double]).map { CGSize(width: $0, height: 1) }
        let layout = TrailingFlowLayout(spacing: CGFloat(row[3] as! Double), lineSpacing: 0)
        #expect(layout.lines(widths, width: CGFloat(row[2] as! Double)) == row[4] as! [[Int]], "\(id)")
    }
}
