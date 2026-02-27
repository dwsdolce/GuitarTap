//
//  ResonantPeak.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import Foundation

/// Represents a detected resonant peak in the frequency spectrum
struct ResonantPeak: Identifiable, Codable {
    let id: UUID
    let frequency: Float        // Hz
    let magnitude: Float        // dB
    let quality: Float          // Q factor (sharpness)
    let bandwidth: Float        // Hz at -3dB points
    let timestamp: Date
    
    // Pitch information
    let pitchNote: String?      // e.g., "A4", "C#3"
    let pitchCents: Double?     // Cents offset from nearest pitch
    let pitchFrequency: Double? // Frequency of nearest pitch
    
    init(frequency: Float, magnitude: Float, quality: Float = 0, bandwidth: Float = 0, pitchNote: String? = nil, pitchCents: Double? = nil, pitchFrequency: Double? = nil) {
        self.id = UUID()
        self.frequency = frequency
        self.magnitude = magnitude
        self.quality = quality
        self.bandwidth = bandwidth
        self.timestamp = Date()
        self.pitchNote = pitchNote
        self.pitchCents = pitchCents
        self.pitchFrequency = pitchFrequency
    }
    
    /// Computed property for formatted pitch information
    var formattedPitch: String {
        guard let note = pitchNote, let cents = pitchCents else {
            return "N/A"
        }
        let sign = cents >= 0 ? "+" : ""
        return "\(note) (\(sign)\(String(format: "%.0f", cents)) ¢)"
    }
}
