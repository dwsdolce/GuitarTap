//
//  MPMAnalyzer.swift
//  GuitarTap
//
//  McLeod Pitch Method (MPM) implementation for resonant frequency detection.
//  Reference: McLeod & Wyvill, "A Smarter Way to Find Pitch" (2005).
//
//  Uses the Normalized Square Difference Function (NSDF) to find the fundamental
//  period of a decaying tap tone, with sub-sample accuracy via parabolic interpolation.

import Foundation
import Accelerate

// MARK: - MPM Result

struct MPMResult {
    /// Detected frequency in Hz, or nil if no confident pitch found
    let frequency: Float?
    /// NSDF peak value (0–1); higher = more confident
    let confidence: Float
    /// Period in samples (before interpolation)
    let periodSamples: Float?
}

// MARK: - MPM Analyzer

/// Implements the McLeod Pitch Method for detecting the resonant frequency
/// of a tap tone.  Feed it raw audio samples captured during the ring-out
/// window; it returns the best frequency estimate with a confidence score.
final class MPMAnalyzer {

    // MARK: - Configuration

    /// NSDF peak threshold as a fraction of the global maximum (0–1).
    /// McLeod's paper recommends 0.93 for sustained pitches; tap tones use a lower
    /// value because the NSDF lobes are weaker on a decaying signal.
    var peakThreshold: Float = 0.80

    /// Minimum frequency to consider (Hz).  Lags longer than sampleRate/minFreq are ignored.
    var minFrequency: Float = 30.0

    /// Maximum frequency to consider (Hz).  Lags shorter than sampleRate/maxFreq are ignored.
    var maxFrequency: Float = 1000.0



    // MARK: - Initialization

    init(minFrequency: Float = 30.0, maxFrequency: Float = 1000.0) {
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
    }

    // MARK: - Public Interface

    /// Analyse a block of raw PCM samples and return an MPM frequency estimate.
    /// - Parameters:
    ///   - samples: Raw float32 PCM at `sampleRate`.  Should cover the full ring-out
    ///              window (~300–500 ms for best results).
    ///   - sampleRate: Sample rate of the audio (e.g. 48000).
    /// - Returns: `MPMResult` with the detected frequency (or nil) and confidence.
    func analyse(samples: [Float], sampleRate: Double) -> MPMResult {
        guard samples.count > 4 else {
            return MPMResult(frequency: nil, confidence: 0, periodSamples: nil)
        }

        // Skip the initial attack transient (~20 ms).  The onset of a tap is
        // inharmonic and distorts the autocorrelation; the ring-out that follows
        // is what reveals the resonant frequency.
        let attackSkipSamples = min(Int(sampleRate * 0.020), samples.count / 4)
        let ringSamples = Array(samples[attackSkipSamples...])

        // Compute Normalized Square Difference Function (NSDF)
        let nsdf = computeNSDF(ringSamples)
        guard !nsdf.isEmpty else {
            return MPMResult(frequency: nil, confidence: 0, periodSamples: nil)
        }

        // Frequency bounds as lag limits.
        // maxLag: longest lag = lowest frequency (protected by -2 for parabolic interpolation)
        // minLag: shortest lag = highest frequency
        let minLag = max(2, Int(sampleRate / Double(maxFrequency)))
        let maxLag = min(nsdf.count - 2, Int(sampleRate / Double(minFrequency)))
        guard minLag < maxLag else {
            return MPMResult(frequency: nil, confidence: 0, periodSamples: nil)
        }

        // Find the global maximum of the NSDF across the FULL valid lag range.
        // This must cover the complete lobe structure, not just a slice starting at minLag,
        // so that lobes whose peak lies below minLag are not truncated and misread.
        let nsdfSlice = Array(nsdf[minLag...maxLag])
        guard let globalMax = nsdfSlice.max(), globalMax > 0 else {
            // Diagnose: report signal RMS and NSDF range to distinguish silence from aperiodic signal
            var rms: Float = 0
            vDSP_rmsqv(ringSamples, 1, &rms, vDSP_Length(ringSamples.count))
            let nsdfMin = nsdf[minLag...maxLag].min() ?? 0
            let nsdfAbsMax = nsdf[minLag...maxLag].map(abs).max() ?? 0
            print("⚠️ MPM NSDF has no positive peak in [\(minLag)...\(maxLag)] "
                + "(f: \(String(format: "%.0f", Float(sampleRate)/Float(maxLag)))–\(String(format: "%.0f", Float(sampleRate)/Float(minLag))) Hz) "
                + "| NSDF range: [\(String(format: "%.3f", nsdfMin)), \(String(format: "%.3f", nsdfAbsMax))] "
                + "| signal RMS: \(String(format: "%.6f", rms)) (\(String(format: "%.1f", rms > 0 ? 20*log10(rms) : -100)) dBFS) "
                + "| samples: \(ringSamples.count)")
            return MPMResult(frequency: nil, confidence: 0, periodSamples: nil)
        }

        let threshold = peakThreshold * globalMax

        // Collect positive lobes over the FULL NSDF (from lag=1) and find the peak of each.
        // Scanning from lag=1 ensures each lobe is seen in its entirety — if we started at
        // minLag we could land mid-lobe and misidentify the local peak near the lobe edge.
        // Candidates are later filtered to the [minLag, maxLag] frequency window.
        var candidates: [(lag: Int, value: Float)] = []
        var inPositiveLobe = false
        var lobePeak: (lag: Int, value: Float) = (0, -Float.infinity)

        for i in 1...(nsdf.count - 2) {
            let v = nsdf[i]
            if v > 0 {
                if !inPositiveLobe {
                    inPositiveLobe = true
                    lobePeak = (i, v)
                } else if v > lobePeak.value {
                    lobePeak = (i, v)
                }
            } else {
                if inPositiveLobe {
                    // End of lobe — record only if the peak falls within the frequency window
                    if lobePeak.lag >= minLag && lobePeak.lag <= maxLag {
                        candidates.append(lobePeak)
                    }
                    inPositiveLobe = false
                    lobePeak = (0, -Float.infinity)
                }
            }
        }
        // Handle lobe that runs to the end of the array
        if inPositiveLobe && lobePeak.lag >= minLag && lobePeak.lag <= maxLag {
            candidates.append(lobePeak)
        }

        // Select the first candidate that exceeds the threshold (McLeod's key rule).
        // "First" means the shortest lag = highest frequency within the allowed window,
        // which is the fundamental for a signal with harmonics.
        guard let selected = candidates.first(where: { $0.value >= threshold }) else {
            return MPMResult(frequency: nil, confidence: 0, periodSamples: nil)
        }

        // Parabolic interpolation for sub-sample accuracy.
        // delta is clamped to (-0.5, 0.5) so refinedLag stays within ±0.5 sample of lag.
        let lag = selected.lag
        let refinedLag: Float
        if lag > 0 && lag < nsdf.count - 1 {
            let y0 = nsdf[lag - 1]
            let y1 = nsdf[lag]
            let y2 = nsdf[lag + 1]
            let denominator = 2 * y1 - y0 - y2
            if abs(denominator) > 1e-6 {
                let delta = max(-0.5, min(0.5, 0.5 * (y2 - y0) / denominator))
                refinedLag = Float(lag) + delta
            } else {
                refinedLag = Float(lag)
            }
        } else {
            refinedLag = Float(lag)
        }

        guard refinedLag > 0 else {
            return MPMResult(frequency: nil, confidence: 0, periodSamples: nil)
        }

        let frequency = Float(sampleRate) / refinedLag
        return MPMResult(frequency: frequency, confidence: selected.value, periodSamples: refinedLag)
    }

    // MARK: - NSDF Computation

    /// Compute the Normalized Square Difference Function using vDSP.
    ///
    /// NSDF(τ) = 2·ACF(τ) / (m'(τ))
    /// where m'(τ) = Σ(x[i]² + x[i+τ]²)  for i = 0..N-τ-1
    ///
    /// This is equivalent to:  NSDF(τ) = 1 - SDF(τ) / m'(τ)
    /// where SDF(τ) = Σ(x[i] - x[i+τ])²
    private func computeNSDF(_ x: [Float]) -> [Float] {
        let N = x.count
        let maxLagNeeded = min(N - 1, Int(Double(N) * 0.7))  // search up to 70% of window

        var nsdf = [Float](repeating: 0, count: maxLagNeeded + 1)

        // Use direct summation. For tap tone windows (~24000 samples) this is fast enough,
        // but a vDSP correlation path is used for the inner loop.

        // Precompute x[i]² for running power sums
        var xSq = [Float](repeating: 0, count: N)
        vDSP_vsq(x, 1, &xSq, 1, vDSP_Length(N))

        // Total power = Σ x[i]²
        var totalPower: Float = 0
        vDSP_sve(xSq, 1, &totalPower, vDSP_Length(N))

        // Running power of the lagged portion: powerLag = Σ x[i+τ]² for i=0..N-τ-1
        // At τ=0: powerLag = totalPower, powerX = totalPower
        // At τ=k: powerX decreases by x[k-1]², powerLag decreases by x[N-k]²

        var powerX = totalPower    // power of x[0..N-τ-1]
        var powerLag = totalPower  // power of x[τ..N-1]

        for lag in 0...maxLagNeeded {
            if lag > 0 {
                powerX   -= xSq[lag - 1]
                powerLag -= xSq[N - lag]
            }
            let mPrime = powerX + powerLag
            guard mPrime > 1e-10 else {
                nsdf[lag] = 0
                continue
            }

            // ACF(τ) = Σ x[i] * x[i+τ]
            var acf: Float = 0
            vDSP_dotpr(x, 1, Array(x[lag...]), 1, &acf, vDSP_Length(N - lag))

            nsdf[lag] = 2.0 * acf / mPrime
        }

        return nsdf
    }

}
