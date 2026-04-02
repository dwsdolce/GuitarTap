//
//  TapToneAnalyzer+TapDetection.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

/// # TapToneAnalyzer+TapDetection
///
/// Rising-edge hysteresis tap detector and multi-phase plate/brace capture
/// sequencer.
///
/// ## Guitar Mode — Absolute Threshold with Hysteresis
/// For guitar measurements the FFT `peakMagnitude` is compared against two
/// absolute dB thresholds:
///
/// ```
/// risingThreshold  = tapDetectionThreshold
/// fallingThreshold = tapDetectionThreshold − hysteresisMargin
/// ```
///
/// A tap fires only on the **rising edge** (transition from below-rising to
/// above-rising). The `isAboveThreshold` flag uses the wider falling threshold
/// to latch `true` until the signal genuinely settles, preventing false
/// re-triggers from the ring-out decay envelope.
///
/// ## Plate / Brace Mode — Relative Threshold
/// The long-window FFT dilutes tap transients by ~15 dB (energy spread across
/// the full window); plate/brace detection therefore uses `inputLevelDB` from
/// the fast polling subscription instead of `peakMagnitude`. Within the
/// `detectTap` method, relative thresholds are derived from a running noise
/// floor EMA (α = 0.05, τ ≈ 190 ms at 10 Hz):
///
/// ```
/// headroom             = max(tapDetectionThreshold − noiseFloorEstimate, 10 dB)
/// risingThreshold      = noiseFloorEstimate + headroom
/// fallingThreshold     = noiseFloorEstimate + max(headroom − hysteresisMargin, 4 dB)
/// ```
///
/// The 10 dB minimum headroom rejects small ambient spikes (typically 1–4 dB
/// above the noise floor) while reliably catching real taps (12–30 dB above).
///
/// ## Warm-Up Period
/// The first 0.5 s after `start()` or `resumeTapDetection()` is a warm-up
/// period during which tap detection is suppressed. On the first frame after
/// warm-up, `justExitedWarmup` triggers a one-time re-anchor of the noise
/// floor EMA and `isAboveThreshold` state so the hysteresis calculation starts
/// from an accurate baseline (the EMA may have converged to −100 dB before
/// the first real audio buffer arrived).
///
/// ## Multi-Phase Plate Sequencer
/// For plate/brace measurements, `handlePlateTapDetection` opens a gated PCM
/// capture window (see `TapToneAnalyzer+SpectrumCapture`) instead of
/// accumulating from the continuous FFT. The phase state machine progresses:
///
/// ```
/// notStarted → capturingLongitudinal → waitingForCrossTap
///           → capturingCross → [waitingForFlcTap → capturingFlc →] complete
/// ```
///
/// Each phase uses a dedicated gated-FFT handler in `TapToneAnalyzer+SpectrumCapture`
/// (`handleLongitudinalGatedProgress`, `handleCrossGatedProgress`,
/// `handleFlcGatedProgress`) that captures a fresh short-window FFT from raw
/// PCM rather than the long-window continuous FFT.

import SwiftUI
import Combine

extension TapToneAnalyzer {

    // MARK: - Tap Detection

    /// Evaluates the current signal level against the active detection threshold
    /// and fires a tap event on a rising edge.
    ///
    /// Called from ``analyzeMagnitudes(_:frequencies:peakMagnitude:)`` for
    /// guitar mode, and from the fast `inputLevelDB` polling subscription for
    /// plate/brace mode.
    ///
    /// - Parameters:
    ///   - peakMagnitude: Current peak dBFS level used for threshold comparison.
    ///     For guitar mode this is the FFT peak magnitude; for plate/brace it is
    ///     `fftAnalyzer.inputLevelDB` sampled at ~10 Hz.
    ///   - magnitudes: Current FFT magnitude spectrum (passed through to
    ///     ``handleTapDetection(magnitudes:frequencies:time:)`` for spectrum
    ///     capture on a confirmed tap).
    ///   - frequencies: Frequency axis matching `magnitudes`, in Hz.
    func detectTap(peakMagnitude: Float, magnitudes: [Float], frequencies: [Float]) {
        let now = Date()

        // For plate/brace modes, use relative spike detection: compare the
        // instantaneous level against a tracked noise floor rather than an absolute
        // threshold.  This keeps detection working when ambient noise is elevated.
        let useRelativeDetection: Bool = {
            let t = TapDisplaySettings.measurementType
            return t == .plate || t == .brace
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
        // Plate/brace mode:     noise floor + headroom derived from the threshold slider.
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
            TAP_DEBUG("detectTap", "RELATIVE mode | peakMag=\(String(format: "%.2f", peakMagnitude)) noiseFloor=\(String(format: "%.2f", noiseFloorEstimate)) headroom=\(String(format: "%.2f", headroom)) risingThresh=\(String(format: "%.2f", effectiveRisingThreshold)) fallingThresh=\(String(format: "%.2f", effectiveFallingThreshold)) isAboveThreshold=\(isAboveThreshold)")
        } else {
            effectiveRisingThreshold  = tapDetectionThreshold
            effectiveFallingThreshold = tapDetectionThreshold - hysteresisMargin
            TAP_DEBUG("detectTap", "ABSOLUTE mode | peakMag=\(String(format: "%.2f", peakMagnitude)) risingThresh=\(String(format: "%.2f", effectiveRisingThreshold)) fallingThresh=\(String(format: "%.2f", effectiveFallingThreshold)) isAboveThreshold=\(isAboveThreshold)")
        }

        // Check if we're still in warm-up period (prevents false detections on startup)
        if let startTime = analyzerStartTime, now.timeIntervalSince(startTime) < warmupPeriod {
            let remaining = warmupPeriod - now.timeIntervalSince(startTime)
            TAP_DEBUG("detectTap", "WARMUP in progress | remaining=\(String(format: "%.2f", remaining))s peakMag=\(String(format: "%.2f", peakMagnitude))")
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
                TAP_DEBUG("detectTap", "WARMUP EXIT (relative) | peakMag=\(String(format: "%.2f", peakMagnitude)) noiseFloorAnchored=\(String(format: "%.2f", noiseFloorEstimate)) risingAnchored=\(String(format: "%.2f", risingAnchored)) isAboveThreshold=\(isAboveThreshold)")
            } else {
                isAboveThreshold = peakMagnitude > effectiveRisingThreshold
                TAP_DEBUG("detectTap", "WARMUP EXIT (absolute) | peakMag=\(String(format: "%.2f", peakMagnitude)) risingThresh=\(String(format: "%.2f", effectiveRisingThreshold)) isAboveThreshold=\(isAboveThreshold)")
            }
            // Don't detect on this frame - just sync the state
            tapDetected = false
            statusMessage = numberOfTaps == 1 ? "Tap the guitar..." : "Tap the guitar \(numberOfTaps) times..."
            return
        }

        // Check cooldown
        if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) < tapCooldown {
            let cooldownRemaining = tapCooldown - now.timeIntervalSince(lastTap)
            TAP_DEBUG("detectTap", "COOLDOWN active | remaining=\(String(format: "%.3f", cooldownRemaining))s peakMag=\(String(format: "%.2f", peakMagnitude))")
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

        // Determine if currently above threshold (with hysteresis).
        // When latched above: use the lower falling threshold to stay "above".
        // When latched below: use the higher rising threshold to cross "above".
        let currentlyAboveThreshold = isAboveThreshold ?
            (peakMagnitude > fallingThreshold) :
            (peakMagnitude > risingThreshold)

        TAP_DEBUG("detectTap", "HYSTERESIS eval | peakMag=\(String(format: "%.2f", peakMagnitude)) wasAbove=\(isAboveThreshold) nowAbove=\(currentlyAboveThreshold) risingThresh=\(String(format: "%.2f", risingThreshold)) fallingThresh=\(String(format: "%.2f", fallingThreshold)) isDetecting=\(isDetecting) currentTapCount=\(currentTapCount)")

        if currentlyAboveThreshold != isAboveThreshold {
            // Update status message when signal settles after a tap in multi-tap mode
            if !currentlyAboveThreshold && isAboveThreshold && currentTapCount > 0 && currentTapCount < numberOfTaps {
                TAP_DEBUG("detectTap", "SIGNAL SETTLED | tap \(currentTapCount)/\(numberOfTaps) — signal dropped below falling threshold")
                statusMessage = "Tap \(currentTapCount)/\(numberOfTaps) captured. Tap again..."
            }
        }
        
        // Detect tap only when crossing from below to above threshold (rising edge only)
        if currentlyAboveThreshold && !isAboveThreshold {
            // Rising edge detected!
            TAP_DEBUG("detectTap", "RISING EDGE FIRED | peakMag=\(String(format: "%.2f", peakMagnitude)) risingThresh=\(String(format: "%.2f", risingThreshold)) tapCount=\(currentTapCount+1)/\(numberOfTaps)")
            tapDetected = true
            lastTapTime = now
            
            // Capture the recent peak input level for decay tracking reference.
            // Use recentPeakLevelDB which holds the max level over the last 0.5 s.
            // This ensures we get the actual tap peak even though FFT detection is delayed.
            tapPeakLevel = fftAnalyzer.recentPeakLevelDB
            
            // Handle tap in multi-tap sequence
            handleTapDetection(magnitudes: magnitudes, frequencies: frequencies, time: now)
        } else {
            if currentlyAboveThreshold && isAboveThreshold {
                // Stays above — still in ring-out, no new tap
            } else if !currentlyAboveThreshold && !isAboveThreshold {
                // Stays below — waiting for tap
            } else {
                // Falling edge (was above, now below)
                TAP_DEBUG("detectTap", "FALLING EDGE | peakMag=\(String(format: "%.2f", peakMagnitude)) fallingThresh=\(String(format: "%.2f", fallingThreshold)) — signal settled, ready for next tap")
            }
            tapDetected = false
        }
        
        // Update state for next frame
        isAboveThreshold = currentlyAboveThreshold
    }
    
    /// Dispatches a confirmed tap event to the appropriate capture handler.
    ///
    /// For guitar mode: stores the current spectrum in `capturedTaps`, starts
    /// decay tracking, and starts the capture-window timer. When all required
    /// taps have been collected, schedules `processMultipleTaps()`.
    ///
    /// For plate/brace mode: delegates to ``handlePlateTapDetection(magnitudes:frequencies:time:)``.
    ///
    /// - Parameters:
    ///   - magnitudes: Current FFT magnitude spectrum (dBFS).
    ///   - frequencies: Frequency axis matching `magnitudes`, in Hz.
    ///   - time: Timestamp of the rising-edge tap detection event.
    func handleTapDetection(magnitudes: [Float], frequencies: [Float], time: Date) {
        // Stop detection temporarily
        isDetecting = false
        
        let measurementType = TapDisplaySettings.measurementType
        let isPlateMode = measurementType == .plate
        let isBraceMode = measurementType == .brace

        TAP_DEBUG("handleTapDetection", "ENTERED | measurementType=\(measurementType) isPlateMode=\(isPlateMode) isBraceMode=\(isBraceMode) currentTapCount=\(currentTapCount) numberOfTaps=\(numberOfTaps)")
        
        // Handle plate/brace mode with phase-based capture
        if isPlateMode || isBraceMode {
            TAP_DEBUG("handleTapDetection", "Routing to handlePlateTapDetection | phase=\(materialTapPhase)")
            handlePlateTapDetection(magnitudes: magnitudes, frequencies: frequencies, time: time)
            return
        }
        
        // Standard guitar mode handling
        // Store spectrum data immediately
        capturedTaps.append((magnitudes: magnitudes, frequencies: frequencies, captureTime: time))
        
        // Increment tap count
        currentTapCount += 1
        tapProgress = min(1.0, Float(currentTapCount) / Float(numberOfTaps))
        TAP_DEBUG("handleTapDetection", "GUITAR TAP STORED | currentTapCount=\(currentTapCount) numberOfTaps=\(numberOfTaps) tapProgress=\(String(format: "%.2f", tapProgress))")
        
        // Start decay tracking for ring-out time measurement.
        // This continues for 3 seconds after the tap to capture full decay.
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
            // Re-enable detection after cooldown for next tap.
            // First, wait for the cooldown period.
            DispatchQueue.main.asyncAfter(deadline: .now() + tapCooldown) { [weak self] in
                guard let self = self else { return }
                
                // Check if the signal has dropped below the falling threshold.
                // If it has, we can immediately start looking for the next tap.
                let currentLevel = self.fftAnalyzer.peakMagnitude
                let fallingThreshold = self.tapDetectionThreshold - self.hysteresisMargin
                
                if currentLevel <= fallingThreshold {
                    // Signal has dropped - ready for next tap
                    self.isAboveThreshold = false
                    self.isDetecting = true
                    self.tapDetected = false
                    self.statusMessage = "Tap \(self.currentTapCount)/\(self.numberOfTaps) captured. Tap again..."

                } else {
                    // Signal still elevated - set isAboveThreshold correctly and wait for drop.
                    // The hysteresis logic in detectTap will naturally detect the falling edge
                    // and then be ready for the next rising edge.
                    self.isAboveThreshold = true
                    self.isDetecting = true
                    self.tapDetected = false
                    self.statusMessage = "Tap \(self.currentTapCount)/\(self.numberOfTaps) captured. Waiting for settle..."

                }
            }
        }
    }
    
    /// The total number of individual taps expected across all plate/brace
    /// capture phases.
    ///
    /// - For brace mode: `numberOfTaps` (longitudinal phase only).
    /// - For plate mode without FLC: `numberOfTaps × 2` (L + C phases).
    /// - For plate mode with FLC: `numberOfTaps × 3` (L + C + FLC phases).
    ///
    /// Used to compute `tapProgress` (0.0–1.0) across the full multi-phase
    /// sequence.
    var totalPlateTaps: Int {
        let type = TapDisplaySettings.measurementType
        if type == .brace {
            return numberOfTaps  // Brace mode: only longitudinal phase
        }
        return numberOfTaps * (TapDisplaySettings.measureFlc ? 3 : 2)
    }
    
    /// Routes a plate/brace tap event to the active gated-FFT capture window.
    ///
    /// Instead of using the long-window FFT magnitudes (which become stale
    /// noise after ~200 ms), this opens a short gated PCM capture window so
    /// `computeGatedFFT` can produce a fresh spectrum from just the ring-out
    /// audio. The phase routing table:
    ///
    /// | Phase | Action |
    /// |---|---|
    /// | `.capturingLongitudinal` | `startGatedCapture(phase:)` |
    /// | `.capturingCross` | `startGatedCapture(phase:)` |
    /// | `.capturingFlc` | `startGatedCapture(phase:)` |
    /// | `.notStarted` / `.complete` | Unexpected — logs a warning |
    ///
    /// - Parameters:
    ///   - magnitudes: Continuous FFT spectrum at the moment of tap detection
    ///     (not used for plate/brace; gated FFT is used instead).
    ///   - frequencies: Corresponding frequency axis, in Hz.
    ///   - time: Timestamp of the tap event.
    func handlePlateTapDetection(magnitudes: [Float], frequencies: [Float], time: Date) {
        // Stop detection while we capture the ring-out window
        isDetecting = false

        let phase = materialTapPhase
        TAP_DEBUG("handlePlateTapDetection", "ENTERED | phase=\(phase) materialCapturedTaps.count=\(materialCapturedTaps.count) numberOfTaps=\(numberOfTaps)")
        switch phase {
        case .capturingLongitudinal, .capturingCross, .waitingForCrossTap,
             .capturingFlc, .waitingForFlcTap:
            TAP_DEBUG("handlePlateTapDetection", "Starting gated capture for phase=\(phase)")
            startGatedCapture(phase: phase)
        case .notStarted, .complete:
            TAP_DEBUG("handlePlateTapDetection", "UNEXPECTED TAP | phase=\(phase) — tap ignored")
            print("⚠️ Unexpected tap in plate phase: \(phase)")
        }
    }
    
    /// Re-enables tap detection after a brief cooldown, used between
    /// consecutive taps within the same plate/brace capture phase.
    ///
    /// Waits `tapCooldown` seconds, then checks the current input level
    /// to seed `isAboveThreshold` correctly so the hysteresis logic starts
    /// from an accurate state.
    ///
    /// - Important: Does **not** reset `analyzerStartTime` — doing so would
    ///   restart the warm-up timer and destabilise `isAboveThreshold` via
    ///   the `justExitedWarmup` sync path.
    func reEnableDetectionForNextPlateTap() {
        TAP_DEBUG("reEnableDetectionForNextPlateTap", "Scheduling re-enable after cooldown=\(tapCooldown)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + tapCooldown) { [weak self] in
            guard let self = self else { return }
            let currentLevel = self.fftAnalyzer.inputLevelDB
            let fallingThreshold = self.tapDetectionThreshold - self.hysteresisMargin
            self.isAboveThreshold = currentLevel > fallingThreshold
            self.isDetecting = true
            self.tapDetected = false
            TAP_DEBUG("reEnableDetectionForNextPlateTap", "Re-enabled | currentLevel=\(String(format: "%.2f", currentLevel)) fallingThreshold=\(String(format: "%.2f", fallingThreshold)) isAboveThreshold=\(self.isAboveThreshold) isDetecting=\(self.isDetecting)")
            // Do NOT reset analyzerStartTime here — that would restart warmup and
            // destabilise isAboveThreshold via the justExitedWarmup sync path.
        }
    }
    
    /// Merges the longitudinal, cross-grain, and (if available) FLC peak
    /// arrays for combined display in plate mode.
    ///
    /// Cross and FLC peaks are deduplicated against previously added peaks
    /// using a 5 Hz frequency tolerance, **except** that the auto-selected
    /// peak from each phase is always included regardless of proximity to
    /// another peak.
    ///
    /// - Returns: The merged peak array sorted by frequency (ascending).
    func combinePlatePeaks() -> [ResonantPeak] {
        var combined: [ResonantPeak] = []
        
        // Add longitudinal peaks (these will show as "L" in the UI)
        combined.append(contentsOf: longitudinalPeaks)
        
        // Add cross-grain peaks, avoiding duplicates within frequency tolerance.
        // Always include the auto-selected cross peak even if it's close to an L peak.
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

