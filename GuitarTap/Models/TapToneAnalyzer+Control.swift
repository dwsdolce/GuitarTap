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
        warmupStartAudioTime = fftAnalyzer.audioElapsed  // Begin the warm-up period for the new session.
        gtLog("🎬 Analyzer started - warm-up period: \(warmupPeriod)s")

        // Evaluate the auto-start guard after pending state changes have settled. Launch auto-arm
        // goes through requestStartTapSequence so it gets the same dump-folder reachability check as
        // the New Tap button — launching the app is a user action, so it must
        // prompt too rather than silently record to (or skip) an unreachable folder.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !self.isDetecting && !self.isMeasurementComplete && !self.isDetectionPaused
                && self.currentTapCount == 0 {
                self.requestStartTapSequence()
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
    /// - Parameter skipWarmup: When `true`, backdates `warmupStartAudioTime` on the AUDIO clock so the
    ///   warm-up window has already elapsed when the first audio chunk arrives.
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
    ///   before the warm-up clock, and live suppresses detection during the warm-up, so no accepted
    /// tap can land in the first 0.5 s.
    // @parity state/tap-tone-analyzer
    /// User-initiated arming (New Tap buttons, settings-apply re-arm). A file that is playing is
    /// stopped first: a new sequence — for a changed measurement type, say — must not be fed the rest
    /// of the file. If Dump Capture Audio is on and its folder can't be reached, sets
    /// ``dumpFolderUnreachable`` so the view prompts the user (Change Location / Turn Off Saving /
    /// Cancel) and does **not** arm — the prompt's actions retry. File-playback setup calls
    /// ``startTapSequence`` directly, bypassing this check. On iOS the check is a no-op — the
    /// container folder is always reachable.
    func requestStartTapSequence() {
        fftAnalyzer.stopFilePlayback()
        #if os(macOS)
        if TapDisplaySettings.dumpCaptureAudio && !WavDumpFolder.isReachable {
            dumpFolderUnreachable = true
            return
        }
        #endif
        startTapSequence()
    }

    func startTapSequence(skipWarmup: Bool = false) {
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
        // isDetecting, warmupStartAudioTime, isAboveThreshold, justExitedWarmup,
        // materialTapPhase, noiseFloorEstimate, gatedCaptureActive / preRollBuffer)
        // is set BEFORE `detectionState = .listening` so the first audio buffer observed
        // by the crossing handler sees a fully-reset analyzer.

        // ===== UI / per-sequence state (not audio-thread visible) =====
        comparisonSpectra = []
        displayMode = .live
        loadedMeasurementName = nil
        loadedNotes = nil
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
        // A new sequence listens to the input until playFile says otherwise.
        resultProvenance = nil
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
        // No pause-clear here: `detectionState = .listening` further down leaves `.paused`
        // on its own, and clearing to `.idle` at this point would disarm a level crossing
        // that a restart-while-listening is relying on staying armed.

        currentDecayTime    = nil
        peakMagnitudeHistory = []
        resetDecayTracking()

        // ===== Audio-thread-visible state (must precede detectionState = .listening) =====
        isMeasurementComplete = false

        // Clear any frozen spectrum BEFORE setting detectionState = .listening.  If we
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
        sessionPreRollActive = true   // bound the pre-first-tap audio to ~2 s
        sessionRecordingSampleRate = mpmSampleRate > 0 ? mpmSampleRate : 48000
        mpmLock.unlock()

        // Seed the noise-floor estimate so the first relative-threshold (plate/brace) calculation has a
        // reasonable baseline.  Seed from the current input level; the warm-up's EMA then converges it,
        // and the warm-up-exit re-anchor snaps it to the real floor.
        //
        // The -100 case arises only when the warm-up is skipped, which — since the caller keys
        // skipWarmup on the measurement type — means GUITAR, where the estimate is never read
        // (guitar uses the absolute threshold).  It must not be reached for material: -100 makes
        //     headroom = max(threshold - (-100), 10) = threshold + 100
        //     rising   = -100 + headroom             = threshold
        // i.e. the relative rule collapses onto the absolute one, silently disabling the very model
        // it is meant to implement.
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
        // A new sequence starts its tap confirmation from zero: a chunk counted before it cannot help
        // confirm its first tap.
        detectTapConsecutiveAbove = 0
        justExitedWarmup = false

        // Reset material phase state: a material sequence starts at its first phase.
        resetMaterialPhaseState(to: isPlateMode || isBraceMode ? .capturingLongitudinal : .notStarted)

        // ===== Arm detection =====
        // AUDIO clock, not wall clock — see `warmupStartAudioTime`. Skipping the warm-up backdates it
        // so the window has already elapsed when the first chunk arrives.
        warmupStartAudioTime = skipWarmup
            ? fftAnalyzer.audioElapsed - (warmupPeriod + 0.1)
            : fftAnalyzer.audioElapsed
        detectionState = .listening

        // ===== Status message and final UI clear =====
        // `resetMaterialPhaseState(to:)` above has already set the phase, so the material prompt is
        // read from it rather than rebuilt here — one source for these strings. A phase-targeted
        // start (file playback) therefore announces the phase it actually begins in.
        statusMessage = (isPlateMode || isBraceMode) ? materialArmPrompt() : tapPrompt()

        // Clear previous results so the chart shows a clean slate while waiting.
        allPeaks        = []
        identifiedModes = []

        // Clear all per-peak state from the PREVIOUS measurement. These are keyed by the old peaks'
        // UUIDs, so once `allPeaks` is emptied they are invisible on screen — but they would still be
        // written verbatim into the NEXT measurement's saved file. A new sequence starts
        // with no selection, no labels and no dragged offsets.
        selectedPeakIDs              = []
        selectedPeakFrequencies      = []
        userHasModifiedPeakSelection = false
        peakModeOverrides            = [:]
        peakAnnotationOffsets        = [:]
    }

    // MARK: - Pause / Resume

    /// Pauses tap detection mid-sequence without losing the current tap count.
    ///
    /// The spectrum remains live so the user can experiment with the guitar while paused.
    /// Use ``resumeTapDetection()`` to continue the sequence from where it left off.
    ///
    /// No-op when not currently detecting or already paused.
    func pauseTapDetection() {
        guard detectionState == .listening else { return }
        detectionState = .paused
        isSessionRecording = false  // Stop accumulating audio during pause
        statusMessage    = Self.pausedStatus
        gtLog("⏸️ Tap detection paused at \(currentTapCount)/\(numberOfTaps)")
    }

    /// Resumes tap detection after a pause, continuing from the current tap count.
    ///
    /// The warm-up timer is reset so the first audio frame after resume does not fire
    /// immediately as a false tap.
    ///
    /// No-op when not paused.
    func resumeTapDetection() {
        guard detectionState == .paused else { return }

        // Reset warm-up to prevent an immediate false trigger on the first frame.
        warmupStartAudioTime = fftAnalyzer.audioElapsed
        isAboveThreshold  = false
        // The tap confirmation restarts: a chunk counted before the pause must not help confirm a tap
        // after it, or a single loud chunk could fire one.
        detectTapConsecutiveAbove = 0

        isSessionRecording = true  // Resume accumulating audio after pause
        detectionState = .listening

        // Restore a context-appropriate prompt. The same derivation the device-change settle uses.
        statusMessage = armedPrompt()
        gtLog("▶️ Tap detection resumed at \(currentTapCount)/\(numberOfTaps)")
    }

    // MARK: - Cancel

    /// Cancels the current tap sequence by restarting it.
    ///
    /// Cancel is a **restart**: it returns the analyzer to the exact state that New
    /// Tap produces — a fresh, re-armed sequence waiting for the first tap — rather
    /// than completing the measurement.  Cancel is offered while a multi-step
    /// (multi-tap or multi-phase) sequence is in progress, and throughout a file
    /// playback. During a playback it stops the file first, so the fresh sequence
    /// listens to the microphone and the partial result is discarded.
    ///
    /// Runs fully synchronously, matching Python's `cancel_tap_sequence`.  All call
    /// sites are main-thread (Cancel button action).
    func cancelTapSequence() {
        gtLog("❌ Tap sequence cancelled — restarting")
        // A pending capture-completion timer from the sequence being abandoned must
        // not fire into the fresh one.
        captureTimer?.invalidate()
        captureTimer = nil
        fftAnalyzer.stopFilePlayback()
        // Re-arm a fresh sequence — identical to pressing New Tap. startTapSequence
        // clears captured taps / counts / frozen spectrum, resets the material phase,
        // restarts session recording, and sets detectionState = .listening with the correct
        // "Ready…" status.
        startTapSequence()
    }

    // MARK: - Play File

    /// Play an audio file through the live pipeline — the Play File action. Plays with the calibration
    /// file given for it, or with no calibration (never the live input's), arms a fresh tap sequence,
    /// then starts the file; the calibration in effect before is restored when playback ends. The view calls this; so do the
    /// file-playback regressions, which therefore run the path users take.
    ///
    /// The warm-up is decided by the MEASUREMENT TYPE, not by "is this a file". Guitar skips it: the
    /// source is deterministic and the tap may sit within the first 0.5 s of an externally recorded
    /// file, and guitar uses the absolute threshold, never the noise floor. Material (plate/brace)
    /// runs it: it is the only mode on the relative noise-floor detector, and the warm-up is what
    /// establishes that floor — skipping it collapses `rising` onto `tapDetectionThreshold`. A saved
    /// session WAV always contains its warm-up.
    ///
    /// `startTapSequence` runs BEFORE `startFromFile`, so the analyzer state is fully reset before any
    /// audio flows — otherwise the engine could deliver buffers while the previous session's
    /// `isMeasurementComplete` still held, or complete a stale capture into `capturedTaps`.
    ///
    /// - Parameters:
    ///   - url: The audio file (WAV, AIFF, CAF, …).
    ///   - calibrationURL: The calibration of the microphone the file was recorded with, or nil to play
    ///     uncalibrated. A file that cannot be parsed is logged and the playback is uncalibrated.
    ///   - completion: Called on the main thread when playback has ended (after the calibration is
    ///     restored).
    /// - Throws: If the file cannot be read.
    func playFile(url: URL, calibrationURL: URL? = nil, completion: (() -> Void)? = nil) throws {
        // The playback uses the file's calibration, or none. The microphone the file was recorded with is
        // unknown, so the live input's calibration never applies to it.
        let previousCalibration = fftAnalyzer.activeCalibration
        var playbackCalibration: MicrophoneCalibration? = nil
        if let calURL = calibrationURL {
            do {
                playbackCalibration = try CalibrationFileParser.parse(url: calURL)
            } catch {
                gtLog("⚠️ Could not parse calibration file: \(error.localizedDescription)")
            }
        }
        fftAnalyzer.setTemporaryCalibration(playbackCalibration)

        let isMaterial = TapDisplaySettings.measurementType == .plate
            || TapDisplaySettings.measurementType == .brace
        startTapSequence(skipWarmup: !isMaterial)

        do {
            try fftAnalyzer.startFromFile(url) { [fftAnalyzer] in
                fftAnalyzer.setTemporaryCalibration(previousCalibration)
                completion?()
            }
            // The result comes from the file: its calibration, its sample rate, an unknown microphone.
            resultProvenance = ResultProvenance(microphoneName: nil, microphoneUID: nil,
                                                calibrationName: playbackCalibration?.name,
                                                sampleRate: fftAnalyzer.actualSampleRate)
        } catch {
            fftAnalyzer.setTemporaryCalibration(previousCalibration)
            throw error
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
            warmupStartAudioTime = fftAnalyzer.audioElapsed
            detectionState = .listening
            statusMessage = materialArmPrompt()   // phase is .capturingCross — one source

        case .reviewingCross:
            if measureFlc {
                gtLog("✅ Accepted C tap — advancing to FLC")
                materialTapPhase = .waitingForFlcTap
                statusMessage = materialArmPrompt()  // phase is .waitingForFlcTap — one source
                // Re-enable detection for the FLC phase after the hold: `tapCooldown` of AUDIO.
                afterAudio(tapCooldown) { [weak self] in
                    guard let self = self else { return }
                    // Cancelled or restarted while the hold ran (Cancel / New Tap / measurement-type
                    // change)? Then the phase is no longer .waitingForFlcTap, and re-arming would drag a
                    // fresh sequence into the FLC capture — clearing its frozen spectrum and re-enabling
                    // detection under a phase the user already left. `afterAudio` cannot be cancelled and
                    // `cancelTapSequence()`'s `captureTimer.invalidate()` does not reach this closure, so
                    // this guard IS the cancellation. Mirrors Python `_do_start_flc` and the web's FLC
                    // hold, both of which have always guarded here.
                    guard self.materialTapPhase == .waitingForFlcTap else { return }
                    self.materialTapPhase = .capturingFlc
                    self.setFrozenSpectrum(frequencies: [], magnitudes: [])
                    // Anchored on the chunk that made the hold due — its level and its audio time.
                    self.isAboveThreshold = self.lastChunkLevelDB > (self.tapDetectionThreshold - self.hysteresisMargin)
                    self.warmupStartAudioTime = self.lastAudioTime
                    self.detectionState = .listening
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
    /// Freezes the spectrum, marks
    /// the phase complete, writes the session WAV, and sets the completion
    /// status message.  Called from both the user-Accept path
    /// (`acceptCurrentPhase` on `.reviewingCross`) and the file-playback
    /// auto-complete path (`handleCrossGatedProgress` when `measureFlc`
    /// is `false`).  Mirrors Python `_finalise_plate_no_flc()`.
    func finalisePlateNoFLC() {
        setFrozenSpectrum(frequencies: [], magnitudes: [])
        materialTapPhase = .complete
        isMeasurementComplete = true
        finishSessionRecording(label: "Plate_LC")
        let fLStr = selectedLongitudinalPeak.map { String(format: "%.1f", $0.frequency) } ?? "?"
        let fCStr = selectedCrossPeak.map { String(format: "%.1f", $0.frequency) } ?? "?"
        statusMessage = "Complete — fL: \(fLStr) Hz, fC: \(fCStr) Hz"
    }

    /// Finalises a three-tap plate measurement (L + C + FLC).
    ///
    /// Freezes the spectrum, marks
    /// the phase complete, writes the session WAV, and sets the completion
    /// status message.  Called from both the user-Accept path
    /// (`acceptCurrentPhase` on `.reviewingFlc`) and the file-playback
    /// auto-complete path (`handleFlcGatedProgress`).  Mirrors Python
    /// `_finalise_plate_with_flc()`.
    func finalisePlateWithFLC() {
        setFrozenSpectrum(frequencies: [], magnitudes: [])
        materialTapPhase = .complete
        isMeasurementComplete = true
        finishSessionRecording(label: "Plate_LCF")
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
            // Redoing the FIRST phase empties the buffer back to the pre-first-tap state, so
            // re-arm the bounded pre-roll — the redone tap gets its ~2 s lead-in again.
            // Later phases (phaseStart > 0) keep earlier taps, so the latch stays frozen.
            if phaseStart == 0 { sessionPreRollActive = true }
        }
        mpmLock.unlock()

        switch materialTapPhase {
        case .reviewingLongitudinal:
            gtLog("🔄 Redo L phase — clearing longitudinal data")
            longitudinalSpectrum = nil
            selectedLongitudinalPeak = nil
            materialCapturedTaps = []
            currentTapCount = 0
            tapProgress = 0.0
            materialTapPhase = .capturingLongitudinal
            setFrozenSpectrum(frequencies: [], magnitudes: [])
            isAboveThreshold = fftAnalyzer.inputLevelDB > (tapDetectionThreshold - hysteresisMargin)
            warmupStartAudioTime = fftAnalyzer.audioElapsed
            detectionState = .listening
            statusMessage = "Ready for fL tap — tap again"

        case .reviewingCross:
            gtLog("🔄 Redo C phase — clearing cross-grain data")
            crossSpectrum = nil
            selectedCrossPeak = nil
            materialCapturedTaps = []
            let lCount = (longitudinalSpectrum != nil) ? numberOfTaps : 0
            currentTapCount = lCount
            tapProgress = Float(lCount) / Float(totalPlateTaps)
            materialTapPhase = .capturingCross
            setFrozenSpectrum(frequencies: [], magnitudes: [])
            isAboveThreshold = fftAnalyzer.inputLevelDB > (tapDetectionThreshold - hysteresisMargin)
            warmupStartAudioTime = fftAnalyzer.audioElapsed
            detectionState = .listening
            statusMessage = "Ready for fC tap — tap again"

        case .reviewingFlc:
            gtLog("🔄 Redo FLC phase — clearing FLC data")
            flcSpectrum = nil
            selectedFlcPeak = nil
            materialCapturedTaps = []
            let lcCount = (longitudinalSpectrum != nil && crossSpectrum != nil) ? numberOfTaps * 2 : 0
            currentTapCount = lcCount
            tapProgress = Float(lcCount) / Float(totalPlateTaps)
            materialTapPhase = .capturingFlc
            setFrozenSpectrum(frequencies: [], magnitudes: [])
            isAboveThreshold = fftAnalyzer.inputLevelDB > (tapDetectionThreshold - hysteresisMargin)
            warmupStartAudioTime = fftAnalyzer.audioElapsed
            detectionState = .listening
            statusMessage = "Ready for fLC tap — tap again"

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
    /// (`detectionState = .listening`).  If the clear were here (deferred inside a `main.async`
    /// block), the audio-queue level-crossing handler could start a legitimate gated
    /// capture between the sync and async sections, and this method would then kill it.
    private func resetMaterialPhaseState(to phase: MaterialTapPhase) {
        materialTapPhase    = phase
        longitudinalSpectrum = nil
        crossSpectrum        = nil
        flcSpectrum          = nil
        selectedLongitudinalPeak        = nil
        selectedCrossPeak               = nil
        selectedFlcPeak                 = nil
        materialCapturedTaps            = []
    }

    /// Stops any active decay tracking.
    private func resetDecayTracking() {
        isTrackingDecay = false
    }
}
