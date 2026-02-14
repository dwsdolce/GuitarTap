//
//  Extensions.swift
//  GuitarTap
//
//  Created on 2/9/26.
//

import SwiftUI

// MARK: - Float Extensions

extension Float {
    /// Formats a frequency value as a human-readable string
    /// - Returns: String with "kHz" suffix for values >= 1000, otherwise "Hz"
    func formattedAsFrequency() -> String {
        if self >= 1000 {
            return String(format: "%.1f kHz", self / 1000)
        } else {
            return String(format: "%.0f Hz", self)
        }
    }
    
    /// Evaluates the quality of a decay time (15 dB threshold)
    /// These thresholds are calibrated for tap tone analysis where:
    /// - Body-only taps (damped strings) typically decay in 0.05-0.3s
    /// - Taps with open strings ringing decay in 0.3-1.5s+
    var decayQuality: String {
        switch self {
        case 0..<0.1:
            return "Very Short"
        case 0.1..<0.3:
            return "Short"
        case 0.3..<0.6:
            return "Moderate"
        case 0.6..<1.0:
            return "Good"
        case 1.0...:
            return "Excellent"
        default:
            return "Unknown"
        }
    }
    
    /// Color indicator for decay quality
    var decayQualityColor: Color {
        switch self {
        case 0..<0.1:
            return .gray
        case 0.1..<0.3:
            return .orange
        case 0.3..<0.6:
            return .yellow
        case 0.6..<1.0:
            return .green
        case 1.0...:
            return .blue
        default:
            return .gray
        }
    }
    
    /// Evaluates the quality of a tap tone ratio (ideal: 1.9 - 2.1)
    var tapToneRatioQuality: String {
        switch self {
        case 0..<1.7:
            return "Low"
        case 1.7..<1.9:
            return "Below Target"
        case 1.9...2.1:
            return "Ideal"
        case 2.1..<2.3:
            return "Above Target"
        case 2.3...:
            return "High"
        default:
            return "Unknown"
        }
    }
    
    /// Color indicator for tap tone ratio quality
    var tapToneRatioQualityColor: Color {
        switch self {
        case 0..<1.7:
            return .red
        case 1.7..<1.9:
            return .orange
        case 1.9...2.1:
            return .green
        case 2.1..<2.3:
            return .orange
        case 2.3...:
            return .red
        default:
            return .gray
        }
    }
}

// MARK: - GuitarMode Extensions

extension GuitarMode {
    /// Display color for each guitar mode
    var color: Color {
        switch self {
        case .helmholtz:
            return .cyan
        case .crossGrain:
            return .blue
        case .longGrain:
            return .green
        case .monopole:
            return .orange
        case .dipole:
            return .red
        case .ringMode:
            return .purple
        case .upperModes:
            return .gray
        case .unknown:
            return .secondary
        }
    }
    
    /// Abbreviated mode name for compact display
    var abbreviation: String {
        switch self {
        case .helmholtz:
            return "HH"
        case .crossGrain:
            return "XG"
        case .longGrain:
            return "LG"
        case .monopole:
            return "MP"
        case .dipole:
            return "DP"
        case .ringMode:
            return "Ring"
        case .upperModes:
            return "Upper"
        case .unknown:
            return "?"
        }
    }
    
    /// Detailed description of the mode
    var description: String {
        switch self {
        case .helmholtz:
            return "Air resonance - the 'breathing' of the guitar body"
        case .crossGrain:
            return "Top plate vibration across the grain"
        case .longGrain:
            return "Top plate vibration along the grain"
        case .monopole:
            return "Top plate moving in phase"
        case .dipole:
            return "Top plate moving out of phase"
        case .ringMode:
            return "Higher frequency body resonances"
        case .upperModes:
            return "Upper harmonic modes"
        case .unknown:
            return "Unclassified frequency"
        }
    }
    
    var icon: String {
        switch self {
        case .helmholtz: return "wind"
        case .crossGrain: return "arrow.left.and.right"
        case .longGrain: return "arrow.up.and.down"
        case .monopole: return "circle.fill"
        case .dipole: return "circle.lefthalf.filled"
        case .ringMode: return "circle.dashed"
        case .upperModes: return "waveform"
        case .unknown: return "questionmark.circle"
        }
    }
}

