//
//  MeasurementAmendTests.swift
//  GuitarTapTests
//

// @parity test/measurement-amend
//
// The AMEND rule: what it means to change a saved measurement's name or notes.
//
// Name and notes are part of a measurement's DATA, not annotations on top of it, so an amended
// measurement is a different dataset and must carry a different `id`. That gives the identity its
// meaning — same `id` ⟺ same content — and it is why `isAmended` exists: a Save that changes
// nothing would hand unchanged content a new identity, so the edit sheet must not allow one.
//
// These cases lived under test/measurement-codable, which is about serialisation; the amend rule is
// not a serialisation concern and web had no counterpart for it at all. Mirrors Python
// tests/test_measurement_amend.py and web test/measurement-amend.test.ts.

import Testing
import Foundation
@testable import GuitarTap

@Suite("MeasurementAmend")
struct MeasurementAmendTests {

    // MARK: - isAmended: the gate on Save

    @Test func isAmended_isFalseWhenNothingDiffers() {
        let m = TapToneMeasurement(peaks: [], measurementName: "Bridge", notes: "Some notes")
        #expect(m.isAmended(measurementName: "Bridge", notes: "Some notes") == false)
    }

    @Test func isAmended_isTrueWhenTheNameDiffers() {
        let m = TapToneMeasurement(peaks: [], measurementName: "Bridge", notes: "Some notes")
        #expect(m.isAmended(measurementName: "Neck", notes: "Some notes"))
    }

    @Test func isAmended_isTrueWhenTheNotesDiffer() {
        let m = TapToneMeasurement(peaks: [], measurementName: "Bridge", notes: "Some notes")
        #expect(m.isAmended(measurementName: "Bridge", notes: "Edited"))
    }

    @Test func isAmended_isTrueWhenAFieldIsCleared() {
        let m = TapToneMeasurement(peaks: [], measurementName: "Bridge", notes: "Some notes")
        #expect(m.isAmended(measurementName: "Bridge", notes: nil))
        #expect(m.isAmended(measurementName: nil, notes: "Some notes"))
    }

    // Whitespace-only retyping is NOT an edit, because both fields normalize the same way. This is
    // the case that made the rule worth sharing: the edit sheet normalizes, so it must compare
    // against normalized values or Save lights up for a change that would never be stored.
    @Test func isAmended_isFalseForWhitespaceOnlyDifferences() {
        let m = TapToneMeasurement(peaks: [], measurementName: "Bridge", notes: "Some notes")
        let name  = TapToneMeasurement.normalizedName("  Bridge  ")
        let notes = TapToneMeasurement.normalizedNotes("\n Some notes \n")
        #expect(m.isAmended(measurementName: name, notes: notes) == false)
    }

    @Test func isAmended_handlesAMeasurementWithNoNameOrNotes() {
        let m = TapToneMeasurement(peaks: [])
        #expect(m.isAmended(measurementName: nil, notes: nil) == false)
        #expect(m.isAmended(measurementName: "Named", notes: nil))
    }

    // MARK: - with(): the amend itself

    // Updating measurementName via with() returns a copy with the new measurementName and a
    // NEW id — name and notes are data, so an amended measurement is a different dataset.
    @Test func with_updatesMeasurementName() {
        let original = TapToneMeasurement(peaks: [], measurementName: "Old")
        let updated = original.with(measurementName: "New", notes: nil)
        #expect(updated.measurementName == "New")
        #expect(updated.id != original.id, "an amended measurement is a different dataset")
    }

    // Updating notes via with() returns a copy with the new notes.
    @Test func with_updatesNotes() {
        let original = TapToneMeasurement(peaks: [], notes: "old notes")
        let updated = original.with(measurementName: nil, notes: "new notes")
        #expect(updated.notes == "new notes")
    }

    // Passing nil for measurementName clears it in the copy.
    @Test func with_clearsMeasurementNameWithNil() {
        let original = TapToneMeasurement(peaks: [], measurementName: "Bridge")
        let updated = original.with(measurementName: nil, notes: nil)
        #expect(updated.measurementName == nil)
        #expect(updated.id != original.id, "clearing the fields is a data change too, so it mints")
    }

    // Every captured field, and the capture time, are preserved in the returned copy. Only the
    // amended fields and the id change.
    @Test func with_preservesOtherFields() throws {
        let peak = ResonantPeak(frequency: 195, magnitude: -20)
        let snap = SpectrumSnapshot(
            frequencies: [100, 200], magnitudes: [-30, -20],
            minFreq: 50, maxFreq: 500, minDB: -100, maxDB: 0, isLogarithmic: false
        )
        let original = TapToneMeasurement(peaks: [peak], decayTime: 0.5, measurementName: "Bridge", spectrum: snap)
        let updated = original.with(measurementName: "Neck", notes: nil)
        #expect(updated.peaks.count == 1)
        #expect(updated.decayTime == 0.5, "decayTime must be preserved")
        #expect(updated.measurementName == "Neck")
        #expect(updated.timestamp == original.timestamp,
                "timestamp records the capture, which amending does not change")
        #expect(updated.spectrumSnapshot?.frequencies.count == 2, "the spectrum must be preserved")
    }

    // Two successive amendments yield three distinct ids: identity tracks content.
    @Test func with_successiveAmendments_eachMintANewId() {
        let a = TapToneMeasurement(peaks: [], measurementName: "First")
        let b = a.with(measurementName: "Second", notes: nil)
        let c = b.with(measurementName: "Third", notes: nil)
        #expect(a.id != b.id)
        #expect(b.id != c.id)
        #expect(a.id != c.id)
    }
}
