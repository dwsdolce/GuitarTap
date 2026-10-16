//
//  MaterialMeasurementInputsTests.swift
//  GuitarTapTests
//
//  A material measurement's own dimensions (Store B, `TapToneAnalyzer.materialInputs`) and its notes:
//  taken from the Settings defaults (Store A) at completion, from the file on a load — which never writes
//  the Settings defaults — and written by a save. The shared cases in `material-measurement-inputs.json`
//  (M1–M13), the same as Python and the web.
//
// @parity test/material-measurement-inputs

import Testing
import Foundation
@testable import GuitarTap

private final class MaterialMeasurementInputsAnchor {}

@Suite("MaterialMeasurementInputs", .serialized)
@MainActor
struct MaterialMeasurementInputsTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: MaterialMeasurementInputsAnchor.self)
            .url(forResource: "material-measurement-inputs", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids() -> [String] {
        (data["cases"] as! [[String: Any]]).map { $0["id"] as! String }
    }

    /// The settings a case may set, by their TapDisplaySettings names.
    static let settingNames = ["measurementType", "plateLength", "plateWidth", "plateThickness", "plateMass",
                               "braceLength", "braceWidth", "braceThickness", "braceMass",
                               "guitarBodyLength", "guitarBodyWidth", "plateStiffnessPreset", "customPlateStiffness"]

    static func setting(_ name: String) -> Any {
        switch name {
        case "measurementType": return TapDisplaySettings.measurementType.rawValue
        case "plateLength": return Double(TapDisplaySettings.plateLength)
        case "plateWidth": return Double(TapDisplaySettings.plateWidth)
        case "plateThickness": return Double(TapDisplaySettings.plateThickness)
        case "plateMass": return Double(TapDisplaySettings.plateMass)
        case "braceLength": return Double(TapDisplaySettings.braceLength)
        case "braceWidth": return Double(TapDisplaySettings.braceWidth)
        case "braceThickness": return Double(TapDisplaySettings.braceThickness)
        case "braceMass": return Double(TapDisplaySettings.braceMass)
        case "guitarBodyLength": return Double(TapDisplaySettings.guitarBodyLength)
        case "guitarBodyWidth": return Double(TapDisplaySettings.guitarBodyWidth)
        case "plateStiffnessPreset": return TapDisplaySettings.plateStiffnessPreset.rawValue
        case "customPlateStiffness": return Double(TapDisplaySettings.customPlateStiffness)
        default: fatalError("unknown setting \(name)")
        }
    }

    static func setSetting(_ name: String, _ value: Any) {
        let f = { Float((value as! NSNumber).doubleValue) }
        switch name {
        case "measurementType": TapDisplaySettings.measurementType = MeasurementType(rawValue: value as! String)!
        case "plateLength": TapDisplaySettings.plateLength = f()
        case "plateWidth": TapDisplaySettings.plateWidth = f()
        case "plateThickness": TapDisplaySettings.plateThickness = f()
        case "plateMass": TapDisplaySettings.plateMass = f()
        case "braceLength": TapDisplaySettings.braceLength = f()
        case "braceWidth": TapDisplaySettings.braceWidth = f()
        case "braceThickness": TapDisplaySettings.braceThickness = f()
        case "braceMass": TapDisplaySettings.braceMass = f()
        case "guitarBodyLength": TapDisplaySettings.guitarBodyLength = f()
        case "guitarBodyWidth": TapDisplaySettings.guitarBodyWidth = f()
        case "plateStiffnessPreset":
            TapDisplaySettings.plateStiffnessPreset = PlateStiffnessPreset(rawValue: value as! String)!
        case "customPlateStiffness": TapDisplaySettings.customPlateStiffness = f()
        default: fatalError("unknown setting \(name)")
        }
    }

    /// The inline file a `load` step names, with its notes replaced when the step gives them.
    static func measurement(_ step: [String: Any]) throws -> TapToneMeasurement {
        var file = (data["files"] as! [String: Any])[step["load"] as! String] as! [[String: Any]]
        if let notes = step["notes"] as? String { file[0]["notes"] = notes }
        let fileData = try JSONSerialization.data(withJSONObject: file)
        return try #require(try TapToneAnalyzer.decodeMeasurements(fileData).first)
    }

    /// A Float compared with a case's number, to the precision the cases are written in.
    static func same(_ actual: Float, _ want: Any) -> Bool {
        abs(Double(actual) - (want as! NSNumber).doubleValue) < 1e-4
    }

    @Test(arguments: ids())
    func materialInputs(_ id: String) throws {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        // The settings are global; put them back afterwards.
        let saved = Self.settingNames.map { ($0, Self.setting($0)) }
        defer { for (name, value) in saved { Self.setSetting(name, value) } }

        let sut = TapToneAnalyzer.forTesting()
        var savedRecord: TapToneMeasurement?
        for step in row["steps"] as! [[String: Any]] {
            if let settings = step["settings"] as? [String: Any] {
                // The type first, as a load applies it before the rest.
                if let type = settings["measurementType"] { Self.setSetting("measurementType", type) }
                for (name, value) in settings where name != "measurementType" { Self.setSetting(name, value) }
            } else if step["complete"] as? Bool == true {
                sut.isMeasurementComplete = true
            } else if let loading = step["loading"] as? Bool {
                sut.isLoadingMeasurement = loading
            } else if step["clearInputs"] as? Bool == true {
                sut.materialInputs = nil
            } else if let has = step["hasInputs"] as? Bool {
                #expect((sut.materialInputs != nil) == has, "\(id): precondition — has dimensions \(has)")
            } else if step["load"] != nil {
                sut.loadMeasurement(try Self.measurement(step))
            } else if step["save"] as? Bool == true {
                savedRecord = sut.makeMeasurement()
            }
        }

        for (field, want) in row["expect"] as! [String: Any] {
            switch field {
            case "inputs":
                guard let want = want as? [String: Any] else {
                    #expect(sut.materialInputs == nil, "\(id) inputs: \(String(describing: sut.materialInputs))")
                    continue
                }
                let mi = try #require(sut.materialInputs, "\(id): dimensions")
                for (key, value) in want {
                    switch key {
                    case "lengthMM": #expect(Self.same(mi.lengthMM, value), "\(id) \(key)")
                    case "widthMM": #expect(Self.same(mi.widthMM, value), "\(id) \(key)")
                    case "thicknessMM": #expect(Self.same(mi.thicknessMM, value), "\(id) \(key)")
                    case "massG": #expect(Self.same(mi.massG, value), "\(id) \(key)")
                    case "bodyLengthMM": #expect(Self.same(mi.bodyLengthMM, value), "\(id) \(key)")
                    case "bodyWidthMM": #expect(Self.same(mi.bodyWidthMM, value), "\(id) \(key)")
                    case "stiffnessPreset": #expect(mi.stiffnessPreset.rawValue == value as? String, "\(id) \(key)")
                    case "customStiffness": #expect(Self.same(mi.customStiffness, value), "\(id) \(key)")
                    default: Issue.record("\(id): unknown inputs field \(key)")
                    }
                }
            case "settings":
                for (name, value) in want as! [String: Any] {
                    #expect(Self.same(Float((Self.setting(name) as! Double)), value), "\(id) setting \(name)")
                }
            case "saved":
                let snap = try #require(savedRecord?.longitudinalSnapshot, "\(id): saved snapshot")
                for (key, value) in want as! [String: Any] {
                    switch key {
                    case "plateLength": #expect(Self.same(snap.plateLength ?? .nan, value), "\(id) \(key)")
                    case "plateWidth": #expect(Self.same(snap.plateWidth ?? .nan, value), "\(id) \(key)")
                    case "plateThickness": #expect(Self.same(snap.plateThickness ?? .nan, value), "\(id) \(key)")
                    case "plateMass": #expect(Self.same(snap.plateMass ?? .nan, value), "\(id) \(key)")
                    case "guitarBodyLength": #expect(Self.same(snap.guitarBodyLength ?? .nan, value), "\(id) \(key)")
                    case "guitarBodyWidth": #expect(Self.same(snap.guitarBodyWidth ?? .nan, value), "\(id) \(key)")
                    case "plateStiffnessPreset":
                        #expect(snap.plateStiffnessPreset?.rawValue == value as? String, "\(id) \(key)")
                    default: Issue.record("\(id): unknown saved field \(key)")
                    }
                }
            case "loadedNotes":
                #expect(sut.loadedNotes == want as? String, "\(id) loadedNotes: \(String(describing: sut.loadedNotes))")
            default:
                Issue.record("\(id): unknown field \(field)")
            }
        }
    }
}
