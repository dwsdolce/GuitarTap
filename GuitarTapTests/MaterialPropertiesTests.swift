//
//  MaterialPropertiesTests.swift
//  GuitarTapTests
//
//  Tests for MaterialProperties and MaterialDimensions calculations.
//  All computations are pure formulas on value types — no hardware required.
//
//  Reference values are derived from the published formula:
//    E = 48π²ρf²L⁴ / (22.37·t)²
//  for a free-free beam (the tap-tone beam bending method).
//

import Testing
import Foundation
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
        let props = MaterialProperties(
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
        let props = MaterialProperties(
            dimensions: d,
            fundamentalFrequencyLong: 170,
            fundamentalFrequencyCross: 100
        )
        #expect(props.youngsModulusLong == 0)
    }

    // Higher frequency → stiffer material → higher E (direct proportionality with f²).
    @Test func youngsModulusLong_higherFrequency_higherModulus() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let propsLow = MaterialProperties(
            dimensions: d, fundamentalFrequencyLong: 100, fundamentalFrequencyCross: 80
        )
        let propsHigh = MaterialProperties(
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
        let p1 = MaterialProperties(dimensions: d1, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50)
        let p2 = MaterialProperties(dimensions: d2, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50)
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
        let props = MaterialProperties(
            dimensions: d, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50
        )
        let c = props.speedOfSoundLong
        #expect(c > 3000 && c < 8000,
                "Sound speed (\(c) m/s) should be in 3000–8000 m/s range for spruce")
    }

    // c = √(E/ρ): since E ∝ f², and c ∝ √E, c ∝ f.
    @Test func speedOfSoundLong_proportionalToFrequency() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let pLow  = MaterialProperties(dimensions: d, fundamentalFrequencyLong: 100, fundamentalFrequencyCross: 80)
        let pHigh = MaterialProperties(dimensions: d, fundamentalFrequencyLong: 200, fundamentalFrequencyCross: 80)
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
        let props = MaterialProperties(
            dimensions: d, fundamentalFrequencyLong: 170, fundamentalFrequencyCross: 100
        )
        let expected = props.youngsModulusLongGPa / d.densityGPerCm3
        #expect(abs(props.specificModulusLong - expected) < 0.001)
    }

    // Zero density → specific modulus = 0 (guard).
    @Test func specificModulusLong_zeroDensity_returnsZero() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 0, massGrams: 0)
        let props = MaterialProperties(
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
        let props = MaterialProperties(
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
        let props = MaterialProperties(
            dimensions: d, fundamentalFrequencyLong: 170, fundamentalFrequencyCross: 100
        )
        let t = props.goreTargetThickness(bodyLengthMm: 0, bodyWidthMm: 390, vibrationalStiffness: 75)
        #expect(t == nil, "Zero body length should return nil")
    }

    // Higher vibrational stiffness target → thicker plate.
    @Test func goreThickness_higherTarget_thickerPlate() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120)
        let props = MaterialProperties(
            dimensions: d, fundamentalFrequencyLong: 170, fundamentalFrequencyCross: 100
        )
        let t55 = props.goreTargetThickness(bodyLengthMm: 490, bodyWidthMm: 390, vibrationalStiffness: 55)
        let t75 = props.goreTargetThickness(bodyLengthMm: 490, bodyWidthMm: 390, vibrationalStiffness: 75)
        if let t55 = t55, let t75 = t75 {
            #expect(t75 > t55, "Higher stiffness target should yield thicker plate: t55=\(t55), t75=\(t75)")
        }
    }
}
