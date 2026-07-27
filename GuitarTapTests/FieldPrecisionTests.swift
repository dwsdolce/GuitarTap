//
//  FieldPrecisionTests.swift
//  GuitarTapTests
//

// @parity test/field-precision
//
// Pins the numeric-precision single source of truth (`FieldPrecision`): the per-field decimal table,
// the restrict-on-entry predicate (`decimalsWithin`), half-away-from-zero rounding (`rounded`), and
// display formatting (`string`). The Python (`test_field_precision.py`) and web
// (`field-precision.test.ts`) suites mirror these cases exactly, so the table, regex, and rounding
// can never quietly drift apart across editions.

import Testing
@testable import GuitarTap

@Suite("FieldPrecision")
struct FieldPrecisionTests {

    // MARK: - Precision table

    @Test func table_matchesCanonicalValues() {
        #expect(FieldPrecision.linearDimensionMM == 2)
        #expect(FieldPrecision.massG == 1)
        #expect(FieldPrecision.bodyDimensionMM == 0)
        #expect(FieldPrecision.frequencyHz == 0)
        #expect(FieldPrecision.magnitudeDB == 0)
        #expect(FieldPrecision.stiffness == 0)
        #expect(FieldPrecision.peakFrequencyHz == 1)
        #expect(FieldPrecision.peakMagnitudeDB == 1)
        #expect(FieldPrecision.qFactor == 1)
        #expect(FieldPrecision.youngsModulusGPa == 2)
        #expect(FieldPrecision.speedOfSoundMS == 0)
        #expect(FieldPrecision.densityGPerCm3 == 3)
        #expect(FieldPrecision.decayRatio == 2)
    }

    // MARK: - decimalsWithin (restrict-on-entry predicate)

    @Test func decimalsWithin_acceptsWithinPrecision() {
        #expect(FieldPrecision.decimalsWithin("29.35", 2))
        #expect(FieldPrecision.decimalsWithin("29.3", 2))
        #expect(FieldPrecision.decimalsWithin("29", 2))
    }

    @Test func decimalsWithin_rejectsOverPrecision() {
        #expect(!FieldPrecision.decimalsWithin("29.356", 2))
        #expect(!FieldPrecision.decimalsWithin("29.35", 1))
    }

    @Test func decimalsWithin_acceptsTrailingDotWhileTyping() {
        #expect(FieldPrecision.decimalsWithin("29.", 2))
    }

    @Test func decimalsWithin_rejectsDotAtZeroDecimals() {
        #expect(!FieldPrecision.decimalsWithin("495.", 0))
        #expect(!FieldPrecision.decimalsWithin("495.5", 0))
        #expect(FieldPrecision.decimalsWithin("495", 0))
    }

    @Test func decimalsWithin_acceptsInProgressEmptyAndMinus() {
        #expect(FieldPrecision.decimalsWithin("", 2))
        #expect(FieldPrecision.decimalsWithin("-", 2))
        #expect(FieldPrecision.decimalsWithin("", 0))
        #expect(FieldPrecision.decimalsWithin("-", 0))
    }

    @Test func decimalsWithin_acceptsNegative() {
        #expect(FieldPrecision.decimalsWithin("-45", 0))
        #expect(FieldPrecision.decimalsWithin("-45.5", 1))
        #expect(!FieldPrecision.decimalsWithin("-45.55", 1))
    }

    @Test func decimalsWithin_rejectsNonNumeric() {
        #expect(!FieldPrecision.decimalsWithin("4a", 0))
        #expect(!FieldPrecision.decimalsWithin("abc", 2))
        #expect(!FieldPrecision.decimalsWithin("2..5", 2))
    }

    // MARK: - rounded (half away from zero)

    @Test func rounded_halfAwayFromZero() {
        #expect(FieldPrecision.rounded(2.5, 0) == 3)
        #expect(FieldPrecision.rounded(0.5, 0) == 1)
        #expect(FieldPrecision.rounded(-2.5, 0) == -3)
        #expect(FieldPrecision.rounded(-0.5, 0) == -1)
    }

    @Test func rounded_roundsToPrecision() {
        #expect(abs(FieldPrecision.rounded(29.356, 2) - 29.36) < 0.001)
        #expect(abs(FieldPrecision.rounded(29.354, 2) - 29.35) < 0.001)
        #expect(abs(FieldPrecision.rounded(29.35, 2) - 29.35) < 0.001)
    }

    @Test func rounded_negativeRoundsAwayFromZero() {
        #expect(abs(FieldPrecision.rounded(-29.356, 2) - (-29.36)) < 0.001)
    }

    // MARK: - string (display formatting)

    @Test func string_formatsAtPrecision() {
        #expect(FieldPrecision.string(29.4, 2) == "29.40")
        #expect(FieldPrecision.string(29, 0) == "29")
        #expect(FieldPrecision.string(-100, 0) == "-100")
        #expect(FieldPrecision.string(2.5, 1) == "2.5")
    }

    @Test func string_roundsForDisplay() {
        #expect(FieldPrecision.string(2.678, 2) == "2.68")
    }
}
