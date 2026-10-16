//
//  MeasurementLoadTests.swift
//  GuitarTapTests
//
//  Loading a saved measurement: the whole load is the model's — its own settings, its peaks shown under
//  them, its spectra, label positions and microphone warning, and the detection state. The shared cases
//  in `measurement-load.json` (LD1–LD6), the same as Python and the web.
//
// @parity test/measurement-load

import Testing
import Foundation
@testable import GuitarTap

private final class MeasurementLoadAnchor {}

@Suite("MeasurementLoad", .serialized)
@MainActor
struct MeasurementLoadTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: MeasurementLoadAnchor.self).url(forResource: "measurement-load", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids() -> [String] {
        (data["cases"] as! [[String: Any]]).map { $0["id"] as! String }
    }

    /// The measurement a `load` step names: an inline file of the case table, or a fixture.
    static func measurement(_ name: String) throws -> TapToneMeasurement {
        let fileData: Data
        if let inline = (data["files"] as? [String: Any])?[name] {
            fileData = try JSONSerialization.data(withJSONObject: inline)
        } else {
            let stem = (name as NSString).deletingPathExtension
            let url = try #require(Bundle(for: MeasurementLoadAnchor.self).url(forResource: stem, withExtension: "guitartap"))
            fileData = try Data(contentsOf: url)
        }
        return try #require(try TapToneAnalyzer.decodeMeasurements(fileData).first)
    }

    @Test(arguments: ids())
    func load(_ id: String) throws {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        // The settings a load writes are global; put them back afterwards.
        let saved = (TapDisplaySettings.measurementType, TapDisplaySettings.showUnknownModes,
                     TapDisplaySettings.peakMinThreshold, TapDisplaySettings.tapDetectionThreshold,
                     TapDisplaySettings.annotationVisibilityMode)
        defer {
            TapDisplaySettings.measurementType = saved.0
            TapDisplaySettings.showUnknownModes = saved.1
            TapDisplaySettings.peakMinThreshold = saved.2
            TapDisplaySettings.tapDetectionThreshold = saved.3
            TapDisplaySettings.annotationVisibilityMode = saved.4
        }
        let sut = TapToneAnalyzer.forTesting()
        for step in row["steps"] as! [[String: Any]] {
            if step["newTap"] as? Bool == true {
                sut.startTapSequence()
                #expect(sut.isDetecting, "\(id): precondition — a new tap sequence arms detection")
            } else if let db = step["peakMin"] as? Double {
                sut.peakMinThreshold = Float(db)
            } else if let name = step["load"] as? String {
                sut.loadMeasurement(try Self.measurement(name))
            } else if step["highlightFirstPeak"] as? Bool == true {
                let first = try #require(sut.peaksAbovePeakMin.first, "\(id): a peak to highlight")
                sut.highlightedPeakID = first.id
                #expect(sut.highlightedPeakID != nil, "\(id): precondition — a peak is highlighted")
            } else if let names = step["compare"] as? [String] {
                sut.loadComparison(measurements: try names.map(Self.measurement))
            }
        }
        let isGuitar = TapDisplaySettings.measurementType.isGuitar
        for (field, want) in row["expect"] as! [String: Any] {
            switch field {
            case "measurementType":
                #expect(TapDisplaySettings.measurementType.rawValue == want as? String, "\(id) \(field)")
            case "peakMinThreshold":
                #expect(Double(sut.peakMinThreshold) == want as? Double, "\(id) \(field)")
            case "tapDetectionThreshold":
                #expect(abs(Double(sut.tapDetectionThreshold) - (want as! Double)) < 1e-4, "\(id) \(field): \(sut.tapDetectionThreshold)")
            case "showUnknownModes":
                #expect(TapDisplaySettings.showUnknownModes == want as? Bool, "\(id) \(field)")
            case "shownPeaks":
                let shown = isGuitar ? sut.peaksAbovePeakMin.count : sut.materialIdentifiedPeaks.count
                #expect(shown == want as? Int, "\(id) \(field): \(shown)")
            case "frozenSpectrum":
                #expect(!sut.frozenFrequencies.isEmpty == want as? Bool, "\(id) \(field)")
            case "phaseSpectra":
                let count = [sut.longitudinalSpectrum != nil, sut.crossSpectrum != nil, sut.flcSpectrum != nil].filter { $0 }.count
                #expect(count == want as? Int, "\(id) \(field): \(count)")
            case "complete":
                #expect(sut.isMeasurementComplete == want as? Bool, "\(id) \(field)")
            case "detecting":
                #expect(sut.isDetecting == want as? Bool, "\(id) \(field)")
            case "comparison":
                #expect((sut.displayMode == .comparison) == want as? Bool, "\(id) \(field)")
            case "microphoneWarning":
                #expect((sut.microphoneWarning != nil) == want as? Bool, "\(id) \(field)")
            case "highlightedPeak":
                #expect((sut.highlightedPeakID != nil) == want as? Bool, "\(id) \(field)")
            case "recordedMicrophone":
                #expect((sut.resultProvenance != nil) == want as? Bool, "\(id) \(field)")
            case "labelPositions":
                #expect(sut.peakAnnotationOffsets.count == want as? Int, "\(id) \(field): \(sut.peakAnnotationOffsets.count)")
            default:
                Issue.record("\(id): unknown field \(field)")
            }
        }
    }
}
