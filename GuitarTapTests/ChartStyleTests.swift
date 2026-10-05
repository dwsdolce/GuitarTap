//
//  ChartStyleTests.swift
//  GuitarTapTests
//
//  The chart's line and point styles, on screen and in the exported image, against the shared case file
//  `chart-style.json` — the same cases the Python and web suites run.
//
// @parity test/chart-style

import CoreGraphics
import Foundation
import Testing
@testable import GuitarTap

private final class ChartStyleTestsAnchor {}

@Suite("ChartStyle")
struct ChartStyleTests {

    static let data: [String: [String: Any]] = {
        let url = Bundle(for: ChartStyleTestsAnchor.self).url(forResource: "chart-style", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }().filter { $0.value is [String: Any] }.mapValues { $0 as! [String: Any] }

    static func lines(_ d: [String: Any]) -> ChartStyle.Lines {
        func n(_ k: String) -> CGFloat { CGFloat((d[k] as! NSNumber).doubleValue) }
        func dash(_ k: String) -> [CGFloat] { (d[k] as! [NSNumber]).map { CGFloat($0.doubleValue) } }
        return ChartStyle.Lines(
            spectrumWidth: n("spectrumWidth"), overlayWidth: n("overlayWidth"), gridWidth: n("gridWidth"),
            modeBoundaryWidth: n("modeBoundaryWidth"), modeBoundaryDash: dash("modeBoundaryDash"),
            modeBoundaryOpacity: Double(n("modeBoundaryOpacity")),
            peakMinWidth: n("peakMinWidth"), peakMinDash: dash("peakMinDash"),
            peakMinOpacity: Double(n("peakMinOpacity")),
            crosshairWidth: n("crosshairWidth"), crosshairDash: dash("crosshairDash"),
            leaderWidth: n("leaderWidth"), leaderDash: dash("leaderDash"), leaderOpacity: Double(n("leaderOpacity")),
            labelBorderWidth: n("labelBorderWidth"),
            dotArea: n("dotArea"), highlightedDotArea: n("highlightedDotArea"),
            magnitudeStride: (d["magnitudeStride"] as? NSNumber)?.doubleValue
        )
    }

    @Test func screen() { #expect(ChartStyle.screen == Self.lines(Self.data["screen"]!)) }

    @Test func export() { #expect(ChartStyle.export == Self.lines(Self.data["export"]!)) }
}
