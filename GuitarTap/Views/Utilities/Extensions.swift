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
    
    /// Evaluates the quality of a decay time using the current guitar type setting
    /// These thresholds are calibrated for tap tone analysis where:
    /// - Body-only taps (damped strings) typically decay in 0.05-0.3s
    /// - Taps with open strings ringing decay in 0.3-1.5s+
    /// Classical guitars typically have longer sustain than acoustic  guitars
    var decayQuality: String {
        return decayQuality(for: SpectrumDisplaySettings.guitarType)
    }
    
    /// Evaluates the quality of a decay time for a specific guitar type
    func decayQuality(for guitarType: GuitarType) -> String {
        let thresholds = guitarType.decayThresholds
        switch self {
        case 0..<thresholds.veryShort:
            return "Very Short"
        case thresholds.veryShort..<thresholds.short:
            return "Short"
        case thresholds.short..<thresholds.moderate:
            return "Moderate"
        case thresholds.moderate..<thresholds.good:
            return "Good"
        case thresholds.good...:
            return "Excellent"
        default:
            return "Unknown"
        }
    }
    
    /// Color indicator for decay quality (uses current guitar type setting)
    var decayQualityColor: Color {
        return decayQualityColor(for: SpectrumDisplaySettings.guitarType)
    }
    
    /// Color indicator for decay quality for a specific guitar type
    func decayQualityColor(for guitarType: GuitarType) -> Color {
        let thresholds = guitarType.decayThresholds
        switch self {
        case 0..<thresholds.veryShort:
            return .gray
        case thresholds.veryShort..<thresholds.short:
            return .orange
        case thresholds.short..<thresholds.moderate:
            return .yellow
        case thresholds.moderate..<thresholds.good:
            return .green
        case thresholds.good...:
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
    /// Display color for each guitar mode (uses normalized mode for legacy compatibility)
    var color: Color {
        switch self.normalized {
        case .air:
            return .cyan
        case .top:
            return .green
        case .back:
            return .orange
        case .dipole:
            return .red
        case .ringMode:
            return .purple
        case .upperModes:
            return .gray
        case .unknown:
            return .secondary
        default:
            return .secondary
        }
    }
    
    /// Abbreviated mode name for compact display
    var abbreviation: String {
        switch self.normalized {
        case .air:
            return "Air"
        case .top:
            return "Top"
        case .back:
            return "Back"
        case .dipole:
            return "DP"
        case .ringMode:
            return "Ring"
        case .upperModes:
            return "Upper"
        case .unknown:
            return "?"
        default:
            return "?"
        }
    }
    
    /// Detailed description of the mode
    var description: String {
        switch self.normalized {
        case .air:
            return "Air resonance (Helmholtz) - the 'breathing' of the guitar body"
        case .top:
            return "Main top plate resonance"
        case .back:
            return "Back plate resonance"
        case .dipole:
            return "Top plate moving out of phase (dipole)"
        case .ringMode:
            return "Higher frequency body resonances"
        case .upperModes:
            return "Upper harmonic modes"
        case .unknown:
            return "Unclassified frequency"
        default:
            return "Unclassified frequency"
        }
    }
    
    var icon: String {
        switch self.normalized {
        case .air: return "wind"
        case .top: return "arrow.up.and.down"
        case .back: return "square.fill"
        case .dipole: return "circle.lefthalf.filled"
        case .ringMode: return "circle.dashed"
        case .upperModes: return "waveform"
        case .unknown: return "questionmark.circle"
        default: return "questionmark.circle"
        }
    }
}

