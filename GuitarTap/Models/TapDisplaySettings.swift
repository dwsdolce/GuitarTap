/// # TapDisplaySettings
///
/// Global `UserDefaults`-backed settings store for GuitarTap's analysis and display
/// configuration.
///
/// ## Overview
///
/// All settings are persisted to `defaults` via static computed
/// properties on the `TapDisplaySettings` struct.  No `ObservableObject` is
/// involved; views read settings at construction time and re-read them when
/// the user changes a value through the settings UI.
///
/// Domain model types used by these settings live in the Models group:
/// ``MeasurementType``, ``GuitarType``, ``PlateStiffnessPreset``.
///
/// ## Settings groups
///
/// - Measurement type & guitar type
/// - Plate dimensions (length, width, thickness, mass in mm / g)
/// - Brace dimensions (separate from plate)
/// - Gore thicknessing inputs (body length, body width, f_vs preset)
/// - Per-type display frequency range (min/max Hz, stored per MeasurementType)
/// - Per-type dB range (min/max dB)
/// - Analysis frequency range (Hz)
/// - Peak detection parameters (threshold, max peaks, hysteresis, etc.)
/// - Tap counting and sequencing parameters
///
/// ## Guitar type vs measurement type
///
/// ``GuitarType`` (`.classical`, `.flamenco`, `.acoustic`) is a subset of
/// ``MeasurementType``.  The `guitarType` property is provided for backward
/// compatibility; new code should use `measurementType` instead.
///
/// ## UserDefaults key naming
///
/// Display frequency keys are per-measurement-type:
/// `"displayMinFreq_<MeasurementType.rawValue>"`.  A shared fallback key
/// `"displayMinFreq"` (no suffix) is retained for legacy data.
///
/// - SeeAlso: `TapSettingsView`, `TapToneAnalyzer`, `PDFReportData`
//
//  TapDisplaySettings.swift
//  GuitarTap
//
//  Created on 2/12/26.
//

import Foundation

/// Global, `UserDefaults`-backed settings for spectrum display and analysis
/// configuration.
///
/// `TapDisplaySettings` is a namespace of static properties; it is never
/// instantiated.  Every property is a computed `static var` that reads from
/// and writes to `defaults` using a private key constant.
///
/// Settings are grouped by function:
/// - **Measurement type** — which kind of analysis is active.
/// - **Plate/brace dimensions** — physical dimensions entered by the user.
/// - **Gore thicknessing** — guitar body dimensions and f_vs preset.
/// - **Display frequency range** — per-measurement-type min/max Hz for the chart.
/// - **dB range** — min/max dB for the vertical axis.
/// - **Analysis frequency range** — band within which peaks are searched.
/// - **Peak detection** — threshold, maximum peak count, hysteresis margin.
/// - **Tap sequencing** — FLC tap inclusion (`measureFlc`).
///
/// - SeeAlso: `TapSettingsView`, `TapToneAnalyzer`, `SpectrumView`
struct TapDisplaySettings {

    // MARK: - UserDefaults Instance
    //
    // All reads and writes go through this property. In production it points to
    // defaults. Tests can redirect it to an isolated named suite so
    // they never touch real user data:
    //
    //   TapDisplaySettings.defaults = UserDefaults(suiteName: "com.guitartap.tests")!
    //
    static var defaults: UserDefaults = {
        // When running under XCTest, use an isolated suite so tests never
        // pollute the user's real UserDefaults.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let suiteName = "com.guitartap.tests"
            let isolated = UserDefaults(suiteName: suiteName)!
            isolated.removePersistentDomain(forName: suiteName)
            return isolated
        }
        return .standard
    }()

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
    private static let tapDetectionThresholdKey = "tapDetectionThreshold"
    private static let hysteresisMarginKey = "hysteresisMargin"
    private static let measureFlcKey = "measureFlc"
    private static let annotationVisibilityModeKey = "annotationVisibilityMode"

    // MARK: - Measurement Type Setting
    
    /// The currently selected measurement type (persisted in UserDefaults)
    static var measurementType: MeasurementType {
        get {
            if let rawValue = defaults.string(forKey: measurementTypeKey),
               let type = MeasurementType(rawValue: rawValue) {
                return type
            }
            return .generic  // Default to generic (broad ranges covering all guitar types)
        }
        set {
            defaults.set(newValue.rawValue, forKey: measurementTypeKey)
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
            if let rawValue = defaults.string(forKey: guitarTypeKey),
               let type = GuitarType(rawValue: rawValue) {
                return type
            }
            return .generic  // Default to generic (broad ranges covering all guitar types)
        }
        set {
            defaults.set(newValue.rawValue, forKey: guitarTypeKey)
            // Also update measurementType
            measurementType = MeasurementType.from(newValue)
        }
    }
    
    // MARK: - Plate Dimensions (for Plate measurement type)
    
    /// Plate length in mm (along grain direction)
    static var plateLength: Float {
        get {
            let value = defaults.float(forKey: plateLengthKey)
            return value > 0 ? value : 500.0  // Default 500mm
        }
        set {
            defaults.set(newValue, forKey: plateLengthKey)
        }
    }
    
    /// Plate width in mm (cross grain direction)
    static var plateWidth: Float {
        get {
            let value = defaults.float(forKey: plateWidthKey)
            return value > 0 ? value : 200.0  // Default 200mm
        }
        set {
            defaults.set(newValue, forKey: plateWidthKey)
        }
    }
    
    /// Plate thickness in mm
    static var plateThickness: Float {
        get {
            let value = defaults.float(forKey: plateThicknessKey)
            return value > 0 ? value : 3.0  // Default 3mm
        }
        set {
            defaults.set(newValue, forKey: plateThicknessKey)
        }
    }
    
    /// Plate mass in grams
    static var plateMass: Float {
        get {
            let value = defaults.float(forKey: plateMassKey)
            return value > 0 ? value : 100.0  // Default 100g
        }
        set {
            defaults.set(newValue, forKey: plateMassKey)
        }
    }

    // MARK: - Gore Thicknessing Settings

    /// Guitar body length (neck join to tail, finished dimensions) in mm
    static var guitarBodyLength: Float {
        get {
            let value = defaults.float(forKey: guitarBodyLengthKey)
            return value > 0 ? value : 490.0  // Default 490mm
        }
        set {
            defaults.set(newValue, forKey: guitarBodyLengthKey)
        }
    }

    /// Guitar lower bout width (finished dimensions) in mm
    static var guitarBodyWidth: Float {
        get {
            let value = defaults.float(forKey: guitarBodyWidthKey)
            return value > 0 ? value : 390.0  // Default 390mm
        }
        set {
            defaults.set(newValue, forKey: guitarBodyWidthKey)
        }
    }

    /// Selected plate vibrational stiffness preset
    static var plateStiffnessPreset: PlateStiffnessPreset {
        get {
            if let raw = defaults.string(forKey: plateStiffnessPresetKey),
               let preset = PlateStiffnessPreset(rawValue: raw) {
                return preset
            }
            return .steelStringTop
        }
        set {
            defaults.set(newValue.rawValue, forKey: plateStiffnessPresetKey)
        }
    }

    /// Custom plate vibrational stiffness value (used when preset is .custom)
    static var customPlateStiffness: Float {
        get {
            let value = defaults.float(forKey: customPlateStiffnessKey)
            return value > 0 ? value : 75.0
        }
        set {
            defaults.set(newValue, forKey: customPlateStiffnessKey)
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
            let value = defaults.float(forKey: braceLengthKey)
            return value > 0 ? value : 300.0  // Default 300mm
        }
        set { defaults.set(newValue, forKey: braceLengthKey) }
    }
    
    /// Brace width in mm (across grain — the narrow horizontal cross-section when lying flat)
    static var braceWidth: Float {
        get {
            let value = defaults.float(forKey: braceWidthKey)
            return value > 0 ? value : 6.0  // Default 6mm
        }
        set { defaults.set(newValue, forKey: braceWidthKey) }
    }
    
    /// Brace height in mm — the vertical cross-section dimension when the brace lies flat.
    /// This is the dimension in the bending/vibration direction (t in the formula).
    static var braceThickness: Float {
        get {
            let value = defaults.float(forKey: braceThicknessKey)
            return value > 0 ? value : 12.0  // Default 12mm
        }
        set { defaults.set(newValue, forKey: braceThicknessKey) }
    }
    
    /// Brace mass in grams
    static var braceMass: Float {
        get {
            let value = defaults.float(forKey: braceMassKey)
            return value > 0 ? value : 8.0  // Default 8g
        }
        set { defaults.set(newValue, forKey: braceMassKey) }
    }
    
    // MARK: - Unknown Mode Display Setting
    
    /// Whether to display/report peaks classified as "Unknown" mode (persisted in UserDefaults)
    static var showUnknownModes: Bool {
        get {
            // Default to true (show unknown modes)
            if defaults.object(forKey: showUnknownModesKey) == nil {
                return true
            }
            return defaults.bool(forKey: showUnknownModesKey)
        }
        set {
            defaults.set(newValue, forKey: showUnknownModesKey)
        }
    }
    
    // MARK: - Annotation Visibility Mode

    /// The last-used annotation visibility mode (persisted in UserDefaults).
    ///
    /// Defaults to `.selected` on first launch.
    static var annotationVisibilityMode: AnnotationVisibilityMode {
        get {
            if let raw = defaults.string(forKey: annotationVisibilityModeKey),
               let mode = AnnotationVisibilityMode(rawValue: raw) {
                return mode
            }
            return .selected
        }
        set {
            defaults.set(newValue.rawValue, forKey: annotationVisibilityModeKey)
        }
    }

    // MARK: - Display Ranges (Persisted)
    
    /// Default minimum frequency for guitar spectrum display (Hz)
    static let defaultMinFrequency: Float = 75
    
    /// Default maximum frequency for guitar spectrum display (Hz)
    static let defaultMaxFrequency: Float = 350
    
    /// Default minimum frequency for plate spectrum display (Hz).
    /// Free-plate fLC values start as low as ~25 Hz; 20 Hz provides a small margin.
    static let defaultPlateMinFrequency: Float = 20

    /// Default maximum frequency for plate spectrum display (Hz).
    ///
    /// GuitarTap measures free-plate material properties using the tap-tone method
    /// described in:
    ///   Gore, T. & Gilet, G., "Contemporary Acoustic Guitar Design and Build,"
    ///   2nd ed., Vol. 1 §4.5 (Gore Guitars, 2011).
    ///
    /// The method is: tap a raw, unbraced rectangular plate blank and measure the
    /// three lowest bending/torsional resonances to derive elastic stiffness constants.
    /// The resulting frequencies across a range of tonewoods (spruce, cedar, etc.) are:
    ///
    ///   • fLC (torsional / twist mode):  ~25–76 Hz
    ///   • fL  (longitudinal bending):    ~43–77 Hz
    ///   • fC  (cross-grain bending):     ~57–194 Hz  ← sets the ceiling
    ///
    /// Empirical ranges from Trevor Gore course materials (multiple tonewoods).
    /// The method and the underlying physics (orthotropic plate equations) are
    /// documented in the book; for additional corroboration see:
    ///   Haines, D.W., "On musical instrument wood,"
    ///   Catgut Acoustical Society Newsletter 31, 23–32 (1979).
    ///
    /// Note: these are *free-plate* resonances on a raw blank, not assembled-box
    /// resonances (which are much higher at ~90–260 Hz and measure a different thing).
    ///
    /// 200 Hz provides a comfortable margin above the observed fC maximum (~194 Hz)
    /// while keeping the spectrum tightly focused on the region of interest.
    static let defaultPlateMaxFrequency: Float = 200
    
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
        let value = defaults.float(forKey: key)
        if value != 0 { return value }
        // Migrate legacy single-key value if present
        let legacy = defaults.float(forKey: displayMinFreqKey)
        return legacy != 0 ? legacy : defaultMinFrequency(for: type)
    }
    
    static func setMinFrequency(_ value: Float, for type: MeasurementType) {
        defaults.set(value, forKey: displayMinFreqKey(for: type))
    }
    
    /// Persisted maximum frequency for display for a specific measurement type (Hz)
    static func maxFrequency(for type: MeasurementType) -> Float {
        let key = displayMaxFreqKey(for: type)
        let value = defaults.float(forKey: key)
        if value != 0 { return value }
        // Migrate legacy single-key value if present, but only for non-brace types
        // (brace has a different default and shouldn't inherit an old guitar setting)
        if type != .brace {
            let legacy = defaults.float(forKey: displayMaxFreqKey)
            if legacy != 0 { return legacy }
        }
        return defaultMaxFrequency(for: type)
    }
    
    static func setMaxFrequency(_ value: Float, for type: MeasurementType) {
        defaults.set(value, forKey: displayMaxFreqKey(for: type))
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
            if defaults.object(forKey: displayMinDBKey) == nil {
                return defaultMinMagnitude
            }
            return defaults.float(forKey: displayMinDBKey)
        }
        set {
            defaults.set(newValue, forKey: displayMinDBKey)
        }
    }
    
    /// Persisted maximum magnitude for display (dB)
    static var maxMagnitude: Float {
        get {
            // Use object check since 0 is a valid value for dB
            if defaults.object(forKey: displayMaxDBKey) == nil {
                return defaultMaxMagnitude
            }
            return defaults.float(forKey: displayMaxDBKey)
        }
        set {
            defaults.set(newValue, forKey: displayMaxDBKey)
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
            let value = defaults.float(forKey: analysisMinFreqKey)
            return value != 0 ? value : defaultAnalysisMinFrequency
        }
        set {
            defaults.set(newValue, forKey: analysisMinFreqKey)
        }
    }
    
    /// Persisted maximum frequency for analysis (Hz)
    static var analysisMaxFrequency: Float {
        get {
            let value = defaults.float(forKey: analysisMaxFreqKey)
            return value != 0 ? value : defaultAnalysisMaxFrequency
        }
        set {
            defaults.set(newValue, forKey: analysisMaxFreqKey)
        }
    }
    
    /// Persisted peak threshold (dB)
    static var peakThreshold: Float {
        get {
            // Use object check since negative values are common for dB
            if defaults.object(forKey: peakThresholdKey) == nil {
                return defaultPeakThreshold
            }
            return defaults.float(forKey: peakThresholdKey)
        }
        set {
            defaults.set(newValue, forKey: peakThresholdKey)
        }
    }
    
    /// Persisted maximum number of peaks to detect and store
    /// A value of 0 means "capture all peaks" (no limit)
    static var maxPeaks: Int {
        get {
            // Use object check to distinguish between "not set" and "set to 0"
            if defaults.object(forKey: maxPeaksKey) == nil {
                return defaultMaxPeaks
            }
            return defaults.integer(forKey: maxPeaksKey)
        }
        set {
            // Allow 0 (all peaks) or any positive value
            defaults.set(max(0, newValue), forKey: maxPeaksKey)
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
            if defaults.object(forKey: tapDetectionThresholdKey) == nil {
                return defaultTapDetectionThreshold
            }
            return defaults.float(forKey: tapDetectionThresholdKey)
        }
        set {
            defaults.set(newValue, forKey: tapDetectionThresholdKey)
        }
    }
    
    /// Whether to perform the optional FLC (diagonal/shear) tap measurement
    /// FLC tap requires supporting the plate at all 4 nodal points - can be difficult
    /// Defaults to false since it's an advanced measurement
    static var measureFlc: Bool {
        get {
            if defaults.object(forKey: measureFlcKey) == nil {
                return false
            }
            return defaults.bool(forKey: measureFlcKey)
        }
        set {
            defaults.set(newValue, forKey: measureFlcKey)
        }
    }
    
    /// Persisted hysteresis margin (dB)
    static var hysteresisMargin: Float {
        get {
            // Use object check since 0 could theoretically be a valid value
            if defaults.object(forKey: hysteresisMarginKey) == nil {
                return defaultHysteresisMargin
            }
            return defaults.float(forKey: hysteresisMarginKey)
        }
        set {
            defaults.set(newValue, forKey: hysteresisMarginKey)
        }
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
