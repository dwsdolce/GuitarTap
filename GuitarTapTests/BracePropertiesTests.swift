//
//  BracePropertiesTests.swift
//  GuitarTapTests
//
//  Brace material properties (BraceProperties) against the shared case file, `brace.json` — the same
//  cases the Python and web suites run.
//
// @parity test/brace

import Foundation
import Testing
@testable import GuitarTap

@Suite("BraceProperties")
struct BracePropertiesTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data = MaterialCases.load("brace")
    nonisolated(unsafe) static let rows = data["braces"] as! [[String: Any]]

    @Test(arguments: rows.map { $0["id"] as! String })
    func brace(_ id: String) {
        let row = Self.rows.first { $0["id"] as! String == id }!
        let e = row["expect"] as! [String: Any]
        let dims = MaterialCases.dimensions(row)
        let p = BraceProperties(dimensions: dims, fundamentalFrequencyLong: MaterialCases.float(row["fL"])!)
        let numbers: [(String, Float)] = [
            ("volume", dims.volume), ("density", dims.density), ("densityGPerCm3", dims.densityGPerCm3),
            ("youngsModulusLong", p.youngsModulusLong), ("youngsModulusLongGPa", p.youngsModulusLongGPa),
            ("speedOfSoundLong", p.speedOfSoundLong), ("specificModulusLong", p.specificModulusLong),
            ("radiationRatioLong", p.radiationRatioLong),
        ]
        for (name, value) in numbers {
            #expect(MaterialCases.close(value, e[name], Self.data), "\(id): \(name) \(value)")
        }
        #expect(p.spruceQuality.rawValue == e["spruceQuality"] as! String, "\(id): spruceQuality")
    }
}
