//
//  TapToneAnalyzer+Control.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

/// # TapToneAnalyzer+Control
///
/// Start, stop, reset, and sequence-management methods for ``TapToneAnalyzer``.
///
/// ## Auto-Start Logic
///
/// ``start()`` auto-starts a tap sequence only on the **first user-initiated launch** — not
/// on engine restarts triggered by device/route changes.  The guard condition checks that:
/// - no sequence is already active (`!isDetecting`)
/// - no measurement is complete (`!isMeasurementComplete`)
/// - detection is not paused (`!isDetectionPaused`)
/// - no taps have been counted yet (`currentTapCount == 0`)
///
/// Route-change restarts are handled by ``handleRouteChangeRestart()`` in the main file,
/// which preserves in-progress sequences.
///
/// ## Pause vs Cancel
///
/// | Action | Detection | Tap count | Spectrum | Phase |
/// |--------|-----------|-----------|----------|-------|
/// | `pauseTapDetection()` | Off | Preserved | Live | Preserved |
/// | `cancelTapSequence()` | On (restarts) | Reset to 0 | Unfrozen | Reset to start |
/// | `reset()` | Off | Reset to 0 | Unfrozen | Reset to notStarted |
import Foundation

extension TapToneAnalyzer {

    // MARK: - Lifecycle Control

    /// Starts the FFT engine and auto-starts a tap detection sequence when appropriate.
    ///
    /// The auto-start guard ensures `startTapSequence()` fires only on a fresh launch, not
    /// on audio-engine restarts mid-sequence.  The guard is evaluated asynchronously on the
    /// main queue so that any in-flight state changes (e.g. a concurrent pause dispatch)
    /// settle before the decision is made.
    ///
    /// - Throws: Any error propagated from ``RealtimeFFTAnalyzer/start()``, such as
    ///   microphone permission denial or audio session configuration failure.
    func start() throws {
        try fftAnalyzer.start()
        analyzerStartTime = Date()  // Begin the warm-up period for the new session.
        print("🎬 Analyzer started - warm-up period: \(warmupPeriod)s")

        // Evaluate the auto-start guard after pending state changes have settled.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !self.isDetecting && !self.isMeasurementComplete && !self.isDetectionPaused
                && self.currentTapCount == 0 {
                self.startTapSequence()
            }
        }
    }

    /// Stops the FFT engine.
    ///
    /// Does not reset the tap count or clear any captured spectra — call ``reset()`` if a
    /// full state clear is needed.
    func stop() {
        fftAnalyzer.stop()
    }

    /// Resets all analysis state to the initial idle condition.
    ///
    /// Clears peaks, spectra, decay data, plate/brace phase state, annotation offsets, and
    /// any in-flight gated capture.  The spectrum is unfrozen.  All operations are
    /// dispatched to the main queue.
    func reset() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.currentPeaks        = []
            self.identifiedModes     = []
            self.currentDecayTime    = nil
            // Clear the loaded-measurement reference — results are now from a fresh tap.
            self.sourceMeasurementTimestamp = nil
            self.peakMagnitudeHistory = []
            self.lastTapTime         = nil
            self.tapDetected         = false
            // Disable detection until the user starts a new sequence.
            self.isDetecting         = false
            self.currentTapCount     = 0
            self.tapProgress         = 0.0
            self.capturedTaps        = []
            self.tapsForAveraging    = []
            self.captureTimer?.invalidate()
            self.captureTimer        = nil
            // Always start fresh so the first new tap is detected on a rising edge.
            self.isAboveThreshold    = false
            self.analyzerStartTime   = Date()  // Reset warm-up timer.

            self.resetDecayTracking()

            // Clear frozen spectrum data.
            self.frozenFrequencies   = []
            self.frozenMagnitudes    = []
            self.isMeasurementComplete = false

            // Clear annotation label offsets.
            self.peakAnnotationOffsets = [:]

            // Reset all plate/brace phase state (notStarted — no active sequence).
            self.resetMaterialPhaseState(to: .notStarted)

            self.displayMode = .live
            self.loadedMeasurementName = nil
            self.showLoadedSettingsWarning = false
            self.statusMessage = "Tap the guitar to begin"
        }
    }

    // MARK: - Tap Sequence Management

    /// Starts a new tap detection sequence, resetting all per-sequence state.
    ///
    /// For plate and brace modes, transitions ``materialTapPhase`` to
    /// `.capturingLongitudinal` and resets all per-phase spectra and peak selections.
    /// For guitar modes, resets the multi-tap counter and averaged spectra.
    ///
    /// `isAboveThreshold` is always reset to `false` regardless of the current signal level.
    /// The ``warmupPeriod`` then handles any audio transients at the start of the session.
    func startTapSequence() {
        let measurementType = TapDisplaySettings.measurementType
        let isPlateMode = measurementType == .plate
        let isBraceMode = measurementType == .brace
        let currentPeakMagImmediate = fftAnalyzer.peakMagnitude
        print("🎬 Starting tap sequence: \(numberOfTaps) tap(s), plate mode: \(isPlateMode), brace mode: \(isBraceMode)")
        print("🎬 Current FFT peak magnitude (immediate): \(currentPeakMagImmediate) dB, threshold: \(tapDetectionThreshold) dB")
        print("🎬 FFT analyzer running: \(fftAnalyzer.isRunning), frequencies count: \(fftAnalyzer.frequencies.count)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Starting a new tap always clears any active comparison overlay.
            self.comparisonSpectra = []
            self.displayMode = .live
            self.loadedMeasurementName = nil
            self.isMeasurementComplete = false

            // Clear per-sequence accumulated data.
            self.capturedTaps        = []
            self.tapsForAveraging    = []
            self.currentTapCount     = 0
            self.tapProgress         = 0.0
            self.tapDetected         = false
            self.isDetectionPaused   = false
            // Seed the noise-floor estimate from the current ambient level so the first
            // relative-threshold calculation is accurate immediately.
            self.noiseFloorEstimate  = self.fftAnalyzer.inputLevelDB

            self.currentDecayTime    = nil
            self.peakMagnitudeHistory = []
            self.resetDecayTracking()

            // Initialise plate/brace phase state.
            let newPhase: MaterialTapPhase = (isPlateMode || isBraceMode) ? .capturingLongitudinal : .notStarted
            self.resetMaterialPhaseState(to: newPhase)

            // Always start with isAboveThreshold = false so the first real tap produces
            // a genuine rising edge.  The warm-up period suppresses detections for the
            // first 0.5 s; justExitedWarmup then re-anchors the state without firing a tap.
            let currentPeakMag = self.fftAnalyzer.peakMagnitude
            print("🎬 Inside async block - FFT peak magnitude: \(currentPeakMag) dB, threshold: \(self.tapDetectionThreshold) dB")
            print("🎬 FFT analyzer state: running=\(self.fftAnalyzer.isRunning), magnitudes count=\(self.fftAnalyzer.magnitudes.count)")

            self.isAboveThreshold  = false
            self.justExitedWarmup  = false  // Will be set true as warm-up ends.
            print("✅ Starting with isAboveThreshold = false - ready for tap detection after warm-up")

            // Reset the warm-up timer for this new sequence.
            self.analyzerStartTime = Date()

            // Clear frozen spectrum data so the live FFT is shown while waiting for taps.
            self.frozenFrequencies = []
            self.frozenMagnitudes  = []

            self.isDetecting = true

            // Set context-appropriate status message.
            if isBraceMode {
                self.statusMessage = self.numberOfTaps > 1 ? "Ready for fL tap (×\(self.numberOfTaps))" : "Ready for fL tap"
            } else if isPlateMode {
                let measureFlc = TapDisplaySettings.measureFlc
                if self.numberOfTaps > 1 {
                    let phases = measureFlc ? "L, C, FLC" : "L, C"
                    self.statusMessage = "Ready for L tap (×\(self.numberOfTaps) each for \(phases))"
                } else {
                    self.statusMessage = "Ready for L tap"
                }
            } else {
                self.statusMessage = self.numberOfTaps == 1 ? "Tap the guitar..." : "Tap the guitar \(self.numberOfTaps) times..."
            }

            // Clear previous results so the chart shows a clean slate while waiting.
            self.currentPeaks    = []
            self.identifiedModes = []
        }
    }

    // MARK: - Pause / Resume

    /// Pauses tap detection mid-sequence without losing the current tap count.
    ///
    /// The spectrum remains live so the user can experiment with the guitar while paused.
    /// Use ``resumeTapDetection()`` to continue the sequence from where it left off.
    ///
    /// No-op when not currently detecting or already paused.
    func pauseTapDetection() {
        guard isDetecting && !isDetectionPaused else { return }
        isDetecting      = false
        isDetectionPaused = true
        statusMessage    = "Detection paused – tap freely, then resume"
        print("⏸️ Tap detection paused at \(currentTapCount)/\(numberOfTaps)")
    }

    /// Resumes tap detection after a pause, continuing from the current tap count.
    ///
    /// The warm-up timer is reset so the first audio frame after resume does not fire
    /// immediately as a false tap.
    ///
    /// No-op when not paused.
    func resumeTapDetection() {
        guard isDetectionPaused else { return }
        isDetectionPaused = false

        // Reset warm-up to prevent an immediate false trigger on the first frame.
        analyzerStartTime = Date()
        isAboveThreshold  = false

        isDetecting = true

        // Restore a context-appropriate prompt.
        let resumeType = TapDisplaySettings.measurementType
        let isPlateMode = resumeType == .plate
        let isBraceMode = resumeType == .brace
        if isPlateMode || isBraceMode {
            switch materialTapPhase {
            case .capturingLongitudinal:
                statusMessage = isBraceMode ? "Ready for fL tap" : "Ready for L tap"
            case .capturingFlc, .waitingForFlcTap:
                statusMessage = "Ready for FLC tap"
            default:
                statusMessage = "Ready for C tap"
            }
        } else if currentTapCount == 0 {
            statusMessage = numberOfTaps == 1 ? "Tap the guitar..." : "Tap the guitar \(numberOfTaps) times..."
        } else {
            statusMessage = "Tap \(currentTapCount)/\(numberOfTaps) captured. Tap again..."
        }
        print("▶️ Tap detection resumed at \(currentTapCount)/\(numberOfTaps)")
    }

    // MARK: - Cancel

    /// Cancels the current tap sequence and immediately restarts detection from scratch.
    ///
    /// Unlike ``reset()``, cancel keeps detection active so the user can start a new
    /// tap without pressing the Start button again.  All per-sequence data (captured taps,
    /// phase spectra, peaks) is cleared.  The spectrum is unfrozen.
    func cancelTapSequence() {
        print("❌ Tap sequence cancelled")

        let measurementType = TapDisplaySettings.measurementType
        let isPlateMode = measurementType == .plate
        let isBraceMode = measurementType == .brace

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.capturedTaps        = []
            self.tapsForAveraging    = []
            self.currentTapCount     = 0
            self.tapProgress         = 0.0
            self.tapDetected         = false
            self.isDetectionPaused   = false
            self.isDetecting         = true

            // Reset plate/brace state back to the start of the sequence.
            let newPhase: MaterialTapPhase = (isPlateMode || isBraceMode) ? .capturingLongitudinal : .notStarted
            self.resetMaterialPhaseState(to: newPhase)

            self.resetDecayTracking()

            // Clear frozen spectrum data.
            self.frozenFrequencies = []
            self.frozenMagnitudes  = []

            // Reset the warm-up timer for the restarted sequence.
            self.analyzerStartTime = Date()
            self.isAboveThreshold  = false

            self.captureTimer?.invalidate()
            self.captureTimer = nil

            // Show an appropriate ready prompt.
            if isBraceMode {
                self.statusMessage = "Ready for fL tap"
            } else if isPlateMode {
                self.statusMessage = "Ready for L tap"
            } else {
                self.statusMessage = self.numberOfTaps == 1 ? "Tap the guitar..." : "Tap the guitar \(self.numberOfTaps) times..."
            }
        }
    }

    // MARK: - Private Helpers

    /// Clears all plate/brace phase state and sets ``materialTapPhase`` to the given value.
    ///
    /// Call with `.notStarted` from ``reset()`` and with `.capturingLongitudinal` from
    /// ``startTapSequence()`` / ``cancelTapSequence()`` when in plate or brace mode.
    /// Also cancels any in-flight gated FFT capture.
    private func resetMaterialPhaseState(to phase: MaterialTapPhase) {
        materialTapPhase    = phase
        longitudinalSpectrum = nil
        crossSpectrum        = nil
        flcSpectrum          = nil
        longitudinalPeaks    = []
        crossPeaks           = []
        flcPeaks             = []
        autoSelectedLongitudinalPeakID = nil
        autoSelectedCrossPeakID        = nil
        autoSelectedFlcPeakID          = nil
        selectedLongitudinalPeak        = nil
        selectedCrossPeak               = nil
        selectedFlcPeak                 = nil
        userSelectedLongitudinalPeakID  = nil
        userSelectedCrossPeakID         = nil
        userSelectedFlcPeakID           = nil
        materialCapturedTaps            = []
        // Cancel any in-flight gated FFT capture.
        gatedCaptureActive = false
        mpmLock.lock()
        gatedAccumBuffer = []
        mpmLock.unlock()
    }

    /// Stops any active decay tracking and clears the associated timer.
    private func resetDecayTracking() {
        isTrackingDecay = false
        decayTrackingTimer?.invalidate()
        decayTrackingTimer = nil
    }
}
