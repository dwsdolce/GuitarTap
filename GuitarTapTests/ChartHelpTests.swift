//
//  ChartHelpTests.swift
//  GuitarTapTests
//
//  The chart's help against the shared case file `chart-help.json`: the same lines, words and groups as Python's
//  and the web's, and on each device the lines that work there.
//
// @parity test/chart-help

import Foundation
import Testing
@testable import GuitarTap

private final class ChartHelpTestsAnchor {}

@Suite("ChartHelp")
struct ChartHelpTests {

    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: ChartHelpTestsAnchor.self).url(forResource: "chart-help", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    @Test func lines() {
        #expect(ChartHelp.title == Self.data["title"] as! String)
        let expected = (Self.data["groups"] as! [[[String: Any]]]).map { group in
            group.map {
                ChartHelpLine(gesture: $0["gesture"] as! String, otherKeys: $0["otherKeys"] as? String,
                              effect: $0["effect"] as! String,
                              needs: Set(($0["needs"] as! [String]).map { ChartHelpLine.Need(rawValue: $0)! }))
            }
        }
        #expect(ChartHelp.groups == expected)
    }

    nonisolated static func deviceIDs() -> [String] { (data["devices"] as! [[String: Any]]).map { $0["id"] as! String } }

    @Test(arguments: deviceIDs())
    func shown(_ id: String) {
        let row = (Self.data["devices"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let device = ChartHelp.Device(pointer: row["pointer"] as! Bool, keyboard: row["keyboard"] as! Bool,
                                      pinch: row["pinch"] as! Bool, appleKeys: row["appleKeys"] as! Bool)
        let shown = ChartHelp.shown(on: device).map { $0.map(\.gesture) }
        #expect(shown == row["shows"] as! [[String]], "\(id)")
    }
}
