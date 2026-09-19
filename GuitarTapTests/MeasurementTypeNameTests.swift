//
//  MeasurementTypeNameTests.swift
//  GuitarTapTests
//
//  Pins the Details-pane "Measurement Type" resolution (parity group view/measurement-detail).
//
//  The measurement type is stored ONLY inside the SpectrumSnapshot — never as a top-level
//  TapToneMeasurement field — so the resolver must read from the snapshot:
//
//      spectrumSnapshot?.measurementType ?? longitudinalSnapshot?.measurementType   → shortName ?? "—"
//
//  These are the Swift counterpart of Python tests/test_measurement_type_name.py and the web
//  test/measurement-type-name.test.ts. They were deferred while `measurementTypeName` was `private`
//  inside MeasurementDetailView (unreachable from a test); the resolver now lives on the model as
//  `TapToneMeasurement.measurementTypeShortName`, so the in-memory cases below can exercise it —
//  the exact shape that regressed to "—" on Python in the 1.0.2 run-review (a round-trip test can't
//  catch it: loading from a dict populates the top-level field; only an in-memory measurement does).
//
// @parity test/measurement-type-name

import Testing
import Foundation
@testable import GuitarTap

@Suite("MeasurementTypeName")
@MainActor
struct MeasurementTypeNameTests {

    /// Minimal snapshot carrying only the field the resolver reads.
    private func snap(_ type: MeasurementType?) -> SpectrumSnapshot {
        SpectrumSnapshot(frequencies: [], magnitudes: [], minFreq: 20, maxFreq: 200,
                         minDB: -100, maxDB: 0, isLogarithmic: false, measurementType: type)
    }

    // ── The regression shape: in-memory, top-level field is not a thing on Swift; type only in the snapshot ──

    @Test func braceResolvesFromLongitudinalSnapshot() {
        let m = TapToneMeasurement(peaks: [], longitudinalSnapshot: snap(.brace))
        #expect(m.measurementTypeShortName == "Brace")
    }

    @Test func plateResolvesFromLongitudinalSnapshot() {
        let m = TapToneMeasurement(peaks: [], longitudinalSnapshot: snap(.plate))
        #expect(m.measurementTypeShortName == "Plate")
    }

    @Test func guitarResolvesFromSpectrumSnapshot() {
        let m = TapToneMeasurement(peaks: [], spectrum: snap(.classical))
        #expect(m.measurementTypeShortName == "Classical")
    }

    // ── Resolution order + fallbacks (mirrors the ?? chain) ──

    @Test func spectrumSnapshotWinsOverLongitudinal() {
        let m = TapToneMeasurement(peaks: [], spectrum: snap(.generic), longitudinalSnapshot: snap(.brace))
        #expect(m.measurementTypeShortName == "Generic")
    }

    @Test func comparisonShortCircuitsBeforeAnySnapshotLookup() {
        let m = TapToneMeasurement(peaks: [], spectrum: snap(.generic), comparisonEntries: [])
        #expect(m.measurementTypeShortName == "Comparison")
    }

    @Test func noSnapshotFallsBackToEmDash() {
        let m = TapToneMeasurement(peaks: [])
        #expect(m.measurementTypeShortName == "—")
    }

    @Test func nilSnapshotTypeFallsBackToEmDash() {
        let m = TapToneMeasurement(peaks: [], spectrum: snap(nil))
        #expect(m.measurementTypeShortName == "—")
    }

    // ── Every type maps to its single word ──

    /// The cases above cover the resolution *chain*; this covers the *mapping*, so a new or renamed
    /// MeasurementType cannot silently resolve to the wrong word in the Details pane.
    @Test(arguments: [(MeasurementType.acoustic, "Acoustic"),
                      (.classical, "Classical"),
                      (.flamenco, "Flamenco"),
                      (.generic, "Generic"),
                      (.plate, "Plate"),
                      (.brace, "Brace")])
    func everyTypeResolvesToItsShortName(type: MeasurementType, expected: String) {
        let m = TapToneMeasurement(peaks: [], spectrum: snap(type))
        #expect(m.measurementTypeShortName == expected)
    }

    // ── The material flag reads the same resolution ──

    /// `isMaterial` resolves through the same snapshot chain, so it is pinned here too: a brace
    /// measurement whose type lives only in the longitudinal snapshot must still read as material.
    @Test func materialFlagResolvesFromTheSameSnapshot() {
        let brace = TapToneMeasurement(peaks: [], longitudinalSnapshot: snap(.brace))
        #expect(brace.isMaterial)
        let guitar = TapToneMeasurement(peaks: [], spectrum: snap(.generic))
        #expect(!guitar.isMaterial)
    }
}