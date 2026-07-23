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
// @parity test/annotation-state

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

    // Select All was removed in Phase 5: Air, Top and Back can each have only ONE definitive
    // (selected) peak, so "everything selected" is not a state the model can hold. The tests that
    // pinned it (selectAllPeaks_selectsAllCurrentPeaks, selectAllPeaks_setsModifiedFlag) went with
    // the feature rather than being rewritten.

    // selectNoPeaks clears all selections.
    @Test func selectNoPeaks_clearsAll() {
        let sut = makeSUT()
        let peaks = [makePeak(frequency: 100), makePeak(frequency: 200)]
        sut.allPeaks = peaks
        sut.selectedPeakIDs = Set(peaks.map(\.id))

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
        sut.allPeaks = [quietAir, loudAir]

        // Simulate user having made a manual change
        sut.userHasModifiedPeakSelection = true
        sut.selectedPeakIDs = []

        sut.resetToAutoSelection()

        #expect(!sut.userHasModifiedPeakSelection, "Flag should be cleared after resetToAutoSelection")
        #expect(sut.selectedPeakIDs.contains(loudAir.id), "Loudest Air peak should be auto-selected")
        #expect(!sut.selectedPeakIDs.contains(quietAir.id), "Quieter Air peak should not be selected")
    }

    // resetToAutoSelection on empty peaksAbovePeakMin is a no-op (no crash).
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

    // D4: .all mode returns all peaksAbovePeakMin.
    @Test func allMode_returnsAllCurrentPeaks() {
        let sut = makeSUT()
        sut.annotationVisibilityMode = .all
        let peaks = [makePeak(frequency: 100), makePeak(frequency: 200), makePeak(frequency: 300)]
        sut.allPeaks = peaks

        #expect(sut.visiblePeaks.count == 3)
    }

    // D5: .selected mode returns only peaks whose IDs are in selectedPeakIDs.
    @Test func selectedMode_filtersToSelectedPeaks() {
        let sut = makeSUT()
        sut.annotationVisibilityMode = .selected
        let p1 = makePeak(frequency: 100)
        let p2 = makePeak(frequency: 200)
        let p3 = makePeak(frequency: 300)
        sut.allPeaks = [p1, p2, p3]
        sut.selectedPeakIDs = [p1.id, p3.id]

        let visible = sut.visiblePeaks
        #expect(visible.count == 2)
        #expect(visible.map(\.frequency).contains(100))
        #expect(visible.map(\.frequency).contains(300))
        #expect(!visible.map(\.frequency).contains(200))
    }

    // D6: .none mode returns empty array regardless of peaksAbovePeakMin.
    @Test func noneMode_returnsEmpty() {
        let sut = makeSUT()
        sut.annotationVisibilityMode = .none
        let peaks = [makePeak(), makePeak(frequency: 300)]
        sut.allPeaks = peaks
        sut.selectedPeakIDs = Set(peaks.map(\.id))   // selection is incidental here; .none wins

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

    // D8b: autoDetectedMode is override-blind — it names what "Reset to Auto-Detected" restores to,
    // NOT the current label. Overriding a peak to another mode must not change the value the reset
    // menu item advertises. (Regression guard: the desktop menu and iOS sheet used to show the
    // current mode here, so after a rename the reset item named the override rather than its target.)
    @Test func autoDetectedMode_ignoresOverride() {
        let sut = makeSUT()
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .acoustic
        defer { TapDisplaySettings.measurementType = savedType }

        let air = makePeak(frequency: 100)     // classifies Air for acoustic
        sut.allPeaks = [air]
        sut.reclassifyPeaks()
        #expect(sut.autoDetectedMode(for: air).normalized == .air, "precondition: auto-detects Air")

        sut.setModeOverride(.assigned(GuitarMode.top.displayName), for: air.id)

        #expect(sut.effectiveModeLabel(for: air) == GuitarMode.top.displayName,
                "the visible label follows the override")
        #expect(sut.autoDetectedMode(for: air).normalized == .air,
                "…but the reset target is still the auto-detected Air, not the override")
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
// Tests TapToneAnalyzer.updateMeasurement(at:measurementName:notes:) — a state-
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

    // Editing one of two duplicates (same id, different index) leaves the other unchanged.
    @Test func update_duplicateImport_onlyEditedIndexChanges() {
        let original = makeMeasurement(measurementName: "Top", notes: "Original")
        // Simulate importing the same file twice — both entries share the same id.
        let analyzer = makeAnalyzerWithMeasurements([original, original])

        analyzer.updateMeasurement(at: 1, measurementName: "Back", notes: "Copy")

        #expect(analyzer.savedMeasurements[0].measurementName == "Top",  "First duplicate must not change")
        #expect(analyzer.savedMeasurements[0].notes == "Original",   "First duplicate must not change")
        #expect(analyzer.savedMeasurements[1].measurementName == "Back", "Second duplicate should be updated")
        #expect(analyzer.savedMeasurements[1].notes == "Copy",       "Second duplicate should be updated")
        #expect(analyzer.savedMeasurements[0].id == analyzer.savedMeasurements[1].id,
                "id must be preserved through the update")
    }

    // Passing nil clears the fields.
    @Test func update_nilValues_clearFields() {
        let m = makeMeasurement(measurementName: "Bridge", notes: "Some notes")
        let analyzer = makeAnalyzerWithMeasurements([m])

        analyzer.updateMeasurement(at: 0, measurementName: nil, notes: nil)

        #expect(analyzer.savedMeasurements[0].measurementName == nil)
        #expect(analyzer.savedMeasurements[0].notes == nil)
    }

    // An out-of-range index is a no-op.
    @Test func update_outOfRangeIndex_isNoOp() {
        let m = makeMeasurement(measurementName: "Bridge")
        let analyzer = makeAnalyzerWithMeasurements([m])

        analyzer.updateMeasurement(at: 99, measurementName: "Changed", notes: nil)

        #expect(analyzer.savedMeasurements[0].measurementName == "Bridge", "Out-of-range update must not modify array")
        #expect(analyzer.savedMeasurements.count == 1)
    }

    // The id and all other fields are preserved after an update.
    @Test func update_preservesIdAndOtherFields() {
        let peak = ResonantPeak(frequency: 195, magnitude: -22)
        let m = TapToneMeasurement(peaks: [peak], decayTime: 0.5, measurementName: "Old", notes: "Old notes")
        let originalID = m.id
        let analyzer = makeAnalyzerWithMeasurements([m])

        analyzer.updateMeasurement(at: 0, measurementName: "New", notes: "New notes")

        let updated = analyzer.savedMeasurements[0]
        #expect(updated.id == originalID, "id must be preserved")
        #expect(updated.peaks.count == 1,  "peaks must be preserved")
        #expect(updated.decayTime == 0.5,  "decayTime must be preserved")
        #expect(updated.measurementName == "New")
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

// ---------------------------------------------------------------------------
// MARK: - Definitive Air/Top/Back uniqueness  (D11–D16) — Phase 5
// ---------------------------------------------------------------------------
//
// Classification and selection are independent. Classification is band membership: five peaks in
// the Air band are five Air peaks. Selection picks which one is DEFINITIVE, and Air/Top/Back may
// have at most one each — they are single physical resonances. Dipole/Ring/Upper are clusters and
// stay unconstrained.
//
// Deselecting never relabels: a displaced peak remains classified Air/Top/Back, it just stops being
// the definitive one.
//
// Generic bands: air 70–135, top 140–260, back 180–300, dipole 310–460. The Top fixtures below sit
// under 180 so they cannot also be Back.

@Suite("DefinitiveModeUniqueness", .serialized)
@MainActor
struct DefinitiveModeUniquenessTests {

    private func makeGuitarSUT() -> TapToneAnalyzer {
        TapDisplaySettings.measurementType = .generic
        return makeSUT()
    }

    // D11: selecting a second Top displaces the first — and the displaced peak is STILL a Top peak.
    @Test func selectingASecondTop_displacesTheFirst_withoutReclassifying() {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        let sut = makeGuitarSUT()

        let topA = makePeak(frequency: 150, magnitude: -30)
        let topB = makePeak(frequency: 170, magnitude: -25)
        sut.allPeaks = [topA, topB]
        sut.reclassifyPeaks()

        sut.togglePeakSelection(topA.id)
        #expect(sut.selectedPeakIDs == [topA.id])

        sut.togglePeakSelection(topB.id)

        #expect(sut.selectedPeakIDs == [topB.id],
                "only one definitive Top — selecting B must displace A")
        #expect(sut.peakMode(for: topA).normalized == .top,
                "the displaced peak is STILL a Top peak; deselecting does not relabel it")
    }

    // D12: Dipole is a cluster — several selected peaks are legitimate there.
    @Test func dipoleAllowsSeveralSelectedPeaks() {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        let sut = makeGuitarSUT()

        let d1 = makePeak(frequency: 320, magnitude: -30)
        let d2 = makePeak(frequency: 400, magnitude: -25)
        sut.allPeaks = [d1, d2]
        sut.reclassifyPeaks()
        #expect(sut.peakMode(for: d1).normalized == .dipole, "fixture precondition")

        sut.togglePeakSelection(d1.id)
        sut.togglePeakSelection(d2.id)

        #expect(sut.selectedPeakIDs == [d1.id, d2.id],
                "Dipole is not a single-holder mode — both stay selected")
    }

    // D13: relabelling an ALREADY-SELECTED peak into Top displaces the current definitive Top.
    @Test func overridingASelectedPeakIntoTop_displacesTheDefinitiveTop() {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        let sut = makeGuitarSUT()

        let top = makePeak(frequency: 150, magnitude: -30)
        let air = makePeak(frequency: 90, magnitude: -25)
        sut.allPeaks = [top, air]
        sut.reclassifyPeaks()
        sut.togglePeakSelection(top.id)
        sut.togglePeakSelection(air.id)
        #expect(sut.selectedPeakIDs == [top.id, air.id], "one Air and one Top, both definitive")

        sut.setModeOverride(.assigned(GuitarMode.top.displayName), for: air.id)

        #expect(sut.selectedPeakIDs == [air.id],
                "the relabelled peak becomes the definitive Top; the previous holder is displaced")
        #expect(sut.peakMode(for: top).normalized == .top,
                "the displaced peak keeps its Top classification")
    }

    // D14: relabelling an UNSELECTED peak changes no selection — it just becomes another candidate.
    @Test func overridingAnUnselectedPeakIntoTop_changesNoSelection() {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        let sut = makeGuitarSUT()

        let top = makePeak(frequency: 150, magnitude: -30)
        let air = makePeak(frequency: 90, magnitude: -25)
        sut.allPeaks = [top, air]
        sut.reclassifyPeaks()
        sut.togglePeakSelection(top.id)

        sut.setModeOverride(.assigned(GuitarMode.top.displayName), for: air.id)

        #expect(sut.selectedPeakIDs == [top.id],
                "overriding an unselected peak must not touch selection")
        #expect(sut.peakMode(for: air).normalized == .top, "…though it IS now a Top candidate")
    }

    // D15: overriding the definitive Top AWAY from Top leaves Top with no definitive peak.
    // Nothing is auto-promoted — there is no promotion rule, deliberately.
    @Test func overridingTheDefinitiveTopAway_leavesTopWithNoHolder() {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        let sut = makeGuitarSUT()

        let topA = makePeak(frequency: 150, magnitude: -30)
        let topB = makePeak(frequency: 170, magnitude: -25)
        sut.allPeaks = [topA, topB]
        sut.reclassifyPeaks()
        sut.togglePeakSelection(topA.id)

        sut.setModeOverride(.assigned("Wolf note"), for: topA.id)

        #expect(sut.peakMode(for: topA).normalized == .unknown, "freeform label, so no longer Top")
        #expect(!sut.selectedPeakIDs.contains(topB.id),
                "topB must NOT be auto-promoted to definitive Top")
        #expect(sut.selectedPeakIDs == [topA.id],
                "the relabelled peak stays selected — it is simply no longer a Top")
    }

    // D16: Select None is a legitimate state — no definitive peaks, classification untouched.
    @Test func selectNone_leavesClassificationIntact() {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        let sut = makeGuitarSUT()

        let top = makePeak(frequency: 150, magnitude: -30)
        let air = makePeak(frequency: 90, magnitude: -25)
        sut.allPeaks = [top, air]
        sut.reclassifyPeaks()
        sut.togglePeakSelection(top.id)

        sut.selectNoPeaks()

        #expect(sut.selectedPeakIDs.isEmpty, "no definitive peaks is a legitimate state")
        #expect(sut.peakMode(for: top).normalized == .top)
        #expect(sut.peakMode(for: air).normalized == .air)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Definitive peak & tap-tone ratio  (D17–D20) — Phase 6
// ---------------------------------------------------------------------------
//
// getPeak(for:) and calculateTapToneRatio resolve the DEFINITIVE peak: the selected peak whose
// override-aware mode is that mode. Deselecting it, or relabelling it, removes it here exactly as it
// does on the chart - so the on-screen ratio and the saved-list ratio cannot disagree.

@Suite("DefinitivePeakAndRatio", .serialized)
@MainActor
struct DefinitivePeakAndRatioTests {

    private func makeGuitarSUT() -> TapToneAnalyzer {
        TapDisplaySettings.measurementType = .generic
        return makeSUT()
    }

    // D17: getPeak returns the SELECTED holder, not merely the strongest in the band.
    @Test func getPeak_returnsSelectedHolder_notStrongest() {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        let sut = makeGuitarSUT()

        let loudTop = makePeak(frequency: 150, magnitude: -18)
        let weakTop = makePeak(frequency: 165, magnitude: -30)
        sut.allPeaks = [loudTop, weakTop]
        sut.reclassifyPeaks()
        sut.togglePeakSelection(weakTop.id)   // select the WEAKER one

        #expect(sut.getPeak(for: .top)?.id == weakTop.id,
                "the definitive Top is the selected peak, not the loudest candidate")
    }

    // D18: THE user-reported bug. Renaming the Top peak to a freeform label drops the ratio.
    @Test func renamingTheTopPeak_dropsTheRatio() {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        let sut = makeGuitarSUT()

        let air = makePeak(frequency: 100, magnitude: -25)
        let top = makePeak(frequency: 150, magnitude: -20)
        sut.allPeaks = [air, top]
        sut.reclassifyPeaks()
        sut.togglePeakSelection(air.id)
        sut.togglePeakSelection(top.id)
        #expect(sut.calculateTapToneRatio() != nil, "precondition: a ratio is shown")

        sut.setModeOverride(.assigned("Wolf note"), for: top.id)

        #expect(sut.getPeak(for: .top) == nil, "a renamed Top is no longer the definitive Top")
        #expect(sut.calculateTapToneRatio() == nil,
                "…so there is no ratio, matching the chart and the table")
    }

    // D19: deselecting the Top peak drops the ratio too.
    @Test func deselectingTheTopPeak_dropsTheRatio() {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        let sut = makeGuitarSUT()

        let air = makePeak(frequency: 100, magnitude: -25)
        let top = makePeak(frequency: 150, magnitude: -20)
        sut.allPeaks = [air, top]
        sut.reclassifyPeaks()
        sut.togglePeakSelection(air.id)
        sut.togglePeakSelection(top.id)
        #expect(sut.calculateTapToneRatio() != nil, "precondition")

        sut.togglePeakSelection(top.id)   // deselect Top

        #expect(sut.calculateTapToneRatio() == nil, "a deselected Top yields no ratio")
    }

    // D20: retargeting a peak TO Top via override makes it the definitive Top and restores the ratio.
    @Test func overridingAPeakToTop_makesItDefinitive() {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        let sut = makeGuitarSUT()

        let air = makePeak(frequency: 100, magnitude: -25)
        let far = makePeak(frequency: 400, magnitude: -20)   // generic: dipole, not Top
        sut.allPeaks = [air, far]
        sut.reclassifyPeaks()
        sut.togglePeakSelection(air.id)
        sut.togglePeakSelection(far.id)
        #expect(sut.getPeak(for: .top) == nil, "precondition: no Top yet")

        sut.setModeOverride(.assigned(GuitarMode.top.displayName), for: far.id)

        #expect(sut.getPeak(for: .top)?.id == far.id, "the relabelled peak is now the definitive Top")
        #expect(sut.calculateTapToneRatio() != nil, "and the ratio returns")
    }

    // D21: the multi-tap Averaged row source. definitiveModeInfo is getPeak per mode plus an override
    // flag — the DEFINITIVE selected peak, NOT a strongest-per-mode re-classification (the old
    // resolvedModePeaks path that produced the 233-as-Top / empty-Back bug). Here: an out-of-band
    // peak overridden to Top is the Top, tagged; the louder in-band 233 does not usurp it.
    @Test func definitiveModeInfo_usesOverriddenDefinitiveTop_andFlagsIt() {
        let saved = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = saved }
        let sut = makeGuitarSUT()

        let air      = makePeak(frequency: 100, magnitude: -25)
        let belowTop = makePeak(frequency: 138, magnitude: -30)  // below the Top band → unknown by position
        let louder   = makePeak(frequency: 233, magnitude: -18)  // louder, in the top band by position
        sut.allPeaks = [air, belowTop, louder]
        sut.reclassifyPeaks()
        sut.togglePeakSelection(air.id)
        sut.togglePeakSelection(belowTop.id)
        sut.setModeOverride(.assigned(GuitarMode.top.displayName), for: belowTop.id)  // 138 → Top

        let info = sut.definitiveModeInfo()
        #expect(info[.top]?.frequency == 138,
                "Top is the overridden+selected peak — not the louder 233, which is not selected")
        #expect(info[.top]?.isOverride == true, "flagged as an override so the Averaged row can tag it")
        #expect(info[.air]?.isOverride == false, "Air here is auto — not tagged")
    }

    // D22: definitiveModeInfo follows SELECTION — a deselected Top yields no Top entry (and no tag).
    @Test func definitiveModeInfo_omitsDeselectedMode() {
        let saved = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = saved }
        let sut = makeGuitarSUT()

        let air = makePeak(frequency: 100, magnitude: -25)
        let top = makePeak(frequency: 150, magnitude: -20)
        sut.allPeaks = [air, top]
        sut.reclassifyPeaks()
        sut.togglePeakSelection(air.id)   // Top left unselected

        let info = sut.definitiveModeInfo()
        #expect(info[.top] == nil, "an unselected Top is not the definitive Top")
        #expect(info[.air]?.frequency == 100)
    }
}
