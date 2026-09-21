//
//  MeasurementNameTests.swift
//  GuitarTapTests
//
//  Pins the required-name rule (FILE-PATHS-AND-NAMES-SPEC §3): a measurement name must be
//  non-empty after trimming before Save is allowed, and the stored name is trimmed. The Save
//  button binds to isValidName; the save path stores normalizedName. Three-way with Python
//  test_measurement_name.py and web measurement-name.test.ts.
//
// @parity test/measurement-name

import Testing
import Foundation
@testable import GuitarTap

@Suite("MeasurementName")
struct MeasurementNameTests {

    // MARK: - isValidName — what enables Save

    @Test func emptyAndWhitespace_areInvalid() {
        #expect(TapToneMeasurement.isValidName("") == false)
        #expect(TapToneMeasurement.isValidName("   ") == false)
        #expect(TapToneMeasurement.isValidName("\t\n ") == false)
    }

    @Test func anyRealText_isValid() {
        #expect(TapToneMeasurement.isValidName("x") == true)
        #expect(TapToneMeasurement.isValidName("Martin 000-28") == true)
        #expect(TapToneMeasurement.isValidName("  padded  ") == true)  // trims to non-empty
    }

    // MARK: - normalizedName — what gets stored

    @Test func normalized_trimsAndBlanksToNil() {
        #expect(TapToneMeasurement.normalizedName("  Martin 000-28  ") == "Martin 000-28")
        #expect(TapToneMeasurement.normalizedName("Ramírez") == "Ramírez")
        #expect(TapToneMeasurement.normalizedName("") == nil)
        #expect(TapToneMeasurement.normalizedName("   ") == nil)
    }

    // MARK: - normalizedNotes — the other user-entered field, normalized the same way

    // Notes trim exactly as the name does. Swift stored them verbatim until the #17 sweep while
    // both ports trimmed; the ports were right. It matters because "has this been edited" compares
    // stored values: if one path trims and another does not, reopening an untouched measurement
    // reads as an edit. See SLUG-SWEEP.md F21.
    @Test func normalizedNotes_trimsAndBlanksToNil() {
        #expect(TapToneMeasurement.normalizedNotes("  Tapped cold  ") == "Tapped cold")
        #expect(TapToneMeasurement.normalizedNotes("line one\nline two") == "line one\nline two")
        #expect(TapToneMeasurement.normalizedNotes("") == nil)
        #expect(TapToneMeasurement.normalizedNotes("   \n  ") == nil)
    }

    // The two fields must agree, or a round trip through one of them looks like an edit.
    @Test func bothFieldsNormalizeIdentically() {
        for candidate in ["", "  ", "\n", "a", "  a  ", "Spruce Top", " multi word \n"] {
            #expect(TapToneMeasurement.normalizedName(candidate) == TapToneMeasurement.normalizedNotes(candidate),
                    "name and notes must normalize identically for \(candidate.debugDescription)")
        }
    }

    // MARK: - The rule is consistent: valid ⇒ stores non-nil; invalid ⇒ nil

    @Test func validityMatchesStorage() {
        for candidate in ["", "  ", "\n", "a", "  a  ", "Spruce Top"] {
            let valid = TapToneMeasurement.isValidName(candidate)
            let stored = TapToneMeasurement.normalizedName(candidate)
            #expect(valid == (stored != nil),
                    "isValidName(\(candidate.debugDescription)) must agree with normalizedName != nil")
        }
    }
}