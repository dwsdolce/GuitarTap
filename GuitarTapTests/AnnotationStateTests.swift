//
//  AnnotationStateTests.swift
//  GuitarTapTests
//
//  The per-peak state the user edits and the views read: dragged label positions, selection, which
//  peaks are annotated, mode labels (the user's own and the auto-detected), the one definitive
//  Air/Top/Back and the tap-tone ratio, and what clears it all. The shared cases in
//  `annotation-state.json` (AS1–AS41), the same as Python and the web: each loads its peaks as the app
//  loads a file and edits them as the views do. Below them, the visibility enum's own cycle and icons,
//  which are Swift's UI types.
//
// @parity test/annotation-state

import Testing
import Foundation
@testable import GuitarTap

private final class AnnotationStateAnchor {}

@Suite("AnnotationState", .serialized)
@MainActor
struct AnnotationStateTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: AnnotationStateAnchor.self).url(forResource: "annotation-state", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids() -> [String] {
        (data["cases"] as! [[String: Any]]).map { $0["id"] as! String }
    }

    static let modes: [String: GuitarMode] = [
        "air": .air, "top": .top, "back": .back, "dipole": .dipole,
        "ringMode": .ringMode, "upperModes": .upperModes, "unknown": .unknown,
    ]
    static func modeName(_ mode: GuitarMode) -> String { String(describing: mode) }

    /// One case's peaks and the names it gives them.
    struct Context {
        let sut: TapToneAnalyzer
        let ids: [String: UUID]
        var names: [UUID: String] { Dictionary(uniqueKeysWithValues: ids.map { ($1, $0) }) }

        /// The analyzer's peak of that name, or — for a name the file does not hold — a peak at 220 Hz
        /// with that id, which the analyzer does not know.
        func peak(_ name: String) -> ResonantPeak {
            let id = ids[name]!
            if let known = sut.allPeaks.first(where: { $0.id == id }) { return known }
            let json = #"{"id":"\#(id.uuidString)","frequency":220,"magnitude":-20,"quality":10,"bandwidth":5,"timestamp":"2026-01-01T00:00:00Z"}"#
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try! decoder.decode(ResonantPeak.self, from: Data(json.utf8))
        }
        func namesOf(_ set: Set<UUID>) -> [String] { set.map { names[$0] ?? $0.uuidString }.sorted() }
    }

    static func run(_ step: [String: Any], _ c: Context, files: [String: Any]) throws -> Bool {
        let sut = c.sut
        if let name = step["load"] as? String {
            let data = try JSONSerialization.data(withJSONObject: files[name]!)
            sut.loadMeasurement(try #require(try TapToneAnalyzer.decodeMeasurements(data).first))
        } else if let name = step["toggle"] as? String {
            sut.togglePeakSelection(c.ids[name]!)
        } else if step["selectNone"] as? Bool == true {
            sut.selectNoPeaks()
        } else if step["resetToAuto"] as? Bool == true {
            sut.resetToAutoSelection()
        } else if let o = step["override"] as? [Any] {
            sut.setModeOverride(o[1] as! String, for: c.ids[o[0] as! String]!)
        } else if let name = step["resetOverride"] as? String {
            sut.resetModeOverride(for: c.ids[name]!)
        } else if let o = step["offset"] as? [Any] {
            sut.updateAnnotationOffset(for: c.ids[o[0] as! String]!,
                                       offset: CGPoint(x: (o[1] as! NSNumber).doubleValue, y: (o[2] as! NSNumber).doubleValue))
        } else if let name = step["resetOffset"] as? String {
            sut.resetAnnotationOffset(for: c.ids[name]!)
        } else if step["resetAllOffsets"] as? Bool == true {
            sut.resetAllAnnotationOffsets()
        } else if let mode = step["visibility"] as? String {
            sut.annotationVisibilityMode = AnnotationVisibilityMode(rawValue: mode)!
        } else if step["cycleVisibility"] as? Bool == true {
            sut.cycleAnnotationVisibility()
        } else if let type = step["guitarTypeChange"] as? String {
            TapDisplaySettings.measurementType = MeasurementType(rawValue: type)!
            sut.reclassifyForGuitarTypeChange()
        } else {
            return runAnalyzerStep(step, on: sut)
        }
        return true
    }

    /// Asserts the fields an expectation names.
    static func check(_ fields: [String: Any], _ c: Context, _ id: String) {
        let sut = c.sut
        for (field, want) in fields {
            switch field {
            case "selected":
                #expect(c.namesOf(sut.selectedPeakIDs) == (want as! [String]).sorted(), "\(id) \(field): \(c.namesOf(sut.selectedPeakIDs))")
            case "userModified":
                #expect(sut.userHasModifiedPeakSelection == want as? Bool, "\(id) \(field)")
            case "visible":
                let hz = sut.visiblePeaks.map { Double($0.frequency) }.sorted()
                #expect(hz == (want as! [NSNumber]).map(\.doubleValue), "\(id) \(field): \(hz)")
            case "visibility":
                #expect(sut.annotationVisibilityMode.rawValue == want as? String, "\(id) \(field)")
            case "savedVisibility":
                #expect(TapDisplaySettings.annotationVisibilityMode.rawValue == want as? String, "\(id) \(field)")
            case "label":
                for (name, label) in want as! [String: String] {
                    #expect(sut.effectiveModeLabel(for: c.peak(name)) == label, "\(id) \(field) \(name): \(sut.effectiveModeLabel(for: c.peak(name)))")
                }
            case "mode":
                for (name, mode) in want as! [String: String] {
                    #expect(modeName(sut.peakMode(for: c.peak(name))) == mode, "\(id) \(field) \(name): \(sut.peakMode(for: c.peak(name)))")
                }
            case "autoMode":
                for (name, mode) in want as! [String: String] {
                    #expect(modeName(sut.autoDetectedMode(for: c.peak(name))) == mode, "\(id) \(field) \(name): \(sut.autoDetectedMode(for: c.peak(name)))")
                }
            case "manualOverride":
                for (name, flag) in want as! [String: Bool] {
                    #expect(sut.hasManualOverride(for: c.ids[name]!) == flag, "\(id) \(field) \(name)")
                }
            case "overrides":
                let got = Dictionary(uniqueKeysWithValues: sut.peakModeOverrides.map { (c.names[$0] ?? $0.uuidString, $1) })
                #expect(got == want as? [String: String], "\(id) \(field): \(got)")
            case "offsets":
                let got = Dictionary(uniqueKeysWithValues: sut.peakAnnotationOffsets.map {
                    (c.names[$0] ?? $0.uuidString, [Double($1.x), Double($1.y)])
                })
                let wanted = (want as! [String: [NSNumber]]).mapValues { $0.map(\.doubleValue) }
                #expect(got == wanted, "\(id) \(field): \(got)")
            case "offsetCount":
                #expect(sut.peakAnnotationOffsets.count == want as? Int, "\(id) \(field)")
            case "getPeak":
                for (mode, name) in want as! [String: Any] {
                    let got = sut.getPeak(for: modes[mode]!).map { c.names[$0.id] ?? $0.id.uuidString }
                    #expect(got == name as? String, "\(id) \(field) \(mode): \(String(describing: got))")
                }
            case "hasRatio":
                #expect((sut.calculateTapToneRatio() != nil) == want as? Bool, "\(id) \(field)")
            case "definitive":
                let info = sut.definitiveModeInfo()
                for (mode, entry) in want as! [String: Any] {
                    let got = info[modes[mode]!]
                    if let entry = entry as? [String: Any] {
                        #expect(got.map { Double($0.frequency) } == (entry["hz"] as! NSNumber).doubleValue, "\(id) \(field) \(mode) hz")
                        #expect(got?.isOverride == entry["isOverride"] as? Bool, "\(id) \(field) \(mode) isOverride")
                    } else {
                        #expect(got == nil, "\(id) \(field) \(mode): \(String(describing: got))")
                    }
                }
            case "materialPeakMode":
                let fL = sut.selectedLongitudinalPeak
                #expect(fL != nil, "\(id) \(field): a captured fL peak")
                #expect(fL.map { modeName(sut.peakMode(for: $0)) } == want as? String, "\(id) \(field)")
            case "selectedIsAuto":
                #expect((sut.selectedPeakIDs == sut.guitarModeSelectedPeakIDs(from: sut.allPeaks)) == want as? Bool, "\(id) \(field)")
            default:
                Issue.record("\(id): unknown field \(field)")
            }
        }
    }

    @Test(arguments: ids())
    func annotationState(_ id: String) throws {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let saved = (TapDisplaySettings.measurementType, TapDisplaySettings.showUnknownModes)
        defer { (TapDisplaySettings.measurementType, TapDisplaySettings.showUnknownModes) = saved }

        let ids = (row["peakIds"] as! [String: String]).mapValues { UUID(uuidString: $0)! }
        let context = Context(sut: makeStepsAnalyzer(), ids: ids)
        let files = row["files"] as! [String: Any]
        for step in row["steps"] as! [[String: Any]] {
            if let fields = step["check"] as? [String: Any] {
                Self.check(fields, context, id)
            } else {
                #expect(try Self.run(step, context, files: files), "\(id): unknown step \(step)")
            }
        }
        Self.check(row["expect"] as! [String: Any], context, id)
    }
}

/// The visibility enum itself — Swift's UI type: its cycle order and its icons.
@Suite("AnnotationVisibilityMode")
struct AnnotationVisibilityModeTests {

    // The .next cycle on the AnnotationVisibilityMode enum itself: all → selected → none → all.
    @Test func annotationVisibilityCycle_allToSelectedToNoneToAll() {
        var mode = AnnotationVisibilityMode.all
        mode = mode.next
        #expect(mode == .selected)
        mode = mode.next
        #expect(mode == .none)
        mode = mode.next
        #expect(mode == .all)
    }

    // Every case of AnnotationVisibilityMode must supply a non-empty SF Symbol name.
    @Test func annotationVisibility_iconNames_nonEmpty() {
        for mode in AnnotationVisibilityMode.allCases {
            #expect(!mode.iconName.isEmpty, "Icon name for \(mode) should not be empty")
        }
    }
}
