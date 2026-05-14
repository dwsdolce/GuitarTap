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

// brace-umik-1-python-mac-1778452289.wav — Brace bar, UMIK-1 mic, 48 kHz.
// Saved gated capture: 19200 frames (400 ms) at 48000 Hz.
// Reference values from the .guitartap file and confirmed by running
// playFileForTesting in both Swift and Python:
//   Peak frequency: 512.59 Hz
//   Peak magnitude: -65.69 dB
//   Tap detection threshold: -62 dB (from the .guitartap reference file)
// The test uses tolerances per the test plan: ±1.0 Hz, ±1.0 dB.
private let braceExpectedFrequency: Float = 512.59
private let braceExpectedMagnitude: Float = -65.69
private let braceTapThreshold: Float = -62.0  // dB — matches original measurement
private let freqTolerance: Float = 1.0  // Hz
private let magTolerance: Float  = 1.0  // dB
private let qTolerance: Float    = 1.0  // dimensionless

// Plate longitudinal (L) capture WAV — saved gated capture from interactive
// measurement.  19200 frames (400 ms) at 48000 Hz, IEEE float 32-bit mono.
// Reference values from the interactive measurement session:
//   fL frequency: 66.6 Hz
//   fL magnitude: -58.4 dB
//   fL Q factor:  15.0
private let plateLExpectedFrequency: Float = 66.6
private let plateLExpectedMagnitude: Float = -58.4
private let plateLExpectedQ: Float = 15.0

// Plate cross-grain (C) capture WAV — saved gated capture from interactive
// measurement.  19200 frames (400 ms) at 48000 Hz, IEEE float 32-bit mono.
// Reference values from the interactive measurement session:
//   fC frequency: 117.5 Hz
//   fC magnitude: -51.3 dB
//   fC Q factor:  26.7
private let plateCExpectedFrequency: Float = 117.5
private let plateCExpectedMagnitude: Float = -51.3
private let plateCExpectedQ: Float = 26.7

// Plate FLC (shear/torsional) capture WAV — saved gated capture from interactive
// measurement.  19200 frames (400 ms) at 48000 Hz, IEEE float 32-bit mono.
// Reference values from the interactive measurement session:
//   fLC frequency: 33.6 Hz
//   fLC magnitude: -59.0 dB
//   fLC Q factor:  5.8
private let plateFlcExpectedFrequency: Float = 33.6
private let plateFlcExpectedMagnitude: Float = -59.0
private let plateFlcExpectedQ: Float = 5.8

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
        // FileLogger is private, so we construct the path manually.
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/GuitarTap")
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
    // Loads a saved brace capture WAV (400 ms, 48 kHz) and plays it through
    // the full pipeline with measurementType = .brace.  Verifies that:
    //   1. The pipeline completes (materialTapPhase == .complete)
    //   2. At least one longitudinal peak is detected
    //   3. The dominant peak frequency matches the .guitartap reference ± 1 Hz
    //   4. The dominant peak magnitude matches the reference ± 1 dB
    @Test func REG_B1_braceSingleTap_producesExpectedPeak() throws {
        let stem = "brace-umik-1-python-mac-1778452289"
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

    // MARK: - REG-P1: Plate longitudinal (L) single-tap

    // swift_Capturing_Longitudinal_2026-05-13T17-35-52Z.wav — Plate, saved gated capture, 48 kHz.
    // Saved gated capture: 19200 frames (400 ms) at 48000 Hz.
    // Reference values from the interactive measurement session.
    // The test feeds this single L capture through the plate pipeline and verifies
    // the auto-selected longitudinal peak matches the interactive result.
    // Since only L data is provided, the pipeline will auto-advance to .capturingCross
    // but will not reach .complete (no C or FLC taps follow).

    /// REG-P1: Plate longitudinal single-tap — known WAV produces expected fL peak.
    ///
    /// Loads a saved plate longitudinal capture WAV (400 ms, 48 kHz) and plays it
    /// through the full pipeline with measurementType = .plate.  Verifies that:
    ///   1. The pipeline auto-advances past L (materialTapPhase == .capturingCross)
    ///   2. At least one longitudinal peak is detected
    ///   3. The dominant peak frequency matches the reference ± 1 Hz
    ///   4. The dominant peak magnitude matches the reference ± 1 dB
    ///   5. The Q factor matches the reference ± 1
    @Test func REG_P1_plateLongitudinalSingleTap_producesExpectedPeak() throws {
        let stem = "swift_Capturing_Longitudinal_2026-05-13T17-35-52Z"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }
        let calURL = testBundle.url(forResource: "7108913", withExtension: "txt")

        let sut = TapToneAnalyzer.forTesting()
        // Plate mode uses relative detection (noise floor + headroom), so the
        // threshold is less critical than for guitar/brace absolute thresholds.
        // Use a low threshold to ensure the tap is detected from the saved capture.
        sut.tapDetectionThreshold = -62.0
        try sut.playFileForTesting(url: url, measurementType: .plate, calibrationURL: calURL,
                                   plateTapPhase: .capturingLongitudinal)

        printPlateDiagnostics(sut, phase: "P1 — Longitudinal", wavFile: stem)

        // 1. Pipeline should auto-advance past L.
        //    With plateTapPhase: .capturingLongitudinal the run loop exits as soon as
        //    the phase advances (e.g. to .capturingCross), without waiting for
        //    subsequent phases to time out.
        let phase = sut.materialTapPhase
        #expect(phase != .capturingLongitudinal && phase != .notStarted,
                "materialTapPhase should have advanced past L, got \(phase)")

        // 2. Longitudinal peaks should be populated.
        #expect(!sut.longitudinalPeaks.isEmpty,
                "longitudinalPeaks should not be empty")

        // 3. Verify the auto-selected longitudinal peak.
        guard let dominant = sut.selectedLongitudinalPeak else {
            Issue.record("selectedLongitudinalPeak is nil")
            return
        }

        // 4. Verify frequency.
        let freqDelta = abs(dominant.frequency - plateLExpectedFrequency)
        #expect(freqDelta < freqTolerance,
                "fL frequency: expected \(plateLExpectedFrequency) Hz ±\(freqTolerance), got \(dominant.frequency) Hz (delta \(freqDelta))")

        // 5. Verify magnitude.
        let magDelta = abs(dominant.magnitude - plateLExpectedMagnitude)
        #expect(magDelta < magTolerance,
                "fL magnitude: expected \(plateLExpectedMagnitude) dB ±\(magTolerance), got \(dominant.magnitude) dB (delta \(magDelta))")

        // 6. Verify Q factor.
        let qDelta = abs(dominant.quality - plateLExpectedQ)
        #expect(qDelta < qTolerance,
                "fL Q factor: expected \(plateLExpectedQ) ±\(qTolerance), got \(dominant.quality) (delta \(qDelta))")
    }

    // MARK: - REG-P2: Plate cross-grain (C) single-tap

    // swift_Capturing_Cross-grain_2026-05-13T17-36-18Z.wav — Plate, saved gated capture, 48 kHz.
    // Saved gated capture: 19200 frames (400 ms) at 48000 Hz.
    // Reference values from the interactive measurement session.
    // The test starts the pipeline in .capturingCross (via plateTapPhase) so the
    // WAV's tap is interpreted as a cross-grain tap, and exits as soon as that
    // phase advances — no need to wait for FLC to time out.

    /// REG-P2: Plate cross-grain single-tap — known WAV produces expected fC peak.
    @Test func REG_P2_plateCrossSingleTap_producesExpectedPeak() throws {
        let stem = "swift_Capturing_Cross-grain_2026-05-13T17-36-18Z"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }
        let calURL = testBundle.url(forResource: "7108913", withExtension: "txt")

        let sut = TapToneAnalyzer.forTesting()
        sut.tapDetectionThreshold = -62.0
        try sut.playFileForTesting(url: url, measurementType: .plate, calibrationURL: calURL,
                                   plateTapPhase: .capturingCross)

        printPlateDiagnostics(sut, phase: "P2 — Cross-grain", wavFile: stem)

        // 1. Pipeline should auto-advance past C.
        let phase = sut.materialTapPhase
        #expect(phase != .capturingCross && phase != .notStarted,
                "materialTapPhase should have advanced past C, got \(phase)")

        // 2. Cross peaks should be populated.
        #expect(!sut.crossPeaks.isEmpty,
                "crossPeaks should not be empty")

        // 3. Verify the auto-selected cross peak.
        guard let dominant = sut.selectedCrossPeak else {
            Issue.record("selectedCrossPeak is nil")
            return
        }

        // 4. Verify frequency.
        let freqDelta = abs(dominant.frequency - plateCExpectedFrequency)
        #expect(freqDelta < freqTolerance,
                "fC frequency: expected \(plateCExpectedFrequency) Hz ±\(freqTolerance), got \(dominant.frequency) Hz (delta \(freqDelta))")

        // 5. Verify magnitude.
        let magDelta = abs(dominant.magnitude - plateCExpectedMagnitude)
        #expect(magDelta < magTolerance,
                "fC magnitude: expected \(plateCExpectedMagnitude) dB ±\(magTolerance), got \(dominant.magnitude) dB (delta \(magDelta))")

        // 6. Verify Q factor.
        let qDelta = abs(dominant.quality - plateCExpectedQ)
        #expect(qDelta < qTolerance,
                "fC Q factor: expected \(plateCExpectedQ) ±\(qTolerance), got \(dominant.quality) (delta \(qDelta))")
    }

    // MARK: - REG-P3: Plate FLC (shear/torsional) single-tap

    // swift_Capturing_FLC_2026-05-13T17-36-29Z.wav — Plate, saved gated capture, 48 kHz.
    // Saved gated capture: 19200 frames (400 ms) at 48000 Hz.
    // Reference values from the interactive measurement session.
    // The test starts the pipeline in .capturingFlc (via plateTapPhase) so the
    // WAV's tap is interpreted as an FLC tap, and exits as soon as that phase
    // advances to .complete.

    /// REG-P3: Plate FLC single-tap — known WAV produces expected fLC peak.
    @Test func REG_P3_plateFlcSingleTap_producesExpectedPeak() throws {
        let stem = "swift_Capturing_FLC_2026-05-13T17-36-29Z"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }
        let calURL = testBundle.url(forResource: "7108913", withExtension: "txt")

        let sut = TapToneAnalyzer.forTesting()
        sut.tapDetectionThreshold = -62.0
        try sut.playFileForTesting(url: url, measurementType: .plate, calibrationURL: calURL,
                                   plateTapPhase: .capturingFlc)

        printPlateDiagnostics(sut, phase: "P3 — FLC", wavFile: stem)

        // 1. Pipeline should advance to .complete.
        let phase = sut.materialTapPhase
        #expect(phase == .complete,
                "materialTapPhase should be .complete, got \(phase)")

        // 2. FLC peaks should be populated.
        #expect(!sut.flcPeaks.isEmpty,
                "flcPeaks should not be empty")

        // 3. Verify the auto-selected FLC peak.
        guard let dominant = sut.selectedFlcPeak else {
            Issue.record("selectedFlcPeak is nil")
            return
        }

        // 4. Verify frequency.
        let freqDelta = abs(dominant.frequency - plateFlcExpectedFrequency)
        #expect(freqDelta < freqTolerance,
                "fLC frequency: expected \(plateFlcExpectedFrequency) Hz ±\(freqTolerance), got \(dominant.frequency) Hz (delta \(freqDelta))")

        // 5. Verify magnitude.
        let magDelta = abs(dominant.magnitude - plateFlcExpectedMagnitude)
        #expect(magDelta < magTolerance,
                "fLC magnitude: expected \(plateFlcExpectedMagnitude) dB ±\(magTolerance), got \(dominant.magnitude) dB (delta \(magDelta))")

        // 6. Verify Q factor.
        let qDelta = abs(dominant.quality - plateFlcExpectedQ)
        #expect(qDelta < qTolerance,
                "fLC Q factor: expected \(plateFlcExpectedQ) ±\(qTolerance), got \(dominant.quality) (delta \(qDelta))")
    }
}
