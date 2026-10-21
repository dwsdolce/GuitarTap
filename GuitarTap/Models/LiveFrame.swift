//
//  LiveFrame.swift
//  GuitarTap
//
//  The latest live FFT frame, published for the views that draw it: the spectrum chart, the status bar's level
//  and peak readout and the metrics panel.
//
// @parity model/live-frame tests=test/live-frame
//

import Combine
import Foundation

/// The latest live FFT frame — its spectrum, peak, readout level and processing times — owned by
/// ``RealtimeFFTAnalyzer`` as `frame`.
///
/// It is published once per frame, several times a second. It is an object of its own so that only the views
/// that draw a frame observe it: published on the engine, every frame would rebuild every view that observes the
/// engine for anything else — the whole main window among them, and a menu open in it would be rebuilt under the
/// user's finger.
final class LiveFrame: ObservableObject {

    /// Frequency spectrum magnitudes in dB, one per bin of the engine's `frequencies`.
    /// - Note: Array length is `fftSize / 2`, from -100 dB to about 0 dB.
    @Published var magnitudes: [Float]

    /// The frequency with the highest magnitude in the frame, in Hz.
    @Published var peakFrequency: Float = 0

    /// The magnitude of the peak frequency in dB. Starts at -100 dB (very quiet), so that nothing reads as above
    /// the threshold before the first frame.
    @Published var peakMagnitude: Float = -100

    /// The input level as a readout, at the frame rate, so the status bar's number refreshes with the graph.
    @Published var displayLevelDB: Float = -100

    /// Time taken to process the frame, in milliseconds.
    @Published var processingTimeMs: Float = 0

    /// Average processing time over the last several frames, in milliseconds.
    @Published var avgProcessingTimeMs: Float = 0

    init(binCount: Int) {
        magnitudes = [Float](repeating: -100, count: binCount)
    }
}
