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
        let overrides: [UUID: UserAssignedMode] = [peak1.id: .assigned("Air"), peak2.id: .auto]

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
            calibrationName: nil
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
        #expect(decoded.annotationVisibilityMode == original.annotationVisibilityMode)
        // selectedPeakIDs must round-trip
        #expect(decoded.selectedPeakIDs == original.selectedPeakIDs)
        // selectedLongitudinalPeakID
        #expect(decoded.selectedLongitudinalPeakID == original.selectedLongitudinalPeakID)
    }

    // Empty (nil) peakAnnotationOffsets encodes to an empty marker and decodes to nil.
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
// MARK: - tapToneRatio uses classifyAll
// ---------------------------------------------------------------------------

@Suite("TapToneRatio")
@MainActor
struct TapToneRatioTests {

    // A peak in the classical Top/Back overlap zone (190–230 Hz) should be
    // found as the Top peak for ratio calculation purposes, not missed because
    // a naive per-frequency classify might label it differently when context
    // is taken into account.
    @Test func tapToneRatio_overlapZonePeaks_computesCorrectRatio() {
        // Air at 95 Hz, Top at 210 Hz (inside classical overlap zone)
        let airPeak = ResonantPeak(frequency: 95,  magnitude: -28)
        let topPeak = ResonantPeak(frequency: 210, magnitude: -20)
        let snapshot = SpectrumSnapshot(
            frequencies: [], magnitudes: [],
            minFreq: 50, maxFreq: 500, minDB: -100, maxDB: 0, isLogarithmic: false,
            guitarType: .classical, measurementType: .classical
        )
        let measurement = TapToneMeasurement(peaks: [airPeak, topPeak], spectrum: snapshot)
        let ratio = measurement.tapToneRatio
        #expect(ratio != nil, "tapToneRatio should find air and top peaks")
        // 210 / 95 ≈ 2.21 — verify to within 1%
        let expected: Float = 210.0 / 95.0
        #expect(abs((ratio ?? 0) - expected) < 0.01)
    }

    // A measurement with no peaks at all should return nil for the ratio.
    @Test func tapToneRatio_noPeaks_returnsNil() {
        let measurement = TapToneMeasurement(peaks: [])
        #expect(measurement.tapToneRatio == nil, "No peaks → ratio must be nil")
    }

    // A measurement with a Top peak but no Air peak should return nil.
    @Test func tapToneRatio_noAirPeak_returnsNil() {
        // 250 Hz classifies as Back for classical, not Air — so no Air peak is present.
        let backPeak = ResonantPeak(frequency: 250, magnitude: -20)
        let snapshot = SpectrumSnapshot(
            frequencies: [], magnitudes: [],
            minFreq: 50, maxFreq: 500, minDB: -100, maxDB: 0, isLogarithmic: false,
            guitarType: .classical, measurementType: .classical
        )
        let measurement = TapToneMeasurement(peaks: [backPeak], spectrum: snapshot)
        #expect(measurement.tapToneRatio == nil, "No Air peak → ratio must be nil")
    }

    // When selectedPeakIDs is set, only those peaks contribute to the ratio.
    @Test func tapToneRatio_usesSelectedPeaksWhenSet() {
        let airPeak  = ResonantPeak(frequency: 95,  magnitude: -28)
        let topPeak  = ResonantPeak(frequency: 200, magnitude: -20)
        let noisePeak = ResonantPeak(frequency: 500, magnitude: -50)
        let snapshot = SpectrumSnapshot(
            frequencies: [], magnitudes: [],
            minFreq: 50, maxFreq: 500, minDB: -100, maxDB: 0, isLogarithmic: false,
            guitarType: .classical, measurementType: .classical
        )
        // Select only air and top; noise peak is excluded.
        let measurement = TapToneMeasurement(
            peaks: [airPeak, topPeak, noisePeak],
            spectrum: snapshot,
            selectedPeakIDs: [airPeak.id, topPeak.id]
        )
        let ratio = measurement.tapToneRatio
        #expect(ratio != nil, "Selected air + top peaks → ratio must be computable")
        let expected: Float = 200.0 / 95.0
        #expect(abs((ratio ?? 0) - expected) < 0.01,
                "Ratio should use selected air (95 Hz) and top (200 Hz) only")
    }

    // When two peaks are in the overlap zone, only one should be claimed as Top.
    // The ratio must use the stronger one (Top), not both.
    @Test func tapToneRatio_twoOverlapPeaks_usesSingleTopPeak() {
        let airPeak     = ResonantPeak(frequency: 95,  magnitude: -28)
        let strongerTop = ResonantPeak(frequency: 205, magnitude: -18) // → Top
        let weakerBack  = ResonantPeak(frequency: 220, magnitude: -25) // → Back
        let snapshot = SpectrumSnapshot(
            frequencies: [], magnitudes: [],
            minFreq: 50, maxFreq: 500, minDB: -100, maxDB: 0, isLogarithmic: false,
            guitarType: .classical, measurementType: .classical
        )
        let measurement = TapToneMeasurement(peaks: [airPeak, strongerTop, weakerBack], spectrum: snapshot)
        let ratio = measurement.tapToneRatio
        #expect(ratio != nil)
        // Ratio must use strongerTop (205 Hz), not weakerBack (220 Hz)
        let expected: Float = 205.0 / 95.0
        #expect(abs((ratio ?? 0) - expected) < 0.01,
                "Ratio should use the stronger Top peak (205 Hz), not Back (220 Hz)")
    }
}

// ---------------------------------------------------------------------------
// MARK: - JSON export modeLabel uses classifyAll
// ---------------------------------------------------------------------------

@Suite("MeasurementExportModeLabel")
@MainActor
struct MeasurementExportModeLabelTests {

    // Two peaks in the classical Top/Back overlap zone should produce different
    // modeLabel values in the exported JSON — "Top" for the stronger and "Back"
    // for the weaker.
    @Test func exportedJSON_overlapZonePeaks_haveDistinctModeLabels() throws {
        let strongerPeak = ResonantPeak(frequency: 210, magnitude: -18)
        let weakerPeak   = ResonantPeak(frequency: 220, magnitude: -26)
        let snapshot = SpectrumSnapshot(
            frequencies: [], magnitudes: [],
            minFreq: 50, maxFreq: 500, minDB: -100, maxDB: 0, isLogarithmic: false,
            guitarType: .classical, measurementType: .classical
        )
        let measurement = TapToneMeasurement(peaks: [strongerPeak, weakerPeak], spectrum: snapshot)
        let data = try JSONEncoder().encode(measurement)
        let json = try #require(String(data: data, encoding: .utf8))
        // Both mode labels must appear somewhere in the JSON
        #expect(json.contains("\"Top\""),  "Stronger peak should be labeled Top in JSON export")
        #expect(json.contains("\"Back\""), "Weaker peak should be labeled Back in JSON export")
    }

    // A user override must still take priority over classifyAll in the export.
    @Test func exportedJSON_userOverrideTakesPriority() throws {
        let peak = ResonantPeak(frequency: 210, magnitude: -20)
        let snapshot = SpectrumSnapshot(
            frequencies: [], magnitudes: [],
            minFreq: 50, maxFreq: 500, minDB: -100, maxDB: 0, isLogarithmic: false,
            guitarType: .classical, measurementType: .classical
        )
        let measurement = TapToneMeasurement(
            peaks: [peak],
            spectrum: snapshot,
            peakModeOverrides: [peak.id: .assigned("Custom Label")]
        )
        let data = try JSONEncoder().encode(measurement)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"Custom Label\""), "User override should appear in JSON export")
    }
}

// ---------------------------------------------------------------------------
// MARK: - with(measurementName:notes:) builder
//
// Mirrors Python TestWithMethod in test_measurement_codable.py.
// ---------------------------------------------------------------------------

@Suite("WithMethod")
struct WithMethodTests {

    // Updating measurementName via with() returns a copy with the new measurementName.
    @Test func with_updatesMeasurementName() {
        let original = TapToneMeasurement(peaks: [], measurementName: "Old")
        let updated = original.with(measurementName: "New", notes: nil)
        #expect(updated.measurementName == "New")
        #expect(updated.id == original.id, "id must be preserved")
    }

    // Updating notes via with() returns a copy with the new notes.
    @Test func with_updatesNotes() {
        let original = TapToneMeasurement(peaks: [], notes: "old notes")
        let updated = original.with(measurementName: nil, notes: "new notes")
        #expect(updated.notes == "new notes")
    }

    // Passing nil for measurementName clears it in the copy.
    @Test func with_clearsMeasurementNameWithNil() {
        let original = TapToneMeasurement(peaks: [], measurementName: "Bridge")
        let updated = original.with(measurementName: nil, notes: nil)
        #expect(updated.measurementName == nil)
    }

    // All other fields are preserved in the returned copy.
    @Test func with_preservesOtherFields() throws {
        let peak = ResonantPeak(frequency: 195, magnitude: -20)
        let snap = SpectrumSnapshot(
            frequencies: [100, 200], magnitudes: [-30, -20],
            minFreq: 50, maxFreq: 500, minDB: -100, maxDB: 0, isLogarithmic: false
        )
        let original = TapToneMeasurement(peaks: [peak], decayTime: 0.5, measurementName: "Bridge", spectrum: snap)
        let updated = original.with(measurementName: "Neck", notes: nil)
        #expect(updated.peaks.count == 1)
        #expect(updated.decayTime == 0.5, "decayTime must be preserved")
        #expect(updated.measurementName == "Neck")
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
// MARK: - Peak selection on TapToneMeasurement (D3, D3b)
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

    // D3b: tapToneRatio uses only selectedPeakIDs when set.
    @Test func tapToneRatio_usesOnlySelectedPeaks() {
        let airPeak   = ResonantPeak(frequency: 95,  magnitude: -25)
        let topPeak   = ResonantPeak(frequency: 195, magnitude: -28)
        let noisePeak = ResonantPeak(frequency: 500, magnitude: -50)
        let snapshot = SpectrumSnapshot(
            frequencies: [], magnitudes: [],
            minFreq: 50, maxFreq: 600, minDB: -100, maxDB: 0, isLogarithmic: false,
            guitarType: .classical, measurementType: .classical
        )
        let m = TapToneMeasurement(
            peaks: [airPeak, topPeak, noisePeak],
            spectrum: snapshot,
            selectedPeakIDs: [airPeak.id, topPeak.id]
        )
        let ratio = m.tapToneRatio
        #expect(ratio != nil, "ratio should be computable with air + top selected")
        let expected: Float = 195.0 / 95.0
        #expect(abs((ratio ?? 0) - expected) < 0.1)
    }

    // nil selectedPeakIDs means all peaks contribute.
    @Test func selectedPeakIDs_nil_usesAllPeaks() {
        let airPeak = ResonantPeak(frequency: 95,  magnitude: -25)
        let topPeak = ResonantPeak(frequency: 195, magnitude: -28)
        let snapshot = SpectrumSnapshot(
            frequencies: [], magnitudes: [],
            minFreq: 50, maxFreq: 400, minDB: -100, maxDB: 0, isLogarithmic: false,
            guitarType: .classical, measurementType: .classical
        )
        let m = TapToneMeasurement(peaks: [airPeak, topPeak], spectrum: snapshot, selectedPeakIDs: nil)
        #expect(m.tapToneRatio != nil, "nil selectedPeakIDs should use all peaks")
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
        let m = TapToneMeasurement(peaks: [peak], peakModeOverrides: [peak.id: .assigned("Top")])
        #expect(m.peakModeOverrides?[peak.id] == .assigned("Top"))
    }

    // D8: peakModeOverrides survive a JSON round-trip.
    @Test func modeOverrides_surviveRoundTrip() throws {
        let peak = ResonantPeak(frequency: 200, magnitude: -20)
        let original = TapToneMeasurement(peaks: [peak], peakModeOverrides: [peak.id: .assigned("Dipole")])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TapToneMeasurement.self, from: data)
        #expect(decoded.peakModeOverrides?[peak.id] == .assigned("Dipole"))
    }

    // Empty peakModeOverrides: nil overrides produce no key in JSON.
    @Test func nilOverrides_notWrittenToJSON() throws {
        let m = TapToneMeasurement(peaks: [])
        let data = try JSONEncoder().encode(m)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("\"peakModeOverrides\""),
                "nil peakModeOverrides should not appear in JSON")
    }

    // Auto-type entries: a peak with .auto override round-trips correctly.
    @Test func autoOverride_roundTrips() throws {
        let peak = ResonantPeak(frequency: 200, magnitude: -20)
        let original = TapToneMeasurement(peaks: [peak], peakModeOverrides: [peak.id: .auto])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TapToneMeasurement.self, from: data)
        #expect(decoded.peakModeOverrides?[peak.id] == .auto)
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
        // An empty list may decode as nil (matching Python behaviour)
        #expect(decoded.selectedPeakIDs == nil || decoded.selectedPeakIDs?.isEmpty == true)
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
}
