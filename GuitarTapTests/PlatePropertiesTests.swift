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
// MARK: - Fixtures
//
// TWO fixtures, for two different jobs. Mixing them is what let this suite drift.
//
// `realPlate*` — an actual measured sample, for every test that claims a result is
// physically sensible. Dimensions and frequencies are read straight out of the hub's
// committed measurement:
//
//     guitar-tap-project/Tests/Plate/plate-umik-1-swift-mac-1778816330.guitartap
//
// and the expected values are the ones GuitarTap itself reported for it, printed in the
// .pdf beside that file. They are NOT numbers this suite produced — a suite that generates
// its own expectations can never fail.
//
// `synthetic*` — round numbers (density lands on exactly 400 kg/m³), for the algebraic
// identities only: E ∝ f², E ∝ L⁴, c = √(E/ρ), the reciprocal ratios, the zero guards.
// Those hold for any input, so being unphysical costs nothing and hand-checkable arithmetic
// is worth more. It is NOT a plausible plate: its E_C/E_L is 0.0089 against the 0.04–0.08 the
// app's own UI calls typical, so no plausibility claim may rest on it.
// ---------------------------------------------------------------------------

// Real measured plate — see the header note. ρ 0.349 g/cm³, graded Fair.
let realPlateDimensions = MaterialDimensions(
    lengthMM: 557.5, widthMM: 220.5, thicknessMM: 4.85, massGrams: 208
)
let realPlateFl: Float = 67.11537
let realPlateFc: Float = 116.27016
let realPlateFlc: Float = 35.353745
// Body outline saved with that measurement (guitarBodyLength / guitarBodyWidth).
let realPlateBodyLengthMM: Float = 490
let realPlateBodyWidthMM: Float = 390

func makeRealPlate() -> PlateProperties {
    PlateProperties(
        dimensions: realPlateDimensions,
        fundamentalFrequencyLong: realPlateFl,
        fundamentalFrequencyCross: realPlateFc,
        fundamentalFrequencyFlc: realPlateFlc
    )
}

// Synthetic plate — algebraic identities only. See the header note.
let syntheticPlateDimensions = MaterialDimensions(
    lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 120
)

// ---------------------------------------------------------------------------
// MARK: - Real Sample Report
//
// One test per number GuitarTap printed for the committed measurement. If the app is ever
// changed so it would report something different for that plate, exactly this suite fails,
// and the .pdf beside the file says what it used to say.
// ---------------------------------------------------------------------------

@Suite("RealPlateReport")
struct RealPlateReportTests {

    // Density: the report prints 0.349 g/cm³.
    @Test func density_matchesReport() {
        #expect(abs(realPlateDimensions.densityGPerCm3 - 0.349) < 0.001,
                "ρ should be ≈0.349 g/cm³, got \(realPlateDimensions.densityGPerCm3)")
    }

    // Specific modulus: 17.5 (L) and 1.3 (C).
    @Test func specificModulus_matchesReport() {
        let props = makeRealPlate()
        #expect(abs(props.specificModulusLong - 17.5) < 0.1,
                "E/ρ (L) should be ≈17.5, got \(props.specificModulusLong)")
        #expect(abs(props.specificModulusCross - 1.3) < 0.1,
                "E/ρ (C) should be ≈1.3, got \(props.specificModulusCross)")
    }

    // Radiation ratio: the report prints 12.0 for the longitudinal direction.
    @Test func radiationRatio_matchesReport() {
        let props = makeRealPlate()
        #expect(abs(props.radiationRatioLong - 12.0) < 0.1,
                "R (L) should be ≈12.0, got \(props.radiationRatioLong)")
    }

    // This is a genuinely mid-grade plate — Fair, not Excellent. It is the only fixture in the
    // suite that exercises the middle of the quality scale; every synthetic one saturates at
    // Excellent, where the assertion holds however far the thresholds move.
    @Test func quality_isFair_notSaturated() {
        let props = makeRealPlate()
        #expect(props.spruceQualityLong == .fair,
                "specific modulus 17.5 should grade Fair, got \(props.spruceQualityLong)")
    }

    // The real plate straddles two grades — Fair along the grain (17.5), Very Good across it
    // (1.29) — so the 0.7/0.3 blend is doing real work: 0.7·2 + 0.3·4 = 2.6 → Good.
    @Test func overallQuality_blendsTheTwoDirections() {
        let props = makeRealPlate()
        #expect(props.spruceQualityLong == .fair)
        #expect(props.spruceQualityCross == .veryGood)
        #expect(props.overallQuality == .good,
                "0.7·Fair + 0.3·VeryGood should blend to Good, got \(props.overallQuality)")
    }

    // Anisotropy: 0.0734 and 13.6 — inside the 0.04–0.08 and 12–25 bands the app's own UI
    // labels typical for spruce. The synthetic fixture sits at 0.0089 and 113, far outside,
    // which is why no plausibility claim may rest on it.
    @Test func anisotropyRatios_areInTheTypicalBand() {
        let props = makeRealPlate()
        #expect(abs(props.crossLongRatio - 0.0734) < 0.001,
                "E_C/E_L should be ≈0.0734, got \(props.crossLongRatio)")
        #expect(abs(props.longCrossRatio - 13.6) < 0.1,
                "E_L/E_C should be ≈13.6, got \(props.longCrossRatio)")
        #expect(props.crossLongRatio > 0.04 && props.crossLongRatio < 0.08,
                "a real spruce plate should fall in the 0.04–0.08 anisotropy band")
    }
}

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
        let d = syntheticPlateDimensions
        // volume = 0.5 × 0.2 × 0.003 = 0.0003 m³
        // density = 0.12 kg / 0.0003 m³ = 400 kg/m³
        #expect(abs(d.density - 400) < 1, "Expected density ≈ 400 kg/m³, got \(d.density)")
    }

    // g/cm³ conversion: 400 kg/m³ = 0.4 g/cm³.
    @Test func densityGPerCm3_correctConversion() {
        let d = syntheticPlateDimensions
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

    // Real measured plate: GuitarTap reported E_L = 6.11 GPa and E_C = 0.45 GPa for it.
    // Pinned to the app's own report rather than to a band wide enough to admit anything.
    @Test func youngsModulus_realPlate_matchesReportedValues() {
        let props = makeRealPlate()
        #expect(abs(props.youngsModulusLongGPa - 6.11) < 0.01,
                "E_L should be ≈6.11 GPa, got \(props.youngsModulusLongGPa) GPa")
        #expect(abs(props.youngsModulusCrossGPa - 0.45) < 0.01,
                "E_C should be ≈0.45 GPa, got \(props.youngsModulusCrossGPa) GPa")
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
        let d = syntheticPlateDimensions
        let props = PlateProperties(dimensions: d, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50)
        #expect(abs(props.youngsModulusLongGPa - props.youngsModulusLong / 1e9) < 1e-5,
                "youngsModulusLongGPa should equal youngsModulusLong / 1e9")
    }

    // youngsModulusCrossGPa is youngsModulusCross expressed in GPa (÷1e9).
    @Test func youngsModulusCross_gpaPropertyIsCorrect() {
        let d = syntheticPlateDimensions
        let props = PlateProperties(dimensions: d, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50)
        #expect(abs(props.youngsModulusCrossGPa - props.youngsModulusCross / 1e9) < 1e-5,
                "youngsModulusCrossGPa should equal youngsModulusCross / 1e9")
    }

    // Higher frequency → stiffer material → higher E (direct proportionality with f²).
    @Test func youngsModulusLong_higherFrequency_higherModulus() {
        let d = syntheticPlateDimensions
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
        let d2 = syntheticPlateDimensions
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

    // Real measured plate: GuitarTap reported c_L = 4185 m/s and c_C = 1134 m/s.
    @Test func speedOfSound_realPlate_matchesReportedValues() {
        let props = makeRealPlate()
        #expect(abs(props.speedOfSoundLong - 4185) < 1,
                "c_L should be ≈4185 m/s, got \(props.speedOfSoundLong) m/s")
        #expect(abs(props.speedOfSoundCross - 1134) < 1,
                "c_C should be ≈1134 m/s, got \(props.speedOfSoundCross) m/s")
    }

    // speedOfSoundLong = √(youngsModulusLong / density).
    @Test func speedOfSoundLong_equalsSquareRootOfEOverRho() {
        let d = syntheticPlateDimensions
        let props = PlateProperties(dimensions: d, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50)
        let expected = sqrt(props.youngsModulusLong / d.density)
        #expect(abs(props.speedOfSoundLong - expected) < 0.01,
                "speedOfSoundLong should equal sqrt(E / rho)")
    }

    // c = √(E/ρ): since E ∝ f², and c ∝ √E, c ∝ f.
    @Test func speedOfSoundLong_proportionalToFrequency() {
        let d = syntheticPlateDimensions
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
        let d = syntheticPlateDimensions
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

    // Real measured plate, with the body outline saved alongside it (490 x 390 mm) and the
    // Classical Top stiffness target (60) that measurement was taken under. The result must be
    // a sensible finished-top thickness for real tonewood.
    @Test func goreThickness_realPlate_isPlausible() {
        let props = makeRealPlate()
        let t = props.goreTargetThickness(
            bodyLengthMm: realPlateBodyLengthMM,
            bodyWidthMm: realPlateBodyWidthMM,
            vibrationalStiffness: 60
        )
        #expect(t != nil, "Should return a thickness value")
        if let t = t {
            #expect(t > 2.0 && t < 5.0,
                    "Target thickness \(t) mm should be in the 2–5 mm range for a guitar top")
        }
    }

    // Zero body length should return nil.
    @Test func goreThickness_zeroBodyLength_returnsNil() {
        let d = syntheticPlateDimensions
        let props = PlateProperties(
            dimensions: d, fundamentalFrequencyLong: 170, fundamentalFrequencyCross: 100
        )
        let t = props.goreTargetThickness(bodyLengthMm: 0, bodyWidthMm: 390, vibrationalStiffness: 75)
        #expect(t == nil, "Zero body length should return nil")
    }

    // Higher vibrational stiffness target → thicker plate.
    @Test func goreThickness_higherTarget_thickerPlate() {
        let d = syntheticPlateDimensions
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
        let d = syntheticPlateDimensions
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

    // Zero density collapses both moduli to 0, so both ratios must return 0 rather than
    // dividing 0 by 0.
    @Test func ratios_zeroDensity_returnZeroNotNaN() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 0, massGrams: 120)
        let props = PlateProperties(dimensions: d, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50)
        #expect(!props.crossLongRatio.isNaN, "crossLongRatio must not be NaN at zero density")
        #expect(!props.longCrossRatio.isNaN, "longCrossRatio must not be NaN at zero density")
        #expect(props.crossLongRatio == 0)
        #expect(props.longCrossRatio == 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Radiation Ratio Tests
//
// R = c/ρ is shown in the Results panel and in the exported image in all three
// editions. It had no test in any of them until the #17 sweep, which is how the
// web port's inline copy came to be missing the zero-density guard and to render
// the string "NaN" where the natives render 0.
// ---------------------------------------------------------------------------

@Suite("PlateRadiationRatio")
struct PlateRadiationRatioTests {

    private static func makePlate() -> PlateProperties {
        let d = syntheticPlateDimensions
        return PlateProperties(dimensions: d, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50)
    }

    // R_L = c_L / ρ.
    @Test func radiationRatioLong_isSpeedOverDensity() {
        let props = Self.makePlate()
        let expected = props.speedOfSoundLong / props.dimensions.density
        #expect(abs(props.radiationRatioLong - expected) < 1e-4,
                "radiationRatioLong should equal c_L / ρ; expected \(expected), got \(props.radiationRatioLong)")
    }

    // R_C = c_C / ρ.
    @Test func radiationRatioCross_isSpeedOverDensity() {
        let props = Self.makePlate()
        let expected = props.speedOfSoundCross / props.dimensions.density
        #expect(abs(props.radiationRatioCross - expected) < 1e-4,
                "radiationRatioCross should equal c_C / ρ; expected \(expected), got \(props.radiationRatioCross)")
    }

    // Along the grain the plate radiates more efficiently than across it, because c_L > c_C
    // at the same density.
    @Test func radiationRatioLong_exceedsCross() {
        let props = Self.makePlate()
        #expect(props.radiationRatioLong > props.radiationRatioCross,
                "R_L (\(props.radiationRatioLong)) should exceed R_C (\(props.radiationRatioCross))")
    }

    // Zero density → c is 0 too, so the unguarded quotient would be 0/0. Both must be 0.
    @Test func radiationRatio_zeroDensity_returnsZeroNotNaN() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 0, massGrams: 120)
        let props = PlateProperties(dimensions: d, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50)
        #expect(props.dimensions.density == 0, "fixture should have zero density")
        #expect(!props.radiationRatioLong.isNaN, "radiationRatioLong must not be NaN at zero density")
        #expect(!props.radiationRatioCross.isNaN, "radiationRatioCross must not be NaN at zero density")
        #expect(props.radiationRatioLong == 0)
        #expect(props.radiationRatioCross == 0)
    }

    // Zero mass reaches the same guard by the other route.
    @Test func radiationRatio_zeroMass_returnsZeroNotNaN() {
        let d = MaterialDimensions(lengthMM: 500, widthMM: 200, thicknessMM: 3, massGrams: 0)
        let props = PlateProperties(dimensions: d, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50)
        #expect(!props.radiationRatioLong.isNaN)
        #expect(props.radiationRatioLong == 0)
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

    // The colour rule is NOT tested here. It belongs to `test/quality-colors`, which owns the
    // `model/quality-colors` slug, and asserting it in this file as well meant the same rule lived
    // under two slugs. When #17 made the colours absolute, this copy still demanded the old
    // semantic ones and the two disagreed — the full suite caught it. See QualityColorsTests.swift.

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
        let d = syntheticPlateDimensions
        let props = PlateProperties(dimensions: d, fundamentalFrequencyLong: 170, fundamentalFrequencyCross: 100)
        // specificModulusLong = youngsModulusLongGPa / densityGPerCm3; high fL → high value → Excellent
        #expect(props.spruceQualityLong == .excellent,
                "High fL should produce Excellent longitudinal quality, got \(props.spruceQualityLong)")
    }

    // spruceQualityLong returns a WoodQuality value (not nil, not a raw scalar).
    @Test func spruceQualityLong_returnsWoodQualityValue() {
        let d = syntheticPlateDimensions
        let props = PlateProperties(dimensions: d, fundamentalFrequencyLong: 85, fundamentalFrequencyCross: 50)
        let quality = props.spruceQualityLong
        // Just verify it is one of the five valid cases
        let valid: [WoodQuality] = [.excellent, .veryGood, .good, .fair, .poor]
        #expect(valid.contains(quality), "spruceQualityLong should be a valid WoodQuality")
    }

    // overallQuality uses a weighted average of longitudinal (70%) and cross (30%) scores.
    // With a high-fL plate both long and cross will be Excellent (score 5), so overall = Excellent.
    @Test func overallQuality_usesWeightedNumericScore() {
        let d = syntheticPlateDimensions
        let props = PlateProperties(dimensions: d, fundamentalFrequencyLong: 170, fundamentalFrequencyCross: 100)
        // At high frequencies both long and cross should score highly → overall Excellent
        let overall = props.overallQuality
        #expect(overall == .excellent || overall == .veryGood,
                "High-fL plate should have Excellent or VeryGood overall quality, got \(overall)")
    }
}
