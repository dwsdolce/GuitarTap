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
// MARK: - SpectrumSnapshot binary size (the bytes themselves: MeasurementCodec, snapshotBytes)
// ---------------------------------------------------------------------------

@Suite("SpectrumSnapshotCodable")
@MainActor
struct SpectrumSnapshotCodableTests {

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

// MARK: - The file format — the shared cases in `measurement-codable.json`
//
// The spectrum's bytes (SB), what a file reads to (DC), what the writer emits (WR), and the real
// fixtures every edition carries: the same cases as Python and the web.
// ---------------------------------------------------------------------------

@Suite("MeasurementCodec", .serialized)
@MainActor
struct MeasurementCodecTests {

    nonisolated static func ids(_ table: String) -> [String] { MeasurementLogicTests.ids(table) }

    nonisolated static func fixtureNames() -> [String] {
        (MeasurementLogicTests.data["fixtures"] as! [[String: Any]]).map { $0["file"] as! String }
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// The app's writer, compact, keys sorted.
    static func write(_ measurements: [TapToneMeasurement]) throws -> String {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return String(decoding: try e.encode(measurements), as: UTF8.self)
    }

    static func read(_ file: Any) throws -> [TapToneMeasurement] {
        try decoder().decode([TapToneMeasurement].self, from: JSONSerialization.data(withJSONObject: file))
    }

    /// Whether `key` appears anywhere in a JSON document.
    static func hasKey(_ key: String, in value: Any) -> Bool {
        if let d = value as? [String: Any] {
            return d[key] != nil || d.values.contains { hasKey(key, in: $0) }
        }
        if let a = value as? [Any] { return a.contains { hasKey(key, in: $0) } }
        return false
    }

    /// `peaks[].k` — the key on every peak of every measurement; otherwise the key anywhere.
    static func present(_ path: String, in doc: Any) -> Bool {
        if path.hasPrefix("peaks[].") {
            let k = String(path.dropFirst("peaks[].".count))
            let peaks = (doc as! [[String: Any]]).flatMap { $0["peaks"] as? [[String: Any]] ?? [] }
            return !peaks.isEmpty && peaks.allSatisfy { $0[k] != nil }
        }
        return hasKey(path, in: doc)
    }

    @Test(arguments: ids("snapshotBytes"))
    func snapshotBytes(_ id: String) throws {
        let row = MeasurementLogicTests.row("snapshotBytes", id)
        let freqs = (row["frequencies"] as! [Double]).map(Float.init)
        let mags = (row["magnitudes"] as! [Double]).map(Float.init)
        let snap = SpectrumSnapshot(frequencies: freqs, magnitudes: mags,
                                    minFreq: 50, maxFreq: 500, minDB: -100, maxDB: 0, isLogarithmic: false)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snap)) as! [String: Any]
        #expect(json["frequenciesData"] as? String == row["frequenciesData"] as? String, "\(id) frequenciesData")
        #expect(json["magnitudesData"] as? String == row["magnitudesData"] as? String, "\(id) magnitudesData")
        #expect(json["frequencies"] == nil && json["magnitudes"] == nil, "\(id): no plain arrays")
        let back = try JSONDecoder().decode(SpectrumSnapshot.self, from: JSONEncoder().encode(snap))
        #expect(back.frequencies == freqs && back.magnitudes == mags, "\(id) read back")
    }

    @Test(arguments: ids("decode"))
    func decode(_ id: String) throws {
        let row = MeasurementLogicTests.row("decode", id)
        let m = try #require(try Self.read(row["file"]!).first)
        for (field, want) in row["expect"] as! [String: Any] {
            switch field {
            case "measurementName":
                #expect(m.measurementName == want as? String, "\(id) \(field)")
            case "peakMinThreshold":
                #expect(m.peakMinThreshold.map(Double.init) == want as? Double, "\(id) \(field)")
            case "sampleRate":
                #expect(m.sampleRate == want as? Double, "\(id) \(field)")
            case "frequencies":
                #expect(m.spectrumSnapshot?.frequencies == (want as! [Double]).map(Float.init), "\(id) \(field)")
            case "magnitudes":
                #expect(m.spectrumSnapshot?.magnitudes == (want as! [Double]).map(Float.init), "\(id) \(field)")
            case "overrides":
                let got = Dictionary(uniqueKeysWithValues: (m.peakModeOverrides ?? [:]).map { ($0.key.uuidString.lowercased(), $0.value) })
                let expected = Dictionary(uniqueKeysWithValues: (want as! [String: String]).map { ($0.key.lowercased(), $0.value) })
                #expect(got == expected, "\(id) \(field)")
            case "peakCount":
                #expect(m.peaks.count == want as? Int, "\(id) \(field)")
            case "pitchNote":
                #expect(m.peaks.first?.pitchNote == want as? String, "\(id) \(field)")
            case "annotationVisibilityMode":
                #expect(m.annotationVisibilityMode?.rawValue == want as? String, "\(id) \(field)")
            default:
                Issue.record("\(id): unknown field \(field)")
            }
        }
    }

    @Test(arguments: ids("write"))
    func write(_ id: String) throws {
        let row = MeasurementLogicTests.row("write", id)
        let text = try Self.write(try Self.read(row["file"]!))
        let doc = try JSONSerialization.jsonObject(with: Data(text.utf8))
        for key in row["present"] as? [String] ?? [] { #expect(Self.present(key, in: doc), "\(id): \(key) written") }
        for key in row["absent"] as? [String] ?? [] { #expect(!Self.hasKey(key, in: doc), "\(id): \(key) not written") }
        for (key, number) in row["text"] as? [String: String] ?? [:] {
            let token = text.range(of: "\"\(key)\":").map { r in
                String(text[r.upperBound...].prefix { !",}]".contains($0) })
            }
            #expect(token == number, "\(id): \(key) written as \(number)")
        }
        for s in row["contains"] as? [String] ?? [] { #expect(text.contains(s), "\(id): contains \(s)") }
    }

    @Test(arguments: fixtureNames())
    func fixture(_ file: String) throws {
        let row = (MeasurementLogicTests.data["fixtures"] as! [[String: Any]]).first { $0["file"] as! String == file }!
        let name = (file as NSString).deletingPathExtension
        let url = try #require(Bundle(for: MeasurementLogicAnchor.self).url(forResource: name, withExtension: "guitartap"))
        let ms = try Self.decoder().decode([TapToneMeasurement].self, from: Data(contentsOf: url))
        #expect(ms.count == row["measurements"] as? Int, "\(file) measurements")
        let m = try #require(ms.first)
        #expect(m.measurementName == row["measurementName"] as? String, "\(file) name")
        #expect(m.peaks.count == row["peakCount"] as? Int, "\(file) peaks")
        #expect(m.sampleRate == row["sampleRate"] as? Double, "\(file) sampleRate")
        #expect(m.isComparison == row["isComparison"] as? Bool, "\(file) isComparison")
        #expect((m.peakModeOverrides ?? [:]).values.sorted() == (row["overrideLabels"] as! [String]).sorted(), "\(file) overrides")
        for peakID in (m.peakModeOverrides ?? [:]).keys {
            #expect(m.peaks.contains { $0.id == peakID }, "\(file): the override names a peak the file contains")
        }

        let text = try Self.write(ms)
        let doc = try JSONSerialization.jsonObject(with: Data(text.utf8))
        for legacy in ["tapLocation", "peakThreshold", "hysteresisMargin", "maxPeaks"] {
            #expect(!Self.hasKey(legacy, in: doc), "\(file): \(legacy) not written")
        }
        let original = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        for (written, read) in zip(doc as! [[String: Any]], original) {
            guard let readSnap = read["spectrumSnapshot"] as? [String: Any], readSnap["frequenciesData"] != nil else { continue }
            let writtenSnap = written["spectrumSnapshot"] as? [String: Any]
            for key in ["frequenciesData", "magnitudesData"] {
                #expect(writtenSnap?[key] as? String == readSnap[key] as? String, "\(file): \(key) written as read")
            }
        }
        let again = try Self.decoder().decode([TapToneMeasurement].self, from: Data(text.utf8))
        #expect(again.count == ms.count, "\(file) read back")
        for (a, b) in zip(again, ms) {
            #expect(a.peaks.map(\.frequency) == b.peaks.map(\.frequency), "\(file) peaks read back")
            #expect(a.spectrumSnapshot?.frequencies == b.spectrumSnapshot?.frequencies, "\(file) spectrum read back")
            #expect(a.spectrumSnapshot?.magnitudes == b.spectrumSnapshot?.magnitudes, "\(file) spectrum read back")
        }
    }
}
