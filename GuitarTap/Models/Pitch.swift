//
//  Pitch.swift
//  GuitarTap
//
//  Converted from pitch.py
//
// @parity dsp/pitch tests=test/pitch

/// # Pitch
///
/// Equal-temperament pitch analysis — note detection, cents deviation, and frequency conversion.
///
/// The calculations are based on the standard 12-tone equal-temperament (12-TET) system where
/// all semitones are equal-ratio intervals of `2^(1/12)`.  The reference pitch for the entire
/// scale is A4 (configurable; defaults to 440 Hz).
///
/// ## Algorithm Overview
///
/// 1. **C0 anchor** — C0 is derived from A4 by shifting 4 octaves down and 9 semitones down:
///    `f_C0 = f_A4 × 2^(−4.75)`.
/// 2. **Half-steps from C0** — Any frequency maps to a half-step count via
///    `h = round(12 × log₂(f / f_C0))`.
/// 3. **Note and octave** — `octave = h / 12`, `note = h % 12` (0 = C, 1 = C#, … 11 = B).
/// 4. **Frequency of a note** — `f(note, octave) = f_C0 × 2^(note/12) × 2^octave`.
/// 5. **Cents deviation** — `cents = 1200 × log₂(f_measured / f_nearest_note)`.
///
/// Reference: https://www.johndcook.com/blog/2016/02/10/musical-pitch-notation/
import Foundation

/// Provides equal-temperament pitch calculations: note detection, cents deviation,
/// frequency-of-note lookup, and range queries.
///
/// All calculations assume the 12-tone equal-temperament scale anchored at ``a4``.
/// Create one shared instance per application context; there is no meaningful state
/// other than the A4 reference frequency.
class Pitch {

    // MARK: - Properties

    /// The reference frequency of A4, in Hz.
    ///
    /// The standard concert pitch is 440 Hz.  Change this value to support alternative
    /// tuning systems (e.g. 432 Hz historical pitch or 415 Hz baroque pitch).
    var a4: Double

    /// The derived frequency of C0, computed from ``a4``.
    ///
    /// C0 is 4 octaves and 9 semitones (= 57 semitones) below A4:
    /// `f_C0 = f_A4 × 2^(−4.75)`.
    /// All note-frequency calculations use C0 as their base reference.
    var c0: Double {
        // -4.75 octaves = -4 octaves (4 × 12 semitones) minus 9 semitones = -57 semitones
        a4 * pow(2, -4.75)
    }

    /// Note name strings in ascending chromatic order, index 0 = C through index 11 = B.
    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    // MARK: - Initialization

    /// Creates a `Pitch` calculator with the given A4 reference frequency.
    ///
    /// - Parameter a4: Reference frequency of A4, in Hz.  Defaults to the standard 440 Hz.
    init(a4: Double = 440.0) {
        self.a4 = a4
    }

    // MARK: - Pitch Calculation

    /// Whether `frequency` has a pitch at all: a finite, positive number of hertz.
    ///
    /// A frequency that has none — 0 Hz, a negative value, NaN, infinity — gets "no pitch" from every
    /// function here: an empty note name, 0 cents, 0 Hz, a (0, 0) range, not in tune. Without this guard
    /// 0 Hz reaches `Int(round(12 * log2(0)))`, which traps.
    func hasPitch(_ frequency: Double) -> Bool {
        frequency.isFinite && frequency > 0
    }

    /// Returns the note index (0–11) and octave number closest to the given frequency.
    ///
    /// The note index maps as: 0 = C, 1 = C#, 2 = D, 3 = D#, 4 = E, 5 = F,
    /// 6 = F#, 7 = G, 8 = G#, 9 = A, 10 = A#, 11 = B.
    ///
    /// - Parameter frequency: The frequency to analyse, in Hz.
    /// - Returns: A tuple `(note: Int, octave: Int)` identifying the nearest equal-temperament pitch;
    ///   `(0, 0)` for a frequency with no pitch (``hasPitch(_:)``).
    func pitch(frequency: Double) -> (note: Int, octave: Int) {
        guard hasPitch(frequency) else { return (0, 0) }
        // Count half-steps above C0; rounding snaps to the nearest semitone.
        let halfSteps = Int(round(12 * log2(frequency / c0)))
        let octave = halfSteps / 12
        let note = halfSteps % 12
        return (note, octave)
    }

    /// Returns the frequencies of the semitones bracketing the given frequency.
    ///
    /// Which side the nearest note falls on depends on the sign of the cents offset: a
    /// frequency *above* its nearest note is bracketed by that note and the semitone above,
    /// and one *below* it by the semitone below and that note.
    ///
    /// No octave special-casing is needed. ``freq(note:octave:)`` is `c0 · 2^(note/12) · 2^octave`
    /// with no bounds check, so note 12 already *means* C of the next octave and note −1 already
    /// means B of the previous one — the exponent carries it.
    ///
    /// - Parameter frequency: The frequency to analyse, in Hz.
    /// - Returns: A tuple `(upper: Double, lower: Double)` one semitone apart, bracketing
    ///   `frequency`.
    func pitchRange(frequency: Double) -> (upper: Double, lower: Double) {
        guard hasPitch(frequency) else { return (upper: 0, lower: 0) }
        let (note, octave) = pitch(frequency: frequency)

        if cents(frequency: frequency) >= 0 {
            // Sharp of (or exactly on) the nearest note: that note is the LOWER bound.
            return (upper: freq(note: note + 1, octave: octave),
                    lower: freq(note: note, octave: octave))
        }
        // Flat of the nearest note: that note is the UPPER bound.
        return (upper: freq(note: note, octave: octave),
                lower: freq(note: note - 1, octave: octave))
    }

    /// Returns the name of the nearest equal-temperament note for the given frequency.
    ///
    /// - Parameter frequency: The frequency to analyse, in Hz.
    /// - Returns: A string such as `"A4"` or `"C#3"`; empty for a frequency with no pitch.
    func note(frequency: Double) -> String {
        guard hasPitch(frequency) else { return "" }
        let (note, octave) = pitch(frequency: frequency)
        return "\(noteNames[note])\(octave)"
    }

    /// Returns the frequency of the nearest equal-temperament note for the given frequency.
    ///
    /// Useful for computing how far (in Hz) the measured frequency deviates from the ideal
    /// note frequency.
    ///
    /// - Parameter frequency: The frequency to analyse, in Hz.
    /// - Returns: The exact frequency in Hz of the nearest note; 0 for a frequency with no pitch.
    func freq0(frequency: Double) -> Double {
        guard hasPitch(frequency) else { return 0 }
        let (note, octave) = pitch(frequency: frequency)
        return freq(note: note, octave: octave)
    }

    /// Returns the exact frequency for a note specified by index and octave.
    ///
    /// Formula: `f = f_C0 × 2^(note/12) × 2^octave`
    ///
    /// - Parameters:
    ///   - note: Chromatic note index (0 = C, 1 = C#, … 11 = B).
    ///   - octave: Octave number (4 is the standard middle-C octave for octave 4 at C4 ≈ 261 Hz).
    /// - Returns: Frequency in Hz.
    func freq(note: Int, octave: Int) -> Double {
        return pow(2, Double(note) / 12.0) * c0 * pow(2, Double(octave))
    }

    /// Returns the signed cents offset from the nearest equal-temperament pitch.
    ///
    /// Formula: `cents = 1200 × log₂(f_measured / f_nearest)`
    ///
    /// - Parameter frequency: The measured frequency, in Hz.
    /// - Returns: Cents offset in the range −50 to +50 (100 cents = 1 semitone).
    ///   Negative means flat; positive means sharp. 0 for a frequency with no pitch.
    func cents(frequency: Double) -> Double {
        guard hasPitch(frequency) else { return 0 }
        let (note, octave) = pitch(frequency: frequency)
        let f0 = freq(note: note, octave: octave)
        // 1200 × log₂ gives the interval in cents between f0 (ideal) and frequency (measured).
        let cents = 1200 * log2(frequency / f0)
        return cents
    }
}

// MARK: - Convenience Extensions

extension Pitch {

    /// Returns a formatted string combining the nearest note name and its cents offset.
    ///
    /// Example output: `"A4 (+23 cents)"` or `"C#3 (-5 cents)"`.
    ///
    /// - Parameter frequency: The frequency to format, in Hz.
    /// - Returns: A human-readable pitch-and-deviation string; empty for a frequency with no pitch.
    func formattedNote(frequency: Double) -> String {
        guard hasPitch(frequency) else { return "" }
        let noteName = note(frequency: frequency)
        let centsOffset = cents(frequency: frequency)
        let sign = centsOffset >= 0 ? "+" : ""
        return "\(noteName) (\(sign)\(String(format: "%.0f", centsOffset)) cents)"
    }

    /// Returns whether the given frequency is within a specified cents tolerance of a pure
    /// equal-temperament pitch.
    ///
    /// - Parameters:
    ///   - frequency: The frequency to check, in Hz.
    ///   - threshold: Maximum absolute cents deviation considered "in tune".  Defaults to 10 cents.
    /// - Returns: `true` when `|cents| ≤ threshold`; `false` for a frequency with no pitch.
    func isInTune(frequency: Double, threshold: Double = 10.0) -> Bool {
        guard hasPitch(frequency) else { return false }
        return abs(cents(frequency: frequency)) <= threshold
    }
}


