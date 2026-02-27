//
//  TapToneAnalyzer+DecayTracking.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import Foundation

extension TapToneAnalyzer {

    // MARK: - Decay Tracking

    /// Start decay tracking after a tap is detected
    /// This runs for 3 seconds to capture the ring-out time
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
    
    /// Stop decay tracking
    func stopDecayTracking() {
        isTrackingDecay = false
        decayTrackingTimer?.invalidate()
        decayTrackingTimer = nil
        
        // Log result for debugging
        if let decayTime = currentDecayTime {
            print("✅ Ring-out measured: \(String(format: "%.2f", decayTime)) seconds")
        } else {
            // Debug why it failed
            if let tapTime = lastTapTime {
                let postTapHistory = peakMagnitudeHistory.filter { $0.time >= tapTime }
                if let peakEntry = postTapHistory.max(by: { $0.magnitude < $1.magnitude }) {
                    let currentLevel = postTapHistory.last?.magnitude ?? -100
                    let target = peakEntry.magnitude - decayThreshold
                    print("⚠️ Ring-out not measured: peak=\(String(format: "%.1f", peakEntry.magnitude)) dB, final=\(String(format: "%.1f", currentLevel)) dB, target=\(String(format: "%.1f", target)) dB, samples=\(postTapHistory.count)")
                } else {
                    print("⚠️ Ring-out not measured: no peak found in \(peakMagnitudeHistory.count) samples")
                }
            } else {
                print("⚠️ Ring-out not measured: no tap time recorded")
            }
        }
    }
    
    /// Track magnitude over time for decay analysis (slow - called per FFT frame)
    /// NOTE: This is now deprecated in favor of trackDecayFast which uses inputLevelDB
    func trackDecay(peakMagnitude: Float) {
        // This function is kept for compatibility but decay tracking now uses trackDecayFast
        // which is called ~10x per second instead of ~1x per second
    }
    
    /// Fast decay tracking using input level (~10Hz update rate)
    /// This provides much better time resolution than tracking per FFT frame
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
    
    /// Measure how long it takes for magnitude to decay
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
