//
//  ParityOracle.swift
//  GuitarTapTests
//
//  The shared numeric golden contract, decoded from the vendored parity-oracle.json.
//
//  Swift is canonical: `GenerateParityOracle` writes this file from the same pipeline
//  the tests below assert against, so the oracle can never disagree with Swift. The
//  committed JSON is then published to the project hub and pulled by every other
//  edition (Tooling/sync-oracle.sh here, tooling/ in the web repo), which is what makes
//  one number one number.
//
//  Before this existed the same constants were typed out here, again in the Python
//  suite and a third time in the web suite — three copies of one contract with nothing
//  keeping them equal.
//
// @parity tooling/parity-oracle

import Foundation

// Anchors Bundle(for:) to the GuitarTapTests bundle, where sync-oracle.sh vendors the JSON.
private class ParityOracleBundleMarker: NSObject {}

struct ParityOracle: Codable {

    struct Tolerances: Codable {
        let freqHz: Float
        let magDb: Float
        let q: Float
        let gatedFftDb: Float
        let ringOutSec: Float
    }

    struct Peak: Codable {
        let role: String
        let frequency: Float
        let magnitude: Float
        let q: Float?
    }

    struct Settings: Codable {
        let measurementType: String?
        let peakMinThreshold: Float?
        let tapDetectionThreshold: Float
        let numberOfTaps: Int?
        let measureFlc: Bool?
        let fftSize: Int?
    }

    struct TapRow: Codable {
        let tap: Int
        let peaks: [Peak]
    }

    /// Per-case tolerance overrides. Only the keys a case actually tightens appear;
    /// everything else falls back to the global tolerances (see `tolerance(_:for:)`).
    struct CaseTolerances: Codable {
        let freqHz: Float?
        let magDb: Float?
        let q: Float?
    }

    struct PlaybackCase: Codable {
        let fixture: String
        let calibration: String?
        let settings: Settings
        let peaks: [Peak]?
        let averagedPeaks: [Peak]?
        let perTap: [TapRow]?
        let ringOutSec: Float?
        let tolerances: CaseTolerances?

        /// The expected peak for one mode role, from `peaks` unless `averaged` is asked for.
        func peak(_ role: String, averaged: Bool = false) -> Peak {
            let list = averaged ? averagedPeaks : peaks
            guard let found = list?.first(where: { $0.role == role }) else {
                fatalError("parity-oracle.json: no \(averaged ? "averaged " : "")\(role) peak for this case")
            }
            return found
        }
    }

    struct GatedTone: Codable {
        let hz: Double
        let amplitude: Double
    }

    struct GatedExpectation: Codable {
        let hz: Double
        let db: Float
    }

    struct GatedCase: Codable {
        /// [[hz, amplitude], ...] — a JSON array of pairs, kept in that shape so the
        /// file reads the same in all four editions.
        let tones: [[Double]]?
        let expected: [GatedExpectation]?
        let deltaDb: Float?
        let binCentered: Bool?
        let signal: String?
        /// The case's exact peak, where one is recorded instead of per-tone expectations — GFFT4's
        /// silence, which is -inf (stored as the string "-Infinity"; see `shared`).
        let maxDb: Float?

        var toneList: [GatedTone] {
            (tones ?? []).map { GatedTone(hz: $0[0], amplitude: $0[1]) }
        }

        /// The expected dB for one tone, matched on its target frequency.
        func expectedDb(at hz: Double) -> Float {
            guard let found = expected?.first(where: { abs($0.hz - hz) < 1e-6 }) else {
                fatalError("parity-oracle.json: no expected entry near \(hz) Hz")
            }
            return found.db
        }
    }

    var oracleVersion: String
    var generatedAt: String
    /// The CROSS-EDITION bar — what a tracking edition must match. See `selfTolerances`.
    var tolerances: Tolerances
    /// The SAME-EDITION bar: zero. Used when an edition checks against goldens it minted
    /// itself, where the input bytes, the code path and the machine are all identical, so
    /// the output is bit-reproducible and any movement is a real change rather than
    /// numerical noise. Optional so a tracking edition's vendored copy still decodes if it
    /// predates this field.
    var selfTolerances: Tolerances?
    var filePlayback: [String: PlaybackCase]
    var gatedFft: [String: GatedCase]

    // MARK: - Loading

    static let shared: ParityOracle = {
        let bundle = Bundle(for: ParityOracleBundleMarker.self)
        guard let url = bundle.url(forResource: "parity-oracle", withExtension: "json") else {
            fatalError("parity-oracle.json not in the test bundle — run Tooling/sync-oracle.sh")
        }
        do {
            // JSON has no infinity, and GFFT4's silence is -inf, so every oracle and baseline file —
            // all three editions and the hub — writes a non-finite number as the STRING
            // "-Infinity" / "Infinity" / "NaN".
            let decoder = JSONDecoder()
            decoder.nonConformingFloatDecodingStrategy =
                .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
            return try decoder.decode(ParityOracle.self, from: Data(contentsOf: url))
        } catch {
            fatalError("parity-oracle.json could not be decoded: \(error)")
        }
    }()

    static func playback(_ name: String) -> PlaybackCase {
        guard let found = shared.filePlayback[name] else {
            fatalError("parity-oracle.json has no filePlayback case \(name)")
        }
        return found
    }

    static func gated(_ name: String) -> GatedCase {
        guard let found = shared.gatedFft[name] else {
            fatalError("parity-oracle.json has no gatedFft case \(name)")
        }
        return found
    }

    /// A case's own tolerance if it declares one, else the global value. REG-P2 is the
    /// case that needs this: its averaged magnitudes are deterministic across editions,
    /// so it pins them at 0.5 dB where the single-tap cases allow 1.0.
    static func tolerance(_ key: KeyPath<CaseTolerances, Float?>,
                          global: KeyPath<Tolerances, Float>,
                          for name: String) -> Float {
        if let override = playback(name).tolerances?[keyPath: key] { return override }
        return shared.tolerances[keyPath: global]
    }

    /// The same-edition bar for this key. Swift mints the oracle, so Swift's own
    /// regression tests assert against it at this bar, not the cross-edition one.
    ///
    /// Zero is meant literally: the stored text is the shortest decimal that recovers the
    /// exact Float the generator computed, so a comparison of `abs(delta) <= 0` is exact
    /// equality with no rounding on either side. Per-case overrides deliberately do NOT
    /// apply — those loosen the parity bar for cross-edition reasons, which say nothing
    /// about whether this edition reproduces itself.
    static func selfTolerance(_ global: KeyPath<Tolerances, Float>) -> Float {
        shared.selfTolerances?[keyPath: global] ?? 0
    }

    /// Absolute URL of a case's WAV fixture in the test bundle.
    static func fixtureURL(_ name: String) -> URL {
        let bundle = Bundle(for: ParityOracleBundleMarker.self)
        let file = playback(name).fixture
        let stem = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        guard let url = bundle.url(forResource: stem, withExtension: ext) else {
            fatalError("\(file) not found in the test bundle")
        }
        return url
    }

    /// Absolute URL of a case's calibration file, or nil when it declares none.
    static func calibrationURL(_ name: String) -> URL? {
        guard let file = playback(name).calibration else { return nil }
        let bundle = Bundle(for: ParityOracleBundleMarker.self)
        let stem = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        return bundle.url(forResource: stem, withExtension: ext)
    }
}
