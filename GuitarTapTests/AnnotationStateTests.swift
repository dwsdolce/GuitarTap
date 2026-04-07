//
//  AnnotationStateTests.swift
//  GuitarTapTests
//
//  Tests for peak annotation state management:
//  offset storage, peak selection, visibility filtering, and mode overrides.
//
//  All tests operate on TapToneAnalyzer's @Published state properties directly;
//  no audio hardware or async timing is involved.
//
//  Test plan coverage: D1–D10
//

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helper
// ---------------------------------------------------------------------------

private func makeSUT() -> TapToneAnalyzer {
    let fft = RealtimeFFTAnalyzer()
    return TapToneAnalyzer(fftAnalyzer: fft)
}

private func makePeak(frequency: Float = 200, magnitude: Float = -20) -> ResonantPeak {
    ResonantPeak(frequency: frequency, magnitude: magnitude)
}

// ---------------------------------------------------------------------------
// MARK: - Annotation Offset Tests  (D1–D2)
// ---------------------------------------------------------------------------

@Suite("AnnotationOffsets")
@MainActor
struct AnnotationOffsetTests {

    // D1: updateAnnotationOffset stores the CGPoint keyed by peak ID.
    @Test func updateAnnotationOffset_storesOffsetByID() {
        let sut = makeSUT()
        let peak = makePeak()
        let offset = CGPoint(x: 10, y: 20)

        sut.updateAnnotationOffset(for: peak.id, offset: offset)

        let stored = sut.peakAnnotationOffsets[peak.id]
        #expect(stored != nil, "Offset should be stored for the peak ID")
        #expect(stored?.x == 10 && stored?.y == 20, "Stored offset mismatch: \(String(describing: stored))")
    }

    // D1b: Updating an offset twice keeps the latest value.
    @Test func updateAnnotationOffset_overwritesPrevious() {
        let sut = makeSUT()
        let peak = makePeak()
        sut.updateAnnotationOffset(for: peak.id, offset: CGPoint(x: 1, y: 2))
        sut.updateAnnotationOffset(for: peak.id, offset: CGPoint(x: 99, y: 88))

        let stored = sut.peakAnnotationOffsets[peak.id]
        #expect(stored?.x == 99 && stored?.y == 88)
    }

    // D2: applyAnnotationOffsets bulk-populates peakAnnotationOffsets.
    @Test func applyAnnotationOffsets_populatesDictionary() {
        let sut = makeSUT()
        let id1 = UUID()
        let id2 = UUID()
        let offsets: [UUID: CGPoint] = [
            id1: CGPoint(x: 5, y: 10),
            id2: CGPoint(x: 15, y: 20)
        ]

        sut.applyAnnotationOffsets(offsets)

        #expect(sut.peakAnnotationOffsets[id1] == CGPoint(x: 5, y: 10))
        #expect(sut.peakAnnotationOffsets[id2] == CGPoint(x: 15, y: 20))
    }
}

// ---------------------------------------------------------------------------
// MARK: - Peak Selection Tests  (D3)
// ---------------------------------------------------------------------------

@Suite("PeakSelection")
struct PeakSelectionTests {

    // D3: Toggling same peak ID twice results in empty selectedPeakIDs.
    @Test func togglePeakSelection_insertsThenRemoves() {
        let sut = makeSUT()
        let id = UUID()

        sut.togglePeakSelection(id)
        #expect(sut.selectedPeakIDs.contains(id), "After first toggle, peak should be selected")

        sut.togglePeakSelection(id)
        #expect(!sut.selectedPeakIDs.contains(id), "After second toggle, peak should be deselected")
    }

    // selectAllPeaks populates selectedPeakIDs with all currentPeaks IDs.
    @Test func selectAllPeaks_selectsAllCurrentPeaks() {
        let sut = makeSUT()
        let peaks = [makePeak(frequency: 100), makePeak(frequency: 200), makePeak(frequency: 300)]
        sut.currentPeaks = peaks

        sut.selectAllPeaks()

        for peak in peaks {
            #expect(sut.selectedPeakIDs.contains(peak.id),
                    "Peak \(peak.frequency) Hz should be selected after selectAllPeaks")
        }
    }

    // selectNoPeaks clears all selections.
    @Test func selectNoPeaks_clearsAll() {
        let sut = makeSUT()
        let peaks = [makePeak(frequency: 100), makePeak(frequency: 200)]
        sut.currentPeaks = peaks
        sut.selectAllPeaks()

        sut.selectNoPeaks()

        #expect(sut.selectedPeakIDs.isEmpty, "selectedPeakIDs should be empty after selectNoPeaks")
    }
}

// ---------------------------------------------------------------------------
// MARK: - userHasModifiedPeakSelection Flag Tests  (D3b)
// ---------------------------------------------------------------------------

@Suite("UserModifiedPeakSelectionFlag")
struct UserModifiedPeakSelectionFlagTests {

    // togglePeakSelection sets the flag.
    @Test func togglePeakSelection_setsModifiedFlag() {
        let sut = makeSUT()
        #expect(!sut.userHasModifiedPeakSelection, "Flag should start false")

        sut.togglePeakSelection(UUID())

        #expect(sut.userHasModifiedPeakSelection, "Flag should be true after toggle")
    }

    // selectAllPeaks sets the flag.
    @Test func selectAllPeaks_setsModifiedFlag() {
        let sut = makeSUT()
        sut.currentPeaks = [makePeak()]

        sut.selectAllPeaks()

        #expect(sut.userHasModifiedPeakSelection)
    }

    // selectNoPeaks sets the flag.
    @Test func selectNoPeaks_setsModifiedFlag() {
        let sut = makeSUT()

        sut.selectNoPeaks()

        #expect(sut.userHasModifiedPeakSelection)
    }

    // resetToAutoSelection clears the flag and selects the best peak per mode.
    @Test func resetToAutoSelection_clearsFlagAndSelectsBestPerMode() {
        let sut = makeSUT()
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .acoustic
        defer { TapDisplaySettings.measurementType = savedType }

        // Two peaks in the acoustic Air range (90–120 Hz); the louder one should win.
        let quietAir = ResonantPeak(frequency: 98, magnitude: -50)
        let loudAir  = ResonantPeak(frequency: 105, magnitude: -30)
        sut.currentPeaks = [quietAir, loudAir]

        // Simulate user having made a manual change
        sut.userHasModifiedPeakSelection = true
        sut.selectedPeakIDs = []

        sut.resetToAutoSelection()

        #expect(!sut.userHasModifiedPeakSelection, "Flag should be cleared after resetToAutoSelection")
        #expect(sut.selectedPeakIDs.contains(loudAir.id), "Loudest Air peak should be auto-selected")
        #expect(!sut.selectedPeakIDs.contains(quietAir.id), "Quieter Air peak should not be selected")
    }

    // resetToAutoSelection on empty currentPeaks is a no-op (no crash).
    @Test func resetToAutoSelection_emptyPeaks_isNoop() {
        let sut = makeSUT()
        sut.userHasModifiedPeakSelection = true

        sut.resetToAutoSelection()

        #expect(!sut.userHasModifiedPeakSelection)
        #expect(sut.selectedPeakIDs.isEmpty)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Visible Peaks Tests  (D4–D6)
// ---------------------------------------------------------------------------

@Suite("VisiblePeaks")
struct VisiblePeaksTests {

    // D4: .all mode returns all currentPeaks.
    @Test func allMode_returnsAllCurrentPeaks() {
        let sut = makeSUT()
        sut.annotationVisibilityMode = .all
        let peaks = [makePeak(frequency: 100), makePeak(frequency: 200), makePeak(frequency: 300)]
        sut.currentPeaks = peaks

        #expect(sut.visiblePeaks.count == 3)
    }

    // D5: .selected mode returns only peaks whose IDs are in selectedPeakIDs.
    @Test func selectedMode_filtersToSelectedPeaks() {
        let sut = makeSUT()
        sut.annotationVisibilityMode = .selected
        let p1 = makePeak(frequency: 100)
        let p2 = makePeak(frequency: 200)
        let p3 = makePeak(frequency: 300)
        sut.currentPeaks = [p1, p2, p3]
        sut.selectedPeakIDs = [p1.id, p3.id]

        let visible = sut.visiblePeaks
        #expect(visible.count == 2)
        #expect(visible.map(\.frequency).contains(100))
        #expect(visible.map(\.frequency).contains(300))
        #expect(!visible.map(\.frequency).contains(200))
    }

    // D6: .none mode returns empty array regardless of currentPeaks.
    @Test func noneMode_returnsEmpty() {
        let sut = makeSUT()
        sut.annotationVisibilityMode = .none
        sut.currentPeaks = [makePeak(), makePeak(frequency: 300)]
        sut.selectAllPeaks()

        #expect(sut.visiblePeaks.isEmpty, "None mode should suppress all annotations")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Mode Override / Label Tests  (D7–D8)
// ---------------------------------------------------------------------------

@Suite("ModeOverrides", .serialized)
@MainActor
struct ModeOverrideTests {

    // D7: No override → label comes from GuitarMode.classify() displayName.
    @Test func noOverride_returnsAutoLabel() {
        let sut = makeSUT()
        // Ensure acoustic guitar type (so 100 Hz → Air)
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .acoustic
        defer { TapDisplaySettings.measurementType = savedType }
        let peak = makePeak(frequency: 100)   // Air mode for acoustic

        let label = sut.effectiveModeLabel(for: peak)

        // GuitarMode.classify(frequency: 100, guitarType: .acoustic) == .air
        #expect(label == "Air (Helmholtz)", "Expected 'Air (Helmholtz)' for 100 Hz in acoustic mode, got '\(label)'")
    }

    // D8: .assigned("Custom") override returns the custom string.
    @Test func assignedOverride_returnsCustomLabel() {
        let sut = makeSUT()
        let peak = makePeak(frequency: 200)
        sut.setModeOverride(.assigned("My Label"), for: peak.id)

        let label = sut.effectiveModeLabel(for: peak)
        #expect(label == "My Label", "Expected 'My Label', got '\(label)'")
    }

    // hasManualOverride returns true only for .assigned overrides.
    @Test func hasManualOverride_trueForAssigned_falseForAuto() {
        let sut = makeSUT()
        let peak = makePeak()

        sut.setModeOverride(.auto, for: peak.id)
        #expect(!sut.hasManualOverride(for: peak.id), ".auto should not count as a manual override")

        sut.setModeOverride(.assigned("Test"), for: peak.id)
        #expect(sut.hasManualOverride(for: peak.id), ".assigned should be a manual override")
    }

    // Clearing an override (setting .auto) reverts to auto-classification.
    @Test func clearOverride_revertsToAutoLabel() {
        let sut = makeSUT()
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .acoustic
        defer { TapDisplaySettings.measurementType = savedType }
        let peak = makePeak(frequency: 100)  // Air mode

        sut.setModeOverride(.assigned("Temp"), for: peak.id)
        sut.setModeOverride(.auto, for: peak.id)

        let label = sut.effectiveModeLabel(for: peak)
        #expect(label == "Air (Helmholtz)")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Annotation Visibility Cycle  (CI5)
// ---------------------------------------------------------------------------

@Suite("AnnotationVisibilityCycle")
struct AnnotationVisibilityCycleTests {

    // CI5: Three calls to cycleAnnotationVisibility traverse all → selected → none → all.
    @Test func cycleAnnotationVisibility_traversesAllModes() {
        let sut = makeSUT()
        sut.annotationVisibilityMode = .all

        sut.cycleAnnotationVisibility()
        #expect(sut.annotationVisibilityMode == .selected)

        sut.cycleAnnotationVisibility()
        #expect(sut.annotationVisibilityMode == .none)

        sut.cycleAnnotationVisibility()
        #expect(sut.annotationVisibilityMode == .all)
    }

    // The .next cycle on the AnnotationVisibilityMode enum itself: all → selected → none → all.
    // Moved from GuitarModeTests where it was incorrectly placed.
    @Test func annotationVisibilityCycle_allToSelectedToNoneToAll() {
        var mode = AnnotationVisibilityMode.all
        mode = mode.next
        #expect(mode == .selected)
        mode = mode.next
        #expect(mode == .none)
        mode = mode.next
        #expect(mode == .all)
    }

    // Every case of AnnotationVisibilityMode must supply a non-empty SF Symbol name.
    @Test func annotationVisibility_iconNames_nonEmpty() {
        for mode in AnnotationVisibilityMode.allCases {
            #expect(!mode.iconName.isEmpty, "Icon name for \(mode) should not be empty")
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Update Measurement  (moved from MeasurementCodableTests)
//
// Tests TapToneAnalyzer.updateMeasurement(at:tapLocation:notes:) — a state-
// mutation operation on the live analyzer, not a JSON serialisation test.
// Mirrors Python TestUpdateMeasurement in test_annotation_state.py.
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
// MARK: - Plate Peak Selection  (PS1–PS6)
// ---------------------------------------------------------------------------

@Suite("PlatePeakSelection")
@MainActor
struct PlatePeakSelectionTests {

    // PS1: selectLongitudinalPeak selects an unassigned peak.
    @Test func selectLongitudinalPeak_selectsNewPeak() {
        let sut = makeSUT()
        let peakID = UUID()
        sut.selectLongitudinalPeak(peakID)
        #expect(sut.userSelectedLongitudinalPeakID == peakID,
                "userSelectedLongitudinalPeakID should be set to the new peak")
    }

    // PS2: selectLongitudinalPeak deselects when called with the already-selected peak.
    @Test func selectLongitudinalPeak_deselectsCurrentPeak() {
        let sut = makeSUT()
        let peakID = UUID()
        sut.userSelectedLongitudinalPeakID = peakID
        sut.selectLongitudinalPeak(peakID)
        #expect(sut.userSelectedLongitudinalPeakID == nil,
                "Selecting the already-selected longitudinal peak should deselect it")
    }

    // PS3: selectLongitudinalPeak clears a conflicting cross assignment.
    @Test func selectLongitudinalPeak_clearsCrossConflict() {
        let sut = makeSUT()
        let sharedID = UUID()
        sut.userSelectedCrossPeakID = sharedID
        sut.selectLongitudinalPeak(sharedID)
        #expect(sut.userSelectedLongitudinalPeakID == sharedID,
                "Longitudinal should be set to the shared peak")
        #expect(sut.userSelectedCrossPeakID == nil,
                "Cross selection should be cleared when the same peak is selected as longitudinal")
    }

    // PS4: selectLongitudinalPeak clears a conflicting Flc assignment.
    @Test func selectLongitudinalPeak_clearsFlcConflict() {
        let sut = makeSUT()
        let sharedID = UUID()
        sut.userSelectedFlcPeakID = sharedID
        sut.selectLongitudinalPeak(sharedID)
        #expect(sut.userSelectedLongitudinalPeakID == sharedID)
        #expect(sut.userSelectedFlcPeakID == nil,
                "Flc selection should be cleared when the same peak is selected as longitudinal")
    }

    // PS5: selectCrossPeak clears a conflicting longitudinal assignment.
    @Test func selectCrossPeak_clearsLongitudinalConflict() {
        let sut = makeSUT()
        let sharedID = UUID()
        sut.userSelectedLongitudinalPeakID = sharedID
        sut.selectCrossPeak(sharedID)
        #expect(sut.userSelectedCrossPeakID == sharedID)
        #expect(sut.userSelectedLongitudinalPeakID == nil,
                "Longitudinal selection should be cleared when the same peak is selected as cross")
    }

    // PS6: selectFlcPeak clears a conflicting cross assignment.
    @Test func selectFlcPeak_clearsCrossConflict() {
        let sut = makeSUT()
        let sharedID = UUID()
        sut.userSelectedCrossPeakID = sharedID
        sut.selectFlcPeak(sharedID)
        #expect(sut.userSelectedFlcPeakID == sharedID)
        #expect(sut.userSelectedCrossPeakID == nil,
                "Cross selection should be cleared when the same peak is selected as Flc")
    }
}
