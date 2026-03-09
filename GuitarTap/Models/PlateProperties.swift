//
//  PlateProperties.swift
//  GuitarTap
//
//  Calculates acoustic properties of wood from tap test measurements on rectangular plates.
//  Used for evaluating tonewood quality for guitar tops, backs, and other instrument parts.
//

import Foundation

/// Represents the physical dimensions of a rectangular material sample
struct MaterialDimensions {
    /// Length in meters (along grain for wood)
    let length: Float
    /// Width in meters (cross grain for wood)
    let width: Float
    /// Thickness in meters
    let thickness: Float
    /// Mass in kilograms
    let mass: Float
    
    /// Initialize from millimeters and grams (more convenient units)
    init(lengthMM: Float, widthMM: Float, thicknessMM: Float, massGrams: Float) {
        self.length = lengthMM / 1000.0
        self.width = widthMM / 1000.0
        self.thickness = thicknessMM / 1000.0
        self.mass = massGrams / 1000.0
    }
    
    /// Initialize from SI units (meters and kilograms)
    init(length: Float, width: Float, thickness: Float, mass: Float) {
        self.length = length
        self.width = width
        self.thickness = thickness
        self.mass = mass
    }
    
    /// Volume in cubic meters
    var volume: Float {
        length * width * thickness
    }
    
    /// Density in kg/m³
    var density: Float {
        guard volume > 0 else { return 0 }
        return mass / volume
    }
    
    /// Density in g/cm³ (common unit for wood)
    var densityGPerCm3: Float {
        density / 1000.0
    }
}

/// Calculated acoustic properties of a material
struct PlateProperties {
    /// The dimensions used for calculation
    let dimensions: MaterialDimensions

    /// Fundamental frequency along the length (longitudinal mode) in Hz
    let fundamentalFrequencyLong: Float

    /// Fundamental frequency along the width (cross mode) in Hz
    let fundamentalFrequencyCross: Float

    /// Fundamental frequency from the FLC (diagonal/torsional) tap in Hz, optional
    let fundamentalFrequencyFlc: Float?

    init(dimensions: MaterialDimensions,
         fundamentalFrequencyLong: Float,
         fundamentalFrequencyCross: Float,
         fundamentalFrequencyFlc: Float? = nil) {
        self.dimensions = dimensions
        self.fundamentalFrequencyLong = fundamentalFrequencyLong
        self.fundamentalFrequencyCross = fundamentalFrequencyCross
        self.fundamentalFrequencyFlc = fundamentalFrequencyFlc
    }

    // MARK: - Calculated Properties
    
    /// Young's modulus along grain (E_long) in Pa
    /// Formula: E = 48π²ρf²L⁴ / (22.37t)²
    /// Derived from the first bending mode of a free-free beam (tap tone method).
    /// The 22.37 constant is (βL)² for the first free-free beam mode.
    var youngsModulusLong: Float {
        let t = dimensions.thickness
        guard t > 0, dimensions.density > 0 else { return 0 }
        return 48 * .pi * .pi * dimensions.density
            * fundamentalFrequencyLong * fundamentalFrequencyLong
            * pow(dimensions.length, 4)
            / pow(22.37 * t, 2)
    }
    
    /// Young's modulus across grain (E_cross) in Pa
    /// Uses width as the effective beam length for the cross-grain bending test.
    var youngsModulusCross: Float {
        let t = dimensions.thickness
        guard t > 0, dimensions.density > 0 else { return 0 }
        return 48 * .pi * .pi * dimensions.density
            * fundamentalFrequencyCross * fundamentalFrequencyCross
            * pow(dimensions.width, 4)
            / pow(22.37 * t, 2)
    }
    
    /// Speed of sound along grain (longitudinal) in m/s
    /// Derived from E_L: c = √(E/ρ)
    var speedOfSoundLong: Float {
        guard dimensions.density > 0 else { return 0 }
        return sqrt(youngsModulusLong / dimensions.density)
    }
    
    /// Speed of sound across grain in m/s
    var speedOfSoundCross: Float {
        guard dimensions.density > 0 else { return 0 }
        return sqrt(youngsModulusCross / dimensions.density)
    }
    
    /// Young's modulus along grain in GPa
    var youngsModulusLongGPa: Float {
        youngsModulusLong / 1e9
    }
    
    /// Young's modulus across grain in GPa
    var youngsModulusCrossGPa: Float {
        youngsModulusCross / 1e9
    }
    
    /// Specific modulus (stiffness-to-weight ratio) along grain in GPa/(g/cm³)
    /// This is one of the most important metrics for tonewood
    /// Higher values = wood vibrates more freely
    var specificModulusLong: Float {
        guard dimensions.densityGPerCm3 > 0 else { return 0 }
        return youngsModulusLongGPa / dimensions.densityGPerCm3
    }
    
    /// Specific modulus across grain in GPa/(g/cm³)
    var specificModulusCross: Float {
        guard dimensions.densityGPerCm3 > 0 else { return 0 }
        return youngsModulusCrossGPa / dimensions.densityGPerCm3
    }
    
    /// Radiation ratio (sound radiation coefficient) along grain
    /// Formula: R = c_L / ρ = √(E/ρ) / ρ
    /// Higher values = more efficient sound production
    var radiationRatioLong: Float {
        guard dimensions.density > 0 else { return 0 }
        return speedOfSoundLong / dimensions.density
    }
    
    /// Radiation ratio across grain
    var radiationRatioCross: Float {
        guard dimensions.density > 0 else { return 0 }
        return speedOfSoundCross / dimensions.density
    }
    
    /// Cross-grain to long-grain stiffness ratio
    /// Typical values for spruce: 0.04-0.08
    var crossLongRatio: Float {
        guard youngsModulusLong > 0 else { return 0 }
        return youngsModulusCross / youngsModulusLong
    }

    /// Long-grain to cross-grain stiffness ratio (inverse of crossLongRatio)
    /// Typical values for spruce: 12-25
    var longCrossRatio: Float {
        guard youngsModulusCross > 0 else { return 0 }
        return youngsModulusLong / youngsModulusCross
    }
    
    // MARK: - Quality Assessment
    
    /// Evaluates the quality of spruce based on specific modulus
    var spruceQualityLong: WoodQuality {
        WoodQuality.evaluate(specificModulus: specificModulusLong, direction: .longitudinal, woodType: .spruce)
    }
    
    /// Evaluates the quality of spruce based on cross-grain specific modulus
    var spruceQualityCross: WoodQuality {
        WoodQuality.evaluate(specificModulus: specificModulusCross, direction: .cross, woodType: .spruce)
    }
    
    /// Evaluates the overall suitability for guitar tops
    var overallQuality: WoodQuality {
        // Weight longitudinal more heavily (it's more important for tops)
        let longScore = spruceQualityLong.numericScore * 0.7
        let crossScore = spruceQualityCross.numericScore * 0.3
        let combined = longScore + crossScore

        if combined >= 4.5 { return .excellent }
        if combined >= 3.5 { return .veryGood }
        if combined >= 2.5 { return .good }
        if combined >= 1.5 { return .fair }
        return .poor
    }

    // MARK: - Gore Plate Thicknessing (Eq. 4.5-7)

    /// Poisson's ratio ν_CL — Gore's suggested average for softwoods
    private static let vcl: Float = 0.05

    /// Product ν_LC × ν_CL — Gore's suggested average
    private static let vlcVcl: Float = 0.02

    /// Gore coefficient 1: (1/((π/2)² × (3/2)⁴)) × 12 × (1 − ν_LC·ν_CL)
    /// Used for EL and EC calculation from tap frequencies.
    private var goreCoef1: Float {
        let term = pow(Float.pi / 2.0, 2.0) * pow(1.5, 4.0)
        return (1.0 / term) * 12.0 * (1.0 - PlateProperties.vlcVcl)
    }

    /// Gore coefficient 2: π × √(12 × (1 − ν_LC·ν_CL) / 126)
    /// Used in the target thickness numerator.
    private var goreCoef2: Float {
        return Float.pi * sqrt(12.0 * (1.0 - PlateProperties.vlcVcl) / 126.0)
    }

    /// Gore coefficient 3: 4 × ν_CL / 7
    /// Poisson correction for the EL term in the denominator.
    private var goreCoef3: Float {
        return 4.0 * PlateProperties.vcl / 7.0
    }

    /// Gore coefficient 4: 4 × 12 × (1 − ν_LC·ν_CL) / 42
    /// Shear term scaling in the denominator.
    private var goreCoef4: Float {
        return 4.0 * 12.0 * (1.0 - PlateProperties.vlcVcl) / 42.0
    }

    /// Young's modulus along grain using Gore's plate formula (Pa)
    /// Formula: EL = Coef_1 × ρ × l⁴ × fL² / t²
    var goreYoungsModulusLong: Float {
        let t = dimensions.thickness
        guard t > 0, dimensions.density > 0 else { return 0 }
        return goreCoef1 * dimensions.density
            * pow(dimensions.length, 4.0)
            * fundamentalFrequencyLong * fundamentalFrequencyLong
            / (t * t)
    }

    /// Young's modulus across grain using Gore's plate formula (Pa)
    /// Formula: EC = Coef_1 × ρ × w⁴ × fC² / t²
    var goreYoungsModulusCross: Float {
        let t = dimensions.thickness
        guard t > 0, dimensions.density > 0 else { return 0 }
        return goreCoef1 * dimensions.density
            * pow(dimensions.width, 4.0)
            * fundamentalFrequencyCross * fundamentalFrequencyCross
            / (t * t)
    }

    /// Shear modulus GLC using Gore's formula (Pa), nil if FLC frequency unavailable
    /// Formula: GLC = (12/π²) × ρ × l² × w² × fLC² / t²
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

    /// Gore target plate thickness in mm for a finished guitar body.
    ///
    /// Implements Gore Equation 4.5-7. Uses EL, EC, and GLC derived from the
    /// test-plate tap tones to calculate the optimal thickness for the actual
    /// guitar plate given the body geometry and desired vibrational stiffness.
    /// When the FLC tap has not been performed, GLC is treated as 0, which
    /// slightly over-estimates the target thickness (typically by ~5–7%).
    ///
    /// - Parameters:
    ///   - bodyLengthMm: Guitar body length (neck join to tail) in mm
    ///   - bodyWidthMm: Guitar lower bout width in mm
    ///   - vibrationalStiffness: Target f_vs (75 = steel string top, 55 = SS back, 50 = classical)
    /// - Returns: Target thickness in mm, or nil only if required inputs are missing/invalid
    func goreTargetThickness(bodyLengthMm: Float, bodyWidthMm: Float, vibrationalStiffness: Float) -> Float? {
        guard bodyLengthMm > 0, bodyWidthMm > 0, vibrationalStiffness > 0 else { return nil }
        guard dimensions.density > 0 else { return nil }

        let a = bodyLengthMm / 1000.0   // body length in metres
        let b = bodyWidthMm / 1000.0    // lower bout width in metres
        let rho = dimensions.density     // kg/m³

        // Moduli in GPa (denominator calculation uses GPa, then × 10⁹ → Pa)
        let elGPa  = goreYoungsModulusLong  / 1.0e9
        let ecGPa  = goreYoungsModulusCross / 1.0e9
        // Use measured GLC if available; fall back to 0 when FLC tap not performed
        let glcGPa = (goreShearModulus ?? 0) / 1.0e9

        // Numerator: Coef_2 × f_vs × a² × √ρ
        let numerator = goreCoef2 * vibrationalStiffness * a * a * sqrt(rho)

        // Denominator (GPa): EL + (a/b)⁴·EC + (a/b)²·(Coef_3·EL + Coef_4·GLC)
        let aOverB  = a / b
        let aOverB2 = aOverB * aOverB
        let aOverB4 = aOverB2 * aOverB2
        let denominatorGPa = elGPa
            + aOverB4 * ecGPa
            + aOverB2 * (goreCoef3 * elGPa + goreCoef4 * glcGPa)
        guard denominatorGPa > 0 else { return nil }

        // Convert denominator to Pa, compute thickness in mm
        let denominatorPa = denominatorGPa * 1.0e9
        return numerator / sqrt(denominatorPa) * 1000.0
    }
}

/// Wood quality rating based on acoustic properties
enum WoodQuality: String, CaseIterable {
    case excellent = "Excellent"
    case veryGood = "Very Good"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    
    var numericScore: Float {
        switch self {
        case .excellent: return 5
        case .veryGood: return 4
        case .good: return 3
        case .fair: return 2
        case .poor: return 1
        }
    }
    
    /// Direction of measurement
    enum Direction {
        case longitudinal  // Along grain
        case cross         // Across grain
    }
    
    /// Type of wood being evaluated
    enum WoodType {
        case spruce
        case cedar
        case maple
        case rosewood
    }
    
    /// Evaluate wood quality based on specific modulus
    static func evaluate(specificModulus: Float, direction: Direction, woodType: WoodType) -> WoodQuality {
        switch (woodType, direction) {
        case (.spruce, .longitudinal):
            // Typical ranges for spruce E/ρ longitudinal: 15-30 GPa/(g/cm³)
            // Master grade: > 25, AAA: 22-25, AA: 19-22, A: 16-19, Below: < 16
            if specificModulus >= 25 { return .excellent }
            if specificModulus >= 22 { return .veryGood }
            if specificModulus >= 19 { return .good }
            if specificModulus >= 16 { return .fair }
            return .poor
            
        case (.spruce, .cross):
            // Cross-grain specific modulus is much lower: 0.5-2.0 GPa/(g/cm³)
            if specificModulus >= 1.5 { return .excellent }
            if specificModulus >= 1.2 { return .veryGood }
            if specificModulus >= 0.9 { return .good }
            if specificModulus >= 0.6 { return .fair }
            return .poor
            
        case (.cedar, .longitudinal):
            // Cedar is typically slightly less stiff than spruce
            if specificModulus >= 22 { return .excellent }
            if specificModulus >= 19 { return .veryGood }
            if specificModulus >= 16 { return .good }
            if specificModulus >= 13 { return .fair }
            return .poor
            
        case (.cedar, .cross):
            if specificModulus >= 1.3 { return .excellent }
            if specificModulus >= 1.0 { return .veryGood }
            if specificModulus >= 0.7 { return .good }
            if specificModulus >= 0.5 { return .fair }
            return .poor
            
        default:
            // Generic evaluation for other woods
            if specificModulus >= 20 { return .excellent }
            if specificModulus >= 16 { return .veryGood }
            if specificModulus >= 12 { return .good }
            if specificModulus >= 8 { return .fair }
            return .poor
        }
    }
}

// MARK: - Brace Properties

/// Calculated acoustic properties of a brace strip using only the longitudinal (fL) tap
struct BraceProperties {
    /// The dimensions used for calculation
    let dimensions: MaterialDimensions
    
    /// Fundamental frequency along the length (longitudinal mode) in Hz
    let fundamentalFrequencyLong: Float
    
    // MARK: - Calculated Properties
    
    /// Young's modulus along grain (EL) in Pa
    /// Formula: E = 48π²ρf²L⁴ / (22.37332t)²
    /// Derived from the first bending mode of a free-free beam (tap tone method).
    var youngsModulusLong: Float {
        let t = dimensions.thickness
        guard t > 0, dimensions.density > 0 else { return 0 }
        return 48 * .pi * .pi * dimensions.density
            * fundamentalFrequencyLong * fundamentalFrequencyLong
            * pow(dimensions.length, 4)
            / pow(22.37332 * t, 2)
    }
    
    /// Speed of sound along grain in m/s
    /// Derived from E_L: c = √(E/ρ)
    var speedOfSoundLong: Float {
        guard dimensions.density > 0 else { return 0 }
        return sqrt(youngsModulusLong / dimensions.density)
    }
    
    /// Young's modulus along grain in GPa
    var youngsModulusLongGPa: Float {
        youngsModulusLong / 1e9
    }
    
    /// Specific modulus (stiffness-to-weight ratio) along grain in GPa/(g/cm³)
    var specificModulusLong: Float {
        guard dimensions.densityGPerCm3 > 0 else { return 0 }
        return youngsModulusLongGPa / dimensions.densityGPerCm3
    }
    
    /// Radiation ratio along grain: R = c_L / ρ = √(E/ρ) / ρ
    var radiationRatioLong: Float {
        guard dimensions.density > 0 else { return 0 }
        return speedOfSoundLong / dimensions.density
    }
    
    /// Quality assessment based on longitudinal specific modulus
    var spruceQuality: WoodQuality {
        WoodQuality.evaluate(specificModulus: specificModulusLong, direction: .longitudinal, woodType: .spruce)
    }
}

// MARK: - Typical Values Reference

/// Reference values for common tonewoods
struct TonewoodReference {
    /// Typical values for Sitka Spruce (guitar tops)
    static let sitkaSpruceTypical = (
        density: Float(0.40),           // g/cm³
        speedOfSoundLong: Float(5500),  // m/s
        specificModulusLong: Float(22), // GPa/(g/cm³)
        radiationRatio: Float(12)       // m⁴/(kg·s)
    )
    
    /// Typical values for Engelmann Spruce
    static let engelmannSpruceTypical = (
        density: Float(0.38),
        speedOfSoundLong: Float(5300),
        specificModulusLong: Float(21),
        radiationRatio: Float(12.5)
    )
    
    /// Typical values for European Spruce (often considered premium)
    static let europeanSpruceTypical = (
        density: Float(0.42),
        speedOfSoundLong: Float(5800),
        specificModulusLong: Float(24),
        radiationRatio: Float(13)
    )
    
    /// Typical values for Western Red Cedar
    static let westernRedCedarTypical = (
        density: Float(0.35),
        speedOfSoundLong: Float(4800),
        specificModulusLong: Float(18),
        radiationRatio: Float(11)
    )
}
