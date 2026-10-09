//
//  MaterialSelectionTests.swift
//  GuitarTapTests
//
//  A material (plate / brace) measurement's effective selection ignores the saved selection, against the
//  shared case file `material-selection.json` — the same cases the Python and web suites run. Material has no
//  per-peak selection: the identified L / C / FLC are the peaks. The case is a genuine iPad-saved plate whose
//  saved selection was clobbered to the cross peak alone; reading it resolves all three, healing the file.
//
// @parity test/material-selection

import Foundation
import Testing
@testable import GuitarTap

// Anchors Bundle(for:) to the GuitarTapTests bundle so the fixtures load on every destination, not just the
// macOS host.
private final class FixtureAnchor {}

@Suite("MaterialSelection")
struct MaterialSelectionTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let cases: [[String: Any]] = {
        let url = Bundle(for: FixtureAnchor.self).url(forResource: "material-selection", withExtension: "json")!
        let data = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return data["cases"] as! [[String: Any]]
    }()

    @Test(arguments: cases.indices)
    func effectiveSelection_isEveryMaterialPeak(_ index: Int) throws {
        let row = Self.cases[index]
        let url = try #require(Bundle(for: FixtureAnchor.self).url(forResource: row["fixture"] as? String, withExtension: "guitartap"))
        let m = try #require(try TapToneAnalyzer.decodeMeasurements(Data(contentsOf: url)).first)
        #expect(m.isMaterial == (row["isMaterial"] as! Bool))
        #expect(m.peaks.count == (row["peakCount"] as! Int))
        #expect((m.selectedPeakIDs?.count ?? 0) == (row["savedSelectionCount"] as! Int))
        #expect(m.effectiveSelectedPeakIDs == Set(m.peaks.map { $0.id }))
        #expect(m.effectiveSelectedPeakIDs.count == (row["effectiveSelectionCount"] as! Int))
    }
}
