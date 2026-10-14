//
//  InputLevel.swift
//  GuitarTap
//
//  The input level of the latest audio buffer, published for the threshold slider's level meter.
//  Mirrors Python `InputLevel` in `models/input_level.py` and web `InputLevel` in
//  `src/audio/inputLevel.ts`.
//
// @parity model/input-level tests=test/input-level,test/dsp,test/notification,test/status-message
//

import Combine
import Foundation

/// The input level of the latest audio buffer — its RMS level, the recent peak and clipping —
/// owned by ``RealtimeFFTAnalyzer`` as `level`.
///
/// It is published once per audio buffer, many times a second. It is an object of its own so that
/// only the threshold slider's meter observes it: published on the engine, every buffer would
/// rebuild every view that observes the engine for anything else — the whole main window among
/// them.
final class InputLevel: ObservableObject {

    /// Fast input level in dB, updated on every audio buffer. Use this for decay tracking instead of
    /// the engine's `peakMagnitude`, which only updates per FFT frame.
    @Published var inputLevelDB: Float = -100

    /// Edge-triggered clipping flag — `true` when any audio chunk in the last
    /// ``RealtimeFFTAnalyzer/clipHoldSeconds`` reached full scale (sample |x| ≥ 0.99) or RMS ≥ 0
    /// dBFS, `false` otherwise. Drives a remediation message in the status bar
    /// (``TapToneAnalyzer`` swaps the displayed `statusMessage` when this toggles) and the slider's
    /// red clipping zone.
    @Published var isClipping: Bool = false

    /// Maximum input level observed over the last ``RealtimeFFTAnalyzer/peakHoldDuration`` seconds
    /// (dBFS), updated on every audio buffer.
    ///
    /// Because the continuous FFT window is ~1.4 s, the engine's `peakMagnitude` lags the actual tap
    /// transient by up to that amount. `recentPeakLevelDB` captures the true tap peak before the FFT
    /// result arrives.
    @Published var recentPeakLevelDB: Float = -100
}
