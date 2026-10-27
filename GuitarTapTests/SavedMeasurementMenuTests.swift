//
//  SavedMeasurementMenuTests.swift
//  GuitarTapTests
//
//  A saved measurement's menu, against the shared case file `saved-measurement-menu.json`: the same items, words,
//  order and icons as Python's and the web's, on the Mac and on iOS and iPadOS. The SF Symbol is checked here; the
//  Material Design icon there.
//
// @parity test/saved-measurement-menu

import Foundation
import Testing
@testable import GuitarTap

private final class SavedMeasurementMenuTestsAnchor {}

/// A shared menu case file's groups as `platform` shows them: the items with a title for it, no group left empty.
func expectedMenuGroups<Action: RawRepresentable & Hashable>(
    _ groups: [[[String: Any]]], for platform: MenuPlatform, action: Action.Type
) -> [[MenuEntry<Action>]] where Action.RawValue == String {
    let key = platform == .mac ? "mac" : "ios"
    return groups.map { group in
        group.compactMap { item -> MenuEntry<Action>? in
            guard let title = (item["titles"] as! [String: String])[key] else { return nil }
            return MenuEntry(action: Action(rawValue: item["action"] as! String)!, title: title,
                             symbol: item["sfSymbol"] as? String)
        }
    }.filter { !$0.isEmpty }
}

@Suite("SavedMeasurementMenu")
struct SavedMeasurementMenuTests {

    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: SavedMeasurementMenuTestsAnchor.self)
            .url(forResource: "saved-measurement-menu", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    @Test(arguments: MenuPlatform.allCases)
    func savedMeasurementMenu(platform: MenuPlatform) {
        let expected = expectedMenuGroups(Self.data["groups"] as! [[[String: Any]]], for: platform,
                                          action: SavedMeasurementAction.self)
        #expect(SavedMeasurementMenu.groups(for: platform) == expected)
    }
}
