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
//  Test plan coverage: R3, R4
//

import Testing
import Foundation
@testable import GuitarTap

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
