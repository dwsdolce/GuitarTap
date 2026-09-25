//
//  PeakFixtureRegressionTests.swift
//  GuitarTapTests
//
//  D3 + D5 + D6 of Development/PEAK-FINDING-DUPLICATE-PEAKS.md (GuitarTapWeb).
//
//  Replays real captured spectra through findPeaks and pins the result against a
//  golden baseline.
//
//  D3 — no fixture may yield duplicate peaks.
//  D5 — the peak set must equal the step-2 baseline with the spurious twin removed:
//       same count, frequencies, magnitudes, Q, bandwidth, mode labels and selection.
//       This is what proves the fix removed ONLY the duplicate and moved nothing else.
//  D6 — `peak-baseline-expected.json` is byte-identical in all three repos, so all
//       three platforms passing D5 is three-way parity. There is no separate test.
//
//  Fixtures are one physical tap captured by all three apps (Swift, Python, web),
//  chosen so one file per platform proves the shared algorithm's behaviour.
//
//  Authored against the UNFIXED code: D3 fails on every fixture (one duplicate each)
//  and D5 fails on peak count until detection stops being interleaved with
//  classification.
//
// @parity test/peaks

import Testing
import Foundation
@testable import GuitarTap

private let kMinHz: Float = 30
private let kMaxHz: Float = 2000

/// Canonical mode token, shared verbatim with the Python and web expectations.
private func modeToken(_ mode: GuitarMode?) -> String {
    switch (mode ?? .unknown).normalized {
    case .air: return "air"
    case .top: return "top"
    case .back: return "back"
    case .dipole: return "dipole"
    case .ringMode: return "ring"
    case .upperModes: return "upper"
    default: return "unknown"
    }
}

// Anchors Bundle(for:) to the GuitarTapTests bundle so fixtures load on every destination
// (iPad/iPhone too), not just the macOS host: #filePath resolves to the build machine's source tree,
// which does not exist on a device. The synchronized GuitarTapTests folder already bundles the fixtures.
private final class FixtureAnchor {}

private func fixtureURL(_ name: String) throws -> URL {
    let stem = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    return try #require(Bundle(for: FixtureAnchor.self).url(forResource: stem, withExtension: ext))
}

private func floats(fromBase64 b64: String) -> [Float] {
    guard let data = Data(base64Encoded: b64) else { return [] }
    return data.withUnsafeBytes { Array($0.bindMemory(to: Float32.self)) }
}

/// Replays a fixture's own saved spectrum through the current findPeaks.
private func replay(fixture name: String) throws -> (peaks: [ResonantPeak], modes: [UUID: GuitarMode], selected: Set<UUID>) {
    let url = try fixtureURL(name)
    let data = try Data(contentsOf: url)
    let arr = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    let m = try #require(arr.first)
    let sn = try #require(m["spectrumSnapshot"] as? [String: Any])

    let freqs = floats(fromBase64: try #require(sn["frequenciesData"] as? String))
    let mags = floats(fromBase64: try #require(sn["magnitudesData"] as? String))
    let gtStr = (m["guitarType"] as? String) ?? "Generic"
    let peakMin = (m["peakMinThreshold"] as? NSNumber)?.floatValue ?? -60

    TapDisplaySettings.guitarType = GuitarType(rawValue: gtStr) ?? .generic
    let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
    sut.peakMinThreshold = peakMin
    sut.minFrequency = kMinHz
    sut.maxFrequency = kMaxHz

    let peaks = sut.findPeaks(magnitudes: mags, frequencies: freqs, minHz: kMinHz, maxHz: kMaxHz)
    return (peaks, GuitarMode.classifyAll(peaks), sut.guitarModeSelectedPeakIDs(from: peaks))
}

private struct ExpectedPeak: Decodable {
    let frequency: Double
    let magnitude: Double
    let quality: Double
    let bandwidth: Double
    let mode: String
    let selected: Bool
}

private struct ExpectedFixture: Decodable {
    let peakCount: Int
    let peaks: [ExpectedPeak]
}

private func loadExpected() throws -> [String: ExpectedFixture] {
    let url = try fixtureURL("peak-baseline-expected.json")
    return try JSONDecoder().decode([String: ExpectedFixture].self, from: try Data(contentsOf: url))
}

@Suite("FindPeaks — fixture regression")
struct PeakFixtureRegressionTests {

    // nonisolated so the @Test(arguments:) macro can read it from a nonisolated context — the test
    // target defaults to @MainActor (SWIFT_DEFAULT_ACTOR_ISOLATION), which otherwise makes this an
    // error under the Swift 6 language mode. It is an immutable Sendable [String], so this is safe.
    nonisolated static let fixtures = [
        "dws-2024-umik-1-swift-mac-1784225155.guitartap",
        "dws-2024-umik-1-python-mac-1784225140.guitartap",
        "dws-2024-umik-1-web-mac-1784225174.guitartap",
    ]

    // D3 — no real capture may produce two peaks for one spectral feature.
    @Test(arguments: fixtures)
    func fixtureHasNoDuplicatePeaks(_ name: String) throws {
        let (peaks, _, _) = try replay(fixture: name)
        #expect(!peaks.isEmpty, "\(name): no peaks replayed")

        var offenders: [String] = []
        for i in peaks.indices {
            for j in peaks.indices where j > i {
                let delta = abs(peaks[i].frequency - peaks[j].frequency)
                if delta < TapToneAnalyzer.peakProximityHz {
                    offenders.append(String(format: "%.5f Hz / %.5f Hz (%.5f apart)",
                                            peaks[i].frequency, peaks[j].frequency, delta))
                }
            }
        }
        #expect(offenders.isEmpty, "\(name): duplicate peaks — \(offenders.joined(separator: "; "))")
    }

    // D5 — golden baseline. The peak set must match the step-2 capture with the
    // twin removed, exactly. Any other delta means the fix changed more than the
    // duplicate and must halt the work (see section 4 of the plan).
    @Test(arguments: fixtures)
    func fixtureMatchesGoldenBaseline(_ name: String) throws {
        let expectedAll = try loadExpected()
        let expected = try #require(expectedAll[name], "no expectation recorded for \(name)")
        let (peaks, modes, selected) = try replay(fixture: name)

        #expect(peaks.count == expected.peakCount,
                "\(name): expected \(expected.peakCount) peaks, got \(peaks.count)")
        guard peaks.count == expected.peakCount else { return }

        // Compare in frequency order so ordering changes don't masquerade as value changes.
        let got = peaks.sorted { $0.frequency < $1.frequency }
        let want = expected.peaks.sorted { $0.frequency < $1.frequency }
        let tol = 1e-3

        for (g, w) in zip(got, want) {
            #expect(abs(Double(g.frequency) - w.frequency) < tol,
                    "\(name): frequency \(g.frequency) vs expected \(w.frequency)")
            #expect(abs(Double(g.magnitude) - w.magnitude) < tol,
                    "\(name): magnitude at \(w.frequency) Hz — \(g.magnitude) vs \(w.magnitude)")
            #expect(abs(Double(g.quality) - w.quality) < tol,
                    "\(name): Q at \(w.frequency) Hz — \(g.quality) vs \(w.quality)")
            #expect(abs(Double(g.bandwidth) - w.bandwidth) < tol,
                    "\(name): bandwidth at \(w.frequency) Hz — \(g.bandwidth) vs \(w.bandwidth)")
            #expect(modeToken(modes[g.id]) == w.mode,
                    "\(name): mode at \(w.frequency) Hz — \(modeToken(modes[g.id])) vs \(w.mode)")
            #expect(selected.contains(g.id) == w.selected,
                    "\(name): selection at \(w.frequency) Hz — \(selected.contains(g.id)) vs \(w.selected)")
        }
    }
}