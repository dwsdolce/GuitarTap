//
//  PlatePropertiesTests.swift
//  GuitarTapTests
//
//  Plate material properties (PlateProperties, MaterialDimensions, WoodQuality) against the shared case
//  file, `plate.json` — the same cases the Python and web suites run. Its first row is the hub's committed
//  plate measurement (Tests/Plate/plate-umik-1-swift-mac-1778816330.guitartap), whose values match the
//  ones GuitarTap reported for it in the .pdf beside that file.
//
// @parity test/plate

import Foundation
import Testing
@testable import GuitarTap

private final class PlatePropertiesTestsAnchor {}

/// Reading a material case file (`plate.json`, `brace.json`).
enum MaterialCases {
    nonisolated static func load(_ name: String) -> [String: Any] {
        let url = Bundle(for: PlatePropertiesTestsAnchor.self).url(forResource: name, withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    static func float(_ value: Any?) -> Float? { (value as? NSNumber)?.floatValue }

    static func dimensions(_ row: [String: Any]) -> MaterialDimensions {
        let s = row["sample"] as! [String: Any]
        return MaterialDimensions(lengthMM: float(s["lengthMm"])!, widthMM: float(s["widthMm"])!,
                                  thicknessMM: float(s["thicknessMm"])!, massGrams: float(s["massG"])!)
    }

    /// `|actual − expected| ≤ relative·|expected| + absolute`, from the file's `tolerance`.
    static func close(_ actual: Float, _ expected: Any?, _ data: [String: Any]) -> Bool {
        let tol = data["tolerance"] as! [String: Double]
        let e = (expected as! NSNumber).doubleValue
        return abs(Double(actual) - e) <= tol["relative"]! * abs(e) + tol["absolute"]!
    }
}

@Suite("PlateProperties")
struct PlatePropertiesTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data = MaterialCases.load("plate")
    nonisolated static func rows(_ key: String) -> [[String: Any]] { data[key] as! [[String: Any]] }

    @Test(arguments: rows("plates").map { $0["id"] as! String })
    func plate(_ id: String) {
        let row = Self.rows("plates").first { $0["id"] as! String == id }!
        let e = row["expect"] as! [String: Any]
        let dims = MaterialCases.dimensions(row)
        let p = PlateProperties(dimensions: dims,
                                fundamentalFrequencyLong: MaterialCases.float(row["fL"])!,
                                fundamentalFrequencyCross: MaterialCases.float(row["fC"])!,
                                fundamentalFrequencyFlc: MaterialCases.float(row["fLC"]))
        let numbers: [(String, Float)] = [
            ("volume", dims.volume), ("density", dims.density), ("densityGPerCm3", dims.densityGPerCm3),
            ("youngsModulusLong", p.youngsModulusLong), ("youngsModulusCross", p.youngsModulusCross),
            ("youngsModulusLongGPa", p.youngsModulusLongGPa), ("youngsModulusCrossGPa", p.youngsModulusCrossGPa),
            ("speedOfSoundLong", p.speedOfSoundLong), ("speedOfSoundCross", p.speedOfSoundCross),
            ("specificModulusLong", p.specificModulusLong), ("specificModulusCross", p.specificModulusCross),
            ("radiationRatioLong", p.radiationRatioLong), ("radiationRatioCross", p.radiationRatioCross),
            ("crossLongRatio", p.crossLongRatio), ("longCrossRatio", p.longCrossRatio),
            ("goreYoungsModulusLong", p.goreYoungsModulusLong), ("goreYoungsModulusCross", p.goreYoungsModulusCross),
        ]
        for (name, value) in numbers {
            #expect(MaterialCases.close(value, e[name], Self.data), "\(id): \(name) \(value)")
        }
        #expect(p.spruceQualityLong.rawValue == e["spruceQualityLong"] as! String, "\(id): spruceQualityLong")
        #expect(p.spruceQualityCross.rawValue == e["spruceQualityCross"] as! String, "\(id): spruceQualityCross")
        #expect(p.overallQuality.rawValue == e["overallQuality"] as! String, "\(id): overallQuality")
        if e["goreShearModulus"] is NSNull {
            #expect(p.goreShearModulus == nil, "\(id): goreShearModulus")
        } else {
            #expect(p.goreShearModulus.map { MaterialCases.close($0, e["goreShearModulus"], Self.data) } == true,
                    "\(id): goreShearModulus \(String(describing: p.goreShearModulus))")
        }
        for g in (row["goreTargetThickness"] as? [[String: Any]]) ?? [] {
            let t = p.goreTargetThickness(bodyLengthMm: MaterialCases.float(g["bodyLengthMm"])!,
                                          bodyWidthMm: MaterialCases.float(g["bodyWidthMm"])!,
                                          vibrationalStiffness: MaterialCases.float(g["vibrationalStiffness"])!)
            if g["expect"] is NSNull {
                #expect(t == nil, "\(id): goreTargetThickness \(g)")
            } else {
                #expect(t.map { MaterialCases.close($0, g["expect"], Self.data) } == true,
                        "\(id): goreTargetThickness \(g) → \(String(describing: t))")
            }
        }
    }

    @Test func woodQuality() {
        let types: [String: WoodQuality.WoodType] = ["spruce": .spruce, "cedar": .cedar, "maple": .maple, "rosewood": .rosewood]
        for row in Self.rows("woodQuality") {
            let q = WoodQuality.evaluate(specificModulus: MaterialCases.float(row["specificModulus"])!,
                                         direction: row["direction"] as! String == "longitudinal" ? .longitudinal : .cross,
                                         woodType: types[row["woodType"] as! String]!)
            #expect(q.rawValue == row["expect"] as! String, "\(row)")
        }
    }

    @Test func numericScore() {
        for row in Self.rows("numericScore") {
            let q = WoodQuality(rawValue: row["quality"] as! String)!
            #expect(Double(q.numericScore) == (row["expect"] as! NSNumber).doubleValue, "\(q)")
        }
    }
}
