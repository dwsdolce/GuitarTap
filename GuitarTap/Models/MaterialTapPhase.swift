//
//  MaterialTapPhase.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import Foundation

/// Phase of material measurement tap sequence
/// Material measurements require two or three separate tap orientations
/// to isolate longitudinal, cross-grain, and optionally FLC (diagonal/shear) modes
enum MaterialTapPhase: String {
    case notStarted = "Not Started"
    case capturingLongitudinal = "Capturing Longitudinal"
    case waitingForCrossTap = "Waiting for Cross-grain Tap"
    case capturingCross = "Capturing Cross-grain"
    case waitingForFlcTap = "Waiting for FLC Tap"
    case capturingFlc = "Capturing FLC"
    case complete = "Complete"
    
    /// User-friendly instruction for current phase
    var instruction: String {
        switch self {
        case .notStarted:
            return "Press New Tap to begin material measurement"
        case .capturingLongitudinal:
            return "Processing longitudinal tap..."
        case .waitingForCrossTap:
            return "Now rotate plate 90° and tap again for cross-grain"
        case .capturingCross:
            return "Processing cross-grain tap..."
        case .waitingForFlcTap:
            return "Support plate at all 4 nodal points (~22% from each corner), tap the center"
        case .capturingFlc:
            return "Processing FLC tap..."
        case .complete:
            return "Material measurement complete"
        }
    }
    
    /// Short status for compact display
    var shortStatus: String {
        switch self {
        case .notStarted: return "Ready"
        case .capturingLongitudinal: return "L tap..."
        case .waitingForCrossTap: return "Tap for C"
        case .capturingCross: return "C tap..."
        case .waitingForFlcTap: return "Tap for FLC"
        case .capturingFlc: return "FLC tap..."
        case .complete: return "Done"
        }
    }
}
