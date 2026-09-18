//
//  GenerateParityOracle.swift
//  GuitarTapTests
//
//  Mints the shared parity oracle from the canonical Swift pipeline.
//
//  Swift mints it because Swift is canonical. A tracking edition minting the oracle
//  would make the file record what the tracking edition does, and the day the two
//  disagreed there would be no way to say which was wrong.
//
//  This is NOT part of a normal test run — it is disabled unless GENERATE_PARITY_ORACLE
//  is set, because it rewrites a committed file:
//
//      GENERATE_PARITY_ORACLE=1 xcodebuild test -scheme GuitarTap \
//          -only-testing:GuitarTapTests/GenerateParityOracle
//
//  Then, from the Swift repo:
//      ORACLE_SRC=~/src/guitar-tap-project ./Tooling/sync-oracle.sh --publish
//  commit the hub, then run sync-oracle.sh in the Python (Tooling/) and web (tooling/) repos.
//
//  It RECOMPUTES VALUES IN PLACE rather than writing a fresh document: the file is read
//  as raw JSON, only the numeric leaves are replaced, and everything else — key order
//  aside — survives. That keeps the prose (_note, _perTapNote, _ringOutNote), which is
//  where the reasons behind the odd-looking numbers live, and it makes the diff after a
//  regeneration exactly the set of values the algorithm moved.
//
//  Run it after any intentional algorithm change, as the Swift half of the lockstep
//  update the parity discipline already requires.
//
// @parity none - the oracle is minted only by the canonical edition; a counterpart in a
// tracking edition would mint what the tracking edition does, which is the inversion this
// design exists to prevent. The loader it writes for (ParityOracle.swift) IS parity-mapped.

import Testing
import Foundation
@testable import GuitarTap

@Suite("GenerateParityOracle")
struct GenerateParityOracleTests {

    /// The vendored oracle in the SOURCE tree (not the built test bundle, which is a copy).
    private static var sourceOracleURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("parity-oracle.json")
    }

    /// Values are rounded so regeneration produces a stable, readable file: a raw Float
    /// widened to Double prints as 87.30731010437012, which would churn the diff without
    /// saying anything (every tolerance here is >= 0.03).
    private static func round5(_ value: Float) -> Double {
        (Double(value) * 100_000).rounded() / 100_000
    }

    /// Replace frequency/magnitude/q in an existing array of peak dictionaries, keyed by
    /// role. Keys the case does not carry (q on the guitar cases) are left absent.
    private static func updatePeaks(
        _ existing: [[String: Any]],
        with computed: [String: (frequency: Float, magnitude: Float, quality: Float?)]
    ) -> [[String: Any]] {
        existing.map { peak in
            var out = peak
            guard let role = peak["role"] as? String, let got = computed[role] else { return out }
            out["frequency"] = round5(got.frequency)
            out["magnitude"] = round5(got.magnitude)
            if out["q"] != nil, let quality = got.quality {
                out["q"] = round5(quality)
            }
            return out
        }
    }

    private static func guitarModePeaks(
        _ sut: TapToneAnalyzer
    ) -> [String: (frequency: Float, magnitude: Float, quality: Float?)] {
        var out: [String: (frequency: Float, magnitude: Float, quality: Float?)] = [:]
        let roles: [(String, GuitarMode)] = [("air", .air), ("top", .top), ("back", .back)]
        for (role, mode) in roles {
            if let peak = sut.getPeak(for: mode) {
                out[role] = (peak.frequency, peak.magnitude, peak.quality)
            }
        }
        return out
    }

    private static func materialPeaks(
        _ sut: TapToneAnalyzer
    ) -> [String: (frequency: Float, magnitude: Float, quality: Float?)] {
        var out: [String: (frequency: Float, magnitude: Float, quality: Float?)] = [:]
        if let p = sut.selectedLongitudinalPeak { out["longitudinal"] = (p.frequency, p.magnitude, p.quality) }
        if let p = sut.selectedCrossPeak { out["cross"] = (p.frequency, p.magnitude, p.quality) }
        if let p = sut.selectedFlcPeak { out["flc"] = (p.frequency, p.magnitude, p.quality) }
        return out
    }

    /// Short git SHA of the working tree, or "unknown" when git is unavailable (a
    /// sandboxed run). Never fails the generation — the stamp is provenance, not data.
    private static func gitShortSHA() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", URL(fileURLWithPath: #filePath).deletingLastPathComponent().path,
                             "rev-parse", "--short", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let sha = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let sha, !sha.isEmpty { return sha }
        } catch {
            // fall through
        }
        return "unknown"
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GENERATE_PARITY_ORACLE"] != nil))
    func generateParityOracle() async throws {
        let url = Self.sourceOracleURL
        let data = try Data(contentsOf: url)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var playback = root["filePlayback"] as? [String: Any],
              var gated = root["gatedFft"] as? [String: Any] else {
            Issue.record("parity-oracle.json is not the expected shape")
            return
        }

        let bundle = Bundle(for: OracleBundleMarker.self)
        func fixtureURL(_ caseDict: [String: Any]) throws -> URL {
            let file = caseDict["fixture"] as? String ?? ""
            let stem = (file as NSString).deletingPathExtension
            let ext = (file as NSString).pathExtension
            guard let found = bundle.url(forResource: stem, withExtension: ext) else {
                throw OracleError.missingFixture(file)
            }
            return found
        }
        func calibrationURL(_ caseDict: [String: Any]) -> URL? {
            guard let file = caseDict["calibration"] as? String else { return nil }
            let stem = (file as NSString).deletingPathExtension
            let ext = (file as NSString).pathExtension
            return bundle.url(forResource: stem, withExtension: ext)
        }
        func settings(_ caseDict: [String: Any]) -> [String: Any] {
            caseDict["settings"] as? [String: Any] ?? [:]
        }

        // ---------------------------------------------------------------- guitar cases
        for name in ["REG-G1", "REG-G2"] {
            guard var caseDict = playback[name] as? [String: Any] else { continue }
            let set = settings(caseDict)
            let sut = TapToneAnalyzer.forTesting()
            sut.peakMinThreshold = Float(set["peakMinThreshold"] as? Double ?? -76)
            sut.tapDetectionThreshold = Float(set["tapDetectionThreshold"] as? Double ?? -40)
            let taps = set["numberOfTaps"] as? Int ?? 1
            try await sut.playFileForTesting(url: try fixtureURL(caseDict),
                                             measurementType: .generic,
                                             numberOfTaps: taps)

            let computed = Self.guitarModePeaks(sut)
            if let peaks = caseDict["peaks"] as? [[String: Any]] {
                caseDict["peaks"] = Self.updatePeaks(peaks, with: computed)
            }
            if let averaged = caseDict["averagedPeaks"] as? [[String: Any]] {
                caseDict["averagedPeaks"] = Self.updatePeaks(averaged, with: computed)
            }
            if let perTap = caseDict["perTap"] as? [[String: Any]] {
                caseDict["perTap"] = perTap.enumerated().map { index, row in
                    var outRow = row
                    guard index < sut.tapEntries.count,
                          let rowPeaks = row["peaks"] as? [[String: Any]] else { return outRow }
                    let modePeaks = sut.tapEntries[index].resolvedModePeaks()
                    var byRole: [String: (frequency: Float, magnitude: Float, quality: Float?)] = [:]
                    let roles: [(String, GuitarMode)] = [("air", .air), ("top", .top), ("back", .back)]
                    for (role, mode) in roles {
                        if let peak = modePeaks[mode] {
                            byRole[role] = (peak.frequency, peak.magnitude, peak.quality)
                        }
                    }
                    outRow["peaks"] = Self.updatePeaks(rowPeaks, with: byRole)
                    return outRow
                }
            }
            if caseDict["ringOutSec"] != nil, let decay = sut.currentDecayTime {
                caseDict["ringOutSec"] = Self.round5(decay)
            }
            playback[name] = caseDict
        }

        // -------------------------------------------------------------- material cases
        for name in ["REG-B1", "REG-P1", "REG-P2"] {
            guard var caseDict = playback[name] as? [String: Any] else { continue }
            let set = settings(caseDict)
            let isBrace = (set["measurementType"] as? String)?.contains("Brace") == true

            let originalMeasureFlc = TapDisplaySettings.measureFlc
            TapDisplaySettings.measureFlc = set["measureFlc"] as? Bool ?? false
            defer { TapDisplaySettings.measureFlc = originalMeasureFlc }

            let sut = TapToneAnalyzer.forTesting()
            sut.tapDetectionThreshold = Float(set["tapDetectionThreshold"] as? Double ?? -40)
            try await sut.playFileForTesting(url: try fixtureURL(caseDict),
                                             measurementType: isBrace ? .brace : .plate,
                                             numberOfTaps: set["numberOfTaps"] as? Int ?? 1,
                                             calibrationURL: calibrationURL(caseDict))

            var computed = Self.materialPeaks(sut)
            if isBrace, let dominant = sut.longitudinalPeaks.first {
                // Brace asserts the dominant longitudinal peak, not the selection.
                computed["longitudinal"] = (dominant.frequency, dominant.magnitude, dominant.quality)
            }
            if let peaks = caseDict["peaks"] as? [[String: Any]] {
                caseDict["peaks"] = Self.updatePeaks(peaks, with: computed)
            }
            playback[name] = caseDict
        }

        // ----------------------------------------------------------------- gated FFT
        let fft = RealtimeFFTAnalyzer()
        let sampleRate: Double = 48000
        for name in gated.keys.sorted() {
            guard var caseDict = gated[name] as? [String: Any] else { continue }  // skips note keys
            let sampleCount = Int(sampleRate * 0.4)
            var signal = [Float](repeating: 0, count: sampleCount)

            if (caseDict["signal"] as? String) != "silence" {
                let tones = (caseDict["tones"] as? [[Double]]) ?? []
                for i in 0..<sampleCount {
                    let t = Double(i) / sampleRate
                    var sample = 0.0
                    for tone in tones where tone.count >= 2 {
                        sample += tone[1] * sin(2.0 * .pi * tone[0] * t)
                    }
                    signal[i] = Float(sample)
                }
            }

            let (mags, freqs) = fft.computeGatedFFT(samples: signal, sampleRate: sampleRate)

            if var expected = caseDict["expected"] as? [[String: Any]] {
                for i in expected.indices {
                    guard let hz = expected[i]["hz"] as? Double,
                          let db = Self.magnitudeAt(Float(hz), magnitudes: mags, frequencies: freqs)
                    else { continue }
                    expected[i]["db"] = (Double(db) * 100).rounded() / 100  // 2 dp, as published
                }
                caseDict["expected"] = expected
                if caseDict["deltaDb"] != nil, expected.count >= 2,
                   let first = expected.first?["db"] as? Double,
                   let last = expected.last?["db"] as? Double {
                    caseDict["deltaDb"] = (( last - first) * 100).rounded() / 100
                }
            }
            gated[name] = caseDict
        }

        root["filePlayback"] = playback
        root["gatedFft"] = gated
        root["oracleVersion"] = Self.gitShortSHA()
        root["generatedAt"] = ISO8601DateFormatter().string(from: Date())

        let out = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try out.write(to: url)
        print("Wrote \(url.path) — review the diff, then publish with Tooling/sync-oracle.sh --publish")
    }

    private static func magnitudeAt(_ targetHz: Float,
                                    magnitudes: [Float],
                                    frequencies: [Float]) -> Float? {
        guard !frequencies.isEmpty else { return nil }
        var bestIdx = 0
        var bestDist = Float.greatestFiniteMagnitude
        for (i, f) in frequencies.enumerated() where abs(f - targetHz) < bestDist {
            bestDist = abs(f - targetHz)
            bestIdx = i
        }
        return magnitudes[bestIdx]
    }
}

private enum OracleError: Error {
    case missingFixture(String)
}

/// Anchors Bundle(for:) to the test bundle holding the WAV fixtures.
private class OracleBundleMarker: NSObject {}
