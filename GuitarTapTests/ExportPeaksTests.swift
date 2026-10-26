//
//  ExportPeaksTests.swift
//  GuitarTapTests
//
//  The peaks a saved measurement's report shows are the peaks it shows on screen, against the shared case file
//  `export-peaks.json` — the same cases the Python and web suites run. A guitar shows its peaks at or above its
//  Peak Min, so a selected peak below Peak Min is left out of its report as it is off its screen; a plate or
//  brace shows its identified peaks whatever the Peak Min. Each case reads a fixture with the Peak Min it names.
//
// @parity test/export-peaks

import Foundation
import Testing
@testable import GuitarTap

// Anchors Bundle(for:) to the GuitarTapTests bundle so the fixtures load on every destination, not just the
// macOS host.
private final class FixtureAnchor {}

@Suite("ExportPeaks")
struct ExportPeaksTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let cases: [[String: Any]] = {
        let url = Bundle(for: FixtureAnchor.self).url(forResource: "export-peaks", withExtension: "json")!
        let data = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return data["cases"] as! [[String: Any]]
    }()

    /// The case's fixture, read with the Peak Min the case names (as saved when it names none).
    private static func measurement(_ row: [String: Any]) throws -> TapToneMeasurement {
        let url = try #require(Bundle(for: FixtureAnchor.self).url(forResource: row["fixture"] as? String, withExtension: "guitartap"))
        var file = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        if let peakMin = row["peakMinThreshold"] as? Double {
            file[0]["peakMinThreshold"] = peakMin
        }
        return try #require(try TapToneAnalyzer.decodeMeasurements(JSONSerialization.data(withJSONObject: file)).first)
    }

    @Test(arguments: cases.indices)
    func peaksAbovePeakMin(_ index: Int) throws {
        let row = Self.cases[index]
        let m = try Self.measurement(row)
        #expect(m.peaksAbovePeakMin.count == (row["peaksAbovePeakMin"] as! Int))
        // The export header's "Detected Peaks: N": the detected peaks in view (none for a plate or brace).
        #expect(m.detectedPeaksInView.count == (row["detectedPeaksInView"] as! Int))
    }

    @Test(arguments: cases.indices.filter { cases[$0]["reportRows"] is [Double] })
    func reportRows_leaveOutPeaksBelowPeakMin(_ index: Int) throws {
        let row = Self.cases[index]
        let data = PDFReportData.from(measurement: try Self.measurement(row))
        let rows = data.peaks.filter { data.selectedPeakIDs.contains($0.id) }
            .map { (Double($0.frequency) * 10).rounded() / 10 }
            .sorted()
        #expect(rows == (row["reportRows"] as! [Double]))
    }

    /// The image's Selected Peaks Summary lists `reportPeaks`: the report table's rows.
    @Test(arguments: cases.indices.filter { cases[$0]["reportRows"] is [Double] })
    func reportPeaks_areTheReportRows(_ index: Int) throws {
        let row = Self.cases[index]
        let rows = try Self.measurement(row).reportPeaks.map { (Double($0.frequency) * 10).rounded() / 10 }
        #expect(rows == (row["reportRows"] as! [Double]))
    }
}
