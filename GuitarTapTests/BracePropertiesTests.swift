//
//  BracePropertiesTests.swift
//  GuitarTapTests
//
//  Tests for BraceProperties calculations.
//  BraceProperties uses only a single longitudinal tap (fL); there is no
//  cross-grain or FLC measurement, and no Gore target thickness.
//
//  The free-free beam formula is identical in form to PlateProperties but
//  uses the more precise beam constant 22.37332 (vs 22.37 for plates).
//
//  Reference formula:
//    E = 48π²ρf²L⁴ / (22.37332·t)²
//
//  All test fixtures are derived from a real measured brace blank:
//    Length 556 mm, Width 20.4 mm, Thickness (Height) 29.4 mm, Mass 128 g, fL 512.3 Hz
//    → ρ ≈ 383.8 kg/m³, EL ≈ 10.54 GPa, c ≈ 5240 m/s, specific modulus ≈ 27.46 → Excellent
// @parity test/brace

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Shared fixture
// ---------------------------------------------------------------------------

// Real measured spruce brace blank used as the baseline throughout these tests.
private let realBraceDimensions = MaterialDimensions(
    lengthMM: 556, widthMM: 20.4, thicknessMM: 29.4, massGrams: 128
)
private let realBraceFl: Float = 512.3

// ---------------------------------------------------------------------------
// MARK: - Young's Modulus Tests
// ---------------------------------------------------------------------------

@Suite("BraceYoungModulus")
struct BraceYoungModulusTests {

    // EL from the real measured blank should fall in the expected spruce range (8–16 GPa).
    @Test func youngsModulusLong_realBrace_physicallyPlausible() {
        let props = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl)
        let EL = props.youngsModulusLong
        #expect(EL > 8e9 && EL < 16e9,
                "EL (\(EL/1e9) GPa) should be in 8–16 GPa range for quality spruce")
    }

    // Spot-check: EL should be within 1% of the hand-calculated 10.541 GPa.
    @Test func youngsModulusLong_realBrace_matchesKnownValue() {
        let props = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl)
        let EL_GPa = props.youngsModulusLong / 1e9
        #expect(abs(EL_GPa - 10.541) < 0.05,
                "EL should be ≈10.54 GPa, got \(EL_GPa) GPa")
    }

    // Zero thickness → guard returns 0.
    @Test func youngsModulusLong_zeroThickness_returnsZero() {
        let d = MaterialDimensions(lengthMM: 556, widthMM: 20.4, thicknessMM: 0, massGrams: 128)
        let props = BraceProperties(dimensions: d, fundamentalFrequencyLong: realBraceFl)
        #expect(props.youngsModulusLong == 0)
    }

    // Zero mass → density = 0 → guard returns 0.
    @Test func youngsModulusLong_zeroMass_returnsZero() {
        let d = MaterialDimensions(lengthMM: 556, widthMM: 20.4, thicknessMM: 29.4, massGrams: 0)
        let props = BraceProperties(dimensions: d, fundamentalFrequencyLong: realBraceFl)
        #expect(props.youngsModulusLong == 0)
    }

    // E ∝ f²: doubling fL should quadruple EL.
    @Test func youngsModulusLong_doubleFrequency_quadruplesModulus() {
        let propsLow  = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl)
        let propsHigh = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl * 2)
        let ratio = propsHigh.youngsModulusLong / propsLow.youngsModulusLong
        #expect(abs(ratio - 4.0) < 0.01,
                "Doubling fL should quadruple EL (ratio = \(ratio))")
    }

    // E ∝ L⁴ at constant density: doubling length (and mass to keep density constant)
    // should increase EL by 2⁴ = 16.
    @Test func youngsModulusLong_doubleLength_sixteenXModulus() {
        let d1 = realBraceDimensions
        let d2 = MaterialDimensions(lengthMM: 556 * 2, widthMM: 20.4, thicknessMM: 29.4, massGrams: 128 * 2)
        let p1 = BraceProperties(dimensions: d1, fundamentalFrequencyLong: realBraceFl)
        let p2 = BraceProperties(dimensions: d2, fundamentalFrequencyLong: realBraceFl)
        let ratio = p2.youngsModulusLong / p1.youngsModulusLong
        #expect(abs(ratio - 16.0) < 0.1,
                "Doubling length at constant density should increase EL 16× (L⁴), got ratio = \(ratio)")
    }

    // youngsModulusLongGPa is youngsModulusLong expressed in GPa (÷1e9).
    @Test func youngsModulusLong_gpaPropertyIsCorrect() {
        let props = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl)
        #expect(abs(props.youngsModulusLongGPa - props.youngsModulusLong / 1e9) < 1e-5,
                "youngsModulusLongGPa should equal youngsModulusLong / 1e9")
    }

    // BraceProperties uses 22.37332, not 22.37. Verify the constant is applied.
    @Test func youngsModulusLong_usesPreciseBeamConstant() {
        let d = realBraceDimensions
        let props = BraceProperties(dimensions: d, fundamentalFrequencyLong: realBraceFl)
        let rho = d.density
        let f = realBraceFl
        let L = d.length
        let t = d.thickness
        let withPrecise = 48 * Float.pi * Float.pi * rho * f * f * pow(L, 4) / pow(22.37332 * t, 2)
        let withApprox  = 48 * Float.pi * Float.pi * rho * f * f * pow(L, 4) / pow(22.37   * t, 2)
        #expect(abs(props.youngsModulusLong - withPrecise) < 1.0,
                "BraceProperties should use constant 22.37332")
        #expect(abs(props.youngsModulusLong - withApprox) > 1000.0,
                "Result should differ meaningfully from the approximate 22.37 constant")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Speed of Sound Tests
// ---------------------------------------------------------------------------

@Suite("BraceSpeedOfSound")
struct BraceSpeedOfSoundTests {

    // Real blank: c ≈ 5240 m/s — well within the 4000–7000 m/s spruce range.
    @Test func speedOfSoundLong_realBrace_inExpectedRange() {
        let props = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl)
        let c = props.speedOfSoundLong
        #expect(c > 4000 && c < 7000,
                "Sound speed (\(c) m/s) should be in 4000–7000 m/s range for quality spruce")
    }

    // Spot-check: c should be within 10 m/s of the hand-calculated 5240 m/s.
    @Test func speedOfSoundLong_realBrace_matchesKnownValue() {
        let props = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl)
        #expect(abs(props.speedOfSoundLong - 5240.4) < 10,
                "c should be ≈5240 m/s, got \(props.speedOfSoundLong) m/s")
    }

    // speedOfSoundLong = √(youngsModulusLong / density).
    @Test func speedOfSoundLong_equalsSquareRootOfEOverRho() {
        let props = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl)
        let expected = sqrt(props.youngsModulusLong / realBraceDimensions.density)
        #expect(abs(props.speedOfSoundLong - expected) < 0.01,
                "speedOfSoundLong should equal sqrt(E / rho)")
    }

    // c = √(E/ρ): since E ∝ f², c ∝ f. Doubling fL should double c.
    @Test func speedOfSoundLong_proportionalToFrequency() {
        let pLow  = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl)
        let pHigh = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl * 2)
        let ratio = pHigh.speedOfSoundLong / pLow.speedOfSoundLong
        #expect(abs(ratio - 2.0) < 0.05,
                "Doubling fL should double speed of sound (ratio = \(ratio))")
    }

    // Zero density → guard returns 0.
    @Test func speedOfSoundLong_zeroDensity_returnsZero() {
        let d = MaterialDimensions(lengthMM: 556, widthMM: 20.4, thicknessMM: 0, massGrams: 0)
        let props = BraceProperties(dimensions: d, fundamentalFrequencyLong: realBraceFl)
        #expect(props.speedOfSoundLong == 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Specific Modulus Tests
// ---------------------------------------------------------------------------

@Suite("BraceSpecificModulus")
struct BraceSpecificModulusTests {

    // Real blank: specific modulus ≈ 27.46 GPa/(g/cm³) → Excellent grade spruce.
    @Test func specificModulusLong_realBrace_matchesKnownValue() {
        let props = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl)
        #expect(abs(props.specificModulusLong - 27.46) < 0.1,
                "Specific modulus should be ≈27.46, got \(props.specificModulusLong)")
    }

    // specificModulusLong = youngsModulusLongGPa / densityGPerCm3
    @Test func specificModulusLong_matchesManualCalc() {
        let props = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl)
        let expected = props.youngsModulusLongGPa / realBraceDimensions.densityGPerCm3
        #expect(abs(props.specificModulusLong - expected) < 0.001)
    }

    // Zero density → specific modulus = 0 (guard).
    @Test func specificModulusLong_zeroDensity_returnsZero() {
        let d = MaterialDimensions(lengthMM: 556, widthMM: 20.4, thicknessMM: 0, massGrams: 0)
        let props = BraceProperties(dimensions: d, fundamentalFrequencyLong: realBraceFl)
        #expect(props.specificModulusLong == 0)
    }

    // Higher frequency → stiffer → higher specific modulus.
    @Test func specificModulusLong_higherFrequency_higherValue() {
        let pLow  = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl / 2)
        let pHigh = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl)
        #expect(pHigh.specificModulusLong > pLow.specificModulusLong,
                "Higher fL should give higher specific modulus")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Quality Assessment Tests
// ---------------------------------------------------------------------------

@Suite("BraceQuality")
struct BraceQualityTests {

    // Real blank has specific modulus ≈ 27.46 (≥25) → Excellent.
    @Test func spruceQuality_realBrace_excellent() {
        let props = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl)
        #expect(props.spruceQuality == .excellent,
                "Real spruce brace with specific modulus ≈27.46 should be Excellent")
    }

    // Half the frequency → EL × ¼ → specific modulus × ¼ ≈ 6.9 → Poor (<16).
    @Test func spruceQuality_halfFrequency_poor() {
        let props = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl / 2)
        #expect(props.specificModulusLong < 16,
                "Half fL should give specific modulus < 16, got \(props.specificModulusLong)")
        #expect(props.spruceQuality == .poor)
    }

    // Quality is monotonically ordered with frequency (and therefore specific modulus).
    @Test func spruceQuality_higherFrequency_betterOrEqualQuality() {
        let pLow  = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl / 2)
        let pHigh = BraceProperties(dimensions: realBraceDimensions, fundamentalFrequencyLong: realBraceFl)
        #expect(pHigh.spruceQuality.numericScore >= pLow.spruceQuality.numericScore,
                "Higher fL should yield equal or better quality rating")
    }
}
