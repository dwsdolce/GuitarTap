//
//  MeasurementCodableTests.swift
//  GuitarTapTests
//
//  JSON round-trip tests for TapToneMeasurement, ResonantPeak, and SpectrumSnapshot.
//  These tests verify that the Codable conformances preserve all fields through
//  encode → decode without loss.
//
//  Also loads the real test fixture (Tests/chris-1771351833.json) to confirm
//  the production JSON format decodes without error.
//
//  Test plan coverage: R1–R6, R11–R14
//
// @parity test/measurement-codable

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - SpectrumSnapshot binary round-trip
// ---------------------------------------------------------------------------

@Suite("SpectrumSnapshotCodable")
@MainActor
struct SpectrumSnapshotCodableTests {

    /// New saves must use compact Base64 binary keys (`frequenciesData` / `magnitudesData`).
    @Test func snapshot_encodesAsCompactBinary() throws {
        let snap = SpectrumSnapshot(
            frequencies: [100.0, 200.0, 300.0],
            magnitudes: [-20.0, -30.0, -40.0],
            minFreq: 50, maxFreq: 500, minDB: -100, maxDB: 0, isLogarithmic: false
        )
        let data = try JSONEncoder().encode(snap)
        let json = try #require(String(data: data, encoding: .utf8))
        // New format must contain the binary keys, not the verbose array keys
        #expect(json.contains("\"frequenciesData\""), "Should encode using compact binary key")
        #expect(json.contains("\"magnitudesData\""),  "Should encode using compact binary key")
        #expect(!json.contains("\"frequencies\":["),  "Should not write legacy array key")
    }

    /// Round-trip through the new binary format preserves float values exactly.
    @Test func snapshot_binaryRoundTrip_preservesValues() throws {
        let original = SpectrumSnapshot(
            frequencies: [43.066, 86.132, 129.199, 172.266],
            magnitudes: [-80.5, -45.2, -30.1, -22.7],
            minFreq: 20, maxFreq: 1000, minDB: -100, maxDB: 0, isLogarithmic: false,
            guitarType: .classical, measurementType: .classical
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpectrumSnapshot.self, from: data)

        #expect(decoded.frequencies.count == original.frequencies.count)
        #expect(decoded.magnitudes.count  == original.magnitudes.count)
        for (a, b) in zip(decoded.frequencies, original.frequencies) {
            #expect(a == b, "Frequency values must survive binary round-trip exactly")
        }
        for (a, b) in zip(decoded.magnitudes, original.magnitudes) {
            #expect(a == b, "Magnitude values must survive binary round-trip exactly")
        }
        #expect(decoded.guitarType      == original.guitarType)
        #expect(decoded.measurementType == original.measurementType)
    }

    /// Old files that contain `"frequencies"` / `"magnitudes"` JSON arrays still decode.
    @Test func snapshot_legacyArrayFormat_decodesCorrectly() throws {
        let legacyJSON = """
        {
          "frequencies": [100.0, 200.0, 300.0],
          "magnitudes": [-20.0, -30.0, -40.0],
          "minFreq": 50.0, "maxFreq": 500.0,
          "minDB": -100.0, "maxDB": 0.0,
          "isLogarithmic": false
        }
        """
        let data = try #require(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(SpectrumSnapshot.self, from: data)
        #expect(decoded.frequencies.count == 3)
        #expect(abs(decoded.frequencies[1] - 200.0) < 0.001)
        #expect(abs(decoded.magnitudes[2] - (-40.0)) < 0.001)
    }

    /// Old files that name the measurement with the pre-rename `"tapLocation"` key still decode
    /// into `measurementName`.
    ///
    /// This was covered only by accident until 2026-07-21: the Python copy of the
    /// `contreras-classical` fixture still carried `tapLocation` while the Swift and web copies had
    /// been updated to `measurementName`, so the three platforms' "same" parity test silently
    /// exercised different branches. The fixture is now byte-identical everywhere and the fallback
    /// is pinned deliberately, here and in the Python/web twins.
    @Test func measurement_legacyTapLocationKey_decodesAsMeasurementName() throws {
        let legacyJSON = """
        {
          "id": "6B29FC40-CA47-1067-B31D-00DD010662DA",
          "timestamp": 1774731564,
          "peaks": [],
          "tapLocation": "Contreras Classical"
        }
        """
        let data = try #require(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(TapToneMeasurement.self, from: data)

        #expect(decoded.measurementName == "Contreras Classical",
                "Legacy tapLocation must populate measurementName")
    }

    /// The writer is minimal-canonical: it never emits the legacy key, even for a file that
    /// arrived carrying it. (Reader is tolerant, writer is strict.)
    @Test func measurement_legacyTapLocationKey_isNeverWrittenBack() throws {
        let legacyJSON = """
        {
          "id": "6B29FC40-CA47-1067-B31D-00DD010662DA",
          "timestamp": 1774731564,
          "peaks": [],
          "tapLocation": "Contreras Classical"
        }
        """
        let data = try #require(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(TapToneMeasurement.self, from: data)
        let reencoded = try JSONEncoder().encode(decoded)
        let json = try #require(String(data: reencoded, encoding: .utf8))

        #expect(!json.contains("tapLocation"), "Writer must not emit the legacy key")
        #expect(json.contains("measurementName"), "Writer must emit the canonical key")
    }

    /// Compact binary encoding is significantly smaller than pretty-printed legacy encoding.
    @Test func snapshot_binaryEncoding_isSmallerThanPrettyPrintedLegacy() throws {
        // Use a realistic FFT bin count: 65536 / 2 = 32768
        let count = 32768
        let freqs = (0..<count).map { Float($0) * 1.4648 }        // realistic Hz spacing
        let mags  = (0..<count).map { Float(-80 + sin(Double($0) * 0.01) * 30) }

        let snap = SpectrumSnapshot(
            frequencies: freqs, magnitudes: mags,
            minFreq: 20, maxFreq: 24000, minDB: -100, maxDB: 0, isLogarithmic: false
        )

        // New binary encoding
        let binaryEncoder = JSONEncoder()
        let binaryData = try binaryEncoder.encode(snap)

        // Old encoding: pretty-printed [Float] arrays as the app used to write them
        struct LegacySnap: Encodable {
            let frequencies: [Float]; let magnitudes: [Float]
            let minFreq: Float; let maxFreq: Float
            let minDB: Float; let maxDB: Float; let isLogarithmic: Bool
        }
        let legacyEncoder = JSONEncoder()
        legacyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let legacyData = try legacyEncoder.encode(
            LegacySnap(frequencies: freqs, magnitudes: mags,
                       minFreq: 20, maxFreq: 24000, minDB: -100, maxDB: 0, isLogarithmic: false)
        )

        // Binary (Base64) should be at least 2× smaller than pretty-printed decimal text.
        // Actual ratio is ~2.8× for realistic FFT data; use 2× as a conservative floor.
        #expect(binaryData.count * 2 < legacyData.count,
                "Binary (\(binaryData.count) B) should be ≥2× smaller than pretty-printed legacy (\(legacyData.count) B)")
    }
}

// ---------------------------------------------------------------------------
// MARK: - ResonantPeak round-trip
// ---------------------------------------------------------------------------

@Suite("ResonantPeakCodable")
@MainActor
struct ResonantPeakCodableTests {

    @Test func resonantPeak_roundTrip_preservesAllFields() throws {
        let original = ResonantPeak(
            frequency: 195.5,
            magnitude: -22.3,
            quality: 18.7,
            bandwidth: 10.4,
            pitchNote: "G3",
            pitchCents: -12.5,
            pitchFrequency: 196.0
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ResonantPeak.self, from: data)

        #expect(decoded.id == original.id)
        #expect(abs(decoded.frequency - original.frequency) < 0.001)
        #expect(abs(decoded.magnitude - original.magnitude) < 0.001)
        #expect(abs(decoded.quality - original.quality) < 0.001)
        #expect(abs(decoded.bandwidth - original.bandwidth) < 0.001)
        #expect(decoded.pitchNote == original.pitchNote)
        #expect(decoded.pitchCents == original.pitchCents)
        #expect(decoded.pitchFrequency == original.pitchFrequency)
    }

    @Test func resonantPeak_nilPitchFields_roundTrip() throws {
        let original = ResonantPeak(frequency: 100, magnitude: -30)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ResonantPeak.self, from: data)
        #expect(decoded.pitchNote == nil)
        #expect(decoded.pitchCents == nil)
        #expect(decoded.pitchFrequency == nil)
    }
}

// ---------------------------------------------------------------------------
// MARK: - TapToneMeasurement round-trip  (R3)
// ---------------------------------------------------------------------------

@Suite("TapToneMeasurementCodable")
@MainActor
struct TapToneMeasurementCodableTests {

    private func makeFullMeasurement() -> TapToneMeasurement {
        let peak1 = ResonantPeak(frequency: 100, magnitude: -25, quality: 15, bandwidth: 6.7)
        let peak2 = ResonantPeak(frequency: 195, magnitude: -20, quality: 22, bandwidth: 8.9,
                                 pitchNote: "G3", pitchCents: 5.0, pitchFrequency: 196.0)

        let snapshot = SpectrumSnapshot(
            frequencies: [50, 100, 150, 200],
            magnitudes: [-80, -25, -60, -20],
            minFreq: 50, maxFreq: 500,
            minDB: -100, maxDB: 0,
            isLogarithmic: false,
            showUnknownModes: false,
            guitarType: .acoustic,
            measurementType: .acoustic
        )

        let annotationOffset = CGPoint(x: 12, y: -8)
        let overrides: [UUID: String] = [peak1.id: "Air"]

        return TapToneMeasurement(
            peaks: [peak1, peak2],
            decayTime: 0.75,
            measurementName: "Bridge",
            notes: "Test measurement",
            spectrum: snapshot,
            annotationOffsets: [peak1.id: annotationOffset],
            tapDetectionThreshold: -40,
            numberOfTaps: 3,
            selectedLongitudinalPeakID: peak1.id,
            selectedCrossPeakID: peak2.id,
            selectedFlcPeakID: nil,
            longitudinalSnapshot: snapshot,
            crossSnapshot: nil,
            flcSnapshot: nil,
            selectedPeakIDs: [peak1.id],
            annotationVisibilityMode: .selected,
            peakModeOverrides: overrides,
            microphoneName: "Built-in Microphone",
            microphoneUID: "BuiltIn_Bottom",
            calibrationName: nil,
            sampleRate: 48000
        )
    }

    // R3: Full round-trip preserves all non-transient fields.
    @Test func fullMeasurement_roundTrip_preservesAllFields() throws {
        let original = makeFullMeasurement()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(TapToneMeasurement.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.peaks.count == 2)
        #expect(abs(decoded.peaks[0].frequency - original.peaks[0].frequency) < 0.001)
        #expect(decoded.decayTime == original.decayTime)
        #expect(decoded.measurementName == original.measurementName)
        #expect(decoded.notes == original.notes)
        #expect(decoded.tapDetectionThreshold == original.tapDetectionThreshold)
        #expect(decoded.numberOfTaps == original.numberOfTaps)
        #expect(decoded.microphoneName == original.microphoneName)
        #expect(decoded.microphoneUID == original.microphoneUID)
        #expect(decoded.sampleRate == original.sampleRate)
        #expect(decoded.annotationVisibilityMode == original.annotationVisibilityMode)
        // selectedPeakIDs must round-trip
        #expect(decoded.selectedPeakIDs == original.selectedPeakIDs)
        // selectedLongitudinalPeakID
        #expect(decoded.selectedLongitudinalPeakID == original.selectedLongitudinalPeakID)
    }

    // Empty (nil) peakAnnotationOffsets encodes to an empty marker and decodes to nil.
    // A nil sampleRate is omitted from JSON, and a file with no sampleRate key
    // (saved before the field existed) decodes to nil — backward compatible.
    @Test func missingSampleRate_decodesAsNil() throws {
        let original = TapToneMeasurement(peaks: [])  // sampleRate defaults to nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(original)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("sampleRate"), "nil sampleRate must be omitted via encodeIfPresent")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(TapToneMeasurement.self, from: data)
        #expect(decoded.sampleRate == nil)
    }

    @Test func emptyAnnotationOffsets_roundTrip() throws {
        let measurement = TapToneMeasurement(peaks: [])
        let data = try JSONEncoder().encode(measurement)
        let decoded = try JSONDecoder().decode(TapToneMeasurement.self, from: data)
        #expect(decoded.peakAnnotationOffsets == nil,
                "nil annotationOffsets should round-trip as nil")
    }

    // peakAnnotationOffsets CGPoint dictionary survives the round-trip.
    @Test func annotationOffsets_roundTrip_preserved() throws {
        let peak = ResonantPeak(frequency: 200, magnitude: -20)
        let measurement = TapToneMeasurement(
            peaks: [peak],
            annotationOffsets: [peak.id: CGPoint(x: 15.5, y: -8.25)]
        )
        let data = try JSONEncoder().encode(measurement)
        let decoded = try JSONDecoder().decode(TapToneMeasurement.self, from: data)
        let offset = decoded.peakAnnotationOffsets?[peak.id]
        #expect(offset != nil, "Annotation offset should survive round-trip")
        #expect(abs((offset?.x ?? 0) - 15.5) < 0.001)
        #expect(abs((offset?.y ?? 0) - (-8.25)) < 0.001)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Annotation offsets on TapToneMeasurement (D1)
//
// Mirrors Python TestAnnotationOffsets - D1 multi-peak case.
// (D2 single-peak round-trip is already covered by annotationOffsets_roundTrip_preserved above.)
// ---------------------------------------------------------------------------

@Suite("AnnotationOffsetsCodable")
@MainActor
struct AnnotationOffsetsCodableTests {

    // D1: Multiple peaks can each have independent annotation offsets.
    @Test func annotationOffsets_multiplePeaks_storedPerPeak() {
        let p1 = ResonantPeak(frequency: 200, magnitude: -30)
        let p2 = ResonantPeak(frequency: 300, magnitude: -28)
        let measurement = TapToneMeasurement(
            peaks: [p1, p2],
            annotationOffsets: [p1.id: CGPoint(x: 200, y: -40), p2.id: CGPoint(x: 300, y: -35)]
        )
        #expect(measurement.peakAnnotationOffsets?[p1.id] != nil, "p1 should have an offset")
        #expect(measurement.peakAnnotationOffsets?[p2.id] != nil, "p2 should have an offset")
        let offset1 = measurement.peakAnnotationOffsets![p1.id]!
        let offset2 = measurement.peakAnnotationOffsets![p2.id]!
        #expect(abs(offset1.x - 200) < 0.01)
        #expect(abs(offset1.y - (-40)) < 0.01)
        #expect(abs(offset2.x - 300) < 0.01)
        #expect(abs(offset2.y - (-35)) < 0.01)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Peak selection on TapToneMeasurement (D3)
//
// Mirrors Python TestPeakSelection.
// ---------------------------------------------------------------------------

@Suite("PeakSelectionOnMeasurement")
@MainActor
struct PeakSelectionOnMeasurementTests {

    // D3: selectedPeakIDs is stored and round-trips through JSON.
    @Test func selectedPeakIDs_storedAndRoundTrip() throws {
        let p1 = ResonantPeak(frequency: 95, magnitude: -25)
        let p2 = ResonantPeak(frequency: 195, magnitude: -28)
        let original = TapToneMeasurement(peaks: [p1, p2], selectedPeakIDs: [p1.id])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TapToneMeasurement.self, from: data)
        #expect(decoded.selectedPeakIDs == [p1.id], "selectedPeakIDs should survive round-trip")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Annotation visibility mode on TapToneMeasurement (D4–D6, CI5)
//
// Mirrors Python TestAnnotationVisibilityMode.
// ---------------------------------------------------------------------------

@Suite("AnnotationVisibilityModeCodable")
@MainActor
struct AnnotationVisibilityModeCodableTests {

    // D4: annotationVisibilityMode is stored and round-trips.
    @Test func annotationVisibilityMode_stored_andRoundTrips() throws {
        let original = TapToneMeasurement(peaks: [], annotationVisibilityMode: .all)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TapToneMeasurement.self, from: data)
        #expect(decoded.annotationVisibilityMode == .all)
    }

    // D5: All three visibility values encode/decode correctly.
    @Test func allVisibilityValues_surviveRoundTrip() throws {
        for mode: AnnotationVisibilityMode in [.all, .selected, .none] {
            let m = TapToneMeasurement(peaks: [], annotationVisibilityMode: mode)
            let data = try JSONEncoder().encode(m)
            let decoded = try JSONDecoder().decode(TapToneMeasurement.self, from: data)
            #expect(decoded.annotationVisibilityMode == mode,
                    "Visibility mode \(mode) should survive round-trip")
        }
    }

    // D6: nil annotationVisibilityMode is absent from JSON.
    @Test func nilVisibilityMode_notWrittenToJSON() throws {
        let m = TapToneMeasurement(peaks: [], annotationVisibilityMode: nil)
        let data = try JSONEncoder().encode(m)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("annotationVisibilityMode"),
                "nil annotationVisibilityMode should not appear in JSON")
    }

    // CI5: All three visibility mode values can be stored on a measurement.
    @Test func visibilityMode_cycle_allValuesStorable() {
        for mode: AnnotationVisibilityMode in [.all, .selected, .none] {
            let m = TapToneMeasurement(peaks: [], annotationVisibilityMode: mode)
            #expect(m.annotationVisibilityMode == mode)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Mode overrides on TapToneMeasurement (D7, D8)
//
// Mirrors Python TestModeOverrides.
// ---------------------------------------------------------------------------

@Suite("ModeOverridesCodable")
@MainActor
struct ModeOverridesCodableTests {

    // D7: peakModeOverrides keyed by peak UUID stores custom mode labels.
    @Test func modeOverrides_storedPerPeak() {
        let peak = ResonantPeak(frequency: 200, magnitude: -20)
        let m = TapToneMeasurement(peaks: [peak], peakModeOverrides: [peak.id: "Top"])
        #expect(m.peakModeOverrides?[peak.id] == "Top")
    }

    // D8: peakModeOverrides survive a JSON round-trip.
    @Test func modeOverrides_surviveRoundTrip() throws {
        let peak = ResonantPeak(frequency: 200, magnitude: -20)
        let original = TapToneMeasurement(peaks: [peak], peakModeOverrides: [peak.id: "Dipole"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TapToneMeasurement.self, from: data)
        #expect(decoded.peakModeOverrides?[peak.id] == "Dipole")
    }

    // Empty peakModeOverrides: nil overrides produce no key in JSON.
    @Test func nilOverrides_notWrittenToJSON() throws {
        let m = TapToneMeasurement(peaks: [])
        let data = try JSONEncoder().encode(m)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("\"peakModeOverrides\""),
                "nil peakModeOverrides should not appear in JSON")
    }

    // An `auto` entry in a FILE carries no label and means "no override", so it is dropped on read.
    // The app cannot produce one — overrides are label-only in memory, and clearing removes the key —
    // but a hand-edited or legacy file can, and both ports drop it the same way.
    @Test func autoOverrideEntry_isDroppedOnRead() throws {
        let peakID = UUID(uuidString: "5E2A8C7D-1111-2222-3333-444455556666")!
        let json = """
        [{"id":"00000000-0000-0000-0000-0000000000AA","timestamp":"2026-01-01T00:00:00Z","peaks":[],
          "peakModeOverrides":["\(peakID.uuidString)",{"type":"auto"}]}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([TapToneMeasurement].self, from: Data(json.utf8))
        #expect(decoded.first?.peakModeOverrides?[peakID] == nil,
                "an auto entry means no override, so it must not become one")
    }

    // The WIRE shape is `{"type":"assigned","label":…}` per entry, even though the label alone is
    // what lives in memory. Pins write parity with Python `to_dict()` and web `encode.ts`,
    // both of which emit the same wrapper — a silent change here would produce files the ports read
    // as having no overrides at all.
    @Test func overrides_areWrittenAsAssignedEntries() throws {
        let peak = ResonantPeak(frequency: 200, magnitude: -20)
        let m = TapToneMeasurement(peaks: [peak], peakModeOverrides: [peak.id: "Top"])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(m), as: UTF8.self)
        #expect(json.contains("\"type\":\"assigned\""), "each entry keeps its type tag")
        #expect(json.contains("\"label\":\"Top\""),      "each entry keeps its label")
    }

    // D9: legacy {uuidString: mode} object form (written by GuitarTap Python 1.0.x)
    // decodes into peakModeOverrides.  The canonical encoding is a flat array, but
    // older Python files used a JSON object keyed by the lowercase peak UUID; those
    // files must remain loadable rather than throwing a typeMismatch.
    @Test func legacyObjectFormOverrides_decode() throws {
        let peakID = UUID()
        let json = """
        [{
          "id": "\(UUID().uuidString)",
          "timestamp": "2026-01-01T00:00:00Z",
          "peaks": [],
          "peakModeOverrides": { "\(peakID.uuidString.lowercased())": { "type": "assigned", "label": "Back" } }
        }]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([TapToneMeasurement].self, from: Data(json.utf8))
        #expect(decoded.first?.peakModeOverrides?[peakID] == "Back")
    }

    // D10: a file produced by the GuitarTap Python build (canonical flat-array
    // overrides + "peakMinThreshold" key, lowercase peak UUID) decodes correctly.
    // This is the exact payload emitted by tap_tone_measurement.to_dict(); it
    // pins cross-implementation read parity.
    @Test func pythonWrittenFile_decodes() throws {
        let json = """
        [{"id":"00000000-0000-0000-0000-0000000000CC","timestamp":"2026-01-01T00:00:00Z","peaks":[],"peakModeOverrides":["5e2a8c7d-1111-2222-3333-444455556666",{"type":"assigned","label":"Top"}],"peakMinThreshold":-60.0}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([TapToneMeasurement].self, from: Data(json.utf8))
        let m = try #require(decoded.first)
        let pid = try #require(UUID(uuidString: "5e2a8c7d-1111-2222-3333-444455556666"))
        #expect(m.peakModeOverrides?[pid] == "Top")
        #expect(m.peakMinThreshold == -60.0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - selectedPeakIDs / selectedPeakFrequencies JSON fields (PS1–PS6)
//
// Mirrors Python TestPeakSelectionTracking.
// ---------------------------------------------------------------------------

@Suite("PeakSelectionTrackingCodable")
@MainActor
struct PeakSelectionTrackingCodableTests {

    // PS1: selectedPeakIDs is stored as an array of UUIDs.
    @Test func selectedPeakIDs_storedAsList() {
        let peaks = [ResonantPeak(frequency: 100, magnitude: -30),
                     ResonantPeak(frequency: 200, magnitude: -28),
                     ResonantPeak(frequency: 300, magnitude: -32)]
        let ids = [peaks[0].id, peaks[1].id]
        let m = TapToneMeasurement(peaks: peaks, selectedPeakIDs: ids)
        #expect(m.selectedPeakIDs == ids)
    }

    // PS2: selectedPeakFrequencies is parallel to selectedPeakIDs.
    @Test func selectedPeakFrequencies_parallelToIDs() {
        let p1 = ResonantPeak(frequency: 200, magnitude: -28)
        let p2 = ResonantPeak(frequency: 300, magnitude: -32)
        let m = TapToneMeasurement(peaks: [p1, p2], selectedPeakIDs: [p1.id])
        #expect(m.selectedPeakIDs == [p1.id])
    }

    // PS3: nil selectedPeakIDs means all peaks are treated as selected.
    @Test func nilSelectedPeakIDs_meansAllSelected() {
        let peaks = (0..<3).map { _ in ResonantPeak(frequency: 200, magnitude: -30) }
        let m = TapToneMeasurement(peaks: peaks, selectedPeakIDs: nil)
        #expect(m.selectedPeakIDs == nil)
    }

    // PS4: selectedPeakIDs survives JSON round-trip.
    @Test func selectedPeakIDs_roundTrip() throws {
        let peak = ResonantPeak(frequency: 200, magnitude: -28)
        let original = TapToneMeasurement(peaks: [peak], selectedPeakIDs: [peak.id])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TapToneMeasurement.self, from: data)
        #expect(decoded.selectedPeakIDs == [peak.id])
    }

    // PS5: (selectedPeakFrequencies is a computed/transient property in Swift
    // and not directly encoded; this test verifies selectedPeakIDs round-trip
    // with a known frequency for completeness.)
    @Test func selectedPeakIDs_withFrequency_roundTrip() throws {
        let peak = ResonantPeak(frequency: 440, magnitude: -20)
        let original = TapToneMeasurement(peaks: [peak], selectedPeakIDs: [peak.id])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TapToneMeasurement.self, from: data)
        #expect(decoded.selectedPeakIDs?.first == peak.id)
        // The decoded measurement should know the frequency of the surviving peak
        #expect(abs((decoded.peaks.first?.frequency ?? 0) - 440) < 0.001)
    }

    // PS6: Empty selectedPeakIDs encodes/decodes without crashing.
    @Test func emptySelectedPeakIDs_roundTrip() throws {
        let original = TapToneMeasurement(peaks: [], selectedPeakIDs: [])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TapToneMeasurement.self, from: data)
        // PS6: an empty selection is Select None — it reads back empty, not as "no selection saved".
        #expect(decoded.selectedPeakIDs == [])
    }
}

// ---------------------------------------------------------------------------
// MARK: - Spectrum snapshot storage on TapToneMeasurement
//
// Mirrors Python TestLiveTapPath (moved from test_frozen_peak_recalculation.py).
// ---------------------------------------------------------------------------

@Suite("SpectrumSnapshotOnMeasurement")
@MainActor
struct SpectrumSnapshotOnMeasurementTests {

    // A freshly created measurement with no snapshot has spectrumSnapshot == nil.
    @Test func spectrumSnapshot_newMeasurement_isNil() {
        let m = TapToneMeasurement(peaks: [])
        #expect(m.spectrumSnapshot == nil, "New measurement should not have a spectrum snapshot")
    }

    // A measurement created with a snapshot stores it.
    @Test func spectrumSnapshot_withSnapshot_stored() {
        let snap = SpectrumSnapshot(
            frequencies: [100, 200], magnitudes: [-40, -35],
            minFreq: 80, maxFreq: 300, minDB: -90, maxDB: -10, isLogarithmic: false
        )
        let m = TapToneMeasurement(peaks: [], spectrum: snap)
        #expect(m.spectrumSnapshot != nil, "Measurement should store the provided snapshot")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Fixture loading test  (R4)
// ---------------------------------------------------------------------------

@Suite("FixtureLoading")
@MainActor
struct FixtureLoadingTests {

    /// Reads a `.guitartap` fixture from the test bundle, falling back to the source tree.
    private func fixtureURL(_ name: String) -> URL? {
        Bundle.allBundles.lazy.compactMap { $0.url(forResource: name, withExtension: "guitartap") }.first
            ?? {
                let url = URL(fileURLWithPath: #file).deletingLastPathComponent()
                    .appendingPathComponent("\(name).guitartap")
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            }()
    }

    // Mode overrides, read from files the APPS actually wrote — one saved by Swift, one by Python.
    //
    // The other override tests use hand-built fixtures; these two are real files. The Python-written
    // one matters most: reading it proves cross-edition parity against bytes Swift did not produce.
    @Test(arguments: [
        ("annotation-override-1790037028", "Fred"),          // written by Swift
        ("annotation-override-python-1790037332", "Fred2"),  // written by Python
    ])
    func realOverrideFixture_decodesItsLabel(fixture: String, expectedLabel: String) throws {
        guard let url = fixtureURL(fixture) else {
            withKnownIssue("Fixture \(fixture).guitartap not found in bundle or source tree") { }
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let measurements = try decoder.decode([TapToneMeasurement].self, from: try Data(contentsOf: url))
        let overrides = try #require(measurements.first?.peakModeOverrides,
                                     "the fixture must carry peakModeOverrides")
        #expect(overrides.count == 1)
        #expect(overrides.values.first == expectedLabel,
                "the label must survive the wire shape, in memory, as the label alone")
        // And the peak it names must still be in the measurement.
        let peakID = try #require(overrides.keys.first)
        #expect(measurements.first?.peaks.contains { $0.id == peakID } == true,
                "the override must key a peak the file still contains")
    }

    // R4: The real test fixture (contreras-classical-1774731564.guitartap) must decode without error.
    // The fixture is a JSON array of TapToneMeasurement objects stored with the .guitartap extension.
    @Test func realFixture_decodesWithoutError() throws {
        // On device the test bundle is the only reliable source; on Mac the
        // fixture may also live next to the source tree.  Try bundle first so
        // this test works on both simulator/device and local Mac runs.
        let fixtureName = "contreras-classical-1774731564"
        let bundleURL = Bundle.allBundles
            .lazy
            .compactMap { $0.url(forResource: fixtureName, withExtension: "guitartap") }
            .first

        // Fall back to the source-relative path used during local development
        let sourceRelativeURL: URL? = {
            let thisFile = URL(fileURLWithPath: #file)
            let url = thisFile
                .deletingLastPathComponent()
                .appendingPathComponent("\(fixtureName).guitartap")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }()

        guard let fixtureURL = bundleURL ?? sourceRelativeURL else {
            // File not available (CI without fixture, or device without bundle resource)
            withKnownIssue("Fixture file not found in bundle or source tree") { }
            return
        }

        let jsonData = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Fixture is an array of measurements — must not throw
        let measurements = try decoder.decode([TapToneMeasurement].self, from: jsonData)

        // Sanity checks on the decoded content
        #expect(!measurements.isEmpty, "Fixture should contain at least one measurement")
        // All peaks across all measurements must have valid frequencies
        for measurement in measurements {
            for peak in measurement.peaks {
                #expect(peak.frequency > 0 && peak.frequency < 20000,
                        "Peak frequency \(peak.frequency) Hz should be in valid audio range")
            }
        }
    }

    /// Resolves the bundled or source-tree Contreras fixture URL, or nil when absent.
    private static func contrerasFixtureURL() -> URL? {
        let name = "contreras-classical-1774731564"
        if let bundled = Bundle.allBundles.lazy
            .compactMap({ $0.url(forResource: name, withExtension: "guitartap") }).first {
            return bundled
        }
        let local = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("\(name).guitartap")
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }

    // R4 (extended): the real fixture must decode -> re-encode -> re-decode with every
    // modeled field preserved, the legacy keys mapped on the way in, and the writer
    // emitting only the canonical key set. Pinned identically in the Python
    // TestFixtureLoading round-trip and the GuitarTapWeb g5-measurement-codable suite so
    // the three writers can't drift. The Contreras file is an OLD save, so this also
    // exercises legacy decode (peakThreshold, no sampleRate, extra ignored fields).
    @Test func realFixture_roundTripsAndCanonicalizes() throws {
        guard let url = Self.contrerasFixtureURL() else {
            withKnownIssue("Fixture file not found in bundle or source tree") { }
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let m = try decoder.decode([TapToneMeasurement].self, from: Data(contentsOf: url))[0]

        // Decode + legacy-mapping assertions.
        #expect(m.peaks.count == 44)
        #expect(m.peakMinThreshold == Float(-78))   // legacy "peakThreshold" -> peakMinThreshold
        #expect(m.sampleRate == nil)                 // absent -> unknown
        #expect(m.measurementName == "Contreras Classical")
        #expect(m.numberOfTaps == 10)
        let s = try #require(m.spectrumSnapshot)
        #expect(s.measurementType?.rawValue == "Classical Guitar")
        #expect(s.guitarType?.rawValue == "Classical")
        #expect(s.minFreq == 75 && s.maxFreq == 350 && s.minDB == -100 && s.maxDB == 0)
        #expect(abs(m.peaks[0].frequency - 212.24847) < 1e-3)
        #expect(m.peaks[0].pitchNote == "G#3")

        // Re-encode with the app's canonical encoder (matches saveMeasurement).
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode([m])
        let json = String(data: data, encoding: .utf8)!

        // Writer = minimal canonical: only current keys, never legacy ones.
        #expect(json.contains("\"peakMinThreshold\""))
        #expect(!json.contains("\"peakThreshold\""))
        #expect(!json.contains("\"hysteresisMargin\""))
        #expect(!json.contains("\"maxPeaks\""))
        #expect(json.contains("\"modeLabel\""))   // convenience label on top-level peaks
        #expect(json.contains("\"Top\""))          // peak 0 classifies as Top

        // Semantic round-trip: re-decoding preserves the modeled fields exactly.
        let again = try decoder.decode([TapToneMeasurement].self, from: data)[0]
        #expect(again.peaks.count == m.peaks.count)
        #expect(again.peakMinThreshold == m.peakMinThreshold)
        #expect(again.sampleRate == m.sampleRate)
        #expect(again.spectrumSnapshot?.frequencies == m.spectrumSnapshot?.frequencies)
        #expect(again.spectrumSnapshot?.magnitudes == m.spectrumSnapshot?.magnitudes)
        #expect(again.peaks.map(\.frequency) == m.peaks.map(\.frequency))
    }
}

// MARK: - The measurement's logic — the shared cases in `measurement-codable.json`
//
// The tap-tone ratio (TR), the mode label each peak is written with (ML), and the selection heal on
// decode (SH): the same cases as Python and the web.
// ---------------------------------------------------------------------------

private final class MeasurementLogicAnchor {}

@Suite("MeasurementLogic", .serialized)
@MainActor
struct MeasurementLogicTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: MeasurementLogicAnchor.self).url(forResource: "measurement-codable", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids(_ table: String) -> [String] {
        (data[table] as! [[String: Any]]).map { $0["id"] as! String }
    }

    static func row(_ table: String, _ id: String) -> [String: Any] {
        (data[table] as! [[String: Any]]).first { $0["id"] as! String == id }!
    }

    /// A case's measurement, and its peaks by the case's peak ids.
    static func measurement(_ row: [String: Any]) -> (TapToneMeasurement, [String: ResonantPeak]) {
        var byName: [String: ResonantPeak] = [:]
        let peaks = (row["peaks"] as! [[String: Any]]).map { p -> ResonantPeak in
            let peak = ResonantPeak(frequency: Float(p["frequency"] as! Double), magnitude: Float(p["magnitude"] as! Double))
            byName[p["id"] as! String] = peak
            return peak
        }
        let selected = (row["selected"] as? [String])?.map { byName[$0]!.id }
        var overrides: [UUID: String] = [:]
        for (name, label) in row["overrides"] as? [String: String] ?? [:] { overrides[byName[name]!.id] = label }
        let snapshot = SpectrumSnapshot(
            frequencies: [], magnitudes: [],
            minFreq: 50, maxFreq: 500, minDB: -100, maxDB: 0, isLogarithmic: false,
            guitarType: .classical, measurementType: .classical
        )
        let material = row["material"] as? Bool ?? false
        let m = TapToneMeasurement(
            peaks: peaks,
            spectrum: material ? nil : snapshot,
            longitudinalSnapshot: material ? snapshot : nil,
            selectedPeakIDs: selected,
            peakModeOverrides: overrides.isEmpty ? nil : overrides
        )
        return (m, byName)
    }

    @Test(arguments: ids("tapToneRatio"))
    func tapToneRatio(_ id: String) {
        let row = Self.row("tapToneRatio", id)
        let (m, byName) = Self.measurement(row)
        let tolerance = Self.data["ratioTolerance"] as! Double
        let expected = row["expect"] as? Double

        func matches(_ ratio: Float?) -> Bool {
            guard let expected else { return ratio == nil }
            return ratio.map { abs(Double($0) - expected) <= tolerance } ?? false
        }
        #expect(matches(m.tapToneRatio), "\(id): saved ratio \(String(describing: m.tapToneRatio)) — \(row["note"] as! String)")

        guard row["live"] as? Bool ?? false else { return }
        let savedType = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = savedType }
        TapDisplaySettings.measurementType = .classical
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        sut.cancellables.removeAll()
        sut.allPeaks = m.peaks
        sut.reclassifyPeaks()
        sut.selectedPeakIDs = Set(m.selectedPeakIDs ?? [])
        for (name, label) in row["overrides"] as? [String: String] ?? [:] { sut.setModeOverride(label, for: byName[name]!.id) }
        #expect(matches(sut.calculateTapToneRatio()),
                "\(id): live ratio \(String(describing: sut.calculateTapToneRatio())) — the saved and live ratios must agree")
    }

    @Test(arguments: ids("modeLabels"))
    func modeLabels(_ id: String) throws {
        let row = Self.row("modeLabels", id)
        let (m, _) = Self.measurement(row)
        // A file whose peaks already carry `storedLabels`: written, the labels set, read back.
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(m)) as? [String: Any])
        var peaks = try #require(json["peaks"] as? [[String: Any]])
        for (index, label) in (row["storedLabels"] as! [Any]).enumerated() {
            if let label = label as? String { peaks[index]["modeLabel"] = label } else { peaks[index].removeValue(forKey: "modeLabel") }
        }
        json["peaks"] = peaks
        let read = try JSONDecoder().decode(TapToneMeasurement.self, from: JSONSerialization.data(withJSONObject: json))
        let written = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(read)) as? [String: Any])
        let labels = (written["peaks"] as? [[String: Any]] ?? []).map { $0["modeLabel"] as? String }
        let expected = (row["expect"] as! [String]).map { Optional($0) }
        #expect(labels == expected, "\(id): written — \(row["note"] as! String)")
        let shown = read.peakModeLabels
        #expect(read.peaks.map { shown[$0.id] } == expected, "\(id): displayed — \(row["note"] as! String)")
    }

    @Test(arguments: ids("selectionHeal"))
    func selectionHeal(_ id: String) throws {
        let row = Self.row("selectionHeal", id)
        let (m, byName) = Self.measurement(row)
        let read = try TapToneAnalyzer.decodeMeasurements(TapToneAnalyzer.encodeMeasurements([m]))[0]
        #expect(read.wasHealed == row["expectHealed"] as! Bool, "\(id): healed — \(row["note"] as! String)")
        let expected = Set((row["expectSelected"] as! [String]).map { byName[$0]!.id })
        #expect(Set(read.selectedPeakIDs ?? []) == expected, "\(id): selection — \(row["note"] as! String)")
    }
}
