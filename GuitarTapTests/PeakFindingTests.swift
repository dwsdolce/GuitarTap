//
//  PeakFindingTests.swift
//  GuitarTapTests
//
//  Peak finding, near-duplicate removal, spectrum averaging, guitar auto-selection and the full-set save,
//  against the shared case file, `peaks.json` — the same cases the Python and web suites run.
//
//  findPeaks must return one peak per spectral feature: the Top/Back overlap case (32768 bins, so peaks
//  7 Hz apart can both be detected) pins three peaks for three features. A saved guitar measurement holds
//  the full set found down to the -100 dB floor, not just what Peak Min shows, so a reloaded measurement
//  can reveal peaks below its capture-time Peak Min; a loaded measurement is saved as it is.
//
// @parity test/peaks

import Foundation
import Testing
@testable import GuitarTap

private final class PeakFindingTestsAnchor {}

@Suite("PeakFinding", .serialized)
struct PeakFindingTests {

    static let data: [String: Any] = {
        let url = Bundle(for: PeakFindingTestsAnchor.self).url(forResource: "peaks", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()
    static func rows(_ key: String) -> [[String: Any]] { data[key] as! [[String: Any]] }
    static func row(_ key: String, _ id: String) -> [String: Any] { rows(key).first { $0["id"] as! String == id }! }
    static func f(_ v: Any?) -> Float { (v as! NSNumber).floatValue }

    /// `|actual − expected| ≤ relative·|expected| + absolute`.
    static func close(_ actual: Double, _ expected: Any?) -> Bool {
        let tol = data["tolerance"] as! [String: Double]
        let e = (expected as! NSNumber).doubleValue
        return abs(actual - e) <= tol["relative"]! * abs(e) + tol["absolute"]!
    }

    /// A case's spectrum, built as the file describes it.
    static func spectrum(_ s: [String: Any]) -> (magnitudes: [Float], frequencies: [Float]) {
        let bins = s["binCount"] as! Int
        let spacing: Float = s["binSpacingHz"].map { f($0) } ?? Float((s["sampleRate"] as! Double) / 2) / Float(bins - 1)
        let freqs = (0..<bins).map { Float($0) * spacing }
        switch s["kind"] as! String {
        case "flat":
            return ([Float](repeating: f(s["value"]), count: bins), freqs)
        case "triangle":
            let peakBin = s["peakBin"] as! Int, peakDB = f(s["peakDB"]), slope = f(s["slopeDBPerBin"])
            return ((0..<bins).map { peakDB - slope * Float(abs($0 - peakBin)) }, freqs)
        default:
            let floor = f(s["noiseFloor"])
            var mags = [Float](repeating: floor, count: bins)
            for p in s["peaks"] as! [[String: Any]] {
                let hz = f(p["peakHz"]), db = f(p["peakDB"]), sigma = f(p["halfWidthHz"]) / 2.355
                for i in 0..<bins {
                    let d = freqs[i] - hz
                    mags[i] = max(mags[i], max(floor, db + (-d * d / (2 * sigma * sigma))))
                }
            }
            return (mags, freqs)
        }
    }

    static func findPeaks(_ row: [String: Any]) -> [ResonantPeak] {
        TapDisplaySettings.guitarType = .generic
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        sut.peakMinThreshold = f(row["peakMinThreshold"])
        sut.minFrequency = f(row["minFrequency"])
        sut.maxFrequency = f(row["maxFrequency"])
        let (m, fr) = spectrum(row["spectrum"] as! [String: Any])
        return sut.findPeaks(magnitudes: m, frequencies: fr, peakMinOverride: row["peakMinOverride"].map { f($0) })
    }

    @Test(arguments: rows("findPeaks").map { $0["id"] as! String })
    func findPeaks(_ id: String) {
        let row = Self.row("findPeaks", id)
        let peaks = Self.findPeaks(row)
        let expected = row["expect"] as! [[String: Any]]
        #expect(peaks.count == expected.count, "\(id): \(peaks.count) peaks \(peaks.map(\.frequency))")
        for (p, e) in zip(peaks, expected) {
            #expect(Self.close(Double(p.frequency), e["frequency"]), "\(id): frequency \(p.frequency)")
            #expect(Self.close(Double(p.magnitude), e["magnitude"]), "\(id): magnitude \(p.magnitude)")
            #expect(Self.close(Double(p.quality), e["quality"]), "\(id): quality \(p.quality)")
            #expect(Self.close(Double(p.bandwidth), e["bandwidth"]), "\(id): bandwidth \(p.bandwidth)")
            #expect(p.pitchNote == e["pitchNote"] as? String, "\(id): pitchNote \(String(describing: p.pitchNote))")
            #expect(Self.close(p.pitchCents ?? .nan, e["pitchCents"]), "\(id): pitchCents \(String(describing: p.pitchCents))")
            #expect(Self.close(p.pitchFrequency ?? .nan, e["pitchFrequency"]), "\(id): pitchFrequency \(String(describing: p.pitchFrequency))")
        }
    }

    @Test(arguments: rows("removeDuplicatePeaks").map { $0["id"] as! String })
    func removeDuplicatePeaks(_ id: String) {
        let row = Self.row("removeDuplicatePeaks", id)
        let peaks = (row["peaks"] as! [[String: Any]]).map { ResonantPeak(frequency: Self.f($0["frequency"]), magnitude: Self.f($0["magnitude"])) }
        let kept = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting()).removeDuplicatePeaks(peaks)
        #expect(kept.map { k in peaks.firstIndex { $0.id == k.id }! } == row["expect"] as! [Int], "\(id)")
    }

    @Test(arguments: rows("averageSpectra").map { $0["id"] as! String })
    func averageSpectra(_ id: String) {
        let row = Self.row("averageSpectra", id)
        let taps = (row["taps"] as! [[String: Any]]).map { t in
            ((t["magnitudes"] as! [NSNumber]).map(\.floatValue), (t["frequencies"] as! [NSNumber]).map(\.floatValue), Date())
        }
        let (m, fr) = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting()).averageSpectra(from: taps)
        let e = row["expect"] as! [String: [NSNumber]]
        #expect(m.count == e["magnitudes"]!.count && fr.count == e["frequencies"]!.count, "\(id): lengths")
        for (a, b) in zip(m, e["magnitudes"]!) { #expect(Self.close(Double(a), b), "\(id): magnitude \(a)") }
        for (a, b) in zip(fr, e["frequencies"]!) { #expect(Self.close(Double(a), b), "\(id): frequency \(a)") }
    }

    @Test(arguments: rows("autoSelection").map { $0["id"] as! String })
    func autoSelection(_ id: String) {
        let row = Self.row("autoSelection", id)
        let peaks = Self.findPeaks(Self.row("findPeaks", row["findPeaks"] as! String))
        let names: [GuitarMode: String] = [.air: "air", .top: "top", .back: "back", .dipole: "dipole",
                                           .ringMode: "ringMode", .upperModes: "upperModes", .unknown: "unknown"]
        let modes = GuitarMode.classifyAll(peaks, guitarType: .generic)
        let selected = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting()).guitarModeSelectedPeakIDs(from: peaks)
        let e = row["expect"] as! [String: Any]
        #expect(peaks.map { names[modes[$0.id]!]! } == e["modes"] as! [String], "\(id): modes")
        #expect(peaks.indices.filter { selected.contains(peaks[$0].id) } == e["selected"] as! [Int], "\(id): selected")
    }

    @Test(arguments: rows("fullSetSave").map { $0["id"] as! String })
    func fullSetSave(_ id: String) throws {
        let row = Self.row("fullSetSave", id)
        TapDisplaySettings.measurementType = .generic
        let stem = ((row["fixture"] as! String) as NSString).deletingPathExtension
        let url = try #require(Bundle(for: PeakFindingTestsAnchor.self).url(forResource: stem, withExtension: "guitartap"))
        let arr = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        let sn = try #require(arr.first?["spectrumSnapshot"] as? [String: Any])
        func floats(_ b64: String) -> [Float] { Data(base64Encoded: b64)!.withUnsafeBytes { Array($0.bindMemory(to: Float32.self)) } }
        let mags = floats(sn["magnitudesData"] as! String), freqs = floats(sn["frequenciesData"] as! String)

        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        sut.setFrozenSpectrum(frequencies: freqs, magnitudes: mags)
        sut.isMeasurementComplete = true
        sut.minFrequency = Self.f(row["minFrequency"])
        sut.maxFrequency = Self.f(row["maxFrequency"])
        sut.peakMinThreshold = Self.f(row["peakMinThreshold"])
        sut.allPeaks = sut.findPeaks(magnitudes: mags, frequencies: freqs, peakMinOverride: TapToneAnalyzer.peakDetectionFloor)
        let air = Self.f(row["airHz"])
        let isAir = { (p: ResonantPeak) in abs(p.frequency - air) < 1 }
        let displayed = sut.peaksAbovePeakMin
        sut.loadedMeasurementPeaks = nil
        let saved = sut.guitarFullSavePeaks()
        let e = row["expect"] as! [String: Any]
        #expect(displayed.count == e["displayedCount"] as! Int, "\(id): displayed \(displayed.count)")
        #expect(saved.count == e["savedCount"] as! Int, "\(id): saved \(saved.count)")
        #expect(displayed.contains(where: isAir) == e["airDisplayed"] as! Bool, "\(id): Air displayed")
        #expect(saved.contains(where: isAir) == e["airSaved"] as! Bool, "\(id): Air saved")
        #expect(displayed.allSatisfy { d in saved.contains { $0.id == d.id } } == e["displayedAmongSaved"] as! Bool, "\(id): displayed among saved")
        #expect((Set(saved.map(\.id)).count == saved.count) == e["savedDistinctIds"] as! Bool, "\(id): each saved peak its own id")

        let loaded = Array(sut.allPeaks.prefix(row["loadedFirst"] as! Int))
        sut.allPeaks = loaded
        sut.loadedMeasurementPeaks = loaded
        let savedLoaded = sut.guitarFullSavePeaks()
        #expect(savedLoaded.count == e["loadedSavedCount"] as! Int, "\(id): loaded saved \(savedLoaded.count)")
        #expect((savedLoaded.map(\.id) == loaded.map(\.id)) == e["loadedSavedSame"] as! Bool, "\(id): loaded saved as it is")
    }
}
