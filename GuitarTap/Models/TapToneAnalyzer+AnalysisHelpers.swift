//
//  TapToneAnalyzer+AnalysisHelpers.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import Foundation

extension TapToneAnalyzer {

    // MARK: - Analysis Helpers
    
    /// Get peaks within a frequency range
    func getPeaks(in range: ClosedRange<Float>) -> [ResonantPeak] {
        currentPeaks.filter { range.contains($0.frequency) }
    }
    
    /// Get the strongest peak for a specific mode (handles legacy mode names via normalization)
    func getPeak(for mode: GuitarMode) -> ResonantPeak? {
        identifiedModes
            .filter { $0.mode.normalized == mode.normalized }
            .max(by: { $0.peak.magnitude < $1.peak.magnitude })?
            .peak
    }
    
    /// Calculate tap tone ratio (ideal is ~2.0)
    /// Ratio of Top resonance to Air resonance frequency
    func calculateTapToneRatio() -> Float? {
        guard let airPeak = getPeak(for: .air),
              let topPeak = getPeak(for: .top) else {
            return nil
        }
        return topPeak.frequency / airPeak.frequency
    }
    
    /// Compare current measurement to a saved one
    func compareTo(_ measurement: TapToneMeasurement) -> [(current: ResonantPeak?, saved: ResonantPeak, difference: Float)] {
        measurement.peaks.map { savedPeak in
            let currentPeak = currentPeaks.min(by: { abs($0.frequency - savedPeak.frequency) < abs($1.frequency - savedPeak.frequency) })
            let difference = currentPeak.map { $0.frequency - savedPeak.frequency } ?? 0
            return (current: currentPeak, saved: savedPeak, difference: difference)
        }
    }
}
