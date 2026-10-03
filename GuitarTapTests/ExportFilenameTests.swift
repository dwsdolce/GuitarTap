//
//  ExportFilenameTests.swift
//  GuitarTapTests
//
//  The export filename stem (ExportFilename.stem) and a saved measurement's base filename against the shared
//  case file `export-filename.json`, the same cases the Python and web suites run.
//
// @parity test/export-filename

import Foundation
import Testing
@testable import GuitarTap

private final class ExportFilenameTestsAnchor {}

@Suite("ExportFilename")
struct ExportFilenameTests {

    static let data: [String: [[String: Any]]] = {
        let url = Bundle(for: ExportFilenameTestsAnchor.self).url(forResource: "export-filename", withExtension: "json")!
        let json = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return json.compactMapValues { $0 as? [[String: Any]] }
    }()

    @Test func stem() {
        for row in Self.data["stem"]! {
            let stem = ExportFilename.stem(name: row["name"] as? String,
                                           timestamp: Date(timeIntervalSince1970: row["seconds"] as! Double),
                                           unnamed: row["unnamed"] as! String)
            #expect(stem == (row["expect"] as! String), "\(row)")
        }
    }

    @Test func measurementBaseFilename() throws {
        let iso = ISO8601DateFormatter()
        let isoFraction = ISO8601DateFormatter()
        isoFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for row in Self.data["measurementBaseFilename"]! {
            let text = row["timestamp"] as! String
            let date = try #require(iso.date(from: text) ?? isoFraction.date(from: text))
            let m = TapToneMeasurement(timestamp: date, peaks: [], measurementName: row["name"] as? String)
            #expect(m.baseFilename == (row["expect"] as! String), "\(row)")
        }
    }
}
