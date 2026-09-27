//
//  PlaybackTestSupport.swift
//  GuitarTapTests
//
//  Drives the app's own Play File path from a test and waits for it. There is no test-only copy of
//  the pipeline: `playFile(url:calibrationURL:completion:)` is what the view calls, so every
//  file-playback regression runs the path users take.
//

import Foundation
@testable import GuitarTap

/// Set by the playback completion (on the main thread), read by the waiting test.
private final class PlaybackEndedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var ended = false
    func signal() { lock.lock(); ended = true; lock.unlock() }
    var isEnded: Bool { lock.lock(); defer { lock.unlock() }; return ended }
}

extension TapToneAnalyzer {
    /// Play `url` through ``playFile(url:calibrationURL:completion:)`` with the measurement type and tap
    /// count set as the user's settings would have them, then wait — yielding the main actor, so the
    /// playback worker's main-queue work and the Combine FFT frames are delivered — until playback has
    /// ended and the measurement has completed (at most 5 s after the end; the last tap is averaged a
    /// capture window later).
    func playFileAndWait(url: URL, measurementType: MeasurementType, numberOfTaps: Int = 1,
                         calibrationURL: URL? = nil) async throws {
        TapDisplaySettings.measurementType = measurementType
        self.numberOfTaps = numberOfTaps
        let ended = PlaybackEndedFlag()
        try playFile(url: url, calibrationURL: calibrationURL) { ended.signal() }
        while !ended.isEnded {
            try? await Task.sleep(nanoseconds: 5_000_000)  // 5 ms — yields the main actor
        }
        let deadline = Date(timeIntervalSinceNow: 5.0)
        while !isMeasurementComplete && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
