//
//  SyntheticTap.swift
//  GuitarTapTests
//
//  A synthetic tap: a decaying sinusoid with a single resonance, at 48 kHz — the ring-out a capture
//  finish is handed in place of microphone audio.
//
//  Mirrors Python tests/synthetic_tap.py and web test/syntheticTap.ts.
//
// @parity tooling/synthetic-tap

import Foundation

/// `seconds` of a tap ringing at `hz`: 0.5 · e^(−6t) · sin(2π·hz·t), sampled at 48 kHz.
func syntheticTap(hz: Float, seconds: Double) -> [Float] {
    let sampleRate: Float = 48000
    let n = Int(Double(sampleRate) * seconds)
    return (0..<n).map { i in
        let t = Float(i) / sampleRate
        return 0.5 * expf(-t * 6.0) * sinf(2 * .pi * hz * t)
    }
}
