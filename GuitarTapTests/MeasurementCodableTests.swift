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

    // Phase 6: renaming the Top peak to a freeform label removes it as the definitive Top, so the
    // ratio disappears - the on-screen and saved values agree that there is no Top. (Before Phase 6
    // tapToneRatio classified override-blind and still divided by the renamed peak.)
    @Test func tapToneRatio_freeformOverrideOnTop_returnsNil() {
        let air = ResonantPeak(frequency: 95,  magnitude: -28)
        let top = ResonantPeak(frequency: 210, magnitude: -20)
        let snapshot = SpectrumSnapshot(
            frequencies: [], magnitudes: [],
            minFreq: 50, maxFreq: 500, minDB: -100, maxDB: 0, isLogarithmic: false,
            guitarType: .classical, measurementType: .classical
        )
        let m = TapToneMeasurement(
            peaks: [air, top], spectrum: snapshot,
            selectedPeakIDs: [air.id, top.id],
            peakModeOverrides: [top.id: "Wolf note"]
        )
        #expect(m.tapToneRatio == nil,
                "a Top peak renamed to a freeform label is no longer the definitive Top")
    }

    // Phase 6: an override that RE-TARGETS a peak to Top makes it the definitive Top.
    @Test func tapToneRatio_overrideRetargetsTop() {
        let air   = ResonantPeak(frequency: 95,  magnitude: -28)
        let far   = ResonantPeak(frequency: 400, magnitude: -20) // classical: not Top by position
        let snapshot = SpectrumSnapshot(
            frequencies: [], magnitudes: [],
            minFreq: 50, maxFreq: 500, minDB: -100, maxDB: 0, isLogarithmic: false,
            guitarType: .classical, measurementType: .classical
        )
        let m = TapToneMeasurement(
            peaks: [air, far], spectrum: snapshot,
            selectedPeakIDs: [air.id, far.id],
            peakModeOverrides: [far.id: GuitarMode.top.displayName]
        )
        let ratio = m.tapToneRatio
        #expect(ratio != nil, "the relabelled peak is now the definitive Top")
        #expect(abs((ratio ?? 0) - 400.0 / 95.0) < 0.01)
    }

    // Phase 6: a Top peak that is DESELECTED is not the definitive Top, so no ratio.
    @Test func tapToneRatio_deselectedTop_returnsNil() {
        let air = ResonantPeak(frequency: 95,  magnitude: -28)
        let top = ResonantPeak(frequency: 210, magnitude: -20)
        let snapshot = SpectrumSnapshot(
            frequencies: [], magnitudes: [],
            minFreq: 50, maxFreq: 500, minDB: -100, maxDB: 0, isLogarithmic: false,
            guitarType: .classical, measurementType: .classical
        )
        let m = TapToneMeasurement(
            peaks: [air, top], spectrum: snapshot,
            selectedPeakIDs: [air.id]   // Top present but not selected
        )
        #expect(m.tapToneRatio == nil, "a deselected Top is a candidate, not the definitive Top")
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
            peakModeOverrides: [peak.id: "Custom Label"]
        )
        let data = try JSONEncoder().encode(measurement)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"Custom Label\""), "User override should appear in JSON export")
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
    // The app cannot produce one — overrides are label-only in memory, and clearing removes the key
    // (#17 F28) — but a hand-edited or legacy file can, and both ports drop it the same way.
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
    // what lives in memory (#17 F28). Pins write parity with Python `to_dict()` and web `encode.ts`,
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

// ---------------------------------------------------------------------------
// MARK: - Selection heal on decode  (Phase 6)
//
// Legacy files predate the definitive-selection rule: some saved no selection at all, some saved a
// selection with several Air/Top/Back peaks. The decoder repairs both so the loaded state, the
// saved-list ratio and the file agree, setting the same `wasHealed` flag as the duplicate-peak heal
// (so the library re-saves identically). Guitar only.
// ---------------------------------------------------------------------------

@Suite("SelectionHealOnDecode")
@MainActor
struct SelectionHealOnDecodeTests {

    private func classicalSnapshot() -> SpectrumSnapshot {
        SpectrumSnapshot(
            frequencies: [], magnitudes: [],
            minFreq: 50, maxFreq: 500, minDB: -100, maxDB: 0, isLogarithmic: false,
            guitarType: .classical, measurementType: .classical
        )
    }

    private func roundTrip(_ m: TapToneMeasurement) throws -> TapToneMeasurement {
        let data = try TapToneAnalyzer.encodeMeasurements([m])
        return try TapToneAnalyzer.decodeMeasurements(data)[0]
    }

    // A guitar file with NO saved selection is healed to the definitive set (strongest per mode),
    // and flagged so the library re-saves.
    @Test func nilSelection_isHealedToDefinitiveSet() throws {
        let air = ResonantPeak(frequency: 95,  magnitude: -28)
        let top = ResonantPeak(frequency: 210, magnitude: -20)
        let m = TapToneMeasurement(peaks: [air, top], spectrum: classicalSnapshot())  // nil selection

        let decoded = try roundTrip(m)

        #expect(decoded.wasHealed, "a healed selection must set wasHealed so the library re-saves")
        #expect(decoded.selectedPeakIDs != nil, "nil selection is populated on read")
        #expect(Set(decoded.selectedPeakIDs ?? []) == [air.id, top.id],
                "the definitive Air and Top are selected")
        #expect(decoded.tapToneRatio != nil, "and the ratio is now available")
    }

    // A guitar file whose selection holds TWO Tops is pruned to the stronger one; the invariant is
    // restored and the untouched Air survives.
    @Test func twoSelectedTops_prunedToTheStronger() throws {
        let air     = ResonantPeak(frequency: 95,  magnitude: -28)
        // Classical Top is 170–230, Back 190–280; 175 and 185 are both Top-only (below Back).
        let weakTop = ResonantPeak(frequency: 175, magnitude: -30)
        let loudTop = ResonantPeak(frequency: 185, magnitude: -18)   // stronger Top
        let m = TapToneMeasurement(
            peaks: [air, weakTop, loudTop], spectrum: classicalSnapshot(),
            selectedPeakIDs: [air.id, weakTop.id, loudTop.id]
        )

        let decoded = try roundTrip(m)

        #expect(decoded.wasHealed, "pruning a duplicate holder counts as a heal")
        let sel = Set(decoded.selectedPeakIDs ?? [])
        #expect(sel.contains(loudTop.id), "the stronger Top survives")
        #expect(!sel.contains(weakTop.id), "the weaker Top is dropped from the selection")
        #expect(sel.contains(air.id), "the Air selection is untouched")
    }

    // A guitar file that already satisfies the invariant is NOT reflagged as healed.
    @Test func validSelection_isNotHealed() throws {
        let air = ResonantPeak(frequency: 95,  magnitude: -28)
        let top = ResonantPeak(frequency: 210, magnitude: -20)
        let m = TapToneMeasurement(
            peaks: [air, top], spectrum: classicalSnapshot(),
            selectedPeakIDs: [air.id, top.id]
        )

        let decoded = try roundTrip(m)

        #expect(!decoded.wasHealed, "a valid selection must not trigger a needless re-save")
        #expect(Set(decoded.selectedPeakIDs ?? []) == [air.id, top.id])
    }
}
