//
//  QualityColorsTests.swift
//  GuitarTapTests
//
//  The wood-quality grades — label against the shared case file `quality-colors.json`, colour against the
//  grade's `wood.*` role in `theme.json` — the same cases the Python and web suites run; and what the data cannot
//  express here: that the drawn colour is built from the pinned hex rather than a system colour the OS resolves.
//
// @parity test/quality-colors

import Foundation
import SwiftUI
import Testing
@testable import GuitarTap

private final class QualityColorsTestsAnchor {}

@Suite("QualityColors")
struct QualityColorsTests {

    static let grades: [[String]] = {
        let url = Bundle(for: QualityColorsTestsAnchor.self).url(forResource: "quality-colors", withExtension: "json")!
        let data = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return data["grades"] as! [[String]]
    }()

    static func grade(_ name: String) -> WoodQuality { WoodQuality.allCases.first { "\($0)" == name }! }

    @Test func labelAndHex() {
        for row in Self.grades {
            let q = Self.grade(row[0])
            #expect(q.rawValue == row[1], "\(row[0])")
            #expect(q.hex == Palette.pair(Palette.Role(rawValue: "wood." + row[0])!).light, "\(row[0])")
        }
    }

    /// The file names every grade, and five grades are five distinguishable colours.
    @Test func everyGradeHasItsOwnColour() {
        #expect(Self.grades.count == WoodQuality.allCases.count)
        #expect(Set(WoodQuality.allCases.map(\.hex)).count == WoodQuality.allCases.count)
    }

    // `color` is derived from `hex`, so the drawn colour cannot diverge from the pinned value.
    @Test func colorIsBuiltFromTheHex() {
        for q in WoodQuality.allCases {
            #expect(q.color == Color(sRGBHex: q.hex), "\(q.rawValue): color should be built from hex \(q.hex)")
        }
    }

    // A colour built from hex must not be a semantic system colour — the regression an `== .green`
    // assertion cannot see.
    @Test func coloursAreAbsolute_notSemantic() {
        #expect(WoodQuality.good.color != .blue, "Good must be an absolute #007AFF, not the OS's .blue, which moved in macOS 26")
        #expect(WoodQuality.fair.color != .orange, "Fair must be an absolute #FF9500, not the OS's .orange")
    }
}
