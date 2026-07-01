//
//  PitchTests.swift
//  GuitarTapTests
//
//  Tests for the Pitch class — note identification, cents calculation,
//  nearest-note frequency, and in-tune detection.
//  All computations are pure math, requiring no hardware.
//
// @parity test/pitch

import Testing
import Foundation
@testable import GuitarTap

@Suite("Pitch")
struct PitchTests {

    // MARK: - Note identification

    // A4 at exactly 440 Hz should return the note string "A4".
    @Test func a4_exactFrequency_returnsA4() {
        let p = Pitch(a4: 440)
        #expect(p.note(frequency: 440) == "A4")
    }

    // Middle C (C4) at ~261.63 Hz.
    @Test func middleC_returnsC4() {
        let p = Pitch(a4: 440)
        // C4 = A4 * 2^(-9/12) ≈ 261.626
        let c4 = 440.0 * pow(2.0, -9.0/12.0)
        #expect(p.note(frequency: c4) == "C4")
    }

    // An octave above A4 (880 Hz) should return "A5".
    @Test func a5_returnsA5() {
        let p = Pitch(a4: 440)
        #expect(p.note(frequency: 880) == "A5")
    }

    // An octave below A4 (220 Hz) should return "A3".
    @Test func a3_returnsA3() {
        let p = Pitch(a4: 440)
        #expect(p.note(frequency: 220) == "A3")
    }

    // MARK: - Cents calculation

    // Exact pitch → 0 cents offset.
    @Test func exactPitch_zeroConts() {
        let p = Pitch(a4: 440)
        let cents = p.cents(frequency: 440)
        #expect(abs(cents) < 0.5, "Expected ~0 cents for exact A4, got \(cents)")
    }

    // One semitone above A4 = A#4 ≈ 466.16 Hz → cents should be near 0 for A#4.
    @Test func oneSmitoneAbove_centsNearZero() {
        let p = Pitch(a4: 440)
        let asharp4 = 440.0 * pow(2.0, 1.0/12.0)
        let cents = p.cents(frequency: asharp4)
        #expect(abs(cents) < 0.5, "Expected ~0 cents for exact A#4, got \(cents)")
    }

    // A frequency halfway between two notes → ±50 cents.
    @Test func halfSemitoneOffset_isAbout50Cents() {
        let p = Pitch(a4: 440)
        // Geometric midpoint between A4 and A#4 in cents = +50 cents from A4
        let midFreq = 440.0 * pow(2.0, 0.5/12.0)
        let cents = p.cents(frequency: midFreq)
        #expect(abs(abs(cents) - 50) < 1, "Expected ≈ ±50 cents at midpoint, got \(cents)")
    }

    // MARK: - Nearest note frequency

    // freq0 for 440 Hz should return 440 Hz.
    @Test func freq0_a4_returns440() {
        let p = Pitch(a4: 440)
        let f0 = p.freq0(frequency: 440)
        #expect(abs(f0 - 440) < 0.01)
    }

    // freq0 for 444 Hz (slightly sharp A4) should also return 440 Hz.
    @Test func freq0_slightlySharp_returnsExactNote() {
        let p = Pitch(a4: 440)
        let f0 = p.freq0(frequency: 444)
        #expect(abs(f0 - 440) < 0.01, "Nearest note to 444 Hz is A4 = 440 Hz, got \(f0)")
    }

    // MARK: - In-tune detection

    // Exact pitch at default 10-cent threshold → in tune.
    @Test func exactPitch_isInTune() {
        let p = Pitch(a4: 440)
        #expect(p.isInTune(frequency: 440))
    }

    // 15 cents sharp at default 10-cent threshold → out of tune.
    @Test func fifteenCentsSharp_isNotInTune() {
        let p = Pitch(a4: 440)
        let sharpFreq = 440.0 * pow(2.0, 15.0/1200.0)  // +15 cents
        #expect(!p.isInTune(frequency: sharpFreq))
    }

    // 8 cents flat at 10-cent threshold → in tune.
    @Test func eightCentsFlat_isInTune() {
        let p = Pitch(a4: 440)
        let flatFreq = 440.0 * pow(2.0, -8.0/1200.0)   // -8 cents
        #expect(p.isInTune(frequency: flatFreq))
    }

    // MARK: - A4 tuning reference change

    // Changing A4 to 432 Hz should shift note identifications accordingly.
    @Test func a4Tuning432_shiftsNoteNames() {
        let p432 = Pitch(a4: 432)
        // 432 Hz is A4 in this tuning
        #expect(p432.note(frequency: 432) == "A4")
        // 440 Hz should now be slightly sharp — still A4 but not exactly
        let cents = p432.cents(frequency: 440)
        #expect(cents > 0, "440 Hz should be sharp relative to 432 Hz A4 tuning")
    }

    // MARK: - formattedNote

    // Formatted note for exact A4 should contain "A4" and "+0" or "0" cents.
    @Test func formattedNote_a4_containsA4() {
        let p = Pitch(a4: 440)
        let formatted = p.formattedNote(frequency: 440)
        #expect(formatted.contains("A4"), "Formatted note should contain 'A4': \(formatted)")
    }

    // A sharp frequency shows '+' and a flat frequency shows '-' in the formatted output.
    @Test func formattedNote_includesSign() {
        let p = Pitch(a4: 440)
        let sharp = p.formattedNote(frequency: 442)
        #expect(sharp.contains("+"), "Sharp note should show '+' in formatted output: \(sharp)")
        let flat = p.formattedNote(frequency: 438)
        #expect(flat.contains("-"), "Flat note should show '-' in formatted output: \(flat)")
    }

    // MARK: - Cents sign

    // Frequency below the nearest note → negative cents.
    @Test func cents_negativeWhenFlat() {
        let p = Pitch(a4: 440)
        let c = p.cents(frequency: 438)   // just below A4
        #expect(c < 0, "Flat frequency should give negative cents; got \(c)")
    }

    // Frequency above the nearest note → positive cents.
    @Test func cents_positiveWhenSharp() {
        let p = Pitch(a4: 440)
        let c = p.cents(frequency: 442)   // just above A4
        #expect(c > 0, "Sharp frequency should give positive cents; got \(c)")
    }

    // MARK: - In-tune boundary cases

    // 9.9 cents sharp (just inside default 10-cent threshold) → in tune.
    @Test func justUnder10CentsSharp_isInTune() {
        let p = Pitch(a4: 440)
        let freq = 440.0 * pow(2.0, 9.9 / 1200.0)
        #expect(p.isInTune(frequency: freq), "9.9 cents sharp should be in tune")
    }

    // 11 cents sharp (outside default 10-cent threshold) → out of tune.
    @Test func elevenCentsSharp_isNotInTune() {
        let p = Pitch(a4: 440)
        let freq = 440.0 * pow(2.0, 11.0 / 1200.0)
        #expect(!p.isInTune(frequency: freq), "11 cents sharp should NOT be in tune")
    }

    // 15 cents flat (outside default 10-cent threshold) → out of tune.
    @Test func fifteenCentsFlat_isNotInTune() {
        let p = Pitch(a4: 440)
        let freq = 440.0 * pow(2.0, -15.0 / 1200.0)
        #expect(!p.isInTune(frequency: freq), "15 cents flat should NOT be in tune")
    }

    // Custom threshold parameter is respected.
    @Test func customThreshold_isRespected() {
        let p = Pitch(a4: 440)
        let fiveCentsSharp = 440.0 * pow(2.0, 5.0 / 1200.0)
        #expect(p.isInTune(frequency: fiveCentsSharp, threshold: 10), "5 cents is in tune at 10-cent threshold")
        #expect(!p.isInTune(frequency: fiveCentsSharp, threshold: 4),  "5 cents is NOT in tune at 4-cent threshold")
    }

    // MARK: - A4 reference at 432 Hz

    // freq0 for A4 under a 432 Hz reference should return 432, not 440.
    @Test func a4Tuning432_changesNoteFrequency() {
        let p432 = Pitch(a4: 432)
        #expect(p432.note(frequency: 432) == "A4")
        let f0 = p432.freq0(frequency: 432)
        #expect(abs(f0 - 432) < 0.01, "freq0 should return 432 Hz under 432 Hz A4 reference, got \(f0)")
    }
}
