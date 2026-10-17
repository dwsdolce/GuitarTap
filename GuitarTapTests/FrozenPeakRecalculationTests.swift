//
//  FrozenPeakRecalculationTests.swift
//  GuitarTapTests
//
//  Frozen peaks: Re-analyze's re-detection, Peak Min's projection, and what a load, a live frame, a
//  capture, Save and Redo do to a measurement's peaks and their per-peak state — each through the app's
//  own path. A measurement is put in place by writing a .guitartap document and loading it as the app
//  loads a file. The shared cases in `frozen-peak-recalc.json`, the same as Python and the web.
//
// @parity test/frozen-peak-recalc

import Testing
import Foundation
@testable import GuitarTap

private final class FrozenPeaksAnchor {}

@Suite("FrozenPeakRecalculation", .serialized)
@MainActor
struct FrozenPeakRecalculationTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: FrozenPeaksAnchor.self).url(forResource: "frozen-peak-recalc", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids(_ group: String) -> [String] {
        (data[group] as! [[String: Any]]).map { $0["id"] as! String }
    }

    static func row(_ group: String, _ id: String) -> [String: Any] {
        (data[group] as! [[String: Any]]).first { $0["id"] as! String == id }!
    }

    static func f(_ v: Any?) -> Float { (v as! NSNumber).floatValue }

    // MARK: - The document a load step describes

    /// What a case's run keeps between steps: the ids a load wrote and the state a mark recorded.
    final class Run {
        var nextID = 1
        var loadedIDs: [UUID] = []
        var markedIDs: [UUID] = []
        var markedSelection: Set<UUID> = []
        var markedTapEntries: [[UUID]] = []
        var markedTapSelections: [[UUID]] = []

        func newID() -> String {
            defer { nextID += 1 }
            return String(format: "00000000-0000-0000-0000-%012d", nextID)
        }
    }

    static func snapshot(_ spec: [String: Any]?, type: String) -> [String: Any] {
        let (magnitudes, frequencies) = spec.map { PeakFindingTests.spectrum($0) }
            ?? ([Float](repeating: -100, count: 4), [0, 100, 200, 300])
        return ["frequencies": frequencies, "magnitudes": magnitudes,
                "minFreq": 0, "maxFreq": 600, "minDB": -100, "maxDB": 0, "isLogarithmic": false,
                "measurementType": type, "guitarType": String(type.split(separator: " ")[0])]
    }

    /// The peaks of a load step, written as the file writes them; returns them with each one's id by frequency.
    static func peaks(_ list: [[Any]], _ run: Run) -> (json: [[String: Any]], ids: [(Float, String)]) {
        var json: [[String: Any]] = [], ids: [(Float, String)] = []
        for p in list {
            let hz = f(p[0]), id = run.newID()
            json.append(["id": id, "frequency": hz, "magnitude": f(p[1]), "quality": 10,
                         "bandwidth": hz / 10, "timestamp": "2026-01-01T00:00:00Z"])
            ids.append((hz, id))
        }
        return (json, ids)
    }

    static func id(_ hz: Any, in ids: [(Float, String)]) -> String {
        ids.first { abs($0.0 - f(hz)) <= 1 }!.1
    }

    static func document(_ load: [String: Any], _ run: Run) -> [String: Any] {
        let type = load["type"] as! String
        let snap = snapshot(load["spectrum"] as? [String: Any], type: type)
        let (peakJSON, ids) = peaks(load["peaks"] as! [[Any]], run)
        var doc: [String: Any] = ["id": run.newID(), "timestamp": "2026-01-01T00:00:00Z", "peaks": peakJSON]
        if load["spectrum"] != nil { doc["spectrumSnapshot"] = snap }
        if let selected = load["selected"] as? [Any] { doc["selectedPeakIDs"] = selected.map { id($0, in: ids) } }
        if let modified = load["userModified"] as? Bool { doc["userModifiedSelection"] = modified }
        if let overrides = load["overrides"] as? [String: String] {
            doc["peakModeOverrides"] = overrides.flatMap { hz, label -> [Any] in
                [id(Double(hz)!, in: ids), ["label": label, "type": "assigned"]]
            }
        }
        if let offsets = load["offsets"] as? [String: [Double]] {
            doc["peakAnnotationOffsets"] = offsets.flatMap { hz, xy -> [Any] in
                [id(Double(hz)!, in: ids), ["absFreqHz": xy[0], "absDB": xy[1]]]
            }
        }
        if let entries = load["tapEntries"] as? [[String: Any]] {
            doc["tapEntries"] = entries.enumerated().map { i, e -> [String: Any] in
                let (json, entryIDs) = peaks(e["peaks"] as! [[Any]], run)
                return ["id": run.newID(), "tapIndex": i + 1, "snapshot": snap, "peaks": json,
                        "selectedPeakIDs": (e["selected"] as! [Any]).map { id($0, in: entryIDs) }]
            }
        }
        run.loadedIDs = ids.map { UUID(uuidString: $0.1)! }
        return doc
    }

    // MARK: - Peaks named by frequency

    /// Every peak the state can name: the measurement's peaks and a material measurement's identified ones.
    static func knownPeaks(_ sut: TapToneAnalyzer) -> [ResonantPeak] { sut.allPeaks + sut.materialIdentifiedPeaks }

    static func peak(at hz: Any, _ sut: TapToneAnalyzer) -> ResonantPeak {
        knownPeaks(sut).first { abs($0.frequency - f(hz)) <= 1 }!
    }

    static func sameFrequencies(_ got: [Float], _ want: Any?) -> Bool {
        let w = (want as! [Any]).map { f($0) }.sorted()
        let g = got.sorted()
        return g.count == w.count && zip(g, w).allSatisfy { abs($0 - $1) <= 1 }
    }

    /// A UUID-keyed map, by its peaks' frequencies, against the case's frequency-keyed one.
    static func sameMap<V>(_ got: [UUID: V], _ want: [String: Any], _ sut: TapToneAnalyzer,
                           _ equal: (V, Any) -> Bool) -> Bool {
        guard got.count == want.count else { return false }
        return got.allSatisfy { id, value in
            guard let p = knownPeaks(sut).first(where: { $0.id == id }),
                  let key = want.keys.first(where: { abs(Float(Double($0)!) - p.frequency) <= 1 }) else { return false }
            return equal(value, want[key]!)
        }
    }

    // MARK: - Steps and checks

    static func check(_ fields: [String: Any], _ sut: TapToneAnalyzer, _ run: Run, _ id: String) {
        for (field, want) in fields {
            switch field {
            case "peaks":
                #expect(sameFrequencies(sut.allPeaks.map(\.frequency), want), "\(id) \(field): \(sut.allPeaks.map(\.frequency))")
            case "shown":
                #expect(sameFrequencies(sut.peaksAbovePeakMin.map(\.frequency), want), "\(id) \(field): \(sut.peaksAbovePeakMin.map(\.frequency))")
            case "selected":
                #expect(sameFrequencies(sut.selectedPeaks.map(\.frequency), want), "\(id) \(field): \(sut.selectedPeaks.map(\.frequency))")
            case "overrides":
                #expect(sameMap(sut.peakModeOverrides, want as! [String: Any], sut) { $0 == $1 as? String },
                        "\(id) \(field): \(sut.peakModeOverrides)")
            case "offsets":
                #expect(sameMap(sut.peakAnnotationOffsets, want as! [String: Any], sut) { point, xy in
                    let w = xy as! [Double]
                    return Double(point.x) == w[0] && Double(point.y) == w[1]
                }, "\(id) \(field): \(sut.peakAnnotationOffsets)")
            case "labels":
                for (hz, label) in want as! [String: String] {
                    let p = knownPeaks(sut).first { abs($0.frequency - Float(Double(hz)!)) <= 1 }
                    #expect(p.map { sut.effectiveModeLabel(for: $0) } == label, "\(id) \(field) \(hz): \(String(describing: p.map { sut.effectiveModeLabel(for: $0) }))")
                }
            case "modes":
                let modes = Dictionary(uniqueKeysWithValues: sut.identifiedModes.map { ($0.peak.id, $0.mode.rawValue) })
                #expect(sameMap(modes, want as! [String: Any], sut) { $0 == $1 as? String }, "\(id) \(field): \(modes)")
            case "tapEntries":
                let wanted = want as! [[String: Any]]
                #expect(sut.tapEntries.count == wanted.count, "\(id) \(field): count")
                for (e, w) in zip(sut.tapEntries, wanted) {
                    #expect(sameFrequencies(e.peaks.map(\.frequency), w["peaks"]), "\(id) \(field) peaks")
                    let selected = e.peaks.filter { e.selectedPeakIDs.contains($0.id) }.map(\.frequency)
                    #expect(sameFrequencies(selected, w["selected"]), "\(id) \(field) selected")
                }
            case "idsAsMarked":
                #expect((sut.allPeaks.map(\.id) == run.markedIDs) == want as? Bool, "\(id) \(field)")
            case "selectedIdsAsMarked":
                #expect((sut.selectedPeakIDs == run.markedSelection) == want as? Bool, "\(id) \(field)")
            case "tapEntriesAsMarked":
                let same = sut.tapEntries.map { $0.peaks.map(\.id) } == run.markedTapEntries
                    && sut.tapEntries.map(\.selectedPeakIDs) == run.markedTapSelections
                #expect(same == want as? Bool, "\(id) \(field)")
            case "idsAsLoaded":
                #expect((Set(sut.allPeaks.map(\.id)) == Set(run.loadedIDs)) == want as? Bool, "\(id) \(field)")
            case "canReanalyze":
                #expect(sut.canReanalyze == want as? Bool, "\(id) \(field)")
            case "complete":
                #expect(sut.isMeasurementComplete == want as? Bool, "\(id) \(field)")
            case "phase":
                #expect(sut.materialTapPhase.rawValue == want as? String, "\(id) \(field): \(sut.materialTapPhase)")
            case "fL", "fC":
                let p = field == "fL" ? sut.selectedLongitudinalPeak : sut.selectedCrossPeak
                if want is NSNull {
                    #expect(p == nil, "\(id) \(field): \(String(describing: p?.frequency))")
                } else {
                    #expect(p.map { abs($0.frequency - f(want)) <= 1 } == true, "\(id) \(field): \(String(describing: p?.frequency))")
                }
            case "materialPeaks":
                #expect(sameFrequencies(sut.materialIdentifiedPeaks.map(\.frequency), want), "\(id) \(field)")
            case "saved":
                let w = want as! [String: Any]
                guard let saved = sut.savedMeasurements.last else { Issue.record("\(id): nothing saved"); continue }
                if let peaks = w["peaks"] {
                    #expect(sameFrequencies(saved.peaks.map(\.frequency), peaks), "\(id) saved peaks")
                }
                if let all = w["selectedAll"] as? Bool {
                    #expect((Set(saved.selectedPeakIDs ?? []) == Set(saved.peaks.map(\.id))) == all, "\(id) saved selectedAll")
                }
            default:
                Issue.record("\(id): unknown field \(field)")
            }
        }
    }

    static func step(_ step: [String: Any], _ sut: TapToneAnalyzer, _ run: Run, _ id: String) throws {
        if let load = step["load"] as? [String: Any] {
            let data = try JSONSerialization.data(withJSONObject: [document(load, run)])
            sut.loadMeasurement(try #require(try TapToneAnalyzer.decodeMeasurements(data).first))
        } else if step["reanalyze"] as? Bool == true {
            sut.reanalyzePeaks()
        } else if let hz = step["toggleSelection"] {
            sut.togglePeakSelection(peak(at: hz, sut).id)
        } else if let name = step["nameMode"] as? [String: Any] {
            sut.setModeOverride(name["label"] as! String, for: peak(at: name["at"]!, sut).id)
        } else if let drag = step["dragLabel"] as? [String: Any] {
            let xy = drag["to"] as! [Double]
            sut.updateAnnotationOffset(for: peak(at: drag["at"]!, sut).id, offset: CGPoint(x: xy[0], y: xy[1]))
        } else if let spec = step["liveFrame"] as? [String: Any] {
            let (magnitudes, frequencies) = PeakFindingTests.spectrum(spec)
            sut.fftAnalyzer.isRunning = true   // a frame comes only from the running engine
            sut.analyzeMagnitudes(magnitudes, frequencies: frequencies, peakMagnitude: magnitudes.max()!)
        } else if step["save"] as? Bool == true {
            sut.saveMeasurement()
        } else if step["loadSaved"] as? Bool == true {
            sut.loadMeasurement(try #require(sut.savedMeasurements.last))
        } else if step["mark"] as? Bool == true {
            run.markedIDs = sut.allPeaks.map(\.id)
            run.markedSelection = sut.selectedPeakIDs
            run.markedTapEntries = sut.tapEntries.map { $0.peaks.map(\.id) }
            run.markedTapSelections = sut.tapEntries.map(\.selectedPeakIDs)
        } else {
            #expect(runAnalyzerStep(step, on: sut), "\(id): unknown step \(step)")
        }
    }

    @Test(arguments: ids("cases"))
    func frozenPeaks(_ id: String) throws {
        let row = Self.row("cases", id)
        let saved = (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc)
        defer { (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc) = saved }

        let sut = makeStepsAnalyzer()
        let run = Run()
        for step in row["steps"] as! [[String: Any]] {
            if let fields = step["check"] as? [String: Any] {
                Self.check(fields, sut, run, id)
            } else {
                try Self.step(step, sut, run, id)
            }
        }
        Self.check(row["expect"] as! [String: Any], sut, run, id)
    }

    @Test(arguments: ids("tapEntryModes"))
    func tapEntryModes(_ id: String) {
        let row = Self.row("tapEntryModes", id)
        let peaks = (row["peaks"] as! [[Any]]).map { ResonantPeak(frequency: Self.f($0[0]), magnitude: Self.f($0[1])) }
        let selected = (row["selected"] as! [Any]).map { hz in peaks.first { abs($0.frequency - Self.f(hz)) <= 1 }!.id }
        let snap = SpectrumSnapshot(frequencies: [], magnitudes: [], minFreq: 0, maxFreq: 600,
                                    minDB: -100, maxDB: 0, isLogarithmic: false)
        let entry = TapEntry(id: UUID(), tapIndex: 1, snapshot: snap, peaks: peaks, selectedPeakIDs: selected)
        let modes = entry.resolvedModePeaks(guitarType: GuitarType(rawValue: row["guitarType"] as! String))
        let got = Dictionary(uniqueKeysWithValues: modes.map { ($0.key.rawValue, $0.value.frequency) })
        let want = (row["expect"] as! [String: Any]).mapValues { Self.f($0) }
        #expect(got == want, "\(id): \(got)")
    }
}
