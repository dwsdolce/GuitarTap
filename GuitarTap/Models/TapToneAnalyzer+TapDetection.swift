//
//  TapToneAnalyzer+TapDetection.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import SwiftUI
import Combine

extension TapToneAnalyzer {

    // MARK: - Tap Detection

    /// Detect tap events using rising edge detection with hysteresis
    func detectTap(peakMagnitude: Float, magnitudes: [Float], frequencies: [Float]) {
        let now = Date()

        // For material/brace modes, use relative spike detection: compare the
        // instantaneous level against a tracked noise floor rather than an absolute
        // threshold.  This keeps detection working when ambient noise is elevated.
        let useRelativeDetection: Bool = {
            let t = SpectrumDisplaySettings.measurementType
            return t == .material || t == .brace
        }()

        // Update the noise floor estimate (EMA) whenever the signal is at background level.
        // We update during warm-up as well — this is the most valuable time to build an
        // accurate noise floor since no taps have occurred yet.
        // Only update while not above threshold so tap energy doesn't inflate the estimate.
        if useRelativeDetection && !isAboveThreshold {
            noiseFloorEstimate = noiseFloorAlpha * peakMagnitude + (1 - noiseFloorAlpha) * noiseFloorEstimate
        }

        // Compute effective thresholds.
        // Guitar mode:          absolute threshold (original behaviour).
        // Material/brace mode:  noise floor + headroom derived from the threshold slider.
        //                       The slider value is absolute dB (-80…-20); we use it as
        //                       the target "tap above noise floor" margin by computing
        //                       headroom = tapDetectionThreshold - noiseFloorEstimate,
        //                       clamped to at least 6 dB so there is always a gap to cross.
        let effectiveRisingThreshold: Float
        let effectiveFallingThreshold: Float
        if useRelativeDetection {
            // Minimum 10 dB above noise floor — rejects small ambient spikes (typically
            // 1–4 dB above floor) while catching real taps (typically 12–30 dB above floor).
            // The tapDetectionThreshold slider sets the absolute upper bound; for quiet
            // environments with an elevated noise floor the relative headroom takes over.
            let headroom = max(tapDetectionThreshold - noiseFloorEstimate, 10.0)
            effectiveRisingThreshold  = noiseFloorEstimate + headroom
            effectiveFallingThreshold = noiseFloorEstimate + max(headroom - hysteresisMargin, 4.0)
        } else {
            effectiveRisingThreshold  = tapDetectionThreshold
            effectiveFallingThreshold = tapDetectionThreshold - hysteresisMargin
        }

        // Check if we're still in warm-up period (prevents false detections on startup)
        if let startTime = analyzerStartTime, now.timeIntervalSince(startTime) < warmupPeriod {
            tapDetected = false
            statusMessage = "Initializing... (\(String(format: "%.1f", warmupPeriod - now.timeIntervalSince(startTime)))s)"
            justExitedWarmup = true  // Mark that next frame is first after warm-up
            return
        }

        // First frame after warm-up: re-anchor noise floor and sync threshold state.
        // The noise floor EMA may have converged to a bad value if inputLevelDB was
        // -100 dB before the first audio buffer arrived (e.g. at app launch).  Now
        // that we have real audio data, snap the noise floor to the current level so
        // the headroom calculation starts from an accurate baseline.
        if justExitedWarmup {
            justExitedWarmup = false
            if useRelativeDetection {
                // Re-anchor to current signal level; EMA will track from here.
                noiseFloorEstimate = peakMagnitude
                // Recompute rising threshold with the corrected noise floor.
                let h = max(tapDetectionThreshold - noiseFloorEstimate, 10.0)
                let risingAnchored = noiseFloorEstimate + h
                isAboveThreshold = peakMagnitude > risingAnchored
                print("🎬 Warm-up complete - signal at \(String(format: "%.1f", peakMagnitude)) dB, noise floor (re-anchored) \(String(format: "%.1f", noiseFloorEstimate)) dB, rising threshold \(String(format: "%.1f", risingAnchored)) dB, isAboveThreshold = \(isAboveThreshold)")
            } else {
                isAboveThreshold = peakMagnitude > effectiveRisingThreshold
                print("🎬 Warm-up complete - signal at \(String(format: "%.1f", peakMagnitude)) dB, rising threshold \(String(format: "%.1f", effectiveRisingThreshold)) dB, isAboveThreshold = \(isAboveThreshold)")
            }
            // Don't detect on this frame - just sync the state
            tapDetected = false
            statusMessage = numberOfTaps == 1 ? "Tap the guitar..." : "Tap the guitar \(numberOfTaps) times..."
            return
        }

        // Check cooldown
        if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) < tapCooldown {
            tapDetected = false
            return
        }

        // Update status message if ready and waiting for tap
        if currentTapCount == 0 && statusMessage.contains("Initializing") {
            statusMessage = numberOfTaps == 1 ? "Tap the guitar..." : "Tap the guitar \(numberOfTaps) times..."
        }

        // Update the detection level for UI display
        tapDetectionLevel = effectiveRisingThreshold

        // Hysteresis: Use different thresholds for rising vs falling edges
        let risingThreshold  = effectiveRisingThreshold
        let fallingThreshold = effectiveFallingThreshold

        // Determine if currently above threshold (with hysteresis)
        let currentlyAboveThreshold = isAboveThreshold ?
            (peakMagnitude > fallingThreshold) :  // When above: use lower threshold to stay "above"
            (peakMagnitude > risingThreshold)     // When below: use higher threshold to go "above"

        // Debug: Log state transitions
        if currentlyAboveThreshold != isAboveThreshold {
            print("🔄 Threshold crossing: \(isAboveThreshold ? "ABOVE→BELOW" : "BELOW→ABOVE") at \(peakMagnitude) dB (rising: \(risingThreshold), falling: \(fallingThreshold))")
            
            // Update status message when signal settles after a tap in multi-tap mode
            if !currentlyAboveThreshold && isAboveThreshold && currentTapCount > 0 && currentTapCount < numberOfTaps {
                statusMessage = "Tap \(currentTapCount)/\(numberOfTaps) captured. Tap again..."
            }
        }
        
        // Detect tap only when crossing from below to above threshold
        if currentlyAboveThreshold && !isAboveThreshold {
            // Rising edge detected! 📈
            tapDetected = true
            lastTapTime = now
            
            // Capture the recent peak input level for decay tracking reference
            // Use recentPeakLevelDB which holds the max level over the last 0.5s
            // This ensures we get the actual tap peak even though FFT detection is delayed
            tapPeakLevel = fftAnalyzer.recentPeakLevelDB
            print("🎯 Tap detected! FFT peak: \(String(format: "%.1f", peakMagnitude)) dB, Input peak: \(String(format: "%.1f", tapPeakLevel)) dB (threshold: \(risingThreshold) dB) [Rising Edge]")
            
            // Handle tap in multi-tap sequence
            handleTapDetection(magnitudes: magnitudes, frequencies: frequencies, time: now)
        } else {
            tapDetected = false
        }
        
        // Update state for next frame
        isAboveThreshold = currentlyAboveThreshold
    }
    
    /// Handle a detected tap in the multi-tap sequence
    func handleTapDetection(magnitudes: [Float], frequencies: [Float], time: Date) {
        // Stop detection temporarily
        isDetecting = false
        
        let measurementType = SpectrumDisplaySettings.measurementType
        let isMaterialMode = measurementType == .material
        let isBraceMode = measurementType == .brace
        
        // Handle material/brace mode with phase-based capture
        if isMaterialMode || isBraceMode {
            handleMaterialTapDetection(magnitudes: magnitudes, frequencies: frequencies, time: time)
            return
        }
        
        // Standard guitar mode handling
        // Store spectrum data immediately
        capturedTaps.append((magnitudes: magnitudes, frequencies: frequencies, captureTime: time))
        
        // Increment tap count
        currentTapCount += 1
        tapProgress = Float(currentTapCount) / Float(numberOfTaps)
        
        print("📊 Captured tap \(currentTapCount) of \(numberOfTaps)")
        
        // Start decay tracking for ring-out time measurement
        // This continues for 3 seconds after the tap to capture full decay
        startDecayTracking()
        
        // Start capture window timer to collect spectrum during ring-out
        captureTimer?.invalidate()
        captureTimer = Timer.scheduledTimer(withTimeInterval: captureWindow, repeats: false) { [weak self] _ in
            self?.finishCapture()
        }
        
        // Update status
        if currentTapCount < numberOfTaps {
            statusMessage = "Tap \(currentTapCount)/\(numberOfTaps) captured. Tap again..."
        } else {
            statusMessage = "All taps captured. Processing..."
        }
        
        // If we've collected all taps, process them
        if currentTapCount >= numberOfTaps {
            DispatchQueue.main.asyncAfter(deadline: .now() + captureWindow) { [weak self] in
                self?.processMultipleTaps()
            }
        } else {
            // Re-enable detection after cooldown for next tap
            // First, wait for the cooldown period
            DispatchQueue.main.asyncAfter(deadline: .now() + tapCooldown) { [weak self] in
                guard let self = self else { return }
                
                // Check if the signal has dropped below the falling threshold
                // If it has, we can immediately start looking for the next tap
                let currentLevel = self.fftAnalyzer.peakMagnitude
                let fallingThreshold = self.tapDetectionThreshold - self.hysteresisMargin
                
                if currentLevel <= fallingThreshold {
                    // Signal has dropped - ready for next tap
                    self.isAboveThreshold = false
                    self.isDetecting = true
                    self.tapDetected = false
                    self.statusMessage = "Tap \(self.currentTapCount)/\(self.numberOfTaps) captured. Tap again..."
                    print("🔄 Ready for tap \(self.currentTapCount + 1) of \(self.numberOfTaps) - signal dropped to \(String(format: "%.1f", currentLevel)) dB (below falling threshold \(String(format: "%.1f", fallingThreshold)) dB)")
                } else {
                    // Signal still elevated - set isAboveThreshold correctly and wait for drop
                    // The hysteresis logic in detectTap will naturally detect the falling edge
                    // and then be ready for the next rising edge
                    self.isAboveThreshold = true
                    self.isDetecting = true
                    self.tapDetected = false
                    self.statusMessage = "Tap \(self.currentTapCount)/\(self.numberOfTaps) captured. Waiting for settle..."
                    print("🔄 Waiting for tap \(self.currentTapCount + 1) of \(self.numberOfTaps) - signal at \(String(format: "%.1f", currentLevel)) dB (still above falling threshold \(String(format: "%.1f", fallingThreshold)) dB)")
                }
            }
        }
    }
    
    /// Total number of taps expected across all material/brace phases
    var totalMaterialTaps: Int {
        let type = SpectrumDisplaySettings.measurementType
        if type == .brace {
            return numberOfTaps  // Brace mode: only longitudinal phase
        }
        return numberOfTaps * (SpectrumDisplaySettings.measureFlc ? 3 : 2)
    }
    
    /// Handle tap detection for material measurement mode (multi-phase, multi-tap capture).
    ///
    /// Instead of using the long-window FFT magnitudes (which become stale noise after
    /// ~200 ms), this opens a short gated PCM capture window so `computeGatedFFT`
    /// can produce a fresh spectrum from just the ring-out audio.
    func handleMaterialTapDetection(magnitudes: [Float], frequencies: [Float], time: Date) {
        // Stop detection while we capture the ring-out window
        isDetecting = false

        let phase = materialTapPhase
        switch phase {
        case .capturingLongitudinal, .capturingCross, .waitingForCrossTap,
             .capturingFlc, .waitingForFlcTap:
            startGatedCapture(phase: phase)
        case .notStarted, .complete:
            print("⚠️ Unexpected tap in material phase: \(phase)")
        }
    }
    
    /// Process a tap captured during the longitudinal phase
    func handleLongitudinalTapProgress(magnitudes: [Float], frequencies: [Float]) {
        let captured = materialCapturedTaps.count
        let total = numberOfTaps
        print("📊 Captured LONGITUDINAL tap \(captured)/\(total)")
        
        if captured < total {
            // More taps needed - update status and re-enable detection
            statusMessage = "L tap \(captured)/\(total) captured. Tap again..."
            reEnableDetectionForNextMaterialTap()
        } else {
            // All L taps done - average spectra and transition to cross phase
            let (avgMags, avgFreqs) = averageSpectra(from: materialCapturedTaps)
            longitudinalSpectrum = (magnitudes: avgMags, frequencies: avgFreqs)
            longitudinalPeaks = findPeaks(magnitudes: avgMags, frequencies: avgFreqs)
            
            // Auto-select the peak in the measurement-appropriate frequency range.
            // For brace mode the relevant range is 100–1000 Hz; for material/plate it is
            // 30–600 Hz. Prefer a peak in that window over a louder low-frequency noise
            // peak (e.g. 78 Hz table vibration excited by the tap impact).
            let mType = SpectrumDisplaySettings.measurementType
            let loSel: Float = (mType == .brace) ? 100 : 30
            let hiSel: Float = SpectrumDisplaySettings.defaultMaxFrequency(for: mType)
            let rangedPeak = longitudinalPeaks.first(where: { $0.frequency >= loSel && $0.frequency <= hiSel })
            let bestPeak = rangedPeak ?? longitudinalPeaks.first
            if let peak = bestPeak {
                autoSelectedLongitudinalPeakID = peak.id
                selectedLongitudinalPeak = peak
                print("🔵 Auto-selected longitudinal peak: \(peak.frequency) Hz")
            }
            
            // Freeze averaged spectrum
            frozenFrequencies = avgFreqs
            frozenMagnitudes = avgMags
            isSpectrumFrozen = true
            currentPeaks = longitudinalPeaks
            
            materialCapturedTaps = []
            
            let isBraceMode = SpectrumDisplaySettings.measurementType == .brace
            if isBraceMode {
                // Brace mode: complete after longitudinal tap only
                // Restrict currentPeaks to only the auto-selected longitudinal peak
                if let selID = autoSelectedLongitudinalPeakID,
                   let selPeak = longitudinalPeaks.first(where: { $0.id == selID }) {
                    currentPeaks = [selPeak]
                } else if let first = longitudinalPeaks.first {
                    currentPeaks = [first]
                } else {
                    currentPeaks = []
                }
                // Clear frozen spectrum — display uses per-phase spectra directly
                isSpectrumFrozen = false
                frozenFrequencies = []
                frozenMagnitudes = []
                materialTapPhase = .complete
                tapProgress = 1.0
                let avgNote = total > 1 ? " (\(total) taps averaged)" : ""
                statusMessage = "Complete\(avgNote) - check Results"
                print("✅ Brace measurement complete: fL=\(longitudinalPeaks.first?.frequency ?? 0) Hz")
            } else {
                // Material mode: continue to cross-grain tap
                materialTapPhase = .waitingForCrossTap
                let avgNote = total > 1 ? " (\(total) taps averaged)" : ""
                statusMessage = "L captured\(avgNote) - rotate 90° for C tap"
                
                // Re-enable for cross tap after cooldown
                DispatchQueue.main.asyncAfter(deadline: .now() + tapCooldown) { [weak self] in
                    guard let self = self else { return }
                    let currentLevel = self.fftAnalyzer.peakMagnitude
                    let fallingThreshold = self.tapDetectionThreshold - self.hysteresisMargin
                    self.isAboveThreshold = currentLevel > fallingThreshold
                    self.isDetecting = true
                    self.tapDetected = false
                    self.materialTapPhase = .capturingCross
                    self.isSpectrumFrozen = false
                    self.frozenFrequencies = []
                    self.frozenMagnitudes = []
                    self.analyzerStartTime = Date()
                    print("🔄 Ready for cross-grain tap")
                }
            }
        }
    }
    
    /// Process a tap captured during the cross-grain phase
    func handleCrossTapProgress(magnitudes: [Float], frequencies: [Float]) {
        let captured = materialCapturedTaps.count
        let total = numberOfTaps
        print("📊 Captured CROSS-GRAIN tap \(captured)/\(total)")
        
        if captured < total {
            statusMessage = "C tap \(captured)/\(total) captured. Tap again..."
            reEnableDetectionForNextMaterialTap()
        } else {
            // All C taps done - average and decide next phase
            let (avgMags, avgFreqs) = averageSpectra(from: materialCapturedTaps)
            crossSpectrum = (magnitudes: avgMags, frequencies: avgFreqs)
            crossPeaks = findPeaks(magnitudes: avgMags, frequencies: avgFreqs)
            
            // Auto-select the best cross-grain peak.
            // For plate/material measurements all resonances (fL, fC, fLC) are low-frequency
            // (typically 30–200 Hz). Prefer the lowest-frequency peak in that window so we
            // don't accidentally pick a louder higher-harmonic or body resonance.
            // If fL is already known, bound fC to a physically plausible range around it.
            let fLfreq = longitudinalPeaks.first(where: { autoSelectedLongitudinalPeakID == $0.id })?.frequency
                      ?? longitudinalPeaks.first?.frequency
            let plateCeiling: Float = 250   // No plate fC should be above 250 Hz
            let crossLo: Float = 20
            let crossHi: Float
            if let fL = fLfreq {
                // Allow up to 3× fL but cap at plateCeiling
                crossHi = min(fL * 3.0, plateCeiling)
            } else {
                crossHi = plateCeiling
            }
            // Sort by frequency ascending so we pick the lowest peak in the window
            let sortedCross = crossPeaks.sorted { $0.frequency < $1.frequency }
            let rangedCrossPeak = sortedCross.first(where: { $0.frequency >= crossLo && $0.frequency <= crossHi })
            let bestCrossPeak = rangedCrossPeak ?? crossPeaks.first
            if let peak = bestCrossPeak {
                autoSelectedCrossPeakID = peak.id
                selectedCrossPeak = peak
                print("🟠 Auto-selected cross-grain peak: \(peak.frequency) Hz (window \(crossLo)–\(crossHi) Hz)")
            }
            
            materialCapturedTaps = []
            
            let measureFlc = SpectrumDisplaySettings.measureFlc
            if measureFlc {
                // Move to FLC phase
                currentPeaks = combineMaterialPeaks()
                frozenFrequencies = avgFreqs
                frozenMagnitudes = avgMags
                isSpectrumFrozen = true
                
                materialTapPhase = .waitingForFlcTap
                let avgNote = total > 1 ? " (\(total) taps averaged)" : ""
                statusMessage = "C captured\(avgNote) - set up for FLC tap"
                
                DispatchQueue.main.asyncAfter(deadline: .now() + tapCooldown) { [weak self] in
                    guard let self = self else { return }
                    let currentLevel = self.fftAnalyzer.peakMagnitude
                    let fallingThreshold = self.tapDetectionThreshold - self.hysteresisMargin
                    self.isAboveThreshold = currentLevel > fallingThreshold
                    self.isDetecting = true
                    self.tapDetected = false
                    self.materialTapPhase = .capturingFlc
                    self.isSpectrumFrozen = false
                    self.frozenFrequencies = []
                    self.frozenMagnitudes = []
                    self.analyzerStartTime = Date()
                    print("🔄 Ready for FLC tap")
                }
            } else {
                // Complete - no FLC
                // Restrict currentPeaks to only the auto-selected L and C peaks
                var selectedPeaks: [ResonantPeak] = []
                if let selID = autoSelectedLongitudinalPeakID,
                   let p = longitudinalPeaks.first(where: { $0.id == selID }) { selectedPeaks.append(p) }
                else if let p = longitudinalPeaks.first { selectedPeaks.append(p) }
                if let selID = autoSelectedCrossPeakID,
                   let p = crossPeaks.first(where: { $0.id == selID }) { selectedPeaks.append(p) }
                else if let p = crossPeaks.first { selectedPeaks.append(p) }
                currentPeaks = selectedPeaks
                // Clear frozen spectrum — display uses per-phase spectra directly
                isSpectrumFrozen = false
                frozenFrequencies = []
                frozenMagnitudes = []
                materialTapPhase = .complete
                tapProgress = 1.0
                let avgNote = total > 1 ? " (\(total) taps averaged each)" : ""
                statusMessage = "Complete\(avgNote) - check Results"
                print("✅ Material measurement complete: L=\(longitudinalPeaks.first?.frequency ?? 0) Hz, C=\(crossPeaks.first?.frequency ?? 0) Hz")
            }
        }
    }
    
    /// Process a tap captured during the FLC phase
    func handleFlcTapProgress(magnitudes: [Float], frequencies: [Float]) {
        let captured = materialCapturedTaps.count
        let total = numberOfTaps
        print("📊 Captured FLC tap \(captured)/\(total)")
        
        if captured < total {
            statusMessage = "FLC tap \(captured)/\(total) captured. Tap again..."
            reEnableDetectionForNextMaterialTap()
        } else {
            // All FLC taps done - average and complete
            let (avgMags, avgFreqs) = averageSpectra(from: materialCapturedTaps)
            flcSpectrum = (magnitudes: avgMags, frequencies: avgFreqs)
            flcPeaks = findPeaks(magnitudes: avgMags, frequencies: avgFreqs)
            
            // Auto-select the best FLC (shear/diagonal) peak.
            // fLC is typically the lowest resonance frequency of the three plate modes.
            // Bound the search below fL (if known) or below 150 Hz.
            let fLfreqF = longitudinalPeaks.first(where: { autoSelectedLongitudinalPeakID == $0.id })?.frequency
                       ?? longitudinalPeaks.first?.frequency
            let flcCeiling: Float
            if let fL = fLfreqF {
                // fLC should be below fL; allow up to 1.5× fL as generous upper bound
                flcCeiling = min(fL * 1.5, 200)
            } else {
                flcCeiling = 150
            }
            // Sort by frequency ascending to prefer the lowest peak in the window
            let sortedFlc = flcPeaks.sorted { $0.frequency < $1.frequency }
            let rangedFlcPeak = sortedFlc.first(where: { $0.frequency >= 20 && $0.frequency <= flcCeiling })
            let bestFlcPeak = rangedFlcPeak ?? flcPeaks.first
            if let peak = bestFlcPeak {
                autoSelectedFlcPeakID = peak.id
                selectedFlcPeak = peak
                print("🟣 Auto-selected FLC peak: \(peak.frequency) Hz (ceiling \(flcCeiling) Hz)")
            }
            
            materialCapturedTaps = []
            // Restrict currentPeaks to only the auto-selected L, C, and FLC peaks
            var selectedPeaks: [ResonantPeak] = []
            if let selID = autoSelectedLongitudinalPeakID,
               let p = longitudinalPeaks.first(where: { $0.id == selID }) { selectedPeaks.append(p) }
            else if let p = longitudinalPeaks.first { selectedPeaks.append(p) }
            if let selID = autoSelectedCrossPeakID,
               let p = crossPeaks.first(where: { $0.id == selID }) { selectedPeaks.append(p) }
            else if let p = crossPeaks.first { selectedPeaks.append(p) }
            if let selID = autoSelectedFlcPeakID,
               let p = flcPeaks.first(where: { $0.id == selID }) { selectedPeaks.append(p) }
            else if let p = flcPeaks.first { selectedPeaks.append(p) }
            currentPeaks = selectedPeaks
            // Clear frozen spectrum — display uses per-phase spectra directly
            isSpectrumFrozen = false
            frozenFrequencies = []
            frozenMagnitudes = []
            materialTapPhase = .complete
            tapProgress = 1.0
            let avgNote = total > 1 ? " (\(total) taps averaged each)" : ""
            statusMessage = "Complete\(avgNote) - check Results"
            print("✅ Material measurement complete: L=\(longitudinalPeaks.first?.frequency ?? 0) Hz, C=\(crossPeaks.first?.frequency ?? 0) Hz, FLC=\(flcPeaks.first?.frequency ?? 0) Hz")
        }
    }
    
    /// Re-enable tap detection for the next tap within the same material phase
    func reEnableDetectionForNextMaterialTap() {
        DispatchQueue.main.asyncAfter(deadline: .now() + tapCooldown) { [weak self] in
            guard let self = self else { return }
            let currentLevel = self.fftAnalyzer.inputLevelDB
            let fallingThreshold = self.tapDetectionThreshold - self.hysteresisMargin
            self.isAboveThreshold = currentLevel > fallingThreshold
            self.isDetecting = true
            self.tapDetected = false
            // Do NOT reset analyzerStartTime here — that would restart warmup and
            // destabilise isAboveThreshold via the justExitedWarmup sync path.
        }
    }
    
    /// Combine peaks from longitudinal, cross-grain, and optionally FLC taps for display
    func combineMaterialPeaks() -> [ResonantPeak] {
        var combined: [ResonantPeak] = []
        
        // Add longitudinal peaks (these will show as "L" in the UI)
        combined.append(contentsOf: longitudinalPeaks)
        
        // Add cross-grain peaks, avoiding duplicates within frequency tolerance
        // BUT always include the auto-selected cross peak even if it's close to an L peak
        let frequencyTolerance: Float = 5.0 // Hz
        for crossPeak in crossPeaks {
            // Always include the auto-selected cross peak
            let isAutoSelected = crossPeak.id == autoSelectedCrossPeakID
            
            let isDuplicate = combined.contains { existingPeak in
                abs(existingPeak.frequency - crossPeak.frequency) < frequencyTolerance
            }
            
            if isAutoSelected || !isDuplicate {
                combined.append(crossPeak)
            }
        }
        
        // Add FLC peaks if available, same deduplication logic
        for flcPeak in flcPeaks {
            let isAutoSelected = flcPeak.id == autoSelectedFlcPeakID
            let isDuplicate = combined.contains { existingPeak in
                abs(existingPeak.frequency - flcPeak.frequency) < frequencyTolerance
            }
            if isAutoSelected || !isDuplicate {
                combined.append(flcPeak)
            }
        }
        
        // Sort by frequency
        return combined.sorted { $0.frequency < $1.frequency }
    }
}
