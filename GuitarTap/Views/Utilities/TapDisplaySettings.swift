//
//  TapDisplaySettings.swift
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
    case plate = "Material (Plate)"
    case brace = "Material (Brace)"
    
    var id: String { rawValue }
    
    /// Short name for display
    var shortName: String {
        switch self {
        case .classical: return "Classical"
        case .flamenco: return "Flamenco"
        case .acoustic: return "Acoustic"
        case .plate: return "Plate"
        case .brace: return "Brace"
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
        case .plate:
            return "Rectangular wood plate for calculating stiffness and sound radiation"
        case .brace:
            return "Brace strip — measures longitudinal stiffness (fL only)"
        }
    }
    
    /// Whether this is a guitar measurement (vs plate/brace)
    var isGuitar: Bool {
        switch self {
        case .classical, .flamenco, .acoustic:
            return true
        case .plate, .brace:
            return false
        }
    }
    
    /// Whether this is a brace measurement (single longitudinal tap only)
    var isBrace: Bool {
        switch self {
        case .brace: return true
        default: return false
        }
    }
    
    /// Convert to GuitarType if applicable
    var guitarType: GuitarType? {
        switch self {
        case .classical: return .classical
        case .flamenco: return .flamenco
        case .acoustic: return .acoustic
        case .plate, .brace: return nil
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

// MARK: - Plate Stiffness Preset

/// Preset vibrational stiffness targets for different plate types (Gore Eq. 4.5-7)
enum PlateStiffnessPreset: String, CaseIterable, Identifiable, Codable {
    case steelStringTop = "Steel String Top"
    case steelStringBack = "Steel String Back"
    case classicalTop = "Classical Top"
    case classicalBack = "Classical Back"
    case custom = "Custom"

    var id: String { rawValue }

    /// The vibrational stiffness value (f_vs) for this preset
    var value: Float {
        switch self {
        case .steelStringTop:  return 75
        case .steelStringBack: return 55
        case .classicalTop:    return 60
        case .classicalBack:   return 50
        case .custom:          return 0  // use customPlateStiffness
        }
    }

    var shortName: String {
        switch self {
        case .steelStringTop:  return "SS Top (75)"
        case .steelStringBack: return "SS Back (55)"
        case .classicalTop:    return "Classical Top (60)"
        case .classicalBack:   return "Classical Back (50)"
        case .custom:          return "Custom"
        }
    }
}

/// Centralized settings for spectrum display ranges across the app
struct TapDisplaySettings {

    // MARK: - UserDefaults Keys

    private static let measurementTypeKey = "measurementType"
    private static let guitarTypeKey = "guitarType"
    private static let showUnknownModesKey = "showUnknownModes"

    // Plate measurement keys
    private static let plateLengthKey = "plateLength"
    private static let plateWidthKey = "plateWidth"
    private static let plateThicknessKey = "plateThickness"
    private static let plateMassKey = "plateMass"

    // Gore thicknessing keys
    private static let guitarBodyLengthKey = "guitarBodyLength"
    private static let guitarBodyWidthKey = "guitarBodyWidth"
    private static let plateStiffnessPresetKey = "plateStiffnessPreset"
    private static let customPlateStiffnessKey = "customPlateStiffness"

    // Brace measurement keys (separate from plate measurement)
    private static let braceLengthKey = "braceLength"
    private static let braceWidthKey = "braceWidth"
    private static let braceThicknessKey = "braceThickness"
    private static let braceMassKey = "braceMass"
    private static let displayMinFreqKey = "displayMinFreq"   // legacy / shared fallback
    private static let displayMaxFreqKey = "displayMaxFreq"   // legacy / shared fallback
    private static let displayMinDBKey = "displayMinDB"
    private static let displayMaxDBKey = "displayMaxDB"
    
    /// Returns the UserDefaults key for the display minimum frequency for a given measurement type
    private static func displayMinFreqKey(for type: MeasurementType) -> String {
        "displayMinFreq_\(type.rawValue)"
    }
    
    /// Returns the UserDefaults key for the display maximum frequency for a given measurement type
    private static func displayMaxFreqKey(for type: MeasurementType) -> String {
        "displayMaxFreq_\(type.rawValue)"
    }
    private static let analysisMinFreqKey = "analysisMinFreq"
    private static let analysisMaxFreqKey = "analysisMaxFreq"
    private static let peakThresholdKey = "peakThreshold"
    private static let maxPeaksKey = "maxPeaks"
    private static let hopSizeOverlapKey = "hopSizeOverlap"
    private static let tapDetectionThresholdKey = "tapDetectionThreshold"
    private static let hysteresisMarginKey = "hysteresisMargin"
    private static let measureFlcKey = "measureFlc"
    
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
    
    // MARK: - Plate Dimensions (for Plate measurement type)
    
    /// Plate length in mm (along grain direction)
    static var plateLength: Float {
        get {
            let value = UserDefaults.standard.float(forKey: plateLengthKey)
            return value > 0 ? value : 500.0  // Default 500mm
        }
        set {
            UserDefaults.standard.set(newValue, forKey: plateLengthKey)
        }
    }
    
    /// Plate width in mm (cross grain direction)
    static var plateWidth: Float {
        get {
            let value = UserDefaults.standard.float(forKey: plateWidthKey)
            return value > 0 ? value : 200.0  // Default 200mm
        }
        set {
            UserDefaults.standard.set(newValue, forKey: plateWidthKey)
        }
    }
    
    /// Plate thickness in mm
    static var plateThickness: Float {
        get {
            let value = UserDefaults.standard.float(forKey: plateThicknessKey)
            return value > 0 ? value : 3.0  // Default 3mm
        }
        set {
            UserDefaults.standard.set(newValue, forKey: plateThicknessKey)
        }
    }
    
    /// Plate mass in grams
    static var plateMass: Float {
        get {
            let value = UserDefaults.standard.float(forKey: plateMassKey)
            return value > 0 ? value : 100.0  // Default 100g
        }
        set {
            UserDefaults.standard.set(newValue, forKey: plateMassKey)
        }
    }

    // MARK: - Gore Thicknessing Settings

    /// Guitar body length (neck join to tail, finished dimensions) in mm
    static var guitarBodyLength: Float {
        get {
            let value = UserDefaults.standard.float(forKey: guitarBodyLengthKey)
            return value > 0 ? value : 490.0  // Default 490mm
        }
        set {
            UserDefaults.standard.set(newValue, forKey: guitarBodyLengthKey)
        }
    }

    /// Guitar lower bout width (finished dimensions) in mm
    static var guitarBodyWidth: Float {
        get {
            let value = UserDefaults.standard.float(forKey: guitarBodyWidthKey)
            return value > 0 ? value : 390.0  // Default 390mm
        }
        set {
            UserDefaults.standard.set(newValue, forKey: guitarBodyWidthKey)
        }
    }

    /// Selected plate vibrational stiffness preset
    static var plateStiffnessPreset: PlateStiffnessPreset {
        get {
            if let raw = UserDefaults.standard.string(forKey: plateStiffnessPresetKey),
               let preset = PlateStiffnessPreset(rawValue: raw) {
                return preset
            }
            return .steelStringTop
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: plateStiffnessPresetKey)
        }
    }

    /// Custom plate vibrational stiffness value (used when preset is .custom)
    static var customPlateStiffness: Float {
        get {
            let value = UserDefaults.standard.float(forKey: customPlateStiffnessKey)
            return value > 0 ? value : 75.0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: customPlateStiffnessKey)
        }
    }

    /// The effective plate vibrational stiffness value (preset or custom)
    static var plateStiffness: Float {
        let preset = plateStiffnessPreset
        return preset == .custom ? customPlateStiffness : preset.value
    }

    // MARK: - Brace Dimensions (for Brace measurement type)
    
    /// Brace length in mm (along grain direction)
    static var braceLength: Float {
        get {
            let value = UserDefaults.standard.float(forKey: braceLengthKey)
            return value > 0 ? value : 300.0  // Default 300mm
        }
        set { UserDefaults.standard.set(newValue, forKey: braceLengthKey) }
    }
    
    /// Brace width in mm (across grain — the narrow horizontal cross-section when lying flat)
    static var braceWidth: Float {
        get {
            let value = UserDefaults.standard.float(forKey: braceWidthKey)
            return value > 0 ? value : 6.0  // Default 6mm
        }
        set { UserDefaults.standard.set(newValue, forKey: braceWidthKey) }
    }
    
    /// Brace height in mm — the vertical cross-section dimension when the brace lies flat.
    /// This is the dimension in the bending/vibration direction (t in the formula).
    static var braceThickness: Float {
        get {
            let value = UserDefaults.standard.float(forKey: braceThicknessKey)
            return value > 0 ? value : 12.0  // Default 12mm
        }
        set { UserDefaults.standard.set(newValue, forKey: braceThicknessKey) }
    }
    
    /// Brace mass in grams
    static var braceMass: Float {
        get {
            let value = UserDefaults.standard.float(forKey: braceMassKey)
            return value > 0 ? value : 8.0  // Default 8g
        }
        set { UserDefaults.standard.set(newValue, forKey: braceMassKey) }
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
    
    /// Default minimum frequency for guitar spectrum display (Hz)
    static let defaultMinFrequency: Float = 75
    
    /// Default maximum frequency for guitar spectrum display (Hz)
    static let defaultMaxFrequency: Float = 350
    
    /// Default minimum frequency for plate spectrum display (Hz)
    /// Plate resonances (fL, fC, fLC) typically start in the 30–80 Hz range
    static let defaultPlateMinFrequency: Float = 30
    
    /// Default maximum frequency for plate spectrum display (Hz)
    static let defaultPlateMaxFrequency: Float = 600
    
    /// Default minimum frequency for brace spectrum display (Hz)
    static let defaultBraceMinFrequency: Float = 30
    
    /// Default maximum frequency for brace spectrum display (Hz)
    static let defaultBraceMaxFrequency: Float = 1000
    
    /// Returns the default minimum display frequency for the given measurement type
    static func defaultMinFrequency(for type: MeasurementType) -> Float {
        switch type {
        case .plate: return defaultPlateMinFrequency
        case .brace:    return defaultBraceMinFrequency
        default:        return defaultMinFrequency
        }
    }
    
    /// Returns the default maximum display frequency for the given measurement type
    static func defaultMaxFrequency(for type: MeasurementType) -> Float {
        switch type {
        case .plate: return defaultPlateMaxFrequency
        case .brace:    return defaultBraceMaxFrequency
        default:        return defaultMaxFrequency
        }
    }
    
    /// Default minimum magnitude for spectrum display (dB)
    static let defaultMinMagnitude: Float = -100
    
    /// Default maximum magnitude for spectrum display (dB)
    static let defaultMaxMagnitude: Float = 0
    
    /// Persisted minimum frequency for display for a specific measurement type (Hz)
    static func minFrequency(for type: MeasurementType) -> Float {
        let key = displayMinFreqKey(for: type)
        let value = UserDefaults.standard.float(forKey: key)
        if value != 0 { return value }
        // Migrate legacy single-key value if present
        let legacy = UserDefaults.standard.float(forKey: displayMinFreqKey)
        return legacy != 0 ? legacy : defaultMinFrequency(for: type)
    }
    
    static func setMinFrequency(_ value: Float, for type: MeasurementType) {
        UserDefaults.standard.set(value, forKey: displayMinFreqKey(for: type))
    }
    
    /// Persisted maximum frequency for display for a specific measurement type (Hz)
    static func maxFrequency(for type: MeasurementType) -> Float {
        let key = displayMaxFreqKey(for: type)
        let value = UserDefaults.standard.float(forKey: key)
        if value != 0 { return value }
        // Migrate legacy single-key value if present, but only for non-brace types
        // (brace has a different default and shouldn't inherit an old guitar setting)
        if type != .brace {
            let legacy = UserDefaults.standard.float(forKey: displayMaxFreqKey)
            if legacy != 0 { return legacy }
        }
        return defaultMaxFrequency(for: type)
    }
    
    static func setMaxFrequency(_ value: Float, for type: MeasurementType) {
        UserDefaults.standard.set(value, forKey: displayMaxFreqKey(for: type))
    }
    
    /// Persisted minimum frequency for display using the current measurement type (Hz)
    static var minFrequency: Float {
        get { minFrequency(for: measurementType) }
        set { setMinFrequency(newValue, for: measurementType) }
    }
    
    /// Persisted maximum frequency for display using the current measurement type (Hz)
    static var maxFrequency: Float {
        get { maxFrequency(for: measurementType) }
        set { setMaxFrequency(newValue, for: measurementType) }
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
    static let defaultAnalysisMinFrequency: Float = 30
    
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
    
    /// Whether to perform the optional FLC (diagonal/shear) tap measurement
    /// FLC tap requires supporting the plate at all 4 nodal points - can be difficult
    /// Defaults to false since it's an advanced measurement
    static var measureFlc: Bool {
        get {
            if UserDefaults.standard.object(forKey: measureFlcKey) == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: measureFlcKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: measureFlcKey)
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
        measureFlc = false
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
