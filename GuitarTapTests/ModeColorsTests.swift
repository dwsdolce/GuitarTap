//
//  ModeColorsTests.swift
//  GuitarTapTests
//
//  Each guitar mode's colour role against the shared case file `theme.json` — the same cases the Python and web
//  suites run — and that the modes, and a freeform label, are told apart in each scheme.
//
// @parity test/mode-colors

import Foundation
import Testing
@testable import GuitarTap

private final class ModeColorsTestsAnchor {}

@Suite("ModeColors")
struct ModeColorsTests {

    static let modeRoles: [[String]] = {
        let url = Bundle(for: ModeColorsTestsAnchor.self).url(forResource: "theme", withExtension: "json")!
        let data = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return data["modeRoles"] as! [[String]]
    }()

    @Test func everyModeAndItsRole() {
        for row in Self.modeRoles {
            let mode = GuitarMode.currentCases.first { "\($0)" == row[0] }!
            #expect(Palette.role(mode).rawValue == row[1], "\(row[0])")
        }
        #expect(Self.modeRoles.count == GuitarMode.currentCases.count)
    }

    /// Seven modes and a freeform label are eight colours, told apart in each scheme.
    @Test func everyModeHasItsOwnColourInEachScheme() {
        let roles = GuitarMode.currentCases.map { Palette.role($0) } + [.modeUserDefined]
        #expect(Set(roles.map { Palette.pair($0).light }).count == roles.count)
        #expect(Set(roles.map { Palette.pair($0).dark }).count == roles.count)
    }
}
