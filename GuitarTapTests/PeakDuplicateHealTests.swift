//
//  PeakDuplicateHealTests.swift
//  GuitarTapTests
//
//  Healing files saved with a duplicate peak, against the shared case file `peak-heal.json` — the same cases
//  the Python and web suites run.
//
//  Loaded peaks are authoritative — never re-derived — so a file saved with a duplicate peak would keep it
//  forever. The repair happens at decode, in the per-measurement decoder, so it covers both a .guitartap file
//  and the saved-measurements store. Rule: collapse peaks closer than the proximity window, keeping (1) the
//  peak whose id is selected, else (2) the higher magnitude, else (3) the first. findPeaks' own spacing keeps
//  saved peaks at least that far apart, so any closer pair is corruption.
//
// @parity test/peak-heal

import Foundation
import Testing
@testable import GuitarTap

private final class FixtureAnchor {}

@Suite("Duplicate-peak heal on decode")
struct PeakDuplicateHealTests {

    static let cases: [[String: Any]] = {
        let url = Bundle(for: FixtureAnchor.self).url(forResource: "peak-heal", withExtension: "json")!
        let data = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return data["cases"] as! [[String: Any]]
    }()

    static func decode(_ row: [String: Any]) throws -> TapToneMeasurement {
        let url = try #require(Bundle(for: FixtureAnchor.self).url(forResource: row["fixture"] as? String, withExtension: "guitartap"))
        return try #require(try TapToneAnalyzer.decodeMeasurements(Data(contentsOf: url)).first)
    }

    @Test(arguments: cases.indices)
    func decodedMeasurementHasNoDuplicatePeaks(_ index: Int) throws {
        let row = Self.cases[index]
        let m = try Self.decode(row)
        let proximity = Float(row["proximityHz"] as! Double)
        var offenders: [String] = []
        for i in m.peaks.indices {
            for j in m.peaks.indices where j > i {
                let delta = abs(m.peaks[i].frequency - m.peaks[j].frequency)
                if delta < proximity {
                    offenders.append(String(format: "%.5f Hz / %.5f Hz (%.5f apart)", m.peaks[i].frequency, m.peaks[j].frequency, delta))
                }
            }
        }
        #expect(offenders.isEmpty, "decode must collapse duplicate peaks — found \(offenders.joined(separator: "; "))")
        #expect(m.peaks.count == (row["peakCount"] as! Int))
    }

    /// The surviving twin is the selected one; otherwise the selection points at a peak that no longer exists.
    @Test(arguments: cases.indices)
    func healKeepsTheSelectedTwin(_ index: Int) throws {
        let row = Self.cases[index]
        let m = try Self.decode(row)
        let hz = Float(row["twinHz"] as! Double), tolerance = Float(row["twinTolerance"] as! Double)
        let survivors = m.peaks.filter { abs($0.frequency - hz) < tolerance }
        #expect(survivors.count == 1, "expected exactly one peak at \(hz) Hz, got \(survivors.count)")
        if let survivor = survivors.first {
            #expect((m.selectedPeakIDs ?? []).contains(survivor.id), "the heal kept the unselected twin — selection now dangles")
        }
    }

    @Test(arguments: cases.indices)
    func healLeavesNoDanglingIDs(_ index: Int) throws {
        let m = try Self.decode(Self.cases[index])
        let ids = Set(m.peaks.map(\.id))
        for id in (m.selectedPeakIDs ?? []) { #expect(ids.contains(id), "selectedPeakIDs references a removed peak: \(id)") }
        for id in (m.peakAnnotationOffsets ?? [:]).keys { #expect(ids.contains(id), "peakAnnotationOffsets references a removed peak: \(id)") }
        for id in (m.peakModeOverrides ?? [:]).keys { #expect(ids.contains(id), "peakModeOverrides references a removed peak: \(id)") }
    }

    /// The saved-measurements store repairs itself on load, so the decoder reports that it healed something.
    @Test(arguments: cases.indices)
    func healIsReportedSoTheStoreCanForceASave(_ index: Int) throws {
        #expect(try Self.decode(Self.cases[index]).wasHealed)
    }

    /// The heal marker is transient state, not part of the file format; the corrected peaks are what is written.
    @Test(arguments: cases.indices)
    func healFlagIsNotSerialised(_ index: Int) throws {
        let m = try Self.decode(Self.cases[index])
        let reencoded = try TapToneAnalyzer.encodeMeasurements([m])
        let json = try #require(String(data: reencoded, encoding: .utf8))
        #expect(!json.contains("wasHealed"), "the heal marker must not round-trip into the .guitartap format")
        let roundTripped = try #require(try TapToneAnalyzer.decodeMeasurements(reencoded).first)
        #expect(roundTripped.peaks.count == m.peaks.count, "re-encoding a healed measurement must persist the corrected peak list")
    }
}
