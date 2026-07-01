//
//  ImportPersistenceTests.swift
//  GuitarTapTests
//
//  Tests that both importMeasurements overloads persist measurements to disk.
//
//  Strategy: call the import method, then spin-wait up to 2 s for
//  TapToneAnalyzer.measurementsFileURL to appear. The URL is redirected to
//  a temporary directory when XCTestConfigurationFilePath is set in the
//  environment, so these tests never touch the user's real data.
//
//  Test plan coverage: IP1–IP3
//
// @parity test/import-persistence

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

@MainActor
private func makeSUT() -> TapToneAnalyzer {
    let fft = RealtimeFFTAnalyzer()
    let sut = TapToneAnalyzer(fftAnalyzer: fft)
    sut.cancellables.removeAll()
    return sut
}

/// Minimal valid JSON representing a single TapToneMeasurement array.
private func minimalMeasurementJSON() -> String {
    // Encode a real TapToneMeasurement so the JSON matches the current schema.
    let m = TapToneMeasurement(
        timestamp: Date(timeIntervalSinceReferenceDate: 0),
        peaks: [],
        measurementName: "Test"
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .sortedKeys
    let data = try! encoder.encode([m])
    return String(data: data, encoding: .utf8)!
}

/// Polls `fileURL` for up to `timeout` seconds, returning `true` once the file exists.
private func waitForFile(at fileURL: URL, timeout: TimeInterval = 2.0) -> Bool {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: fileURL.path) { return true }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return FileManager.default.fileExists(atPath: fileURL.path)
}

// ---------------------------------------------------------------------------
// MARK: - IP1–IP3: Import persistence tests
// ---------------------------------------------------------------------------

@Suite("ImportPersistence", .serialized)
@MainActor
struct ImportPersistenceTests {

    init() {
        // Remove any leftover test file from a previous run
        try? FileManager.default.removeItem(at: TapToneAnalyzer.measurementsFileURL)
    }

    // IP1: importMeasurements(json:) must persist to disk after a successful import.
    @Test func importMeasurementsJSON_persistsToDisk() {
        let sut = makeSUT()
        let json = minimalMeasurementJSON()

        let result = sut.importMeasurements(json: json)

        #expect(result == true, "importMeasurements(json:) should return true for valid JSON")
        #expect(sut.savedMeasurements.count == 1, "One measurement should be in savedMeasurements")

        let fileURL = TapToneAnalyzer.measurementsFileURL
        let appeared = waitForFile(at: fileURL)
        #expect(appeared, "saved_measurements.json should exist on disk after import")
    }

    // IP2: importMeasurements(from:) must persist to disk after a successful import.
    @Test func importMeasurementsData_persistsToDisk() throws {
        let sut = makeSUT()
        let json = minimalMeasurementJSON()
        let data = json.data(using: .utf8)!

        _ = try sut.importMeasurements(from: data)

        let fileURL = TapToneAnalyzer.measurementsFileURL
        let appeared = waitForFile(at: fileURL)
        #expect(appeared, "saved_measurements.json should exist on disk after importMeasurements(from:)")
    }

    // IP3: importMeasurements(json:) appends to any previously saved measurements.
    @Test func importMeasurementsJSON_appendsToExisting() {
        let sut = makeSUT()
        let json = minimalMeasurementJSON()

        _ = sut.importMeasurements(json: json)
        let countAfterFirst = sut.savedMeasurements.count

        _ = sut.importMeasurements(json: json)
        let countAfterSecond = sut.savedMeasurements.count

        #expect(countAfterSecond == countAfterFirst + 1,
                "Second import should append; count was \(countAfterFirst), now \(countAfterSecond)")
    }
}
