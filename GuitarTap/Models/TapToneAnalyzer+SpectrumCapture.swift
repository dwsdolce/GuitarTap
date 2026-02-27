//
//  TapToneAnalyzer+SpectrumCapture.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import Foundation

extension TapToneAnalyzer {

    // MARK: - Spectrum Capture

    /// Finish capturing spectrum after capture window
    func finishCapture() {
        captureTimer?.invalidate()
        captureTimer = nil
    }
    
    /// Process multiple captured taps and average the results
    func processMultipleTaps() {
        guard !capturedTaps.isEmpty else { return }
        
        print("🔬 Processing \(capturedTaps.count) taps for averaging...")
        
        // Average the raw FFT spectrum across all taps FIRST
        let (avgMagnitudes, avgFrequencies) = averageSpectra(from: capturedTaps)
        
        // Freeze the averaged spectrum for display
        frozenFrequencies = avgFrequencies
        frozenMagnitudes = avgMagnitudes
        isSpectrumFrozen = true
        print("📸 Spectrum frozen with averaged data from \(capturedTaps.count) taps")
        
        // Now find peaks in the AVERAGED spectrum so they align with what's displayed
        // This ensures peak markers sit on actual peaks in the averaged waveform
        let peaksFromAveragedSpectrum = findPeaks(magnitudes: avgMagnitudes, frequencies: avgFrequencies)
        
        // Update current peaks with peaks from averaged spectrum
        currentPeaks = peaksFromAveragedSpectrum
        
        // Classify modes based on peaks
        identifiedModes = peaksFromAveragedSpectrum.map { peak in
            (peak: peak, mode: GuitarMode.classify(frequency: peak.frequency))
        }
        
        // Update status
        statusMessage = "Analysis complete! \(peaksFromAveragedSpectrum.count) peaks identified (from \(capturedTaps.count) averaged taps)."
        tapProgress = 1.0
        
        print("✅ Found \(peaksFromAveragedSpectrum.count) peaks in averaged spectrum from \(capturedTaps.count) taps")
    }
    
    /// Average peaks across multiple taps
    /// Maintains mode priority: strongest peak for each known mode is guaranteed,
    /// then fills remaining slots with additional peaks by magnitude
    func averagePeaks(from tapPeaks: [[ResonantPeak]]) -> [ResonantPeak] {
        guard !tapPeaks.isEmpty else { return [] }
        
        // If only one tap, return its peaks
        if tapPeaks.count == 1 {
            return tapPeaks[0]
        }
        
        // Collect all unique peak frequencies (with tolerance)
        var peakGroups: [[ResonantPeak]] = []
        let frequencyTolerance: Float = 5.0  // Hz
        
        // Group similar peaks across taps
        for tapIndex in 0..<tapPeaks.count {
            for peak in tapPeaks[tapIndex] {
                // Try to find existing group
                var foundGroup = false
                for groupIndex in 0..<peakGroups.count {
                    let groupAvgFreq = peakGroups[groupIndex].map({ $0.frequency }).reduce(0, +) / Float(peakGroups[groupIndex].count)
                    if abs(peak.frequency - groupAvgFreq) < frequencyTolerance {
                        peakGroups[groupIndex].append(peak)
                        foundGroup = true
                        break
                    }
                }
                
                // Create new group if no match found
                if !foundGroup {
                    peakGroups.append([peak])
                }
            }
        }
        
        // Average each group
        var averagedPeaks: [ResonantPeak] = []
        for group in peakGroups {
            let avgFreq = group.map({ $0.frequency }).reduce(0, +) / Float(group.count)
            let avgMag = group.map({ $0.magnitude }).reduce(0, +) / Float(group.count)
            let avgQuality = group.map({ $0.quality }).reduce(0, +) / Float(group.count)
            let avgBandwidth = group.map({ $0.bandwidth }).reduce(0, +) / Float(group.count)
            
            let averagedPeak = ResonantPeak(
                frequency: avgFreq,
                magnitude: avgMag,
                quality: avgQuality,
                bandwidth: avgBandwidth
            )
            averagedPeaks.append(averagedPeak)
        }
        
        // Apply mode-priority selection (same logic as findPeaks)
        // Define known modes to search for
        let knownModes: [GuitarMode] = [.air, .top, .back, .dipole, .ringMode, .upperModes]
        
        // Find strongest peak for each mode
        var strongestPeakPerMode: [GuitarMode: ResonantPeak] = [:]
        for peak in averagedPeaks {
            let mode = GuitarMode.classify(frequency: peak.frequency).normalized
            if mode != .unknown {
                if let existing = strongestPeakPerMode[mode] {
                    if peak.magnitude > existing.magnitude {
                        strongestPeakPerMode[mode] = peak
                    }
                } else {
                    strongestPeakPerMode[mode] = peak
                }
            }
        }
        
        // Build final list: mode peaks first, then fill remaining by magnitude
        var finalPeaks: [ResonantPeak] = []
        var includedPeakIDs = Set<UUID>()
        
        for mode in knownModes {
            if let peak = strongestPeakPerMode[mode] {
                finalPeaks.append(peak)
                includedPeakIDs.insert(peak.id)
            }
        }
        
        // Fill remaining slots
        // maxPeaks == 0 means "capture all peaks"
        if maxPeaks == 0 {
            // Add all remaining peaks (no limit)
            let otherPeaks = averagedPeaks
                .filter { !includedPeakIDs.contains($0.id) }
                .sorted { $0.magnitude > $1.magnitude }
            finalPeaks.append(contentsOf: otherPeaks)
        } else {
            let remainingSlots = maxPeaks - finalPeaks.count
            if remainingSlots > 0 {
                let otherPeaks = averagedPeaks
                    .filter { !includedPeakIDs.contains($0.id) }
                    .sorted { $0.magnitude > $1.magnitude }
                    .prefix(remainingSlots)
                finalPeaks.append(contentsOf: otherPeaks)
            }
        }
        
        // Sort final result by magnitude descending
        return finalPeaks.sorted { $0.magnitude > $1.magnitude }
    }
    
    /// Average raw FFT spectra across multiple taps
    func averageSpectra(from taps: [(magnitudes: [Float], frequencies: [Float], captureTime: Date)]) -> (magnitudes: [Float], frequencies: [Float]) {
        guard !taps.isEmpty else { return ([], []) }
        
        // If only one tap, return its spectrum
        if taps.count == 1 {
            return (taps[0].magnitudes, taps[0].frequencies)
        }
        
        // Ensure all spectra have the same length
        let spectrumLength = taps[0].magnitudes.count
        guard taps.allSatisfy({ $0.magnitudes.count == spectrumLength }) else {
            print("⚠️ Warning: Spectrum lengths don't match, using first tap only")
            return (taps[0].magnitudes, taps[0].frequencies)
        }
        
        // Average magnitudes bin-by-bin
        var averagedMagnitudes = [Float](repeating: 0, count: spectrumLength)
        
        // Convert dB to linear (power), average, then convert back to dB
        for binIndex in 0..<spectrumLength {
            var linearSum: Float = 0
            
            for tap in taps {
                let magnitudeDB = tap.magnitudes[binIndex]
                // Convert dB to linear power: power = 10^(dB/10)
                let linearPower = pow(10.0, magnitudeDB / 10.0)
                linearSum += linearPower
            }
            
            // Average and convert back to dB
            let averageLinear = linearSum / Float(taps.count)
            averagedMagnitudes[binIndex] = 10.0 * log10(averageLinear)
        }
        
        // Frequencies should be identical across all taps, use first one
        let frequencies = taps[0].frequencies
        
        print("📊 Averaged \(taps.count) spectra: \(spectrumLength) bins each")
        
        return (magnitudes: averagedMagnitudes, frequencies: frequencies)
    }
}
