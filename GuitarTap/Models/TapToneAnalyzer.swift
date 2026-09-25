//
//  TapToneAnalyzer.swift
//  GuitarTap
//
//  Created on 1/25/26.
//
// @parity audio/tap-analyzer tests=test/tap-decisions,test/tap-progress

/// # TapToneAnalyzer
///
/// The central coordinator for tap-tone analysis of acoustic instruments and tonewoods.
///
/// `TapToneAnalyzer` sits between the low-level ``RealtimeFFTAnalyzer`` (which delivers raw
/// FFT frames and input-level events) and the SwiftUI views (which present results).  It owns
/// the complete lifecycle of a tap-tone measurement session: waiting for a tap, capturing the
/// ring-out spectrum, detecting peaks, classifying modes, and persisting the result.
///
/// ## Measurement Modes
///
/// Three measurement types are supported, selected via ``TapDisplaySettings/measurementType``:
///
/// | Mode | Taps | What is captured |
/// |------|------|-----------------|
/// | Guitar (classical/flamenco/acoustic) | 1–N averaged | Spectrum peak in each guitar-mode band |
/// | Plate | L + C (+ optional FLC) | Per-phase gated FFT → Young's moduli, specific modulus |
/// | Brace | L only | Longitudinal Young's modulus and specific modulus |
///
/// ## Two-Layer Peak Selection (Plate / Brace)
///
/// For material measurements the app tracks two peak-selection signals and resolves them with
/// strict priority order:
///
/// 1. **Phase-stored peak** (`selectedLongitudinalPeak` / Cross / Flc) — set automatically
///    when a gated-FFT phase completes and the dominant peak is identified.
/// 2. **Auto-selected ID** (`autoSelectedLongitudinalPeakID` / Cross / Flc) — intermediate
///    result set during HPS analysis before the phase is finalised.
///
/// There was a third, highest-priority layer — an explicit user override set by tapping a peak
/// row — until 2026-09-20. Its UI was removed on 2026-04-17 and replaced by redoing the phase;
/// see "Plate Peak Selection — REMOVED" in TapToneAnalyzer+AnnotationManagement.swift.
///
/// The computed ``effectiveLongitudinalPeakID``, ``effectiveCrossPeakID``, and
/// ``effectiveFlcPeakID`` properties expose the winning ID to views.
///
/// ## Gated FFT and Pre-Roll
///
/// For plate/brace measurements the analyzer uses a **gated FFT** approach:
/// - A circular pre-roll buffer (``preRollDuration``: 200 ms) continuously holds the most
///   recent raw audio samples.
/// - When tap detection fires, ``startGatedCapture(phase:)`` seeds the accumulator with the
///   pre-roll contents so the tap attack is not missed.
/// - The capture window (``gatedCaptureDuration``: 500 ms) then accumulates the ring-out.
/// - When the window closes, ``finishGatedFFTCapture`` runs a dedicated FFT and routes
///   results to the appropriate phase handler.
///
/// ## Tap Detection Strategy
///
/// | Mode | Signal used | Reason |
/// |------|-------------|--------|
/// | Guitar | FFT `peakMagnitude` (~0.7 Hz) | Slower but includes full spectrum analysis |
/// | Plate / Brace | `inputLevelDB` (~43 Hz RMS) | Long-window FFT dilutes short transients by ~15 dB |
///
/// In all modes a **hysteresis state machine** (`isAboveThreshold`) prevents retriggering:
/// the rising edge fires only when the signal crosses the rising threshold from below; the
/// next tap cannot be detected until the signal first falls below the falling threshold.
///
/// ## Warm-Up Period
///
/// The first ``warmupPeriod`` (0.5 s) after `start()` or `startTapSequence()` suppresses
/// all tap detection to let the audio engine and FFT pipeline settle.  At warm-up exit,
/// `justExitedWarmup` is momentarily `true` so `detectTap` can re-anchor `isAboveThreshold`
/// to the actual signal level without firing a spurious tap event.
import SwiftUI
import Combine

/// Test-only thread-safe completion flag for `playFileForTesting`: the background file-processing
/// worker `signal()`s it; the main-actor poll loop reads `isDone`. Replaces a `DispatchSemaphore`
/// whose non-blocking `.wait(timeout:)` is unavailable from async contexts under the Swift 6 language
/// mode. The lock keeps the cross-thread flag access data-race-free.
private final class FileProcessingDoneFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func signal() { lock.lock(); done = true; lock.unlock() }
    var isDone: Bool { lock.lock(); defer { lock.unlock() }; return done }
}

// MARK: - TapToneAnalyzer

/// The main `ObservableObject` that coordinates tap-tone measurements across all modes.
///
/// Create one shared instance as a `@StateObject` at the app level and pass it to child
/// views.  All `@Published` properties are updated on the main thread.
///
/// - SeeAlso: ``RealtimeFFTAnalyzer`` for the underlying audio/FFT engine.
/// - SeeAlso: ``TapToneMeasurement`` for the serialisable measurement record.
final class TapToneAnalyzer: ObservableObject {

    // MARK: - Testing Support

    /// Creates a `TapToneAnalyzer` wired for file-playback testing.
    ///
    /// The returned instance has the full pipeline connected (Combine
    /// subscriptions, raw-sample handler, level-crossing handler) but no
    /// audio hardware.  Use `playFileForTesting(url:measurementType:numberOfTaps:)`
    /// to feed a WAV file through the pipeline.
    ///
    /// The FFT size is the class-level constant in `RealtimeFFTAnalyzer`
    /// (65 536); it is not configurable per-instance.
    ///
    /// Mirrors Python `TapToneAnalyzer.for_testing()`.
    static func forTesting() -> TapToneAnalyzer {
        let fft = RealtimeFFTAnalyzer.forTesting()
        return TapToneAnalyzer(fftAnalyzer: fft)
    }

    /// Feeds a WAV file through the full analysis pipeline for testing.
    ///
    /// This is the test-only equivalent of the view-layer `openAudioFile(_:)`.
    /// It configures the measurement type, starts a tap sequence with warmup
    /// skipped, pre-fills the pre-roll buffer with silence, and synchronously
    /// processes all audio through `processFileData`.
    ///
    /// Mirrors Python `TapToneAnalyzer.play_file_for_testing()`.
    ///
    /// - Parameters:
    ///   - url: URL of the audio file (WAV, AIFF, CAF, etc.).
    ///   - measurementType: The measurement type to configure before playback.
    ///   - numberOfTaps: Number of taps to detect (guitar mode). Default 1.
    ///   - calibrationURL: Optional microphone calibration file to apply during playback.
    ///   - plateTapPhase: For plate measurements, the specific phase to test.
    ///     When set, the analyzer starts in this phase and the run loop exits as soon
    ///     as the phase advances (rather than waiting for `isMeasurementComplete`).
    ///     Pass `.capturingLongitudinal` for an L-only test, `.capturingCross` for C,
    ///     or `.capturingFlc` for FLC.  Ignored for non-plate measurement types.
    /// - Throws: If the audio file cannot be read.
    func playFileForTesting(url: URL, measurementType: MeasurementType, numberOfTaps: Int = 1, calibrationURL: URL? = nil, plateTapPhase: MaterialTapPhase? = nil) async throws {
        // 1. Configure measurement type and tap count.
        TapDisplaySettings.measurementType = measurementType
        self.numberOfTaps = numberOfTaps

        // 1b. If a calibration file was provided, parse it and temporarily
        //     override the active calibration on the FFT analyzer.
        if let calURL = calibrationURL {
            let cal = try CalibrationFileParser.parse(url: calURL)
            fftAnalyzer.setTemporaryCalibration(cal)
        }

        // 2. Start the tap sequence.  The MEASUREMENT TYPE decides whether to skip the warm-up.
        //
        //    Guitar: SKIP it.  The guitar fixtures are externally recorded files (not session dumps)
        //    with only 0.15–0.26 s before the tap, so a 0.5 s warm-up would suppress the transient.
        //    Guitar detects against the ABSOLUTE threshold and never uses the noise floor, so skipping
        //    costs nothing.
        //
        //    Material (plate/brace): RUN it.  Material is the ONLY mode that uses the relative
        //    noise-floor detector, and the warm-up is what establishes that floor (it feeds the EMA and
        //    fires the re-anchor at exit).  Skipping it also pinned `noiseFloorEstimate = -100`, which
        //    makes `rising` compute to exactly `tapDetectionThreshold` — i.e. it silently DEGRADED
        //    relative detection to absolute, so playback was never exercising the path live users take.
        //    A saved session WAV always contains the warm-up by construction (isSessionRecording is set
        //    before the warm-up clock, and live suppresses detection during it, so no tap can land in
        //    the first 0.5 s), and every material fixture carries 2.3–2.9 s of lead-in.
        //
        //    Playback must run the LIVE detection path — otherwise it cannot tell us whether live and
        //    playback agree, which is the whole point of the file-playback regression.
        //
        //    When plateTapPhase is provided, pass it as initialPhase so both the
        //    synchronous setup and the async housekeeping block use the correct
        //    phase — preventing the async block from resetting the phase back to
        //    .capturingLongitudinal after the override.
        let isMaterial = measurementType == .plate || measurementType == .brace
        startTapSequence(skipWarmup: !isMaterial, initialPhase: plateTapPhase)

        // 3. Read the audio file.
        let (monoSamples, fileSampleRate) = try RealtimeFFTAnalyzer.readAudioFileAsMonoFloat32(url: url)

        // 4. Set the sample rate so gatedCaptureSamples is computed correctly
        //    when a tap fires.  Do NOT pre-fill the pre-roll buffer with zeros —
        //    startTapSequence already cleared it to [], and it will fill naturally
        //    with real audio as chunks arrive through accumulateGatedSamples.
        //    Pre-filling with zeros dilutes the gated capture signal by ~50%,
        //    suppressing the spectral magnitude by ~6 dB.
        mpmSampleRate = fileSampleRate

        // 5. Configure @Published state and dispatch processFileData to a
        //    background queue — exactly as startFromFile does in the real app.
        //    The main run loop must keep spinning so that Combine sinks
        //    (.receive(on: DispatchQueue.main)) can deliver FFT frames to
        //    onFftFrame → tap detection → gated capture → finishGatedFFTCapture.
        let fileName = url.deletingPathExtension().lastPathComponent
        fftAnalyzer.prepareForFilePlayback(sampleRate: fileSampleRate, fileName: fileName)

        let done = FileProcessingDoneFlag()
        DispatchQueue.global(qos: .userInitiated).async { [fftAnalyzer] in
            fftAnalyzer.processFileData(
                samples: monoSamples,
                sampleRate: fileSampleRate,
                fileName: fileName
            )
            done.signal()
        }

        // Spin the main run loop until processFileData finishes, so
        // DispatchQueue.main.async blocks (Combine sinks, finishGatedFFTCapture)
        // are drained during processing — matching the real app's threading.
        // Poll for processFileData to finish, YIELDING the main actor between checks rather than
        // blocking it in RunLoop.main.run. The worker calls DispatchQueue.main.sync (the gated-capture
        // flush, RealtimeFFTAnalyzer+EngineControl.swift:622); under the test target's MainActor
        // isolation the test runs ON the main actor, so a blocking wait here deadlocks that sync.
        // `Task.sleep` suspends the main actor, freeing the main thread to run the worker's main-queue
        // work and deliver the Combine `.receive(on: .main)` FFT frames.
        while !done.isDone {
            try? await Task.sleep(nanoseconds: 5_000_000)  // 5 ms
        }
        // Continue draining the main run loop until the measurement completes.
        // processMultipleTaps() is scheduled via DispatchQueue.main.asyncAfter
        // with a delay of captureWindow (0.2 s), so we must keep spinning
        // until it fires and sets isMeasurementComplete = true.
        //
        // For phase-targeted plate tests (plateTapPhase != nil), exit as soon as
        // the phase advances past the target — the single capture is done and we
        // don't need to wait for subsequent phases to time out.
        let deadline = Date(timeIntervalSinceNow: 5.0)
        if let targetPhase = plateTapPhase, measurementType == .plate {
            while materialTapPhase == targetPhase && Date() < deadline {
                try? await Task.sleep(nanoseconds: 5_000_000)  // 5 ms — yields the main actor
            }
        } else {
            while !isMeasurementComplete && Date() < deadline {
                try? await Task.sleep(nanoseconds: 5_000_000)  // 5 ms — yields the main actor
            }
        }
    }

    // MARK: - Dependencies

    /// The underlying real-time FFT engine that delivers spectrum frames and input-level events.
    let fftAnalyzer: RealtimeFFTAnalyzer

    /// Equal-temperament pitch calculator (A4 = 440 Hz) used to annotate peaks with note names.
    let pitchCalculator = Pitch(a4: 440.0)

    // MARK: - Configuration

    /// Minimum magnitude for a spectral peak to be reported, in dBFS.
    ///
    /// Peaks below this level are discarded during peak-finding.  Persisted in
    /// ``TapDisplaySettings``.
    @Published var peakMinThreshold: Float = TapDisplaySettings.peakMinThreshold {
        didSet {
            TapDisplaySettings.peakMinThreshold = peakMinThreshold
            // Peak Min is a DISPLAY control, and re-projecting is ALL it does. It does not detect,
            // does not classify, and does not touch per-peak state — so selection, mode overrides
            // and dragged annotation positions survive a slider sweep untouched, and a peak hidden
            // then revealed returns exactly as it was.
            refreshDisplayedPeaks()
        }
    }

    /// Lower bound of the analysis frequency range, in Hz.
    ///
    /// Frequencies outside `minFrequency...maxFrequency` are excluded from peak detection.
    @Published var minFrequency: Float = TapDisplaySettings.analysisMinFrequency

    /// Upper bound of the analysis frequency range, in Hz.
    @Published var maxFrequency: Float = TapDisplaySettings.analysisMaxFrequency

    /// Minimum decay level relative to the tap peak for ring-out time measurement, in dB.
    ///
    /// Ring-out time is measured from the tap peak to the first moment the signal drops
    /// more than `decayThreshold` dB below that peak.  15 dB works well against typical
    /// room noise floors.
    @Published var decayThreshold: Float = 15

    /// Number of taps to average into a single spectrum (1 = single tap, 3–5 recommended).
    ///
    /// When this changes mid-sequence while waiting for the first tap, the status message
    /// is updated immediately to reflect the new count.
    @Published var numberOfTaps: Int = 1 {
        didSet {
            // Update the prompt if we're still waiting for the first tap.
            //
            // `armedPrompt()`, not `tapPrompt()`: the latter is the GUITAR prompt, so changing Taps
            // at the start of a plate or brace sequence — where the control is still unlocked,
            // because no tap has been captured — wrote "Tap the guitar 3 times..." over "Ready for
            // fL tap (×3 each for L, C)" (#17 F36).
            if isDetecting && currentTapCount == 0 {
                statusMessage = armedPrompt()
            }
            // NOTE: there is deliberately NO "reduce the count mid-sequence → finalise with the taps
            // already captured" branch here. The Taps stepper is disabled the moment a sequence has a
            // tap — `.disabled(tap.currentTapCount > 0 && !tap.isMeasurementComplete)`, on every
            // stepper on every platform — so the count simply cannot change mid-sequence; to change
            // it you cancel first. The branch that used to live here was therefore unreachable, and
            // being unreachable it had silently drifted three ways: Swift deferred processing by
            // `captureWindow` and averaged ALL captured taps, Python finalised synchronously and
            // truncated to the new count, and the web never implemented it at all. Removed rather
            // than reconciled (OUT-5) — reachable behaviour is unchanged. It was also a latent trap:
            // `loadMeasurement` writes `numberOfTaps`, so a load during a live sequence would have
            // kicked off `processMultipleTaps()` mid-load, guarded only by call ordering.
            //
            // If a mid-sequence count change is ever wanted, unlock the stepper and define the
            // semantics deliberately — do not resurrect an implicit finalise.

            // If the user changes tap count manually, the loaded-settings warning
            // is no longer relevant for this setting.
            if numberOfTaps != loadedNumberOfTaps {
                showLoadedSettingsWarning = false
            }
        }
    }

    // MARK: - Status derivation (mirrors the web state→string machine)

    /// The guitar resting prompt (post-warm-up steady state) — the single source for the
    /// "Tap the guitar…" / "Tap the guitar N times…" strings.  Mirrors the web `tapPrompt()`.
    func tapPrompt() -> String {
        numberOfTaps == 1 ? "Tap the guitar..." : "Tap the guitar \(numberOfTaps) times..."
    }

    /// Guitar detection-loop status derived from the current state — the analyzer's
    /// equivalent of the web `setGuitarStatus(engineState)`.  `capturing == false` →
    /// the resting prompt (count 0) or the between-taps "…captured. Tap again…";
    /// `capturing == true` → the in-progress "Tap n/N capturing…" or, on the final tap,
    /// "All taps captured. Processing…".  (guitar mode keeps `currentTapCount ==
    /// capturedTaps.count`, so the provisional `+1` matches the old `capturedTaps.count + 1`.)
    /// The status shown while a sequence is PAUSED.  One literal, used by `pauseTapDetection()`
    /// and by ``statusAfterSettle()`` so a device change cannot silently reword a paused sequence.
    static let pausedStatus = "Detection paused – tap freely, then resume"

    /// The prompt for an ARMED analyzer, whatever it is measuring — guitar count-aware, material
    /// phase-aware.  Extracted from `resumeTapDetection()`, which is where this logic lived as the
    /// only "restore a context-appropriate prompt" in the app.
    func armedPrompt() -> String {
        let type = TapDisplaySettings.measurementType
        guard !type.isGuitar else { return guitarLoopStatus(capturing: false) }
        return materialArmPrompt()
    }

    /// The prompt a material (plate/brace) sequence shows while armed and waiting in its CURRENT
    /// phase — the single source for these strings.
    ///
    /// Three callers, which is the point: ``startTapSequence`` (which sets the phase before the
    /// status), the phase advances in ``acceptCurrentPhase``, and ``armedPrompt()``. They used to
    /// hold two sets of literals — the advance said "Rotate 90° and tap for fC" while the armed
    /// derivation said "Ready for fC tap" — so resuming or changing the tap count silently reworded
    /// the instruction the user was following (#17 F37).
    ///
    /// The fL branch is count-aware, because that is the phase whose prompt names the tap count and
    /// the only phase where the Taps control is still unlocked.
    func materialArmPrompt() -> String {
        switch materialTapPhase {
        case .capturingCross:
            return "Rotate 90° and tap for fC"
        case .capturingFlc, .waitingForFlcTap:
            return "Set up for fLC tap, then tap"
        default:
            // capturingLongitudinal / notStarted. "fL", not "L", for plate as well — the phase-tap
            // rename missed this site once already (#17 F33).
            guard numberOfTaps > 1 else { return "Ready for fL tap" }
            guard TapDisplaySettings.measurementType == .plate else {
                return "Ready for fL tap (×\(numberOfTaps))"
            }
            let phases = TapDisplaySettings.measureFlc ? "L, C, FLC" : "L, C"
            return "Ready for fL tap (×\(numberOfTaps) each for \(phases))"
        }
    }

    /// The status to restore when a device/route-change settle ends — or `nil` to leave the current
    /// status alone.
    ///
    /// The settle used to CHOOSE between two strings (`tapPrompt()` when detecting, `"Ready"`
    /// otherwise), which is wrong in both directions: mid-sequence it said "Tap the guitar 3
    /// times…" when one tap was already captured, and on a finished measurement it replaced
    /// "Analysis complete! N peaks…" with "Ready".  The status is a function of state, so derive it
    /// rather than guessing — and say nothing at all where the status is a RESULT announcement
    /// rather than a live prompt, because a completed or loaded measurement's status is not
    /// re-derivable and must not be thrown away (#17 F33).
    func statusAfterSettle() -> String? {
        if isMeasurementComplete { return nil }        // "Analysis complete…" / "Loaded measurement…"
        if displayMode == .comparison { return nil }   // an overlay is not a tap prompt
        if isDetectionPaused { return Self.pausedStatus }
        if isDetecting {
            // A material phase prompt is an INSTRUCTION tied to a transition that already happened
            // — "Rotate 90° and tap for fC" — not a description of the state the analyzer is in.
            // It is therefore not re-derivable here: after a device swap the user has already
            // rotated the plate, and a redo's "Ready for fC tap — tap again" is a different, equally
            // correct string for the same phase. Preserve it, exactly as a completed measurement's
            // announcement is preserved. Guitar's prompt IS a function of count and total, both of
            // which the analyzer holds, so it is still derived (#17 F37).
            guard TapDisplaySettings.measurementType.isGuitar else { return nil }
            return armedPrompt()
        }
        return "Ready"
    }

    /// The status to show when a settle ends, given what the status said before it began.
    ///
    /// The whole decision in one pure function, so every edition can pin it: derive from state, and
    /// where the state's status is a result announcement rather than a prompt, put back what was
    /// there. The first version returned "nothing to say" and left the caller to skip the
    /// assignment — which left the "Audio device changed - reinitializing…" transient up forever on
    /// a completed measurement (#17 F33).
    func restoredStatus(before: String) -> String {
        statusAfterSettle() ?? before
    }

    func guitarLoopStatus(capturing: Bool) -> String {
        if capturing {
            let prov = min(currentTapCount + 1, numberOfTaps)
            return prov < numberOfTaps
                ? "Tap \(prov)/\(numberOfTaps) capturing..."
                : "All taps captured. Processing..."
        }
        return currentTapCount == 0
            ? tapPrompt()
            : "Tap \(currentTapCount)/\(numberOfTaps) captured. Tap again..."
    }

    /// Duration of the spectrum-capture window after each tap, in seconds.
    ///
    /// The spectrum snapshot is taken at `captureWindow` seconds after the tap event.
    /// 200 ms (default) captures the early decay while avoiding noise floor.
    @Published var captureWindow: TimeInterval = 0.2

    /// Tap-detection threshold, in dBFS.
    ///
    /// For guitar mode this is an absolute FFT magnitude level.  For plate/brace mode it is
    /// combined with the noise-floor estimate to form a relative threshold.
    /// Persisted in ``TapDisplaySettings``.
    @Published var tapDetectionThreshold: Float = TapDisplaySettings.tapDetectionThreshold {
        didSet {
            TapDisplaySettings.tapDetectionThreshold = tapDetectionThreshold
            // Keep the audio-queue level-crossing threshold in sync with the slider.
            //
            // NOTE: this is the ABSOLUTE threshold, and for plate/brace it deliberately does NOT match
            // the main-thread detector, which compares against the noise-floor-RELATIVE threshold
            // (`noiseFloorEstimate + headroom`). The level crossing is only a PRE-ROLL SNAPSHOT
            // mechanism — it grabs pre-onset audio so the gated window has lead-in; `detectTap` alone
            // decides whether a tap actually happened. (The comment here used to claim the two "fire at
            // the same level", which is false for material.)
            fftAnalyzer.levelCrossingThreshold = tapDetectionThreshold
            // If the user changes the threshold manually, the loaded-settings warning
            // is no longer relevant for this setting.
            if tapDetectionThreshold != loadedTapDetectionThreshold {
                showLoadedSettingsWarning = false
            }
        }
    }

    /// Hysteresis margin in dB.
    ///
    /// After a tap is detected, the signal must fall at least `hysteresisMargin` dB below
    /// the detection threshold before the next tap can be registered.  This prevents
    /// re-triggering during the ring-out of a single tap.
    /// Hardcoded constant — no longer user-configurable.
    let hysteresisMargin: Float = 3.0

    // MARK: - Published Results

    /// **The peaks.** The durable, complete peak set for the current measurement — everything found
    /// down to ``peakDetectionFloor`` (−100 dB), regardless of Peak Min.
    ///
    /// This is the source of truth. Peak identity lives here and changes ONLY when the spectrum
    /// changes (a new tap, freeze, or an explicit Re-analyze) — never because the display changed.
    /// Per-peak state (selection, mode overrides, annotation offsets) is keyed to these identities,
    /// which is what makes that state durable across a Peak Min move.
    ///
    @Published var allPeaks: [ResonantPeak] = [] {
        didSet { refreshDisplayedPeaks() }
    }

    /// ``allPeaks`` with the **Peak Min** filter applied — and *only* that filter.
    ///
    /// **It is not "the peaks".** Peak display is narrowed in three stages, each with a different
    /// scope, and this property is the middle one:
    ///
    /// | Stage | Scope | Changes when |
    /// |---|---|---|
    /// | ``allPeaks`` | the measurement | a new capture, or an explicit Re-analyze |
    /// | **this property** | a *setting*, global to the measurement | the user moves Peak Min |
    /// | ``GuitarMode/peaksInDisplayRange(_:minFreq:maxFreq:isGuitar:showUnknownModes:overriddenPeakIDs:guitarType:)`` | the *viewport* | pan, zoom, or a different chart |
    ///
    /// The stage exists on its own because the model needs it without the viewport: ``visiblePeaks``
    /// picks annotation candidates after Peak Min but *before* any range, since the view applies
    /// range afterwards. Folding it away would mean inlining the same filter at each such site,
    /// which is how display rules drift apart.
    ///
    /// **Read this only to decide what to SHOW.** Anything asking a question *about the measurement*
    /// — what to save, what is selected, what to classify, whether a measurement exists — must read
    /// ``allPeaks`` (or ``selectedPeaks``). Reading this property for such a question is the single
    /// most repeated defect in this codebase's history: it silently makes the answer depend on where
    /// a slider happens to sit.
    ///
    /// Derived, never assigned directly: it hands back the *same* `ResonantPeak` objects as
    /// ``allPeaks``, so filtering can never disturb identity or the per-peak state keyed to it.
    /// Peak Min is a guitar-only control, so for plate/brace this is simply ``allPeaks`` — the
    /// identified L / C / FLC peaks are the material result and are never filtered.
    @Published private(set) var peaksAbovePeakMin: [ResonantPeak] = []

    /// Recomputes ``peaksAbovePeakMin`` from ``allPeaks``. Called when either the peak set or Peak
    /// Min changes. Cheap — a filter over an existing array, no detection.
    func refreshDisplayedPeaks() {
        peaksAbovePeakMin = TapDisplaySettings.measurementType.isGuitar
            ? allPeaks.filter { $0.magnitude >= peakMinThreshold }
            : allPeaks
    }

    /// The user's selected peaks, resolved over the **durable** set.
    ///
    /// Selection is a fact about the measurement, not about what is currently on screen: auto-
    /// selection runs over the full set, so a selected peak may legitimately sit below Peak Min.
    /// Resolving it against ``peaksAbovePeakMin`` would silently drop such a peak from every derived
    /// value as the slider moves — the defect this property exists to prevent. One rule, so the
    /// on-screen multi-tap table and the exported PDF cannot drift apart.
    var selectedPeaks: [ResonantPeak] {
        allPeaks.filter { selectedPeakIDs.contains($0.id) }
    }

    /// Peak–mode pairs produced by classifying each entry in ``peaksAbovePeakMin``.
    ///
    /// Each element pairs a ``ResonantPeak`` with the ``GuitarMode`` whose frequency band
    /// contains the peak.  Legacy mode names are normalised before comparison.
    @Published var identifiedModes: [(peak: ResonantPeak, mode: GuitarMode)] = []

    /// Ring-out decay time from the most recent tap, in seconds.
    ///
    /// `nil` when no tap has been completed or decay tracking is disabled.
    @Published var currentDecayTime: Float?

    /// All measurements saved during this session, ordered by save time.
    @Published var savedMeasurements: [TapToneMeasurement] = []

    // MARK: - Published Detection State

    /// Most recent average FFT magnitude, in dBFS.
    ///
    /// Used internally by the hysteresis detector and exposed for the level-meter view.
    @Published var averageMagnitude: Float = -100

    /// The computed detection-threshold level displayed on the spectrum chart, in dBFS.
    ///
    /// For plate/brace mode this is `noiseFloorEstimate + headroom`; for guitar mode
    /// it equals ``tapDetectionThreshold``.
    @Published var tapDetectionLevel: Float = -100

    /// Whether the detector is listening, paused mid-sequence, or neither.
    ///
    /// Setting this property automatically arms or disarms the audio-queue
    /// level-crossing handler that snapshots the pre-roll buffer, on entry to
    /// and exit from ``DetectionState/listening``.
    ///
    /// One value rather than the `isDetecting` / `isDetectionPaused` pair it
    /// replaced: that pair could express "detecting AND paused", and every site
    /// touching either flag had to keep them consistent by hand.  Both remain
    /// available as computed reads below.
    @Published var detectionState: DetectionState = .idle {
        didSet {
            // Nothing to do for a same-value assignment — and in particular the
            // re-confirmation in startTapSequence's async block must not
            // re-arm, so that a capture already started by the audio queue
            // between the synchronous and async assignments is not disrupted.
            guard oldValue != detectionState else { return }
            let wasDetecting = (oldValue == .listening)
            TAP_DEBUG("detectionState", "\(oldValue.rawValue) → \(detectionState.rawValue) | complete=\(isMeasurementComplete) ready=\(isReadyForDetection) tapCount=\(currentTapCount)/\(numberOfTaps) capt=\(capturedTaps.count) phase=\(materialTapPhase) measType=\(TapDisplaySettings.measurementType) | isPlayingFile=\(fftAnalyzer.isPlayingFile)")
            // Brief call stack so we can see WHO changed the state (top 8 frames,
            // first one is the dispatch_wrap for swift property setters and is
            // skipped).  Strip the leading address columns to keep lines short.
            let frames = Thread.callStackSymbols.dropFirst().prefix(8)
                .map { $0.replacingOccurrences(of: "  +0x[0-9a-f]+", with: "", options: .regularExpression) }
                .joined(separator: " | ")
            TAP_DEBUG("detectionState.stack", frames)
            if isDetecting && !wasDetecting {
                // Entering `listening`: arm the audio-queue level-crossing
                // handler so it can start the gated capture at the exact
                // buffer that crosses the threshold (no main-thread delay).
                TAP_DEBUG("detectionState", "ARMING level crossing (→ listening)")
                fftAnalyzer.levelCrossingArmed = true
                // During file playback the audio queue is already tracking
                // previousLevelDB naturally.  Resetting it to -100 would
                // create a false rising-edge on the next chunk if the
                // previous tap's ring-out tail is still above threshold,
                // causing a spurious capture of silence/decay instead of
                // waiting for the real next tap's attack.
                // accumulateGatedSamples re-arms without resetting for this
                // exact reason — honour that here too.
                if !fftAnalyzer.isPlayingFile {
                    fftAnalyzer.previousLevelDB = -100
                }
            } else if !isDetecting {
                // During file playback, the audio queue manages its own
                // re-arming cycle (accumulateGatedSamples re-arms after
                // each capture completes).  Disarming here would undo that
                // re-arm before the next tap's audio arrives on the queue,
                // because the main-thread tap detection (which leaves
                // `listening`) runs after the audio-queue re-arm but before
                // the next tap's audio chunks are processed.
                if !fftAnalyzer.isPlayingFile {
                    TAP_DEBUG("detectionState", "DISARMING level crossing (not playing file)")
                    fftAnalyzer.levelCrossingArmed = false
                } else {
                    TAP_DEBUG("detectionState", "SKIPPED disarm (playing file)")
                }
            }
        }
    }

    /// `true` when tap detection is actively listening for taps.
    ///
    /// `false` after `stop()`, `cancelTapSequence()`, or while paused.
    var isDetecting: Bool { detectionState == .listening }

    /// `true` when the tap sequence is paused (spectrum stays live, detection is off).
    ///
    /// Distinct from ``DetectionState/idle`` because pause preserves the in-progress
    /// tap count, while a full stop resets it.
    var isDetectionPaused: Bool { detectionState == .paused }

    /// `true` while a device/route change settles and the chart should show nothing.
    ///
    /// The transient blank used to be expressed by writing `displayMode = .frozen`, which
    /// overloaded that value: `.frozen` then meant "a loaded measurement" AND "blanked for a
    /// moment", and the guard that decided whether to blank asked `displayMode == .live` — which is
    /// still true of a COMPLETED measurement, because no completion path sets `.frozen`. A device
    /// change therefore wiped a finished result's spectrum and peaks (#17 F35, regression from
    /// `a086638`, build 264). One flag for one fact.
    @Published var isSettling: Bool = false

    /// `false` during the brief period after an audio route change while the engine
    /// reinitialises.  The UI disables the New Tap and Resume buttons while this is `false`.
    @Published var isReadyForDetection: Bool = true {
        didSet {
            guard oldValue != isReadyForDetection else { return }
            TAP_DEBUG("isReadyForDetection", "\(oldValue) → \(isReadyForDetection) | detecting=\(isDetecting) complete=\(isMeasurementComplete) paused=\(isDetectionPaused)")
            let frames = Thread.callStackSymbols.dropFirst().prefix(6)
                .map { $0.replacingOccurrences(of: "  +0x[0-9a-f]+", with: "", options: .regularExpression) }
                .joined(separator: " | ")
            TAP_DEBUG("isReadyForDetection.stack", frames)
        }
    }

    /// Number of taps captured so far in the current multi-tap sequence.
    @Published var currentTapCount: Int = 0

    /// Fractional progress of the current multi-tap sequence (0.0–1.0).
    ///
    /// `currentTapCount / numberOfTaps`.  Used by the progress bar.
    @Published var tapProgress: Float = 0.0

    /// Human-readable status string shown in the status bar and instructions area.
    // @parity state/status-message
    @Published var statusMessage: String = "Tap the guitar to begin"

    /// Set true when the user tries to start a tap sequence (New Tap) while Dump Capture Audio is on
    /// but its folder can't be reached (§4b decision 1b). The view shows a prompt — Change Location /
    /// Turn Off Saving / Cancel — and the sequence does not arm until it is resolved. macOS only.
    @Published var dumpFolderUnreachable: Bool = false

    /// The most recent analyzer-set status message, preserved while the
    /// clipping override is active so it can be restored when clipping clears.
    /// Updated by a Combine sink on `$statusMessage` (see setupSubscriptions).
    /// Mirrors Python `_latest_real_status`.
    var latestRealStatus: String = "Tap the guitar to begin"

    /// What the status said before a device-change settle replaced it with the "reinitializing…"
    /// transient, or `nil` when no settle is in flight.
    ///
    /// A stored property rather than a local, matching Python `_status_before_settle` and web
    /// `statusBeforeSettle`, so the capture is observable and all three editions can pin it (#17 F37).
    var statusBeforeSettle: String?

    /// Sentinel string used to detect (and ignore) self-writes to
    /// `statusMessage` performed by the clipping-override path, so the
    /// `$statusMessage` sink doesn't store the warning into
    /// `latestRealStatus`.  Mirrors Python's identical override.
    static let clippingWarningStatus = "⚠ Input clipping — reduce mic gain"

    /// Shown while the input delivers buffers that carry no signal. Outranks the
    /// clipping warning: a dead input cannot also be clipping, and if both were
    /// somehow set, "no audio" is the more actionable message.
    static let deadInputStatus = "⚠ No audio input — check the microphone connection"

    // MARK: - Published Frozen Spectrum

    /// Frequencies of the frozen (post-tap-sequence) spectrum, in Hz.
    ///
    /// Populated for guitar measurements when `isMeasurementComplete` becomes `true`.
    /// Not used for plate/brace measurements (per-phase spectra are stored separately).
    ///
    /// - Important: Always assign this together with `frozenMagnitudes` via
    ///   `setFrozenSpectrum(frequencies:magnitudes:)` so both arrays update in a
    ///   single `objectWillChange` notification.  Assigning them separately triggers
    ///   two render passes; between the first and second pass, the arrays have
    ///   mismatched lengths, which causes SwiftUI Charts to draw spurious vertical
    ///   line artifacts.
    @Published var frozenFrequencies: [Float] = []

    /// Magnitudes of the frozen (post-tap-sequence) spectrum, in dBFS.
    ///
    /// - Important: Always assign via `setFrozenSpectrum(frequencies:magnitudes:)`.
    @Published var frozenMagnitudes: [Float] = []

    /// Assign both frozen arrays in a single `objectWillChange` notification.
    ///
    /// Calling this helper ensures that `frozenFrequencies` and `frozenMagnitudes`
    /// are always updated atomically from SwiftUI's perspective: only one render
    /// pass is triggered, so the two arrays are never transiently mismatched in
    /// length.  All assignment sites should call this instead of setting the two
    /// properties individually.
    func setFrozenSpectrum(frequencies: [Float], magnitudes: [Float]) {
        objectWillChange.send()
        frozenFrequencies = frequencies
        frozenMagnitudes  = magnitudes
    }

    // MARK: - Published Annotation & Selection State

    /// Screen-space label offset overrides for draggable peak annotations, keyed by peak UUID.
    ///
    /// `.zero` means the label is at its default computed position.  Non-zero values are
    /// persisted in ``TapToneMeasurement/peakAnnotationOffsets`` when a measurement is saved.
    @Published var peakAnnotationOffsets: [UUID: CGPoint] = [:]

    /// Per-peak user mode label overrides, keyed by peak UUID.
    ///
    /// Every entry IS an override: the label the user assigned. A peak with no entry uses
    /// auto-classification — absence is the only way to say "no override", so a stored value
    /// meaning "no override" cannot exist. Mirrors Python `peak_mode_overrides` (`{uuid: label}`)
    /// and web `overrides` (`Map<number, string>`); ``UserAssignedMode`` remains the `.guitartap`
    /// wire shape, converted at the file boundary (#17 F28).
    @Published var peakModeOverrides: [UUID: String] = [:]

    /// UUIDs of peaks the user has marked as significant results.
    ///
    /// Unmarked peaks are displayed at reduced opacity and can be hidden by setting
    /// ``annotationVisibilityMode`` to `.selected`.
    @Published var selectedPeakIDs: Set<UUID> = []

    /// The peak the user has focused by clicking a dot in the chart or a row in the results panel.
    ///
    /// Only one peak can be highlighted at a time. Setting this to a peak's UUID highlights
    /// the corresponding dot (chart) and row (results). Setting to `nil` clears the highlight.
    /// Both chart and results panel observe this via `@ObservedObject` on the shared analyzer.
    @Published var highlightedPeakID: UUID? = nil

    /// Whether the user has manually modified peak selections since the last auto-selection.
    ///
    /// When `false`, changing Peak Min on a frozen guitar spectrum re-runs
    /// ``guitarModeSelectedPeakIDs(from:)`` from scratch. When `true`, selections
    /// are carried forward by frequency proximity instead so manual choices are preserved.
    /// Reset to `false` by ``resetToAutoSelection()`` or by a new tap sequence completing.
    var userHasModifiedPeakSelection: Bool = false

    /// The original peak array from the most recently loaded measurement.
    ///
    /// Retained so that ``recalculateFrozenPeaksIfNeeded()`` can remap
    /// ``peakAnnotationOffsets``, ``peakModeOverrides``, and ``selectedPeakIDs``
    /// by frequency proximity when Peak Min changes generate new UUIDs.
    /// `nil` when no measurement has been loaded, or after a new tap sequence starts.
    var loadedMeasurementPeaks: [ResonantPeak]? = nil

    /// Frequencies (Hz) of the currently selected peaks, kept in sync with
    /// `selectedPeakIDs` whenever a non-empty peak set is available.  Used as
    /// a stable carry-forward reference in `recalculateFrozenPeaksIfNeeded()`
    /// so that selection survives Peak Min being raised above all peaks and
    /// then lowered again (at which point `selectedPeakIDs` holds stale UUIDs
    /// that no longer exist in the current peak set).
    var selectedPeakFrequencies: [Float] = []

    /// Suppresses `recalculateFrozenPeaksIfNeeded()` while `loadMeasurement` is
    /// restoring state.  During a load the saved peaks are already correct; we
    /// must not re-run `findPeaks()` with a potentially-wrong guitar type before
    /// the view has had a chance to apply `loadedGuitarType`.
    var isLoadingMeasurement: Bool = false

    /// Controls which annotations are rendered on the spectrum chart.
    /// Initialised from UserDefaults so the last-used mode is restored on launch.
    @Published var annotationVisibilityMode: AnnotationVisibilityMode = TapDisplaySettings.annotationVisibilityMode

    // MARK: - Mode Label Helpers

    /// Returns the display label for a peak, respecting any user override.
    ///
    /// - Parameter peak: The peak whose label is needed.
    /// - Returns: The ``UserAssignedMode/assigned(_:)`` string if a manual override exists,
    ///   otherwise the auto-classified ``GuitarMode/displayName``.
    func effectiveModeLabel(for peak: ResonantPeak) -> String {
        peakModeOverrides[peak.id] ?? peakMode(for: peak).displayName
    }

    /// The mode this peak would carry with **no** override — i.e. the mode a "Reset to Auto-Detected"
    /// would restore it to.
    ///
    /// Deliberately override-blind: it reads the auto-classification (``identifiedModes``) and
    /// never consults ``peakModeOverrides``. This is exactly the value the reset menu item should
    /// name — the target of the reset, not the current label. `.unknown` is a legitimate result (a
    /// peak in no band, or a material peak, which has no guitar mode) and is shown as such — so a
    /// peak with no entry resolves to it rather than being classified alone. See ``peakMode(for:)``.
    func autoDetectedMode(for peak: ResonantPeak) -> GuitarMode {
        identifiedModes.first(where: { $0.peak.id == peak.id })?.mode ?? .unknown
    }

    /// Sets or clears a mode override for a specific peak, thread-safely.
    ///
    /// If called from a background thread, the update is dispatched to the main queue.
    ///
    /// - Parameters:
    ///   - override: The ``UserAssignedMode`` to apply.
    ///   - peakID: UUID of the target peak.
    func setModeOverride(_ label: String, for peakID: UUID) {
        if Thread.isMainThread {
            peakModeOverrides[peakID] = label
            // A mode change on an ALREADY-SELECTED peak can leave two definitive peaks in one mode;
            // that is the only way an override touches selection. Relabelling an unselected peak
            // just adds a candidate. See `enforceDefinitiveModeUniqueness(preferring:)`.
            enforceDefinitiveModeUniqueness(preferring: peakID)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakModeOverrides[peakID] = label
                self?.enforceDefinitiveModeUniqueness(preferring: peakID)
            }
        }
    }

    /// Returns `true` when the given peak has a manually-assigned (non-auto) mode label.
    ///
    /// - Parameter peakID: UUID of the peak to check.
    func hasManualOverride(for peakID: UUID) -> Bool {
        peakModeOverrides[peakID] != nil
    }

    /// The UUIDs of every peak the user has given a manual mode label.
    ///
    /// Passed to ``GuitarMode/peaksInDisplayRange(_:minFreq:maxFreq:isGuitar:showUnknownModes:overriddenPeakIDs:guitarType:)``
    /// so a static, pure function can apply the same unknown-mode rule the analyzer uses, without
    /// needing an analyzer reference at the call site.
    var overriddenPeakIDs: Set<UUID> {
        Set(peakModeOverrides.keys)
    }

    /// Whether a peak counts as **unknown** for the Show Unknown Modes filter.
    ///
    /// The single rule behind all three display surfaces — the results table, the chart dot layer
    /// and the annotation badges. A peak is unknown only when auto-classification failed to place it
    /// in any mode band **and** the user has not named it. **Naming a peak makes it known**: a user
    /// who labels a peak "Wolf note" has identified it, and hiding it would discard their own work.
    ///
    /// Note this is equivalent to the old positional test ``GuitarMode/isKnown(frequency:guitarType:)``
    /// for every peak *without* an override, because ``GuitarMode/classifyAll(_:guitarType:)`` falls
    /// back to a per-frequency lookup for peaks its one-per-mode claiming pass did not take. The two
    /// differ only under a user override — which is exactly the case this predicate exists to fix.
    ///
    func isUnknown(_ peak: ResonantPeak) -> Bool {
        peakMode(for: peak).normalized == .unknown && !hasManualOverride(for: peak.id)
    }

    // MARK: - Peak Selection Helpers

    /// Toggles the selection state of a single peak.
    ///
    /// Selected peaks are shown at full opacity and included in the `.selected` annotation
    /// visibility mode.
    ///
    /// - Parameter peakID: UUID of the peak to toggle.
    func togglePeakSelection(_ peakID: UUID) {
        if selectedPeakIDs.contains(peakID) {
            selectedPeakIDs.remove(peakID)
        } else {
            selectedPeakIDs.insert(peakID)
            enforceDefinitiveModeUniqueness(preferring: peakID)
        }
        userHasModifiedPeakSelection = true
    }

    /// The modes that can have at most one **definitive** (selected) peak.
    ///
    /// Air, Top and Back are single physical resonances, so exactly one peak can be *the* Air, Top
    /// or Back. Dipole, Ring and Upper Modes are clusters — several selected peaks are meaningful
    /// there, so they are deliberately unconstrained.
    static let singleHolderModes: Set<GuitarMode> = [.air, .top, .back]

    /// Keeps the selection invariant: **at most one selected peak per Air / Top / Back**.
    ///
    /// The selected peak *is* the definitive Air/Top/Back; every other peak of that mode remains a
    /// candidate. Deselecting a peak does **not** relabel it — classification is band membership and
    /// is untouched by selection. This function only ever removes other peaks from the selection; it
    /// never reclassifies anything and never promotes a replacement.
    ///
    /// Only two things can break the invariant, and both call this:
    /// 1. selecting a peak whose mode already has a definitive holder (``togglePeakSelection(_:)``);
    /// 2. changing the mode of an **already-selected** peak (``setModeOverride(_:for:)``).
    ///
    /// Overriding an *unselected* peak changes no selection — it simply becomes another candidate.
    /// Overriding the definitive Top away from Top leaves Top with no definitive peak, deliberately:
    /// nothing is auto-promoted.
    ///
    /// Guitar only — material has no per-peak selection.
    ///
    /// - Parameter peakID: The peak that should remain selected; any other selected peak sharing its
    ///   mode is deselected.
    func enforceDefinitiveModeUniqueness(preferring peakID: UUID) {
        guard TapDisplaySettings.measurementType.isGuitar,
              selectedPeakIDs.contains(peakID),
              let winner = allPeaks.first(where: { $0.id == peakID }) else { return }

        // Resolve through `peakMode(for:)` — the OVERRIDE-AWARE path. `identifiedModes` is built from
        // classifyAll alone and never consults overrides, so using it here would silently ignore a
        // mode the user assigned by hand. (See Phase 6 in the lifecycle plan.)
        let mode = peakMode(for: winner).normalized
        guard Self.singleHolderModes.contains(mode) else { return }

        for other in allPeaks
        where other.id != peakID
            && selectedPeakIDs.contains(other.id)
            && peakMode(for: other).normalized == mode {
            selectedPeakIDs.remove(other.id)
        }
    }

    /// Clears the selection set so no peaks are marked as significant.
    func selectNoPeaks() {
        selectedPeakIDs.removeAll()
        userHasModifiedPeakSelection = true
    }

    /// Advances ``annotationVisibilityMode`` to the next state in the cycle:
    /// `all → selected → none → all`, and persists the new value to UserDefaults.
    func cycleAnnotationVisibility() {
        // All → Selected → None → All, on every measurement type. For material (plate/brace) there is
        // no per-peak selection, so `.selected` and `.all` render the same set (all identified peaks);
        // the mode is a shared setting and is never coerced on type change. (RESPIN-1.0.2.)
        annotationVisibilityMode = annotationVisibilityMode.next
        TapDisplaySettings.annotationVisibilityMode = annotationVisibilityMode
    }

    /// The subset of ``peaksAbovePeakMin`` that should be rendered as annotations given
    /// the current ``annotationVisibilityMode``.
    ///
    /// In guitar mode, peaks classified as Unknown are excluded when
    /// ``TapDisplaySettings/showUnknownModes`` is `false`, keeping the chart
    /// consistent with the Analysis Results panel.
    var visiblePeaks: [ResonantPeak] {
        // Material (plate/brace): annotate the accumulated identified L/C/FLC (stable, persistent),
        // matching the web — NOT `peaksAbovePeakMin`, which churns through 87→126→3 raw peaks during
        // capture. There is no per-peak selection, so `.all`/`.selected` are equivalent. (RESPIN-1.0.2, fix R.)
        if !TapDisplaySettings.measurementType.isGuitar {
            return annotationVisibilityMode == .none ? [] : materialIdentifiedPeaks
        }
        let candidates: [ResonantPeak]
        switch annotationVisibilityMode {
        case .all:      candidates = peaksAbovePeakMin
        case .selected: candidates = peaksAbovePeakMin.filter { selectedPeakIDs.contains($0.id) }
        case .none:     return []
        }
        // Filter unknown-mode peaks in guitar mode when the setting is off. One rule for all three
        // display surfaces — see `isUnknown(_:)`. Note the annotation layer carries an extra gate the
        // table and the dot layer do not: the visibility mode above. `All` means all *identified*
        // peaks, selected or not.
        guard !TapDisplaySettings.showUnknownModes else {
            return candidates
        }
        return candidates.filter { !isUnknown($0) }
    }

    /// The identified per-phase peaks (L, then C, then FLC) found so far in a material measurement,
    /// in phase order. Stable and PERSISTENT across phases — the material analog of the guitar
    /// "selected" set, mirroring the web's `matPeaks` that drives material annotations. Empty for
    /// guitar. Used as the live-chart annotation source so annotations grow 1→2→3 cleanly instead of
    /// following `peaksAbovePeakMin` (which churns through all raw peaks during capture). (RESPIN-1.0.2, fix R.)
    var materialIdentifiedPeaks: [ResonantPeak] {
        guard !TapDisplaySettings.measurementType.isGuitar else { return [] }
        return [selectedLongitudinalPeak, selectedCrossPeak, selectedFlcPeak].compactMap { $0 }
    }

    // MARK: - Plate / Brace Measurement State

    /// Current phase of the multi-tap material measurement sequence.
    ///
    /// Progresses from `.notStarted` through `.capturingLongitudinal`, `.reviewingLongitudinal`,
    /// `.capturingCross`, `.reviewingCross` (and optionally FLC phases) to `.complete`.
    @Published var materialTapPhase: MaterialTapPhase = .notStarted

    /// `true` when a measurement is complete and ready for review — whether it is a guitar
    /// measurement (frozen spectrum) or a plate/brace measurement (`materialTapPhase == .complete`).
    ///
    /// Used as a unified guard to prevent auto-starting a new tap sequence when the analyzer
    /// engine restarts (e.g. after an AirDrop or returning from background).  Cleared by
    /// `startTapSequence()` and `newMeasurement()`.
    /// Store B — the CURRENT measurement's material inputs (see ``MaterialMeasurementInputs``): the
    /// sole source for its derived properties, its Results-panel display/edit, and Save. Distinct from
    /// ``TapDisplaySettings`` (the defaults for a NEW measurement). Seeded from settings when a
    /// material measurement completes; set from the file snapshot on load; `nil` for guitar and before
    /// completion.
    @Published var materialInputs: MaterialMeasurementInputs?

    @Published var isMeasurementComplete: Bool = false {
        didSet {
            if oldValue != isMeasurementComplete {
                TAP_DEBUG("isMeasurementComplete", "\(oldValue) → \(isMeasurementComplete) | detecting=\(isDetecting) paused=\(isDetectionPaused) ready=\(isReadyForDetection) tapCount=\(currentTapCount)/\(numberOfTaps) capt=\(capturedTaps.count) measType=\(TapDisplaySettings.measurementType)")
                let frames = Thread.callStackSymbols.dropFirst().prefix(6)
                    .map { $0.replacingOccurrences(of: "  +0x[0-9a-f]+", with: "", options: .regularExpression) }
                    .joined(separator: " | ")
                TAP_DEBUG("isMeasurementComplete.stack", frames)
            }
            // A successful new tap clears the loaded-settings warning — the user
            // has now captured a measurement with the current (loaded) settings and
            // knows what they are.
            if isMeasurementComplete { showLoadedSettingsWarning = false }

            // Store B: on a material *capture* completion (not a load — loadMeasurement sets
            // materialInputs from the file), snapshot the current Settings defaults as this
            // measurement's own material inputs. Nothing reads them before completion.
            if isMeasurementComplete, !oldValue,
               !TapDisplaySettings.measurementType.isGuitar,
               !isLoadingMeasurement {
                materialInputs = .fromSettings(for: TapDisplaySettings.measurementType)
            }
        }
    }

    /// Averaged FFT spectrum from the longitudinal (along-grain) tap, once captured.
    ///
    /// `nil` before the longitudinal phase completes.
    @Published var longitudinalSpectrum: (magnitudes: [Float], frequencies: [Float])?

    /// Averaged FFT spectrum from the cross-grain tap, once captured.
    ///
    /// `nil` before the cross-grain phase completes.
    @Published var crossSpectrum: (magnitudes: [Float], frequencies: [Float])?

    /// Peaks detected from the longitudinal tap (all candidates, not just the dominant one).
    @Published var longitudinalPeaks: [ResonantPeak] = []

    /// Peaks detected from the cross-grain tap.
    @Published var crossPeaks: [ResonantPeak] = []

    /// Intermediate auto-selected UUID from HPS analysis of the longitudinal phase.
    ///
    /// Part of the two-layer peak-selection system; overridden by ``selectedLongitudinalPeak``
    /// once the phase finalises.
    @Published var autoSelectedLongitudinalPeakID: UUID?

    /// The dominant longitudinal peak stored when the longitudinal phase finalises.
    ///
    /// First priority: the finalised phase peak, used whenever the phase has completed.
    @Published var selectedLongitudinalPeak: ResonantPeak?

    /// Intermediate auto-selected UUID from HPS analysis of the cross-grain phase.
    @Published var autoSelectedCrossPeakID: UUID?

    /// The dominant cross-grain peak stored when the cross-grain phase finalises.
    @Published var selectedCrossPeak: ResonantPeak?

    /// Peaks detected from the FLC (torsional/twist) tap.
    @Published var flcPeaks: [ResonantPeak] = []

    /// Averaged FFT spectrum from the FLC tap, once captured.
    @Published var flcSpectrum: (magnitudes: [Float], frequencies: [Float])?

    /// Intermediate auto-selected UUID from HPS analysis of the FLC phase.
    @Published var autoSelectedFlcPeakID: UUID?

    /// The dominant FLC peak stored when the FLC phase finalises.
    @Published var selectedFlcPeak: ResonantPeak?

    // MARK: - Effective Peak Selection
    //
    // `selected<Phase>Peak` is the identified peak. The resolvers below used to fall back to
    // `autoSelected<Phase>PeakID`, but that arm was UNREACHABLE: both are assigned on adjacent
    // lines in the phase-completion handlers, and the selected one is never nil when the auto id is
    // set (`?? avgPeak`). Removed 2026-09-20.
    //
    // The `autoSelected*PeakID` properties THEMSELVES stay — they are a @Published change channel
    // the view subscribes to (`.onReceive(tap.$autoSelectedLongitudinalPeakID)`) to widen the chart
    // axis onto a newly identified peak. Deleting them would silently drop that behaviour.

    /// UUID of the longitudinal (fL) peak, or `nil` before the phase finalises.
    ///
    /// There is nothing to resolve: this is the phase's identified peak. It was a three-layer
    /// resolution until 2026-09-20 — a user-override tier whose UI went in April 2026, over the
    /// phase peak, over `autoSelectedLongitudinalPeakID` — and the note above records why both
    /// extra layers went. Kept as a named property because views and the material-property
    /// calculations read it, and because its two siblings exist for the other phases.
    var effectiveLongitudinalPeakID: UUID? {
        selectedLongitudinalPeak?.id
    }

    /// UUID of the cross-grain (fC) peak, or `nil` before the phase finalises.
    var effectiveCrossPeakID: UUID? {
        selectedCrossPeak?.id
    }

    /// UUID of the FLC (torsional/twist) peak, or `nil` before the phase finalises.
    var effectiveFlcPeakID: UUID? {
        selectedFlcPeak?.id
    }

    // MARK: - Loaded / Restored State

    /// All four axis bounds from a saved measurement, published as a single unit.
    ///
    /// Wrapping the four values in one struct ensures the view's `onReceive` handler
    /// fires once and applies all four bounds in the same render pass.  Publishing
    /// them as four separate `@Published` optionals fired four `onReceive` deliveries
    /// and four separate renders; between deliveries some bounds were updated while
    /// others were still at their previous values, causing a transient `minDB ≈ maxDB`
    /// state that made SwiftUI Charts clamp every data point to the same level and
    /// render a burst of apparent vertical lines.
    struct LoadedAxisRange {
        let minFreq: Float
        let maxFreq: Float
        let minDB: Float
        let maxDB: Float
    }

    /// Axis bounds loaded from a saved measurement (or comparison union).
    ///
    /// Set via `setLoadedAxisRange(minFreq:maxFreq:minDB:maxDB:)` so all four values
    /// are published in a single `objectWillChange` notification.  Cleared (set to `nil`)
    /// by the view after applying.
    @Published var loadedAxisRange: LoadedAxisRange?

    /// Frequency range bounds loaded from a saved measurement.
    ///
    /// These are published so that the view layer can pick them up via `onReceive` and
    /// apply them to its local display-range state without the analyzer needing to know
    /// about the chart's axis state directly.
    @Published var loadedMinFreq: Float?
    /// Upper frequency bound loaded from a saved measurement, in Hz.
    @Published var loadedMaxFreq: Float?
    /// Lower magnitude bound loaded from a saved measurement, in dBFS.
    @Published var loadedMinDB: Float?
    /// Upper magnitude bound loaded from a saved measurement, in dBFS.
    @Published var loadedMaxDB: Float?

    /// Publish all four axis bounds as a single atomic notification.
    ///
    /// Calling this helper instead of assigning the four `loaded*` properties
    /// individually ensures the view receives one `onReceive` event and applies
    /// all bounds in the same render pass, preventing transient mismatches.
    func setLoadedAxisRange(minFreq: Float, maxFreq: Float, minDB: Float, maxDB: Float) {
        objectWillChange.send()
        loadedAxisRange = LoadedAxisRange(minFreq: minFreq, maxFreq: maxFreq,
                                         minDB: minDB, maxDB: maxDB)
        // Also keep the individual properties in sync for any existing call sites
        // that still read them (e.g. tests).
        loadedMinFreq = minFreq
        loadedMaxFreq = maxFreq
        loadedMinDB   = minDB
        loadedMaxDB   = maxDB
    }

    /// Analysis settings loaded from a saved measurement (tap detection threshold in dBFS).
    @Published var loadedTapDetectionThreshold: Float?
    /// Peak-magnitude threshold loaded from a saved measurement, in dBFS.
    @Published var loadedPeakThreshold: Float?
    /// Number-of-taps setting loaded from a saved measurement.
    @Published var loadedNumberOfTaps: Int?
    /// Unknown-modes visibility flag loaded from a saved measurement.
    @Published var loadedShowUnknownModes: Bool?
    /// Guitar type classification loaded from a saved measurement.
    @Published var loadedGuitarType: GuitarType?
    /// Measurement type (guitar / plate / brace) loaded from a saved measurement.
    @Published var loadedMeasurementType: MeasurementType?

    /// True while the user should be reminded that threshold and tap-count settings
    /// came from a loaded measurement rather than their own preferences.
    /// Set when a measurement is loaded; cleared when a new tap is successfully
    /// completed, when the user manually changes threshold or tap count, or on reset.
    @Published var showLoadedSettingsWarning: Bool = false

    /// Warning message shown when the microphone used for a loaded measurement is unavailable
    /// on the current device.
    @Published var microphoneWarning: String?

    /// Peak selection IDs loaded from a saved plate/brace measurement.
    @Published var loadedSelectedLongitudinalPeakID: UUID?
    /// Cross-grain peak ID loaded from a saved plate measurement.
    @Published var loadedSelectedCrossPeakID: UUID?
    /// FLC peak ID loaded from a saved plate measurement.
    @Published var loadedSelectedFlcPeakID: UUID?

    // NOTE: the former loaded*-dimension publishers (loadedPlateLength/…/loadedBraceMass +
    // guitarBody*/plateStiffness*/measureFlc) were removed with the two-store material-dimensions
    // work: loading now sets the measurement's own `materialInputs` (Store B) directly and never
    // writes the Settings defaults, so those publishers and their view handlers were dead.

    /// Timestamp of the measurement most recently loaded into the results panel.
    ///
    /// `nil` when the current results are from a fresh (unsaved) measurement session.
    @Published var sourceMeasurementTimestamp: Date? = nil

    /// Measurement name label of the measurement currently loaded into the chart.
    ///
    /// Set to `measurement.measurementName` (or `nil` if blank) when a measurement
    /// is loaded. Cleared to `nil` when a new tap sequence starts or the
    /// analyzer is reset, so the UI can show "New" instead.
    @Published var loadedMeasurementName: String? = nil

    /// The notes of the most recently loaded measurement (or `nil` if blank). Seeds the Save sheet's
    /// notes field so re-saving a loaded measurement keeps its notes (R10). Mirrors
    /// `loadedMeasurementName`: set on load, cleared to `nil` on a new tap sequence / reset.
    @Published var loadedNotes: String? = nil

    /// The authoritative display mode for the main spectrum view.
    ///
    /// All UI sections that differ between live, frozen, and comparison modes should
    /// switch on this property rather than checking `comparisonSpectra.isEmpty`.
    @Published var displayMode: AnalysisDisplayMode = .live

    /// Overlay spectra loaded for comparison in the main chart.
    ///
    /// When non-empty, these are merged into `materialSpectra` in guitar mode so the
    /// main `SpectrumView` displays them as colored overlays using its existing
    /// `materialSpectra` path. Cleared by `clearComparison()` or a new tap sequence.
    /// The `modeIDs` element is the definitive `{mode name: peak id}` map for this overlay (see
    /// ``ComparisonEntry/modePeakIDs``), computed override-aware from the source at build time and
    /// carried so the on-screen comparison table shows the same Air/Top/Back the source measurement
    /// does — including a user's override. Empty only for the in-memory fallback; render then
    /// re-derives positionally.
    @Published var comparisonSpectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String, peaks: [ResonantPeak], guitarType: GuitarType?, modeIDs: [String: UUID])] = []

    /// Full `SpectrumSnapshot` for each entry in `comparisonSpectra`, in the same order.
    ///
    /// Stored so that `saveComparison()` can embed the snapshots into `ComparisonEntry`
    /// values without needing to re-query the measurement store.  Populated by
    /// `loadComparison` and cleared by `clearComparison` / `loadMeasurement`.
    @Published var comparisonSnapshots: [SpectrumSnapshot] = []

    // MARK: - Multi-Tap Comparison State

    /// Per-tap spectra and peaks from the most recently completed multi-tap guitar sequence.
    ///
    /// Populated by `processMultipleTaps()` when `capturedTaps.count > 1` for guitar mode.
    /// Cleared by `startTapSequence()` / `resetForNewSequence()` when a new sequence begins.
    /// Also restored from `TapToneMeasurement.tapEntries` when a saved measurement is loaded.
    @Published var tapEntries: [TapEntry] = []

    /// When `true`, the Results panel shows the multi-tap comparison view (per-tap spectra
    /// overlaid on the chart + Air/Top/Back table) instead of the normal averaged peak list.
    ///
    /// Only relevant when `isMeasurementComplete && !tapEntries.isEmpty`.
    /// Automatically reset to `false` when a new sequence starts.
    @Published var showingMultiTapComparison: Bool = false

    /// `true` when the user has loaded saved measurements to overlay — the classic
    /// "Comparison" mode.  `false` during multi-tap comparison (per-tap waveform view
    /// of the current guitar measurement) even though both set `displayMode = .comparison`.
    ///
    /// Use this wherever behaviour must differ between the two comparison sub-types:
    /// save routing, PDF/spectrum export routing, annotation suppression, etc.
    var isSavedMeasurementComparison: Bool {
        displayMode == .comparison && !showingMultiTapComparison
    }

    // MARK: - Gated FFT State

    /// Lock protecting ``gatedAccumBuffer``, which is written on the audio queue and
    /// read/cleared on the main queue.
    let mpmLock = NSLock()

    /// `true` when the gated-FFT capture window is open and accumulating samples.
    var gatedCaptureActive: Bool = false

    /// Monotonic capture identity — incremented at every `startGatedCapture` /
    /// `startGuitarGatedCapture` call.  Each pending safety-timeout closure
    /// captures the ID at scheduling time and only flushes the accumulator if
    /// `gatedCaptureID` still matches.  Without this, a stale timeout from a
    /// previous capture can fire while the next capture is mid-fill, dispatch
    /// its partial buffer as if it were the new capture's complete result, and
    /// silently truncate the capture window.  Mirrors Python `_gated_capture_id`.
    var gatedCaptureID: Int = 0

    /// The `gatedCaptureID` value set by the most recent audio-queue
    /// level-crossing fast-start.  `startGatedCapture(phase:)` and
    /// `startGuitarGatedCapture()` check this: if it matches the current
    /// `gatedCaptureID` the fast-start already handled this tap — whether
    /// the capture is still running or has already completed — so the
    /// main-thread call skips re-seeding entirely.
    var lastLevelCrossingCaptureID: Int = -1

    /// Pre-roll snapshot captured by the level-crossing handler on the audio
    /// queue when it fires during file playback but a previous capture's
    /// completion is still pending on the main thread.  In this "deferred"
    /// case the handler does NOT start `gatedCaptureActive` (which would
    /// cascade), but snapshots the pre-roll so the main-thread
    /// `startGatedCapture(phase:)` can seed from the correct audio position.
    /// Cleared by `startGatedCapture` after consumption.
    var pendingLevelCrossingPreRoll: [Float]? = nil

    /// Accumulated raw PCM samples for the current gated FFT capture window.
    ///
    /// Seeded with pre-roll content when the window opens; populated by
    /// ``accumulateGatedSamples(_:sampleRate:)`` on the audio queue.
    var gatedAccumBuffer: [Float] = []

    /// Target duration of the gated capture buffer, in seconds.
    ///
    /// 500 ms is intentionally longer than ``gatedFFTWindowDuration`` so that
    /// `alignCaptureToOnset` always has at least 400 ms of audio available
    /// to extract a sample-aligned window — regardless of how full the
    /// pre-roll ring buffer happens to be when the level crossing fires.
    /// Without this slack, a partially-filled pre-roll (e.g. when the user
    /// taps quickly after pressing Accept) would yield a captured buffer
    /// where the onset is too close to the end, forcing the aligner to
    /// zero-pad and producing FFT input that differs between live and
    /// playback even though the underlying audio is identical.
    static let gatedCaptureDuration: Double = 0.500

    /// Duration of the aligned FFT input window, in seconds.
    ///
    /// 400 ms captures the full plate ring-out while rejecting post-decay
    /// noise.  Shorter than ``gatedCaptureDuration`` to leave alignment
    /// headroom — see that property's documentation for the rationale.
    static let gatedFFTWindowDuration: Double = 0.400

    // ── Onset-alignment constants ─────────────────────────────────
    // Used by `alignCaptureToOnset` to anchor the capture window to
    // the sample-level tap onset rather than a chunk boundary.

    /// Duration of pre-onset silence to include in the aligned capture
    /// window.  100 ms places the transient where the Hann window
    /// weight is near maximum.
    static let preOnsetDuration: Double = 0.100

    /// Number of samples at the buffer start used to estimate the noise
    /// floor for onset detection.
    static let onsetNoiseEstimateSamples: Int = 2048

    /// Onset threshold multiplier relative to noise-floor RMS.  10×
    /// (20 dB above noise) rejects ambient noise while catching even
    /// a quiet tap transient.
    static let onsetThresholdMultiplier: Float = 10.0

    /// Minimum absolute onset threshold when the noise floor is near
    /// digital silence.
    static let onsetMinThreshold: Float = 0.001

    /// Number of samples to back up from the detected onset to ensure
    /// the very beginning of the transient is captured.
    static let onsetBackupSamples: Int = 32

    /// Number of samples in one gated capture window at the current hardware sample rate.
    /// Target size of the gated-capture window, in samples.
    ///
    /// Set at capture-start time so the same accumulator infrastructure can serve
    /// different capture lengths: plate/brace uses ``gatedCaptureDuration`` (~500 ms);
    /// guitar uses the full `fftSize` so the resulting spectrum has the same
    /// frequency resolution as the live FFT path.
    var gatedCaptureSamples: Int = 0

    /// Callback invoked on the main thread when the gated capture window fills.
    ///
    /// Receives `(samples, sampleRate, phase)` and is responsible for running the gated
    /// FFT and routing results to the appropriate phase handler.
    var gatedCaptureCompletion: (([Float], Double, MaterialTapPhase) -> Void)?

    /// The ``MaterialTapPhase`` that was active when the current gated capture started,
    /// or `nil` for a guitar-mode capture.
    ///
    /// Stored at capture-start time so the completion handler knows which phase to finalise
    /// even if ``materialTapPhase`` has advanced by the time the window closes.
    /// `nil` is the sentinel value identifying a guitar-mode capture, parallel to
    /// Python's `_gated_capture_phase = None`.
    var gatedCapturePhase: MaterialTapPhase? = nil

    /// Most recent hardware sample rate, in Hz.
    ///
    /// Set on the audio processing queue when a new audio buffer arrives.
    var mpmSampleRate: Double = 48000

    // MARK: - Session Recording
    //
    // A continuous audio buffer that accumulates raw mic samples while tap
    // detection is active, producing one WAV per measurement that replays
    // identically through the pipeline.  See session-recording-wav-save.md.

    /// Session recording buffer — accumulates raw mic audio while detection
    /// is active.  Used to produce a single WAV per measurement that can be
    /// replayed through the pipeline to reproduce the original results.
    ///
    /// Access is protected by `mpmLock` (shared with the gated-capture state).
    var sessionRecordingBuffer: [Float] = []

    /// Whether the session recording is actively accumulating samples.
    /// Set to `true` when a tap sequence starts and detection is active.
    /// Set to `false` during pause, on cancel, or when the measurement completes.
    var isSessionRecording = false

    /// Checkpoint offsets (sample counts in `sessionRecordingBuffer`) for
    /// accepted plate phases.  When a phase is redone, the buffer is truncated
    /// to the last checkpoint so rejected audio is excluded from the saved WAV.
    var sessionCheckpoints: [Int] = []

    /// Sample rate captured at recording start, used for session WAV export.
    var sessionRecordingSampleRate: Double = 48000

    /// Bounded pre-roll for the session WAV (FILE-PATHS-AND-NAMES-SPEC §6).
    ///
    /// While armed and **before the first tap**, the session buffer keeps only the last
    /// ``sessionPreRollDuration`` of audio (trimmed on every chunk), so an app left armed for
    /// minutes does not accumulate minutes of silence — in RAM or in the saved WAV. This latch is
    /// `true` from `startTapSequence` until the first gated capture begins, then stays `false`:
    /// once real recording starts, the buffer grows straight through so every tap, phase and redo
    /// checkpoint is preserved. Guarantees ≥ 0.5 s before the first tap (detection is suppressed
    /// during the warm-up), so every dumped WAV is a valid playback fixture. Access under `mpmLock`.
    var sessionPreRollActive = false

    /// Seconds of audio retained before the first tap. ≥ the 0.5 s warm-up, with margin.
    static let sessionPreRollDuration: Double = 2.0

    /// ``sessionPreRollDuration`` in samples at the current session rate.
    var sessionPreRollSamples: Int { Int(sessionRecordingSampleRate * TapToneAnalyzer.sessionPreRollDuration) }

    // MARK: - Pre-Roll Ring Buffer

    // The tap detection subscriber runs on the main thread, while raw audio buffers
    // arrive on the audio processing queue.  By the time detectTap fires and
    // startGatedCapture sets gatedCaptureActive = true, several audio buffers carrying
    // the tap transient have already passed through accumulateGatedSamples and been
    // discarded — so without a pre-roll the gated window captures only the decaying tail.
    //
    // Solution (two layers):
    // 1. Continuously maintain the last `preRollSamples` of raw audio in a circular
    //    buffer (preRollBuffer).  When startGatedCapture is called it seeds
    //    gatedAccumBuffer with the ring-buffer contents.
    // 2. For guitar mode: the audio-queue level-crossing handler (wired in
    //    setupSubscriptions) starts the gated capture immediately when the input
    //    level crosses the detection threshold — seeding gatedAccumBuffer with the
    //    pre-roll and setting gatedCaptureActive = true right on the audio queue.
    //    This eliminates both the pre-roll shift AND the sample gap that would
    //    otherwise occur during the main-thread Combine dispatch delay.  When
    //    startGuitarGatedCapture() runs on the main thread it detects the already-
    //    active capture and only sets up the safety timeout.

    /// Duration of the pre-roll look-back buffer, in seconds.
    ///
    /// 200 ms is enough to guarantee the tap attack is captured even on slow devices.
    static let preRollDuration: Double = 0.200

    /// Number of pre-roll samples at the current hardware sample rate.
    var preRollSamples: Int { Int(mpmSampleRate * TapToneAnalyzer.preRollDuration) }

    /// Circular buffer holding the most recent ``preRollSamples`` raw PCM samples.
    ///
    /// Always written on the audio queue; read once at ``startGatedCapture(phase:)``.
    var preRollBuffer: [Float] = []

    // initializePreRollBuffer was removed — pre-filling the pre-roll with
    // zeros diluted the gated capture signal by ~50%, suppressing spectral
    // magnitude by ~6 dB.  The pre-roll buffer now starts empty (cleared by
    // startTapSequence) and fills naturally with real audio as chunks arrive.

    // MARK: - Noise Floor Estimation (Plate / Brace Modes)

    /// Exponential moving average of `inputLevelDB`, used as the ambient noise-floor
    /// estimate for relative tap detection in plate/brace modes.
    ///
    /// Updated only when the signal is below the detection threshold (i.e. between taps)
    /// so that tap energy does not contaminate the estimate.
    var noiseFloorEstimate: Float = -60

    /// EMA smoothing factor for noise-floor tracking.
    ///
    /// At ~23 ms audio buffer updates (1024 samples at 44.1 kHz), α = 0.05 gives a time constant τ ≈ 450 ms:
    /// `α ≈ 1 − exp(−dt/τ)`.  Slower than a one-pole would normally be so that brief
    /// transients (instrument handling noise, room noise spikes) do not drive the estimate up.
    let noiseFloorAlpha: Float = 0.05

    // MARK: - Private State

    /// Frequency proximity tolerance used to identify near-duplicate peaks (Hz).
    ///
    /// Two peaks within this distance are considered the same physical resonance.
    /// Shared by ``removeDuplicatePeaks(_:)`` in `+PeakAnalysis` and
    /// ``buildAllPeaks(magnitudes:frequencies:dominantPeak:)`` in `+SpectrumCapture`.
    static let peakProximityHz: Float = 2.0

    /// The absolute magnitude floor (dBFS) for the peak set persisted with a guitar measurement.
    ///
    /// A saved measurement records every peak down to this floor, not just those above the current
    /// Peak Min, so a reloaded measurement can reveal peaks below the capture-time Peak Min exactly
    /// as the live measurement can. −100 dB is the chart's `defaultMinMagnitude` and the Peak Min
    /// slider's lower bound, so a peak below it can neither be drawn nor admitted by Peak Min — there
    /// is nothing to gain by storing it. See PEAK-MIN-SEMANTICS.md in the GuitarTapWeb repo.
    static let peakDetectionFloor: Float = -100.0

    /// Combine cancellable storage for FFT and input-level subscriptions.
    var cancellables = Set<AnyCancellable>()

    /// Tears down the `fftAnalyzer` subscriptions deterministically, while `fftAnalyzer` is still
    /// alive, so their teardown cannot race its deallocation.
    ///
    /// These subscriptions are `fftAnalyzer.$magnitudes` / `$frequencies` / … `.receive(on:).sink`.
    /// On dealloc, the *synthesized* deinit releases stored properties in an unspecified order: if
    /// `fftAnalyzer` (and its `@Published` subjects) released before `cancellables`, tearing down a
    /// `.receive(on:)` subscription touches a **freed** subject → EXC_BAD_ACCESS (seen as a refcount
    /// release on a garbage pointer in `swift_cvw_destroyImpl` during the deinit epilogue).
    ///
    /// `cancel()` ALONE is not enough: it stops delivery but leaves the `Set<AnyCancellable>`
    /// populated, so the conduit graph is still released in the unspecified-order epilogue — and the
    /// crash reproduced with only-cancel present (build 418, `PeakFixtureRegressionTests`, ~1/300).
    /// `removeAll()` releases the conduit graph HERE, in the deinit body, while `fftAnalyzer`'s
    /// subjects are guaranteed still alive; the later `fftAnalyzer` release then has no conduits left
    /// pointing at it. The invariant is cancel-then-release, both before any stored property drops.
    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    /// History of (audioTime, inputLevelDB) samples used by the decay tracker.
    ///
    /// `time` is the **audio clock** (seconds since engine start), carried with each sample
    /// from the audio thread — NOT wall-clock. The ring-out is therefore measured in audio
    /// time and is invariant to main-thread scheduling jitter under load; stamping with
    /// `Date()` at the consumer made the decay number drift on a busy machine. (OUT-4 lesson:
    /// the timestamp must travel with the sample.)
    var peakMagnitudeHistory: [(time: Double, magnitude: Float)] = []

    /// Audio-clock time (seconds since engine start) of the tap that started the current
    /// decay-tracking window — the time-zero reference for ``measureDecayTime(tapTime:)``.
    var decayTapAudioTime: Double?

    /// The audio clock as the analyzer has seen it: the audio time of the latest chunk delivered to
    /// ``onRmsLevelChanged(_:audioTime:)``, recorded on every chunk before any guard.
    ///
    /// The tap-lifecycle timers run on THIS clock, not the wall clock (#19). File playback advances
    /// audio at "real time + processing time", so a wall-clock delay covered a different stretch of
    /// audio on a slower run, and captures late in a sequence moved. Chunks reach the main thread in
    /// order, each carrying its own audio time, so a delay measured here covers exactly the same audio
    /// on every run. Never substitute `fftAnalyzer.audioElapsed` read on the main thread: the audio
    /// thread races ahead of it.
    var lastAudioTime: Double = 0

    /// The level (dBFS) of the chunk whose audio time is ``lastAudioTime``. A re-arm that falls due on
    /// a chunk re-anchors the hysteresis latch from THIS level — the published meter level
    /// (`fftAnalyzer.inputLevelDB`) lags a chunk behind on the main thread.
    var lastChunkLevelDB: Float = -100

    /// The WALL time (`ProcessInfo.systemUptime`) at which the latest chunk reached
    /// ``onRmsLevelChanged(_:audioTime:)`` — what the capture safety timeout measures its silence from
    /// (``afterAudioStall(_:while:_:)``, #19).
    var lastChunkWallTime: TimeInterval = 0

    /// Tap-lifecycle actions waiting on the audio clock — see ``afterAudio(_:releasedAtFileEnd:_:)``.
    var pendingAudioActions: [(due: Double, releasedAtFileEnd: Bool, action: () -> Void)] = []

    /// Input level (dBFS) at the moment the most recent tap was detected.
    ///
    /// Used as the reference magnitude for ring-out time computation.
    var tapPeakLevel: Float = -100

    /// The rest after a capture before detection re-arms, and the hold before the FLC phase arms, in
    /// seconds of AUDIO (see ``afterAudio(_:releasedAtFileEnd:_:)``, #19).
    let tapCooldown: TimeInterval = 0.5

    /// Value of the engine's AUDIO clock (`fftAnalyzer.audioElapsed`, in seconds of audio processed)
    /// when `start()` or `startTapSequence()` last armed a sequence. `nil` until first armed.
    ///
    /// Used to enforce the warm-up period. This is deliberately the AUDIO clock, not the wall clock:
    /// the warm-up must cover the first `warmupPeriod` of AUDIO. Live, the two coincide. In FILE
    /// PLAYBACK they do not — the file is read and the engine reconfigured between arming and the first
    /// chunk, and if that setup outlasts the warm-up, a wall-clock warm-up expires *before any audio
    /// arrives*: it never runs, the noise-floor re-anchor never fires, and the EMA latches at its seed.
    /// That silently disabled relative detection in playback. See OUT-4-DETECTION-SPEC.md.
    var warmupStartAudioTime: Double?

    /// Duration of the warm-up period during which all taps are suppressed, in seconds.
    ///
    /// Gives the audio engine and FFT pipeline time to stabilise after a cold start.
    let warmupPeriod: TimeInterval = 0.5

    /// Captured tap spectra waiting to be averaged at the end of a guitar-mode sequence.
    var capturedTaps: [(magnitudes: [Float], frequencies: [Float], captureTime: Date)] = []

    /// Captured spectra within the current plate/brace phase (supports per-phase averaging).
    var materialCapturedTaps: [(magnitudes: [Float], frequencies: [Float], captureTime: Date)] = []

    /// Timer that fires at the end of the capture window to trigger spectrum snapshot.
    var captureTimer: Timer?

    /// `true` when the signal is currently above the detection threshold.
    ///
    /// This is the state bit of the hysteresis state machine.  A tap is registered only
    /// on a **rising edge** (transition from `false` to `true`) confirmed by
    /// ``RealtimeFFTAnalyzer/levelCrossingConfirmationChunks`` consecutive
    /// above-rising-threshold chunks.
    var isAboveThreshold: Bool = false

    /// Running count of consecutive above-rising-threshold chunks within the
    /// current candidate rising-edge run for the main-thread `detectTap`.
    /// Reset to `0` whenever the signal falls back below the rising threshold
    /// before reaching ``RealtimeFFTAnalyzer/levelCrossingConfirmationChunks``.
    /// Once it reaches the target, ``isAboveThreshold`` latches to `true` and
    /// the rising-edge actions run.
    ///
    /// This mirrors ``RealtimeFFTAnalyzer/levelCrossingConsecutiveAbove`` for
    /// the audio-queue fast-path level-crossing detector — both paths must
    /// apply the same confirmation logic or a bump that's rejected by the
    /// audio queue can still fire here and start a bogus gated capture.
    var detectTapConsecutiveAbove: Int = 0

    /// How long after a tap the ring-out is tracked, in seconds of AUDIO (#19).
    let decayTrackingDuration: Double = 3.0

    /// `true` while decay tracking is actively recording the post-tap signal envelope.
    var isTrackingDecay: Bool = false

    /// `true` for the single FFT frame immediately after the warm-up period ends.
    ///
    /// Used to re-anchor `isAboveThreshold` to the real signal level without firing
    /// a spurious tap event.
    var justExitedWarmup: Bool = false

    // MARK: - Initialisation

    /// Creates a `TapToneAnalyzer` backed by the given FFT engine.
    ///
    /// Loads persisted analysis settings from ``TapDisplaySettings`` and previously
    /// saved measurements from the Documents directory, then wires up Combine subscriptions
    /// to the FFT engine's published properties.
    ///
    /// - Parameter fftAnalyzer: The ``RealtimeFFTAnalyzer`` instance to subscribe to.
    init(fftAnalyzer: RealtimeFFTAnalyzer) {
        self.fftAnalyzer = fftAnalyzer

        #if os(macOS)
        // When the user grants microphone permission during the first-launch dialog,
        // RealtimeFFTAnalyzer's requestAccess callback fires on a background thread.
        // Without this hook it would call fftAnalyzer.start() directly, bypassing
        // TapToneAnalyzer.start() — so warmupStartAudioTime would never be set and
        // startTapSequence() would never be called, leaving the app stuck showing
        // "Tap the guitar to begin" with no peak detection active.
        fftAnalyzer.onPermissionGranted = { [weak self] in
            guard let self else { return }
            do {
                try self.start()
            } catch {
                // Surface engine errors that occur on the permission-granted restart.
                // kAudioUnitErr_Unauthorized (-10877): TCC cache hasn't updated yet even
                // though the user just granted permission — treat as a permission error.
                let nsError = error as NSError
                let isPermissionError = (nsError.domain == "RealtimeFFTAnalyzer" && (nsError.code == 1 || nsError.code == 2))
                                     || nsError.code == -10877
                if isPermissionError {
                    self.fftAnalyzer.microphonePermissionDenied = true
                }
            }
        }
        #endif

        // Restore persisted analysis settings.
        peakMinThreshold = TapDisplaySettings.peakMinThreshold
        minFrequency  = TapDisplaySettings.analysisMinFrequency
        maxFrequency  = TapDisplaySettings.analysisMaxFrequency

        // Restore persisted tap detection settings.
        tapDetectionThreshold = TapDisplaySettings.tapDetectionThreshold

        // Load any previously saved measurements from the Documents directory.
        loadPersistedMeasurements()

        setupSubscriptions()
    }

    // MARK: - Combine Setup

    /// Wires up Combine subscriptions to ``fftAnalyzer``'s published properties.
    ///
    /// The wiring is:
    /// 1. **FFT magnitudes + peakMagnitude** — drives ``analyzeMagnitudes(_:frequencies:peakMagnitude:)``
    ///    for peak *analysis* (~0.7 Hz). This is the only place a genuine FFT peak-bin magnitude is used.
    /// 2. **rmsLevelHandler (fast, audio thread → main, ~43 Hz)** — the per-buffer RMS level *and its
    ///    audio-clock timestamp*, hopped to the main queue. It drives BOTH `detectTap(...)` (the per-chunk
    ///    rising-edge detector — guitar vs the ABSOLUTE threshold, plate/brace vs the noise-floor-RELATIVE
    ///    threshold) and ``trackDecayFast(inputLevel:audioTime:)`` (ring-out tracking). Carrying the audio
    ///    time with the sample keeps both invariant to main-queue scheduling under load. The long-window
    ///    FFT is unreliable for short transient taps, so no mode detects from the FFT-rate path any more.
    /// 3. **routeChangeRestartCount** — triggers ``handleRouteChangeRestart()`` when the audio
    ///    engine restarts after a device/route change.
    func setupSubscriptions() {
        // Wire the raw-sample handler for gated FFT capture (called on the audio queue).
        fftAnalyzer.rawSampleHandler = { [weak self] samples, sampleRate in
            self?.accumulateGatedSamples(samples, sampleRate: sampleRate)
        }

        // Wire the audio-queue level-crossing handler.
        // When the input level crosses the threshold on the audio queue, start
        // the gated capture immediately — seeding gatedAccumBuffer with the
        // pre-roll and setting gatedCaptureActive = true — so that no audio
        // buffers are lost between the threshold crossing and the main thread
        // eventually running startGuitarGatedCapture() / startGatedCapture().
        // The main-thread call then only sets up the safety timeout (it skips
        // re-seeding because it sees gatedCaptureActive is already true).
        fftAnalyzer.levelCrossingHandler = { [weak self] in
            guard let self = self else { return }
            let mt = TapDisplaySettings.measurementType
            self.mpmLock.lock()
            if mt == .plate || mt == .brace {
                // Guard: only start a capture when we're actually in a
                // capturing phase.  Before file playback starts the phase
                // is still .notStarted — mic audio can trigger a spurious
                // level crossing in that window.  After playback ends the
                // phase is .complete — mic restart can trigger another.
                let phase = self.materialTapPhase
                guard phase.isCapturing else {
                    self.mpmLock.unlock()
                    TAP_DEBUG("levelCrossing", "SKIPPED — phase \(phase) is not capturing")
                    return
                }

                // File-playback deferred path: if a previous capture has
                // completed on the audio queue and its finishGatedFFTCapture
                // dispatch is still pending on the main thread, starting a
                // new gatedCaptureActive here would cascade — the new capture
                // fills before the main thread can advance the phase, so it
                // runs under the stale phase.  Instead, just snapshot the
                // pre-roll so the main-thread startGatedCapture can seed
                // from the correct audio position when it eventually runs.
                if self.fftAnalyzer.isPlayingFile
                    && self.pendingLevelCrossingPreRoll == nil
                    && !self.gatedCaptureActive
                    && self.lastLevelCrossingCaptureID == self.gatedCaptureID {
                    // A previous fast-start capture has completed
                    // (lastLevelCrossingCaptureID == gatedCaptureID) but its
                    // finishGatedFFTCapture dispatch hasn't run on the main
                    // thread yet.  Defer: snapshot pre-roll for main-thread
                    // startGatedCapture consumption.
                    self.pendingLevelCrossingPreRoll = self.preRollBuffer
                    let preRollCount = self.preRollBuffer.count
                    let profile = self.captureWindowProfile(self.preRollBuffer, label: "DEFERRED_PREROLL")
                    self.mpmLock.unlock()
                    TAP_DEBUG("levelCrossing", "DEFERRED — snapshot pre-roll (\(preRollCount) samples) for main-thread startGatedCapture\n\(profile)")
                    return
                }
            }
            self.gatedCaptureID += 1
            self.lastLevelCrossingCaptureID = self.gatedCaptureID
            self.gatedAccumBuffer = self.preRollBuffer
            if mt == .plate || mt == .brace {
                // Plate/brace: use the current phase and 500 ms window
                // (with a 400 ms FFT input extracted from it after onset
                // alignment — see gatedCaptureDuration / gatedFFTWindowDuration).
                self.gatedCapturePhase = self.materialTapPhase
                self.gatedCaptureSamples = Int(self.mpmSampleRate * TapToneAnalyzer.gatedCaptureDuration)

                // Keep the pre-roll even when it contains digital silence
                // (e.g. inter-tap gaps in a concatenated playback file).
                // The pre-roll positions the tap transient at ~sample 4800
                // of the 32768-sample Hann window, matching the live-capture
                // weighting.  Discarding it shifts the transient to sample 0
                // where the Hann weight is ~0, distorting magnitudes by
                // several dB.
            } else {
                // Guitar: nil phase sentinel, fftSize window.
                self.gatedCapturePhase = nil
                self.gatedCaptureSamples = self.fftAnalyzer.fftSize
            }
            self.gatedCaptureActive = true
            self.pendingLevelCrossingPreRoll = nil  // consumed by direct start
            let preRollCount = self.gatedAccumBuffer.count
            let target = self.gatedCaptureSamples
            let profile = self.captureWindowProfile(self.gatedAccumBuffer, label: "FASTSTART_PREROLL")
            self.mpmLock.unlock()
            TAP_DEBUG("levelCrossing", "Gated capture started on audio queue | mode=\(mt) pre-roll \(preRollCount) samples, target \(target)\n\(profile)")
        }
        fftAnalyzer.levelCrossingThreshold = tapDetectionThreshold

        // Wire the pre-mic-restart handler so any active gated capture is
        // zero-padded and completed before mic noise can fill the remaining
        // window.  Mirrors Python _on_pre_mic_restart callback.
        fftAnalyzer.preMicRestartHandler = { [weak self] in
            self?.flushGatedCaptureOnFileEnd()
        }

        // Re-initialize the pre-roll ring buffer after the mic engine stops
        // in startFromFile.  Between startTapSequence (which clears
        // preRollBuffer) and startFromFile (which stops the engine), mic
        // audio leaks into the ring buffer via accumulateGatedSamples.
        //
        // Clear the pre-roll buffer after the engine stops and the audio queue
        // is drained, so any mic noise that leaked in between startTapSequence
        // (which clears preRollBuffer) and the engine stop is flushed.
        // Do NOT pre-fill with zeros — the buffer fills naturally with real
        // audio as file chunks arrive through accumulateGatedSamples.
        // Pre-filling with zeros dilutes the gated capture signal by ~50%,
        // suppressing the spectral magnitude by ~6 dB.
        fftAnalyzer.postEngineStopHandler = { [weak self] in
            guard let self else { return }
            TAP_DEBUG("file_playback", "POST_ENGINE_STOP_HANDLER | mpmSampleRate=\(Int(self.mpmSampleRate)) preRollBefore=\(self.preRollBuffer.count)")
            self.mpmLock.lock()
            self.preRollBuffer = []
            // Reset capture IDs so the deferred level-crossing guard
            // (lastLevelCrossingCaptureID == gatedCaptureID) won't match
            // on the first file tap due to stale IDs from a prior live capture.
            self.lastLevelCrossingCaptureID = -1
            self.gatedCaptureID = 0
            self.pendingLevelCrossingPreRoll = nil
            self.mpmLock.unlock()
            TAP_DEBUG("file_playback", "POST_ENGINE_STOP_HANDLER_DONE | preRollAfter=\(self.preRollBuffer.count)")
        }

        // Slow path: full FFT frame → onFftFrame (in +TapDetection.swift),
        // which delegates to analyzeMagnitudes for peak analysis.  The entry-
        // point method placement mirrors Python's on_fft_frame in
        // tap_tone_analyzer_tap_detection.py.
        fftAnalyzer.$magnitudes
            .combineLatest(fftAnalyzer.$frequencies, fftAnalyzer.$peakMagnitude)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] magnitudes, frequencies, peakMag in
                self?.onFftFrame(magnitudes: magnitudes, frequencies: frequencies, peakMagnitude: peakMag)
            }
            .store(in: &cancellables)

        // Direct RMS callback — mirrors Python's
        //   proc_thread.rmsLevelChanged.connect(self._on_rms_level_changed)
        //
        // Called synchronously on the audio processing queue for every chunk.
        // Dispatches to main thread to call onRmsLevelChanged, matching
        // Python's Qt.QueuedConnection (cross-thread → main thread).
        //
        // Always use async dispatch to avoid deadlock.  A previous attempt
        // used DispatchQueue.main.sync during file playback so tap detection
        // ran in lockstep with the audio pump, but this deadlocks when the
        // user opens a second file: startFromFile (main thread) calls
        // audioProcessingQueue.sync{} to drain, while processRawSamples
        // (audioProcessingQueue) is stuck in DispatchQueue.main.sync waiting
        // for the blocked main thread.
        //
        // Async dispatch is safe because:
        //  - The main queue is serial, so RMS updates arrive in order.
        //  - processFileData sleeps chunkDuration between chunks, giving
        //    the main run loop time to drain queued blocks.
        //  - Tap detection sees the same sequence of values, just with
        //    negligible (~1 chunk) latency.
        fftAnalyzer.rmsLevelHandler = { [weak self] levelDB, audioTime in
            DispatchQueue.main.async { [weak self] in
                // audioTime is THIS chunk's audio timestamp, captured on the audio thread. It must be
                // carried across the hop — the audio thread races ahead of the main queue, so reading
                // fftAnalyzer.audioElapsed here would give a LATER time and silently skip the warm-up.
                self?.onRmsLevelChanged(levelDB, audioTime: audioTime)
                // Ring-out decay tracking rides the SAME carried audioTime, so it is stamped in audio
                // time (load-invariant) rather than with Date() at delivery. It self-gates on
                // isTrackingDecay and runs OUTSIDE onRmsLevelChanged's isDetecting guard — the ring-out
                // continues past measurement completion, which is exactly the window we measure.
                self?.trackDecayFast(inputLevel: levelDB, audioTime: audioTime)
            }
        }

        // Audio route change → reinitialise detection state after the engine restarts.
        fftAnalyzer.$routeChangeRestartCount
            .dropFirst()  // Ignore the initial published value (0).
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleRouteChangeRestart()
            }
            .store(in: &cancellables)

        // ── Input-clipping override ──────────────────────────────────────
        // When fftAnalyzer.isClipping toggles, swap the displayed
        // statusMessage between the analyzer's intended message
        // (preserved in latestRealStatus) and a remediation warning.
        // Mirrors Python `_set_clipping`.
        fftAnalyzer.$isClipping
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyStatusOverrides()
            }
            .store(in: &cancellables)

        // ── Dead-input override ──────────────────────────────────────────
        // Same mechanism as clipping, higher priority. Mirrors Python.
        fftAnalyzer.$inputAppearsDead
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyStatusOverrides()
            }
            .store(in: &cancellables)

        // ── Track the latest analyzer-set status ─────────────────────────
        // Every write to statusMessage triggers this sink.  Writes that match
        // the clipping warning sentinel are self-writes from the override
        // above and are ignored; all other writes are saved as the most
        // recent "real" status so that toggling clipping off restores the
        // correct message.  Mirrors Python `_set_status_message`.
        $statusMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                guard let self = self else { return }
                guard newValue != TapToneAnalyzer.clippingWarningStatus,
                      newValue != TapToneAnalyzer.deadInputStatus else { return }
                self.latestRealStatus = newValue
                // If an override is currently active, immediately re-apply it so the
                // analyzer's message doesn't briefly flash.
                self.applyStatusOverrides()
            }
            .store(in: &cancellables)
    }

    /// Resolves the displayed status against the active input-condition overrides.
    ///
    /// One place decides precedence — dead input, then clipping, then whatever the
    /// analyzer last set — so the two override sinks cannot fight each other or leave
    /// a stale warning on screen after its condition clears.
    func applyStatusOverrides() {
        let resolved: String
        if fftAnalyzer.inputAppearsDead {
            resolved = TapToneAnalyzer.deadInputStatus
        } else if fftAnalyzer.isClipping {
            resolved = TapToneAnalyzer.clippingWarningStatus
        } else {
            resolved = latestRealStatus
        }
        if statusMessage != resolved { statusMessage = resolved }
    }

    // MARK: - Route Change Handling

    /// Responds to an audio engine restart triggered by a device or route change.
    ///
    /// Temporarily disables tap detection, resets the warm-up timer, and re-enables
    /// detection 3 seconds later (after the 65 536-sample FFT window has filled with
    /// valid post-restart data).  If detection was active before the route change it is
    /// restored; otherwise the analyzer returns to the "Ready" state.
    ///
    /// - Important: The 3-second settle delay is conservative to ensure `peakMagnitude`
    ///   reflects real audio data rather than silence or the engine startup transient
    ///   before `isAboveThreshold` is re-anchored.
    func handleRouteChangeRestart() {
        gtLog("🔄 TapToneAnalyzer: Handling route change restart - resetting detection state")

        let wasDetecting = (detectionState == .listening)

        // Disable the New Tap and Resume buttons while reinitialising.
        isReadyForDetection = false
        // Stand the detector down only if it was listening.  A sequence paused before the
        // route change must still be paused after it, so Resume picks up where it left off —
        // which the old boolean pair expressed by clearing `isDetecting` alone.
        if wasDetecting { detectionState = .idle }

        // Reset the warm-up timer so the new engine session starts cleanly.
        warmupStartAudioTime = fftAnalyzer.audioElapsed

        // Pre-set isAboveThreshold = true so the first FFT frame does not fire a false
        // rising edge.  The actual value will be corrected after the settle delay.
        isAboveThreshold = true

        // Freeze the display on the last good spectrum while the pipeline refills with
        // valid data from the new device.  This prevents the transitional noise/silence
        // from the device switch showing as a bogus live waveform.
        // Blank only if a LIVE spectrum is on screen. `displayMode == .live` was the old test and
        // it is wrong: no completion path sets `.frozen`, so a finished measurement is still
        // `.live` and was being wiped. `isMeasurementComplete` is the field that actually says
        // whether what you are looking at is a result (#17 F35).
        let wasShowingLive = !isMeasurementComplete && displayMode != .comparison
        if wasShowingLive {
            // Show nothing during the settle rather than the old device's spectrum, which would be
            // confusing (wrong noise floor, wrong shape). The flag is the whole mechanism — no
            // `displayMode` write, so a completed or loaded measurement is untouched.
            isSettling = true
            // Clear peak annotations so they don't float on a blank chart during settle.
            allPeaks = []
            identifiedModes = []
        }

        // Remember what the status said BEFORE the transient replaces it. When the settle ends,
        // `statusAfterSettle()` returns nil for the states whose status is a result announcement
        // rather than a prompt — and "leave it alone" has to mean restoring THIS, not leaving the
        // transient up forever, which is what it meant on the first pass (#17 F33).
        //
        // `latestRealStatus`, NOT `statusMessage`: the latter is the OVERRIDE-RESOLVED string, so a
        // route change while the input is clipping or dead preserved the warning sentinel and put it
        // back as though the analyzer had set it. The override layer re-resolves on its own from the
        // real status, so the real status is what has to survive the settle (#17 F37).
        statusBeforeSettle = latestRealStatus
        statusMessage = "Audio device changed - reinitializing..."

        // Wait for the FFT pipeline to fill with valid post-restart data (~1.36 s for
        // 65 536 samples at 48 kHz).  Use 3 s: the extra margin covers the HALC
        // startup transient that sometimes appears 2–2.5 s after a device hot-swap
        // when the audio unit requires an internal recovery restart.
        let fftSettleTime: TimeInterval = 3.0
        DispatchQueue.main.asyncAfter(deadline: .now() + fftSettleTime) { [weak self] in
            guard let self = self else { return }
            guard self.fftAnalyzer.isRunning else { return }

            // Wait for the next published FFT frame before re-anchoring detection
            // and unfreezing the display.  This ensures both happen on the same
            // frame — the first one the user actually sees — preventing a false
            // rising edge caused by a transient that arrives between the settle
            // timer firing and the re-anchor.  isAboveThreshold stays true
            // (blocking detection) until that frame arrives.
            self.fftAnalyzer.$magnitudes
                .dropFirst()   // skip the currently-published value
                .first()       // fire exactly once on the next new publication
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }

                    // Re-anchor isAboveThreshold to the level of the first frame
                    // that is actually displayed, so the hysteresis detector starts
                    // in the correct state and cannot fire a spurious rising edge.
                    let currentPeakMag = self.fftAnalyzer.peakMagnitude
                    self.isAboveThreshold = (currentPeakMag > self.tapDetectionThreshold)

                    if wasShowingLive { self.isSettling = false }

                    self.isReadyForDetection = true

                    if wasDetecting { self.detectionState = .listening }
                    // Derive the status from the state we are now in; where that is a result
                    // announcement rather than a prompt, put back what was there before the settle.
                    self.statusMessage = self.restoredStatus(before: self.statusBeforeSettle ?? "Ready")
                    self.statusBeforeSettle = nil
                    gtLog("🔄 TapToneAnalyzer: Detection re-enabled after route change (current level: \(currentPeakMag) dB, threshold: \(self.tapDetectionThreshold) dB, above threshold: \(self.isAboveThreshold))")
                }
                .store(in: &self.cancellables)
        }
    }
}
