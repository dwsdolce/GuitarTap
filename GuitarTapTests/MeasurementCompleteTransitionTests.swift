//
//  MeasurementCompleteTransitionTests.swift
//  GuitarTapTests
//
//  `isMeasurementComplete` gates whether the spectrum freezes or keeps showing live frames, so every
//  path that should set it true or false is a case here — a new completion path without one is a gap —
//  and so are the paths that move the loaded-settings warning with it. The shared cases in
//  `measurement-complete.json` (MC1–MC18), the same as Python and the web.
//
// @parity test/measurement-complete

import Testing
import Foundation
@testable import GuitarTap

private final class MeasurementCompleteAnchor {}

@Suite("MeasurementCompleteTransitions", .serialized)
@MainActor
struct MeasurementCompleteTransitionTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: MeasurementCompleteAnchor.self).url(forResource: "measurement-complete", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids() -> [String] {
        (data["cases"] as! [[String: Any]]).map { $0["id"] as! String }
    }

    /// A captured tap: 64 bins at 31.25 Hz, −80 dB but bin 16 at `peakDB`.
    static func capturedTap(peakDB: Float) -> (magnitudes: [Float], frequencies: [Float], captureTime: Date) {
        var magnitudes = [Float](repeating: -80, count: 64)
        magnitudes[16] = peakDB
        return (magnitudes, (0..<64).map { Float($0) * 31.25 }, Date())
    }

    @Test(arguments: ids())
    func transitions(_ id: String) throws {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let savedType = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = savedType }
        TapDisplaySettings.measurementType = .classical
        let sut = TapToneAnalyzer.forTesting()
        sut.numberOfTaps = 1
        sut.tapDetectionThreshold = -40
        sut.warmupStartAudioTime = -2  // audio clock: warm-up already elapsed
        sut.justExitedWarmup = false

        for step in row["steps"] as! [[String: Any]] {
            if let n = step["numberOfTaps"] as? Int {
                sut.numberOfTaps = n
            } else if let levels = step["captureTaps"] as? [Double] {
                sut.capturedTaps = levels.map { Self.capturedTap(peakDB: Float($0)) }
            } else if step["processTaps"] as? Bool == true {
                sut.processMultipleTaps()
            } else if step["newTap"] as? Bool == true {
                sut.startTapSequence()
            } else if step["cancel"] as? Bool == true {
                sut.cancelTapSequence()
            } else if let name = step["load"] as? String {
                let file = (Self.data["files"] as! [String: Any])[name]!
                let measurement = try #require(try TapToneAnalyzer.decodeMeasurements(
                    JSONSerialization.data(withJSONObject: file)).first)
                sut.loadMeasurement(measurement)
            } else if step["warning"] as? Bool == true {
                sut.showLoadedSettingsWarning = true
            } else if let n = step["setTaps"] as? Int {
                sut.numberOfTaps = n
            } else if let dB = step["setThreshold"] as? Double {
                sut.tapDetectionThreshold = Float(dB)
            }
        }

        for (field, want) in row["expect"] as! [String: Any] {
            switch field {
            case "complete":
                #expect(sut.isMeasurementComplete == want as? Bool, "\(id) \(field)")
            case "frozenSpectrum":
                let held = !sut.frozenMagnitudes.isEmpty && !sut.frozenFrequencies.isEmpty
                #expect(held == want as? Bool, "\(id) \(field)")
            case "detecting":
                #expect(sut.isDetecting == want as? Bool, "\(id) \(field)")
            case "loadedSettingsWarning":
                #expect(sut.showLoadedSettingsWarning == want as? Bool, "\(id) \(field)")
            case "numberOfTaps":
                #expect(sut.numberOfTaps == want as? Int, "\(id) \(field)")
            default:
                Issue.record("\(id): unknown field \(field)")
            }
        }
    }
}
