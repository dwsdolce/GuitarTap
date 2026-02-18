//
//  SpectrumDisplaySettings.swift
//  GuitarTap
//
//  Created on 2/12/26.
//

import Foundation

// MARK: - Measurement Type

/// The type of measurement being performed
enum MeasurementType: String, Codable, CaseIterable, Identifiable {
    case classical = "Classical Guitar"
    case flamenco = "Flamenco Guitar"
    case acoustic = "Acoustic Guitar"
    case material = "Material (Wood Plate)"
    
    var id: String { rawValue }
    
    /// Short name for display
    var shortName: String {
        switch self {
        case .classical: return "Classical"
        case .flamenco: return "Flamenco"
        case .acoustic: return "Acoustic"
        case .material: return "Material"
        }
    }
    
    /// Description of the measurement type
    var description: String {
        switch self {
        case .classical:
            return "Nylon string, fan-braced, deep body"
        case .flamenco:
            return "Nylon string, light bracing, shallow body"
        case .acoustic:
            return "Steel string, X-braced (Dreadnought, OM, etc.)"
        case .material:
            return "Rectangular wood plate for calculating stiffness and sound radiation"
        }
    }
    
    /// Whether this is a guitar measurement (vs material)
    var isGuitar: Bool {
        switch self {
        case .classical, .flamenco, .acoustic:
            return true
        case .material:
            return false
        }
    }
    
    /// Convert to GuitarType if applicable
    var guitarType: GuitarType? {
        switch self {
        case .classical: return .classical
        case .flamenco: return .flamenco
        case .acoustic: return .acoustic
        case .material: return nil
        }
    }
    
    /// Create from GuitarType
    static func from(_ guitarType: GuitarType) -> MeasurementType {
        switch guitarType {
        case .classical: return .classical
        case .flamenco: return .flamenco
        case .acoustic: return .acoustic
        }
    }
}

// MARK: - Guitar Type

/// The type of guitar being analyzed, affecting frequency range classifications
enum GuitarType: String, Codable, CaseIterable, Identifiable {
    case classical = "Classical"
    case flamenco = "Flamenco"
    case acoustic = "Acoustic"
    
    var id: String { rawValue }
    
    /// Description of the guitar type
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
        case .acoustic:
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

/// Centralized settings for spectrum display ranges across the app
struct SpectrumDisplaySettings {
    
    // MARK: - UserDefaults Keys
    
    private static let measurementTypeKey = "measurementType"
    private static let guitarTypeKey = "guitarType"
    private static let showUnknownModesKey = "showUnknownModes"
    
    // Material measurement keys
    private static let materialLengthKey = "materialLength"
    private static let materialWidthKey = "materialWidth"
    private static let materialThicknessKey = "materialThickness"
    private static let materialMassKey = "materialMass"
    private static let displayMinFreqKey = "displayMinFreq"
    private static let displayMaxFreqKey = "displayMaxFreq"
    private static let displayMinDBKey = "displayMinDB"
    private static let displayMaxDBKey = "displayMaxDB"
    private static let analysisMinFreqKey = "analysisMinFreq"
    private static let analysisMaxFreqKey = "analysisMaxFreq"
    private static let peakThresholdKey = "peakThreshold"
    private static let maxPeaksKey = "maxPeaks"
    private static let hopSizeOverlapKey = "hopSizeOverlap"
    private static let tapDetectionThresholdKey = "tapDetectionThreshold"
    private static let hysteresisMarginKey = "hysteresisMargin"
    
    // MARK: - Measurement Type Setting
    
    /// The currently selected measurement type (persisted in UserDefaults)
    static var measurementType: MeasurementType {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: measurementTypeKey),
               let type = MeasurementType(rawValue: rawValue) {
                return type
            }
            return .acoustic  // Default to steel-string guitar
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: measurementTypeKey)
        }
    }
    
    // MARK: - Guitar Type Setting (for backward compatibility)
    
    /// The currently selected guitar type (persisted in UserDefaults)
    /// Note: Use measurementType for new code
    static var guitarType: GuitarType {
        get {
            // First check if measurementType is set and is a guitar type
            if let type = measurementType.guitarType {
                return type
            }
            // Fall back to stored guitarType for backward compatibility
            if let rawValue = UserDefaults.standard.string(forKey: guitarTypeKey),
               let type = GuitarType(rawValue: rawValue) {
                return type
            }
            return .acoustic  // Default to steel-string
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: guitarTypeKey)
            // Also update measurementType
            measurementType = MeasurementType.from(newValue)
        }
    }
    
    // MARK: - Material Dimensions (for Material measurement type)
    
    /// Material plate length in mm (along grain direction)
    static var materialLength: Float {
        get {
            let value = UserDefaults.standard.float(forKey: materialLengthKey)
            return value > 0 ? value : 500.0  // Default 500mm
        }
        set {
            UserDefaults.standard.set(newValue, forKey: materialLengthKey)
        }
    }
    
    /// Material plate width in mm (cross grain direction)
    static var materialWidth: Float {
        get {
            let value = UserDefaults.standard.float(forKey: materialWidthKey)
            return value > 0 ? value : 200.0  // Default 200mm
        }
        set {
            UserDefaults.standard.set(newValue, forKey: materialWidthKey)
        }
    }
    
    /// Material plate thickness in mm
    static var materialThickness: Float {
        get {
            let value = UserDefaults.standard.float(forKey: materialThicknessKey)
            return value > 0 ? value : 3.0  // Default 3mm
        }
        set {
            UserDefaults.standard.set(newValue, forKey: materialThicknessKey)
        }
    }
    
    /// Material plate mass in grams
    static var materialMass: Float {
        get {
            let value = UserDefaults.standard.float(forKey: materialMassKey)
            return value > 0 ? value : 100.0  // Default 100g
        }
        set {
            UserDefaults.standard.set(newValue, forKey: materialMassKey)
        }
    }
    
    // MARK: - Unknown Mode Display Setting
    
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
    
    // MARK: - Display Ranges (Persisted)
    
    /// Default minimum frequency for guitar tap tone spectrum display (Hz)
    static let defaultMinFrequency: Float = 75
    
    /// Default maximum frequency for guitar tap tone spectrum display (Hz)
    static let defaultMaxFrequency: Float = 350
    
    /// Default minimum magnitude for spectrum display (dB)
    static let defaultMinMagnitude: Float = -100
    
    /// Default maximum magnitude for spectrum display (dB)
    static let defaultMaxMagnitude: Float = 0
    
    /// Persisted minimum frequency for display (Hz)
    static var minFrequency: Float {
        get {
            let value = UserDefaults.standard.float(forKey: displayMinFreqKey)
            return value != 0 ? value : defaultMinFrequency
        }
        set {
            UserDefaults.standard.set(newValue, forKey: displayMinFreqKey)
        }
    }
    
    /// Persisted maximum frequency for display (Hz)
    static var maxFrequency: Float {
        get {
            let value = UserDefaults.standard.float(forKey: displayMaxFreqKey)
            return value != 0 ? value : defaultMaxFrequency
        }
        set {
            UserDefaults.standard.set(newValue, forKey: displayMaxFreqKey)
        }
    }
    
    /// Persisted minimum magnitude for display (dB)
    static var minMagnitude: Float {
        get {
            // Use object check since 0 is a valid value for dB
            if UserDefaults.standard.object(forKey: displayMinDBKey) == nil {
                return defaultMinMagnitude
            }
            return UserDefaults.standard.float(forKey: displayMinDBKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: displayMinDBKey)
        }
    }
    
    /// Persisted maximum magnitude for display (dB)
    static var maxMagnitude: Float {
        get {
            // Use object check since 0 is a valid value for dB
            if UserDefaults.standard.object(forKey: displayMaxDBKey) == nil {
                return defaultMaxMagnitude
            }
            return UserDefaults.standard.float(forKey: displayMaxDBKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: displayMaxDBKey)
        }
    }
    
    // MARK: - Analysis Settings (Persisted)
    
    /// Default minimum frequency for peak detection and analysis (Hz)
    static let defaultAnalysisMinFrequency: Float = 50
    
    /// Default maximum frequency for peak detection and analysis (Hz)
    static let defaultAnalysisMaxFrequency: Float = 2000
    
    /// Default minimum magnitude threshold for peak detection (dB)
    static let defaultPeakThreshold: Float = -60
    
    /// Default maximum number of peaks to detect and store (0 = all peaks)
    static let defaultMaxPeaks: Int = 0
    
    /// Persisted minimum frequency for analysis (Hz)
    static var analysisMinFrequency: Float {
        get {
            let value = UserDefaults.standard.float(forKey: analysisMinFreqKey)
            return value != 0 ? value : defaultAnalysisMinFrequency
        }
        set {
            UserDefaults.standard.set(newValue, forKey: analysisMinFreqKey)
        }
    }
    
    /// Persisted maximum frequency for analysis (Hz)
    static var analysisMaxFrequency: Float {
        get {
            let value = UserDefaults.standard.float(forKey: analysisMaxFreqKey)
            return value != 0 ? value : defaultAnalysisMaxFrequency
        }
        set {
            UserDefaults.standard.set(newValue, forKey: analysisMaxFreqKey)
        }
    }
    
    /// Persisted peak threshold (dB)
    static var peakThreshold: Float {
        get {
            // Use object check since negative values are common for dB
            if UserDefaults.standard.object(forKey: peakThresholdKey) == nil {
                return defaultPeakThreshold
            }
            return UserDefaults.standard.float(forKey: peakThresholdKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: peakThresholdKey)
        }
    }
    
    /// Persisted maximum number of peaks to detect and store
    /// A value of 0 means "capture all peaks" (no limit)
    static var maxPeaks: Int {
        get {
            // Use object check to distinguish between "not set" and "set to 0"
            if UserDefaults.standard.object(forKey: maxPeaksKey) == nil {
                return defaultMaxPeaks
            }
            return UserDefaults.standard.integer(forKey: maxPeaksKey)
        }
        set {
            // Allow 0 (all peaks) or any positive value
            UserDefaults.standard.set(max(0, newValue), forKey: maxPeaksKey)
        }
    }
    
    // MARK: - FFT Settings (Persisted)
    
    /// Default hop size overlap percentage
    static let defaultHopSizeOverlap: Float = 0
    
    /// Persisted hop size overlap percentage
    static var hopSizeOverlap: Float {
        get {
            // Use object check since 0 is a valid value
            if UserDefaults.standard.object(forKey: hopSizeOverlapKey) == nil {
                return defaultHopSizeOverlap
            }
            return UserDefaults.standard.float(forKey: hopSizeOverlapKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hopSizeOverlapKey)
        }
    }
    
    // MARK: - Tap Detection Settings (Persisted)
    
    /// Default tap detection threshold in dB
    static let defaultTapDetectionThreshold: Float = -40.0
    
    /// Default hysteresis margin in dB
    static let defaultHysteresisMargin: Float = 3.0
    
    /// Persisted tap detection threshold (dB)
    static var tapDetectionThreshold: Float {
        get {
            // Use object check since negative values are common for dB
            if UserDefaults.standard.object(forKey: tapDetectionThresholdKey) == nil {
                return defaultTapDetectionThreshold
            }
            return UserDefaults.standard.float(forKey: tapDetectionThresholdKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: tapDetectionThresholdKey)
        }
    }
    
    /// Persisted hysteresis margin (dB)
    static var hysteresisMargin: Float {
        get {
            // Use object check since 0 could theoretically be a valid value
            if UserDefaults.standard.object(forKey: hysteresisMarginKey) == nil {
                return defaultHysteresisMargin
            }
            return UserDefaults.standard.float(forKey: hysteresisMarginKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hysteresisMarginKey)
        }
    }
    
    // MARK: - Reset to Defaults
    
    /// Reset all persisted settings to their default values
    static func resetToDefaults() {
        guitarType = .acoustic
        showUnknownModes = false
        minFrequency = defaultMinFrequency
        maxFrequency = defaultMaxFrequency
        minMagnitude = defaultMinMagnitude
        maxMagnitude = defaultMaxMagnitude
        analysisMinFrequency = defaultAnalysisMinFrequency
        analysisMaxFrequency = defaultAnalysisMaxFrequency
        peakThreshold = defaultPeakThreshold
        maxPeaks = defaultMaxPeaks
        hopSizeOverlap = defaultHopSizeOverlap
        tapDetectionThreshold = defaultTapDetectionThreshold
        hysteresisMargin = defaultHysteresisMargin
    }
    
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
