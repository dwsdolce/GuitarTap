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
            measurementType: .acoustic,
            maxPeaks: 8
        )

        let annotationOffset = CGPoint(x: 12, y: -8)
        let overrides: [UUID: UserAssignedMode] = [peak1.id: .assigned("Air"), peak2.id: .auto]

        return TapToneMeasurement(
            peaks: [peak1, peak2],
            decayTime: 0.75,
            tapLocation: "Bridge",
            notes: "Test measurement",
            spectrum: snapshot,
            annotationOffsets: [peak1.id: annotationOffset],
            tapDetectionThreshold: -40,
            hysteresisMargin: 5,
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
        #expect(decoded.tapLocation == original.tapLocation)
        #expect(decoded.notes == original.notes)
        #expect(decoded.tapDetectionThreshold == original.tapDetectionThreshold)
        #expect(decoded.hysteresisMargin == original.hysteresisMargin)
        #expect(decoded.numberOfTaps == original.numberOfTaps)
        #expect(decoded.microphoneName == original.microphoneName)
        #expect(decoded.microphoneUID == original.microphoneUID)
        #expect(decoded.annotationVisibilityMode == original.annotationVisibilityMode)
        // selectedPeakIDs must round-trip
        #expect(decoded.selectedPeakIDs == original.selectedPeakIDs)
        // selectedLongitudinalPeakID
        #expect(decoded.selectedLongitudinalPeakID == original.selectedLongitudinalPeakID)
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
// MARK: - updateMeasurement(at:tapLocation:notes:)
// ---------------------------------------------------------------------------

@Suite("UpdateMeasurement")
@MainActor
struct UpdateMeasurementTests {

    private func makeAnalyzerWithMeasurements(_ measurements: [TapToneMeasurement]) -> TapToneAnalyzer {
        let analyzer = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer())
        analyzer.savedMeasurements = measurements
        return analyzer
    }

    private func makeMeasurement(location: String? = nil, notes: String? = nil) -> TapToneMeasurement {
        TapToneMeasurement(peaks: [], tapLocation: location, notes: notes)
    }

    // Updating by index changes only the targeted entry's location and notes.
    @Test func update_byIndex_changesOnlyTargetedEntry() {
        let m0 = makeMeasurement(location: "Bridge", notes: "First")
        let m1 = makeMeasurement(location: "Soundhole", notes: "Second")
        let analyzer = makeAnalyzerWithMeasurements([m0, m1])

        analyzer.updateMeasurement(at: 0, tapLocation: "Upper Bout", notes: "Edited")

        #expect(analyzer.savedMeasurements[0].tapLocation == "Upper Bout")
        #expect(analyzer.savedMeasurements[0].notes == "Edited")
        #expect(analyzer.savedMeasurements[1].tapLocation == "Soundhole", "Second entry must not be affected")
        #expect(analyzer.savedMeasurements[1].notes == "Second", "Second entry must not be affected")
    }

    // Editing one of two duplicates (same id, different index) leaves the other unchanged.
    @Test func update_duplicateImport_onlyEditedIndexChanges() {
        let original = makeMeasurement(location: "Top", notes: "Original")
        // Simulate importing the same file twice — both entries share the same id.
        let analyzer = makeAnalyzerWithMeasurements([original, original])

        analyzer.updateMeasurement(at: 1, tapLocation: "Back", notes: "Copy")

        #expect(analyzer.savedMeasurements[0].tapLocation == "Top",  "First duplicate must not change")
        #expect(analyzer.savedMeasurements[0].notes == "Original",   "First duplicate must not change")
        #expect(analyzer.savedMeasurements[1].tapLocation == "Back", "Second duplicate should be updated")
        #expect(analyzer.savedMeasurements[1].notes == "Copy",       "Second duplicate should be updated")
        // Both entries still share the original id
        #expect(analyzer.savedMeasurements[0].id == analyzer.savedMeasurements[1].id,
                "id must be preserved through the update")
    }

    // Passing nil clears the fields.
    @Test func update_nilValues_clearFields() {
        let m = makeMeasurement(location: "Bridge", notes: "Some notes")
        let analyzer = makeAnalyzerWithMeasurements([m])

        analyzer.updateMeasurement(at: 0, tapLocation: nil, notes: nil)

        #expect(analyzer.savedMeasurements[0].tapLocation == nil)
        #expect(analyzer.savedMeasurements[0].notes == nil)
    }

    // An out-of-range index is a no-op.
    @Test func update_outOfRangeIndex_isNoOp() {
        let m = makeMeasurement(location: "Bridge")
        let analyzer = makeAnalyzerWithMeasurements([m])

        analyzer.updateMeasurement(at: 99, tapLocation: "Changed", notes: nil)

        #expect(analyzer.savedMeasurements[0].tapLocation == "Bridge", "Out-of-range update must not modify array")
        #expect(analyzer.savedMeasurements.count == 1)
    }

    // The id and all other fields are preserved after an update.
    @Test func update_preservesIdAndOtherFields() {
        let peak = ResonantPeak(frequency: 195, magnitude: -22)
        let m = TapToneMeasurement(peaks: [peak], decayTime: 0.5, tapLocation: "Old", notes: "Old notes")
        let originalID = m.id
        let analyzer = makeAnalyzerWithMeasurements([m])

        analyzer.updateMeasurement(at: 0, tapLocation: "New", notes: "New notes")

        let updated = analyzer.savedMeasurements[0]
        #expect(updated.id == originalID, "id must be preserved")
        #expect(updated.peaks.count == 1,  "peaks must be preserved")
        #expect(updated.decayTime == 0.5,  "decayTime must be preserved")
        #expect(updated.tapLocation == "New")
        #expect(updated.notes == "New notes")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Fixture loading test  (R4)
// ---------------------------------------------------------------------------

@Suite("FixtureLoading")
@MainActor
struct FixtureLoadingTests {

    // R4: The real test fixture (chris-1771351833.json) must decode without error.
    // The fixture is a JSON array of TapToneMeasurement objects.
    @Test func realFixture_decodesWithoutError() throws {
        // On device the test bundle is the only reliable source; on Mac the
        // fixture may also live next to the source tree.  Try bundle first so
        // this test works on both simulator/device and local Mac runs.
        let fixtureName = "chris-1771351833"
        let bundleURL = Bundle.allBundles
            .lazy
            .compactMap { $0.url(forResource: fixtureName, withExtension: "json") }
            .first

        // Fall back to the source-relative path used during local development
        let sourceRelativeURL: URL? = {
            let thisFile = URL(fileURLWithPath: #file)
            let url = thisFile
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Tests")
                .appendingPathComponent("\(fixtureName).json")
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
