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
//  This is NOT part of a normal test run — it is disabled unless the generate flag is
//  set, because it regenerates a committed file. Mint it through the wrapper:
//
//      ./Tooling/mint-oracle.sh
//
//  Do NOT hand-run the xcodebuild invocation. Three things about it are easy to get
//  wrong and ALL THREE produce "** TEST SUCCEEDED **" while minting nothing:
//
//    - the scheme is `guitar_tap`, not `GuitarTap` (that is a target name);
//    - `-only-testing` takes the TYPE name, GenerateParityOracleTests, not the
//      @Suite display name — a mismatch runs "Executed 0 tests" and still succeeds;
//    - xcodebuild does not forward the shell environment to a hosted test runner, so
//      the flag must be passed as TEST_RUNNER_GENERATE_PARITY_ORACLE. Unprefixed, the
//      test is simply skipped.
//
//  The wrapper gets all three right and then verifies a file was actually produced,
//  so a silent no-op cannot be mistaken for a clean run.
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
    /// READ from here: regeneration is in-place over the committed file, so the prose
    /// notes survive and a diff shows exactly the values the algorithm moved.
    private static var sourceOracleURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("parity-oracle.json")
    }

    /// Where the regenerated JSON is WRITTEN — which cannot be the source tree.
    ///
    /// This test bundle is hosted in the app (TEST_HOST), and the app has
    /// ENABLE_APP_SANDBOX = YES, so the test process inherits the app's sandbox and a
    /// write to the checkout fails with NSCocoaErrorDomain 513 / EPERM. Reads are
    /// permitted, which is why the source file above is still the input.
    ///
    /// So the generator emits to a permitted path and the wrapper copies it into the
    /// tree. Redirecting the write was chosen over turning the sandbox off for Debug:
    /// the suite should run against an app sandboxed the way the shipped one is.
    private static var outputURL: URL {
        if let out = ProcessInfo.processInfo.environment["PARITY_ORACLE_OUT"], !out.isEmpty {
            return URL(fileURLWithPath: out)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("parity-oracle.json")
    }

    /// The stored form of a computed value: the SHORTEST decimal that recovers this exact
    /// Float.
    ///
    /// Not a rounding. `String(Float)` gives the shortest round-tripping representation,
    /// so the text stays short — 87.30731, not the 87.30731010437012 you get by widening
    /// to Double first and printing the binary tail — while `Float(text)` returns the
    /// identical bits. That is what lets the regression tolerance be literally zero:
    /// the test compares Floats with ==, no rounding step on either side.
    ///
    /// This replaced a fixed 5-decimal rounding. That was lossless for the values here
    /// only by accident of magnitude (5 dp on values in the tens-to-hundreds exceeds
    /// Float32's ~7.2 significant digits); a much smaller value would have quietly lost
    /// bits, and under a zero tolerance that reads as a test that can never pass.
    private static func stored(_ value: Float) -> Double {
        Double(String(value)) ?? Double(value)
    }

    /// `stored`, but a non-finite value becomes the string JSON can carry: "-Infinity" /
    /// "Infinity" / "NaN" — the same encoding Python, the web and the hub read and write.
    private static func storedAllowingNonFinite(_ value: Float) -> Any {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value > 0 ? "Infinity" : "-Infinity" }
        return stored(value)
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
            out["frequency"] = stored(got.frequency)
            out["magnitude"] = stored(got.magnitude)
            if out["q"] != nil, let quality = got.quality {
                out["q"] = stored(quality)
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
    /// The Swift commit these numbers were minted from.
    ///
    /// Supplied by the wrapper, because this process cannot ask git itself: the test
    /// bundle runs inside the app's sandbox, which denies spawning a subprocess, and the
    /// failure was silent — every mint stamped "unknown". That is not cosmetic. The
    /// committed oracle still carried the placeholder `TBD-swift-commit-sha`, so when its
    /// numbers were found to have drifted there was no way to say WHICH build produced
    /// them, or when. This field is how the next person dates the goldens.
    /// Edition, OS and arch — the key every edition's self-baseline is filed under.
    ///
    /// Deliberately excludes the Swift and Xcode versions: a toolchain upgrade that moves the
    /// numbers is precisely the event the zero-tolerance bar exists to catch, and keying on the
    /// version would let the baseline follow the upgrade and report nothing.
    private static func configuration() -> [String: String] {
    #if arch(arm64)
        let arch = "arm64"
    #elseif arch(x86_64)
        let arch = "x86_64"
    #else
        let arch = "unknown"
    #endif
    #if os(macOS)
        let system = "darwin"
    #elseif os(iOS)
        let system = "ios"
    #else
        let system = "unknown"
    #endif
        return ["edition": "swift", "os": system, "arch": arch]
    }

    private static func oracleVersion() -> String {
        if let sha = ProcessInfo.processInfo.environment["PARITY_ORACLE_VERSION"],
           !sha.isEmpty {
            return sha
        }
        return gitShortSHA()   // works only if ever run unsandboxed; otherwise "unknown"
    }

    /// The repo's short SHA, for stamping which commit produced an oracle.
    ///
    /// macOS only: `Process` does not exist on iOS, and shelling out to git from a sandboxed
    /// test host would be blocked even where it does. Minting is a macOS act by design — but
    /// this file compiles into the test target on every platform, so the iOS build needs the
    /// guard or the whole suite fails to build. `Tooling/mint-oracle.sh` computes the SHA
    /// outside the sandbox and passes it in via PARITY_ORACLE_VERSION, which is the path
    /// actually used; this is the fallback for a direct run.
    private static func gitShortSHA() -> String {
    #if os(macOS)
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
    #endif
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
            try await sut.playFileAndWait(url: try fixtureURL(caseDict),
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
                caseDict["ringOutSec"] = Self.stored(decay)
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
            try await sut.playFileAndWait(url: try fixtureURL(caseDict),
                                             measurementType: isBrace ? .brace : .plate,
                                             numberOfTaps: set["numberOfTaps"] as? Int ?? 1,
                                             calibrationURL: calibrationURL(caseDict))

            let computed = Self.materialPeaks(sut)
            if let peaks = caseDict["peaks"] as? [[String: Any]] {
                caseDict["peaks"] = Self.updatePeaks(peaks, with: computed)
            }
            playback[name] = caseDict
        }

        // ----------------------------------------------------------------- gated FFT
        let fft = RealtimeFFTAnalyzer.forTesting()
        let sampleRate: Double = 48000
        for name in gated.keys.sorted() {
            guard var caseDict = gated[name] as? [String: Any] else { continue }  // skips note keys
            // Silence is the signal with no tones. The same builder the GFFT tests use.
            let tones = (caseDict["signal"] as? String) == "silence" ? [] :
                ((caseDict["tones"] as? [[Double]]) ?? [])
                    .filter { $0.count >= 2 }
                    .map { ParityOracle.GatedTone(hz: $0[0], amplitude: $0[1]) }
            let signal = makeGatedTestSignal(tones: tones, sampleRate: sampleRate)

            let (mags, freqs) = fft.computeGatedFFT(samples: signal, sampleRate: sampleRate)

            // Silence: record the exact peak — -inf. JSONSerialization cannot write infinity, so it
            // is stored as the string "-Infinity", which every edition's reader and the hub decode.
            if (caseDict["signal"] as? String) == "silence" {
                caseDict.removeValue(forKey: "maxDbBelow")
                caseDict["maxDb"] = Self.storedAllowingNonFinite(mags.max() ?? -.infinity)
            }

            if var expected = caseDict["expected"] as? [[String: Any]] {
                for i in expected.indices {
                    guard let hz = expected[i]["hz"] as? Double,
                          let db = gatedMagnitude(at: Float(hz), magnitudes: mags, frequencies: freqs)
                    else { continue }
                    expected[i]["db"] = Self.stored(db)
                }
                caseDict["expected"] = expected
                if caseDict["deltaDb"] != nil, expected.count >= 2,
                   let first = expected.first?["db"] as? Double,
                   let last = expected.last?["db"] as? Double {
                    caseDict["deltaDb"] = Self.stored(Float(last - first))
                }
            }
            gated[name] = caseDict
        }

        root["filePlayback"] = playback
        root["gatedFft"] = gated
        root["oracleVersion"] = Self.oracleVersion()
        root["generatedAt"] = ISO8601DateFormatter().string(from: Date())
        // Which configuration minted this. The oracle is the cross-edition contract AND the
        // canonical configuration's own zero-tolerance self-baseline — it is only the second
        // of those for the configuration that produced it, so the file has to say which one
        // that was rather than leave the hub to assume it.
        root["configuration"] = Self.configuration()

        // Tolerances are hand-written, not computed, but they still round-trip through
        // Double — so 0.03 re-serialises as 0.029999999999999999 and churns the diff on
        // every regeneration. Re-round them through the shortest decimal that reproduces
        // the value, the same treatment the computed values get.
        //
        // NOT by rounding to a fixed number of decimal places: the parity bar is now
        // 1e-07 for ringOutSec and 1e-05 for q, and rounding those to 5 dp would silently
        // write 0 — a bar of zero on values that cannot be zero, which would fail every
        // run and look like a real finding.
        for key in ["tolerances", "selfTolerances", "bootstrapTolerances"] {
            if var block = root[key] as? [String: Any] {
                for (k, v) in block {
                    if let d = v as? Double { block[k] = Double(String(d)) ?? d }
                }
                root[key] = block
            }
        }

        var out = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        out.append(0x0A)   // trailing newline, so every diff does not end in "\ No newline"
        let dest = Self.outputURL
        try out.write(to: dest)
        print("PARITY_ORACLE_WROTE \(dest.path)")
        print("Regenerated from \(url.path) — the wrapper copies it into the tree; review the diff, then publish with Tooling/sync-oracle.sh --publish")
    }
}

private enum OracleError: Error {
    case missingFixture(String)
}

/// Anchors Bundle(for:) to the test bundle holding the WAV fixtures.
private class OracleBundleMarker: NSObject {}
