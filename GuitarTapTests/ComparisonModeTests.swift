//
//  ComparisonModeTests.swift
//  GuitarTapTests
//
//  Comparing saved measurements: the entries a comparison holds, their labels and range, the mode,
//  detection standing down, the per-tap overlay giving way, each entry's Air/Top/Back taken from its
//  source, and saving and loading a comparison. The shared cases in `comparison.json` (CM1–CM25), the
//  same as Python and the web.
//
// @parity test/comparison

import Testing
import Foundation
@testable import GuitarTap

private final class ComparisonAnchor {}

@Suite("Comparison", .serialized)
@MainActor
struct ComparisonModeTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: ComparisonAnchor.self).url(forResource: "comparison", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids() -> [String] {
        (data["cases"] as! [[String: Any]]).map { $0["id"] as! String }
    }

    static func measurement(_ name: String) throws -> TapToneMeasurement {
        let file = (data["files"] as! [String: Any])[name]!
        return try #require(try TapToneAnalyzer.decodeMeasurements(JSONSerialization.data(withJSONObject: file)).first)
    }

    static func peakName(_ id: UUID) -> String {
        (data["peakNames"] as! [String: String]).first { UUID(uuidString: $0.key) == id }?.value ?? id.uuidString
    }

    static func check(_ fields: [String: Any], _ sut: TapToneAnalyzer, savedBefore: Int, _ id: String) {
        for (field, want) in fields {
            switch field {
            case "entries": #expect(sut.comparisonSpectra.count == want as? Int, "\(id) \(field)")
            case "labels": #expect(sut.comparisonSpectra.map(\.label) == want as? [String], "\(id) \(field): \(sut.comparisonSpectra.map(\.label))")
            case "mode": #expect((sut.displayMode == .comparison ? "comparison" : "live") == want as? String, "\(id) \(field)")
            case "loadedRange":
                let r = sut.loadedAxisRange
                let got = r.map { [Double($0.minFreq), Double($0.maxFreq), Double($0.minDB), Double($0.maxDB)] }
                #expect(got == (want as! [NSNumber]).map(\.doubleValue), "\(id) \(field): \(String(describing: got))")
            case "detecting": #expect(sut.isDetecting == want as? Bool, "\(id) \(field)")
            case "multiTap": #expect(sut.showingMultiTapComparison == want as? Bool, "\(id) \(field)")
            case "tapEntries": #expect(sut.tapEntries.count == want as? Int, "\(id) \(field)")
            case "savedComparison": #expect(sut.isSavedMeasurementComparison == want as? Bool, "\(id) \(field)")
            case "modeIds":
                let got = (sut.comparisonSpectra.first?.modeIDs ?? [:]).mapValues { peakName($0) }
                #expect(got == want as? [String: String], "\(id) \(field): \(got)")
            case "entryGuitarType":
                #expect(sut.comparisonSpectra.first?.guitarType?.rawValue == want as? String, "\(id) \(field)")
            case "entryPeaks":
                let got = (sut.comparisonSpectra.first?.peaks ?? []).map { peakName($0.id) }.sorted()
                #expect(got == (want as! [String]).sorted(), "\(id) \(field): \(got)")
            case "savedRecord":
                if let record = want as? [String: Any] {
                    let last = sut.savedMeasurements.last
                    #expect(sut.savedMeasurements.count == savedBefore + 1, "\(id) \(field): a record added")
                    #expect(last?.measurementName == record["name"] as? String, "\(id) \(field) name")
                    #expect(last?.comparisonEntries?.count == record["entries"] as? Int, "\(id) \(field) entries")
                } else {
                    #expect(sut.savedMeasurements.count == savedBefore, "\(id) \(field): none added")
                }
            case "phase": #expect(sut.materialTapPhase.rawValue == want as? String, "\(id) \(field)")
            case "complete": #expect(sut.isMeasurementComplete == want as? Bool, "\(id) \(field)")
            default: Issue.record("\(id): unknown field \(field)")
            }
        }
    }

    @Test(arguments: ids())
    func comparison(_ id: String) throws {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }

        let sut = makeStepsAnalyzer()
        sut.savedMeasurements = []
        sut.libraryFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("comparison-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: sut.libraryFileURL) }
        for step in row["steps"] as! [[String: Any]] {
            if let names = step["compare"] as? [String] {
                sut.loadComparison(measurements: try names.map(Self.measurement))
            } else if step["clearComparison"] as? Bool == true {
                sut.clearComparison()
            } else if let name = step["load"] as? String {
                sut.loadMeasurement(try Self.measurement(name))
            } else if let show = step["multiTap"] as? Bool {
                sut.applyMultiTapComparisonOverlays(enabled: show)   // the Taps toggle
            } else if let name = step["saveComparison"] as? String {
                sut.saveComparison(measurementName: name)
            } else if step["loadSaved"] as? Bool == true {
                sut.loadMeasurement(try #require(sut.savedMeasurements.last))
            } else if let fields = step["check"] as? [String: Any] {
                Self.check(fields, sut, savedBefore: 0, id)
            } else {
                #expect(runAnalyzerStep(step, on: sut), "\(id): unknown step \(step)")
            }
        }
        Self.check(row["expect"] as! [String: Any], sut, savedBefore: 0, id)
    }
}
