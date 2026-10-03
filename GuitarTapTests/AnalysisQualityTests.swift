//
//  AnalysisQualityTests.swift
//  GuitarTapTests
//
//  The guitar tap-tone quality helpers against the shared case file `analysis-quality.json` — the same cases
//  the Python and web suites run.
//
// @parity test/analysis-quality

import Foundation
import SwiftUI
import Testing
@testable import GuitarTap

private final class AnalysisQualityTestsAnchor {}

@Suite("AnalysisQuality")
struct AnalysisQualityTests {

    static let data: [String: Any] = {
        let url = Bundle(for: AnalysisQualityTestsAnchor.self).url(forResource: "analysis-quality", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    static let palette: [String: Color] = [
        "gray": Palette.gray, "orange": Palette.orange, "yellow": Palette.yellow,
        "green": Palette.green, "blue": Palette.blue, "red": Palette.red,
    ]
    static func type(_ name: String) -> GuitarType { GuitarType.allCases.first { "\($0)" == name }! }
    static func number(_ v: Any) -> Float { (v as? String) == "NaN" ? .nan : Float(v as! Double) }

    @Test func decayThresholds() {
        for row in Self.data["decayThresholds"] as! [[Any]] {
            let t = Self.type(row[0] as! String).decayThresholds
            #expect([t.veryShort, t.short, t.moderate, t.good] == row.dropFirst().map { Float($0 as! Double) }, "\(row[0])")
        }
    }

    @Test func decayLabelAndColor() {
        for row in Self.data["decayLabel"] as! [[Any]] {
            #expect(Self.number(row[1]).decayQuality(for: Self.type(row[0] as! String)) == (row[2] as! String), "\(row[0]) \(row[1])")
        }
        for row in Self.data["decayColor"] as! [[Any]] {
            #expect(Self.number(row[1]).decayQualityColor(for: Self.type(row[0] as! String)) == Self.palette[row[2] as! String]!,
                    "\(row[0]) \(row[1])")
        }
    }

    @Test func ratioLabelAndColor() {
        for row in Self.data["ratioLabel"] as! [[Any]] {
            #expect(Self.number(row[0]).tapToneRatioQuality == (row[1] as! String), "\(row[0])")
        }
        for row in Self.data["ratioColor"] as! [[Any]] {
            #expect(Self.number(row[0]).tapToneRatioQualityColor == Self.palette[row[1] as! String]!, "\(row[0])")
        }
    }

    @Test func outsideEveryBand() {
        let o = Self.data["outsideEveryBand"] as! [String: Any]
        let type = Self.type(o["guitarType"] as! String)
        let color = Self.palette[o["color"] as! String]!
        for v in o["values"] as! [Any] {
            let value = Self.number(v)
            #expect(value.decayQuality(for: type) == (o["label"] as! String), "\(v)")
            #expect(value.decayQualityColor(for: type) == color, "\(v)")
            #expect(value.tapToneRatioQuality == (o["label"] as! String), "\(v)")
            #expect(value.tapToneRatioQualityColor == color, "\(v)")
        }
    }

    /// The palette's light and dark values, read back through SwiftUI (its hex carries an alpha byte).
    @Test func palette() {
        var light = EnvironmentValues()
        light.colorScheme = .light
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        for row in Self.data["palette"] as! [[String]] {
            let color = Self.palette[row[0]]!
            #expect(color.resolve(in: light).description == row[1] + "FF", "\(row[0])")
            #expect(color.resolve(in: dark).description == row[2] + "FF", "\(row[0])")
        }
        #expect(Self.palette.count == (Self.data["palette"] as! [[String]]).count)
    }
}
