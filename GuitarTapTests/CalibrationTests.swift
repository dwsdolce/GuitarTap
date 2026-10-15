//
//  CalibrationTests.swift
//  GuitarTapTests
//
//  The engine's calibration corrections: the engine holds the active calibration and computes its
//  per-bin corrections from its own bins, at each bin's exact frequency, and again when the sample rate
//  changes (CAL1, CAL2 — the shared cases in `calibration.json`).
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
}
