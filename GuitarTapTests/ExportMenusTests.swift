//
//  ExportMenusTests.swift
//  GuitarTapTests
//
//  Saved Measurements' library menu and Analysis Results' menu, against the shared case file `export-menus.json`:
//  each button's word and icon, and its items, words, order and icons, on the Mac and on iOS and iPadOS — the same
//  as Python's and the web's.
//
// @parity test/export-menus

import Foundation
import Testing
@testable import GuitarTap

private final class ExportMenusTestsAnchor {}

@Suite("ExportMenus")
struct ExportMenusTests {

    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: ExportMenusTestsAnchor.self).url(forResource: "export-menus", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    private func check<Action: RawRepresentable & Hashable>(_ menu: ExportMenu<Action>, _ key: String,
                                                            _ platform: MenuPlatform)
    where Action.RawValue == String {
        let spec = Self.data[key] as! [String: Any]
        #expect(menu.button(for: platform) == (spec["button"] as! [String: String])[platform == .mac ? "mac" : "ios"])
        #expect(menu.symbol == spec["sfSymbol"] as? String)
        #expect(menu.entries(for: platform)
                == expectedMenuGroups(spec["groups"] as! [[[String: Any]]], for: platform, action: Action.self))
    }

    @Test(arguments: MenuPlatform.allCases)
    func panelMenu(platform: MenuPlatform) {
        check(ExportMenus.panel, "panel", platform)
    }

    @Test(arguments: MenuPlatform.allCases)
    func analysisResultsMenu(platform: MenuPlatform) {
        check(ExportMenus.analysisResults, "analysisResults", platform)
    }
}
