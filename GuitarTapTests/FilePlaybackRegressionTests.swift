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

// ---------------------------------------------------------------------------
// MARK: - Tests  (REG-B1)
// ---------------------------------------------------------------------------

@Suite("FilePlaybackRegression")
struct FilePlaybackRegressionTests {

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

        let sut = TapToneAnalyzer.forTesting()
        sut.tapDetectionThreshold = braceTapThreshold
        try sut.playFileForTesting(url: url, measurementType: .brace)

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
}
