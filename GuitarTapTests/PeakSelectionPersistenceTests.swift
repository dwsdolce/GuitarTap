//
//  PeakSelectionPersistenceTests.swift
//  GuitarTapTests
//
//  Option 1 of PEAK-MIN-SEMANTICS.md: the manual/auto selection flag is persisted, so a reloaded
//  measurement behaves like a live one. An AUTO selection re-runs auto-selection when Peak Min
//  changes (a peak revealed by lowering Peak Min is selected as its mode's winner); a MANUAL one is
//  carried forward. Files saved before the field default to manual (prior behaviour, no regression).
//
//  Uses the real swift-mac capture: Air is at 97.26 Hz / −64.21 dB, so a Peak Min of −60 excludes
//  it; lowering to −70 reveals it, and whether it gets selected depends on the persisted flag.
//
// @parity test/peak-selection-persistence

import Testing
import Foundation
@testable import GuitarTap

private final class SelAnchor {}

@Suite("Peak selection persistence")
struct PeakSelectionPersistenceTests {

    private func fixtureSpectrum() throws -> (mags: [Float], freqs: [Float]) {
        let url = try #require(Bundle(for: SelAnchor.self).url(forResource: "dws-2024-umik-1-swift-mac-1784225155", withExtension: "guitartap"))
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
        let full = sut.findPeaks(magnitudes: mags, frequencies: freqs, minHz: 30, maxHz: 2000, peakMinOverride: -100)
        let displayed60 = full.filter { $0.magnitude >= -60 }
        let winners60 = sut.guitarModeSelectedPeakIDs(from: displayed60)
        let snap = SpectrumSnapshot(frequencies: freqs, magnitudes: mags, minFreq: 75, maxFreq: 350,
                                    minDB: -100, maxDB: 0, isLogarithmic: false,
                                    guitarType: .generic, measurementType: .generic)
        let m = TapToneMeasurement(
            peaks: full,
            spectrum: snap,
            tapDetectionThreshold: -49,
            numberOfTaps: 1,
            peakMinThreshold: -60,
            selectedPeakIDs: Array(winners60),
            selectedPeakFrequencies: displayed60.filter { winners60.contains($0.id) }.map { $0.frequency },
            userModifiedSelection: userModified
        )
        // Sanity: no Air winner in the saved selection.
        let airSelectedInSave = full.contains { winners60.contains($0.id) && abs($0.frequency - 97.26) < 1 }
        return (m, airSelectedInSave)
    }

    private func makeSUTForBuild() -> TapToneAnalyzer {
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer())
        sut.minFrequency = 30; sut.maxFrequency = 2000
        return sut
    }

    private func airSelectedAfterLowering(_ m: TapToneMeasurement) -> (revealed: Bool, selected: Bool) {
        TapDisplaySettings.measurementType = .generic
        let sut = makeSUTForBuild()
        sut.loadMeasurement(m)
        sut.peakMinThreshold = -70          // reveal Air (−64.21 dB)
        sut.recalculateFrozenPeaksIfNeeded()
        let air = sut.currentPeaks.first { abs($0.frequency - 97.26) < 1 }
        let revealed = air != nil
        let selected = air.map { sut.selectedPeakIDs.contains($0.id) } ?? false
        return (revealed, selected)
    }

    @Test func automaticSelection_reSelectsRevealedAir() throws {
        let (m, airInSave) = try makeMeasurement(userModified: false)
        #expect(!airInSave, "precondition: Air is not selected in the saved (Peak Min −60) selection")
        let r = airSelectedAfterLowering(m)
        #expect(r.revealed, "lowering Peak Min should reveal the Air peak")
        #expect(r.selected, "an AUTO measurement should auto-select the revealed Air winner (like live)")
    }

    @Test func manualSelection_doesNotReSelect() throws {
        let (m, _) = try makeMeasurement(userModified: true)
        let r = airSelectedAfterLowering(m)
        #expect(r.revealed, "lowering Peak Min should still reveal the Air peak")
        #expect(!r.selected, "a MANUAL measurement carries its selection forward — Air stays unselected")
    }

    @Test func legacyFileDefaultsToManual() throws {
        // Field absent (old file) → nil → treated as manual (prior behaviour, no auto-reselect).
        let (m, _) = try makeMeasurement(userModified: nil)
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer())
        sut.loadMeasurement(m)
        #expect(sut.userHasModifiedPeakSelection == true, "a legacy file (no flag) defaults to manual")
    }

    @Test func flagRoundTripsThroughEncoding() throws {
        for value in [true, false] {
            let (m, _) = try makeMeasurement(userModified: value)
            let data = try TapToneAnalyzer.encodeMeasurements([m])
            let back = try #require(try TapToneAnalyzer.decodeMeasurements(data).first)
            #expect(back.userModifiedSelection == value, "userModifiedSelection must round-trip (\(value))")
        }
        // Absent key decodes to nil.
        let (m, _) = try makeMeasurement(userModified: nil)
        let data = try TapToneAnalyzer.encodeMeasurements([m])
        #expect(!(String(data: data, encoding: .utf8) ?? "").contains("userModifiedSelection"),
                "a nil flag is omitted from the JSON")
    }
}