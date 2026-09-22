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

// MARK: - Update Measurement — the saved-measurement LIBRARY, addressed by index
//
// Tests TapToneAnalyzer.updateMeasurement(at:measurementName:notes:): editing an entry of the
// savedMeasurements array. Filed here, with the library, because that is what it mutates — it was
// under test/annotation-state until #17 F27, which is neither where it belongs nor where the web
// files its equivalent.
//
// The VALUE-level rules of an amendment — what `with(...)` preserves, and that every amendment
// mints a new id — belong to test/measurement-amend and are not repeated here.
//
// Two of these have no web counterpart BY ARCHITECTURE, not by omission: the natives address the
// library by index, while web's store is a rowKey-addressed IndexedDB with no index API (F19b).
// ---------------------------------------------------------------------------

@Suite("UpdateMeasurement — the library, by index")
@MainActor
struct UpdateMeasurementTests {

    private func makeAnalyzerWithMeasurements(_ measurements: [TapToneMeasurement]) -> TapToneAnalyzer {
        let analyzer = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer())
        analyzer.savedMeasurements = measurements
        return analyzer
    }

    private func makeMeasurement(measurementName: String? = nil, notes: String? = nil) -> TapToneMeasurement {
        TapToneMeasurement(peaks: [], measurementName: measurementName, notes: notes)
    }

    // Updating by index changes only the targeted entry's measurementName and notes.
    @Test func update_byIndex_changesOnlyTargetedEntry() {
        let m0 = makeMeasurement(measurementName: "Bridge", notes: "First")
        let m1 = makeMeasurement(measurementName: "Soundhole", notes: "Second")
        let analyzer = makeAnalyzerWithMeasurements([m0, m1])

        analyzer.updateMeasurement(at: 0, measurementName: "Upper Bout", notes: "Edited")

        #expect(analyzer.savedMeasurements[0].measurementName == "Upper Bout")
        #expect(analyzer.savedMeasurements[0].notes == "Edited")
        #expect(analyzer.savedMeasurements[1].measurementName == "Soundhole", "Second entry must not be affected")
        #expect(analyzer.savedMeasurements[1].notes == "Second", "Second entry must not be affected")
    }

    // Editing one of two duplicates (same id, different index) leaves the other unchanged, and
    // the two ids diverge — the edited entry is no longer the same dataset as its twin.
    @Test func update_duplicateImport_onlyEditedIndexChanges() {
        let original = makeMeasurement(measurementName: "Top", notes: "Original")
        // Simulate importing the same file twice — both entries share the same id.
        let analyzer = makeAnalyzerWithMeasurements([original, original])

        analyzer.updateMeasurement(at: 1, measurementName: "Back", notes: "Copy")

        #expect(analyzer.savedMeasurements[0].measurementName == "Top",  "First duplicate must not change")
        #expect(analyzer.savedMeasurements[0].notes == "Original",   "First duplicate must not change")
        #expect(analyzer.savedMeasurements[1].measurementName == "Back", "Second duplicate should be updated")
        #expect(analyzer.savedMeasurements[1].notes == "Copy",       "Second duplicate should be updated")
        #expect(analyzer.savedMeasurements[0].id == original.id,
                "the untouched duplicate keeps its id")
        #expect(analyzer.savedMeasurements[0].id != analyzer.savedMeasurements[1].id,
                "the edited duplicate is different data, so it must no longer share the twin's id")
    }


    // An out-of-range index is a no-op.
    @Test func update_outOfRangeIndex_isNoOp() {
        let m = makeMeasurement(measurementName: "Bridge")
        let analyzer = makeAnalyzerWithMeasurements([m])

        analyzer.updateMeasurement(at: 99, measurementName: "Changed", notes: nil)

        #expect(analyzer.savedMeasurements[0].measurementName == "Bridge", "Out-of-range update must not modify array")
        #expect(analyzer.savedMeasurements.count == 1)
    }


}
