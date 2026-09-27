//
//  PeakDuplicateHealTests.swift
//  GuitarTapTests
//
//  The duplicate-peak defect: healing files saved with a duplicate peak.
//
//  Fixing findPeaks stops NEW corruption. Every .guitartap file already written still
//  carries the duplicate peak, and loaded peaks are authoritative — they are never
//  re-derived — so old files would keep rendering an extra Analysis Results row
//  forever. The repair therefore happens at DECODE time, in the per-measurement
//  decoder, so it covers both reading a .guitartap file and reading the
//  saved-measurements store, and no future read path can bypass it.
//
//  Rule: collapse peaks closer than peakProximityHz, keeping (1) the peak whose id is
//  in selectedPeakIDs, else (2) the higher magnitude, else (3) the first. findPeaks'
//  own dedup guarantees legitimately saved peaks are >= 2 Hz apart, so any closer pair
//  is by definition corruption.
//
//  Authored against the UNFIXED code. Two kinds of test live here:
//
//    RED NOW — fail until the heal exists:
//      decodedMeasurementHasNoDuplicatePeaks, healKeepsTheSelectedTwin,
//      healIsReportedSoTheStoreCanForceASave
//
//    GUARDS — pass now and must keep passing; they constrain what the heal may do
//    rather than demanding it exist:
//      healLeavesNoDanglingIDs      (the heal must not orphan selection/offset/override ids)
//      healFlagIsNotSerialised      (the transient flag must never reach the file format)
//
//  A guard passing today is not evidence of anything; its value is entirely in step 8.
//
// @parity test/peak-heal

import Testing
import Foundation
@testable import GuitarTap

/// The Swift-captured fixture also used by the findPeaks regression: 50 saved peaks,
/// one of which is a bit-identical twin at 240.10170 Hz.
private let fixtureStem = "dws-2024-umik-1-swift-mac-1784225155"

// Anchors Bundle(for:) to the GuitarTapTests bundle so the fixture loads on every destination
// (iPad/iPhone too), not just the macOS host: #filePath resolves to the build machine's source tree,
// which does not exist on a device. The synchronized GuitarTapTests folder already bundles the fixture
// (the same file loads this way in PeakSelectionPersistenceTests / PeakFindingTests).
private final class FixtureAnchor {}

private func loadFixtureData() throws -> Data {
    let url = try #require(Bundle(for: FixtureAnchor.self)
        .url(forResource: fixtureStem, withExtension: "guitartap"))
    return try Data(contentsOf: url)
}

@Suite("Duplicate-peak heal on decode")
struct PeakDuplicateHealTests {

    @Test func decodedMeasurementHasNoDuplicatePeaks() throws {
        let m = try #require(try TapToneAnalyzer.decodeMeasurements(loadFixtureData()).first)

        var offenders: [String] = []
        for i in m.peaks.indices {
            for j in m.peaks.indices where j > i {
                let delta = abs(m.peaks[i].frequency - m.peaks[j].frequency)
                if delta < TapToneAnalyzer.peakProximityHz {
                    offenders.append(String(format: "%.5f Hz / %.5f Hz (%.5f apart)",
                                            m.peaks[i].frequency, m.peaks[j].frequency, delta))
                }
            }
        }
        #expect(offenders.isEmpty,
                "decode must collapse duplicate peaks — found \(offenders.joined(separator: "; "))")
        #expect(m.peaks.count == 49, "expected 49 peaks after healing 50, got \(m.peaks.count)")
    }

    @Test func healKeepsTheSelectedTwin() throws {
        let m = try #require(try TapToneAnalyzer.decodeMeasurements(loadFixtureData()).first)

        // The surviving 240.1 Hz peak must be the one that was claimed as a mode winner,
        // otherwise the selection silently points at a peak that no longer exists.
        let survivors = m.peaks.filter { abs($0.frequency - 240.10170) < 0.01 }
        #expect(survivors.count == 1, "expected exactly one 240.1 Hz peak, got \(survivors.count)")

        if let survivor = survivors.first {
            #expect((m.selectedPeakIDs ?? []).contains(survivor.id),
                    "the heal kept the unselected twin — selection now dangles")
        }
    }

    @Test func healLeavesNoDanglingIDs() throws {
        let m = try #require(try TapToneAnalyzer.decodeMeasurements(loadFixtureData()).first)
        let ids = Set(m.peaks.map(\.id))

        for id in (m.selectedPeakIDs ?? []) {
            #expect(ids.contains(id), "selectedPeakIDs references a removed peak: \(id)")
        }
        for id in (m.peakAnnotationOffsets ?? [:]).keys {
            #expect(ids.contains(id), "peakAnnotationOffsets references a removed peak: \(id)")
        }
        for id in (m.peakModeOverrides ?? [:]).keys {
            #expect(ids.contains(id), "peakModeOverrides references a removed peak: \(id)")
        }
    }

    // The saved-measurements store must repair itself on load, which means the decoder
    // has to report that it healed something.
    @Test func healIsReportedSoTheStoreCanForceASave() throws {
        let m = try #require(try TapToneAnalyzer.decodeMeasurements(loadFixtureData()).first)

        // Probed reflectively on purpose: the property does not exist yet, and referencing
        // it directly would be a COMPILE error, which would block the whole test target
        // rather than producing a failing test. Replace with a direct `m.wasHealed` check
        // once the API lands in step 5.
        let healFlag = Mirror(reflecting: m).children
            .first { $0.label == "wasHealed" }?.value as? Bool

        let message = "decode healed a duplicate but did not report it (wasHealed = "
            + "\(String(describing: healFlag))); the saved-measurements store cannot know to "
            + "force a save"
        #expect(healFlag == true, Comment(rawValue: message))
    }

    // The heal marker is transient state, not part of the file format. A flag written to
    // disk would be meaningless on the next read and would pollute the format.
    @Test func healFlagIsNotSerialised() throws {
        let m = try #require(try TapToneAnalyzer.decodeMeasurements(loadFixtureData()).first)
        let reencoded = try TapToneAnalyzer.encodeMeasurements([m])
        let json = try #require(String(data: reencoded, encoding: .utf8))

        #expect(!json.contains("wasHealed"),
                "the heal marker must not round-trip into the .guitartap format")

        // And the corrected form is what gets written — the twin must not come back.
        let roundTripped = try #require(try TapToneAnalyzer.decodeMeasurements(reencoded).first)
        #expect(roundTripped.peaks.count == m.peaks.count,
                "re-encoding a healed measurement must persist the corrected peak list")
    }
}