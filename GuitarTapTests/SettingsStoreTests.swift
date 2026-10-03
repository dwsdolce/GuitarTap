//
//  SettingsStoreTests.swift
//  GuitarTapTests
//
//  The per-measurement-type display frequency range store: each type has its own default and its
//  own stored minimum and maximum, a bound never stored reads the default, a stored bound keeps its exact
//  value (Save Current View comes back as saved; an untouched Settings field never rounds it), and an
//  entered range is validated before it is stored. Mirrors Python tests/test_settings_store.py and web
//  test/settings-store.test.ts.
//
//  The defaults, the entered value and the validation run the shared case file `settings-store.json`; the
//  store's read and write cases stay here, as each edition persists differently. Serialized: the cases write
//  settings and restore them.
//
// @parity test/settings-store

import Foundation
import Testing
@testable import GuitarTap

private final class SettingsStoreTestsAnchor {}

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

    // MARK: - The shared cases in `settings-store.json`

    static let data: [String: Any] = {
        let url = Bundle(for: SettingsStoreTestsAnchor.self).url(forResource: "settings-store", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    static func type(_ name: String) -> MeasurementType { MeasurementType.allCases.first { "\($0)" == name }! }
    static func f(_ v: Any) -> Float { Float(v as! Double) }

    @Test func perTypeDefaults() {
        for row in Self.data["defaults"] as! [[Any]] {
            let t = Self.type(row[0] as! String)
            #expect(TapDisplaySettings.defaultMinFrequency(for: t) == Self.f(row[1]), "\(row[0])")
            #expect(TapDisplaySettings.defaultMaxFrequency(for: t) == Self.f(row[2]), "\(row[0])")
        }
    }

    /// A Settings range field: untouched keeps the exact stored value, edited is the number typed.
    @Test func enteredValue() {
        for row in Self.data["enteredValue"] as! [[Any]] {
            let value = DisplayRange.enteredValue(row[0] as! String, stored: Self.f(row[1]), decimals: row[2] as! Int)
            #expect(value == (row[3] is NSNull ? nil : Self.f(row[3])), "\(row)")
        }
    }

    @Test func validateFrequencyRange() {
        for row in Self.data["validateFrequencyRange"] as! [[String: Any]] {
            restoringSavedRange {
                if let saved = row["saved"] as? [Double] {
                    TapDisplaySettings.minFrequency = Float(saved[0])
                    TapDisplaySettings.maxFrequency = Float(saved[1])
                }
                let input = row["input"] as! [Double], expect = row["expect"] as! [Double]
                let r = TapDisplaySettings.validateFrequencyRange(minFreq: Float(input[0]), maxFreq: Float(input[1]))
                #expect(r.min == Float(expect[0]) && r.max == Float(expect[1]), "\(input)")
            }
        }
    }

    @Test func validateMagnitudeRange() {
        for row in Self.data["validateMagnitudeRange"] as! [[String: Any]] {
            restoringSavedRange {
                if let saved = row["saved"] as? [Double] {
                    TapDisplaySettings.minMagnitude = Float(saved[0])
                    TapDisplaySettings.maxMagnitude = Float(saved[1])
                }
                let input = row["input"] as! [Double], expect = row["expect"] as! [Double]
                let r = TapDisplaySettings.validateMagnitudeRange(minDB: Float(input[0]), maxDB: Float(input[1]))
                #expect(r.min == Float(expect[0]) && r.max == Float(expect[1]), "\(input)")
            }
        }
    }

    // MARK: - The store: each edition's own persistence

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
}
