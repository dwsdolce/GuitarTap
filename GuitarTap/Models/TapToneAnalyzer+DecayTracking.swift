//
//  TapToneAnalyzer+DecayTracking.swift
//  GuitarTap
//
//  Created on 1/25/26.
//
// @parity dsp/decay tests=test/decay-tracking

/// # TapToneAnalyzer+DecayTracking
///
/// Measures the ring-out (decay) time of the guitar or plate after each tap
/// by tracking the time-varying input level in the seconds following a tap
/// detection event.
///
/// ## Architecture
/// Because the continuous FFT operates on a long window (≈ 400 ms) it delivers
/// only about 1 update per second — far too coarse for accurate decay timing.
/// Instead, decay tracking uses the per-buffer 20·log10(rms) level delivered once per audio
/// buffer (about 43 Hz at 44.1 kHz) through `RealtimeFFTAnalyzer.rmsLevelHandler` — the SAME
/// audio-thread callback that drives tap detection, which carries each buffer's audio-clock
/// timestamp across the hop to the main queue. `TapToneAnalyzer` forwards each `(level, audioTime)`
/// pair to ``trackDecayFast(inputLevel:audioTime:)``, so the ring-out is timed in audio seconds
/// and does not drift when the main queue is starved under load.
///
/// ## Ring-Out Definition
/// Ring-out time is measured as the elapsed time from the post-tap peak level
/// to when the signal first falls below `peak − decayThreshold` (in dB).
/// A lower `decayThreshold` (e.g. 20 dB) measures the early decay rate; a
/// higher value (e.g. 40 dB) captures the full sustain.
///
/// ## Tracking Window
/// The tracking timer runs for 3 seconds after each tap. If the signal has not
/// decayed by `decayThreshold` dB within that window, `currentDecayTime`
/// remains `nil` for the current measurement. The history buffer retains at
/// most 5 seconds of samples.

import Foundation

extension TapToneAnalyzer {

    // MARK: - Decay Tracking

    /// Initialises decay tracking immediately after a tap is detected.
    ///
    /// Clears the magnitude history and seeds it with `tapPeakLevel` as the
    /// time-zero reference. Tracking stops once a chunk arrives 3 s of AUDIO
    /// after the tap (see ``trackDecayFast(inputLevel:audioTime:)``).
    ///
    /// - Parameter tapAudioTime: The audio-clock time (seconds since engine start) of the tap
    ///   onset — the time-zero reference for the ring-out measurement, carried from the audio
    ///   thread so the decay is measured in audio time (load-invariant).
    /// - Note: Call this from the main thread.
    func startDecayTracking(tapAudioTime: Double) {
        // Clear previous decay history and seed with the tap peak level at the tap's AUDIO time.
        peakMagnitudeHistory = [(time: tapAudioTime, magnitude: tapPeakLevel)]
        decayTapAudioTime = tapAudioTime
        currentDecayTime = nil

        // Enable decay tracking
        isTrackingDecay = true

        // Debug output removed - decay tracking now works silently
    }
    
    /// Finalises the decay-tracking window and logs the result.
    ///
    /// Sets `isTrackingDecay` to `false` so that ``trackDecayFast(inputLevel:)``
    /// stops appending samples. If `currentDecayTime` was not established during
    /// the window, diagnostic information is printed to the console explaining
    /// whether the signal never peaked, never decayed far enough, or had
    /// insufficient history.
    func stopDecayTracking() {
        isTrackingDecay = false
        // No further action needed: trackDecayFast's guard will no longer
        // append samples, and currentDecayTime retains whatever value was
        // established during the window (or nil if none was).
    }
    
    /// Fast-path decay tracker called once per audio buffer (~43 Hz at 44.1 kHz)
    /// from the `$inputLevelDB` Combine subscription.
    ///
    /// Appends the current `inputLevel` to `peakMagnitudeHistory` and trims
    /// entries older than 5 seconds. When enough history is present it calls
    /// ``measureDecayTime(tapTime:)`` to update `currentDecayTime`.
    ///
    /// - Parameters:
    ///   - inputLevel: The current instantaneous input level in dBFS, one value per audio
    ///     buffer (the `levelDB` passed to `rmsLevelHandler`).
    ///   - audioTime: THIS buffer's audio-clock timestamp (seconds since engine start),
    ///     carried from the audio thread. Stamping with this instead of `Date()` makes the
    ///     ring-out measurement invariant to when the main queue actually runs.
    ///
    /// - Note: Returns immediately (no-op) when `isTrackingDecay` is `false`.
    func trackDecayFast(inputLevel: Float, audioTime: Double) {
        // Only track decay history if we're actively tracking after a tap
        guard isTrackingDecay else { return }

        // Stop 3 s of AUDIO after the tap, without applying this chunk. This was a 3 s WALL-clock
        // timer, so on a slow run more (or fewer) chunks got in before it fired and a slow ring-out
        // could read differently (#19). The web's DecayTracker has always stopped here.
        if let tapTime = decayTapAudioTime, audioTime - tapTime >= decayTrackingDuration {
            stopDecayTracking()
            return
        }

        peakMagnitudeHistory.append((time: audioTime, magnitude: inputLevel))

        // Keep only recent history (audio-time window)
        let decayHistoryWindowSeconds: Double = 5.0
        peakMagnitudeHistory = peakMagnitudeHistory.filter { audioTime - $0.time < decayHistoryWindowSeconds }

        // Calculate decay time if we have a tap and enough history
        let minimumDecayHistoryCount = 10
        if let tapTime = decayTapAudioTime, peakMagnitudeHistory.count > minimumDecayHistoryCount {
            currentDecayTime = measureDecayTime(tapTime: tapTime)
        }
    }
    
    /// Measures the ring-out time from the post-tap peak to the first crossing
    /// of `peak − decayThreshold`.
    ///
    /// The algorithm:
    /// 1. Finds the maximum magnitude sample that occurred at or after `tapTime`.
    /// 2. Defines `decayTarget = peakMag − decayThreshold`.
    /// 3. Finds the first sample *after* the peak where the level drops below
    ///    `decayTarget`.
    /// 4. Returns the elapsed time in seconds between the peak sample and the
    ///    crossing sample.
    ///
    /// - Parameter tapTime: The audio-clock time (seconds since engine start) of the tap
    ///   onset (set by ``startDecayTracking(tapAudioTime:)``).
    /// - Returns: Elapsed ring-out time in seconds, or `nil` if the signal
    ///   did not decay by `decayThreshold` dB within the history window.
    func measureDecayTime(tapTime: Double) -> Float? {
        // Find peak magnitude after tap
        let postTapHistory = peakMagnitudeHistory.filter { $0.time >= tapTime }

        guard let peakEntry = postTapHistory.max(by: { $0.magnitude < $1.magnitude }) else {
            return nil
        }

        let peakMag = peakEntry.magnitude
        let decayTarget = peakMag - decayThreshold

        // Find when it crossed the threshold
        if let decayEntry = postTapHistory.first(where: { $0.magnitude < decayTarget && $0.time > peakEntry.time }) {
            let decayTime = Float(decayEntry.time - peakEntry.time)
            return decayTime
        }

        return nil
    }
}
