//
//  GuitarMode.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import Foundation

/// Guitar resonance mode classification based on frequency ranges
/// Uses luthier-friendly terminology for completed instruments
enum GuitarMode: String, Codable {
    case air = "Air (Helmholtz)"      // Combined Helmholtz + coupled air/top mode
    case top = "Top"                   // Main top plate resonance (formerly long-grain)
    case back = "Back"                 // Back plate resonance (formerly monopole)
    case dipole = "Dipole"             // T(1,2) dipole mode
    case ringMode = "Ring Mode"        // Higher structural mode
    case upperModes = "Upper Modes"    // Higher frequency modes
    case unknown = "Unknown"
    
    // Legacy case mappings for backward compatibility with saved data
    case helmholtz = "Helmholtz (Air)"
    case crossGrain = "Cross-Grain"
    case longGrain = "Long-Grain"
    case monopole = "Monopole"
    
    /// Classify a frequency into a guitar mode using the current guitar type setting
    static func classify(frequency: Float) -> GuitarMode {
        return classify(frequency: frequency, guitarType: TapDisplaySettings.guitarType)
    }
    
    /// Classify a frequency into a guitar mode for a specific guitar type
    static func classify(frequency: Float, guitarType: GuitarType) -> GuitarMode {
        let ranges = guitarType.modeRanges
        
        switch frequency {
        case ranges.air:
            return .air
        case ranges.top:
            return .top
        case ranges.back:
            return .back
        case ranges.dipole:
            return .dipole
        case ranges.ringMode:
            return .ringMode
        case ranges.upperModes:
            return .upperModes
        default:
            return .unknown
        }
    }
    
    /// Ideal frequency range for this mode (uses current guitar type setting)
    var idealRange: ClosedRange<Float> {
        return idealRange(for: TapDisplaySettings.guitarType)
    }
    
    /// Ideal frequency range for this mode for a specific guitar type
    func idealRange(for guitarType: GuitarType) -> ClosedRange<Float> {
        let ranges = guitarType.idealRanges
        switch self.normalized {
        case .air: return ranges.air
        case .top: return ranges.top
        case .back: return ranges.back
        case .dipole: return ranges.dipole
        case .ringMode: return ranges.ringMode
        case .upperModes: return ranges.upperModes
        case .unknown: return 0...20000
        default: return 0...20000
        }
    }
    
    /// Display name for UI (handles legacy modes)
    var displayName: String {
        switch self {
        case .air, .helmholtz, .crossGrain: return "Air (Helmholtz)"
        case .top, .longGrain: return "Top"
        case .back, .monopole: return "Back"
        case .dipole: return "Dipole"
        case .ringMode: return "Ring Mode"
        case .upperModes: return "Upper Modes"
        case .unknown: return "Unknown"
        }
    }
    
    /// Normalized mode for comparisons (maps legacy modes to new ones)
    var normalized: GuitarMode {
        switch self {
        case .helmholtz, .crossGrain: return .air
        case .longGrain: return .top
        case .monopole: return .back
        default: return self
        }
    }
}
