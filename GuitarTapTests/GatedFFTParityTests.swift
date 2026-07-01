//
//  GatedFFTParityTests.swift
//  GuitarTapTests
//
//  Parity tests for computeGatedFFT: feed identical synthetic signals and verify
//  the output magnitudes match the expected values.  The companion Python test
//  (test_gated_fft_parity.py) uses the same signal and expected values, so any
//  systematic difference between the two implementations will show up as a
//  failing test on one side only.
//
//  Test plan coverage: GFFT1–GFFT5
//
// @parity test/gated-fft

import Testing
import Foundation
import Accelerate
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

/// Generate a synthetic PCM signal consisting of two sine waves.
///
/// - Parameters:
///   - sampleRate: Sample rate in Hz.
///   - duration:   Duration in seconds.
///   - freq1:      First sine frequency in Hz.
///   - amp1:       First sine amplitude (linear, 0–1).
///   - freq2:      Second sine frequency in Hz.
///   - amp2:       Second sine amplitude (linear, 0–1).
/// - Returns: Array of Float samples.
private func makeTwoToneSignal(
    sampleRate: Double = 48000,
    duration: Double = 0.4,
    freq1: Double,
    amp1: Double,
    freq2: Double,
    amp2: Double
) -> [Float] {
    let count = Int(sampleRate * duration)
    return (0..<count).map { i in
        let t = Double(i) / sampleRate
        let s1 = amp1 * sin(2.0 * .pi * freq1 * t)
        let s2 = amp2 * sin(2.0 * .pi * freq2 * t)
        return Float(s1 + s2)
    }
}

/// Find the magnitude (in dB) at the bin closest to `targetHz` in the output
/// of `computeGatedFFT`.
private func magnitudeAtFrequency(
    _ targetHz: Float,
    magnitudes: [Float],
    frequencies: [Float]
) -> Float? {
    guard !frequencies.isEmpty else { return nil }
    var bestIdx = 0
    var bestDist = Float.greatestFiniteMagnitude
    for (i, f) in frequencies.enumerated() {
        let dist = abs(f - targetHz)
        if dist < bestDist {
            bestDist = dist
            bestIdx = i
        }
    }
    return magnitudes[bestIdx]
}

// ---------------------------------------------------------------------------
// MARK: - Gated FFT Parity Tests
// ---------------------------------------------------------------------------

@Suite("GatedFFTParityTests")
struct GatedFFTParityTests {

    // GFFT1: A single 100 Hz sine at amplitude 0.5.
    // Python reports: -15.72 dB.  Swift should match within ~1 dB.
    @Test func singleTone100Hz_magnitudeIsReasonable() {
        let sampleRate: Double = 48000
        let signal = makeTwoToneSignal(
            sampleRate: sampleRate, duration: 0.4,
            freq1: 100, amp1: 0.5,
            freq2: 0, amp2: 0
        )
        let fft = RealtimeFFTAnalyzer()
        let (mags, freqs) = fft.computeGatedFFT(samples: signal, sampleRate: sampleRate)

        let mag100 = magnitudeAtFrequency(100, magnitudes: mags, frequencies: freqs)!
        // Python: -15.72 dB.  Check Swift is within 1 dB of that.
        #expect(abs(mag100 - (-15.72)) < 1.0,
                "100 Hz: Swift=\(mag100) dB, Python=-15.72 dB — difference > 1 dB")
    }

    // GFFT2: Two tones at 67 Hz and 117 Hz with known amplitudes.
    // Python reports: 67 Hz = -49.74 dB, 117 Hz = -29.55 dB, delta = 20.19 dB.
    @Test func twoTone_67Hz_and_117Hz_magnitudesMatch() {
        let sampleRate: Double = 48000
        let signal = makeTwoToneSignal(
            sampleRate: sampleRate, duration: 0.4,
            freq1: 67, amp1: 0.01,
            freq2: 117, amp2: 0.1
        )
        let fft = RealtimeFFTAnalyzer()
        let (mags, freqs) = fft.computeGatedFFT(samples: signal, sampleRate: sampleRate)

        let m67 = magnitudeAtFrequency(67, magnitudes: mags, frequencies: freqs)!
        let m117 = magnitudeAtFrequency(117, magnitudes: mags, frequencies: freqs)!
        let delta = m117 - m67

        // Check each magnitude matches Python within 1 dB
        #expect(abs(m67 - (-49.74)) < 1.0,
                "67 Hz: Swift=\(m67) dB, Python=-49.74 dB — difference > 1 dB")
        #expect(abs(m117 - (-29.55)) < 1.0,
                "117 Hz: Swift=\(m117) dB, Python=-29.55 dB — difference > 1 dB")
        #expect(abs(delta - 20.19) < 1.0,
                "Delta: Swift=\(delta) dB, Python=20.19 dB — difference > 1 dB")
    }

    // GFFT3: Exact bin-centred tones to eliminate spectral leakage.
    // Python reports: 67.3828 Hz = -49.70 dB, 117.1875 Hz = -29.51 dB, delta = 20.19 dB.
    @Test func binCentred_tones_exactMagnitudes() {
        let sampleRate: Double = 48000
        let paddedSize = 32768
        let binWidth = sampleRate / Double(paddedSize)
        let freq1 = Double(46) * binWidth   // 67.3828125 Hz
        let freq2 = Double(80) * binWidth   // 117.1875 Hz

        let signal = makeTwoToneSignal(
            sampleRate: sampleRate, duration: 0.4,
            freq1: freq1, amp1: 0.01,
            freq2: freq2, amp2: 0.1
        )
        let fft = RealtimeFFTAnalyzer()
        let (mags, freqs) = fft.computeGatedFFT(samples: signal, sampleRate: sampleRate)

        let m1 = magnitudeAtFrequency(Float(freq1), magnitudes: mags, frequencies: freqs)!
        let m2 = magnitudeAtFrequency(Float(freq2), magnitudes: mags, frequencies: freqs)!
        let delta = m2 - m1

        #expect(abs(m1 - (-49.70)) < 1.0,
                "\(freq1) Hz: Swift=\(m1) dB, Python=-49.70 dB — difference > 1 dB")
        #expect(abs(m2 - (-29.51)) < 1.0,
                "\(freq2) Hz: Swift=\(m2) dB, Python=-29.51 dB — difference > 1 dB")
        #expect(abs(delta - 20.19) < 1.0,
                "Delta: Swift=\(delta) dB, Python=20.19 dB — difference > 1 dB")
    }

    // GFFT4: Silence should produce all bins near noise floor (< -100 dB).
    @Test func silence_allBinsBelowNoiseFloor() {
        let sampleRate: Double = 48000
        let count = Int(sampleRate * 0.4)
        let signal = [Float](repeating: 0, count: count)
        let fft = RealtimeFFTAnalyzer()
        let (mags, _) = fft.computeGatedFFT(samples: signal, sampleRate: sampleRate)

        let maxMag = mags.max() ?? 0
        #expect(maxMag < -100,
                "All bins should be below -100 dB for silence, max = \(maxMag)")
    }

    // GFFT5: Verify that HANN_DENORM window produces values matching Python.
    // After fixing the window from HANN_NORM to HANN_DENORM, the bin-centred
    // tone should match Python within 1 dB (previously off by ~4.26 dB).
    @Test func afterFix_binCentred_matchesPython() {
        let N = 32768
        let sampleRate: Double = 48000
        let targetBin = 46
        let amplitude: Float = 0.01
        let sampleCount = Int(sampleRate * 0.4)
        let freq = Double(targetBin) * sampleRate / Double(N)

        var signal = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let t = Float(i) / Float(sampleRate)
            signal[i] = amplitude * sin(2.0 * Float.pi * Float(freq) * t)
        }

        let fft = RealtimeFFTAnalyzer()
        let (mags, freqs) = fft.computeGatedFFT(samples: signal, sampleRate: sampleRate)
        let swiftDB = magnitudeAtFrequency(Float(freq), magnitudes: mags, frequencies: freqs)!

        // Python compute_gated_fft reports -49.70 dB for this signal.
        #expect(abs(swiftDB - (-49.70)) < 1.0,
                "bin 46: Swift=\(swiftDB) dB, Python=-49.70 dB — difference > 1 dB")
    }
}
