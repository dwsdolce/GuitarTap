//
//  ClassifyCasesTests.swift
//  GuitarTapTests
//
//  Guitar mode classification against the shared case file, `classify.json` — the same cases the Python
//  and web suites run. The file's spellings are Swift's case names.
//
// @parity test/classify

import Foundation
import Testing
@testable import GuitarTap

private final class ClassifyCasesTestsAnchor {}

@Suite("ClassifyCases")
struct ClassifyCasesTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: ClassifyCasesTestsAnchor.self).url(forResource: "classify", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func rows(_ key: String) -> [[String: Any]] { data[key] as! [[String: Any]] }

    static let modes: [String: GuitarMode] = [
        "air": .air, "top": .top, "back": .back, "dipole": .dipole, "ringMode": .ringMode,
        "upperModes": .upperModes, "unknown": .unknown,
    ]
    static func type(_ name: String) -> GuitarType { GuitarType.allCases.first { "\($0)" == name }! }
    static func peaks(_ row: [String: Any]) -> [ResonantPeak] {
        (row["peaks"] as! [[Double]]).map { ResonantPeak(frequency: Float($0[0]), magnitude: Float($0[1])) }
    }

    @Test(arguments: rows("classifyAll").map { $0["id"] as! String })
    func classifyAll(_ id: String) {
        let row = Self.rows("classifyAll").first { $0["id"] as! String == id }!
        let peaks = Self.peaks(row)
        let result = GuitarMode.classifyAll(peaks, guitarType: Self.type(row["guitarType"] as! String))
        let expected = (row["expect"] as! [String]).map { Self.modes[$0]! }
        #expect(result.count == peaks.count, "\(id)")
        #expect(peaks.map { result[$0.id] } == expected, "\(id)")
    }

    @Test(arguments: rows("resolvedModePeaks").map { $0["id"] as! String })
    func resolvedModePeaks(_ id: String) {
        let row = Self.rows("resolvedModePeaks").first { $0["id"] as! String == id }!
        let peaks = Self.peaks(row)
        let resolved = TapToneAnalyzer.resolvedModePeaks(peaks: peaks, guitarType: Self.type(row["guitarType"] as! String))
        let expected = (row["expect"] as! [String: Int])
        #expect(resolved.count == expected.count, "\(id): \(resolved.keys)")
        for (mode, index) in expected {
            #expect(resolved[Self.modes[mode]!]?.id == peaks[index].id, "\(id): \(mode)")
        }
    }

    @Test func bands() {
        for (name, rows) in Self.data["bands"] as! [String: [[Any]]] {
            let type = Self.type(name)
            for row in rows {
                let range = Self.modes[row[0] as! String]!.modeRange(for: type)
                #expect(Double(range.lowerBound) == (row[1] as! Double) && Double(range.upperBound) == (row[2] as! Double),
                        "\(name) \(row[0]): \(range)")
            }
        }
    }

    @Test func fromDisplayName() {
        for row in Self.data["fromDisplayName"] as! [[Any]] {
            let expected = (row[1] as? String).map { Self.modes[$0]! }
            #expect(GuitarMode.fromDisplayName(row[0] as! String) == expected, "\(row[0])")
        }
        #expect(GuitarMode.additionalModeLabels == Self.data["additionalModeLabels"] as! [String])
    }

    @Test func effectiveMode() {
        for row in Self.rows("effectiveMode") {
            let result = GuitarMode.effectiveMode(override: row["override"] as? String, auto: Self.modes[row["auto"] as! String]!)
            #expect(result == Self.modes[row["expect"] as! String]!, "override \(String(describing: row["override"]))")
        }
    }

    @Test func displayNameAndAbbreviation() {
        for row in Self.data["displayName"] as! [[String]] {
            #expect(Self.modes[row[0]]!.displayName == row[1], "\(row[0])")
        }
        for row in Self.data["abbreviation"] as! [[String]] {
            #expect(Self.modes[row[0]]!.abbreviation == row[1], "\(row[0])")
        }
    }
}
