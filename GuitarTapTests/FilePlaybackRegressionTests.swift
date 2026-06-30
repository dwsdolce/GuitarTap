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

import Testing
import Foundation
@testable import GuitarTap

// Used to anchor Bundle(for:) lookups to the GuitarTapTests bundle.
private class TestBundleMarker: NSObject {}
private var testBundle: Bundle { Bundle(for: TestBundleMarker.self) }

// ---------------------------------------------------------------------------
// MARK: - Expected values
// ---------------------------------------------------------------------------

// brace-umik-1-swift-mac-1778816093.wav — Brace bar, UMIK-1 mic, 48 kHz.
// Full-session recording (mono float32, 48 kHz).
// Reference values from the matching .guitartap file
// (Tests/Brace/brace-umik-1-swift-mac-1778816093.guitartap):
//   Peak frequency: 512.68880 Hz
//   Peak magnitude: -70.93484 dB
//   Peak Q factor:  87.5
//   Tap detection threshold: -53.33838 dB
// The test uses tolerances per the test plan: ±1.0 Hz, ±1.0 dB, ±1.0 Q.
private let braceExpectedFrequency: Float = 512.68880
private let braceExpectedMagnitude: Float = -70.93484
private let braceExpectedQ: Float = 87.5
private let braceTapThreshold: Float = -53.33838  // dB — matches .guitartap reference
private let freqTolerance: Float = 1.0  // Hz
private let magTolerance: Float  = 1.0  // dB
private let qTolerance: Float    = 1.0  // dimensionless

// plate-umik-1-swift-mac-1778816330.wav — Plate, UMIK-1 mic, 48 kHz.
// Full-session recording (mono float32, 48 kHz) covering all three plate
// phases (L → C → FLC).  Played back end-to-end through the plate pipeline,
// which auto-advances between phases on file playback so the run reaches
// .complete with all three peaks populated.
//
// Reference values from the matching .guitartap file
// (Tests/Plate/plate-umik-1-swift-mac-1778816330.guitartap):
//   fL  frequency: 67.11537 Hz   magnitude: -60.36113 dB   Q: 15.333
//   fC  frequency: 116.27016 Hz  magnitude: -52.80130 dB   Q: 26.333
//   fLC frequency: 35.35375 Hz   magnitude: -58.28925 dB   Q: 6.000
//   Tap detection threshold: -53.33838 dB
private let plateLExpectedFrequency: Float = 67.11537
private let plateLExpectedMagnitude: Float = -60.36113
private let plateLExpectedQ: Float = 15.333

private let plateCExpectedFrequency: Float = 116.27016
private let plateCExpectedMagnitude: Float = -52.80130
private let plateCExpectedQ: Float = 26.333

private let plateFlcExpectedFrequency: Float = 35.35375
private let plateFlcExpectedMagnitude: Float = -58.28925
private let plateFlcExpectedQ: Float = 6.000

private let plateTapThreshold: Float = -53.33838  // dB — matches .guitartap reference

// plate-umik-1-web-mac-3-taps.wav — Plate, UMIK-1, 48 kHz, recorded by the WEB app (Chrome) with
// numberOfTaps = 3 (3 taps PER PHASE, 9 total). Replaying at numberOfTaps = 3 averages each phase.
// Expected values are the WEB capture's (companion .guitartap, same recording) — so a pass means
// Swift agrees with the web on multi-tap material averaging. (Close to, not equal to, the separate
// Swift 3-tap capture L66.6/C117.1/FLC35.5.)
private let plate3TapLExpectedFrequency: Float = 68.2587
private let plate3TapLExpectedMagnitude: Float = -71.5858
private let plate3TapLExpectedQ: Float = 15.667
private let plate3TapCExpectedFrequency: Float = 117.4681
private let plate3TapCExpectedMagnitude: Float = -56.5436
private let plate3TapCExpectedQ: Float = 26.667
private let plate3TapFlcExpectedFrequency: Float = 35.3011
private let plate3TapFlcExpectedMagnitude: Float = -63.6008  // peak read off the AVERAGED spectrum
private let plate3TapFlcExpectedQ: Float = 6.000
private let plate3TapThreshold: Float = -40.0  // dB — matches the .guitartap reference
// REG-P2 uses a tighter magnitude tolerance than the generic 1.0 dB.  The averaged
// values are deterministic across platforms, so they agree far more closely than a
// single tap would; 0.5 dB still leaves headroom for FFT-library differences while
// reliably catching a regression to last-tap selection (the masked deltas were
// fL 0.94, fC 0.81, fLC 2.62 dB — all caught at 0.5).
private let plate3TapMagTolerance: Float = 0.5  // dB

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
    @Test func REG_B1_braceSingleTap_producesExpectedPeak() throws {
        let stem = "brace-umik-1-swift-mac-1778816093"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }
        let calURL = testBundle.url(forResource: "7108913", withExtension: "txt")

        let sut = TapToneAnalyzer.forTesting()
        sut.tapDetectionThreshold = braceTapThreshold
        try sut.playFileForTesting(url: url, measurementType: .brace, calibrationURL: calURL)

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
        #expect(freqDelta < freqTolerance,
                "Peak frequency: expected \(braceExpectedFrequency) Hz ±\(freqTolerance), got \(dominant.frequency) Hz (delta \(freqDelta))")

        // 4. Verify dominant peak magnitude.
        let magDelta = abs(dominant.magnitude - braceExpectedMagnitude)
        #expect(magDelta < magTolerance,
                "Peak magnitude: expected \(braceExpectedMagnitude) dB ±\(magTolerance), got \(dominant.magnitude) dB (delta \(magDelta))")

        // 5. Verify dominant peak Q factor.
        let qDelta = abs(dominant.quality - braceExpectedQ)
        #expect(qDelta < qTolerance,
                "Peak Q factor: expected \(braceExpectedQ) ±\(qTolerance), got \(dominant.quality) (delta \(qDelta))")
    }

    // MARK: - REG-G1: O'Brien single-tap generic guitar

    // Recording 5.wav — Generic guitar, single-tap, 48 kHz.
    // Reference values from the Recording 5.guitartap file (Tests/O'Brien/).
    // Settings: peakMinThreshold = -76, tapDetectionThreshold = -40,
    //           measurementType = .generic, numberOfTaps = 1.
    //           FFT size is a constant (65536) inside RealtimeFFTAnalyzer.
    private static let g1AirFreq: Float = 87.30731
    private static let g1AirMag: Float  = -45.351357
    private static let g1TopFreq: Float = 164.09756
    private static let g1TopMag: Float  = -36.67097
    private static let g1BackFreq: Float = 240.5668
    private static let g1BackMag: Float  = -54.567883

    /// REG-G1: Generic guitar single-tap — validates Air/Top/Back peaks.
    ///
    /// Loads a single-tap generic guitar recording and plays it through the
    /// full pipeline.  Verifies that:
    ///   1. The pipeline completes with 1 tap entry
    ///   2. Air, Top, Back frequencies and magnitudes match reference ± 1
    @Test func REG_G1_genericGuitarSingleTap_producesExpectedPeaks() throws {
        let stem = "Recording 5"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }

        let sut = TapToneAnalyzer.forTesting()
        sut.peakMinThreshold = -76
        sut.tapDetectionThreshold = -40
        try sut.playFileForTesting(url: url, measurementType: .generic, numberOfTaps: 1)

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
        #expect(abs(airPeak.frequency - Self.g1AirFreq) < freqTolerance,
                "Air freq: expected \(Self.g1AirFreq) ±\(freqTolerance), got \(airPeak.frequency)")
        #expect(abs(airPeak.magnitude - Self.g1AirMag) < magTolerance,
                "Air mag: expected \(Self.g1AirMag) ±\(magTolerance), got \(airPeak.magnitude)")

        guard let topPeak = sut.getPeak(for: .top) else {
            Issue.record("No Top peak found")
            return
        }
        #expect(abs(topPeak.frequency - Self.g1TopFreq) < freqTolerance,
                "Top freq: expected \(Self.g1TopFreq) ±\(freqTolerance), got \(topPeak.frequency)")
        #expect(abs(topPeak.magnitude - Self.g1TopMag) < magTolerance,
                "Top mag: expected \(Self.g1TopMag) ±\(magTolerance), got \(topPeak.magnitude)")

        guard let backPeak = sut.getPeak(for: .back) else {
            Issue.record("No Back peak found")
            return
        }
        #expect(abs(backPeak.frequency - Self.g1BackFreq) < freqTolerance,
                "Back freq: expected \(Self.g1BackFreq) ±\(freqTolerance), got \(backPeak.frequency)")
        #expect(abs(backPeak.magnitude - Self.g1BackMag) < magTolerance,
                "Back mag: expected \(Self.g1BackMag) ±\(magTolerance), got \(backPeak.magnitude)")
    }

    // MARK: - REG-G2: O'Brien 8-tap generic guitar

    // Recording.wav — Generic guitar, 8-tap multi-tap, 48 kHz.
    // Reference values from the Recording.guitartap file (Tests/O'Brien/).
    // Settings: peakMinThreshold = -76, tapDetectionThreshold = -40,
    //           measurementType = .generic, numberOfTaps = 8.
    //           FFT size is a constant (65536) inside RealtimeFFTAnalyzer.

    // Average peaks
    private static let guitarAvgAirFreq: Float = 87.233154
    private static let guitarAvgAirMag: Float  = -44.34529
    private static let guitarAvgTopFreq: Float = 164.04662
    private static let guitarAvgTopMag: Float  = -35.105385
    private static let guitarAvgBackFreq: Float = 240.57095
    private static let guitarAvgBackMag: Float  = -55.152287

    // Per-tap expected values: (airFreq, airMag, topFreq, topMag, backFreq, backMag)
    private static let guitarPerTap: [(airFreq: Float, airMag: Float, topFreq: Float, topMag: Float, backFreq: Float, backMag: Float)] = [
        (87.20365, -46.083164, 164.15787, -37.15723,  296.5797,  -57.117817), // Tap 1
        (87.22049, -43.714653, 163.98953, -34.96168,  240.6308,  -54.930405), // Tap 2
        (87.21567, -44.400375, 164.00642, -36.064285, 240.54478, -56.384575), // Tap 3
        (87.23355, -43.930878, 164.02281, -34.72927,  240.58727, -55.048416), // Tap 4
        (87.23911, -44.447514, 164.09766, -36.650166, 240.52957, -54.569893), // Tap 5
        (87.258545,-44.08946,  164.05678, -34.239933, 240.63478, -54.847008), // Tap 6
        (87.2434,  -43.969948, 164.05476, -33.775253, 296.5151,  -54.0257),   // Tap 7
        (87.24372, -44.523045, 164.0366,  -34.412136, 240.49031, -54.849174), // Tap 8
    ]

    /// REG-G2: Generic guitar 8-tap — validates averaged and per-tap Air/Top/Back.
    ///
    /// Loads a live 8-tap generic guitar recording and plays it through the full
    /// pipeline.  Verifies that:
    ///   1. The pipeline completes with 8 tap entries
    ///   2. Averaged Air, Top, Back frequencies and magnitudes match reference ± 1
    ///   3. All 8 individual taps' Air, Top, Back frequencies and magnitudes match
    @Test func REG_G2_genericGuitar8Tap_producesExpectedPeaks() throws {
        let stem = "Recording"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }

        let sut = TapToneAnalyzer.forTesting()
        sut.peakMinThreshold = -76
        sut.tapDetectionThreshold = -40
        try sut.playFileForTesting(url: url, measurementType: .generic, numberOfTaps: 8)

        // 1. Pipeline should complete with 8 tap entries.
        #expect(sut.isMeasurementComplete, "isMeasurementComplete should be true")
        #expect(sut.tapEntries.count == 8,
                "Expected 8 tap entries, got \(sut.tapEntries.count)")

        // 2. Averaged peaks — use getPeak(for:), the same API the Results panel uses.
        guard let airPeak = sut.getPeak(for: .air) else {
            Issue.record("No averaged Air peak found")
            return
        }
        #expect(abs(airPeak.frequency - Self.guitarAvgAirFreq) < freqTolerance,
                "Avg Air freq: expected \(Self.guitarAvgAirFreq) ±\(freqTolerance), got \(airPeak.frequency)")
        #expect(abs(airPeak.magnitude - Self.guitarAvgAirMag) < magTolerance,
                "Avg Air mag: expected \(Self.guitarAvgAirMag) ±\(magTolerance), got \(airPeak.magnitude)")

        guard let topPeak = sut.getPeak(for: .top) else {
            Issue.record("No averaged Top peak found")
            return
        }
        #expect(abs(topPeak.frequency - Self.guitarAvgTopFreq) < freqTolerance,
                "Avg Top freq: expected \(Self.guitarAvgTopFreq) ±\(freqTolerance), got \(topPeak.frequency)")
        #expect(abs(topPeak.magnitude - Self.guitarAvgTopMag) < magTolerance,
                "Avg Top mag: expected \(Self.guitarAvgTopMag) ±\(magTolerance), got \(topPeak.magnitude)")

        guard let backPeak = sut.getPeak(for: .back) else {
            Issue.record("No averaged Back peak found")
            return
        }
        #expect(abs(backPeak.frequency - Self.guitarAvgBackFreq) < freqTolerance,
                "Avg Back freq: expected \(Self.guitarAvgBackFreq) ±\(freqTolerance), got \(backPeak.frequency)")
        #expect(abs(backPeak.magnitude - Self.guitarAvgBackMag) < magTolerance,
                "Avg Back mag: expected \(Self.guitarAvgBackMag) ±\(magTolerance), got \(backPeak.magnitude)")

        // 3. Per-tap peaks — uses TapEntry.resolvedModePeaks(), the same
        //    code path as MultiTapComparisonResultsView and PDF export.
        for (index, entry) in sut.tapEntries.enumerated() {
            let expected = Self.guitarPerTap[index]
            let tapLabel = "Tap \(index + 1)"

            let modePeaks = entry.resolvedModePeaks()

            // Air
            if let air = modePeaks[.air] {
                #expect(abs(air.frequency - expected.airFreq) < freqTolerance,
                        "\(tapLabel) Air freq: expected \(expected.airFreq) ±\(freqTolerance), got \(air.frequency)")
                #expect(abs(air.magnitude - expected.airMag) < magTolerance,
                        "\(tapLabel) Air mag: expected \(expected.airMag) ±\(magTolerance), got \(air.magnitude)")
            } else {
                Issue.record("\(tapLabel): no Air peak found in selected peaks")
            }

            // Top
            if let top = modePeaks[.top] {
                #expect(abs(top.frequency - expected.topFreq) < freqTolerance,
                        "\(tapLabel) Top freq: expected \(expected.topFreq) ±\(freqTolerance), got \(top.frequency)")
                #expect(abs(top.magnitude - expected.topMag) < magTolerance,
                        "\(tapLabel) Top mag: expected \(expected.topMag) ±\(magTolerance), got \(top.magnitude)")
            } else {
                Issue.record("\(tapLabel): no Top peak found in selected peaks")
            }

            // Back
            if let back = modePeaks[.back] {
                #expect(abs(back.frequency - expected.backFreq) < freqTolerance,
                        "\(tapLabel) Back freq: expected \(expected.backFreq) ±\(freqTolerance), got \(back.frequency)")
                #expect(abs(back.magnitude - expected.backMag) < magTolerance,
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
    @Test func REG_P1_plateFullSession_producesExpectedPeaks() throws {
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
        try sut.playFileForTesting(url: url, measurementType: .plate, calibrationURL: calURL)

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
        #expect(lFreqDelta < freqTolerance,
                "fL frequency: expected \(plateLExpectedFrequency) Hz ±\(freqTolerance), got \(lPeak.frequency) Hz (delta \(lFreqDelta))")
        let lMagDelta = abs(lPeak.magnitude - plateLExpectedMagnitude)
        #expect(lMagDelta < magTolerance,
                "fL magnitude: expected \(plateLExpectedMagnitude) dB ±\(magTolerance), got \(lPeak.magnitude) dB (delta \(lMagDelta))")
        let lQDelta = abs(lPeak.quality - plateLExpectedQ)
        #expect(lQDelta < qTolerance,
                "fL Q factor: expected \(plateLExpectedQ) ±\(qTolerance), got \(lPeak.quality) (delta \(lQDelta))")

        // 3b. fC peak.
        guard let cPeak = sut.selectedCrossPeak else {
            Issue.record("selectedCrossPeak is nil")
            return
        }
        let cFreqDelta = abs(cPeak.frequency - plateCExpectedFrequency)
        #expect(cFreqDelta < freqTolerance,
                "fC frequency: expected \(plateCExpectedFrequency) Hz ±\(freqTolerance), got \(cPeak.frequency) Hz (delta \(cFreqDelta))")
        let cMagDelta = abs(cPeak.magnitude - plateCExpectedMagnitude)
        #expect(cMagDelta < magTolerance,
                "fC magnitude: expected \(plateCExpectedMagnitude) dB ±\(magTolerance), got \(cPeak.magnitude) dB (delta \(cMagDelta))")
        let cQDelta = abs(cPeak.quality - plateCExpectedQ)
        #expect(cQDelta < qTolerance,
                "fC Q factor: expected \(plateCExpectedQ) ±\(qTolerance), got \(cPeak.quality) (delta \(cQDelta))")

        // 3c. fLC peak.
        guard let flcPeak = sut.selectedFlcPeak else {
            Issue.record("selectedFlcPeak is nil")
            return
        }
        let flcFreqDelta = abs(flcPeak.frequency - plateFlcExpectedFrequency)
        #expect(flcFreqDelta < freqTolerance,
                "fLC frequency: expected \(plateFlcExpectedFrequency) Hz ±\(freqTolerance), got \(flcPeak.frequency) Hz (delta \(flcFreqDelta))")
        let flcMagDelta = abs(flcPeak.magnitude - plateFlcExpectedMagnitude)
        #expect(flcMagDelta < magTolerance,
                "fLC magnitude: expected \(plateFlcExpectedMagnitude) dB ±\(magTolerance), got \(flcPeak.magnitude) dB (delta \(flcMagDelta))")
        let flcQDelta = abs(flcPeak.quality - plateFlcExpectedQ)
        #expect(flcQDelta < qTolerance,
                "fLC Q factor: expected \(plateFlcExpectedQ) ±\(qTolerance), got \(flcPeak.quality) (delta \(flcQDelta))")
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
    @Test func REG_P2_plateThreeTapsPerPhase_averagesEachPhase() throws {
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
        try sut.playFileForTesting(url: url, measurementType: .plate, numberOfTaps: 3, calibrationURL: calURL)

        printPlateDiagnostics(sut, phase: "P2 - 3 taps/phase", wavFile: stem)

        #expect(sut.materialTapPhase == .complete,
                "materialTapPhase should be .complete, got \(sut.materialTapPhase)")
        #expect(sut.isMeasurementComplete, "isMeasurementComplete should be true")

        guard let lPeak = sut.selectedLongitudinalPeak else { Issue.record("selectedLongitudinalPeak is nil"); return }
        #expect(abs(lPeak.frequency - plate3TapLExpectedFrequency) < freqTolerance,
                "fL frequency: expected \(plate3TapLExpectedFrequency) Hz, got \(lPeak.frequency) Hz")
        #expect(abs(lPeak.magnitude - plate3TapLExpectedMagnitude) < plate3TapMagTolerance,
                "fL magnitude: expected \(plate3TapLExpectedMagnitude) dB, got \(lPeak.magnitude) dB")
        #expect(abs(lPeak.quality - plate3TapLExpectedQ) < qTolerance,
                "fL Q: expected \(plate3TapLExpectedQ), got \(lPeak.quality)")

        guard let cPeak = sut.selectedCrossPeak else { Issue.record("selectedCrossPeak is nil"); return }
        #expect(abs(cPeak.frequency - plate3TapCExpectedFrequency) < freqTolerance,
                "fC frequency: expected \(plate3TapCExpectedFrequency) Hz, got \(cPeak.frequency) Hz")
        #expect(abs(cPeak.magnitude - plate3TapCExpectedMagnitude) < plate3TapMagTolerance,
                "fC magnitude: expected \(plate3TapCExpectedMagnitude) dB, got \(cPeak.magnitude) dB")
        #expect(abs(cPeak.quality - plate3TapCExpectedQ) < qTolerance,
                "fC Q: expected \(plate3TapCExpectedQ), got \(cPeak.quality)")

        guard let flcPeak = sut.selectedFlcPeak else { Issue.record("selectedFlcPeak is nil"); return }
        #expect(abs(flcPeak.frequency - plate3TapFlcExpectedFrequency) < freqTolerance,
                "fLC frequency: expected \(plate3TapFlcExpectedFrequency) Hz, got \(flcPeak.frequency) Hz")
        #expect(abs(flcPeak.magnitude - plate3TapFlcExpectedMagnitude) < plate3TapMagTolerance,
                "fLC magnitude: expected \(plate3TapFlcExpectedMagnitude) dB, got \(flcPeak.magnitude) dB")
        #expect(abs(flcPeak.quality - plate3TapFlcExpectedQ) < qTolerance,
                "fLC Q: expected \(plate3TapFlcExpectedQ), got \(flcPeak.quality)")
    }
}
