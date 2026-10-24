//
//  SavedMeasurementsOrderTests.swift
//  GuitarTapTests
//
//  The order Saved Measurements shows the library in — `SavedMeasurementsOrder.shown` — against the shared case
//  file `saved-measurements-order.json`, the same cases the Python and web suites run.
//
// @parity test/saved-measurements-order

import Foundation
import Testing
@testable import GuitarTap

private final class SavedMeasurementsOrderTestsAnchor {}

@Suite("SavedMeasurementsOrder")
struct SavedMeasurementsOrderTests {
    nonisolated(unsafe) static let file: [String: Any] = {
        let url = Bundle(for: SavedMeasurementsOrderTestsAnchor.self)
            .url(forResource: "saved-measurements-order", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()
    nonisolated(unsafe) static let cases = file["cases"] as! [[String: Any]]

    static let keys: [SavedMeasurementsOrder.Key] = {
        let iso = ISO8601DateFormatter()
        return (file["measurements"] as! [[String: Any]]).map {
            SavedMeasurementsOrder.Key(name: $0["name"] as! String,
                                       date: iso.date(from: $0["timestamp"] as! String)!,
                                       type: $0["type"] as! String)
        }
    }()

    @Test(arguments: cases.map { $0["id"] as! String })
    func shownOrder(_ id: String) {
        let row = Self.cases.first { $0["id"] as! String == id }!
        let shown = SavedMeasurementsOrder.shown(Self.keys,
                                                 sort: SavedMeasurementsSort(rawValue: row["sort"] as! String)!,
                                                 ascending: row["ascending"] as! Bool,
                                                 filter: row["filter"] as? String)
        #expect(shown == row["expect"] as! [Int], "\(id) \(row["name"] as! String)")
    }

    nonisolated(unsafe) static let duplicateCases = file["duplicates"] as! [[String: Any]]

    @Test(arguments: duplicateCases.map { $0["id"] as! String })
    func duplicates(_ id: String) {
        let row = Self.duplicateCases.first { $0["id"] as! String == id }!
        #expect(SavedMeasurementsOrder.duplicates(row["ids"] as! [String]) == row["expect"] as! [Int],
                "\(id) \(row["name"] as! String)")
    }
}
