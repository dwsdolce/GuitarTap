//
//  MeasurementNameTests.swift
//  GuitarTapTests
//
//  The required-name rule — what enables Save (isValidName) and what is stored for the name and the notes
//  (normalizedName, normalizedNotes) — against the shared case file `measurement-name.json`, the same cases
//  the Python and web suites run.
//
// @parity test/measurement-name

import Foundation
import Testing
@testable import GuitarTap

private final class MeasurementNameTestsAnchor {}

@Suite("MeasurementName")
struct MeasurementNameTests {

    static let data: [String: [[Any]]] = {
        let url = Bundle(for: MeasurementNameTestsAnchor.self).url(forResource: "measurement-name", withExtension: "json")!
        let json = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return json.compactMapValues { $0 as? [[Any]] }
    }()

    @Test func isValidName() {
        for row in Self.data["isValidName"]! {
            #expect(TapToneMeasurement.isValidName(row[0] as! String) == (row[1] as! Bool), "\((row[0] as! String).debugDescription)")
        }
    }

    @Test func normalizedName() {
        for row in Self.data["normalizedName"]! {
            #expect(TapToneMeasurement.normalizedName(row[0] as! String) == row[1] as? String, "\((row[0] as! String).debugDescription)")
        }
    }

    @Test func normalizedNotes() {
        for row in Self.data["normalizedNotes"]! {
            #expect(TapToneMeasurement.normalizedNotes(row[0] as! String) == row[1] as? String, "\((row[0] as! String).debugDescription)")
        }
    }
}
