//
//  QualityColorsTests.swift
//  GuitarTapTests
//
//  The wood-quality grades — label against the shared case file `quality-colors.json`, and each grade's colour
//  role, `wood.<grade>` in `theme.json` — the same cases the Python and web suites run.
//
// @parity test/quality-colors

import Foundation
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

    @Test func labelAndRole() {
        for row in Self.grades {
            let q = Self.grade(row[0])
            #expect(q.rawValue == row[1], "\(row[0])")
            #expect(Palette.role(q).rawValue == "wood." + row[0], "\(row[0])")
        }
        #expect(Self.grades.count == WoodQuality.allCases.count)
    }

    /// Five grades are five colours, told apart in each scheme.
    @Test func everyGradeHasItsOwnColourInEachScheme() {
        let roles = WoodQuality.allCases.map { Palette.role($0) }
        #expect(Set(roles.map { Palette.pair($0).light }).count == roles.count)
        #expect(Set(roles.map { Palette.pair($0).dark }).count == roles.count)
    }
}
