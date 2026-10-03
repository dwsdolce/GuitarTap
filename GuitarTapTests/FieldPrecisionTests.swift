//
//  FieldPrecisionTests.swift
//  GuitarTapTests
//
//  The numeric-precision table and its helpers (FieldPrecision) against the shared case file,
//  `field-precision.json` — the same cases the Python and web suites run.
//
// @parity test/field-precision

import Foundation
import Testing
@testable import GuitarTap

private final class FieldPrecisionTestsAnchor {}

@Suite("FieldPrecision")
struct FieldPrecisionTests {

    static let data: [String: Any] = {
        let url = Bundle(for: FieldPrecisionTestsAnchor.self).url(forResource: "field-precision", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    /// The file's field names → FieldPrecision's values (Swift has no lookup by name).
    static let fields: [String: Int] = [
        "linearDimensionMM": FieldPrecision.linearDimensionMM, "massG": FieldPrecision.massG,
        "bodyDimensionMM": FieldPrecision.bodyDimensionMM, "frequencyHz": FieldPrecision.frequencyHz,
        "magnitudeDB": FieldPrecision.magnitudeDB, "stiffness": FieldPrecision.stiffness,
        "peakFrequencyHz": FieldPrecision.peakFrequencyHz, "peakMagnitudeDB": FieldPrecision.peakMagnitudeDB,
        "qFactor": FieldPrecision.qFactor, "youngsModulusGPa": FieldPrecision.youngsModulusGPa,
        "speedOfSoundMS": FieldPrecision.speedOfSoundMS, "densityGPerCm3": FieldPrecision.densityGPerCm3,
        "decayRatio": FieldPrecision.decayRatio, "bandwidthHz": FieldPrecision.bandwidthHz,
        "shearModulusGPa": FieldPrecision.shearModulusGPa, "specificModulus": FieldPrecision.specificModulus,
        "radiationRatio": FieldPrecision.radiationRatio, "crossLongRatio": FieldPrecision.crossLongRatio,
        "longCrossRatio": FieldPrecision.longCrossRatio, "goreThicknessMM": FieldPrecision.goreThicknessMM,
        "decayTimeS": FieldPrecision.decayTimeS,
    ]

    /// A number from the file, "Infinity" / "-Infinity" included.
    static func number(_ v: Any) -> Float {
        if let s = v as? String { return s == "-Infinity" ? -.infinity : .infinity }
        return Float(v as! Double)
    }

    @Test func table() {
        for row in Self.data["table"] as! [[Any]] {
            let name = row[0] as! String
            #expect(Self.fields[name] == (row[1] as! Int), "\(name)")
        }
        #expect(Self.fields.count == (Self.data["table"] as! [[Any]]).count)
    }

    @Test func decimalsWithin() {
        for row in Self.data["decimalsWithin"] as! [[Any]] {
            #expect(FieldPrecision.decimalsWithin(row[0] as! String, row[1] as! Int) == (row[2] as! Bool), "\(row[0]) \(row[1])")
        }
    }

    @Test func rounded() {
        for row in Self.data["rounded"] as! [[String: Any]] {
            let result = FieldPrecision.rounded(Self.number(row["value"]!), row["decimals"] as! Int)
            let expected = Self.number(row["expect"]!)
            if let tolerance = row["tolerance"] as? Double {
                #expect(abs(result - expected) < Float(tolerance), "\(row["value"]!)")
            } else {
                #expect(result == expected, "\(row["value"]!)")
            }
        }
    }

    @Test func string() {
        for row in Self.data["string"] as! [[Any]] {
            #expect(FieldPrecision.string(Self.number(row[0]), row[1] as! Int) == (row[2] as! String), "\(row[0]) \(row[1])")
        }
    }
}
