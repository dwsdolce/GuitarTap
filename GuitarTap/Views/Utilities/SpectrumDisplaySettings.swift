//
//  SpectrumDisplaySettings.swift
//  GuitarTap
//
//  Created on 2/12/26.
//

import Foundation

/// Centralized settings for spectrum display ranges across the app
struct SpectrumDisplaySettings {
    // MARK: - Display Ranges
    
    /// Standard minimum frequency for guitar tap tone spectrum display (Hz)
    static let minFrequency: Float = 75
    
    /// Standard maximum frequency for guitar tap tone spectrum display (Hz)
    static let maxFrequency: Float = 350
    
    /// Standard minimum magnitude for spectrum display (dB)
    static let minMagnitude: Float = -100
    
    /// Standard maximum magnitude for spectrum display (dB)
    static let maxMagnitude: Float = 0
    
    // MARK: - Analysis Settings
    
    /// Minimum frequency for peak detection and analysis (Hz)
    static let analysisMinFrequency: Float = 50
    
    /// Maximum frequency for peak detection and analysis (Hz)
    static let analysisMaxFrequency: Float = 2000
    
    /// Default minimum magnitude threshold for peak detection (dB)
    /// Any magnitude below this is ignored. Even if the threshold setting is below it.
    static let defaultPeakThreshold: Float = -60
    
    // MARK: - Validation
    
    /// Validates and clamps frequency range
    /// - Parameters:
    ///   - minFreq: Minimum frequency to validate
    ///   - maxFreq: Maximum frequency to validate
    /// - Returns: Tuple of validated (min, max) frequencies
    static func validateFrequencyRange(minFreq: Float, maxFreq: Float) -> (min: Float, max: Float) {
        let clampedMin = max(20, min(minFreq, 20000))
        let clampedMax = max(20, min(maxFreq, 20000))
        
        // Ensure minimum separation of 10 Hz
        if clampedMin < clampedMax && (clampedMax - clampedMin) >= 10 {
            return (clampedMin, clampedMax)
        }
        
        // Return defaults if validation fails
        return (minFrequency, maxFrequency)
    }
    
    /// Validates and clamps magnitude range
    /// - Parameters:
    ///   - minDB: Minimum magnitude to validate
    ///   - maxDB: Maximum magnitude to validate
    /// - Returns: Tuple of validated (min, max) magnitudes
    static func validateMagnitudeRange(minDB: Float, maxDB: Float) -> (min: Float, max: Float) {
        let clampedMin = max(-120, min(minDB, 20))
        let clampedMax = max(-120, min(maxDB, 20))
        
        // Ensure minimum separation of 10 dB
        if clampedMin < clampedMax && (clampedMax - clampedMin) >= 10 {
            return (clampedMin, clampedMax)
        }
        
        // Return defaults if validation fails
        return (minMagnitude, maxMagnitude)
    }
}
