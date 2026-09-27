//
//  MaterialMeasurementInputsTests.swift
//  GuitarTapTests
//
//  The two-store material-dimensions model: a measurement's own dimensions (Store B,
//  `TapToneAnalyzer.materialInputs`) are seeded from the Settings template (Store A) at completion,
//  restored from the file's snapshot on load, and — crucially — loading NEVER writes the Settings
//  defaults (the origin bug this design fixes). Also covers notes-on-load (R10).
//
//  These are the *sourcing* invariants that existing tests don't cover: PlateProperties/BraceProperties
//  test the calc math (dims passed in directly), and MeasurementCodableTests tests the format round-trip
//  — neither exercises where the dimensions come from.
//
// @parity test/material-measurement-inputs

import Testing
import Foundation
@testable import GuitarTap

/// Serialized: every test mutates the global `TapDisplaySettings`, so they must not interleave.
@Suite(.serialized)
struct MaterialMeasurementInputsTests {

    private func makeSUT() -> TapToneAnalyzer {
        TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
    }

    /// A minimal loadable plate measurement whose snapshot carries its own dimensions.
    private func plateMeasurement(notes: String? = nil,
                                  length: Float = 111, width: Float = 222,
                                  thickness: Float = 3.33, mass: Float = 44,
                                  bodyLength: Float = 480, bodyWidth: Float = 370,
                                  preset: PlateStiffnessPreset = .classicalTop) -> TapToneMeasurement {
        let snap = SpectrumSnapshot(
            frequencies: [100, 200], magnitudes: [-10, -20],
            minFreq: 50, maxFreq: 300, minDB: -100, maxDB: 0, isLogarithmic: false,
            measurementType: .plate,
            plateLength: length, plateWidth: width, plateThickness: thickness, plateMass: mass,
            guitarBodyLength: bodyLength, guitarBodyWidth: bodyWidth,
            plateStiffnessPreset: preset, customPlateStiffness: 60)
        return TapToneMeasurement(peaks: [], notes: notes, longitudinalSnapshot: snap)
    }

    // MARK: - Seed at complete

    @Test func seedsStoreBFromSettingsWhenPlateCompletes() throws {
        TapDisplaySettings.measurementType = .plate
        TapDisplaySettings.plateLength = 501
        TapDisplaySettings.plateWidth = 201
        TapDisplaySettings.plateThickness = 4.5
        TapDisplaySettings.plateMass = 210
        TapDisplaySettings.plateStiffnessPreset = .classicalTop
        let sut = makeSUT()
        #expect(sut.materialInputs == nil)              // nil until the measurement completes
        sut.isMeasurementComplete = true
        let mi = try #require(sut.materialInputs)
        #expect(mi.lengthMM == 501)
        #expect(mi.widthMM == 201)
        #expect(mi.thicknessMM == 4.5)
        #expect(mi.massG == 210)
        #expect(mi.stiffnessPreset == .classicalTop)
    }

    @Test func doesNotSeedStoreBForGuitar() {
        TapDisplaySettings.measurementType = .generic
        let sut = makeSUT()
        sut.isMeasurementComplete = true
        #expect(sut.materialInputs == nil)              // guitar has no material dimensions
    }

    @Test func doesNotSeedStoreBWhileLoading() {
        TapDisplaySettings.measurementType = .plate
        let sut = makeSUT()
        sut.isLoadingMeasurement = true
        sut.isMeasurementComplete = true                // the load path sets complete; the seed must be
        #expect(sut.materialInputs == nil)              // suppressed — load sets Store B from the snapshot
        sut.isLoadingMeasurement = false
    }

    // MARK: - Load sets Store B without clobbering Settings (the origin bug)

    @Test func loadSetsStoreBFromSnapshotAndLeavesSettingsUntouched() throws {
        TapDisplaySettings.measurementType = .plate
        // Store A (the template) — deliberately DIFFERENT from the measurement's own dims.
        TapDisplaySettings.plateLength = 999
        TapDisplaySettings.plateWidth = 999
        TapDisplaySettings.plateThickness = 9.9
        TapDisplaySettings.plateMass = 999

        let sut = makeSUT()
        sut.loadMeasurement(plateMeasurement())

        // Store B carries the measurement's OWN dimensions.
        let mi = try #require(sut.materialInputs)
        #expect(mi.lengthMM == 111)
        #expect(mi.widthMM == 222)
        #expect(mi.thicknessMM == 3.33)
        #expect(mi.massG == 44)
        #expect(mi.bodyLengthMM == 480)
        #expect(mi.bodyWidthMM == 370)
        #expect(mi.stiffnessPreset == .classicalTop)

        // The Settings template (Store A) is UNTOUCHED — the invariant the de-clobber restored.
        #expect(TapDisplaySettings.plateLength == 999)
        #expect(TapDisplaySettings.plateWidth == 999)
        #expect(TapDisplaySettings.plateThickness == 9.9)
        #expect(TapDisplaySettings.plateMass == 999)
    }

    // MARK: - Notes on load (R10)

    @Test func loadRestoresNotesForReSave() {
        TapDisplaySettings.measurementType = .plate
        let sut = makeSUT()
        sut.loadMeasurement(plateMeasurement(notes: "spruce, tight grain"))
        #expect(sut.loadedNotes == "spruce, tight grain")
    }

    @Test func loadTreatsBlankNotesAsNil() {
        TapDisplaySettings.measurementType = .plate
        let sut = makeSUT()
        sut.loadMeasurement(plateMeasurement(notes: ""))
        #expect(sut.loadedNotes == nil)
    }
}
