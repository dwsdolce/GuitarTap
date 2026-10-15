//
//  PeakSelectionPersistenceTests.swift
//  GuitarTapTests
//
//  Whether a guitar measurement's peak selection was the user's own (manual) or the app's
//  (automatic) is saved with it: a loaded manual selection — or one from a file saved before the flag
//  existed — enables the Reset to automatic selection (wand) button, and the wand makes it automatic
//  again. The cases are the shared ones in `peak-selection-persistence.json` (PSP1–PSP6), the same as
//  Python and the web. They use the real swift-mac capture, saved with the automatic selection at Peak
//  Min −60, which leaves out the Air peak at 97.26 Hz / −64.21 dB; the automatic selection over all
//  the peaks includes it.
//
// @parity test/peak-selection-persistence

import Testing
import Foundation
@testable import GuitarTap

private final class SelAnchor {}

@Suite("Peak selection persistence")
struct PeakSelectionPersistenceTests {

    private func fixtureSpectrum() throws -> (mags: [Float], freqs: [Float]) {
        let url = try #require(Bundle(for: SelAnchor.self).url(forResource: ((Self.data["fixture"] as! String) as NSString).deletingPathExtension, withExtension: "guitartap"))
        let arr = try #require(try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [[String: Any]])
        let sn = try #require(arr.first?["spectrumSnapshot"] as? [String: Any])
        func floats(_ b64: String) -> [Float] { Data(base64Encoded: b64)!.withUnsafeBytes { Array($0.bindMemory(to: Float32.self)) } }
        return (floats(sn["magnitudesData"] as! String), floats(sn["frequenciesData"] as! String))
    }

    /// Builds a loadable guitar measurement whose peaks are the full ≥−100 set and whose saved
    /// selection is the auto winners at Peak Min −60 (which excludes Air).
    private func makeMeasurement(userModified: Bool?) throws -> (m: TapToneMeasurement, air: Bool) {
        TapDisplaySettings.measurementType = .generic
        let sut = makeSUTForBuild()
        let (mags, freqs) = try fixtureSpectrum()
        let minHz = Float(Self.data["minHz"] as! Double), maxHz = Float(Self.data["maxHz"] as! Double)
        let savedPeakMin = Float(Self.data["savedPeakMin"] as! Double)
        let full = sut.findPeaks(magnitudes: mags, frequencies: freqs, minHz: minHz, maxHz: maxHz, peakMinOverride: -100)
        let displayed60 = full.filter { $0.magnitude >= savedPeakMin }
        let winners60 = sut.guitarModeSelectedPeakIDs(from: displayed60)
        let snap = SpectrumSnapshot(frequencies: freqs, magnitudes: mags, minFreq: 75, maxFreq: 350,
                                    minDB: -100, maxDB: 0, isLogarithmic: false,
                                    guitarType: .generic, measurementType: .generic)
        let m = TapToneMeasurement(
            peaks: full,
            spectrum: snap,
            tapDetectionThreshold: -49,
            numberOfTaps: 1,
            peakMinThreshold: savedPeakMin,
            selectedPeakIDs: Array(winners60),
            selectedPeakFrequencies: displayed60.filter { winners60.contains($0.id) }.map { $0.frequency },
            userModifiedSelection: userModified
        )
        // Sanity: no Air winner in the saved selection.
        let airSelectedInSave = full.contains { winners60.contains($0.id) && abs($0.frequency - Float(Self.data["airHz"] as! Double)) < 1 }
        return (m, airSelectedInSave)
    }

    private func makeSUTForBuild() -> TapToneAnalyzer {
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        sut.minFrequency = Float(Self.data["minHz"] as! Double); sut.maxFrequency = Float(Self.data["maxHz"] as! Double)
        return sut
    }

    // MARK: - The shared cases in `peak-selection-persistence.json`

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: SelAnchor.self).url(forResource: "peak-selection-persistence", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids(_ table: String) -> [String] {
        (data[table] as! [[String: Any]]).map { $0["id"] as! String }
    }

    static func row(_ table: String, _ id: String) -> [String: Any] {
        (data[table] as! [[String: Any]]).first { $0["id"] as! String == id }!
    }

    @Test(arguments: ids("load"))
    func load(_ id: String) throws {
        let row = Self.row("load", id)
        let (m, airInSave) = try makeMeasurement(userModified: row["userModified"] as? Bool)
        #expect(!airInSave, "\(id): precondition — Air is not in the saved selection")
        TapDisplaySettings.measurementType = .generic
        let sut = makeSUTForBuild()
        sut.loadMeasurement(m)
        let airHz = Float(Self.data["airHz"] as! Double)
        let air = try #require(sut.allPeaks.first { abs($0.frequency - airHz) < 1 }, "\(id): the Air peak is loaded")
        #expect(sut.userHasModifiedPeakSelection == row["expectManual"] as? Bool, "\(id) manual (the wand enabled)")
        #expect(sut.selectedPeakIDs.contains(air.id) == row["expectAirSelected"] as? Bool, "\(id) Air selected")
        sut.resetToAutoSelection()
        #expect(sut.userHasModifiedPeakSelection == row["expectManualAfterReset"] as? Bool, "\(id) manual after the wand")
        #expect(sut.selectedPeakIDs.contains(air.id) == row["expectAirSelectedAfterReset"] as? Bool, "\(id) Air selected after the wand")
    }

    @Test(arguments: ids("roundTrip"))
    func roundTrip(_ id: String) throws {
        let row = Self.row("roundTrip", id)
        let (m, _) = try makeMeasurement(userModified: row["userModified"] as? Bool)
        let data = try TapToneAnalyzer.encodeMeasurements([m])
        let written = (String(data: data, encoding: .utf8) ?? "").contains("userModifiedSelection")
        #expect(written == row["expectWritten"] as? Bool, "\(id) written")
        let back = try #require(try TapToneAnalyzer.decodeMeasurements(data).first)
        #expect(back.userModifiedSelection == row["expectRead"] as? Bool, "\(id) read back")
    }
}
