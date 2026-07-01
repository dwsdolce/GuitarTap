//
//  DisplayRangeTests.swift
//  GuitarTapTests
//
//  Per-measurement-type display frequency ranges.
//
//  Parity test (paired): mirrors Python
//  tests/test_wi6_tap_display_settings.py::TestPerTypeDisplayRanges and web
//  test/settings-display-range.test.ts. Each MeasurementType has its own default
//  display range, and a value persisted for one type must not affect another.
//
//  Safe under parallel test execution: the per-type defaults are pure (no
//  UserDefaults), and the `displayMinFreq_<rawValue>` keys are touched by no
//  other test.
//
// @parity test/display-range

import Testing
@testable import GuitarTap

@Suite("DisplayRange")
struct DisplayRangeTests {

    /// The canonical per-type default display ranges — identical across
    /// Swift / Python / web: guitar (all subtypes) 75–350, plate 20–200,
    /// brace 30–1000.
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

    /// Persisting a display range for one measurement type must not change
    /// another type's range (the keys are per-type), and each type reads back
    /// its own stored value.
    @Test func perType_setOneTypeDoesNotClobberAnother() {
        let origPlate = TapDisplaySettings.minFrequency(for: .plate)
        let origBrace = TapDisplaySettings.minFrequency(for: .brace)
        defer {
            TapDisplaySettings.setMinFrequency(origPlate, for: .plate)
            TapDisplaySettings.setMinFrequency(origBrace, for: .brace)
        }

        TapDisplaySettings.setMinFrequency(18, for: .plate)
        TapDisplaySettings.setMinFrequency(40, for: .brace)

        #expect(TapDisplaySettings.minFrequency(for: .plate) == 18)
        #expect(TapDisplaySettings.minFrequency(for: .brace) == 40)
    }
}