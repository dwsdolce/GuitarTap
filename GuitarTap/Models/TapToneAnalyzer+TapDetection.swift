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
/// For guitar measurements the per-chunk RMS `inputLevelDB` is compared
/// against two absolute dB thresholds:
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
/// Within the `detectTap` method, relative thresholds are derived from a
/// running noise floor EMA (α = 0.05, τ ≈ 190 ms at ~43 Hz):
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
/// notStarted → capturingLongitudinal → reviewingLongitudinal
///           → capturingCross → reviewingCross → [waitingForFlcTap → capturingFlc → reviewingFlc →] complete
/// ```
///
/// Each phase uses a dedicated gated-FFT handler in `TapToneAnalyzer+SpectrumCapture`
/// (`handleLongitudinalGatedProgress`, `handleCrossGatedProgress`,
/// `handleFlcGatedProgress`) that captures a fresh short-window FFT from raw
/// PCM rather than the long-window continuous FFT.

import SwiftUI
import Combine

extension TapToneAnalyzer {

    // MARK: - FFT-Frame Entry Point

    /// Receives one full FFT frame (~2.7 Hz) and routes it to peak analysis.
    ///
    /// Called from the `$magnitudes` Combine sink in
    /// ``setupSubscriptions()``.  Mirrors Python `on_fft_frame` in
    /// `tap_tone_analyzer_tap_detection.py` so the FFT-frame entry point
    /// lives in matching files between the two ports.  The peak-analysis
    /// implementation itself remains in ``analyzeMagnitudes(_:frequencies:peakMagnitude:)``
    /// in `+PeakAnalysis.swift`, parallel to Python's `analyze_magnitudes`
    /// in `tap_tone_analyzer_peak_analysis.py`.
    ///
    /// Tap detection is no longer driven from this slow FFT-rate path — see
    /// ``onRmsLevelChanged(_:)`` for the per-chunk RMS-driven detector.
    ///
    /// NOTE: `peakMagnitude` here is a GENUINE FFT peak-bin magnitude — unlike `detectTap(level:)`,
    /// which takes the per-chunk RMS level. The two are different quantities; do not conflate them.
    func onFftFrame(magnitudes: [Float], frequencies: [Float], peakMagnitude: Float) {
        analyzeMagnitudes(magnitudes, frequencies: frequencies, peakMagnitude: peakMagnitude)
    }

    // MARK: - RMS-Level Entry Point

    /// Receives the per-chunk RMS input level (~43 Hz) and runs the rising-edge
    /// tap detector for whichever measurement type is currently active.
    ///
    /// Called from the `$inputLevelDB` Combine sink in ``setupSubscriptions()``.
    /// Mirrors Python `_on_rms_level_changed` in
    /// `tap_tone_analyzer_tap_detection.py`.  The guards (isDetecting /
    /// isDetectionPaused / isMeasurementComplete) live here in the handler, not
    /// inline at the sink, so the file-level placement matches Python.
    ///
    /// Guitar mode previously detected from the FFT-rate path
    /// (`analyzeMagnitudes`); now all modes detect from this finer-resolution
    /// RMS path.  The captured spectrum for guitar is then assembled via
    /// ``startGuitarGatedCapture()``.
    func onRmsLevelChanged(_ levelDB: Float, audioTime: Double) {
        if fftAnalyzer.isPlayingFile {
            TAP_DEBUG("onRmsLevel", "FILE | levelDB=\(String(format: "%.2f", levelDB)) isDetecting=\(isDetecting) isPaused=\(isDetectionPaused) isComplete=\(isMeasurementComplete)")
        }
        guard isDetecting && !isDetectionPaused && !isMeasurementComplete else {
            return
        }
        detectTap(level: levelDB,
                  audioTime: audioTime,
                  magnitudes: fftAnalyzer.magnitudes,
                  frequencies: fftAnalyzer.frequencies)
    }

    // MARK: - Tap Detection

    /// Evaluates the current signal level against the active detection threshold
    /// and fires a tap event on a rising edge.
    ///
    /// Called from ``onRmsLevelChanged(_:)`` for all modes at ~43 Hz
    /// (per-chunk RMS input level).
    ///
    /// - Parameters:
    ///   - level: Current RMS input level in dBFS used for threshold
    ///     comparison (`fftAnalyzer.inputLevelDB`, sampled per audio chunk at
    ///     ~43 Hz).
    ///
    ///     This was previously named `peakMagnitude`, which was wrong and actively misleading: it is
    ///     the broadband **RMS chunk level**, never an FFT peak-bin magnitude. (A genuine FFT peak does
    ///     exist — `onFftFrame(magnitudes:frequencies:peakMagnitude:)` — but it drives peak *analysis*,
    ///     not tap detection.) The old name cost real time during the OUT-4 investigation: it looked as
    ///     though Swift and the web were detecting on entirely different signals. They are not — all
    ///     three platforms detect on the per-chunk RMS level.
    ///   - magnitudes: Current FFT magnitude spectrum (passed through to
    ///     ``handleTapDetection(magnitudes:frequencies:time:)`` for spectrum
    ///     capture on a confirmed tap).
    ///   - frequencies: Frequency axis matching `magnitudes`, in Hz.
    func detectTap(level: Float, audioTime: Double, magnitudes: [Float], frequencies: [Float]) {
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
            noiseFloorEstimate = noiseFloorAlpha * level + (1 - noiseFloorAlpha) * noiseFloorEstimate
        }

        // Compute effective thresholds.
        // Guitar mode:          absolute threshold (original behaviour).
        // Plate/brace mode:     noise floor + headroom derived from the threshold slider.
        //                       The slider value is absolute dB (-80…-20); we use it as
        //                       the target "tap above noise floor" margin by computing
        //                       headroom = tapDetectionThreshold - noiseFloorEstimate,
        //                       clamped to at least 6 dB so there is always a gap to cross.
        //
        // NOTE: Per-chunk TAP_DEBUG log lines restored for file playback only
        // to diagnose intermittent gated-capture failures.
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
            if fftAnalyzer.isPlayingFile {
                TAP_DEBUG("detectTap", "FILE_CHUNK | peakMag=\(String(format: "%.2f", level)) noiseFloor=\(String(format: "%.2f", noiseFloorEstimate)) headroom=\(String(format: "%.1f", headroom)) risingThresh=\(String(format: "%.2f", effectiveRisingThreshold)) isAbove=\(isAboveThreshold)")
            }
        } else {
            effectiveRisingThreshold  = tapDetectionThreshold
            effectiveFallingThreshold = tapDetectionThreshold - hysteresisMargin
            if fftAnalyzer.isPlayingFile {
                TAP_DEBUG("detectTap", "FILE_CHUNK | peakMag=\(String(format: "%.2f", level)) absThresh=\(String(format: "%.2f", effectiveRisingThreshold)) isAbove=\(isAboveThreshold)")
            }
        }

        // Check if we're still in warm-up period (prevents false detections on startup).
        // The warm-up is SILENT: it suppresses detection but never writes statusMessage, so
        // the prompt set at the transition (arm / accept / redo / resume) survives — mirrors
        // the web's counter-based warm-up. (Was: overwrote the status with "Initializing…".)
        if let t0 = warmupStartAudioTime, audioTime - t0 < warmupPeriod {
            tapDetected = false
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
                noiseFloorEstimate = level
                // Recompute rising threshold with the corrected noise floor.
                let h = max(tapDetectionThreshold - noiseFloorEstimate, 10.0)
                let risingAnchored = noiseFloorEstimate + h
                isAboveThreshold = level > risingAnchored
                TAP_DEBUG("detectTap", "WARMUP EXIT (relative) | peakMag=\(String(format: "%.2f", level)) noiseFloorAnchored=\(String(format: "%.2f", noiseFloorEstimate)) risingAnchored=\(String(format: "%.2f", risingAnchored)) isAboveThreshold=\(isAboveThreshold)")
            } else {
                isAboveThreshold = level > effectiveRisingThreshold
                TAP_DEBUG("detectTap", "WARMUP EXIT (absolute) | peakMag=\(String(format: "%.2f", level)) risingThresh=\(String(format: "%.2f", effectiveRisingThreshold)) isAboveThreshold=\(isAboveThreshold)")
            }
            // Don't detect on this frame - just sync the state.  (The noise-floor
            // re-anchor above stays; only the status write is gone — the warm-up is silent.)
            tapDetected = false
            return
        }

        // Check cooldown
        if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) < tapCooldown {
            let cooldownRemaining = tapCooldown - now.timeIntervalSince(lastTap)
            // Edge-triggered: log only the FIRST chunk in the cooldown window,
            // not every chunk for the full 0.5 s.  ~43 Hz × 0.5 s = ~22 redundant
            // lines per cooldown otherwise.  Mirrors Python.
            if !cooldownLogged {
                TAP_DEBUG("detectTap", "COOLDOWN active | remaining=\(String(format: "%.3f", cooldownRemaining))s peakMag=\(String(format: "%.2f", level))")
                cooldownLogged = true
            }
            tapDetected = false
            return
        } else {
            cooldownLogged = false
        }

        // Update the detection level for UI display
        tapDetectionLevel = effectiveRisingThreshold

        // Hysteresis: Use different thresholds for rising vs falling edges.
        // Rising edge ALSO requires N consecutive chunks above the rising
        // threshold to confirm — mirrors the audio-queue level crossing
        // detector in RealtimeFFTAnalyzer.  Without confirmation here,
        // a brief noise bump that the audio-queue rejected can still
        // fire the main-thread rising-edge detector and start a bogus
        // gated capture (see test failure on plate-umik-1-swift-mac-1778816330
        // where the FLC bump at -46.8 dB was rejected by the audio queue
        // but caught here, capturing 26.4 Hz @ -78.9 dB instead of the
        // real 35.4 Hz FLC tap that arrived a few seconds later).
        let risingThreshold  = effectiveRisingThreshold
        let fallingThreshold = effectiveFallingThreshold
        let confirmTarget = RealtimeFFTAnalyzer.levelCrossingConfirmationChunks

        if isAboveThreshold {
            // Currently latched above — apply falling-threshold hysteresis.
            if level <= fallingThreshold {
                // Falling edge.
                if currentTapCount > 0 && currentTapCount < numberOfTaps {
                    TAP_DEBUG("detectTap", "SIGNAL SETTLED | tap \(currentTapCount)/\(numberOfTaps) — signal dropped below falling threshold")
                    statusMessage = guitarLoopStatus(capturing: false)
                }
                TAP_DEBUG("detectTap", "FALLING EDGE | peakMag=\(String(format: "%.2f", level)) fallingThresh=\(String(format: "%.2f", fallingThreshold)) — signal settled, ready for next tap")
                isAboveThreshold = false
                detectTapConsecutiveAbove = 0
            }
            tapDetected = false
        } else {
            // Currently latched below — apply rising-threshold gate with
            // N-chunk confirmation.
            if level > risingThreshold {
                detectTapConsecutiveAbove += 1
                if detectTapConsecutiveAbove >= confirmTarget {
                    // Confirmed rising edge — fire the tap-detection event.
                    TAP_DEBUG("detectTap", "RISING EDGE FIRED | peakMag=\(String(format: "%.2f", level)) risingThresh=\(String(format: "%.2f", risingThreshold)) tapCount=\(currentTapCount+1)/\(numberOfTaps) confirmedBy=\(confirmTarget)")
                    isAboveThreshold = true
                    detectTapConsecutiveAbove = 0
                    tapDetected = true
                    lastTapTime = now

                    // Capture the recent peak input level for decay tracking reference.
                    // Use recentPeakLevelDB, which holds the max level over the last
                    // `fftAnalyzer.peakHoldDuration` (2.0 s). This ensures we get the actual tap peak
                    // even though FFT detection is delayed.
                    tapPeakLevel = fftAnalyzer.recentPeakLevelDB

                    // Handle tap in multi-tap sequence
                    handleTapDetection(magnitudes: magnitudes, frequencies: frequencies, time: now, audioTime: audioTime)
                } else {
                    // Pending — waiting for more above-threshold chunks.
                    if fftAnalyzer.isPlayingFile && detectTapConsecutiveAbove == 1 {
                        TAP_DEBUG("detectTap", "RISING EDGE PENDING | peakMag=\(String(format: "%.2f", level)) risingThresh=\(String(format: "%.2f", risingThreshold)) need=\(confirmTarget - 1) more")
                    }
                    tapDetected = false
                }
            } else {
                // Below rising threshold.
                if detectTapConsecutiveAbove > 0 && fftAnalyzer.isPlayingFile {
                    TAP_DEBUG("detectTap", "RISING EDGE CANCELED | peakMag=\(String(format: "%.2f", level)) (signal fell below after \(detectTapConsecutiveAbove)/\(confirmTarget) chunks)")
                }
                detectTapConsecutiveAbove = 0
                tapDetected = false
            }
        }
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
    ///   - time: Wall-clock timestamp of the rising-edge tap detection event.
    ///   - audioTime: Audio-clock time (seconds since engine start) of the same event, used to
    ///     seed ring-out decay tracking so it is measured in audio time (load-invariant).
    func handleTapDetection(magnitudes: [Float], frequencies: [Float], time: Date, audioTime: Double) {
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
        
        // Guitar mode — start a gated raw-PCM capture aligned to the tap onset.
        // Detection now runs on the fast RMS path (~43 Hz); the captured window
        // is one full fftSize buffer that begins ~pre-roll milliseconds before
        // the trigger.  The FFT is computed in finishGuitarGatedCapture once
        // the window fills, then appended to capturedTaps.  This eliminates the
        // tap-position-within-FFT-frame variability that the legacy path had.
        TAP_DEBUG("handleTapDetection", "GUITAR — starting gated capture | capturedTaps=\(capturedTaps.count)/\(numberOfTaps)")

        // Start decay tracking immediately (uses RMS level, independent of FFT capture).
        startDecayTracking(tapAudioTime: audioTime)

        // Provisional status update — final status is emitted after the gated
        // capture completes and capturedTaps grows.  (currentTapCount == capturedTaps.count
        // here, so guitarLoopStatus's provisional +1 == the old capturedTaps.count + 1.)
        statusMessage = guitarLoopStatus(capturing: true)

        // Open the guitar gated capture.  accumulateGatedSamples will fill the
        // accumulator over the next fftSize samples and dispatch
        // finishGatedFFTCapture(samples:sampleRate:phase:) on the main thread,
        // which routes nil-phase to finishGuitarGatedCapture.
        startGuitarGatedCapture()
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
        case .capturingLongitudinal, .capturingCross,
             .capturingFlc, .waitingForFlcTap:
            TAP_DEBUG("handlePlateTapDetection", "Starting gated capture for phase=\(phase)")
            startGatedCapture(phase: phase)
        case .notStarted, .complete,
             .reviewingLongitudinal, .reviewingCross, .reviewingFlc:
            TAP_DEBUG("handlePlateTapDetection", "UNEXPECTED TAP | phase=\(phase) — tap ignored")
            gtLog("⚠️ Unexpected tap in plate phase: \(phase)")
        }
    }
    
    /// Re-enables tap detection after a brief cooldown, used between
    /// consecutive taps within the same plate/brace capture phase.
    ///
    /// Waits `tapCooldown` seconds, then checks the current input level
    /// to seed `isAboveThreshold` correctly so the hysteresis logic starts
    /// from an accurate state.
    ///
    /// - Important: Does **not** reset `warmupStartAudioTime` — doing so would
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
            // Clear stale fast-start marker so the next tap's main-thread
            // startGatedCapture correctly falls back to pre-roll seeding
            // if the audio-queue level crossing doesn't fire in time.
            self.mpmLock.lock()
            self.lastLevelCrossingCaptureID = -1
            self.mpmLock.unlock()
            TAP_DEBUG("reEnableDetectionForNextPlateTap", "Re-enabled | currentLevel=\(String(format: "%.2f", currentLevel)) fallingThreshold=\(String(format: "%.2f", fallingThreshold)) isAboveThreshold=\(self.isAboveThreshold) isDetecting=\(self.isDetecting)")
            // Do NOT reset warmupStartAudioTime here — that would restart warmup and
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

