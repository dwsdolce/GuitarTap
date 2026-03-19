//
//  TapToneAnalyzer+DecayTracking.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

/// # TapToneAnalyzer+DecayTracking
///
/// Measures the ring-out (decay) time of the guitar or plate after each tap
/// by tracking the time-varying input level in the seconds following a tap
/// detection event.
///
/// ## Architecture
/// Because the continuous FFT operates on a long window (≈ 400 ms) it delivers
/// only about 1 update per second — far too coarse for accurate decay timing.
/// Instead, decay tracking uses `RealtimeFFTAnalyzer.inputLevelDB`, which
/// updates at approximately 10 Hz via the fast `recentPeakLevelDB` polling
/// subscription in the main `TapToneAnalyzer`.  The fast callback is
/// ``trackDecayFast(inputLevel:)``; the legacy ``trackDecay(peakMagnitude:)``
/// entry point is retained for API compatibility but is now a no-op.
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
    /// Clears the magnitude history, seeds it with `tapPeakLevel` as the
    /// time-zero reference, and starts a 3-second timer that calls
    /// ``stopDecayTracking()`` when it fires.
    ///
    /// - Note: Call this from the main thread. The timer is scheduled on the
    ///   main run loop via `Timer.scheduledTimer`.
    func startDecayTracking() {
        // Clear previous decay history and seed with the tap peak level
        let now = Date()
        peakMagnitudeHistory = [(time: now, magnitude: tapPeakLevel)]
        currentDecayTime = nil
        
        // Enable decay tracking
        isTrackingDecay = true
        
        // Stop decay tracking after 3 seconds (enough time to measure ring-out)
        decayTrackingTimer?.invalidate()
        decayTrackingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.stopDecayTracking()
        }
        
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
        decayTrackingTimer?.invalidate()
        decayTrackingTimer = nil
        

    }
    
    /// Legacy slow-path decay tracker — now a no-op.
    ///
    /// Previously called once per FFT frame (≈ 1 Hz), which provided
    /// insufficient time resolution for accurate ring-out measurement.
    /// Superseded by ``trackDecayFast(inputLevel:)`` which runs at ≈ 10 Hz
    /// using `inputLevelDB` from the fast polling subscription.
    ///
    /// - Parameter peakMagnitude: The current FFT peak magnitude in dBFS
    ///   (ignored).
    ///
    /// - Warning: Deprecated in favour of ``trackDecayFast(inputLevel:)``.
    ///   This method is retained only to avoid breaking callers.
    func trackDecay(peakMagnitude: Float) {
        // This function is kept for compatibility but decay tracking now uses trackDecayFast
        // which is called ~10x per second instead of ~1x per second
    }
    
    /// Fast-path decay tracker called at ~10 Hz from the input-level polling
    /// subscription.
    ///
    /// Appends the current `inputLevel` to `peakMagnitudeHistory` and trims
    /// entries older than 5 seconds. When enough history is present it calls
    /// ``measureDecayTime(tapTime:)`` to update `currentDecayTime`.
    ///
    /// - Parameter inputLevel: The current instantaneous input level in dBFS,
    ///   typically sourced from
    ///   `RealtimeFFTAnalyzer.inputLevelDB` sampled at ~10 Hz.
    ///
    /// - Note: Returns immediately (no-op) when `isTrackingDecay` is `false`.
    func trackDecayFast(inputLevel: Float) {
        let now = Date()
        
        // Only track decay history if we're actively tracking after a tap
        guard isTrackingDecay else { return }
        
        peakMagnitudeHistory.append((time: now, magnitude: inputLevel))
        
        // Keep only recent history (5 seconds)
        peakMagnitudeHistory = peakMagnitudeHistory.filter { now.timeIntervalSince($0.time) < 5.0 }
        
        // Calculate decay time if we have a tap and enough history
        if let tapTime = lastTapTime, peakMagnitudeHistory.count > 10 {
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
    /// - Parameter tapTime: The `Date` of the tap onset (set at the moment
    ///   ``startDecayTracking()`` is called).
    /// - Returns: Elapsed ring-out time in seconds, or `nil` if the signal
    ///   did not decay by `decayThreshold` dB within the history window.
    func measureDecayTime(tapTime: Date) -> Float? {
        // Find peak magnitude after tap
        let postTapHistory = peakMagnitudeHistory.filter { $0.time >= tapTime }
        
        guard let peakEntry = postTapHistory.max(by: { $0.magnitude < $1.magnitude }) else {
            return nil
        }
        
        let peakMag = peakEntry.magnitude
        let decayTarget = peakMag - decayThreshold
        
        // Find when it crossed the threshold
        if let decayEntry = postTapHistory.first(where: { $0.magnitude < decayTarget && $0.time > peakEntry.time }) {
            let decayTime = Float(decayEntry.time.timeIntervalSince(peakEntry.time))
            return decayTime
        }
        
        return nil
    }
}
