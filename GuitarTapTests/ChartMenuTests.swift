//
//  ChartMenuTests.swift
//  GuitarTapTests
//
//  The chart's menu and a peak label's, against the shared case file `chart-menu.json`: the same items, words,
//  order and icons as Python's and the web's. The SF Symbol is checked here; the Material Design icon there.
//
// @parity test/chart-menu

import Foundation
import Testing
@testable import GuitarTap

private final class ChartMenuTestsAnchor {}

@Suite("ChartMenu")
struct ChartMenuTests {

    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: ChartMenuTestsAnchor.self).url(forResource: "chart-menu", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    private static func entries(_ cases: [[String: Any]]) -> [ChartMenuEntry] {
        cases.map {
            ChartMenuEntry(action: ChartMenuEntry.Action(rawValue: $0["action"] as! String)!,
                           title: $0["title"] as! String, symbol: $0["sfSymbol"] as! String)
        }
    }

    @Test func chartMenu() {
        let expected = (Self.data["groups"] as! [[[String: Any]]]).map(Self.entries)
        #expect(ChartMenu.groups == expected)
    }

    @Test func comparisonMenu() {
        let expected = (Self.data["comparisonGroups"] as! [[[String: Any]]]).map(Self.entries)
        #expect(ChartMenu.comparisonGroups == expected)
    }

    @Test func labelMenu() {
        #expect(ChartMenu.labelMenu == Self.entries(Self.data["labelMenu"] as! [[String: Any]]))
    }
}
