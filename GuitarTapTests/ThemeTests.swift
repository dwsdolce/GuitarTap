//
//  ThemeTests.swift
//  GuitarTapTests
//
//  The palette against the shared case file `theme.json` — every colour role with its light and dark value, and
//  the opacities applied to other roles — the same cases the Python and web suites run; and, what the data cannot
//  express here, that each role's colour resolves to its light value in the light scheme and its dark value in the
//  dark scheme.
//
// @parity test/theme

import Foundation
import SwiftUI
import Testing
@testable import GuitarTap

private final class ThemeTestsAnchor {}

@Suite("Theme")
struct ThemeTests {

    static let data: [String: Any] = {
        let url = Bundle(for: ThemeTestsAnchor.self).url(forResource: "theme", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    static var roles: [[String]] { data["roles"] as! [[String]] }

    @Test func everyRoleAndItsValues() {
        for row in Self.roles {
            guard let role = Palette.Role(rawValue: row[0]) else {
                Issue.record("no role \(row[0])")
                continue
            }
            #expect(Palette.pair(role) == Palette.Pair(light: row[1], dark: row[2]), "\(row[0])")
        }
        #expect(Palette.Role.allCases.map(\.rawValue) == Self.roles.map { $0[0] })
    }

    @Test func opacities() {
        let rows = Self.data["opacities"] as! [[Any]]
        for row in rows {
            let opacity = Palette.Opacity(rawValue: row[0] as! String)!
            #expect(Palette.opacities[opacity]!.light == row[1] as! Double, "\(row[0])")
            #expect(Palette.opacities[opacity]!.dark == row[2] as! Double, "\(row[0])")
        }
        #expect(Palette.Opacity.allCases.map(\.rawValue) == rows.map { $0[0] as! String })
    }

    /// Each role's colour, read back through SwiftUI in each scheme (its hex carries an alpha byte).
    @Test func colorsResolveByScheme() {
        var light = EnvironmentValues()
        light.colorScheme = .light
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        func rgba(_ hex: String) -> String { hex.count == 9 ? hex : hex + "FF" }
        for role in Palette.Role.allCases {
            let color = Palette.color(role)
            #expect(color.resolve(in: light).description == rgba(Palette.pair(role).light), "\(role.rawValue)")
            #expect(color.resolve(in: dark).description == rgba(Palette.pair(role).dark), "\(role.rawValue)")
        }
    }

    /// A role at an opacity keeps its colour and scales its alpha by the scheme's opacity.
    @Test func colorAtOpacity() {
        var light = EnvironmentValues()
        light.colorScheme = .light
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        let tint = Palette.color(.modeAir, opacity: .peakRowTint)
        #expect(abs(Double(tint.resolve(in: light).opacity) - 0.10) < 0.001)
        #expect(abs(Double(tint.resolve(in: dark).opacity) - 0.20) < 0.001)
        #expect(tint.resolve(in: light).description.prefix(7) == "#00B0DC")
        #expect(tint.resolve(in: dark).description.prefix(7) == "#64D2FF")
    }
}
