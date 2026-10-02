//
//  SettingsStoreTests.swift
//  GuitarTapTests
//
//  The per-measurement-type display frequency range store: each type has its own default and its
//  own stored minimum and maximum, a bound never stored reads the default, a stored bound keeps its exact
//  value (Save Current View comes back as saved; an untouched Settings field never rounds it), and an
//  entered range is validated before it is stored. Mirrors Python
//  tests/test_settings_store.py and web test/settings-store.test.ts.
//
//  The store is the isolated test suite (TapDisplaySettings.defaults under test). Serialized:
//  the cases write plate and brace and restore them.
//
// @parity test/settings-store

import Testing
@testable import GuitarTap

@Suite("SettingsStore", .serialized)
struct SettingsStoreTests {

    /// Run `body`, then put plate's and brace's stored ranges back as they were.
    private func restoringPlateAndBrace(_ body: () -> Void) {
        let saved = [MeasurementType.plate, .brace].map {
            ($0, TapDisplaySettings.minFrequency(for: $0), TapDisplaySettings.maxFrequency(for: $0))
        }
        defer {
            for (type, lo, hi) in saved {
                TapDisplaySettings.setMinFrequency(lo, for: type)
                TapDisplaySettings.setMaxFrequency(hi, for: type)
            }
        }
        body()
    }

    @Test func perTypeDefaults_matchCanonicalValues() {
        for type in [MeasurementType.generic, .acoustic, .classical, .flamenco] {
            #expect(TapDisplaySettings.defaultMinFrequency(for: type) == 75)
            #expect(TapDisplaySettings.defaultMaxFrequency(for: type) == 350)
        }
        #expect(TapDisplaySettings.defaultMinFrequency(for: .plate) == 20)
        #expect(TapDisplaySettings.defaultMaxFrequency(for: .plate) == 200)
        #expect(TapDisplaySettings.defaultMinFrequency(for: .brace) == 30)
        #expect(TapDisplaySettings.defaultMaxFrequency(for: .brace) == 1000)
    }

    @Test func aTypeWithNothingStored_readsItsDefault() {
        #expect(TapDisplaySettings.minFrequency(for: .flamenco) == 75)
        #expect(TapDisplaySettings.maxFrequency(for: .flamenco) == 350)
    }

    @Test func aStoredRange_readsBack() {
        restoringPlateAndBrace {
            TapDisplaySettings.setMinFrequency(15, for: .plate)
            TapDisplaySettings.setMaxFrequency(180, for: .plate)
            #expect(TapDisplaySettings.minFrequency(for: .plate) == 15)
            #expect(TapDisplaySettings.maxFrequency(for: .plate) == 180)
        }
    }

    @Test func storingOneType_doesNotChangeAnother() {
        restoringPlateAndBrace {
            TapDisplaySettings.setMinFrequency(18, for: .plate)
            TapDisplaySettings.setMinFrequency(40, for: .brace)
            #expect(TapDisplaySettings.minFrequency(for: .plate) == 18)
            #expect(TapDisplaySettings.minFrequency(for: .brace) == 40)
        }
    }

    @Test func storingOneBound_leavesTheOther() {
        restoringPlateAndBrace {
            TapDisplaySettings.setMinFrequency(15, for: .plate)
            TapDisplaySettings.setMaxFrequency(250, for: .plate)
            #expect(TapDisplaySettings.minFrequency(for: .plate) == 15)
            #expect(TapDisplaySettings.maxFrequency(for: .plate) == 250)
        }
    }

    @Test func aStoredRange_keepsItsExactValue() {
        restoringPlateAndBrace {
            TapDisplaySettings.setMinFrequency(15.37, for: .plate)
            TapDisplaySettings.setMaxFrequency(180.43, for: .plate)
            #expect(TapDisplaySettings.minFrequency(for: .plate) == 15.37)
            #expect(TapDisplaySettings.maxFrequency(for: .plate) == 180.43)
        }
    }

    // MARK: - A Settings range field: untouched keeps the exact stored value

    @Test func enteredValue_untouchedField_keepsTheExactStoredValue() {
        let stored: Float = 23.37
        let shown = FieldPrecision.string(stored, FieldPrecision.frequencyHz)   // "23"
        #expect(DisplayRange.enteredValue(shown, stored: stored, decimals: FieldPrecision.frequencyHz) == 23.37)
    }

    @Test func enteredValue_editedField_isTheNumberTyped() {
        #expect(DisplayRange.enteredValue("30", stored: 23.37, decimals: FieldPrecision.frequencyHz) == 30)
    }

    @Test func enteredValue_notANumber_isNil() {
        #expect(DisplayRange.enteredValue("abc", stored: 23.37, decimals: FieldPrecision.frequencyHz) == nil)
    }

    // MARK: - Validation of an entered range: each bound clamped, at least 10 apart, else the saved range

    /// Run `body`, then put the current type's saved range and the magnitude range back.
    private func restoringSavedRange(_ body: () -> Void) {
        let saved = (TapDisplaySettings.minFrequency, TapDisplaySettings.maxFrequency,
                     TapDisplaySettings.minMagnitude, TapDisplaySettings.maxMagnitude)
        defer {
            TapDisplaySettings.minFrequency = saved.0
            TapDisplaySettings.maxFrequency = saved.1
            TapDisplaySettings.minMagnitude = saved.2
            TapDisplaySettings.maxMagnitude = saved.3
        }
        body()
    }

    @Test func frequencyRange_valid_isUnchanged() {
        let r = TapDisplaySettings.validateFrequencyRange(minFreq: 200, maxFreq: 3000)
        #expect(r.min == 200 && r.max == 3000)
    }

    @Test func frequencyRange_below1Hz_isClamped() {
        let r = TapDisplaySettings.validateFrequencyRange(minFreq: 0, maxFreq: 3000)
        #expect(r.min == 1 && r.max == 3000)
    }

    @Test func frequencyRange_above5kHz_isClamped() {
        let r = TapDisplaySettings.validateFrequencyRange(minFreq: 200, maxFreq: 6000)
        #expect(r.min == 200 && r.max == 5000)
    }

    @Test func frequencyRange_inverted_readsTheSavedRange() {
        restoringSavedRange {
            TapDisplaySettings.minFrequency = 100
            TapDisplaySettings.maxFrequency = 8000
            let r = TapDisplaySettings.validateFrequencyRange(minFreq: 5000, maxFreq: 200)
            #expect(r.min == 100 && r.max == 8000)
        }
    }

    @Test func frequencyRange_tooNarrow_readsTheSavedRange() {
        restoringSavedRange {
            TapDisplaySettings.minFrequency = 100
            TapDisplaySettings.maxFrequency = 8000
            let r = TapDisplaySettings.validateFrequencyRange(minFreq: 1000, maxFreq: 1005)
            #expect(r.min == 100 && r.max == 8000)
        }
    }

    @Test func frequencyRange_exactly10HzApart_isAccepted() {
        let r = TapDisplaySettings.validateFrequencyRange(minFreq: 100, maxFreq: 110)
        #expect(r.min == 100 && r.max == 110)
    }

    @Test func magnitudeRange_valid_isUnchanged() {
        let r = TapDisplaySettings.validateMagnitudeRange(minDB: -80, maxDB: -20)
        #expect(r.min == -80 && r.max == -20)
    }

    @Test func magnitudeRange_belowMinus120dB_isClamped() {
        let r = TapDisplaySettings.validateMagnitudeRange(minDB: -150, maxDB: -20)
        #expect(r.min == -120 && r.max == -20)
    }

    @Test func magnitudeRange_above20dB_isClamped() {
        let r = TapDisplaySettings.validateMagnitudeRange(minDB: -80, maxDB: 50)
        #expect(r.min == -80 && r.max == 20)
    }

    @Test func magnitudeRange_inverted_readsTheSavedRange() {
        restoringSavedRange {
            TapDisplaySettings.minMagnitude = -100
            TapDisplaySettings.maxMagnitude = -10
            let r = TapDisplaySettings.validateMagnitudeRange(minDB: -20, maxDB: -80)
            #expect(r.min == -100 && r.max == -10)
        }
    }

    @Test func magnitudeRange_tooNarrow_readsTheSavedRange() {
        restoringSavedRange {
            TapDisplaySettings.minMagnitude = -100
            TapDisplaySettings.maxMagnitude = -10
            let r = TapDisplaySettings.validateMagnitudeRange(minDB: -50, maxDB: -45)
            #expect(r.min == -100 && r.max == -10)
        }
    }

    @Test func magnitudeRange_exactly10dBApart_isAccepted() {
        let r = TapDisplaySettings.validateMagnitudeRange(minDB: -60, maxDB: -50)
        #expect(r.min == -60 && r.max == -50)
    }
}

