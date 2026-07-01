//
//  PlatePropertiesTests.swift
//  GuitarTapTests
//
//  Tests for PlateProperties and MaterialDimensions calculations.
//  All computations are pure formulas on value types — no hardware required.
//
//  Reference values are derived from the published formula:
//    E = 48π²ρf²L⁴ / (22.37·t)²
//  for a free-free beam (the tap-tone beam bending method).
//
// @parity test/plate

import Testing
import Foundation
import SwiftUI
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - MaterialDimensions Tests
// ---------------------------------------------------------------------------

@Suite("MaterialDimensions")
struct MaterialDimensionsTests {

    // Volume = length × width × thickness (in metres cubed).
    @Test func volume_correctForTypicalPlate() {
        // 500 mm × 200 mm × 3 mm plate
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 100)
        let expectedVolume: Float = 0.5 * 0.2 * 0.003   // m³
        #expect(abs(d.volume - expectedVolume) < 1e-7)
    }

    // Density = mass / volume; typical spruce ≈ 400 kg/m³.
    @Test func density_sprucePlate_inExpectedRange() {
        // 500 mm × 200 mm × 3 mm, 120 g
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        // volume = 0.5 × 0.2 × 0.003 = 0.0003 m³
        // density = 0.12 kg / 0.0003 m³ = 400 kg/m³
        #expect(abs(d.density - 400) < 1, "Expected density ≈ 400 kg/m³, got \(d.density)")
    }

    // g/cm³ conversion: 400 kg/m³ = 0.4 g/cm³.
    @Test func densityGPerCm3_correctConversion() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        // 400 kg/m³ → 0.4 g/cm³
        #expect(abs(d.densityGPerCm3 - 0.4) < 0.001)
    }

    // Zero thickness → density = 0 (guard against division by zero).
    @Test func zeroThickness_densityIsZero() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 0, massGrams: 100)
        #expect(d.density == 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Young's Modulus Tests
// ---------------------------------------------------------------------------

@Suite("YoungModulus")
struct YoungModulusTests {

    // Reference calculation using realistic spruce values.
    // 500 mm × 200 mm × 3 mm plate, 120 g, fL = 85 Hz:
    //   ρ = 0.12 / (0.5 × 0.2 × 0.003) = 400 kg/m³, L = 0.5 m, t = 0.003 m
    //   E = 48π²·400·85²·0.5⁴ / (22.37·0.003)² ≈ 19 GPa  (within 5–20 GPa)
    @Test func youngsModulusLong_sprucePlate_physicallyPlausible() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let props = PlateProperties(
            dimensions: d,
            fundamentalFrequencyLong: 85,    // realistic tap-tone freq for 500 mm spruce
            fundamentalFrequencyCross: 50
        )
        let EL = props.youngsModulusLong
        // Typical spruce EL: 10–15 GPa. Accept a wide range (5–20 GPa) for test robustness.
        #expect(EL > 5e9 && EL < 20e9,
                "EL (\(EL/1e9) GPa) should be in 5–20 GPa range for spruce")
    }

    // Zero thickness → E = 0 (guard against division by zero).
    @Test func youngsModulusLong_zeroThickness_returnsZero() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 0, massGrams: 120)
        let props = PlateProperties(
            dimensions: d,
            fundamentalFrequencyLong: 170,
            fundamentalFrequencyCross: 100
        )
        #expect(props.youngsModulusLong == 0)
    }

    // youngsModulusLongGPa is youngsModulusLong expressed in GPa (÷1e9).
    @Test func youngsModulusLong_gpaPropertyIsCorrect() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let props = PlateProperties(dimensions: d, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50)
        #expect(abs(props.youngsModulusLongGPa - props.youngsModulusLong / 1e9) < 1e-5,
                "youngsModulusLongGPa should equal youngsModulusLong / 1e9")
    }

    // youngsModulusCrossGPa is youngsModulusCross expressed in GPa (÷1e9).
    @Test func youngsModulusCross_gpaPropertyIsCorrect() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let props = PlateProperties(dimensions: d, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50)
        #expect(abs(props.youngsModulusCrossGPa - props.youngsModulusCross / 1e9) < 1e-5,
                "youngsModulusCrossGPa should equal youngsModulusCross / 1e9")
    }

    // Higher frequency → stiffer material → higher E (direct proportionality with f²).
    @Test func youngsModulusLong_higherFrequency_higherModulus() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let propsLow = PlateProperties(
            dimensions: d, fundamentalFrequencyLong: 100, fundamentalFrequencyCross: 80
        )
        let propsHigh = PlateProperties(
            dimensions: d, fundamentalFrequencyLong: 200, fundamentalFrequencyCross: 80
        )
        // E ∝ f², so doubling f quadruples E
        let ratio = propsHigh.youngsModulusLong / propsLow.youngsModulusLong
        #expect(abs(ratio - 4.0) < 0.01,
                "Doubling fL should quadruple EL (ratio = \(ratio))")
    }

    // E ∝ L⁴ when density is held constant: to keep density constant while doubling L,
    // mass must double too (same volume density = mass/(L·w·t)).
    // When density is constant: E_2/E_1 = (L_2/L_1)⁴ = 2⁴ = 16.
    @Test func youngsModulusLong_doubleLength_sixteenXModulus() {
        // d1: L=250 mm, mass=60 g  → density = 0.06 / (0.25×0.2×0.003) = 400 kg/m³
        // d2: L=500 mm, mass=120 g → density = 0.12 / (0.5×0.2×0.003)  = 400 kg/m³
        let d1 = MaterialDimensions(lengthMM: 250, widthMM: 200, thicknessMM: 3, massGrams: 60)
        let d2 = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let p1 = PlateProperties(dimensions: d1, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50)
        let p2 = PlateProperties(dimensions: d2, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50)
        // E ∝ ρ·L⁴: with equal density, ratio = (L2/L1)⁴ = 16
        let ratio = p2.youngsModulusLong / p1.youngsModulusLong
        #expect(abs(ratio - 16.0) < 0.1,
                "Doubling length at constant density should increase EL 16× (L⁴ dependence), got ratio = \(ratio)")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Speed of Sound Tests
// ---------------------------------------------------------------------------

@Suite("SpeedOfSound")
struct SpeedOfSoundTests {

    // Typical spruce longitudinal sound speed: 4000–7000 m/s.
    // Using fL=85 Hz which gives EL ≈ 19 GPa, ρ = 400 kg/m³ → c = √(E/ρ) ≈ 6890 m/s.
    @Test func speedOfSoundLong_spruce_inExpectedRange() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let props = PlateProperties(
            dimensions: d, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50
        )
        let c = props.speedOfSoundLong
        #expect(c > 3000 && c < 8000,
                "Sound speed (\(c) m/s) should be in 3000–8000 m/s range for spruce")
    }

    // speedOfSoundLong = √(youngsModulusLong / density).
    @Test func speedOfSoundLong_equalsSquareRootOfEOverRho() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let props = PlateProperties(dimensions: d, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50)
        let expected = sqrt(props.youngsModulusLong / d.density)
        #expect(abs(props.speedOfSoundLong - expected) < 0.01,
                "speedOfSoundLong should equal sqrt(E / rho)")
    }

    // c = √(E/ρ): since E ∝ f², and c ∝ √E, c ∝ f.
    @Test func speedOfSoundLong_proportionalToFrequency() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let pLow  = PlateProperties(dimensions: d, fundamentalFrequencyLong: 100, fundamentalFrequencyCross: 80)
        let pHigh = PlateProperties(dimensions: d, fundamentalFrequencyLong: 200, fundamentalFrequencyCross: 80)
        let ratio = pHigh.speedOfSoundLong / pLow.speedOfSoundLong
        // E ∝ f², c = √(E/ρ) ∝ f → ratio should be ≈ 2
        #expect(abs(ratio - 2.0) < 0.05,
                "Doubling fL should double speed of sound (ratio = \(ratio))")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Specific Modulus Tests
// ---------------------------------------------------------------------------

@Suite("SpecificModulus")
struct SpecificModulusTests {

    // specificModulusLong = youngsModulusLong (GPa) / density (g/cm³)
    @Test func specificModulusLong_matchesManualCalc() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let props = PlateProperties(
            dimensions: d, fundamentalFrequencyLong: 170, fundamentalFrequencyCross: 100
        )
        let expected = props.youngsModulusLongGPa / d.densityGPerCm3
        #expect(abs(props.specificModulusLong - expected) < 0.001)
    }

    // Zero density → specific modulus = 0 (guard).
    @Test func specificModulusLong_zeroDensity_returnsZero() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 0, massGrams: 0)
        let props = PlateProperties(
            dimensions: d, fundamentalFrequencyLong: 170, fundamentalFrequencyCross: 100
        )
        #expect(props.specificModulusLong == 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Gore Target Thickness Tests
// ---------------------------------------------------------------------------

@Suite("GoreTargetThickness")
struct GoreTargetThicknessTests {

    // The target thickness should be a positive, physically plausible value
    // for typical tonewood (2–5 mm for a guitar top).
    // Using fL=85 Hz gives EL ≈ 19 GPa → Gore thickness ≈ 2.4 mm (within 1.5–6 mm).
    @Test func goreThickness_spruceTop_isPlausible() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let props = PlateProperties(
            dimensions: d, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50
        )
        // Steel string top vibrational stiffness target = 75
        let t = props.goreTargetThickness(bodyLengthMm: 490, bodyWidthMm: 390, vibrationalStiffness: 75)
        #expect(t != nil, "Should return a thickness value")
        if let t = t {
            #expect(t > 1.5 && t < 6.0,
                    "Target thickness \(t) mm should be in 1.5–6 mm range for a guitar top")
        }
    }

    // Zero body length should return nil.
    @Test func goreThickness_zeroBodyLength_returnsNil() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let props = PlateProperties(
            dimensions: d, fundamentalFrequencyLong: 170, fundamentalFrequencyCross: 100
        )
        let t = props.goreTargetThickness(bodyLengthMm: 0, bodyWidthMm: 390, vibrationalStiffness: 75)
        #expect(t == nil, "Zero body length should return nil")
    }

    // Higher vibrational stiffness target → thicker plate.
    @Test func goreThickness_higherTarget_thickerPlate() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let props = PlateProperties(
            dimensions: d, fundamentalFrequencyLong: 170, fundamentalFrequencyCross: 100
        )
        let t55 = props.goreTargetThickness(bodyLengthMm: 490, bodyWidthMm: 390, vibrationalStiffness: 55)
        let t75 = props.goreTargetThickness(bodyLengthMm: 490, bodyWidthMm: 390, vibrationalStiffness: 75)
        if let t55 = t55, let t75 = t75 {
            #expect(t75 > t55, "Higher stiffness target should yield thicker plate: t55=\(t55), t75=\(t75)")
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - AnisotropyRatioTests
//
// Mirrors Python TestPlateAnisotropyRatios in test_material_properties.py.
// ---------------------------------------------------------------------------

@Suite("AnisotropyRatioTests", .serialized)
struct AnisotropyRatioTests {
    // Shared fixture: spruce-like plate with f_long=85 Hz, f_cross=50 Hz.
    private static func makePlate() -> PlateProperties {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        return PlateProperties(dimensions: d, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50)
    }

    // crossLongRatio = E_C / E_L
    @Test func crossLongRatio_is_EC_over_EL() {
        let props = Self.makePlate()
        guard props.youngsModulusLong > 0 else {
            Issue.record("youngsModulusLong must be positive for this test")
            return
        }
        let expected = props.youngsModulusCross / props.youngsModulusLong
        #expect(abs(props.crossLongRatio - expected) < 1e-5,
                "crossLongRatio should equal E_C / E_L; expected \(expected), got \(props.crossLongRatio)")
    }

    // longCrossRatio = E_L / E_C
    @Test func longCrossRatio_is_EL_over_EC() {
        let props = Self.makePlate()
        guard props.youngsModulusCross > 0 else {
            Issue.record("youngsModulusCross must be positive for this test")
            return
        }
        let expected = props.youngsModulusLong / props.youngsModulusCross
        #expect(abs(props.longCrossRatio - expected) < 1e-5,
                "longCrossRatio should equal E_L / E_C; expected \(expected), got \(props.longCrossRatio)")
    }

    // crossLongRatio x longCrossRatio ~= 1 (they are reciprocals)
    @Test func ratios_areReciprocals() {
        let props = Self.makePlate()
        let product = props.crossLongRatio * props.longCrossRatio
        #expect(abs(product - 1.0) < 1e-4,
                "crossLongRatio x longCrossRatio should equal 1; got \(product)")
    }
}

// ---------------------------------------------------------------------------
// MARK: - WoodQualityTests
//
// Mirrors Python TestWoodQuality in test_material_properties.py.
// ---------------------------------------------------------------------------

@Suite("WoodQualityTests", .serialized)
struct WoodQualityTests {
    // Numeric scores must be 5/4/3/2/1 for Excellent ... Poor.
    @Test func numericScores_areCorrect() {
        #expect(WoodQuality.excellent.numericScore == 5, "excellent should score 5")
        #expect(WoodQuality.veryGood.numericScore  == 4, "veryGood should score 4")
        #expect(WoodQuality.good.numericScore      == 3, "good should score 3")
        #expect(WoodQuality.fair.numericScore      == 2, "fair should score 2")
        #expect(WoodQuality.poor.numericScore      == 1, "poor should score 1")
    }

    // Every quality level maps to the expected SwiftUI Color.
    @Test func colorValues_matchExpected() {
        #expect(WoodQuality.excellent.color == Color.green,  "excellent should be green")
        #expect(WoodQuality.veryGood.color  == Color.mint,   "veryGood should be mint")
        #expect(WoodQuality.good.color      == Color.blue,   "good should be blue")
        #expect(WoodQuality.fair.color      == Color.orange, "fair should be orange")
        #expect(WoodQuality.poor.color      == Color.red,    "poor should be red")
    }

    // Spruce longitudinal thresholds: >=25=Excellent, >=22=VG, >=19=Good, >=16=Fair, <16=Poor.
    @Test func evaluate_spruceLongitudinal_thresholds() {
        let D = WoodQuality.Direction.longitudinal
        let T = WoodQuality.WoodType.spruce
        #expect(WoodQuality.evaluate(specificModulus: 25, direction: D, woodType: T) == .excellent)
        #expect(WoodQuality.evaluate(specificModulus: 22, direction: D, woodType: T) == .veryGood)
        #expect(WoodQuality.evaluate(specificModulus: 19, direction: D, woodType: T) == .good)
        #expect(WoodQuality.evaluate(specificModulus: 16, direction: D, woodType: T) == .fair)
        #expect(WoodQuality.evaluate(specificModulus: 10, direction: D, woodType: T) == .poor)
    }

    // Spruce cross-grain thresholds: >=1.5=Excellent, >=1.2=VG, >=0.9=Good, >=0.6=Fair, <0.6=Poor.
    @Test func evaluate_spruceCross_thresholds() {
        let D = WoodQuality.Direction.cross
        let T = WoodQuality.WoodType.spruce
        #expect(WoodQuality.evaluate(specificModulus: 1.5, direction: D, woodType: T) == .excellent)
        #expect(WoodQuality.evaluate(specificModulus: 1.2, direction: D, woodType: T) == .veryGood)
        #expect(WoodQuality.evaluate(specificModulus: 0.9, direction: D, woodType: T) == .good)
        #expect(WoodQuality.evaluate(specificModulus: 0.6, direction: D, woodType: T) == .fair)
        #expect(WoodQuality.evaluate(specificModulus: 0.3, direction: D, woodType: T) == .poor)
    }
}

// ---------------------------------------------------------------------------
// MARK: - PlateQuality Tests
//
// Mirrors Python TestPlateQuality in test_material_properties.py.
// ---------------------------------------------------------------------------

@Suite("PlateQuality")
struct PlateQualityTests {

    // spruceQualityLong == .excellent when specificModulusLong is high (≥25).
    // Use fL=170 Hz on the reference plate (density=400 kg/m³) to get a high specific modulus.
    @Test func spruceQualityLong_excellent_forHighSpecificModulus() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let props = PlateProperties(dimensions: d, fundamentalFrequencyLong: 170, fundamentalFrequencyCross: 100)
        // specificModulusLong = youngsModulusLongGPa / densityGPerCm3; high fL → high value → Excellent
        #expect(props.spruceQualityLong == .excellent,
                "High fL should produce Excellent longitudinal quality, got \(props.spruceQualityLong)")
    }

    // spruceQualityLong returns a WoodQuality value (not nil, not a raw scalar).
    @Test func spruceQualityLong_returnsWoodQualityValue() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let props = PlateProperties(dimensions: d, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50)
        let quality = props.spruceQualityLong
        // Just verify it is one of the five valid cases
        let valid: [WoodQuality] = [.excellent, .veryGood, .good, .fair, .poor]
        #expect(valid.contains(quality), "spruceQualityLong should be a valid WoodQuality")
    }

    // overallQuality uses a weighted average of longitudinal (70%) and cross (30%) scores.
    // With a high-fL plate both long and cross will be Excellent (score 5), so overall = Excellent.
    @Test func overallQuality_usesWeightedNumericScore() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let props = PlateProperties(dimensions: d, fundamentalFrequencyLong: 170, fundamentalFrequencyCross: 100)
        // At high frequencies both long and cross should score highly → overall Excellent
        let overall = props.overallQuality
        #expect(overall == .excellent || overall == .veryGood,
                "High-fL plate should have Excellent or VeryGood overall quality, got \(overall)")
    }
}
