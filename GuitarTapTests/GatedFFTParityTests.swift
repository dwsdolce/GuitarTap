//
//  GatedFFTParityTests.swift
//  GuitarTapTests
//
//  Parity tests for computeGatedFFT: feed identical synthetic signals and verify the
//  output magnitudes match the expected values. Signals and expected values come from the
//  shared oracle (parity-oracle.json), so the Python and web suites feed the same tones
//  and assert the same dB - any systematic difference between the implementations shows up
//  as a one-sided failure rather than as three sets of numbers drifting apart.
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

    /// The one tolerance every edition applies to gated-FFT dB.
    // Same-edition bar: zero. See FilePlaybackRegressionTests for why Swift does not
    // assert against the cross-edition tolerance.
    private static let tol: Float = ParityOracle.selfTolerance(\.gatedFftDb)

    // GFFT1: a single sine at the amplitude the oracle declares.
    @Test func singleTone100Hz_magnitudeIsReasonable() {
        let sampleRate: Double = 48000
        let gfft = ParityOracle.gated("GFFT1")
        let tone = gfft.toneList[0]
        let expected = gfft.expectedDb(at: tone.hz)
        let signal = makeTwoToneSignal(
            sampleRate: sampleRate, duration: 0.4,
            freq1: tone.hz, amp1: tone.amplitude,
            freq2: 0, amp2: 0
        )
        let fft = RealtimeFFTAnalyzer()
        let (mags, freqs) = fft.computeGatedFFT(samples: signal, sampleRate: sampleRate)

        let mag100 = magnitudeAtFrequency(Float(tone.hz), magnitudes: mags, frequencies: freqs)!
        #expect(abs(mag100 - expected) <= Self.tol,
                "\(tone.hz) Hz: Swift=\(mag100) dB, oracle=\(expected) dB — difference > \(Self.tol) dB")
    }

    // GFFT2: two tones at the plate-C capture frequencies that exposed the discrepancy.
    @Test func twoTone_67Hz_and_117Hz_magnitudesMatch() {
        let sampleRate: Double = 48000
        let gfft = ParityOracle.gated("GFFT2")
        let t1 = gfft.toneList[0], t2 = gfft.toneList[1]
        let exp1 = gfft.expectedDb(at: t1.hz), exp2 = gfft.expectedDb(at: t2.hz)
        let expDelta = gfft.deltaDb ?? (exp2 - exp1)
        let signal = makeTwoToneSignal(
            sampleRate: sampleRate, duration: 0.4,
            freq1: t1.hz, amp1: t1.amplitude,
            freq2: t2.hz, amp2: t2.amplitude
        )
        let fft = RealtimeFFTAnalyzer()
        let (mags, freqs) = fft.computeGatedFFT(samples: signal, sampleRate: sampleRate)

        let m67 = magnitudeAtFrequency(Float(t1.hz), magnitudes: mags, frequencies: freqs)!
        let m117 = magnitudeAtFrequency(Float(t2.hz), magnitudes: mags, frequencies: freqs)!
        let delta = m117 - m67

        #expect(abs(m67 - exp1) <= Self.tol,
                "\(t1.hz) Hz: Swift=\(m67) dB, oracle=\(exp1) dB — difference > \(Self.tol) dB")
        #expect(abs(m117 - exp2) <= Self.tol,
                "\(t2.hz) Hz: Swift=\(m117) dB, oracle=\(exp2) dB — difference > \(Self.tol) dB")
        #expect(abs(delta - expDelta) <= Self.tol,
                "Delta: Swift=\(delta) dB, oracle=\(expDelta) dB — difference > \(Self.tol) dB")
    }

    // GFFT3: exact bin-centred tones to eliminate spectral leakage. With paddedSize 32768
    // the oracle's frequencies are exact multiples of the 1.46484375 Hz bin width (bins 46, 80).
    @Test func binCentred_tones_exactMagnitudes() {
        let sampleRate: Double = 48000
        let gfft = ParityOracle.gated("GFFT3")
        let t1 = gfft.toneList[0], t2 = gfft.toneList[1]
        let exp1 = gfft.expectedDb(at: t1.hz), exp2 = gfft.expectedDb(at: t2.hz)
        let expDelta = gfft.deltaDb ?? (exp2 - exp1)

        let signal = makeTwoToneSignal(
            sampleRate: sampleRate, duration: 0.4,
            freq1: t1.hz, amp1: t1.amplitude,
            freq2: t2.hz, amp2: t2.amplitude
        )
        let fft = RealtimeFFTAnalyzer()
        let (mags, freqs) = fft.computeGatedFFT(samples: signal, sampleRate: sampleRate)

        let m1 = magnitudeAtFrequency(Float(t1.hz), magnitudes: mags, frequencies: freqs)!
        let m2 = magnitudeAtFrequency(Float(t2.hz), magnitudes: mags, frequencies: freqs)!
        let delta = m2 - m1

        #expect(abs(m1 - exp1) <= Self.tol,
                "\(t1.hz) Hz: Swift=\(m1) dB, oracle=\(exp1) dB — difference > \(Self.tol) dB")
        #expect(abs(m2 - exp2) <= Self.tol,
                "\(t2.hz) Hz: Swift=\(m2) dB, oracle=\(exp2) dB — difference > \(Self.tol) dB")
        #expect(abs(delta - expDelta) <= Self.tol,
                "Delta: Swift=\(delta) dB, oracle=\(expDelta) dB — difference > \(Self.tol) dB")
    }

    // GFFT4: silence reads exactly the oracle's value — -inf in every bin. The oracle used to record
    // only a bound (maxDbBelow: -100) because JSON cannot hold infinity; it now stores "-Infinity"
    // as a string and all three editions compare exactly (#17 F44).
    @Test func silence_allBinsBelowNoiseFloor() {
        let sampleRate: Double = 48000
        let count = Int(sampleRate * 0.4)
        let signal = [Float](repeating: 0, count: count)
        let fft = RealtimeFFTAnalyzer()
        let (mags, _) = fft.computeGatedFFT(samples: signal, sampleRate: sampleRate)

        let expected = ParityOracle.gated("GFFT4").maxDb
        let maxMag = mags.max()
        #expect(expected != nil, "the oracle records GFFT4's exact value")
        #expect(maxMag == expected, "silence must read \(String(describing: expected)) dB, got \(String(describing: maxMag))")
    }

    // GFFT5: Verify that HANN_DENORM window produces values matching Python.
    // After fixing the window from HANN_NORM to HANN_DENORM, the bin-centred
    // tone should match Python within 1 dB (previously off by ~4.26 dB).
    @Test func afterFix_binCentred_matchesPython() {
        let N = 32768
        let sampleRate: Double = 48000
        let gfft = ParityOracle.gated("GFFT5")
        let tone = gfft.toneList[0]
        let expected = gfft.expectedDb(at: tone.hz)
        let freq = tone.hz
        let targetBin = Int((freq * Double(N) / sampleRate).rounded())  // 46, for the message
        let amplitude = Float(tone.amplitude)
        let sampleCount = Int(sampleRate * 0.4)

        // Synthesised in Double and cast to Float per sample, matching makeTwoToneSignal
        // above, the oracle generator, and — the reason for all three — what the app is
        // actually handed. Real audio arrives as Float32 samples that are each correctly
        // rounded from the true waveform; nothing accumulates phase error along the way.
        // Computing t and sin() in Float does accumulate it (~7 significant digits over
        // 19,200 samples), so the array is not a faithful Float32 rendering of the tone.
        // On this bin-centred case that was worth 0.2 dB — which is why the golden moved
        // from -49.7 to -49.5 when the oracle was first minted rather than hand-recorded.
        var signal = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate
            signal[i] = Float(Double(amplitude) * sin(2.0 * .pi * freq * t))
        }

        let fft = RealtimeFFTAnalyzer()
        let (mags, freqs) = fft.computeGatedFFT(samples: signal, sampleRate: sampleRate)
        let swiftDB = magnitudeAtFrequency(Float(freq), magnitudes: mags, frequencies: freqs)!

        #expect(abs(swiftDB - expected) <= Self.tol,
                "bin \(targetBin): Swift=\(swiftDB) dB, oracle=\(expected) dB — difference > \(Self.tol) dB")
    }
}
