//
//  CalibrationTests.swift
//  GuitarTapTests
//
//  The engine's calibration corrections: the engine holds the active calibration and computes its
//  per-bin corrections from its own bins, at each bin's exact frequency, again when the sample rate
//  changes, and flat outside the file's range (CAL1–CAL3); and reading a calibration file — its points,
//  its header's Sens Factor and reference level, and a file with no data (CP1–CP9). The shared cases in
//  `calibration.json`.
//
//  The same list, ids and values as Python test_calibration.py and web test/calibration.test.ts.
//
// @parity test/calibration

import Testing
import Foundation
@testable import GuitarTap

private final class CalibrationAnchor {}

@Suite("Calibration", .serialized)
@MainActor
struct CalibrationTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: CalibrationAnchor.self).url(forResource: "calibration", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    /// Sets the engine's sample rate and waits until its bins — published on the main queue — follow it.
    private func setSampleRate(_ rate: Double, of engine: RealtimeFFTAnalyzer) async {
        engine.actualSampleRate = rate
        engine.updateFrequencyBins()
        let expected = Float(rate) / Float(engine.fftSize)
        for _ in 0..<200 where engine.frequencies.count < 2 || engine.frequencies[1] != expected {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @Test(arguments: (data["cases"] as! [[String: Any]]).map { $0["id"] as! String })
    func calibrationCorrections(_ id: String) async throws {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let engine = RealtimeFFTAnalyzer.forTesting()
        #expect(engine.fftSize == Self.data["fftSize"] as! Int)
        await setSampleRate((row["fromSampleRate"] as? Double) ?? (row["sampleRate"] as! Double), of: engine)
        let name = (Self.data["calibrationFile"] as! String) as NSString
        let url = try #require(Bundle(for: CalibrationAnchor.self).url(
            forResource: name.deletingPathExtension, withExtension: name.pathExtension))
        engine.setTemporaryCalibration(try CalibrationFileParser.parse(url: url))
        if row["fromSampleRate"] != nil {
            #expect(!engine.calibrationCorrections.isEmpty, "computed for the first rate")
            await setSampleRate(row["sampleRate"] as! Double, of: engine)
        }
        let corrections = engine.calibrationCorrections
        let tolerance = Self.data["tolerance"] as! Double
        for (bin, expected) in zip(row["bins"] as! [Int], row["expect"] as! [Double]) {
            #expect(abs(Double(corrections[bin]) - expected) <= tolerance,
                    "\(id): bin \(bin) — \(corrections[bin]) dB, expected \(expected) — \(row["note"] as! String)")
        }
    }

    @Test(arguments: (data["parse"] as! [[String: Any]]).map { $0["id"] as! String })
    func calibrationParse(_ id: String) throws {
        let row = (Self.data["parse"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let content: String
        if let file = row["file"] as? String {
            let name = file as NSString
            let url = try #require(Bundle(for: CalibrationAnchor.self).url(
                forResource: name.deletingPathExtension, withExtension: name.pathExtension))
            content = try String(contentsOf: url, encoding: .utf8)
        } else {
            content = row["content"] as! String
        }
        let expect = row["expect"] as! [String: Any]
        guard let cal = try? CalibrationFileParser.parse(content: content, name: id) else {
            #expect(expect["error"] as? Bool == true, "\(id): the text did not parse")
            return
        }
        #expect(expect["error"] == nil, "\(id): the text parsed, where an error was expected")
        let points = cal.correctionPoints.map { [Double($0.frequency), Double($0.correction)] }
        func near(_ a: [Double], _ b: [Double]) -> Bool { zip(a, b).allSatisfy { abs($0 - $1) < 1e-3 } && a.count == b.count }
        for (field, want) in expect {
            switch field {
            case "pointCount": #expect(points.count == want as? Int, "\(id) \(field): \(points.count)")
            case "first": #expect(near(points.first ?? [], (want as! [NSNumber]).map(\.doubleValue)), "\(id) \(field)")
            case "last": #expect(near(points.last ?? [], (want as! [NSNumber]).map(\.doubleValue)), "\(id) \(field)")
            case "points":
                let all = (want as! [[NSNumber]]).map { $0.map(\.doubleValue) }
                #expect(points.count == all.count && zip(points, all).allSatisfy { near($0, $1) }, "\(id) \(field): \(points)")
            case "sensitivity", "referenceLevel":
                let got = field == "sensitivity" ? cal.sensitivityFactor : cal.referenceLevel
                if let w = want as? NSNumber {
                    #expect(got.map { abs(Double($0) - w.doubleValue) < 1e-4 } == true, "\(id) \(field): \(String(describing: got))")
                } else {
                    #expect(got == nil, "\(id) \(field): \(String(describing: got))")
                }
            case "error": break
            default: Issue.record("\(id): unknown field \(field)")
            }
        }
    }

    @Test(arguments: (data["details"] as! [[String: Any]]).map { $0["id"] as! String })
    func calibrationDetails(_ id: String) throws {
        let row = (Self.data["details"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let content: String
        if let file = row["file"] as? String {
            let name = file as NSString
            let url = try #require(Bundle(for: CalibrationAnchor.self).url(
                forResource: name.deletingPathExtension, withExtension: name.pathExtension))
            content = try String(contentsOf: url, encoding: .utf8)
        } else {
            content = row["content"] as! String
        }
        let details = try CalibrationFileParser.parse(content: content, name: id).details
        let expect = row["expect"] as! [String: Any]
        #expect(details.sensitivity == expect["sensitivity"] as? String, "\(id) sensitivity: \(String(describing: details.sensitivity))")
        #expect(details.dataPoints == expect["dataPoints"] as? String, "\(id) dataPoints: \(details.dataPoints)")
        #expect(details.range == expect["range"] as? String, "\(id) range: \(String(describing: details.range))")
    }

    /// Every bin's correction, computed for all the FFT's bins at once, is the one ``correction(at:)`` gives
    /// that bin alone — exactly, for the bins of 48 kHz and of 44.1 kHz and for unsorted frequencies.
    @Test func correctionsForAllBins_areEachBinsCorrection() throws {
        let name = (Self.data["calibrationFile"] as! String) as NSString
        let url = try #require(Bundle(for: CalibrationAnchor.self).url(
            forResource: name.deletingPathExtension, withExtension: name.pathExtension))
        let calibration = try CalibrationFileParser.parse(url: url)
        let fftSize = Self.data["fftSize"] as! Int
        for rate in [48000.0, 44100.0] {
            let bins = (0..<(fftSize / 2)).map { Float($0) * Float(rate) / Float(fftSize) }
            #expect(calibration.corrections(for: bins) == bins.map { calibration.correction(at: $0) }, "\(rate) Hz")
        }
        let unsorted: [Float] = [1000, 20, 5000, 20, 19000, 3]
        #expect(calibration.corrections(for: unsorted) == unsorted.map { calibration.correction(at: $0) })
    }
}
