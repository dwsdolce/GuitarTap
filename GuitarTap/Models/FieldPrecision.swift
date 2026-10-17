// @parity util/field-precision tests=test/field-precision
//
//  FieldPrecision.swift
//  GuitarTap
//
//  Single source of truth for numeric precision (decimal places) per value. An input field's `P`
//  limits what can be typed and rounds what is committed; a computed value's `P` is the decimals it
//  is shown with, on screen, in exports and in the PDF. Every display of a number formats it through
//  `string` with its entry, so a value reads identically everywhere and across the Swift, Python and
//  web editions. The saved display range is stored exactly, not rounded to `frequencyHz` / `magnitudeDB`.
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
//      peakFrequencyHz     1        youngsModulusGPa    2        radiationRatio      1
//      peakMagnitudeDB     1        shearModulusGPa     3        crossLongRatio      3
//      qFactor             1        specificModulus     1        longCrossRatio      1
//      bandwidthHz         1        speedOfSoundMS      0        decayTimeS          2
//      goreThicknessMM     2        densityGPerCm3      3        decayRatio          2

import Foundation

enum FieldPrecision {
    // MARK: - Input / settings fields (decimal places)

    /// Plate/brace length, width, thickness — 0.01 mm (caliper resolution).
    static let linearDimensionMM = 2
    /// Plate/brace mass — 0.1 g.
    static let massG = 1
    /// Guitar body length/width — 1 mm (feeds only the Gore target).
    static let bodyDimensionMM = 0
    /// Display frequency range — 1 Hz (finer than the FFT bin).
    static let frequencyHz = 0
    /// Display magnitude range + thresholds — 1 dB.
    static let magnitudeDB = 0
    /// Custom plate stiffness (f_vs) — unitless.
    static let stiffness = 0

    // MARK: - Computed / displayed values (decimal places)

    static let peakFrequencyHz = 1
    static let peakMagnitudeDB = 1
    static let qFactor = 1
    /// A peak's bandwidth (frequency / Q).
    static let bandwidthHz = 1
    static let youngsModulusGPa = 2
    /// The plate's GLC shear modulus.
    static let shearModulusGPa = 3
    /// E / ρ, in GPa per g/cm³.
    static let specificModulus = 1
    static let speedOfSoundMS = 0
    static let densityGPerCm3 = 3
    static let radiationRatio = 1
    /// fC / fL stiffness ratio.
    static let crossLongRatio = 3
    /// fL / fC stiffness ratio.
    static let longCrossRatio = 1
    static let goreThicknessMM = 2
    /// Ring-out (decay) time, in seconds.
    static let decayTimeS = 2
    /// The tap-tone ratio (f_Top / f_Air).
    static let decayRatio = 2

    // MARK: - Helpers

    /// Format a value for display at the given precision: the `Float`, rounded as C does — to the
    /// nearest, an exact tie to even.
    ///
    /// Infinity reads as "-∞" / "∞" — what SwiftUI's `specifier:` shows — not the C formatter's
    /// "-inf". A silent input's peak is -∞ dB, and it must not look different from one screen to
    /// the next.
    static func string(_ value: Float, _ decimals: Int) -> String {
        if value.isInfinite { return value < 0 ? "-∞" : "∞" }
        return String(format: "%.\(decimals)f", value)
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
