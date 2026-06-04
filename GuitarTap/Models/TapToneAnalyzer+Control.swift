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
        gtLog("🎬 Analyzer started - warm-up period: \(warmupPeriod)s")

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
            self.tapEntries          = []
            self.showingMultiTapComparison = false
            self.captureTimer?.invalidate()
            self.captureTimer        = nil
            // Always start fresh so the first new tap is detected on a rising edge.
            self.isAboveThreshold    = false
            self.analyzerStartTime   = Date()  // Reset warm-up timer.

            self.resetDecayTracking()

            // Clear frozen spectrum data (atomic — prevents transient length mismatch).
            self.setFrozenSpectrum(frequencies: [], magnitudes: [])
            self.isMeasurementComplete = false

            // Clear annotation label offsets.
            self.peakAnnotationOffsets = [:]

            // Cancel any in-flight gated capture (must be explicit since
            // resetMaterialPhaseState no longer clears gated state).
            self.gatedCaptureActive = false
            self.mpmLock.lock()
            self.gatedAccumBuffer = []
            self.mpmLock.unlock()

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
    /// - Parameter skipWarmup: When `true`, sets `analyzerStartTime` far enough in the past
    ///   that the 0.5 s warm-up period has already elapsed when the first audio buffer arrives.
    ///   Use this for file-playback mode where the audio source is deterministic and the tap
    ///   transient may occur within the first half-second of the recording.
    func startTapSequence(skipWarmup: Bool = false, initialPhase: MaterialTapPhase? = nil) {
        let measurementType = TapDisplaySettings.measurementType
        let isPlateMode = measurementType == .plate
        let isBraceMode = measurementType == .brace
        gtLog("🎬 Starting tap sequence: \(numberOfTaps) tap(s), plate mode: \(isPlateMode), brace mode: \(isBraceMode), skipWarmup: \(skipWarmup)")

        // CRITICAL: Apply all state that detectTap() reads on the audio thread
        // synchronously — before any audio buffers from a just-started file or engine
        // can arrive and be evaluated.  The full housekeeping (clearing peaks, status
        // messages, etc.) runs in the main.async block below, but these must be
        // visible to the audio thread immediately:
        //   • isMeasurementComplete = false — allows detectTap's peak-analysis path
        //   • isDetecting = true            — allows detectTap to run
        //   • analyzerStartTime             — controls the warm-up gate
        //   • isAboveThreshold               — false for live (first tap = rising edge),
        //                                     true for file playback (require falling
        //                                     edge first so opening decay doesn't
        //                                     trigger a false first tap)
        //   • justExitedWarmup = false       — will be set true as warm-up ends
        //   • gatedCaptureActive / preRollBuffer — clean capture state
        // All are @Published / @MainActor-safe to write from the main thread.
        // This call is always made on the main thread (from openAudioFile or the
        // Start button handler), so no dispatch is needed here.
        isMeasurementComplete = false
        // Clear any frozen spectrum BEFORE setting isDetecting = true.
        // If we set isDetecting first and the audio thread fires a tap immediately
        // (file playback case), setFrozenSpectrum() inside the main.async block below
        // would wipe the just-captured gated-FFT result.
        setFrozenSpectrum(frequencies: [], magnitudes: [])

        // Cancel any in-flight gated capture from a previous sequence and
        // reset the pre-roll BEFORE arming the crossing handler (isDetecting = true).
        // This must be synchronous so the crossing handler starts with clean
        // state — if deferred to the async block, the handler may start a
        // capture that the async block then kills.
        //
        // Start with an empty pre-roll buffer.  The ring buffer fills naturally
        // as audio chunks arrive via accumulateGatedSamples.  If a tap fires
        // before the buffer is full, startGatedCapture seeds the accumulator
        // with only the samples received so far — no zero-padding.  This avoids
        // diluting the captured signal with silence, which would suppress the
        // spectral magnitude (the old zero-fill caused a ~7 dB live-capture
        // deficit and ~23 dB file-playback deficit vs Python).
        gatedCaptureActive = false
        mpmLock.lock()
        gatedAccumBuffer = []
        preRollBuffer = []
        // Session recording: clear the buffer and begin recording.
        // The buffer accumulates raw audio while detection is active,
        // producing a single WAV per measurement for replay.
        sessionRecordingBuffer = []
        // Seed with checkpoint 0 so the first phase has a truncation
        // anchor — without it, redoing the first phase (or the same
        // phase repeatedly) would leave the rejected tap's audio in
        // the saved WAV.  See acceptCurrentPhase / redoCurrentPhase.
        sessionCheckpoints = [0]
        isSessionRecording = true
        sessionRecordingSampleRate = mpmSampleRate > 0 ? mpmSampleRate : 48000
        mpmLock.unlock()

        // Reset the threshold-crossing state BEFORE arming detection.
        // If deferred to the main.async block, the level-crossing handler on
        // the audio queue can fire between isDetecting = true and the async
        // block running — starting an orphaned gated capture that consumes
        // samples meant for the real first tap.
        //
        // For file playback (skipWarmup): start with isAboveThreshold = true so
        // the detector requires a falling edge (signal drops below threshold)
        // before any rising edge can fire.  This prevents the file's opening
        // audio — which may be mid-decay from a prior tap and already above
        // threshold — from immediately triggering a false first tap that
        // captures garbage.  The decay will naturally fall below threshold,
        // then the real first tap attack will produce the genuine rising edge.
        isAboveThreshold = skipWarmup
        justExitedWarmup = false

        // Reset the material phase BEFORE arming the level crossing.
        // The audio-queue crossing handler checks materialTapPhase.isCapturing
        // and skips if the phase is still reviewingLongitudinal (left over from
        // a previous tap sequence).  If deferred to the main.async block below,
        // the first file chunk can cross the threshold before the reset runs,
        // causing the crossing to be skipped and the handler permanently
        // disarmed for the rest of playback.
        //
        // When initialPhase is provided (phase-targeted file playback tests),
        // use that phase instead of .capturingLongitudinal so the level-crossing
        // handler and gated capture route to the correct phase handler.
        if isPlateMode || isBraceMode {
            materialTapPhase = initialPhase ?? .capturingLongitudinal
        }

        isDetecting = true
        analyzerStartTime = skipWarmup
            ? Date().addingTimeInterval(-(warmupPeriod + 0.1))
            : Date()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Starting a new tap always clears any active comparison overlay.
            self.comparisonSpectra = []
            self.displayMode = .live
            self.loadedMeasurementName = nil
            self.sourceMeasurementTimestamp = nil
            // Also clear the played-file name so the chart title reverts to "New"
            // when the user starts a fresh tap sequence (e.g. by changing
            // measurement type across the guitar/material boundary).  Without
            // this, chartTitle — computed as
            //   fft.playingFileName ?? tap.loadedMeasurementName ?? "New"
            // — keeps showing the previously-played filename even though the
            // new sequence is unrelated to that file.  For the file-playback
            // path (startFromFile) this is harmless because the playback
            // setup re-assigns playingFileName immediately after
            // startTapSequence returns.
            self.fftAnalyzer.playingFileName = nil
            self.isMeasurementComplete = false
            // Clear the loaded-settings warning — the user is explicitly starting a new
            // sequence so the loaded threshold/tap-count are now their chosen settings.
            self.showLoadedSettingsWarning = false

            // Clear multi-tap comparison state so the toggle resets for the new sequence.
            self.tapEntries = []
            self.showingMultiTapComparison = false

            // Clear per-sequence accumulated data.
            self.capturedTaps        = []
            self.currentTapCount     = 0
            self.tapProgress         = 0.0
            self.tapDetected         = false
            self.isDetectionPaused   = false

            // gatedCaptureActive, gatedAccumBuffer, isAboveThreshold, and
            // justExitedWarmup were cleared, and preRollBuffer was pre-filled
            // with silence, synchronously before isDetecting = true (see above)
            // so the audio-queue crossing handler starts with clean state, a
            // full pre-roll window, and no stale threshold-crossing flag.

            // Seed the noise-floor estimate so the first relative-threshold
            // calculation has a reasonable baseline.
            // For file playback (skipWarmup), use -100 dB (silence) so the
            // file's audio — even a quiet ring-out — will cross the rising
            // threshold.  Mic ambient noise must not influence file playback.
            // For live mic, seed from the current ambient level.
            self.noiseFloorEstimate = skipWarmup ? -100.0 : self.fftAnalyzer.inputLevelDB

            self.currentDecayTime    = nil
            self.peakMagnitudeHistory = []
            self.resetDecayTracking()

            // Initialise plate/brace phase state.
            // When initialPhase is provided (phase-targeted file playback tests),
            // use that phase so the async housekeeping doesn't clobber the override.
            let newPhase: MaterialTapPhase
            if isPlateMode || isBraceMode {
                newPhase = initialPhase ?? .capturingLongitudinal
            } else {
                newPhase = .notStarted
            }
            self.resetMaterialPhaseState(to: newPhase)

            // isAboveThreshold, justExitedWarmup, analyzerStartTime, isDetecting, and
            // isMeasurementComplete are all set synchronously before this block was
            // enqueued — see the comment above the DispatchQueue.main.async call.
            // setFrozenSpectrum was also called synchronously to prevent this block from
            // wiping a gated-FFT result captured between the sync section and here.
            // Do not re-assign isDetecting here: handleTapDetection may have set it false
            // between the sync arming above and this block running, and overwriting that
            // leaves the analyzer stuck in "detecting" after the measurement completes.

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
        isSessionRecording = false  // Stop accumulating audio during pause
        statusMessage    = "Detection paused – tap freely, then resume"
        gtLog("⏸️ Tap detection paused at \(currentTapCount)/\(numberOfTaps)")
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

        isSessionRecording = true  // Resume accumulating audio after pause
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
        gtLog("▶️ Tap detection resumed at \(currentTapCount)/\(numberOfTaps)")
    }

    // MARK: - Cancel

    /// Cancels the current tap sequence and stops detection.
    ///
    /// All per-sequence data (captured taps, phase spectra, peaks) is cleared and the
    /// spectrum is unfrozen.  Detection is stopped — the user presses New Tap to begin
    /// a new sequence, allowing them to adjust settings first.
    func cancelTapSequence() {
        gtLog("❌ Tap sequence cancelled")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.capturedTaps        = []
            self.tapEntries          = []
            self.showingMultiTapComparison = false
            self.currentTapCount     = 0
            self.tapProgress         = 0.0
            self.tapDetected         = false
            self.isDetectionPaused   = false
            self.isDetecting         = false
            // Mark as complete so New Tap is re-enabled after cancel.
            self.isMeasurementComplete = true

            // Cancel any in-flight gated capture (must be explicit since
            // resetMaterialPhaseState no longer clears gated state).
            self.gatedCaptureActive = false
            self.mpmLock.lock()
            self.gatedAccumBuffer = []
            // Session recording: discard the buffer on cancel.
            self.isSessionRecording = false
            self.sessionRecordingBuffer = []
            self.sessionCheckpoints = []
            self.mpmLock.unlock()

            self.resetMaterialPhaseState(to: .notStarted)
            self.resetDecayTracking()

            // Clear frozen spectrum data (atomic — prevents transient length mismatch).
            self.setFrozenSpectrum(frequencies: [], magnitudes: [])

            self.analyzerStartTime = Date()
            self.isAboveThreshold  = false

            self.captureTimer?.invalidate()
            self.captureTimer = nil

            self.statusMessage = "Cancelled — press New Tap to start again"
        }
    }

    // MARK: - Phase Review (Accept / Redo)

    /// Accepts the current review-phase spectrum and advances to the next capture phase.
    ///
    /// Called when the user taps "Accept" (the repurposed Pause button) during a
    /// `reviewingLongitudinal`, `reviewingCross`, or `reviewingFlc` state.
    ///
    /// - For `reviewingLongitudinal`: unfreezes the spectrum and transitions to `.capturingCross`.
    /// - For `reviewingCross`: transitions to `.waitingForFlcTap` (FLC enabled) or `.complete`.
    /// - For `reviewingFlc`: marks the measurement complete.
    func acceptCurrentPhase() {
        // Session recording: checkpoint the current buffer position so that
        // if a subsequent phase is redone, we can truncate back to here.
        mpmLock.lock()
        sessionCheckpoints.append(sessionRecordingBuffer.count)
        mpmLock.unlock()

        let measureFlc = TapDisplaySettings.measureFlc
        switch materialTapPhase {
        case .reviewingLongitudinal:
            gtLog("✅ Accepted L tap — advancing to cross-grain")
            materialTapPhase = .capturingCross
            setFrozenSpectrum(frequencies: [], magnitudes: [])
            isAboveThreshold = fftAnalyzer.inputLevelDB > (tapDetectionThreshold - hysteresisMargin)
            analyzerStartTime = Date()
            isDetecting = true
            tapDetected = false
            statusMessage = "Rotate 90° and tap for C"

        case .reviewingCross:
            if measureFlc {
                gtLog("✅ Accepted C tap — advancing to FLC")
                materialTapPhase = .waitingForFlcTap
                statusMessage = "Set up for FLC tap, then tap"
                // Re-enable detection for the FLC phase after the cooldown.
                DispatchQueue.main.asyncAfter(deadline: .now() + tapCooldown) { [weak self] in
                    guard let self = self else { return }
                    self.materialTapPhase = .capturingFlc
                    self.setFrozenSpectrum(frequencies: [], magnitudes: [])
                    self.isAboveThreshold = self.fftAnalyzer.inputLevelDB > (self.tapDetectionThreshold - self.hysteresisMargin)
                    self.analyzerStartTime = Date()
                    self.isDetecting = true
                    self.tapDetected = false
                }
            } else {
                gtLog("✅ Accepted C tap — measurement complete")
                finalisePlateNoFLC()
            }

        case .reviewingFlc:
            gtLog("✅ Accepted FLC tap — measurement complete")
            finalisePlateWithFLC()

        default:
            gtLog("⚠️ acceptCurrentPhase called in unexpected phase: \(materialTapPhase)")
        }
    }

    // MARK: - Plate Completion Helpers

    /// Finalises a two-tap plate measurement (L + C, no FLC).
    ///
    /// Resolves the displayed peak selection, freezes the spectrum, marks
    /// the phase complete, writes the session WAV, and sets the completion
    /// status message.  Called from both the user-Accept path
    /// (``acceptCurrentPhase`` on `.reviewingCross`) and the file-playback
    /// auto-complete path (``handleCrossGatedProgress`` when `measureFlc`
    /// is `false`).  Mirrors Python `_finalise_plate_no_flc()`.
    func finalisePlateNoFLC() {
        let sel = resolvedPlatePeaks(crossOverride: selectedCrossPeak ?? crossPeaks.first)
        currentPeaks = sel
        selectedPeakIDs = Set(sel.map { $0.id })
        setFrozenSpectrum(frequencies: [], magnitudes: [])
        materialTapPhase = .complete
        isMeasurementComplete = true
        finishSessionRecording(label: "Plate_LC")
        tapProgress = 1.0
        let fLStr = selectedLongitudinalPeak.map { String(format: "%.1f", $0.frequency) } ?? "?"
        let fCStr = selectedCrossPeak.map { String(format: "%.1f", $0.frequency) } ?? "?"
        statusMessage = "Complete — fL: \(fLStr) Hz, fC: \(fCStr) Hz"
    }

    /// Finalises a three-tap plate measurement (L + C + FLC).
    ///
    /// Resolves the displayed peak selection, freezes the spectrum, marks
    /// the phase complete, writes the session WAV, and sets the completion
    /// status message.  Called from both the user-Accept path
    /// (``acceptCurrentPhase`` on `.reviewingFlc`) and the file-playback
    /// auto-complete path (``handleFlcGatedProgress``).  Mirrors Python
    /// `_finalise_plate_with_flc()`.
    func finalisePlateWithFLC() {
        let sel = resolvedPlatePeaks(includeCross: true, includeFlc: true, flcOverride: selectedFlcPeak ?? flcPeaks.first)
        currentPeaks = sel
        selectedPeakIDs = Set(sel.map { $0.id })
        setFrozenSpectrum(frequencies: [], magnitudes: [])
        materialTapPhase = .complete
        isMeasurementComplete = true
        finishSessionRecording(label: "Plate_LCF")
        tapProgress = 1.0
        statusMessage = "Complete - check Results"
    }

    /// Clears the current phase's captured data and restarts detection for that phase.
    ///
    /// Called when the user taps "Redo" (the repurposed Cancel button) during a
    /// `reviewingLongitudinal`, `reviewingCross`, or `reviewingFlc` state.
    /// Only the data for the current phase is cleared — earlier phases are preserved.
    func redoCurrentPhase() {
        // Session recording: truncate back to the start of the current
        // phase so the rejected tap's audio is excluded from the saved WAV.
        // Peek (don't pop) — the anchor must remain in place so that a
        // second redo of the same phase truncates to the same position,
        // not to the start of the *previous* accepted phase.
        mpmLock.lock()
        if let phaseStart = sessionCheckpoints.last,
           sessionRecordingBuffer.count > phaseStart {
            sessionRecordingBuffer.removeSubrange(phaseStart...)
        }
        mpmLock.unlock()

        switch materialTapPhase {
        case .reviewingLongitudinal:
            gtLog("🔄 Redo L phase — clearing longitudinal data")
            longitudinalSpectrum = nil
            longitudinalPeaks = []
            autoSelectedLongitudinalPeakID = nil
            selectedLongitudinalPeak = nil
            userSelectedLongitudinalPeakID = nil
            materialCapturedTaps = []
            currentTapCount = 0
            tapProgress = 0.0
            materialTapPhase = .capturingLongitudinal
            setFrozenSpectrum(frequencies: [], magnitudes: [])
            isAboveThreshold = fftAnalyzer.inputLevelDB > (tapDetectionThreshold - hysteresisMargin)
            analyzerStartTime = Date()
            isDetecting = true
            tapDetected = false
            statusMessage = "Ready for L tap — tap again"

        case .reviewingCross:
            gtLog("🔄 Redo C phase — clearing cross-grain data")
            crossSpectrum = nil
            crossPeaks = []
            autoSelectedCrossPeakID = nil
            selectedCrossPeak = nil
            userSelectedCrossPeakID = nil
            materialCapturedTaps = []
            let lCount = (longitudinalSpectrum != nil) ? numberOfTaps : 0
            currentTapCount = lCount
            tapProgress = Float(lCount) / Float(totalPlateTaps)
            materialTapPhase = .capturingCross
            setFrozenSpectrum(frequencies: [], magnitudes: [])
            isAboveThreshold = fftAnalyzer.inputLevelDB > (tapDetectionThreshold - hysteresisMargin)
            analyzerStartTime = Date()
            isDetecting = true
            tapDetected = false
            statusMessage = "Ready for C tap — tap again"

        case .reviewingFlc:
            gtLog("🔄 Redo FLC phase — clearing FLC data")
            flcSpectrum = nil
            flcPeaks = []
            autoSelectedFlcPeakID = nil
            selectedFlcPeak = nil
            userSelectedFlcPeakID = nil
            materialCapturedTaps = []
            let lcCount = (longitudinalSpectrum != nil && crossSpectrum != nil) ? numberOfTaps * 2 : 0
            currentTapCount = lcCount
            tapProgress = Float(lcCount) / Float(totalPlateTaps)
            materialTapPhase = .capturingFlc
            setFrozenSpectrum(frequencies: [], magnitudes: [])
            isAboveThreshold = fftAnalyzer.inputLevelDB > (tapDetectionThreshold - hysteresisMargin)
            analyzerStartTime = Date()
            isDetecting = true
            tapDetected = false
            statusMessage = "Ready for FLC tap — tap again"

        default:
            gtLog("⚠️ redoCurrentPhase called in unexpected phase: \(materialTapPhase)")
        }
    }

    // MARK: - Private Helpers

    /// Clears all plate/brace phase state and sets ``materialTapPhase`` to the given value.
    ///
    /// Call with `.notStarted` from ``reset()`` and with `.capturingLongitudinal` from
    /// ``startTapSequence()`` / ``cancelTapSequence()`` when in plate or brace mode.
    ///
    /// **Does NOT clear gated capture state** (`gatedCaptureActive`, `gatedAccumBuffer`,
    /// `preRollBuffer`).  Callers that need to cancel an in-flight capture must do so
    /// explicitly — and crucially, they must do it *synchronously* before arming detection
    /// (`isDetecting = true`).  If the clear were here (deferred inside a `main.async`
    /// block), the audio-queue level-crossing handler could start a legitimate gated
    /// capture between the sync and async sections, and this method would then kill it.
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
    }

    /// Stops any active decay tracking and clears the associated timer.
    private func resetDecayTracking() {
        isTrackingDecay = false
        decayTrackingTimer?.invalidate()
        decayTrackingTimer = nil
    }
}
