//
//  MaterialProperties.swift
//  GuitarTap
//
//  Calculates acoustic properties of wood from tap test measurements on rectangular plates.
//  Used for evaluating tonewood quality for guitar tops, backs, and other instrument parts.
//
// @parity dsp/material-properties tests=test/brace,test/plate

/// # MaterialProperties
///
/// Acoustic and mechanical properties of tonewoods derived from free-free beam tap tests.
///
/// ## Background — The Tap-Test Method
///
/// Suspending a rectangular plate at its nodal points and tapping it produces a resonant
/// "ping" whose fundamental frequency depends on the plate's geometry, mass, and elastic
/// moduli.  By measuring the fundamental frequency in the longitudinal (along-grain) and
/// cross-grain directions, the Young's moduli `E_L` and `E_C` can be back-calculated using
/// the Euler–Bernoulli free-free beam equation.  A third optional tap at 45° (the FLC or
/// "diagonal" tap) yields the shear modulus `G_LC`.
///
/// ## Free-Free Beam Equation
///
/// ```
/// E = 48 × π² × ρ × f² × L⁴ / (β × L)²
/// ```
///
/// where:
/// - `ρ` = density (kg/m³)
/// - `f` = fundamental bending frequency (Hz)
/// - `L` = beam length (m) — use plate length for L-tap, plate width for C-tap
/// - `(βL)² = 22.37` for the first free-free bending mode — first root of
///   `cos(βL)·cosh(βL) = 1`, i.e. βL = 4.7300… (Blevins 1979, Table 8-1).
///   Applied to lutherie wood by Haines (1979, 2000) — see
///   *Documentation/tonewood-references.md* for full citations.
///
/// ## Gore Plate Equations
///
/// ``PlateProperties`` also implements the more accurate plate-theory approach from
/// *Gore, T. & Gilet, G., "Contemporary Acoustic Guitar Design and Build", 2nd ed. (2016)*
/// (Vol. 1 ISBN: 978-0-9871174-2-7).  The plate
/// equations account for Poisson coupling between the two axes and give more accurate
/// modulus values for thin plates (typical guitar-top ratios of L/t ≈ 50–150).
///
/// ## Key Derived Properties
///
/// | Property | Formula | Significance |
/// |----------|---------|--------------|
/// | Specific modulus | `E / ρ` (GPa/(g/cm³)) | Primary quality indicator; higher = lighter, stiffer wood |
/// | Speed of sound | `√(E/ρ)` (m/s) | Governs how quickly vibrations travel through the plate |
/// | Radiation ratio | `c_L / ρ` | Efficiency of acoustic power radiation |
import Foundation
import SwiftUI

// MARK: - MaterialDimensions

/// The physical dimensions and mass of a rectangular material sample (plate or brace).
///
/// All stored values are in SI units (metres and kilograms).  Convenience initialisers
/// accept millimetres and grams, which are the more practical units when measuring
/// guitar plates and braces with callipers and a digital scale.
struct MaterialDimensions {

    /// Length of the sample in metres.
    ///
    /// For wood, orient the sample so that this dimension runs **along** the grain
    /// (longitudinal direction).
    let length: Float

    /// Width of the sample in metres.
    ///
    /// For wood, this dimension runs **across** the grain (cross-grain direction).
    let width: Float

    /// Thickness of the sample in metres.
    let thickness: Float

    /// Mass of the sample in kilograms.
    let mass: Float

    // MARK: - Initialisers

    /// Creates `MaterialDimensions` from the practical measurement units used for guitar work.
    ///
    /// - Parameters:
    ///   - lengthMM: Sample length in millimetres (along-grain for wood).
    ///   - widthMM: Sample width in millimetres (cross-grain for wood).
    ///   - thicknessMM: Sample thickness in millimetres.
    ///   - massGrams: Sample mass in grams.
    init(lengthMM: Float, widthMM: Float, thicknessMM: Float, massGrams: Float) {
        self.length    = lengthMM    / 1000.0
        self.width     = widthMM     / 1000.0
        self.thickness = thicknessMM / 1000.0
        self.mass      = massGrams   / 1000.0
    }

    /// Creates `MaterialDimensions` directly from SI units.
    ///
    /// - Parameters:
    ///   - length: Sample length in metres.
    ///   - width: Sample width in metres.
    ///   - thickness: Sample thickness in metres.
    ///   - mass: Sample mass in kilograms.
    init(length: Float, width: Float, thickness: Float, mass: Float) {
        self.length    = length
        self.width     = width
        self.thickness = thickness
        self.mass      = mass
    }

    // MARK: - Derived Properties

    /// Volume of the sample in m³.
    var volume: Float {
        length * width * thickness
    }

    /// Density of the sample in kg/m³.
    ///
    /// Returns 0 when ``volume`` is zero to avoid division-by-zero.
    var density: Float {
        guard volume > 0 else { return 0 }
        return mass / volume
    }

    /// Density in g/cm³, the unit conventionally used for wood density tables.
    ///
    /// Equals ``density`` / 1000.  Typical guitar-top spruce: 0.35–0.45 g/cm³.
    var densityGPerCm3: Float {
        density / 1000.0
    }
}

// MARK: - PlateProperties

/// Acoustic properties of a rectangular plate sample calculated from two or three tap-test
/// fundamental frequencies.
///
/// Two tap orientations are required for a full plate analysis (longitudinal and cross-grain);
/// a third optional diagonal tap yields the shear modulus.
///
/// Properties are available in two flavours:
/// - **Beam formula** (``youngsModulusLong``, ``youngsModulusCross``) — uses the Euler–Bernoulli
///   free-free beam equation.  Simpler but slightly less accurate for thin plates.
/// - **Gore plate formula** (``goreYoungsModulusLong``, ``goreYoungsModulusCross``) — accounts
///   for Poisson coupling between axes.  More accurate for typical guitar-plate aspect ratios.
///
/// - SeeAlso: ``BraceProperties`` for single-tap longitudinal-only analysis.
/// - SeeAlso: ``WoodQuality`` for quality assessment thresholds.
struct PlateProperties {

    /// Dimensions and mass of the sample.
    let dimensions: MaterialDimensions

    /// Fundamental bending frequency from the longitudinal (along-grain) tap, in Hz.
    ///
    /// The plate is suspended at its nodal points (22% from each end along its length)
    /// and tapped at the centre to excite the first free-free bending mode.
    let fundamentalFrequencyLong: Float

    /// Fundamental bending frequency from the cross-grain tap, in Hz.
    ///
    /// The plate is rotated 90° and suspended at the nodal points along its width before tapping.
    let fundamentalFrequencyCross: Float

    /// Fundamental frequency from the FLC (45°-diagonal / torsional) tap, in Hz.
    ///
    /// The plate is held at the midpoint of one long edge and tapped near the opposite corner
    /// (~22% from the end and side).  `nil` when the optional third tap was not performed.
    let fundamentalFrequencyFlc: Float?

    // MARK: - Initialiser

    /// Creates a `PlateProperties` record from dimensions and measured fundamental frequencies.
    ///
    /// - Parameters:
    ///   - dimensions: Physical dimensions and mass of the plate.
    ///   - fundamentalFrequencyLong: Along-grain fundamental frequency in Hz.
    ///   - fundamentalFrequencyCross: Cross-grain fundamental frequency in Hz.
    ///   - fundamentalFrequencyFlc: Optional FLC diagonal frequency in Hz.
    init(dimensions: MaterialDimensions,
         fundamentalFrequencyLong: Float,
         fundamentalFrequencyCross: Float,
         fundamentalFrequencyFlc: Float? = nil) {
        self.dimensions                = dimensions
        self.fundamentalFrequencyLong  = fundamentalFrequencyLong
        self.fundamentalFrequencyCross = fundamentalFrequencyCross
        self.fundamentalFrequencyFlc   = fundamentalFrequencyFlc
    }

    // MARK: - Beam-Formula Young's Moduli

    /// Young's modulus along the grain (E_L) in Pascals, from the free-free beam formula.
    ///
    /// Formula (Euler–Bernoulli free-free beam, first mode):
    /// ```
    /// E = 48 × π² × ρ × fL² × L⁴ / (22.37 × t)²
    /// ```
    /// where `L` is the plate length (along-grain), `t` is thickness, and `ρ` is density.
    ///
    /// Returns 0 when thickness or density is zero.
    var youngsModulusLong: Float {
        let t = dimensions.thickness
        guard t > 0, dimensions.density > 0 else { return 0 }
        return 48 * .pi * .pi * dimensions.density
            * fundamentalFrequencyLong * fundamentalFrequencyLong
            * pow(dimensions.length, 4)
            / pow(22.37 * t, 2)
    }

    /// Young's modulus across the grain (E_C) in Pascals, from the free-free beam formula.
    ///
    /// Uses the plate **width** (cross-grain dimension) as the effective beam length:
    /// ```
    /// E = 48 × π² × ρ × fC² × W⁴ / (22.37 × t)²
    /// ```
    ///
    /// Returns 0 when thickness or density is zero.
    var youngsModulusCross: Float {
        let t = dimensions.thickness
        guard t > 0, dimensions.density > 0 else { return 0 }
        return 48 * .pi * .pi * dimensions.density
            * fundamentalFrequencyCross * fundamentalFrequencyCross
            * pow(dimensions.width, 4)
            / pow(22.37 * t, 2)
    }

    // MARK: - Speed of Sound

    /// Speed of sound along the grain (longitudinal) in m/s.
    ///
    /// Derived from Young's modulus by the standard elastic-wave relation: `c = √(E / ρ)`.
    /// Typical values for guitar-top spruce: 4 800–5 800 m/s.
    var speedOfSoundLong: Float {
        guard dimensions.density > 0 else { return 0 }
        return sqrt(youngsModulusLong / dimensions.density)
    }

    /// Speed of sound across the grain in m/s.
    ///
    /// Typical values for spruce: 900–1 800 m/s (much lower than longitudinal).
    var speedOfSoundCross: Float {
        guard dimensions.density > 0 else { return 0 }
        return sqrt(youngsModulusCross / dimensions.density)
    }

    // MARK: - Convenience Unit Conversions

    /// Young's modulus along the grain in GPa (gigapascals).
    ///
    /// Typical range for guitar-top spruce: 8–16 GPa.
    var youngsModulusLongGPa: Float { youngsModulusLong / 1e9 }

    /// Young's modulus across the grain in GPa.
    ///
    /// Typical range for spruce: 0.4–1.2 GPa.
    var youngsModulusCrossGPa: Float { youngsModulusCross / 1e9 }

    // MARK: - Specific Modulus

    /// Specific modulus (stiffness-to-weight ratio) along the grain, in GPa/(g/cm³).
    ///
    /// The primary quality metric for guitar tonewoods: higher values indicate wood that
    /// vibrates more freely for a given mass, enabling a lighter, more responsive plate.
    /// Excellent spruce tops: ≥ 25 GPa/(g/cm³); good: 19–22.
    var specificModulusLong: Float {
        guard dimensions.densityGPerCm3 > 0 else { return 0 }
        return youngsModulusLongGPa / dimensions.densityGPerCm3
    }

    /// Specific modulus across the grain, in GPa/(g/cm³).
    ///
    /// Much lower than the longitudinal value; typical spruce range: 0.5–2.0 GPa/(g/cm³).
    var specificModulusCross: Float {
        guard dimensions.densityGPerCm3 > 0 else { return 0 }
        return youngsModulusCrossGPa / dimensions.densityGPerCm3
    }

    // MARK: - Radiation Ratio

    /// Sound radiation coefficient (radiation ratio) along the grain.
    ///
    /// Formula: `R = c_L / ρ`, equivalent to `√(E/ρ) / ρ`.
    /// A higher radiation ratio indicates more efficient conversion of vibrational energy
    /// into acoustic radiation.  Typical guitar-top spruce: 10–15 m⁴/(kg·s).
    var radiationRatioLong: Float {
        guard dimensions.density > 0 else { return 0 }
        return speedOfSoundLong / dimensions.density
    }

    /// Sound radiation coefficient across the grain.
    var radiationRatioCross: Float {
        guard dimensions.density > 0 else { return 0 }
        return speedOfSoundCross / dimensions.density
    }

    // MARK: - Anisotropy Ratios

    /// Cross-grain to long-grain Young's modulus ratio (E_C / E_L).
    ///
    /// Indicates the degree of wood anisotropy.  Lower values mean more anisotropic wood
    /// (more directional stiffness), which is generally desirable for guitar tops.
    /// Typical spruce: 0.04–0.08.
    var crossLongRatio: Float {
        guard youngsModulusLong > 0 else { return 0 }
        return youngsModulusCross / youngsModulusLong
    }

    /// Long-grain to cross-grain Young's modulus ratio (E_L / E_C).
    ///
    /// The inverse of ``crossLongRatio``.  Higher values indicate more anisotropic wood.
    /// Typical spruce: 12–25.
    var longCrossRatio: Float {
        guard youngsModulusCross > 0 else { return 0 }
        return youngsModulusLong / youngsModulusCross
    }

    // MARK: - Quality Assessment

    /// Wood-quality rating for the longitudinal direction, evaluated using spruce thresholds.
    ///
    /// - SeeAlso: ``WoodQuality/evaluate(specificModulus:direction:woodType:)``
    var spruceQualityLong: WoodQuality {
        WoodQuality.evaluate(specificModulus: specificModulusLong, direction: .longitudinal, woodType: .spruce)
    }

    /// Wood-quality rating for the cross-grain direction, evaluated using spruce thresholds.
    var spruceQualityCross: WoodQuality {
        WoodQuality.evaluate(specificModulus: specificModulusCross, direction: .cross, woodType: .spruce)
    }

    /// Overall quality rating for use as a guitar-top material.
    ///
    /// Computed as a weighted average of the longitudinal (70%) and cross-grain (30%)
    /// quality scores, since longitudinal stiffness is the dominant factor for top-plate
    /// vibration.
    var overallQuality: WoodQuality {
        // Longitudinal is weighted more heavily as it dominates top-plate stiffness.
        let longScore  = spruceQualityLong.numericScore  * 0.7
        let crossScore = spruceQualityCross.numericScore * 0.3
        let combined   = longScore + crossScore

        if combined >= 4.5 { return .excellent }
        if combined >= 3.5 { return .veryGood  }
        if combined >= 2.5 { return .good       }
        if combined >= 1.5 { return .fair       }
        return .poor
    }

    // MARK: - Gore Plate Thicknessing (Eq. 4.5-7)

    /// Poisson's ratio ν_CL — Gore's recommended average for softwoods.
    private static let vcl: Float = 0.05

    /// Product ν_LC × ν_CL — Gore's recommended average for softwoods.
    private static let vlcVcl: Float = 0.02

    /// Gore coefficient 1: `(1 / ((π/2)² × (3/2)⁴)) × 12 × (1 − ν_LC·ν_CL)`.
    ///
    /// Scales the density-frequency-geometry product into units of Pa for the plate E formulae.
    private var goreCoef1: Float {
        let term = pow(Float.pi / 2.0, 2.0) * pow(1.5, 4.0)
        return (1.0 / term) * 12.0 * (1.0 - PlateProperties.vlcVcl)
    }

    /// Gore coefficient 2: `π × √(12 × (1 − ν_LC·ν_CL) / 126)`.
    ///
    /// Appears in the numerator of the Gore target-thickness equation.
    private var goreCoef2: Float {
        return Float.pi * sqrt(12.0 * (1.0 - PlateProperties.vlcVcl) / 126.0)
    }

    /// Gore coefficient 3: `4 × ν_CL / 7`.
    ///
    /// Poisson correction for the E_L term in the target-thickness denominator.
    private var goreCoef3: Float {
        return 4.0 * PlateProperties.vcl / 7.0
    }

    /// Gore coefficient 4: `4 × 12 × (1 − ν_LC·ν_CL) / 42`.
    ///
    /// Shear-modulus scaling factor in the target-thickness denominator.
    private var goreCoef4: Float {
        return 4.0 * 12.0 * (1.0 - PlateProperties.vlcVcl) / 42.0
    }

    // MARK: - Gore Young's Moduli

    /// Young's modulus along the grain using Gore's plate formula, in Pascals.
    ///
    /// Formula: `E_L = Coef₁ × ρ × L⁴ × fL² / t²`
    ///
    /// More accurate than the beam formula for thin plates because it accounts for Poisson
    /// coupling through the `Coef₁` term.
    var goreYoungsModulusLong: Float {
        let t = dimensions.thickness
        guard t > 0, dimensions.density > 0 else { return 0 }
        return goreCoef1 * dimensions.density
            * pow(dimensions.length, 4.0)
            * fundamentalFrequencyLong * fundamentalFrequencyLong
            / (t * t)
    }

    /// Young's modulus across the grain using Gore's plate formula, in Pascals.
    ///
    /// Formula: `E_C = Coef₁ × ρ × W⁴ × fC² / t²`
    var goreYoungsModulusCross: Float {
        let t = dimensions.thickness
        guard t > 0, dimensions.density > 0 else { return 0 }
        return goreCoef1 * dimensions.density
            * pow(dimensions.width, 4.0)
            * fundamentalFrequencyCross * fundamentalFrequencyCross
            / (t * t)
    }

    /// Shear modulus G_LC using Gore's formula, in Pascals.
    ///
    /// Formula: `G_LC = (12/π²) × ρ × L² × W² × fLC² / t²`
    ///
    /// Returns `nil` when the optional FLC diagonal tap was not performed and
    /// ``fundamentalFrequencyFlc`` is therefore `nil`.
    var goreShearModulus: Float? {
        guard let fLC = fundamentalFrequencyFlc else { return nil }
        let t = dimensions.thickness
        guard t > 0, dimensions.density > 0 else { return nil }
        let coef = 12.0 / (Float.pi * Float.pi)
        return coef * dimensions.density
            * pow(dimensions.length, 2.0)
            * pow(dimensions.width, 2.0)
            * fLC * fLC
            / (t * t)
    }

    // MARK: - Gore Target Thickness

    /// Target thickness for the finished guitar plate, in mm — from Gore Equation 4.5-7.
    ///
    /// Uses the Gore plate moduli (E_L, E_C, G_LC) together with the guitar body geometry
    /// and a target vibrational stiffness (`f_vs`) to calculate the optimal plate thickness
    /// that will yield the desired stiffness once shaped to the guitar body outline.
    ///
    /// When the FLC tap has not been performed, G_LC is treated as 0.  This omission
    /// typically causes a slight over-estimate of the target thickness (about 5–7%).
    ///
    /// **Numerator:** `Coef₂ × f_vs × a² × √ρ`
    ///
    /// **Denominator:** `√(E_L + (a/b)⁴·E_C + (a/b)²·(Coef₃·E_L + Coef₄·G_LC))`
    ///
    /// **Typical `f_vs` values:**
    /// - Steel-string top: 75
    /// - Steel-string back: 55
    /// - Classical top: 60
    /// - Classical back: 50
    ///
    /// - Parameters:
    ///   - bodyLengthMm: Guitar body length (neck joint to tail block) in mm.
    ///   - bodyWidthMm: Guitar lower-bout width in mm.
    ///   - vibrationalStiffness: Target vibrational stiffness (`f_vs`).
    /// - Returns: Target plate thickness in mm, or `nil` if any input is zero or invalid.
    func goreTargetThickness(bodyLengthMm: Float, bodyWidthMm: Float, vibrationalStiffness: Float) -> Float? {
        guard bodyLengthMm > 0, bodyWidthMm > 0, vibrationalStiffness > 0 else { return nil }
        guard dimensions.density > 0 else { return nil }

        let a   = bodyLengthMm / 1000.0   // Guitar body length in metres
        let b   = bodyWidthMm  / 1000.0   // Lower bout width in metres
        let rho = dimensions.density       // Density of the test plate in kg/m³

        // Convert moduli to GPa for the denominator calculation; result is in Pa via ×10⁹.
        let elGPa  = goreYoungsModulusLong  / 1.0e9
        let ecGPa  = goreYoungsModulusCross / 1.0e9
        // Use G_LC from the FLC tap; fall back to 0 when the tap was not performed.
        let glcGPa = (goreShearModulus ?? 0) / 1.0e9

        // Numerator: scale target stiffness by body area and root-density.
        let numerator = goreCoef2 * vibrationalStiffness * a * a * sqrt(rho)

        // Denominator: anisotropic stiffness sum scaled by body aspect ratio.
        let aOverB  = a / b
        let aOverB2 = aOverB  * aOverB
        let aOverB4 = aOverB2 * aOverB2
        let denominatorGPa = elGPa
            + aOverB4 * ecGPa
            + aOverB2 * (goreCoef3 * elGPa + goreCoef4 * glcGPa)
        guard denominatorGPa > 0 else { return nil }

        // Convert denominator GPa → Pa, then compute thickness in mm.
        let denominatorPa = denominatorGPa * 1.0e9
        return numerator / sqrt(denominatorPa) * 1000.0
    }
}

// MARK: - WoodQuality

/// A subjective quality rating for a tonewood sample based on its specific modulus.
///
/// Thresholds are calibrated against published ranges for instrument-grade tonewoods
/// (Gore & Gilet 2011/2016; Brémaud 2012; Wegst 2006).
/// The grading scales differ by wood species (spruce vs cedar) and measurement direction
/// (longitudinal vs cross-grain) because the physical ranges are very different.
/// Full citations in *Documentation/tonewood-references.md*.
enum WoodQuality: String, CaseIterable {

    /// Exceptional instrument-grade material; master-grade or AAA classification.
    case excellent = "Excellent"

    /// High-quality material; AAA–AA classification.
    case veryGood = "Very Good"

    /// Good general-purpose instrument material; AA–A classification.
    case good = "Good"

    /// Below-average; usable but not ideal for fine instruments.
    case fair = "Fair"

    /// Poor; not recommended for fine instrument use.
    case poor = "Poor"

    /// Numeric score (1–5) for arithmetic quality averaging.
    ///
    /// Used internally by ``PlateProperties/overallQuality`` to blend longitudinal and
    /// cross-grain ratings into a single overall score.
    var numericScore: Float {
        switch self {
        case .excellent: return 5
        case .veryGood:  return 4
        case .good:      return 3
        case .fair:      return 2
        case .poor:      return 1
        }
    }

    /// Display colour for quality labels and PDF report cells.
    ///
    /// Single source of truth — both the UI (`TapAnalysisResultsView`) and the PDF
    /// renderer (`PDFReportGenerator`) use this property so the two are always in sync.
    var color: Color {
        switch self {
        case .excellent: return .green
        case .veryGood:  return .mint
        case .good:      return .blue
        case .fair:      return .orange
        case .poor:      return .red
        }
    }

    // MARK: - Supporting Enums

    /// The grain direction in which a measurement was taken.
    enum Direction {
        /// Along the grain (parallel to the wood fibres).
        case longitudinal
        /// Across the grain (perpendicular to the wood fibres).
        case cross
    }

    /// The species of wood being evaluated, used to select the appropriate grading thresholds.
    enum WoodType {
        case spruce
        case cedar
        case maple
        case rosewood
    }

    // MARK: - Evaluation

    /// Evaluates the quality of a wood sample from its specific modulus value.
    ///
    /// Thresholds are based on published instrument-grade quality ranges.
    ///
    /// **Source:** Gore, T. & Gilet, G., *Contemporary Acoustic Guitar Design and Build*,
    /// 2nd ed. (2016), Vol. 1 (ISBN: 978-0-9871174-2-7).  See also Brémaud (2012) and
    /// Wegst (2006) for corroborating species data.  Full citations in
    /// *Documentation/tonewood-references.md*.
    ///
    /// | Species | Direction | Excellent | Very Good | Good | Fair | Poor |
    /// |---------|-----------|-----------|-----------|------|------|------|
    /// | Spruce  | Long.     | ≥ 25      | ≥ 22      | ≥ 19 | ≥ 16 | < 16 |
    /// | Spruce  | Cross     | ≥ 1.5     | ≥ 1.2     | ≥ 0.9 | ≥ 0.6 | < 0.6 |
    /// | Cedar   | Long.     | ≥ 22      | ≥ 19      | ≥ 16 | ≥ 13 | < 13 |
    /// | Cedar   | Cross     | ≥ 1.3     | ≥ 1.0     | ≥ 0.7 | ≥ 0.5 | < 0.5 |
    /// | Others  | —         | ≥ 20      | ≥ 16      | ≥ 12 | ≥ 8  | < 8  |
    ///
    /// All specific-modulus values are in GPa/(g/cm³).
    ///
    /// - Parameters:
    ///   - specificModulus: Measured specific modulus in GPa/(g/cm³).
    ///   - direction: Whether this is a longitudinal or cross-grain measurement.
    ///   - woodType: Species of wood being graded.
    /// - Returns: The appropriate ``WoodQuality`` rating.
    static func evaluate(specificModulus: Float, direction: Direction, woodType: WoodType) -> WoodQuality {
        switch (woodType, direction) {
        case (.spruce, .longitudinal):
            // Typical instrument-grade spruce E_L/ρ: 15–30 GPa/(g/cm³)
            // Master grade ≥ 25, AAA ≥ 22, AA ≥ 19, A ≥ 16, below-grade < 16
            if specificModulus >= 25 { return .excellent }
            if specificModulus >= 22 { return .veryGood  }
            if specificModulus >= 19 { return .good      }
            if specificModulus >= 16 { return .fair      }
            return .poor

        case (.spruce, .cross):
            // Cross-grain specific modulus is much lower: 0.5–2.0 GPa/(g/cm³)
            if specificModulus >= 1.5 { return .excellent }
            if specificModulus >= 1.2 { return .veryGood  }
            if specificModulus >= 0.9 { return .good      }
            if specificModulus >= 0.6 { return .fair      }
            return .poor

        case (.cedar, .longitudinal):
            // Cedar is inherently less stiff than spruce; thresholds shifted down ~3 points
            if specificModulus >= 22 { return .excellent }
            if specificModulus >= 19 { return .veryGood  }
            if specificModulus >= 16 { return .good      }
            if specificModulus >= 13 { return .fair      }
            return .poor

        case (.cedar, .cross):
            if specificModulus >= 1.3 { return .excellent }
            if specificModulus >= 1.0 { return .veryGood  }
            if specificModulus >= 0.7 { return .good      }
            if specificModulus >= 0.5 { return .fair      }
            return .poor

        default:
            // Generic thresholds for maple, rosewood, and other species not individually calibrated
            if specificModulus >= 20 { return .excellent }
            if specificModulus >= 16 { return .veryGood  }
            if specificModulus >= 12 { return .good      }
            if specificModulus >= 8  { return .fair      }
            return .poor
        }
    }
}

// MARK: - BraceProperties

/// Acoustic properties of a rectangular brace strip calculated from a single longitudinal tap.
///
/// Braces are analysed using only the along-grain (longitudinal) fundamental frequency
/// because only the along-grain stiffness and speed of sound matter for their structural
/// and acoustic function in the instrument.  The cross-grain and FLC taps that are
/// required for plate analysis are not needed here.
///
/// The formula used is the same Euler–Bernoulli free-free beam equation as
/// ``PlateProperties/youngsModulusLong``, but with the coefficient `22.37332` (more precise).
///
/// - SeeAlso: ``PlateProperties`` for the full two-/three-tap plate analysis.
struct BraceProperties {

    /// Dimensions and mass of the brace sample.
    let dimensions: MaterialDimensions

    /// Fundamental bending frequency from the longitudinal tap, in Hz.
    ///
    /// The brace is suspended at its nodal points (22% from each end along its length)
    /// and tapped at the centre.
    let fundamentalFrequencyLong: Float

    // MARK: - Calculated Properties

    /// Young's modulus along the grain (E_L) in Pascals.
    ///
    /// Formula: `E = 48 × π² × ρ × fL² × L⁴ / (22.37332 × t)²`
    ///
    /// Uses the more precise `βL` coefficient `22.37332` compared to the plate's rounded `22.37`.
    ///
    /// Returns 0 when thickness or density is zero.
    var youngsModulusLong: Float {
        let t = dimensions.thickness
        guard t > 0, dimensions.density > 0 else { return 0 }
        return 48 * .pi * .pi * dimensions.density
            * fundamentalFrequencyLong * fundamentalFrequencyLong
            * pow(dimensions.length, 4)
            / pow(22.37332 * t, 2)
    }

    /// Speed of sound along the grain in m/s.
    ///
    /// Formula: `c = √(E_L / ρ)`.  Typical guitar-brace spruce: 4 500–5 500 m/s.
    var speedOfSoundLong: Float {
        guard dimensions.density > 0 else { return 0 }
        return sqrt(youngsModulusLong / dimensions.density)
    }

    /// Young's modulus along the grain in GPa.
    var youngsModulusLongGPa: Float { youngsModulusLong / 1e9 }

    /// Specific modulus (stiffness-to-weight ratio) along the grain, in GPa/(g/cm³).
    ///
    /// The primary quality indicator for braces.  Excellent spruce braces: ≥ 25.
    var specificModulusLong: Float {
        guard dimensions.densityGPerCm3 > 0 else { return 0 }
        return youngsModulusLongGPa / dimensions.densityGPerCm3
    }

    /// Sound radiation coefficient along the grain: `R = c_L / ρ`.
    var radiationRatioLong: Float {
        guard dimensions.density > 0 else { return 0 }
        return speedOfSoundLong / dimensions.density
    }

    /// Quality rating based on the longitudinal specific modulus, using spruce thresholds.
    ///
    /// - SeeAlso: ``WoodQuality/evaluate(specificModulus:direction:woodType:)``
    var spruceQuality: WoodQuality {
        WoodQuality.evaluate(specificModulus: specificModulusLong, direction: .longitudinal, woodType: .spruce)
    }
}

// MARK: - TonewoodReference

/// Published reference values for common guitar tonewoods.
///
/// These typical values can be used to contextualise measurements from tap tests, or as
/// starting points when a reference sample is not available.  Values are approximate averages
/// consistent with: Haines et al. (1977), Brémaud (2012), Wegst (2006), and Bucur (2006).
/// Full citations in *Documentation/tonewood-references.md*.
struct TonewoodReference {

    /// Typical acoustic properties of Sitka Spruce, the most common guitar-top wood.
    static let sitkaSpruceTypical = (
        density: Float(0.40),            // g/cm³
        speedOfSoundLong: Float(5500),   // m/s
        specificModulusLong: Float(22),  // GPa/(g/cm³)
        radiationRatio: Float(12)        // m⁴/(kg·s)
    )

    /// Typical acoustic properties of Engelmann Spruce.
    static let engelmannSpruceTypical = (
        density: Float(0.38),
        speedOfSoundLong: Float(5300),
        specificModulusLong: Float(21),
        radiationRatio: Float(12.5)
    )

    /// Typical acoustic properties of European (German) Spruce, often considered premium.
    static let europeanSpruceTypical = (
        density: Float(0.42),
        speedOfSoundLong: Float(5800),
        specificModulusLong: Float(24),
        radiationRatio: Float(13)
    )

    /// Typical acoustic properties of Western Red Cedar.
    static let westernRedCedarTypical = (
        density: Float(0.35),
        speedOfSoundLong: Float(4800),
        specificModulusLong: Float(18),
        radiationRatio: Float(11)
    )
}
