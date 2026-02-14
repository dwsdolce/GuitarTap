//
//  SpectrumDisplaySettings.swift
//  GuitarTap
//
//  Created on 2/12/26.
//

import Foundation

// MARK: - Guitar Type

/// The type of guitar being analyzed, affecting frequency range classifications
enum GuitarType: String, Codable, CaseIterable, Identifiable {
    case classical = "Classical"
    case flamenco = "Flamenco"
    case steelString = "Steel-String"
    
    var id: String { rawValue }
    
    /// Description of the guitar type
    var description: String {
        switch self {
        case .classical:
            return "Nylon string, fan-braced, deep body"
        case .flamenco:
            return "Nylon string, light bracing, shallow body"
        case .steelString:
            return "Steel string, X-braced (Dreadnought, OM, etc.)"
        }
    }
    
    /// Frequency ranges for mode classification
    struct ModeRanges {
        let air: ClosedRange<Float>          // Helmholtz/Air resonance
        let top: ClosedRange<Float>          // Main top plate resonance
        let back: ClosedRange<Float>         // Back plate resonance
        let dipole: ClosedRange<Float>       // Dipole mode
        let ringMode: ClosedRange<Float>     // Ring mode
        let upperModes: ClosedRange<Float>   // Upper modes
    }
    
    /// Get the frequency ranges for this guitar type
    var modeRanges: ModeRanges {
        switch self {
        case .classical:
            return ModeRanges(
                air: 80...110,        // Lower air resonance due to deeper body
                top: 170...230,       // Main top resonance
                back: 190...260,      // Back resonance
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
        case .steelString:
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
    
    /// Ideal frequency ranges for display (narrower "target" ranges)
    var idealRanges: ModeRanges {
        switch self {
        case .classical:
            return ModeRanges(
                air: 90...100,
                top: 185...215,
                back: 210...250,
                dipole: 360...410,
                ringMode: 650...750,
                upperModes: 850...2000
            )
        case .flamenco:
            return ModeRanges(
                air: 95...105,
                top: 205...235,
                back: 195...225,
                dipole: 380...420,
                ringMode: 680...780,
                upperModes: 880...2000
            )
        case .steelString:
            return ModeRanges(
                air: 95...110,
                top: 165...195,
                back: 230...270,
                dipole: 390...430,
                ringMode: 680...780,
                upperModes: 900...2000
            )
        }
    }
    
    /// Decay time quality thresholds for this guitar type
    struct DecayThresholds {
        let veryShort: Float    // Below this is "Very Short"
        let short: Float        // Below this is "Short"
        let moderate: Float     // Below this is "Moderate"
        let good: Float         // Below this is "Good", above is "Excellent"
    }
    
    /// Get decay quality thresholds for this guitar type
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
        case .steelString:
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

/// Centralized settings for spectrum display ranges across the app
struct SpectrumDisplaySettings {
    
    // MARK: - Guitar Type Setting
    
    /// Key for storing guitar type in UserDefaults
    private static let guitarTypeKey = "guitarType"
    
    /// The currently selected guitar type (persisted in UserDefaults)
    static var guitarType: GuitarType {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: guitarTypeKey),
               let type = GuitarType(rawValue: rawValue) {
                return type
            }
            return .steelString  // Default to steel-string
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: guitarTypeKey)
        }
    }
    
    // MARK: - Unknown Mode Display Setting
    
    /// Key for storing unknown mode display preference in UserDefaults
    private static let showUnknownModesKey = "showUnknownModes"
    
    /// Whether to display/report peaks classified as "Unknown" mode (persisted in UserDefaults)
    static var showUnknownModes: Bool {
        get {
            // Default to false (hide unknown modes)
            if UserDefaults.standard.object(forKey: showUnknownModesKey) == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: showUnknownModesKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showUnknownModesKey)
        }
    }
    // MARK: - Display Ranges
    
    /// Standard minimum frequency for guitar tap tone spectrum display (Hz)
    static let minFrequency: Float = 75
    
    /// Standard maximum frequency for guitar tap tone spectrum display (Hz)
    static let maxFrequency: Float = 350
    
    /// Standard minimum magnitude for spectrum display (dB)
    static let minMagnitude: Float = -100
    
    /// Standard maximum magnitude for spectrum display (dB)
    static let maxMagnitude: Float = 0
    
    // MARK: - Analysis Settings
    
    /// Minimum frequency for peak detection and analysis (Hz)
    static let analysisMinFrequency: Float = 50
    
    /// Maximum frequency for peak detection and analysis (Hz)
    static let analysisMaxFrequency: Float = 2000
    
    /// Default minimum magnitude threshold for peak detection (dB)
    /// Any magnitude below this is ignored. Even if the threshold setting is below it.
    static let defaultPeakThreshold: Float = -60
    
    // MARK: - Validation
    
    /// Validates and clamps frequency range
    /// - Parameters:
    ///   - minFreq: Minimum frequency to validate
    ///   - maxFreq: Maximum frequency to validate
    /// - Returns: Tuple of validated (min, max) frequencies
    static func validateFrequencyRange(minFreq: Float, maxFreq: Float) -> (min: Float, max: Float) {
        let clampedMin = max(20, min(minFreq, 20000))
        let clampedMax = max(20, min(maxFreq, 20000))
        
        // Ensure minimum separation of 10 Hz
        if clampedMin < clampedMax && (clampedMax - clampedMin) >= 10 {
            return (clampedMin, clampedMax)
        }
        
        // Return defaults if validation fails
        return (minFrequency, maxFrequency)
    }
    
    /// Validates and clamps magnitude range
    /// - Parameters:
    ///   - minDB: Minimum magnitude to validate
    ///   - maxDB: Maximum magnitude to validate
    /// - Returns: Tuple of validated (min, max) magnitudes
    static func validateMagnitudeRange(minDB: Float, maxDB: Float) -> (min: Float, max: Float) {
        let clampedMin = max(-120, min(minDB, 20))
        let clampedMax = max(-120, min(maxDB, 20))
        
        // Ensure minimum separation of 10 dB
        if clampedMin < clampedMax && (clampedMax - clampedMin) >= 10 {
            return (clampedMin, clampedMax)
        }
        
        // Return defaults if validation fails
        return (minMagnitude, maxMagnitude)
    }
}
