//
//  MeasurementTypeNameTests.swift
//  GuitarTapTests
//
//  The Details pane's measurement type (`TapToneMeasurement.measurementTypeShortName`) and the material flag
//  (`isMaterial`), both resolved from the snapshots — the type lives only there — against the shared case file
//  `measurement-type-name.json`, the same cases the Python and web suites run. In-memory measurements, the
//  shape a round trip cannot test (loading a file fills the type in).
//
// @parity test/measurement-type-name

import Foundation
import Testing
@testable import GuitarTap

private final class MeasurementTypeNameTestsAnchor {}

@Suite("MeasurementTypeName")
@MainActor
struct MeasurementTypeNameTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: [[String: Any]]] = {
        let url = Bundle(for: MeasurementTypeNameTestsAnchor.self).url(forResource: "measurement-type-name", withExtension: "json")!
        let json = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return json.compactMapValues { $0 as? [[String: Any]] }
    }()

    /// A snapshot as the file describes it: "absent" is none, null is one with no type.
    static func snapshot(_ v: Any?) -> SpectrumSnapshot? {
        if (v as? String) == "absent" { return nil }
        let type = (v as? String).map { MeasurementType(rawValue: $0)! }
        return SpectrumSnapshot(frequencies: [], magnitudes: [], minFreq: 20, maxFreq: 200,
                                minDB: -100, maxDB: 0, isLogarithmic: false, measurementType: type)
    }

    static func measurement(_ row: [String: Any]) -> TapToneMeasurement {
        TapToneMeasurement(peaks: [], spectrum: snapshot(row["spectrum"] is NSNull ? nil : row["spectrum"]),
                           longitudinalSnapshot: snapshot(row["longitudinal"] is NSNull ? nil : row["longitudinal"]),
                           comparisonEntries: (row["isComparison"] as? Bool) == true ? [] : nil)
    }

    nonisolated static func applies(_ row: [String: Any]) -> Bool { (row["editions"] as? [String])?.contains("swift") ?? true }

    @Test(arguments: data["shortName"]!.filter(applies).map { $0["id"] as! String })
    func shortName(_ id: String) {
        let row = Self.data["shortName"]!.first { $0["id"] as! String == id }!
        #expect(Self.measurement(row).measurementTypeShortName == (row["expect"] as! String), "\(id)")
    }

    @Test func isMaterial() {
        for row in Self.data["isMaterial"]! {
            #expect(Self.measurement(row).isMaterial == (row["expect"] as! Bool), "\(row)")
        }
    }
}
