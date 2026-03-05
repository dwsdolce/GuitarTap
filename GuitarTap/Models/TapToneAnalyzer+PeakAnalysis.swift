//
//  TapToneAnalyzer+PeakAnalysis.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import SwiftUI
import Combine

extension TapToneAnalyzer {

    // MARK: - Analysis Methods

    /// Main analysis pipeline
    func analyzeMagnitudes(_ magnitudes: [Float], frequencies: [Float], peakMagnitude: Float) {
        // Don't analyze anything if the FFT analyzer isn't actually running
        guard fftAnalyzer.isRunning else {
            // Reset tap detection state to prevent false positives before start
            tapDetected = false
            return
        }
        
        // Calculate average magnitude for tap detection
        let validMags = magnitudes.filter { $0 > -100 }
        averageMagnitude = validMags.isEmpty ? -100 : validMags.reduce(0, +) / Float(validMags.count)
        
        // Only detect taps if detection is enabled.
        // Material/brace modes use the fast recentPeakLevelDB subscription instead of
        // this slow FFT path — the long-window FFT dilutes transient tap energy by ~15 dB.
        let mType = TapDisplaySettings.measurementType
        let usesFastTapDetection = (mType == .material || mType == .brace)
        if isDetecting && !usesFastTapDetection {
            detectTap(peakMagnitude: peakMagnitude, magnitudes: magnitudes, frequencies: frequencies)
        }
        
        // Analyze peaks if detection is enabled, paused (spectrum stays live), or in capture window
        // But don't overwrite currentPeaks after a material/brace measurement is complete —
        // those peaks are the final selected L/C/FLC peaks and must not be replaced by live audio.
        if (isDetecting || isDetectionPaused || captureTimer != nil) && materialTapPhase != .complete {
            // Find peaks in spectrum
            let peaks = findPeaks(magnitudes: magnitudes, frequencies: frequencies)
            currentPeaks = peaks
            // Auto-select all newly detected peaks so visibility mode "selected" shows everything by default
            selectedPeakIDs = Set(peaks.map { $0.id })

            // Classify modes
            identifiedModes = peaks.map { peak in
                (peak: peak, mode: GuitarMode.classify(frequency: peak.frequency))
            }
            
        }
        
        // Always track peak magnitude for decay analysis (even when not detecting taps)
        // This ensures we can measure ring-out time after a tap is detected
        trackDecay(peakMagnitude: peakMagnitude)
    }

    /// Find all significant peaks in the spectrum
    /// Guarantees the strongest peak for each known guitar mode is included,
    /// then fills remaining slots with additional peaks by magnitude
    func findPeaks(magnitudes: [Float], frequencies: [Float], minHz: Float? = nil, maxHz: Float? = nil) -> [ResonantPeak] {
        guard magnitudes.count == frequencies.count else { return [] }
        
        var allPeaks: [ResonantPeak] = []
        let windowSize = 5  // Look at ±5 bins around each point
        
        // Find frequency range indices — caller can override the analysis window
        let loFreq = minHz ?? minFrequency
        let hiFreq = maxHz ?? maxFrequency
        let startIdx = frequencies.firstIndex(where: { $0 >= loFreq }) ?? 0
        let endIdx = frequencies.firstIndex(where: { $0 > hiFreq }) ?? frequencies.count - 1
        
        // Define all known modes to search for (excluding unknown)
        // Uses legacy names that map to normalized modes via .normalized property
        let knownModes: [GuitarMode] = [.helmholtz, .crossGrain, .longGrain, .monopole, .dipole, .ringMode, .upperModes]
        
        // Track the strongest peak found in each mode range
        var strongestPeakPerMode: [GuitarMode: ResonantPeak] = [:]
        
        // Step 1: Search known mode ranges for peaks
        for mode in knownModes {
            let modeRange = mode.idealRange
            let normalizedMode = mode.normalized
            
            // Find indices for this mode's range
            let modeStartIdx = frequencies.firstIndex(where: { $0 >= modeRange.lowerBound }) ?? startIdx
            let modeEndIdx = frequencies.firstIndex(where: { $0 > modeRange.upperBound }) ?? endIdx
            
            // Skip if range is invalid
            guard modeStartIdx < modeEndIdx, modeStartIdx >= startIdx, modeEndIdx <= endIdx else { continue }
            
            // Scan for local maxima within this mode's range
            for i in max(modeStartIdx, startIdx + windowSize)..<min(modeEndIdx, endIdx - windowSize) {
                let magnitude = magnitudes[i]
                
                // Skip if below threshold
                guard magnitude > peakThreshold else { continue }
                
                // Check if local maximum
                var isLocalMax = true
                for offset in -windowSize...windowSize where offset != 0 {
                    if magnitudes[i + offset] >= magnitude {
                        isLocalMax = false
                        break
                    }
                }
                
                guard isLocalMax else { continue }
                
                // Refine peak location and magnitude with parabolic interpolation
                let (interpFreq, interpMag) = parabolicInterpolate(magnitudes: magnitudes, frequencies: frequencies, peakIndex: i)
                
                // Calculate Q factor using interpolated peak magnitude for accurate -3 dB threshold
                let (quality, bandwidth) = calculateQFactor(magnitudes: magnitudes, frequencies: frequencies, peakIndex: i, peakMagnitude: interpMag)
                
                // Calculate pitch information from interpolated frequency
                let freq = Double(interpFreq)
                let pitchNote = pitchCalculator.note(frequency: freq)
                let pitchCents = pitchCalculator.cents(frequency: freq)
                let pitchFreq = pitchCalculator.freq0(frequency: freq)
                
                let peak = ResonantPeak(
                    frequency: interpFreq,
                    magnitude: interpMag,
                    quality: quality,
                    bandwidth: bandwidth,
                    pitchNote: pitchNote,
                    pitchCents: pitchCents,
                    pitchFrequency: pitchFreq
                )
                allPeaks.append(peak)
                
                // Track strongest peak for this mode
                if let existing = strongestPeakPerMode[normalizedMode] {
                    if magnitude > existing.magnitude {
                        strongestPeakPerMode[normalizedMode] = peak
                    }
                } else {
                    strongestPeakPerMode[normalizedMode] = peak
                }
            }
        }
        
        // Step 2: Search entire spectrum for peaks outside known mode ranges (unknown peaks)
        for i in (startIdx + windowSize)..<(endIdx - windowSize) {
            let magnitude = magnitudes[i]
            let frequency = frequencies[i]
            
            // Skip if below threshold
            guard magnitude > peakThreshold else { continue }
            
            // Check if this frequency is already covered by a known mode
            let isInKnownMode = knownModes.contains { mode in
                mode.idealRange.contains(frequency)
            }
            
            // Only process if outside known mode ranges
            guard !isInKnownMode else { continue }
            
            // Check if local maximum
            var isLocalMax = true
            for offset in -windowSize...windowSize where offset != 0 {
                if magnitudes[i + offset] >= magnitude {
                    isLocalMax = false
                    break
                }
            }
            
            guard isLocalMax else { continue }
            
            // Refine peak location and magnitude with parabolic interpolation
            let (interpFreq, interpMag) = parabolicInterpolate(magnitudes: magnitudes, frequencies: frequencies, peakIndex: i)
            
            // Calculate Q factor using interpolated peak magnitude for accurate -3 dB threshold
            let (quality, bandwidth) = calculateQFactor(magnitudes: magnitudes, frequencies: frequencies, peakIndex: i, peakMagnitude: interpMag)
            
            // Calculate pitch information from interpolated frequency
            let freq = Double(interpFreq)
            let pitchNote = pitchCalculator.note(frequency: freq)
            let pitchCents = pitchCalculator.cents(frequency: freq)
            let pitchFreq = pitchCalculator.freq0(frequency: freq)
            
            let peak = ResonantPeak(
                frequency: interpFreq,
                magnitude: interpMag,
                quality: quality,
                bandwidth: bandwidth,
                pitchNote: pitchNote,
                pitchCents: pitchCents,
                pitchFrequency: pitchFreq
            )
            allPeaks.append(peak)
        }
        
        // Remove duplicate peaks (in case of overlap)
        allPeaks = removeDuplicatePeaks(allPeaks)
        
        // Step 3: Build final peak list with mode priority
        // First, include the strongest peak from each known mode (guaranteed slots)
        var finalPeaks: [ResonantPeak] = []
        var includedPeakIDs = Set<UUID>()
        
        for (_, peak) in strongestPeakPerMode {
            finalPeaks.append(peak)
            includedPeakIDs.insert(peak.id)
        }
        
        // Then fill remaining slots with other peaks by magnitude
        // maxPeaks == 0 means "capture all peaks"
        if maxPeaks == 0 {
            // Add all remaining peaks (no limit)
            let otherPeaks = allPeaks
                .filter { !includedPeakIDs.contains($0.id) }
                .sorted { $0.magnitude > $1.magnitude }
            finalPeaks.append(contentsOf: otherPeaks)
        } else {
            let remainingSlots = maxPeaks - finalPeaks.count
            if remainingSlots > 0 {
                let otherPeaks = allPeaks
                    .filter { !includedPeakIDs.contains($0.id) }
                    .sorted { $0.magnitude > $1.magnitude }
                    .prefix(remainingSlots)
                finalPeaks.append(contentsOf: otherPeaks)
            }
        }
        
        // Sort final result by magnitude descending
        return finalPeaks.sorted(by: { $0.magnitude > $1.magnitude })
    }
    
    /// Remove duplicate peaks that are too close in frequency
    func removeDuplicatePeaks(_ peaks: [ResonantPeak]) -> [ResonantPeak] {
        var uniquePeaks: [ResonantPeak] = []
        let frequencyTolerance: Float = 2.0  // Hz - peaks closer than this are considered duplicates
        
        for peak in peaks {
            // Check if we already have a peak at this frequency
            let isDuplicate = uniquePeaks.contains { existingPeak in
                abs(existingPeak.frequency - peak.frequency) < frequencyTolerance
            }
            
            if !isDuplicate {
                uniquePeaks.append(peak)
            } else {
                // If duplicate, keep the one with higher magnitude
                if let existingIndex = uniquePeaks.firstIndex(where: { abs($0.frequency - peak.frequency) < frequencyTolerance }) {
                    if peak.magnitude > uniquePeaks[existingIndex].magnitude {
                        uniquePeaks[existingIndex] = peak
                    }
                }
            }
        }
        
        return uniquePeaks
    }
    
    /// Refine a bin-level peak location using parabolic interpolation.
    ///
    /// Fits a parabola through the peak bin and its two neighbours to estimate
    /// where the true spectral peak sits between bins.  This improves frequency
    /// accuracy by roughly one order of magnitude over the raw bin spacing,
    /// and corrects the magnitude estimate so it reflects the true peak rather
    /// than the sample at the nearest bin centre.
    ///
    /// - Parameters:
    ///   - magnitudes: dB magnitude spectrum.
    ///   - frequencies: Frequency axis matching `magnitudes`.
    ///   - peakIndex: Index of the local maximum bin.
    /// - Returns: `(frequency, magnitude)` of the interpolated peak.
    ///            Falls back to the raw bin values if interpolation cannot be applied.
    func parabolicInterpolate(magnitudes: [Float], frequencies: [Float], peakIndex i: Int) -> (frequency: Float, magnitude: Float) {
        guard i > 0, i < magnitudes.count - 1 else {
            return (frequencies[i], magnitudes[i])
        }
        let val  = magnitudes[i]
        let lval = magnitudes[i - 1]
        let rval = magnitudes[i + 1]
        let denom = lval - 2 * val + rval
        // Avoid division by near-zero (flat top — bin is already accurate)
        guard abs(denom) > 1e-6 else {
            return (frequencies[i], val)
        }
        // Sub-bin offset δ ∈ (-0.5, 0.5)
        let delta = 0.5 * (lval - rval) / denom
        let binWidth = frequencies[i] - frequencies[i - 1]
        let interpFreq = frequencies[i] + delta * binWidth
        let interpMag  = val - 0.25 * (lval - rval) * delta
        return (interpFreq, interpMag)
    }

    /// Calculate Q factor and bandwidth for a peak.
    ///
    /// - Parameters:
    ///   - magnitudes:  dB spectrum array (same source as `frequencies`).
    ///   - frequencies: Frequency axis matching `magnitudes`.  Pass the gated FFT
    ///                  frequency array when called with gated-FFT data so the bin
    ///                  spacing is correct.  Defaults to the continuous FFT axis.
    ///   - peakIndex:   Index of the peak in the arrays.
    ///   - peakMagnitude: Peak magnitude in dB.
    func calculateQFactor(magnitudes: [Float], frequencies: [Float], peakIndex: Int, peakMagnitude: Float) -> (quality: Float, bandwidth: Float) {
        let threshold = peakMagnitude - 3.0  // -3dB points

        // Find lower -3dB point
        var lowerIdx = peakIndex
        while lowerIdx > 0 && magnitudes[lowerIdx] > threshold {
            lowerIdx -= 1
        }

        // Find upper -3dB point
        var upperIdx = peakIndex
        while upperIdx < magnitudes.count - 1 && magnitudes[upperIdx] > threshold {
            upperIdx += 1
        }

        guard peakIndex < frequencies.count,
              lowerIdx < frequencies.count,
              upperIdx < frequencies.count else {
            return (quality: 0, bandwidth: 0)
        }

        let lowerFreq = frequencies[lowerIdx]
        let upperFreq = frequencies[upperIdx]
        let centerFreq = frequencies[peakIndex]

        let bandwidth = upperFreq - lowerFreq
        let quality = bandwidth > 0 ? centerFreq / bandwidth : 0

        return (quality: quality, bandwidth: bandwidth)
    }
}
