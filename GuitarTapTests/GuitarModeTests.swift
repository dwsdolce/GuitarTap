//
//  GuitarModeTests.swift
//  GuitarTapTests
//
//  Tests for GuitarMode classification, normalization, display names,
//  and ideal frequency ranges.  Uses the two-argument classify overload
//  (frequency + explicit GuitarType) so tests are independent of
//  UserDefaults state.
//

import Testing
import Foundation
@testable import GuitarTap

@Suite("GuitarModeClassification")
struct GuitarModeClassificationTests {

    // MARK: - Acoustic guitar classification

    @Test func acoustic_airRange_classifiesAsAir() {
        // Acoustic air range: 90–120 Hz
        #expect(GuitarMode.classify(frequency: 100, guitarType: .acoustic) == .air)
        #expect(GuitarMode.classify(frequency: 90, guitarType: .acoustic) == .air)
        #expect(GuitarMode.classify(frequency: 120, guitarType: .acoustic) == .air)
    }

    @Test func acoustic_topRange_classifiesAsTop() {
        // Acoustic top range: 150–210 Hz
        #expect(GuitarMode.classify(frequency: 180, guitarType: .acoustic) == .top)
    }

    @Test func acoustic_backRange_classifiesAsBack() {
        // Acoustic back range: 210–290 Hz
        #expect(GuitarMode.classify(frequency: 250, guitarType: .acoustic) == .back)
    }

    @Test func acoustic_dipoleRange_classifiesAsDipole() {
        #expect(GuitarMode.classify(frequency: 400, guitarType: .acoustic) == .dipole)
    }

    @Test func acoustic_ringModeRange_classifiesAsRingMode() {
        #expect(GuitarMode.classify(frequency: 700, guitarType: .acoustic) == .ringMode)
    }

    @Test func acoustic_upperModesRange_classifiesAsUpperModes() {
        #expect(GuitarMode.classify(frequency: 1200, guitarType: .acoustic) == .upperModes)
    }

    // A frequency that falls between defined ranges should return .unknown.
    @Test func acoustic_betweenRanges_classifiesAsUnknown() {
        // Between acoustic back (290) and dipole (360): e.g. 320 Hz
        #expect(GuitarMode.classify(frequency: 320, guitarType: .acoustic) == .unknown)
    }

    // MARK: - Classical guitar classification

    @Test func classical_airRange_classifiesAsAir() {
        // Classical air range: 80–110 Hz
        #expect(GuitarMode.classify(frequency: 95, guitarType: .classical) == .air)
    }

    @Test func classical_topRange_classifiesAsTop() {
        // Classical top range: 170–230 Hz
        #expect(GuitarMode.classify(frequency: 200, guitarType: .classical) == .top)
    }

    // MARK: - Flamenco guitar classification

    @Test func flamenco_airRange_classifiesAsAir() {
        // Flamenco air range: 85–115 Hz
        #expect(GuitarMode.classify(frequency: 100, guitarType: .flamenco) == .air)
    }

    // MARK: - Mode normalization (legacy cases)

    @Test func helmholtz_normalizesToAir() {
        #expect(GuitarMode.helmholtz.normalized == .air)
    }

    @Test func crossGrain_normalizesToAir() {
        #expect(GuitarMode.crossGrain.normalized == .air)
    }

    @Test func longGrain_normalizesToTop() {
        #expect(GuitarMode.longGrain.normalized == .top)
    }

    @Test func monopole_normalizesToBack() {
        #expect(GuitarMode.monopole.normalized == .back)
    }

    @Test func air_normalizesToAir() {
        // Modern cases normalize to themselves
        #expect(GuitarMode.air.normalized == .air)
    }

    @Test func dipole_normalizesToDipole() {
        #expect(GuitarMode.dipole.normalized == .dipole)
    }

    // MARK: - Display names

    @Test func displayName_legacyHelmholtz_showsAirHelmholtz() {
        #expect(GuitarMode.helmholtz.displayName == "Air (Helmholtz)")
    }

    @Test func displayName_legacyLongGrain_showsTop() {
        #expect(GuitarMode.longGrain.displayName == "Top")
    }

    @Test func displayName_legacyMonopole_showsBack() {
        #expect(GuitarMode.monopole.displayName == "Back")
    }

    @Test func displayName_unknown_showsUnknown() {
        #expect(GuitarMode.unknown.displayName == "Unknown")
    }

    // MARK: - Ideal range consistency

    // The ideal range must be contained within (or equal to) the mode's classification range.
    @Test func idealRange_classicalAir_containedInClassificationRange() {
        let ideal = GuitarMode.air.idealRange(for: .classical)
        let classif = GuitarType.classical.modeRanges.air
        // Ideal range must be narrower or equal to classification range
        #expect(ideal.lowerBound >= classif.lowerBound)
        #expect(ideal.upperBound <= classif.upperBound)
    }

    @Test func idealRange_acousticTop_containedInClassificationRange() {
        let ideal = GuitarMode.top.idealRange(for: .acoustic)
        let classif = GuitarType.acoustic.modeRanges.top
        #expect(ideal.lowerBound >= classif.lowerBound)
        #expect(ideal.upperBound <= classif.upperBound)
    }

    // MARK: - Annotation visibility mode cycle

    @Test func annotationVisibilityCycle_allToSelectedToNoneToAll() {
        var mode = AnnotationVisibilityMode.all
        mode = mode.next
        #expect(mode == .selected)
        mode = mode.next
        #expect(mode == .none)
        mode = mode.next
        #expect(mode == .all)
    }

    @Test func annotationVisibility_iconNames_nonEmpty() {
        for mode in AnnotationVisibilityMode.allCases {
            #expect(!mode.iconName.isEmpty, "Icon name for \(mode) should not be empty")
        }
    }
}
