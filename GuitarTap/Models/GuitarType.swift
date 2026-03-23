//
//  GuitarType.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

/// The kind of guitar body, which determines mode frequency classification ranges.
///
/// Each guitar type has a distinct set of ``ModeRanges`` reflecting its typical
/// construction (body depth, bracing style, string tension), and separate
/// ``DecayThresholds`` calibrated to expected ring-out times.
///
/// - SeeAlso: ``GuitarMode`` for the resonance mode classification that uses these ranges.
/// - SeeAlso: ``MeasurementType`` for the broader type that includes plate/brace measurements.
import Foundation

enum GuitarType: String, Codable, CaseIterable, Identifiable {
    case classical = "Classical"
    case flamenco = "Flamenco"
    case acoustic = "Acoustic"

    var id: String { rawValue }

    /// Human-readable description of the guitar type shown in the settings UI.
    var description: String {
        switch self {
        case .classical:
            return "Nylon string, fan-braced, deep body"
        case .flamenco:
            return "Nylon string, light bracing, shallow body"
        case .acoustic:
            return "Steel string, X-braced (Dreadnought, OM, etc.)"
        }
    }

    // MARK: - Mode Ranges

    /// Frequency classification bands for each guitar body mode, in Hz.
    ///
    /// Used by ``GuitarMode/classify(frequency:guitarType:)`` to assign a mode label to each
    /// detected peak.  Bands are non-overlapping and cover the full audible spectrum via
    /// `upperModes`.
    struct ModeRanges {
        /// Helmholtz air resonance band, in Hz.
        let air: ClosedRange<Float>
        /// Main top plate bending mode band, in Hz.
        let top: ClosedRange<Float>
        /// Back plate bending mode band, in Hz.
        let back: ClosedRange<Float>
        /// Dipole (top-plate out-of-phase) mode band, in Hz.
        let dipole: ClosedRange<Float>
        /// Ring mode band, in Hz.
        let ringMode: ClosedRange<Float>
        /// Upper harmonic modes band (extends to 20 kHz), in Hz.
        let upperModes: ClosedRange<Float>
    }

    /// The frequency classification bands for this guitar type.
    var modeRanges: ModeRanges {
        switch self {
        case .classical:
            return ModeRanges(
                air: 80...110,        // Lower air resonance due to deeper body
                top: 170...230,       // Main top resonance
                back: 190...280,      // Back resonance (extended to 280 Hz to capture higher back modes)
                dipole: 330...430,    // Dipole mode
                ringMode: 580...820,  // Ring mode
                upperModes: 820...20000
            )
        case .flamenco:
            return ModeRanges(
                air: 85...115,        // Slightly higher due to shallower body
                top: 190...250,       // Higher due to thinner, lighter top
                back: 180...240,      // Cypress back, lighter construction
                dipole: 350...450,    // Dipole mode
                ringMode: 600...850,  // Ring mode
                upperModes: 850...20000
            )
        case .acoustic:
            return ModeRanges(
                air: 90...120,        // Higher due to smaller/tighter body
                top: 150...210,       // Lower due to stiffer X-bracing
                back: 210...290,      // Back resonance
                dipole: 360...460,    // Dipole mode
                ringMode: 620...880,  // Ring mode
                upperModes: 880...20000
            )
        }
    }

    // MARK: - Decay Thresholds

    /// Ring-out time quality thresholds, in seconds.
    ///
    /// Used by ``Swift/Float/decayQuality(for:)`` to convert a numeric ring-out time into a
    /// qualitative label.  Thresholds differ between guitar types: flamenco guitars are expected
    /// to decay quickly (percussive playing), while classical guitars are expected to sustain longer.
    struct DecayThresholds {
        /// Ring-out times below this value are rated "Very Short", in seconds.
        let veryShort: Float
        /// Ring-out times below this value are rated "Short", in seconds.
        let short: Float
        /// Ring-out times below this value are rated "Moderate", in seconds.
        let moderate: Float
        /// Ring-out times below this value are rated "Good"; at or above is "Excellent", in seconds.
        let good: Float
    }

    /// The ring-out quality thresholds for this guitar type.
    var decayThresholds: DecayThresholds {
        switch self {
        case .classical:
            // Classical guitars have longer sustain due to deeper body and heavier bracing
            return DecayThresholds(
                veryShort: 0.15,
                short: 0.35,
                moderate: 0.60,
                good: 1.0
            )
        case .flamenco:
            // Flamenco guitars are designed for short, percussive decay
            // Quick decay is a feature for clear rasgueados and golpe
            return DecayThresholds(
                veryShort: 0.08,
                short: 0.20,
                moderate: 0.35,
                good: 0.55
            )
        case .acoustic:
            // Steel-string guitars have punchier, shorter decay
            return DecayThresholds(
                veryShort: 0.10,
                short: 0.25,
                moderate: 0.45,
                good: 0.75
            )
        }
    }
}
