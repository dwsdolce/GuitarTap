//
//  SavedMeasurementMenuTests.swift
//  GuitarTapTests
//
//  A saved measurement's menu, against the shared case file `saved-measurement-menu.json`: the same items, words,
//  order and icons as Python's and the web's. The SF Symbol is checked here; the Material Design icon there.
//
// @parity test/saved-measurement-menu

import Foundation
import Testing
@testable import GuitarTap

private final class SavedMeasurementMenuTestsAnchor {}

@Suite("SavedMeasurementMenu")
struct SavedMeasurementMenuTests {

    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: SavedMeasurementMenuTestsAnchor.self)
            .url(forResource: "saved-measurement-menu", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    @Test func savedMeasurementMenu() {
        let expected = (Self.data["groups"] as! [[[String: Any]]]).map { group in
            group.map {
                SavedMeasurementMenuEntry(action: SavedMeasurementMenuEntry.Action(rawValue: $0["action"] as! String)!,
                                          title: $0["title"] as! String, symbol: $0["sfSymbol"] as! String,
                                          macOSOnly: $0["macOSOnly"] as? Bool ?? false)
            }
        }
        #expect(SavedMeasurementMenu.groups == expected)
    }
}
