//
//  FilePlaybackRegressionTests.swift
//  GuitarTapTests
//
//  End-to-end regression tests for the full file-playback pipeline.
//
//  Unlike FilePlaybackPipelineTests (FP1–FP5) which test the FFT → findPeaks
//  → classifyAll path directly, these tests exercise the FULL pipeline:
//    WAV read → chunk pacing → RMS → tap detection → gated capture →
//    Hann window → FFT → peak selection → mode identification
//
//  The analyzer is created via `TapToneAnalyzer.forTesting()` (no audio
//  hardware) and fed via `playFileForTesting(url:measurementType:)`.
//
//  Expected values were established by running the file through the app
//  and recording the displayed peak frequency and magnitude values.
//  Both Swift and Python test suites use the same WAV files and expected
//  values so that passing both suites guarantees cross-platform parity.
//
//  Test plan coverage: REG-G1, REG-B1, REG-G2
//
// @parity test/file-playback

import Testing
import Foundation
@testable import GuitarTap

// Used to anchor Bundle(for:) lookups to the GuitarTapTests bundle.
private class TestBundleMarker: NSObject {}
private var testBundle: Bundle { Bundle(for: TestBundleMarker.self) }

// ---------------------------------------------------------------------------
// MARK: - Expected values
// ---------------------------------------------------------------------------

// Every expected value below is read from the shared oracle (parity-oracle.json, vendored
// beside this file by Tooling/sync-oracle.sh). They were file-scope literals until
// guitar-tap-project#10: the same numbers were also typed into the Python suite and a third
// time into the web suite, with nothing keeping the three equal. Swift still owns them -
// GenerateParityOracle mints the oracle from this very pipeline - but it now owns them in one
// place that the other editions read.

// REG-B1 - brace bar, UMIK-1 mic, 48 kHz, full-session recording (mono float32). The oracle's
// values originally came from the matching .guitartap reference
// (Tests/Brace/brace-umik-1-swift-mac-1778816093.guitartap).
private let braceCase = ParityOracle.playback("REG-B1")
private let braceExpectedPeak = braceCase.peak("longitudinal")
private let braceExpectedFrequency: Float = braceExpectedPeak.frequency
private let braceExpectedMagnitude: Float = braceExpectedPeak.magnitude
private let braceExpectedQ: Float = braceExpectedPeak.q ?? 0
private let braceTapThreshold: Float = braceCase.settings.tapDetectionThreshold
// Swift MINTS the oracle, so these assert at the same-edition bar — zero. The values in
// the file are the exact Floats this code produced, stored as the shortest decimal that
// recovers them, so equality is exact and any movement is a real change in the DSP.
// ParityOracle.shared.tolerances is the cross-edition bar and is for the tracking
// editions; using it here would hide Swift drift four orders of magnitude below it,
// which is precisely what it did until the oracle was first re-minted.
private let freqTolerance: Float = ParityOracle.selfTolerance(\.freqHz)  // Hz
private let magTolerance: Float  = ParityOracle.selfTolerance(\.magDb)   // dB
private let qTolerance: Float    = ParityOracle.selfTolerance(\.q)       // dimensionless

// REG-P1 - plate, UMIK-1 mic, 48 kHz. Full-session recording covering all three plate phases
// (L -> C -> FLC). Played back end-to-end through the plate pipeline, which auto-advances
// between phases on file playback so the run reaches .complete with all three peaks populated.
private let plateCase = ParityOracle.playback("REG-P1")
private let plateLExpectedFrequency: Float = plateCase.peak("longitudinal").frequency
private let plateLExpectedMagnitude: Float = plateCase.peak("longitudinal").magnitude
private let plateLExpectedQ: Float = plateCase.peak("longitudinal").q ?? 0

private let plateCExpectedFrequency: Float = plateCase.peak("cross").frequency
private let plateCExpectedMagnitude: Float = plateCase.peak("cross").magnitude
private let plateCExpectedQ: Float = plateCase.peak("cross").q ?? 0

private let plateFlcExpectedFrequency: Float = plateCase.peak("flc").frequency
private let plateFlcExpectedMagnitude: Float = plateCase.peak("flc").magnitude
private let plateFlcExpectedQ: Float = plateCase.peak("flc").q ?? 0

private let plateTapThreshold: Float = plateCase.settings.tapDetectionThreshold

// REG-P2 - plate, UMIK-1, 48 kHz, recorded by the WEB app (Chrome) with numberOfTaps = 3
// (3 taps PER PHASE, 9 total). Replaying at numberOfTaps = 3 averages each phase. The expected
// values are the WEB capture's, so a pass means Swift agrees with the web on multi-tap material
// averaging. (Close to, not equal to, the separate Swift 3-tap capture L66.6/C117.1/FLC35.5.)
private let plate3TapCase = ParityOracle.playback("REG-P2")
private let plate3TapLExpectedFrequency: Float = plate3TapCase.peak("longitudinal").frequency
private let plate3TapLExpectedMagnitude: Float = plate3TapCase.peak("longitudinal").magnitude
private let plate3TapLExpectedQ: Float = plate3TapCase.peak("longitudinal").q ?? 0
private let plate3TapCExpectedFrequency: Float = plate3TapCase.peak("cross").frequency
private let plate3TapCExpectedMagnitude: Float = plate3TapCase.peak("cross").magnitude
private let plate3TapCExpectedQ: Float = plate3TapCase.peak("cross").q ?? 0
private let plate3TapFlcExpectedFrequency: Float = plate3TapCase.peak("flc").frequency
// peak read off the AVERAGED spectrum, not the last tap - see the oracle's _note
private let plate3TapFlcExpectedMagnitude: Float = plate3TapCase.peak("flc").magnitude
private let plate3TapFlcExpectedQ: Float = plate3TapCase.peak("flc").q ?? 0
private let plate3TapThreshold: Float = plate3TapCase.settings.tapDetectionThreshold
// REG-P2 uses a tighter magnitude tolerance than the generic 1.0 dB.  The averaged
// values are deterministic across platforms, so they agree far more closely than a
// single tap would; 0.5 dB still leaves headroom for FFT-library differences while
// reliably catching a regression to last-tap selection (the masked deltas were
// fL 0.94, fC 0.81, fLC 2.62 dB — all caught at 0.5).
// REG-P2 declares a tighter CROSS-EDITION tolerance (0.5 dB) because its averaged
// magnitudes are deterministic across editions. That override is about parity; for
// Swift's own regression the bar is zero like everything else here.
private let plate3TapMagTolerance: Float = ParityOracle.selfTolerance(\.magDb)  // dB

// ---------------------------------------------------------------------------
// MARK: - Tests  (REG-B1)
// ---------------------------------------------------------------------------

@Suite("FilePlaybackRegression")
struct FilePlaybackRegressionTests {

    // MARK: - Diagnostic helper

    /// Prints comprehensive diagnostic information about the analyzer state
    /// after a plate phase file playback test.  Output goes to the test console
    /// so we can compare what happened across P1, P2, and P3.
    private func printPlateDiagnostics(_ sut: TapToneAnalyzer, phase: String, wavFile: String) {
        print("╔══════════════════════════════════════════════════════════════════")
        print("║ PLATE DIAGNOSTIC: \(phase)")
        print("║ WAV: \(wavFile)")
        print("╠══════════════════════════════════════════════════════════════════")
        print("║ materialTapPhase:     \(sut.materialTapPhase)")
        print("║ isMeasurementComplete: \(sut.isMeasurementComplete)")
        print("║ isDetecting:          \(sut.isDetecting)")
        print("║ isAboveThreshold:     \(sut.isAboveThreshold)")
        print("║ noiseFloorEstimate:   \(String(format: "%.2f", sut.noiseFloorEstimate)) dB")
        print("║ tapDetectionThreshold: \(String(format: "%.2f", sut.tapDetectionThreshold)) dB")
        print("║ gatedCaptureActive:   \(sut.gatedCaptureActive)")
        print("║ gatedCaptureSamples:  \(sut.gatedCaptureSamples)")
        print("║ gatedAccumBuffer.count: \(sut.gatedAccumBuffer.count)")
        print("║ preRollBuffer.count:  \(sut.preRollBuffer.count)")
        print("║ preRollSamples:       \(sut.preRollSamples)")
        print("║ materialCapturedTaps: \(sut.materialCapturedTaps.count)")
        print("║ measureFlc:           \(TapDisplaySettings.measureFlc)")
        print("╠──────────────────────────────────────────────────────────────────")
        print("║ L peaks: \(sut.longitudinalPeaks.count)")
        if let p = sut.selectedLongitudinalPeak {
            print("║   selected: \(String(format: "%.4f", p.frequency)) Hz, \(String(format: "%.4f", p.magnitude)) dB, Q=\(String(format: "%.4f", p.quality))")
        } else {
            print("║   selected: nil")
        }
        print("║ C peaks: \(sut.crossPeaks.count)")
        if let p = sut.selectedCrossPeak {
            print("║   selected: \(String(format: "%.4f", p.frequency)) Hz, \(String(format: "%.4f", p.magnitude)) dB, Q=\(String(format: "%.4f", p.quality))")
        } else {
            print("║   selected: nil")
        }
        print("║ FLC peaks: \(sut.flcPeaks.count)")
        if let p = sut.selectedFlcPeak {
            print("║   selected: \(String(format: "%.4f", p.frequency)) Hz, \(String(format: "%.4f", p.magnitude)) dB, Q=\(String(format: "%.4f", p.quality))")
        } else {
            print("║   selected: nil")
        }
        // Dump all peaks for each phase so we can see what findPeaks found
        for (i, p) in sut.longitudinalPeaks.enumerated() {
            print("║   L[\(i)]: \(String(format: "%.4f", p.frequency)) Hz, \(String(format: "%.4f", p.magnitude)) dB, Q=\(String(format: "%.4f", p.quality))")
        }
        for (i, p) in sut.crossPeaks.enumerated() {
            print("║   C[\(i)]: \(String(format: "%.4f", p.frequency)) Hz, \(String(format: "%.4f", p.magnitude)) dB, Q=\(String(format: "%.4f", p.quality))")
        }
        for (i, p) in sut.flcPeaks.enumerated() {
            print("║   FLC[\(i)]: \(String(format: "%.4f", p.frequency)) Hz, \(String(format: "%.4f", p.magnitude)) dB, Q=\(String(format: "%.4f", p.quality))")
        }
        // Read and print the tail of the debug log to capture TAP_DEBUG output.
        // FileLogger is private, so we construct the path manually.  On macOS
        // the log lives under the user's home Documents dir; on iOS the test
        // app is sandboxed and writes to its container's Documents instead.
        // FileManager.homeDirectoryForCurrentUser is macOS-only, so route via
        // the standard Documents URL on iOS.
        let logDir: URL = {
            #if os(macOS)
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/GuitarTap")
            #else
            let docs = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            return docs.appendingPathComponent("GuitarTap")
            #endif
        }()
        let logURL = logDir.appendingPathComponent("GuitarTap-debug.log")
        if let logData = try? String(contentsOf: logURL, encoding: .utf8) {
            let lines = logData.components(separatedBy: "\n")
            // Find the most recent session start marker and print from there
            let sessionLines: [String]
            if let lastSession = lines.lastIndex(where: { $0.contains("=== GuitarTap session started") }) {
                sessionLines = Array(lines[lastSession...])
            } else {
                // Take last 100 lines
                sessionLines = Array(lines.suffix(100))
            }
            print("╠──────────────────────────────────────────────────────────────────")
            print("║ TAP_DEBUG LOG (from session start):")
            for line in sessionLines where !line.isEmpty {
                print("║ > \(line)")
            }
        }
        print("╚══════════════════════════════════════════════════════════════════")
    }

    // REG-B1: Brace single-tap — known WAV produces expected fL peak.
    //
    // Loads a full-session brace recording WAV (~12.6 s, 48 kHz) and plays it
    // through the full pipeline with measurementType = .brace.  Verifies that:
    //   1. The pipeline completes (materialTapPhase == .complete)
    //   2. At least one longitudinal peak is detected
    //   3. The dominant peak frequency matches the .guitartap reference ± 1 Hz
    //   4. The dominant peak magnitude matches the reference ± 1 dB
    //   5. The dominant peak Q factor matches the reference ± 1
    @Test func REG_B1_braceSingleTap_producesExpectedPeak() async throws {
        let stem = "brace-umik-1-swift-mac-1778816093"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }
        let calURL = testBundle.url(forResource: "7108913", withExtension: "txt")

        let sut = TapToneAnalyzer.forTesting()
        sut.tapDetectionThreshold = braceTapThreshold
        try await sut.playFileForTesting(url: url, measurementType: .brace, calibrationURL: calURL)

        // 1. Pipeline should reach .complete for brace (single-tap mode).
        #expect(sut.materialTapPhase == .complete,
                "materialTapPhase should be .complete, got \(sut.materialTapPhase)")

        #expect(sut.isMeasurementComplete,
                "isMeasurementComplete should be true")

        // 2. Longitudinal peaks should be populated.
        #expect(!sut.longitudinalPeaks.isEmpty,
                "longitudinalPeaks should not be empty")

        // 3. Verify dominant peak frequency.
        guard let dominant = sut.longitudinalPeaks.first else { return }
        let freqDelta = abs(dominant.frequency - braceExpectedFrequency)
        #expect(freqDelta <= freqTolerance,
                "Peak frequency: expected \(braceExpectedFrequency) Hz ±\(freqTolerance), got \(dominant.frequency) Hz (delta \(freqDelta))")

        // 4. Verify dominant peak magnitude.
        let magDelta = abs(dominant.magnitude - braceExpectedMagnitude)
        #expect(magDelta <= magTolerance,
                "Peak magnitude: expected \(braceExpectedMagnitude) dB ±\(magTolerance), got \(dominant.magnitude) dB (delta \(magDelta))")

        // 5. Verify dominant peak Q factor.
        let qDelta = abs(dominant.quality - braceExpectedQ)
        #expect(qDelta <= qTolerance,
                "Peak Q factor: expected \(braceExpectedQ) ±\(qTolerance), got \(dominant.quality) (delta \(qDelta))")
    }

    // MARK: - REG-G1: O'Brien single-tap generic guitar

    // Recording 5.wav — Generic guitar, single-tap, 48 kHz.
    // Reference values from the Recording 5.guitartap file (Tests/O'Brien/).
    // Settings: peakMinThreshold = -76, tapDetectionThreshold = -40,
    //           measurementType = .generic, numberOfTaps = 1.
    //           FFT size is a constant (65536) inside RealtimeFFTAnalyzer.
    private static let g1Case = ParityOracle.playback("REG-G1")
    private static let g1AirFreq: Float = g1Case.peak("air").frequency
    private static let g1AirMag: Float  = g1Case.peak("air").magnitude
    private static let g1TopFreq: Float = g1Case.peak("top").frequency
    private static let g1TopMag: Float  = g1Case.peak("top").magnitude
    private static let g1BackFreq: Float = g1Case.peak("back").frequency
    private static let g1BackMag: Float  = g1Case.peak("back").magnitude

    /// REG-G1: Generic guitar single-tap — validates Air/Top/Back peaks.
    ///
    /// Loads a single-tap generic guitar recording and plays it through the
    /// full pipeline.  Verifies that:
    ///   1. The pipeline completes with 1 tap entry
    ///   2. Air, Top, Back frequencies and magnitudes match reference ± 1
    @Test func REG_G1_genericGuitarSingleTap_producesExpectedPeaks() async throws {
        let stem = "Recording 5"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }

        let sut = TapToneAnalyzer.forTesting()
        sut.peakMinThreshold = -76
        sut.tapDetectionThreshold = -40
        try await sut.playFileForTesting(url: url, measurementType: .generic, numberOfTaps: 1)

        // 1. Pipeline should complete with 1 captured tap.
        //    (tapEntries is only populated for multi-tap sessions; single-tap
        //     uses capturedTaps directly.)
        #expect(sut.isMeasurementComplete, "isMeasurementComplete should be true")
        #expect(sut.capturedTaps.count == 1,
                "Expected 1 captured tap, got \(sut.capturedTaps.count)")

        // 2. Peaks — use getPeak(for:), the same API the Results panel uses.
        guard let airPeak = sut.getPeak(for: .air) else {
            Issue.record("No Air peak found")
            return
        }
        #expect(abs(airPeak.frequency - Self.g1AirFreq) <= freqTolerance,
                "Air freq: expected \(Self.g1AirFreq) ±\(freqTolerance), got \(airPeak.frequency)")
        #expect(abs(airPeak.magnitude - Self.g1AirMag) <= magTolerance,
                "Air mag: expected \(Self.g1AirMag) ±\(magTolerance), got \(airPeak.magnitude)")

        guard let topPeak = sut.getPeak(for: .top) else {
            Issue.record("No Top peak found")
            return
        }
        #expect(abs(topPeak.frequency - Self.g1TopFreq) <= freqTolerance,
                "Top freq: expected \(Self.g1TopFreq) ±\(freqTolerance), got \(topPeak.frequency)")
        #expect(abs(topPeak.magnitude - Self.g1TopMag) <= magTolerance,
                "Top mag: expected \(Self.g1TopMag) ±\(magTolerance), got \(topPeak.magnitude)")

        guard let backPeak = sut.getPeak(for: .back) else {
            Issue.record("No Back peak found")
            return
        }
        #expect(abs(backPeak.frequency - Self.g1BackFreq) <= freqTolerance,
                "Back freq: expected \(Self.g1BackFreq) ±\(freqTolerance), got \(backPeak.frequency)")
        #expect(abs(backPeak.magnitude - Self.g1BackMag) <= magTolerance,
                "Back mag: expected \(Self.g1BackMag) ±\(magTolerance), got \(backPeak.magnitude)")
    }

    // MARK: - REG-G: ring-out (decay) time

    /// REG-G ring-out — the post-tap level for Recording 5.wav decays to peak−15 dB. Shared
    /// cross-platform golden (web g4d-decay + Python test_REG_G_generic_guitar_ringout assert the
    /// same value): 0.0853 s ± 0.03 s. The web is audio-clock-deterministic; Swift's wall-clock
    /// decay reaches the same crossing because file playback runs at real-time pace (wall-clock ≈
    /// audio time). The loose tolerance covers per-platform chunk-granularity + clock jitter
    /// (web 0.0853, Python ~0.091).
    @Test func REG_G_genericGuitarRingOut_matchesGolden() async throws {
        let stem = "Recording 5"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }

        let sut = TapToneAnalyzer.forTesting()
        sut.peakMinThreshold = -76
        sut.tapDetectionThreshold = -40
        try await sut.playFileForTesting(url: url, measurementType: .generic, numberOfTaps: 1)

        guard let decay = sut.currentDecayTime else {
            Issue.record("No ring-out measured")
            return
        }
        let golden: Float = ParityOracle.playback("REG-G1").ringOutSec ?? 0
        let tol: Float = ParityOracle.selfTolerance(\.ringOutSec)
        #expect(abs(decay - golden) <= tol,
                "Ring-out: expected \(golden) ±\(tol), got \(decay)")
    }

    // MARK: - REG-G2: O'Brien 8-tap generic guitar

    // Recording.wav — Generic guitar, 8-tap multi-tap, 48 kHz.
    // Reference values from the Recording.guitartap file (Tests/O'Brien/).
    // Settings: peakMinThreshold = -76, tapDetectionThreshold = -40,
    //           measurementType = .generic, numberOfTaps = 8.
    //           FFT size is a constant (65536) inside RealtimeFFTAnalyzer.

    // Average peaks
    private static let g2Case = ParityOracle.playback("REG-G2")
    private static let guitarAvgAirFreq: Float = g2Case.peak("air", averaged: true).frequency
    private static let guitarAvgAirMag: Float  = g2Case.peak("air", averaged: true).magnitude
    private static let guitarAvgTopFreq: Float = g2Case.peak("top", averaged: true).frequency
    private static let guitarAvgTopMag: Float  = g2Case.peak("top", averaged: true).magnitude
    private static let guitarAvgBackFreq: Float = g2Case.peak("back", averaged: true).frequency
    private static let guitarAvgBackMag: Float  = g2Case.peak("back", averaged: true).magnitude

    // Per-tap expected values: (airFreq, airMag, topFreq, topMag, backFreq, backMag)
    // Taps 1 and 7 pin Back at ~296.5 Hz rather than ~240.6 - real behaviour of the shared
    // selection path on this fixture, pinned deliberately (see _perTapNote in the oracle).
    private typealias PerTapRow = (airFreq: Float, airMag: Float,
                                   topFreq: Float, topMag: Float,
                                   backFreq: Float, backMag: Float)

    /// One oracle `perTap` row, as the tuple the assertions below expect.
    ///
    /// Written out in annotated steps rather than as a single tuple literal: six optional
    /// chains with `??` defaults in one expression is more than the type checker will solve
    /// in reasonable time (it was the literal that produced "unable to type-check this
    /// expression in reasonable time").
    private static func perTapRow(_ row: ParityOracle.TapRow) -> PerTapRow {
        func peak(_ role: String) -> ParityOracle.Peak? {
            row.peaks.first(where: { $0.role == role })
        }
        let air: ParityOracle.Peak? = peak("air")
        let top: ParityOracle.Peak? = peak("top")
        let back: ParityOracle.Peak? = peak("back")

        let airFreq: Float = air?.frequency ?? 0
        let airMag: Float = air?.magnitude ?? 0
        let topFreq: Float = top?.frequency ?? 0
        let topMag: Float = top?.magnitude ?? 0
        let backFreq: Float = back?.frequency ?? 0
        let backMag: Float = back?.magnitude ?? 0

        return (airFreq: airFreq, airMag: airMag,
                topFreq: topFreq, topMag: topMag,
                backFreq: backFreq, backMag: backMag)
    }

    private static let guitarPerTap: [PerTapRow] = (g2Case.perTap ?? []).map(perTapRow)

    /// REG-G2: Generic guitar 8-tap — validates averaged and per-tap Air/Top/Back.
    ///
    /// Loads a live 8-tap generic guitar recording and plays it through the full
    /// pipeline.  Verifies that:
    ///   1. The pipeline completes with 8 tap entries
    ///   2. Averaged Air, Top, Back frequencies and magnitudes match reference ± 1
    ///   3. All 8 individual taps' Air, Top, Back frequencies and magnitudes match
    @Test func REG_G2_genericGuitar8Tap_producesExpectedPeaks() async throws {
        let stem = "Recording"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }

        let sut = TapToneAnalyzer.forTesting()
        sut.peakMinThreshold = -76
        sut.tapDetectionThreshold = -40
        try await sut.playFileForTesting(url: url, measurementType: .generic, numberOfTaps: 8)

        // 1. Pipeline should complete with 8 tap entries.
        #expect(sut.isMeasurementComplete, "isMeasurementComplete should be true")
        #expect(sut.tapEntries.count == 8,
                "Expected 8 tap entries, got \(sut.tapEntries.count)")

        // 2. Averaged peaks — use getPeak(for:), the same API the Results panel uses.
        guard let airPeak = sut.getPeak(for: .air) else {
            Issue.record("No averaged Air peak found")
            return
        }
        #expect(abs(airPeak.frequency - Self.guitarAvgAirFreq) <= freqTolerance,
                "Avg Air freq: expected \(Self.guitarAvgAirFreq) ±\(freqTolerance), got \(airPeak.frequency)")
        #expect(abs(airPeak.magnitude - Self.guitarAvgAirMag) <= magTolerance,
                "Avg Air mag: expected \(Self.guitarAvgAirMag) ±\(magTolerance), got \(airPeak.magnitude)")

        guard let topPeak = sut.getPeak(for: .top) else {
            Issue.record("No averaged Top peak found")
            return
        }
        #expect(abs(topPeak.frequency - Self.guitarAvgTopFreq) <= freqTolerance,
                "Avg Top freq: expected \(Self.guitarAvgTopFreq) ±\(freqTolerance), got \(topPeak.frequency)")
        #expect(abs(topPeak.magnitude - Self.guitarAvgTopMag) <= magTolerance,
                "Avg Top mag: expected \(Self.guitarAvgTopMag) ±\(magTolerance), got \(topPeak.magnitude)")

        guard let backPeak = sut.getPeak(for: .back) else {
            Issue.record("No averaged Back peak found")
            return
        }
        #expect(abs(backPeak.frequency - Self.guitarAvgBackFreq) <= freqTolerance,
                "Avg Back freq: expected \(Self.guitarAvgBackFreq) ±\(freqTolerance), got \(backPeak.frequency)")
        #expect(abs(backPeak.magnitude - Self.guitarAvgBackMag) <= magTolerance,
                "Avg Back mag: expected \(Self.guitarAvgBackMag) ±\(magTolerance), got \(backPeak.magnitude)")

        // 3. Per-tap peaks — uses TapEntry.resolvedModePeaks(), the same
        //    code path as MultiTapComparisonResultsView and PDF export.
        for (index, entry) in sut.tapEntries.enumerated() {
            let expected = Self.guitarPerTap[index]
            let tapLabel = "Tap \(index + 1)"

            let modePeaks = entry.resolvedModePeaks()

            // Air
            if let air = modePeaks[.air] {
                #expect(abs(air.frequency - expected.airFreq) <= freqTolerance,
                        "\(tapLabel) Air freq: expected \(expected.airFreq) ±\(freqTolerance), got \(air.frequency)")
                #expect(abs(air.magnitude - expected.airMag) <= magTolerance,
                        "\(tapLabel) Air mag: expected \(expected.airMag) ±\(magTolerance), got \(air.magnitude)")
            } else {
                Issue.record("\(tapLabel): no Air peak found in selected peaks")
            }

            // Top
            if let top = modePeaks[.top] {
                #expect(abs(top.frequency - expected.topFreq) <= freqTolerance,
                        "\(tapLabel) Top freq: expected \(expected.topFreq) ±\(freqTolerance), got \(top.frequency)")
                #expect(abs(top.magnitude - expected.topMag) <= magTolerance,
                        "\(tapLabel) Top mag: expected \(expected.topMag) ±\(magTolerance), got \(top.magnitude)")
            } else {
                Issue.record("\(tapLabel): no Top peak found in selected peaks")
            }

            // Back
            if let back = modePeaks[.back] {
                #expect(abs(back.frequency - expected.backFreq) <= freqTolerance,
                        "\(tapLabel) Back freq: expected \(expected.backFreq) ±\(freqTolerance), got \(back.frequency)")
                #expect(abs(back.magnitude - expected.backMag) <= magTolerance,
                        "\(tapLabel) Back mag: expected \(expected.backMag) ±\(magTolerance), got \(back.magnitude)")
            } else {
                Issue.record("\(tapLabel): no Back peak found in selected peaks")
            }
        }
    }

    // MARK: - REG-P1: Plate full-session (L + C + FLC)

    // plate-umik-1-swift-mac-1778816330.wav — Plate, UMIK-1, 48 kHz, full session.
    // Reference values from the matching .guitartap file in Tests/Plate/.
    // The pipeline runs end-to-end with auto-advance between phases on file
    // playback, so all three peaks are populated and the phase reaches .complete.

    /// REG-P1: Plate full-session — single WAV exercises all three phases.
    ///
    /// Loads a full-session plate recording and plays it through the
    /// pipeline with measurementType = .plate.  Verifies that:
    ///   1. The pipeline reaches .complete (all three phases captured)
    ///   2. fL / fC / fLC peaks are each populated
    ///   3. Each auto-selected peak's frequency, magnitude, and Q factor
    ///      matches the .guitartap reference within tolerance
    @Test func REG_P1_plateFullSession_producesExpectedPeaks() async throws {
        let stem = "plate-umik-1-swift-mac-1778816330"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }
        let calURL = testBundle.url(forResource: "7108913", withExtension: "txt")

        // FLC must be enabled — the saved measurement was captured with all
        // three phases, and the playback pipeline reads this flag to decide
        // whether to advance past C → FLC or finish after C.  Save/restore
        // so the test doesn't bleed state into other tests in the suite.
        let originalMeasureFlc = TapDisplaySettings.measureFlc
        TapDisplaySettings.measureFlc = true
        defer { TapDisplaySettings.measureFlc = originalMeasureFlc }

        let sut = TapToneAnalyzer.forTesting()
        sut.tapDetectionThreshold = plateTapThreshold
        try await sut.playFileForTesting(url: url, measurementType: .plate, calibrationURL: calURL)

        printPlateDiagnostics(sut, phase: "P1 — Full session", wavFile: stem)

        // 1. Pipeline should reach .complete after all three phases.
        #expect(sut.materialTapPhase == .complete,
                "materialTapPhase should be .complete, got \(sut.materialTapPhase)")
        #expect(sut.isMeasurementComplete,
                "isMeasurementComplete should be true")

        // 2. All three peak arrays populated.
        #expect(!sut.longitudinalPeaks.isEmpty, "longitudinalPeaks should not be empty")
        #expect(!sut.crossPeaks.isEmpty, "crossPeaks should not be empty")
        #expect(!sut.flcPeaks.isEmpty, "flcPeaks should not be empty")

        // 3a. fL peak.
        guard let lPeak = sut.selectedLongitudinalPeak else {
            Issue.record("selectedLongitudinalPeak is nil")
            return
        }
        let lFreqDelta = abs(lPeak.frequency - plateLExpectedFrequency)
        #expect(lFreqDelta <= freqTolerance,
                "fL frequency: expected \(plateLExpectedFrequency) Hz ±\(freqTolerance), got \(lPeak.frequency) Hz (delta \(lFreqDelta))")
        let lMagDelta = abs(lPeak.magnitude - plateLExpectedMagnitude)
        #expect(lMagDelta <= magTolerance,
                "fL magnitude: expected \(plateLExpectedMagnitude) dB ±\(magTolerance), got \(lPeak.magnitude) dB (delta \(lMagDelta))")
        let lQDelta = abs(lPeak.quality - plateLExpectedQ)
        #expect(lQDelta <= qTolerance,
                "fL Q factor: expected \(plateLExpectedQ) ±\(qTolerance), got \(lPeak.quality) (delta \(lQDelta))")

        // 3b. fC peak.
        guard let cPeak = sut.selectedCrossPeak else {
            Issue.record("selectedCrossPeak is nil")
            return
        }
        let cFreqDelta = abs(cPeak.frequency - plateCExpectedFrequency)
        #expect(cFreqDelta <= freqTolerance,
                "fC frequency: expected \(plateCExpectedFrequency) Hz ±\(freqTolerance), got \(cPeak.frequency) Hz (delta \(cFreqDelta))")
        let cMagDelta = abs(cPeak.magnitude - plateCExpectedMagnitude)
        #expect(cMagDelta <= magTolerance,
                "fC magnitude: expected \(plateCExpectedMagnitude) dB ±\(magTolerance), got \(cPeak.magnitude) dB (delta \(cMagDelta))")
        let cQDelta = abs(cPeak.quality - plateCExpectedQ)
        #expect(cQDelta <= qTolerance,
                "fC Q factor: expected \(plateCExpectedQ) ±\(qTolerance), got \(cPeak.quality) (delta \(cQDelta))")

        // 3c. fLC peak.
        guard let flcPeak = sut.selectedFlcPeak else {
            Issue.record("selectedFlcPeak is nil")
            return
        }
        let flcFreqDelta = abs(flcPeak.frequency - plateFlcExpectedFrequency)
        #expect(flcFreqDelta <= freqTolerance,
                "fLC frequency: expected \(plateFlcExpectedFrequency) Hz ±\(freqTolerance), got \(flcPeak.frequency) Hz (delta \(flcFreqDelta))")
        let flcMagDelta = abs(flcPeak.magnitude - plateFlcExpectedMagnitude)
        #expect(flcMagDelta <= magTolerance,
                "fLC magnitude: expected \(plateFlcExpectedMagnitude) dB ±\(magTolerance), got \(flcPeak.magnitude) dB (delta \(flcMagDelta))")
        let flcQDelta = abs(flcPeak.quality - plateFlcExpectedQ)
        #expect(flcQDelta <= qTolerance,
                "fLC Q factor: expected \(plateFlcExpectedQ) ±\(qTolerance), got \(flcPeak.quality) (delta \(flcQDelta))")
    }

    // ── OUT-4: the one test that can tell the two detection models apart ────────────────────────
    //
    // plate-umik-1-noisy-52.wav is the SAME plate session with broadband noise mixed in to raise its
    // noise floor from -77 dBFS to -52 dBFS — i.e. ABOVE the -53.34 dB tap threshold.
    //
    // Swift/Python detect material taps against an EMA-tracked noise floor; the web port uses a fixed
    // absolute dBFS threshold. The relative rule reduces to
    //     rising = max(tapDetectionThreshold, noiseFloor + 10 dB)
    // so the two are the SAME FUNCTION until the floor climbs within 10 dB of the threshold. Every
    // other fixture sits at -64…-69 dBFS, far below that — which is why no test has ever separated them.
    //
    // At a -52 floor an ABSOLUTE detector SATURATES: the level never drops below the threshold, so no
    // rising edge can be confirmed and it captures NOTHING. (The web's counterpart test asserts exactly
    // that failure.) The RELATIVE detector floats its threshold to floor+10 = -42 dB and still finds
    // every tap (they peak at -24…-27 dBFS chunk-RMS). That is precisely the failure the relative model
    // exists to prevent: "keeps detection working when ambient noise is elevated".
    //
    // This test only became possible once file playback stopped pinning noiseFloorEstimate = -100,
    // which collapsed `rising` onto the absolute threshold and silently disabled relative detection in
    // playback on every platform.
    //
    // Asserts the PHASE COUNT, not peak values: the added noise sums into the gated FFT, so fL/fC/fLC
    // shift slightly. A tight peak assertion here would be measuring the noise, not the detector.
    //
    // Regenerate: python3 GuitarTapWeb/tooling/make-noisy-fixture.py (deterministic, seeded).
    // Analysis:   GuitarTapWeb/Development/OUT-4-DETECTION-SPEC.md
    @Test func OUT4_noisyPlate_relativeNoiseFloor_stillCapturesAllPhases() async throws {
        let stem = "plate-umik-1-noisy-52"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }
        let calURL = testBundle.url(forResource: "7108913", withExtension: "txt")

        let originalMeasureFlc = TapDisplaySettings.measureFlc
        TapDisplaySettings.measureFlc = true
        defer { TapDisplaySettings.measureFlc = originalMeasureFlc }

        let sut = TapToneAnalyzer.forTesting()
        sut.tapDetectionThreshold = plateTapThreshold
        try await sut.playFileForTesting(url: url, measurementType: .plate, calibrationURL: calURL)

        let captured = [
            ("L", sut.longitudinalSpectrum != nil),
            ("C", sut.crossSpectrum != nil),
            ("FLC", sut.flcSpectrum != nil),
        ].filter { $0.1 }.map { $0.0 }

        #expect(captured.count == 3,
                """
                absolute-threshold detection saturates on an elevated noise floor and captures nothing; \
                the noise-floor-relative detector must still find all three taps. \
                Captured: \(captured), noiseFloorEstimate=\(sut.noiseFloorEstimate) dBFS
                """)

        // The floor must have actually CONVERGED to the noisy ambient. If it is still pinned near -100,
        // the relative model has silently degraded to the absolute one and this test would be passing
        // for the wrong reason.
        #expect(sut.noiseFloorEstimate > -60 && sut.noiseFloorEstimate < -40,
                "noiseFloorEstimate should have converged to the fixture's ~-52 dBFS floor; got \(sut.noiseFloorEstimate) (pinned at -100 means relative detection is OFF)")
    }


    // MARK: - REG-P2: Plate, 3 taps per phase (multi-tap averaging)

    /// REG-P2: Plate at numberOfTaps = 3 — each phase (L/C/FLC) averages 3 taps.
    ///
    /// Replays a 3-taps-per-phase plate session (recorded by the web app) at
    /// numberOfTaps = 3, exercising the multi-tap-per-phase averaging path
    /// (handleLongitudinalGatedProgress collecting numberOfTaps before
    /// averageSpectra). Expected values are the WEB capture's, so a pass means
    /// Swift agrees with the web. printPlateDiagnostics prints Swift's actual
    /// fL/fC/fLC regardless of pass/fail.
    @Test func REG_P2_plateThreeTapsPerPhase_averagesEachPhase() async throws {
        let stem = "plate-umik-1-web-mac-3-taps"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }
        let calURL = testBundle.url(forResource: "7108913", withExtension: "txt")

        let originalMeasureFlc = TapDisplaySettings.measureFlc
        TapDisplaySettings.measureFlc = true
        defer { TapDisplaySettings.measureFlc = originalMeasureFlc }

        let sut = TapToneAnalyzer.forTesting()
        sut.tapDetectionThreshold = plate3TapThreshold
        try await sut.playFileForTesting(url: url, measurementType: .plate, numberOfTaps: 3, calibrationURL: calURL)

        printPlateDiagnostics(sut, phase: "P2 - 3 taps/phase", wavFile: stem)

        #expect(sut.materialTapPhase == .complete,
                "materialTapPhase should be .complete, got \(sut.materialTapPhase)")
        #expect(sut.isMeasurementComplete, "isMeasurementComplete should be true")

        guard let lPeak = sut.selectedLongitudinalPeak else { Issue.record("selectedLongitudinalPeak is nil"); return }
        #expect(abs(lPeak.frequency - plate3TapLExpectedFrequency) <= freqTolerance,
                "fL frequency: expected \(plate3TapLExpectedFrequency) Hz, got \(lPeak.frequency) Hz")
        #expect(abs(lPeak.magnitude - plate3TapLExpectedMagnitude) <= plate3TapMagTolerance,
                "fL magnitude: expected \(plate3TapLExpectedMagnitude) dB, got \(lPeak.magnitude) dB")
        #expect(abs(lPeak.quality - plate3TapLExpectedQ) <= qTolerance,
                "fL Q: expected \(plate3TapLExpectedQ), got \(lPeak.quality)")

        guard let cPeak = sut.selectedCrossPeak else { Issue.record("selectedCrossPeak is nil"); return }
        #expect(abs(cPeak.frequency - plate3TapCExpectedFrequency) <= freqTolerance,
                "fC frequency: expected \(plate3TapCExpectedFrequency) Hz, got \(cPeak.frequency) Hz")
        #expect(abs(cPeak.magnitude - plate3TapCExpectedMagnitude) <= plate3TapMagTolerance,
                "fC magnitude: expected \(plate3TapCExpectedMagnitude) dB, got \(cPeak.magnitude) dB")
        #expect(abs(cPeak.quality - plate3TapCExpectedQ) <= qTolerance,
                "fC Q: expected \(plate3TapCExpectedQ), got \(cPeak.quality)")

        guard let flcPeak = sut.selectedFlcPeak else { Issue.record("selectedFlcPeak is nil"); return }
        #expect(abs(flcPeak.frequency - plate3TapFlcExpectedFrequency) <= freqTolerance,
                "fLC frequency: expected \(plate3TapFlcExpectedFrequency) Hz, got \(flcPeak.frequency) Hz")
        #expect(abs(flcPeak.magnitude - plate3TapFlcExpectedMagnitude) <= plate3TapMagTolerance,
                "fLC magnitude: expected \(plate3TapFlcExpectedMagnitude) dB, got \(flcPeak.magnitude) dB")
        #expect(abs(flcPeak.quality - plate3TapFlcExpectedQ) <= qTolerance,
                "fLC Q: expected \(plate3TapFlcExpectedQ), got \(flcPeak.quality)")
    }
}
