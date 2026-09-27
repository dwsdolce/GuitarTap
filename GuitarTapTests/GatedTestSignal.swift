//
//  GatedTestSignal.swift
//  GuitarTapTests
//
//  The one place the gated-FFT test signal is built and read back. Used by the GFFT parity tests
//  and by GenerateParityOracle, which mints the values those tests assert — so the tests and the
//  oracle are fed the same samples by construction, not by two copies kept in step.
//
//  Mirrors Python tests/gated_signal.py and web test/gatedSignal.ts.
//
// @parity tooling/gated-signal

import Foundation
@testable import GuitarTap

/// The gated-FFT test signal: a sum of sine tones, synthesised in Double and rounded to Float once
/// per sample. Real audio arrives as Float32 samples each correctly rounded from the true waveform;
/// computing `t` and `sin()` in Float instead accumulates phase error over the 19,200 samples, which
/// would hand the transform something no microphone produces. No tones gives silence.
///
/// - Parameters:
///   - tones:      The tones to sum, in any order.
///   - sampleRate: Sample rate in Hz.
///   - duration:   Duration in seconds; the sample count is `Int(sampleRate * duration)`.
func makeGatedTestSignal(tones: [ParityOracle.GatedTone],
                         sampleRate: Double = 48000,
                         duration: Double = 0.4) -> [Float] {
    let count = Int(sampleRate * duration)
    return (0..<count).map { i in
        let t = Double(i) / sampleRate
        var sample = 0.0
        for tone in tones {
            sample += tone.amplitude * sin(2.0 * .pi * tone.hz * t)
        }
        return Float(sample)
    }
}

/// The magnitude (dB) at the bin nearest `targetHz`, or nil for an empty spectrum.
func gatedMagnitude(at targetHz: Float, magnitudes: [Float], frequencies: [Float]) -> Float? {
    guard !frequencies.isEmpty else { return nil }
    var bestIdx = 0
    var bestDist = Float.greatestFiniteMagnitude
    for (i, f) in frequencies.enumerated() where abs(f - targetHz) < bestDist {
        bestDist = abs(f - targetHz)
        bestIdx = i
    }
    return magnitudes[bestIdx]
}
