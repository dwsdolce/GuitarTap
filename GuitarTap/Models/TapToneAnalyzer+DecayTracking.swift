//
//  TapToneAnalyzer+DecayTracking.swift
//  GuitarTap
//
//  Created on 1/25/26.
//
// @parity dsp/decay tests=test/decay-tracking,test/guitar-capture-window

/// # TapToneAnalyzer+DecayTracking
///
/// Measures the ring-out (decay) time of a guitar tap from the samples of its FFT window.
///
/// ## Ring-Out Definition
/// The level is the mean square over a window of ``ringOutWindowSamples`` samples, taken at every
/// sample from the tap's onset. Ring-out time is the time from the window where that level is
/// highest to the first window after it whose level is `decayThreshold` dB lower, interpolated
/// between samples.
///
/// ## Why from the window
/// The guitar window starts a fixed distance before the tap's onset, and its audio ends a fixed
/// distance after it, whichever chunk the trigger fired on. Measured on those samples, the ring-out
/// depends on the tap alone — not on where the audio's chunk boundaries fell, which differs from one
/// run, and one edition, to the next. Measured once per chunk, it could only come out in whole
/// chunks, and the same tap read a chunk apart.
///
/// The window's audio lasts about 1.16 s after the onset; a ring-out longer than that is not measured.

import Foundation

extension TapToneAnalyzer {

    // MARK: - Ring-Out

    /// The number of samples the ring-out level is measured over.
    static let ringOutWindowSamples = 1024

    /// The ring-out time of the audio in `samples[start..<end]`.
    ///
    /// The algorithm:
    /// 1. The energy of every ``ringOutWindowSamples``-sample window starting from `start` and ending
    ///    by `end`, from a running sum of the squares (in `Double`, from `start`, one sample at a time).
    /// 2. The peak is the first window with the most energy.
    /// 3. The target is the peak's energy `threshold` dB lower; the crossing is the first window after
    ///    the peak with less energy than the target.
    /// 4. The crossing is interpolated in dB between the window before it and the crossing window.
    ///
    /// - Parameters:
    ///   - samples: The audio — a guitar tap's FFT window.
    ///   - start: The first sample measured — the tap's onset in the window.
    ///   - end: One past the last sample measured — where the window's audio ends.
    ///   - sampleRate: The sample rate in Hz.
    ///   - threshold: How far below the peak the level must fall, in dB (`decayThreshold`).
    /// - Returns: Seconds from the peak to the crossing, or `nil` if there is too little audio, it is
    ///   silent, or its level does not fall by `threshold` before `end`.
    static func ringOutTime(_ samples: [Float], from start: Int, to end: Int,
                            sampleRate: Double, threshold: Float) -> Float? {
        let window = ringOutWindowSamples
        let end = min(end, samples.count)
        guard start >= 0, sampleRate > 0, end - start > window else { return nil }

        var sums = [Double](repeating: 0, count: end - start + 1)
        var total = 0.0
        for k in start..<end {
            let x = Double(samples[k])
            total += x * x
            sums[k - start + 1] = total
        }
        let windows = end - start - window + 1
        func energy(_ i: Int) -> Double { sums[i + window] - sums[i] }

        var peak = 0
        for i in 1..<windows where energy(i) > energy(peak) { peak = i }
        let peakEnergy = energy(peak)
        guard peakEnergy > 0 else { return nil }

        let target = peakEnergy * pow(10, -Double(threshold) / 10)
        guard let crossing = (peak + 1..<windows).first(where: { energy($0) < target }) else { return nil }

        let before = energy(crossing - 1), after = energy(crossing)
        let fraction = after > 0
            ? (log10(before) - log10(target)) / (log10(before) - log10(after))
            : 0
        return Float((Double(crossing - 1 - peak) + fraction) / sampleRate)
    }
}
