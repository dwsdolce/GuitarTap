//
//  ExportFilenameTests.swift
//  GuitarTapTests
//
//  Pins the shared export-filename rule (FILE-PATHS-AND-NAMES-SPEC §2b): one stem function,
//  per-artifact default word, integer-second discriminator, name slugged (spaces and "/" → "-",
//  lowercased). Three-way with Python test_export_filename.py and web export-filename.test.ts.
//
// @parity test/export-filename

import Testing
import Foundation
@testable import GuitarTap

@Suite("ExportFilename")
struct ExportFilenameTests {

    // A fixed instant so the discriminator is deterministic: 1_784_060_789 s.
    private let ts = Date(timeIntervalSince1970: 1_784_060_789)

    // MARK: - The core rule: named vs the per-artifact default word

    @Test func named_usesTheName_forEveryArtifact() {
        #expect(ExportFilename.stem(name: "Martin 000-28", timestamp: ts, unnamed: "measurement") == "martin-000-28-1784060789")
        #expect(ExportFilename.stem(name: "Martin 000-28", timestamp: ts, unnamed: "report") == "martin-000-28-1784060789")
        #expect(ExportFilename.stem(name: "Martin 000-28", timestamp: ts, unnamed: "spectrum") == "martin-000-28-1784060789")
    }

    @Test func unnamed_usesTheArtifactWord_neverAnInfix() {
        #expect(ExportFilename.stem(name: nil, timestamp: ts, unnamed: "measurement") == "measurement-1784060789")
        #expect(ExportFilename.stem(name: nil, timestamp: ts, unnamed: "report") == "report-1784060789")
        #expect(ExportFilename.stem(name: nil, timestamp: ts, unnamed: "spectrum") == "spectrum-1784060789")
    }

    // An empty or whitespace name is treated as unnamed — never a leading dash.
    @Test func emptyName_fallsBackToTheWord() {
        #expect(ExportFilename.stem(name: "", timestamp: ts, unnamed: "measurement") == "measurement-1784060789")
    }

    // MARK: - Slugging: spaces AND slashes → "-", lowercased

    @Test func slugging_spacesAndSlashes_lowercased() {
        #expect(ExportFilename.stem(name: "Bridge/Plate Top", timestamp: ts, unnamed: "report") == "bridge-plate-top-1784060789")
        #expect(ExportFilename.stem(name: "RAMÍREZ 1975", timestamp: ts, unnamed: "measurement") == "ramírez-1975-1784060789")
    }

    // MARK: - The discriminator is integer seconds, never fractional

    @Test func timestamp_isIntegerSeconds() {
        let fractional = Date(timeIntervalSince1970: 1_784_060_789.123456)
        #expect(ExportFilename.stem(name: "x", timestamp: fractional, unnamed: "measurement") == "x-1784060789")
    }

    // MARK: - The concrete artifacts wire the right default word

    @Test func measurement_baseFilename_usesMeasurementWord() {
        let named = TapToneMeasurement(timestamp: ts, peaks: [], measurementName: "Martin")
        #expect(named.baseFilename == "martin-1784060789")
        let unnamed = TapToneMeasurement(timestamp: ts, peaks: [], measurementName: nil)
        #expect(unnamed.baseFilename == "measurement-1784060789")
    }
}