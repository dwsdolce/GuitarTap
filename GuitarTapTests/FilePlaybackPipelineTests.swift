//
//  FilePlaybackPipelineTests.swift
//  GuitarTapTests
//
//  End-to-end regression tests for the WAV-file analysis pipeline.
//
//  The test helper `runFilePipeline` mirrors exactly what the app does when
//  playing back a file:
//    1. Load the WAV as mono Float PCM.
//    2. Feed samples through `RealtimeFFTAnalyzer.computeFFT` in fftSize-sample
//       chunks, exactly as `processAudioBuffer` → `performFFT` does at runtime.
//    3. Zero-pad and process the final partial frame, as `startFromFile` does
//       at end-of-file.
//    4. Take the frame with the highest peak magnitude (the "best" frame).
//    5. Run `TapToneAnalyzer.findPeaks` and `GuitarMode.classifyAll` on it.
//
//  The fftSize passed to `runFilePipeline` must match the one the app was using
//  when the expected values were recorded.  For Tap Test 2, the app was running
//  at fftSize = 65536 (see TapToneAnalysisView.swift init).
//
//  Adding a new test file:
//    1. Play the file through the app and record the displayed Air/Top/Back
//       frequency and magnitude values.
//    2. Add a `FilePipelineExpectation` constant below with those values.
//    3. Add one `@Test` function that calls `assertModePeaks`.
//
//  Test plan coverage: FP1–FP5
//

import Testing
import Foundation
import AVFoundation
@testable import GuitarTap

// Used to anchor Bundle(for:) lookups to the GuitarTapTests bundle.
private class TestBundleMarker: NSObject {}

private var testBundle: Bundle { Bundle(for: TestBundleMarker.self) }

// ---------------------------------------------------------------------------
// MARK: - Expected values per test file
// ---------------------------------------------------------------------------

/// Expected mode peak for a single guitar resonance mode.
private struct ModeExpectation {
    let mode: GuitarMode
    let frequency: Float   // Hz as reported by the app
    let magnitude: Float   // dBFS as reported by the app
    let freqTolerance: Float   // Hz
    let magTolerance: Float    // dB
}

/// All expected mode peaks for one test recording.
private struct FilePipelineExpectation {
    let filename: String
    let guitarType: GuitarType
    let fftSize: Int
    let peakMinThreshold: Float
    let modes: [ModeExpectation]
}

// Tap Test 2.wav — Classical guitar, fftSize=65536.
// Expected values established by playing the file through the app and reading
// the Analysis Results panel.  The file is 39,936 samples (0.906 s) at 44100 Hz,
// shorter than one 65536-sample frame, so the pipeline produces exactly one
// zero-padded FFT frame.
private let tapTest2 = FilePipelineExpectation(
    filename: "Tap Test 2.wav",
    guitarType: .classical,
    fftSize: 65536,
    peakMinThreshold: -65,
    modes: [
        ModeExpectation(mode: .air,  frequency: 104.8, magnitude: -59.7, freqTolerance: 2.0, magTolerance: 3.0),
        ModeExpectation(mode: .top,  frequency: 225.5, magnitude: -48.5, freqTolerance: 2.0, magTolerance: 3.0),
        ModeExpectation(mode: .back, frequency: 243.2, magnitude: -42.2, freqTolerance: 2.0, magTolerance: 3.0),
    ]
)

// ---------------------------------------------------------------------------
// MARK: - Pipeline helper
// ---------------------------------------------------------------------------

/// Load a WAV file and run it through the app's FFT → findPeaks → classifyAll
/// pipeline, returning the detected peaks and their mode classifications.
///
/// This mirrors the exact runtime path:
/// - `computeFFT` uses the same rectangular window, deinterleave, normalisation,
///   and dB conversion as `performFFT`.
/// - Full-size chunks are processed in order; the final partial chunk is
///   zero-padded to `fftSize`, matching `startFromFile`'s end-of-file handling.
/// - The frame with the highest peak magnitude is used for analysis, matching
///   the app's behaviour of displaying and freezing the strongest spectrum.
///
/// Returns nil if the file cannot be found or loaded.
@MainActor
private func runFilePipeline(
    _ expectation: FilePipelineExpectation
) -> (peaks: [ResonantPeak], modeMap: [UUID: GuitarMode], frequencies: [Float])? {

    // Locate file in the test bundle. Fixtures must be added to the GuitarTapTests
    // target's Copy Bundle Resources phase so they are available on all platforms.
    let stem = (expectation.filename as NSString).deletingPathExtension
    let ext  = (expectation.filename as NSString).pathExtension
    guard let url = testBundle.url(forResource: stem, withExtension: ext),
          FileManager.default.fileExists(atPath: url.path),
          let file = try? AVAudioFile(forReading: url) else { return nil }

    let sampleRate = file.fileFormat.sampleRate
    let frameCount = AVAudioFrameCount(file.length)
    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!,
        frameCapacity: frameCount
    ),
    (try? file.read(into: buffer)) != nil,
    let channelData = buffer.floatChannelData else { return nil }

    let allSamples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
    let fftSize = expectation.fftSize

    // Build the frequency axis (sampleRate is known from the file; no need for start())
    let binHz = Float(sampleRate) / Float(fftSize)
    let frequencies = (0..<fftSize / 2).map { Float($0) * binHz }

    // Create analyzer at the fftSize the app was using when values were recorded
    let fft = RealtimeFFTAnalyzer(fftSize: fftSize)

    // Process all full frames, then the final zero-padded partial frame
    var bestDB: [Float] = []
    var bestPeak: Float = -999

    let fullFrames = allSamples.count / fftSize
    for i in 0..<fullFrames {
        let chunk = Array(allSamples[(i * fftSize)..<((i + 1) * fftSize)])
        let db = fft.computeFFT(on: chunk)
        if let peak = db.max(), peak > bestPeak { bestPeak = peak; bestDB = db }
    }

    // Final partial frame: zero-pad to fftSize (matches startFromFile end-of-file logic)
    let remaining = allSamples.count % fftSize
    if remaining > 0 {
        var partial = Array(allSamples[(fullFrames * fftSize)...])
        partial.append(contentsOf: [Float](repeating: 0, count: fftSize - remaining))
        let db = fft.computeFFT(on: partial)
        if let peak = db.max(), peak > bestPeak { bestPeak = peak; bestDB = db }
    }

    guard !bestDB.isEmpty else { return nil }

    // findPeaks + classifyAll — same calls as TapToneAnalyzer.analyzeMagnitudes
    TapDisplaySettings.guitarType = expectation.guitarType
    let analyzer = TapToneAnalyzer(fftAnalyzer: fft)
    analyzer.peakMinThreshold = expectation.peakMinThreshold
    analyzer.minFrequency = 20
    analyzer.maxFrequency = 4000

    let peaks = analyzer.findPeaks(magnitudes: bestDB, frequencies: frequencies)
    let modeMap = GuitarMode.classifyAll(peaks, guitarType: expectation.guitarType)

    return (peaks, modeMap, frequencies)
}

// ---------------------------------------------------------------------------
// MARK: - Assertion helper
// ---------------------------------------------------------------------------

/// Assert that every `ModeExpectation` in `expectation.modes` is satisfied by
/// the pipeline result.  Each expected mode must have exactly one classified
/// peak whose frequency and magnitude are within the stated tolerances.
@MainActor
private func assertModePeaks(
    _ expectation: FilePipelineExpectation,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard let result = runFilePipeline(expectation) else {
        Issue.record("\(expectation.filename) not found or could not be loaded",
                     sourceLocation: sourceLocation)
        return
    }

    for expected in expectation.modes {
        let matchingPeaks = result.peaks.filter { result.modeMap[$0.id] == expected.mode }

        #expect(!matchingPeaks.isEmpty,
                "No peak classified as .\(expected.mode) in \(expectation.filename)",
                sourceLocation: sourceLocation)

        if let peak = matchingPeaks.first {
            #expect(
                abs(peak.frequency - expected.frequency) < expected.freqTolerance,
                ".\(expected.mode) frequency: expected \(expected.frequency) Hz ±\(expected.freqTolerance), got \(peak.frequency) Hz",
                sourceLocation: sourceLocation
            )
            #expect(
                abs(peak.magnitude - expected.magnitude) < expected.magTolerance,
                ".\(expected.mode) magnitude: expected \(expected.magnitude) dB ±\(expected.magTolerance), got \(peak.magnitude) dB",
                sourceLocation: sourceLocation
            )
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Tests  (FP1–FP5)
// ---------------------------------------------------------------------------

@Suite("FilePlaybackPipeline")
@MainActor
struct FilePlaybackPipelineTests {

    // FP1: The reference WAV file loads and contains audio at the expected sample rate.
    @Test func FP1_tapTest2_loadsSuccessfully() {
        let stem = (tapTest2.filename as NSString).deletingPathExtension
        let ext  = (tapTest2.filename as NSString).pathExtension
        guard let url = testBundle.url(forResource: stem, withExtension: ext),
              FileManager.default.fileExists(atPath: url.path) else {
            Issue.record("\(tapTest2.filename) not found — skipping")
            return
        }
        guard let file = try? AVAudioFile(forReading: url) else {
            Issue.record("Could not open \(tapTest2.filename)")
            return
        }
        #expect(file.length > 0, "WAV file should contain audio samples")
        #expect(file.fileFormat.sampleRate == 44100,
                "Expected 44100 Hz sample rate, got \(file.fileFormat.sampleRate)")
    }

    // FP2: Air resonance (Helmholtz) is detected at the expected frequency and magnitude.
    @Test func FP2_tapTest2_airPeakNear105Hz() {
        assertModePeaks(FilePipelineExpectation(
            filename: tapTest2.filename,
            guitarType: tapTest2.guitarType,
            fftSize: tapTest2.fftSize,
            peakMinThreshold: tapTest2.peakMinThreshold,
            modes: [tapTest2.modes.first { $0.mode == .air }!]
        ))
    }

    // FP3: Top plate resonance is detected at the expected frequency and magnitude.
    @Test func FP3_tapTest2_topPeakNear225Hz() {
        assertModePeaks(FilePipelineExpectation(
            filename: tapTest2.filename,
            guitarType: tapTest2.guitarType,
            fftSize: tapTest2.fftSize,
            peakMinThreshold: tapTest2.peakMinThreshold,
            modes: [tapTest2.modes.first { $0.mode == .top }!]
        ))
    }

    // FP4: Back plate resonance is detected at the expected frequency and magnitude.
    @Test func FP4_tapTest2_backPeakNear243Hz() {
        assertModePeaks(FilePipelineExpectation(
            filename: tapTest2.filename,
            guitarType: tapTest2.guitarType,
            fftSize: tapTest2.fftSize,
            peakMinThreshold: tapTest2.peakMinThreshold,
            modes: [tapTest2.modes.first { $0.mode == .back }!]
        ))
    }

    // FP5: All three modes are present simultaneously and ordered Air < Top < Back.
    @Test func FP5_tapTest2_allThreeModesPresentAndOrdered() {
        assertModePeaks(tapTest2)

        guard let result = runFilePipeline(tapTest2) else { return }

        let air  = result.peaks.first { result.modeMap[$0.id] == .air }
        let top  = result.peaks.first { result.modeMap[$0.id] == .top }
        let back = result.peaks.first { result.modeMap[$0.id] == .back }

        if let air, let top {
            #expect(air.frequency < top.frequency,
                    "Air (\(air.frequency) Hz) should be lower than Top (\(top.frequency) Hz)")
        }
        if let top, let back {
            #expect(top.frequency < back.frequency,
                    "Top (\(top.frequency) Hz) should be lower than Back (\(back.frequency) Hz)")
        }
    }
}
