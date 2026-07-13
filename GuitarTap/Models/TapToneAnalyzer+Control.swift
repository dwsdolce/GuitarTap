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
    func stop() {
        fftAnalyzer.stop()
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
    ///
    ///   Callers key this on the **measurement type**, not on "is this a file":
    ///   - **Guitar** file playback passes `true` — the tap transient may occur within the first
    ///     half-second of an externally recorded file, and guitar detects against the absolute
    ///     threshold, so it never reads the noise floor.
    ///   - **Material** (plate/brace) file playback passes `false` — it is the only mode that uses
    ///     the relative noise-floor detector, and the warm-up is what establishes that floor. Skipping
    ///     it pins `noiseFloorEstimate = -100`, which collapses the relative threshold onto the
    ///     absolute one and silently disables relative detection. Playback must run the LIVE detection
    ///     path or it cannot tell us whether live and playback agree.
    ///
    ///   A saved session WAV always contains its warm-up by construction: `isSessionRecording` is set
    ///   before `analyzerStartTime`, and live suppresses detection during the warm-up, so no accepted
    ///   tap can land in the first 0.5 s. See GuitarTapWeb/Development/OUT-4-DETECTION-SPEC.md.
    /// - Parameter initialPhase: For material (plate/brace) modes, the tap phase to begin
    ///   capturing in; when `nil`, the sequence starts at its first phase.
    // @parity state/tap-tone-analyzer
    func startTapSequence(skipWarmup: Bool = false, initialPhase: MaterialTapPhase? = nil) {
        let measurementType = TapDisplaySettings.measurementType
        let isPlateMode = measurementType == .plate
        let isBraceMode = measurementType == .brace
        gtLog("🎬 Starting tap sequence: \(numberOfTaps) tap(s), plate mode: \(isPlateMode), brace mode: \(isBraceMode), skipWarmup: \(skipWarmup)")

        // This function runs fully synchronously, matching the Python port's
        // `start_tap_sequence`.  All call sites are on the main thread (button
        // actions, settings-apply callbacks, file-playback setup); none of them
        // observe partial state, so there is no need to defer housekeeping to a
        // later main-queue tick.  Eliminating the deferral removes the race
        // class where handleTapDetection on the audio thread set isDetecting
        // false between the sync arming and a deferred re-arming.
        //
        // State that detectTap() reads on the audio thread (isMeasurementComplete,
        // isDetecting, analyzerStartTime, isAboveThreshold, justExitedWarmup,
        // materialTapPhase, noiseFloorEstimate, gatedCaptureActive / preRollBuffer)
        // is set BEFORE `isDetecting = true` so the first audio buffer observed
        // by the crossing handler sees a fully-reset analyzer.

        // ===== UI / per-sequence state (not audio-thread visible) =====
        comparisonSpectra = []
        displayMode = .live
        loadedMeasurementName = nil
        sourceMeasurementTimestamp = nil
        // Clear the played-file name so the chart title reverts to "New" when
        // the user starts a fresh tap sequence (e.g. by changing measurement
        // type across the guitar/material boundary).  Without this, chartTitle
        // — computed as fft.playingFileName ?? tap.loadedMeasurementName ??
        // "New" — keeps showing the previously-played filename even though the
        // new sequence is unrelated to that file.  For the file-playback path
        // (startFromFile) this is harmless because the playback setup
        // re-assigns playingFileName immediately after startTapSequence returns.
        fftAnalyzer.playingFileName = nil
        // Clear the loaded-settings warning — the user is explicitly starting
        // a new sequence so the loaded threshold/tap-count are now theirs.
        showLoadedSettingsWarning = false

        // Clear multi-tap comparison state so the toggle resets.
        tapEntries = []
        showingMultiTapComparison = false

        // Clear per-sequence accumulated data.
        capturedTaps        = []
        currentTapCount     = 0
        tapProgress         = 0.0
        tapDetected         = false
        isDetectionPaused   = false

        currentDecayTime    = nil
        peakMagnitudeHistory = []
        resetDecayTracking()

        // ===== Audio-thread-visible state (must precede isDetecting = true) =====
        isMeasurementComplete = false

        // Clear any frozen spectrum BEFORE setting isDetecting = true.  If we
        // set isDetecting first and the audio thread fires a tap immediately
        // (file-playback case), a later setFrozenSpectrum() would wipe the
        // just-captured gated-FFT result.
        setFrozenSpectrum(frequencies: [], magnitudes: [])

        // Cancel any in-flight gated capture from a previous sequence and
        // reset the pre-roll BEFORE arming the crossing handler.  The ring
        // buffer fills naturally as audio chunks arrive via
        // accumulateGatedSamples.  If a tap fires before the buffer is full,
        // startGatedCapture seeds the accumulator with only the samples
        // received so far — no zero-padding.  This avoids diluting the
        // captured signal with silence, which would suppress the spectral
        // magnitude (the old zero-fill caused a ~7 dB live-capture deficit
        // and ~23 dB file-playback deficit vs Python).
        gatedCaptureActive = false
        mpmLock.lock()
        gatedAccumBuffer = []
        preRollBuffer = []
        // Clear the audio-queue fast-start markers so the first tap of this
        // sequence cannot mistake a stale "already handled" equality
        // (gatedCaptureID == lastLevelCrossingCaptureID) for a real fast-start
        // capture.  A material (plate/brace) completion leaves these two IDs
        // equal — unlike the guitar re-enable paths, it never resets them — so
        // a material→guitar boundary switch would otherwise make
        // startGuitarGatedCapture bail out (accum 0 samples) without capturing
        // or completing, stranding the analyzer with all controls disabled.
        // Mirrors the reset in postEngineStopHandler / reEnableDetectionForNextPlateTap.
        gatedCaptureID = 0
        lastLevelCrossingCaptureID = -1
        // Session recording: clear the buffer and begin recording.  The
        // buffer accumulates raw audio while detection is active, producing
        // a single WAV per measurement for replay.  Seed with checkpoint 0
        // so the first phase has a truncation anchor — without it, redoing
        // the first phase (or the same phase repeatedly) would leave the
        // rejected tap's audio in the saved WAV.
        sessionRecordingBuffer = []
        sessionCheckpoints = [0]
        isSessionRecording = true
        sessionRecordingSampleRate = mpmSampleRate > 0 ? mpmSampleRate : 48000
        mpmLock.unlock()

        // Seed the noise-floor estimate so the first relative-threshold (plate/brace) calculation has a
        // reasonable baseline.  Seed from the current input level; the warm-up's EMA then converges it,
        // and the warm-up-exit re-anchor snaps it to the real floor.
        //
        // The -100 case now only arises when the warm-up is skipped, which — since the caller keys
        // skipWarmup on the measurement type — means GUITAR, where the estimate is never read
        // (guitar uses the absolute threshold).  It must not be reached for material: -100 makes
        //     headroom = max(threshold - (-100), 10) = threshold + 100
        //     rising   = -100 + headroom             = threshold
        // i.e. the relative rule collapses onto the absolute one, silently disabling the very model
        // it is meant to implement.  That is what used to happen on EVERY file playback, which is why
        // the relative detector was never exercised by any regression test on any platform.
        // See GuitarTapWeb/Development/OUT-4-DETECTION-SPEC.md.
        noiseFloorEstimate = skipWarmup ? -100.0 : fftAnalyzer.inputLevelDB

        // For file playback (skipWarmup): start with isAboveThreshold = true
        // so the detector requires a falling edge (signal drops below
        // threshold) before any rising edge can fire.  This prevents the
        // file's opening audio — which may be mid-decay from a prior tap and
        // already above threshold — from immediately triggering a false first
        // tap that captures garbage.  The decay will naturally fall below
        // threshold, then the real first tap attack will produce the genuine
        // rising edge.
        isAboveThreshold = skipWarmup
        justExitedWarmup = false

        // Reset material phase state.  When initialPhase is provided
        // (phase-targeted file-playback tests), use that phase so the
        // level-crossing handler and gated capture route to the correct
        // phase handler.
        let newPhase: MaterialTapPhase
        if isPlateMode || isBraceMode {
            newPhase = initialPhase ?? .capturingLongitudinal
        } else {
            newPhase = .notStarted
        }
        resetMaterialPhaseState(to: newPhase)

        // ===== Arm detection =====
        analyzerStartTime = skipWarmup
            ? Date().addingTimeInterval(-(warmupPeriod + 0.1))
            : Date()
        isDetecting = true

        // ===== Status message and final UI clear =====
        if isBraceMode {
            statusMessage = numberOfTaps > 1 ? "Ready for fL tap (×\(numberOfTaps))" : "Ready for fL tap"
        } else if isPlateMode {
            let measureFlc = TapDisplaySettings.measureFlc
            if numberOfTaps > 1 {
                let phases = measureFlc ? "L, C, FLC" : "L, C"
                statusMessage = "Ready for L tap (×\(numberOfTaps) each for \(phases))"
            } else {
                statusMessage = "Ready for L tap"
            }
        } else {
            statusMessage = tapPrompt()
        }

        // Clear previous results so the chart shows a clean slate while waiting.
        currentPeaks    = []
        identifiedModes = []
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
        } else {
            statusMessage = guitarLoopStatus(capturing: false)
        }
        gtLog("▶️ Tap detection resumed at \(currentTapCount)/\(numberOfTaps)")
    }

    // MARK: - Cancel

    /// Cancels the current tap sequence by restarting it.
    ///
    /// Cancel is a **restart**: it returns the analyzer to the exact state that New
    /// Tap produces — a fresh, re-armed sequence waiting for the first tap — rather
    /// than completing the measurement.  (Previously this set
    /// `isMeasurementComplete = true` purely to re-enable the New Tap button; that
    /// button-gating hack is gone now that the button rule keys off whether a
    /// multi-step sequence is active.)  Cancel is only offered while a multi-step
    /// (multi-tap or multi-phase) sequence is in progress; re-arming there returns
    /// to tap 0 of that sequence.
    ///
    /// Runs fully synchronously, matching Python's `cancel_tap_sequence`.  All call
    /// sites are main-thread (Cancel button action).
    func cancelTapSequence() {
        gtLog("❌ Tap sequence cancelled — restarting")
        // A pending capture-completion timer from the sequence being abandoned must
        // not fire into the fresh one.
        captureTimer?.invalidate()
        captureTimer = nil
        // Re-arm a fresh sequence — identical to pressing New Tap. startTapSequence
        // clears captured taps / counts / frozen spectrum, resets the material phase,
        // restarts session recording, and sets isDetecting = true with the correct
        // "Ready…" status.
        startTapSequence()
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
    /// (`acceptCurrentPhase` on `.reviewingCross`) and the file-playback
    /// auto-complete path (`handleCrossGatedProgress` when `measureFlc`
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
    /// (`acceptCurrentPhase` on `.reviewingFlc`) and the file-playback
    /// auto-complete path (`handleFlcGatedProgress`).  Mirrors Python
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
    /// Call with `.notStarted` from ``cancelTapSequence()`` (guitar mode) and with
    /// `.capturingLongitudinal` from ``startTapSequence()`` / ``cancelTapSequence()``
    /// when in plate or brace mode.
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
