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