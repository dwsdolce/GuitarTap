//  SpectrumReplayProbeTests.swift
//  Dumps the replayed material spectrum so it can be compared, bin by bin, against the
//  spectrum saved in the .guitartap file from the original LIVE capture of the same WAV.
//
//  This is the measurement issue #7 is actually about. The peaks already reproduce live
//  capture essentially exactly (REG-B1 bit-identical; REG-P1 seven of nine values
//  bit-identical, the other two within 3e-05 Hz / 0.001 dB). What has never reproduced is
//  the rest of the spectrum — originally reported as ~0.02 dB mean across the >= -100 dB
//  range with 0 of 3702 bins exact. Peaks agreeing while bins do not is the thing to explain.
//
//  Gated: does nothing unless SPECTRUM_PROBE=1 (TEST_RUNNER_SPECTRUM_PROBE=1 under
//  xcodebuild, which does not forward the plain environment to a hosted test runner).
//  Prints SPECTRUM_PROBE_WROTE <path> — the sandboxed test host cannot write where a shell
//  would choose, so the test picks the path and reports it.
//  @parity none — Swift-only by nature: it compares this edition's replay against the
//  spectrum stored in a .guitartap written by this edition's live capture. The other
//  editions have no such archive to check themselves against.

import Foundation
import Testing
@testable import GuitarTap

/// Bundle anchor for locating fixtures (see project memory: use Bundle(for:), not #filePath).
private final class ProbeAnchor {}

@Suite(.serialized)
struct SpectrumReplayProbeTests {

    private static var enabled: Bool {
        ProcessInfo.processInfo.environment["SPECTRUM_PROBE"] == "1"
    }

    private static func outputURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spectrum-replay-\(name).json")
    }

    /// The GUITAR case this issue was actually filed about: a stereo recording with a live
    /// .guitartap saved from the same session. Stereo is the shape the downmix bug corrupted —
    /// replay analysed the left channel alone while the live capture analysed the mono mic.
    @Test @MainActor
    func dumpReplayedGuitarSpectrum() async throws {
        guard Self.enabled else { return }
        let bundle = Bundle(for: ProbeAnchor.self)
        guard let url = bundle.url(forResource: "5 tap test", withExtension: "wav") else {
            Issue.record("5 tap test.wav not in the test bundle")
            return
        }
        let sut = TapToneAnalyzer.forTesting()
        sut.peakMinThreshold = -69
        sut.tapDetectionThreshold = -40
        try await sut.playFileForTesting(
            url: url, measurementType: .generic, numberOfTaps: 5,
            calibrationURL: bundle.url(forResource: "7108913", withExtension: "txt"))

        struct Dump: Codable {
            let caseName: String
            let magnitudes: [Float]
            let frequencies: [Float]
        }
        let data = try JSONEncoder().encode(Dump(caseName: "5-tap-test",
                                                 magnitudes: sut.frozenMagnitudes,
                                                 frequencies: sut.frozenFrequencies))
        let out = Self.outputURL("5-tap-test")
        try data.write(to: out)
        print("SPECTRUM_PROBE_WROTE \(out.path)  (\(sut.frozenMagnitudes.count) bins, "
              + "capturedTaps=\(sut.capturedTaps.count))")
    }

    @Test @MainActor
    func dumpReplayedMaterialSpectra() async throws {
        guard Self.enabled else { return }

        for caseName in ["REG-B1", "REG-P1"] {
            let spec = ParityOracle.playback(caseName)
            let url = ParityOracle.fixtureURL(caseName)
            let brace = spec.settings.measurementType == "Material (Brace)"

            let sut = TapToneAnalyzer.forTesting()
            sut.tapDetectionThreshold = spec.settings.tapDetectionThreshold
            let restore = TapDisplaySettings.measureFlc
            TapDisplaySettings.measureFlc = spec.settings.measureFlc ?? false
            defer { TapDisplaySettings.measureFlc = restore }

            try await sut.playFileForTesting(
                url: url,
                measurementType: brace ? .brace : .plate,
                calibrationURL: ParityOracle.calibrationURL(caseName))

            guard let longitudinal = sut.longitudinalSpectrum else {
                Issue.record("\(caseName): no longitudinal spectrum after replay")
                continue
            }
            struct Dump: Codable {
                let caseName: String
                let magnitudes: [Float]
                let frequencies: [Float]
            }
            let encoder = JSONEncoder()
            let data = try encoder.encode(Dump(caseName: caseName,
                                               magnitudes: longitudinal.magnitudes,
                                               frequencies: longitudinal.frequencies))
            let out = Self.outputURL(caseName)
            try data.write(to: out)
            print("SPECTRUM_PROBE_WROTE \(out.path)  (\(longitudinal.magnitudes.count) bins)")
        }
    }
}
