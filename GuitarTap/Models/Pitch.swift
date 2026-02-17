//
//  Pitch.swift
//  GuitarTap
//
//  Converted from pitch.py
//

import Foundation

/// For a specified frequency find the pitch, octave, and cents offset.
/// This is based on the specified setting for A4.
/// There are also some utilities for formatting the name and the
/// closest frequency of a note.
/// Some of these calculations come from:
///     https://www.johndcook.com/blog/2016/02/10/musical-pitch-notation/
class Pitch {
    
    // MARK: - Properties
    
    /// The frequency of A4 in Hz (default: 440 Hz)
    var a4: Double
    
    /// The frequency of C0 in Hz (calculated from A4)
    var c0: Double {
        a4 * pow(2, -4.75)  // -4 octaves below A4 and -9/12 below A
    }
    
    /// Note names in chromatic scale
    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    
    // MARK: - Initialization
    
    /// Initialize with a specific A4 frequency
    /// - Parameter a4: The frequency of A4 in Hz (typically 440 Hz)
    init(a4: Double = 440.0) {
        self.a4 = a4
    }
    
    // MARK: - Pitch Calculation Methods
    
    /// Find the pitch (note and octave) closest to the given frequency
    /// - Parameter frequency: The frequency in Hz to analyze
    /// - Returns: A tuple containing the note index (0-11) and octave number
    func pitch(frequency: Double) -> (note: Int, octave: Int) {
        // This gives the 1/2 steps above c_0
        let halfSteps = Int(round(12 * log2(frequency / c0)))
        let octave = halfSteps / 12
        let note = halfSteps % 12
        return (note, octave)
    }
    
    /// Return the frequencies of the upper and lower notes for this frequency
    /// - Parameter frequency: The frequency in Hz to analyze
    /// - Returns: A tuple containing the upper and lower note frequencies
    func pitchRange(frequency: Double) -> (upper: Double, lower: Double) {
        let (note, octave) = pitch(frequency: frequency)
        let cents = self.cents(frequency: frequency)
        
        let upper: Double
        let lower: Double
        
        if cents >= 0 {
            if note == 11 {
                upper = freq(note: 0, octave: octave + 1)
            } else {
                upper = freq(note: note + 1, octave: octave)
            }
            lower = freq(note: note, octave: octave)
        } else {
            upper = freq(note: note, octave: octave)
            if note == 0 {
                lower = freq(note: 11, octave: octave - 1)
            } else {
                lower = freq(note: note - 1, octave: octave)
            }
        }
        
        return (upper, lower)
    }
    
    /// Return a string representation of the pitch closest to this frequency
    /// - Parameter frequency: The frequency in Hz to analyze
    /// - Returns: A string like "A4" or "C#3"
    func note(frequency: Double) -> String {
        let (note, octave) = pitch(frequency: frequency)
        return "\(noteNames[note])\(octave)"
    }
    
    /// Return the frequency of the pitch closest to this frequency
    /// - Parameter frequency: The frequency in Hz to analyze
    /// - Returns: The frequency of the nearest note in Hz
    func freq0(frequency: Double) -> Double {
        let (note, octave) = pitch(frequency: frequency)
        return freq(note: note, octave: octave)
    }
    
    /// Return the frequency of the note specified by pitch and octave
    /// - Parameters:
    ///   - note: The note index (0=C, 1=C#, 2=D, etc.)
    ///   - octave: The octave number
    /// - Returns: The frequency in Hz
    func freq(note: Int, octave: Int) -> Double {
        return pow(2, Double(note) / 12.0) * c0 * pow(2, Double(octave))
    }
    
    /// Return the cents offset from the pitch closest to this frequency
    /// - Parameter frequency: The frequency in Hz to analyze
    /// - Returns: The cents offset (-50 to +50, where 100 cents = 1 semitone)
    func cents(frequency: Double) -> Double {
        let (note, octave) = pitch(frequency: frequency)
        let f0 = freq(note: note, octave: octave)
        // f0 is the desired frequency and frequency is the actual
        let cents = 1200 * log2(frequency / f0)
        return cents
    }
}

// MARK: - Convenience Extensions

extension Pitch {
    /// Format a frequency with its note name and cents offset
    /// - Parameter frequency: The frequency in Hz to format
    /// - Returns: A formatted string like "A4 (+23 cents)"
    func formattedNote(frequency: Double) -> String {
        let noteName = note(frequency: frequency)
        let centsOffset = cents(frequency: frequency)
        let sign = centsOffset >= 0 ? "+" : ""
        return "\(noteName) (\(sign)\(String(format: "%.0f", centsOffset)) cents)"
    }
    
    /// Check if a frequency is in tune (within a threshold of cents)
    /// - Parameters:
    ///   - frequency: The frequency in Hz to check
    ///   - threshold: The maximum cents offset to consider in tune (default: 10)
    /// - Returns: True if the frequency is within the threshold
    func isInTune(frequency: Double, threshold: Double = 10.0) -> Bool {
        return abs(cents(frequency: frequency)) <= threshold
    }
}

// MARK: - Preview/Testing

#if DEBUG
extension Pitch {
    /// Run example calculations (for testing/debugging)
    static func runExample() {
        let pitch = Pitch(a4: 440)
        
        print("Example 1:")
        let f1: Double = 173
        print("f_1 = \(f1)")
        print("Note = \(pitch.note(frequency: f1))")
        print("f_0 = \(pitch.freq0(frequency: f1))")
        print("cents = \(pitch.cents(frequency: f1))")
        print("==========================")
        
        print("Example 2:")
        let f2: Double = 175.8
        print("f_1 = \(f2)")
        print("Note = \(pitch.note(frequency: f2))")
        print("f_0 = \(pitch.freq0(frequency: f2))")
        print("cents = \(pitch.cents(frequency: f2))")
        print("formatted = \(pitch.formattedNote(frequency: f2))")
        print("in tune? \(pitch.isInTune(frequency: f2))")
    }
}
#endif
