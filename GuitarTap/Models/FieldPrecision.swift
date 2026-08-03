// @parity util/field-precision
//
//  FieldPrecision.swift
//  GuitarTap
//
//  Single source of truth for numeric precision (decimal places) per field. One `P` per field
//  governs input (round-on-commit), storage, and display, so a value reads identically in the
//  input field, Settings, the saved measurement, and the PDF — and identically across the Swift,
//  Python, and web editions. Replaces the scattered ad-hoc `String(format: "%.Nf", …)` literals.
//
//  This table MUST stay identical across the Swift, Python, and web mirrors.
//
//  Precision table — P = decimal places:
//
//    INPUT / SETTINGS
//      linearDimensionMM   2   plate/brace length · width · thickness   0.01 mm  (caliper)
//      massG               1   plate/brace mass                         0.1 g
//      bodyDimensionMM     0   guitar body length · width               1 mm
//      frequencyHz         0   display frequency range                  1 Hz  (< FFT bin ≈1.46 Hz)
//      magnitudeDB         0   display magnitude range · thresholds     1 dB
//      stiffness           0   custom plate stiffness (f_vs)            1  (unitless)
//
//    COMPUTED / DISPLAYED
//      peakFrequencyHz     1        youngsModulusGPa    2
//      peakMagnitudeDB     1        speedOfSoundMS      0
//      qFactor             1        densityGPerCm3      3
//                                   decayRatio          2

import Foundation

enum FieldPrecision {
    // MARK: - Input / settings fields (decimal places)

    /// Plate/brace length, width, thickness — 0.01 mm (caliper resolution).
    static let linearDimensionMM = 2
    /// Plate/brace mass — 0.1 g.
    static let massG = 1
    /// Guitar body length/width — 1 mm (feeds only the Gore target).
    static let bodyDimensionMM = 0
    /// Display frequency range + tap/peak thresholds — 1 Hz (finer than the FFT bin).
    static let frequencyHz = 0
    /// Display magnitude range + thresholds — 1 dB.
    static let magnitudeDB = 0
    /// Custom plate stiffness (f_vs) — unitless.
    static let stiffness = 0

    // MARK: - Computed / displayed values (decimal places)

    static let peakFrequencyHz = 1
    static let peakMagnitudeDB = 1
    static let qFactor = 1
    static let youngsModulusGPa = 2
    static let speedOfSoundMS = 0
    static let densityGPerCm3 = 3
    static let decayRatio = 2

    // MARK: - Helpers

    /// Format a value for display at the given precision.
    static func string(_ value: Float, _ decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }

    /// Round a value to the given precision. Retained as a safety net for values that reach
    /// settings by a non-typed path; typed entry is restricted up front by `decimalsWithin`.
    static func rounded(_ value: Float, _ decimals: Int) -> Float {
        let m = powf(10, Float(decimals))
        return (value * m).rounded() / m
    }

    /// Whether `text` is an acceptable *partial* numeric entry for a field limited to `decimals`
    /// fractional digits — used to reject a keystroke that would exceed the field's precision, so
    /// the extra digit never appears (e.g. a 2-dp field accepts "29.35" but not "29.356"). Allows
    /// in-progress states ("", "-", "29", and "29." when `decimals > 0`) and a leading minus for dB
    /// fields. A 0-decimal field rejects the decimal point entirely (no stray trailing dot).
    static func decimalsWithin(_ text: String, _ decimals: Int) -> Bool {
        if text.isEmpty || text == "-" { return true }
        let pattern = decimals > 0 ? "^-?[0-9]*(\\.[0-9]{0,\(decimals)})?$" : "^-?[0-9]*$"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
