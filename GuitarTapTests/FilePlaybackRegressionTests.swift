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
//  Test plan coverage: REG-B1
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

        let sut = TapToneAnalyzer.forTesting(fftSize: 16384)
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
}
