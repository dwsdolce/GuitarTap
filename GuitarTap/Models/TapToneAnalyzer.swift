//
//  TapToneAnalyzer.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

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
/// ## Three-Layer Peak Selection (Plate / Brace)
///
/// For material measurements the app tracks three independent peak-selection signals and
/// resolves them with strict priority order:
///
/// 1. **User override** (`userSelectedLongitudinalPeakID` / Cross / Flc) — set when the user
///    explicitly taps a peak row in the results panel.  Takes highest priority.
/// 2. **Phase-stored peak** (`selectedLongitudinalPeak` / Cross / Flc) — set automatically
///    when a gated-FFT phase completes and the dominant peak is identified.
/// 3. **Auto-selected ID** (`autoSelectedLongitudinalPeakID` / Cross / Flc) — intermediate
///    result set during HPS analysis before the phase is finalised.
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
/// - The capture window (``gatedCaptureDuration``: 400 ms) then accumulates the ring-out.
/// - When the window closes, ``finishGatedFFTCapture`` runs a dedicated FFT and routes
///   results to the appropriate phase handler.
///
/// ## Tap Detection Strategy
///
/// | Mode | Signal used | Reason |
/// |------|-------------|--------|
/// | Guitar | FFT `peakMagnitude` (~1 Hz) | Slower but includes full spectrum analysis |
/// | Plate / Brace | `inputLevelDB` (~10 Hz RMS) | Long-window FFT dilutes short transients by ~15 dB |
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
    /// audio hardware.  Use ``playFileForTesting(url:measurementType:numberOfTaps:)``
    /// to feed a WAV file through the pipeline.
    ///
    /// The FFT size is the class-level constant in `RealtimeFFTAnalyzer`
    /// (65 536); it is not configurable per-instance.
    ///
    /// Mirrors Python ``TapToneAnalyzer.for_testing()``.
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
    /// Mirrors Python ``TapToneAnalyzer.play_file_for_testing()``.
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
    func playFileForTesting(url: URL, measurementType: MeasurementType, numberOfTaps: Int = 1, calibrationURL: URL? = nil, plateTapPhase: MaterialTapPhase? = nil) throws {
        // 1. Configure measurement type and tap count.
        TapDisplaySettings.measurementType = measurementType
        self.numberOfTaps = numberOfTaps

        // 1b. If a calibration file was provided, parse it and temporarily
        //     override the active calibration on the FFT analyzer.
        if let calURL = calibrationURL {
            let cal = try CalibrationFileParser.parse(url: calURL)
            fftAnalyzer.setTemporaryCalibration(cal)
        }

        // 2. Start the tap sequence with warmup skipped (deterministic file audio).
        //    When plateTapPhase is provided, pass it as initialPhase so both the
        //    synchronous setup and the async housekeeping block use the correct
        //    phase — preventing the async block from resetting the phase back to
        //    .capturingLongitudinal after the override.
        startTapSequence(skipWarmup: true, initialPhase: plateTapPhase)

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

        let done = DispatchSemaphore(value: 0)
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
        while done.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
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
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            }
        } else {
            while !isMeasurementComplete && Date() < deadline {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
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
            recalculateFrozenPeaksIfNeeded()
        }
    }

    /// Lower bound of the analysis frequency range, in Hz.
    ///
    /// Frequencies outside `minFrequency...maxFrequency` are excluded from peak detection.
    @Published var minFrequency: Float = TapDisplaySettings.analysisMinFrequency

    /// Upper bound of the analysis frequency range, in Hz.
    @Published var maxFrequency: Float = TapDisplaySettings.analysisMaxFrequency

    /// Maximum number of peaks to detect and display.
    ///
    /// When more candidate peaks exist, the strongest ones by magnitude are kept.
    /// Persisted in ``TapDisplaySettings``.
    @Published var maxPeaks: Int = TapDisplaySettings.maxPeaks

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
            if isDetecting && currentTapCount == 0 {
                statusMessage = numberOfTaps == 1 ? "Tap the guitar..." : "Tap the guitar \(numberOfTaps) times..."
            }
            // If the user reduces numberOfTaps to at or below the taps already captured
            // mid-sequence, treat the already-captured taps as sufficient and process them.
            if isDetecting && currentTapCount >= numberOfTaps && currentTapCount > 0 {
                isDetecting = false
                statusMessage = "All taps captured. Processing..."
                DispatchQueue.main.asyncAfter(deadline: .now() + captureWindow) { [weak self] in
                    self?.processMultipleTaps()
                }
            }
            // If the user changes tap count manually, the loaded-settings warning
            // is no longer relevant for this setting.
            if numberOfTaps != loadedNumberOfTaps {
                showLoadedSettingsWarning = false
            }
        }
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
            // Keep the audio-queue level-crossing threshold in sync so the
            // pre-roll snapshot fires at the same level as the main-thread detector.
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
    /// Persisted in ``TapDisplaySettings``.
    @Published var hysteresisMargin: Float = TapDisplaySettings.hysteresisMargin {
        didSet { TapDisplaySettings.hysteresisMargin = hysteresisMargin }
    }

    // MARK: - Published Results

    /// The most recently detected resonant peaks, updated after each completed tap sequence.
    @Published var currentPeaks: [ResonantPeak] = []

    /// Peak–mode pairs produced by classifying each entry in ``currentPeaks``.
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

    /// `true` for a single frame immediately after a tap rising edge is confirmed.
    ///
    /// Views observe this to flash the tap indicator.
    @Published var tapDetected: Bool = false

    /// `true` when tap detection is actively listening for taps.
    ///
    /// `false` after `stop()`, `reset()`, or while paused.
    /// Setting this property automatically arms or disarms the audio-queue
    /// level-crossing handler that snapshots the pre-roll buffer.
    @Published var isDetecting: Bool = false {
        didSet {
            TAP_DEBUG("isDetecting", "\(oldValue) → \(isDetecting) | isPlayingFile=\(fftAnalyzer.isPlayingFile)")
            if isDetecting && !oldValue {
                // false → true transition only: arm the audio-queue level-
                // crossing handler so it can start the gated capture at the
                // exact buffer that crosses the threshold (no main-thread
                // delay).
                //
                // We deliberately ignore true → true assignments (e.g. the
                // re-confirmation in startTapSequence's async block) so that
                // a capture already started by the audio queue between the
                // synchronous and async assignments is not disrupted.
                TAP_DEBUG("isDetecting", "ARMING level crossing (false→true)")
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
                // because the main-thread tap detection (which triggers
                // isDetecting = false) runs after the audio-queue re-arm
                // but before the next tap's audio chunks are processed.
                if !fftAnalyzer.isPlayingFile {
                    TAP_DEBUG("isDetecting", "DISARMING level crossing (not playing file)")
                    fftAnalyzer.levelCrossingArmed = false
                } else {
                    TAP_DEBUG("isDetecting", "SKIPPED disarm (playing file)")
                }
            }
        }
    }

    /// `true` when the tap sequence is paused (spectrum stays live, detection is off).
    ///
    /// Distinct from `isDetecting = false` because pause preserves the in-progress
    /// tap count, while a full stop resets it.
    @Published var isDetectionPaused: Bool = false

    /// `false` during the brief period after an audio route change while the engine
    /// reinitialises.  The UI disables the New Tap and Resume buttons while this is `false`.
    @Published var isReadyForDetection: Bool = true

    /// Number of taps captured so far in the current multi-tap sequence.
    @Published var currentTapCount: Int = 0

    /// Fractional progress of the current multi-tap sequence (0.0–1.0).
    ///
    /// `currentTapCount / numberOfTaps`.  Used by the progress bar.
    @Published var tapProgress: Float = 0.0

    /// Human-readable status string shown in the status bar and instructions area.
    @Published var statusMessage: String = "Tap the guitar to begin"

    /// The most recent analyzer-set status message, preserved while the
    /// clipping override is active so it can be restored when clipping clears.
    /// Updated by a Combine sink on `$statusMessage` (see setupSubscriptions).
    /// Mirrors Python `_latest_real_status`.
    var latestRealStatus: String = "Tap the guitar to begin"

    /// Sentinel string used to detect (and ignore) self-writes to
    /// `statusMessage` performed by the clipping-override path, so the
    /// `$statusMessage` sink doesn't store the warning into
    /// `latestRealStatus`.  Mirrors Python's identical override.
    static let clippingWarningStatus = "⚠ Input clipping — reduce mic gain"

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

    /// Per-peak user mode label overrides.
    ///
    /// An empty dictionary means all peaks use auto-classification.
    /// - SeeAlso: ``UserAssignedMode``
    @Published var peakModeOverrides: [UUID: UserAssignedMode] = [:]

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
        switch peakModeOverrides[peak.id] ?? .auto {
        case .auto:
            return peakMode(for: peak).displayName
        case .assigned(let label):
            return label
        }
    }

    /// Sets or clears a mode override for a specific peak, thread-safely.
    ///
    /// If called from a background thread, the update is dispatched to the main queue.
    ///
    /// - Parameters:
    ///   - override: The ``UserAssignedMode`` to apply.
    ///   - peakID: UUID of the target peak.
    func setModeOverride(_ override: UserAssignedMode, for peakID: UUID) {
        if Thread.isMainThread {
            peakModeOverrides[peakID] = override
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakModeOverrides[peakID] = override
            }
        }
    }

    /// Returns `true` when the given peak has a manually-assigned (non-auto) mode label.
    ///
    /// - Parameter peakID: UUID of the peak to check.
    func hasManualOverride(for peakID: UUID) -> Bool {
        guard let override = peakModeOverrides[peakID] else { return false }
        if case .assigned = override { return true }
        return false
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
        }
        userHasModifiedPeakSelection = true
    }

    /// Marks all current peaks as selected.
    func selectAllPeaks() {
        selectedPeakIDs = Set(currentPeaks.map { $0.id })
        userHasModifiedPeakSelection = true
    }

    /// Clears the selection set so no peaks are marked as significant.
    func selectNoPeaks() {
        selectedPeakIDs.removeAll()
        userHasModifiedPeakSelection = true
    }

    /// Advances ``annotationVisibilityMode`` to the next state in the cycle:
    /// `all → selected → none → all`, and persists the new value to UserDefaults.
    func cycleAnnotationVisibility() {
        annotationVisibilityMode = annotationVisibilityMode.next
        TapDisplaySettings.annotationVisibilityMode = annotationVisibilityMode
    }

    /// The subset of ``currentPeaks`` that should be rendered as annotations given
    /// the current ``annotationVisibilityMode``.
    ///
    /// In guitar mode, peaks classified as Unknown are excluded when
    /// ``TapDisplaySettings/showUnknownModes`` is `false`, keeping the chart
    /// consistent with the Analysis Results panel.
    var visiblePeaks: [ResonantPeak] {
        let candidates: [ResonantPeak]
        switch annotationVisibilityMode {
        case .all:      candidates = currentPeaks
        case .selected: candidates = currentPeaks.filter { selectedPeakIDs.contains($0.id) }
        case .none:     return []
        }
        // Filter unknown-mode peaks in guitar mode when the setting is off
        guard TapDisplaySettings.measurementType.isGuitar,
              !TapDisplaySettings.showUnknownModes else {
            return candidates
        }
        return candidates.filter { GuitarMode.isKnown(frequency: $0.frequency) }
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
    /// `reset()`, `startTapSequence()`, and `newMeasurement()`.
    @Published var isMeasurementComplete: Bool = false {
        didSet {
            // A successful new tap clears the loaded-settings warning — the user
            // has now captured a measurement with the current (loaded) settings and
            // knows what they are.
            if isMeasurementComplete { showLoadedSettingsWarning = false }
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
    /// Part of the three-layer peak-selection system; overridden by ``selectedLongitudinalPeak``
    /// once the phase finalises, and further overridden by ``userSelectedLongitudinalPeakID``
    /// if the user makes a manual choice.
    @Published var autoSelectedLongitudinalPeakID: UUID?

    /// The dominant longitudinal peak stored when the longitudinal phase finalises.
    ///
    /// Second priority in the three-layer selection: used when no user override exists.
    @Published var selectedLongitudinalPeak: ResonantPeak?

    /// Explicit user override for the longitudinal peak selection.
    ///
    /// Highest priority in the three-layer selection.  Set when the user taps a peak row
    /// in the results panel.
    @Published var userSelectedLongitudinalPeakID: UUID?

    /// Intermediate auto-selected UUID from HPS analysis of the cross-grain phase.
    @Published var autoSelectedCrossPeakID: UUID?

    /// The dominant cross-grain peak stored when the cross-grain phase finalises.
    @Published var selectedCrossPeak: ResonantPeak?

    /// Explicit user override for the cross-grain peak selection.
    @Published var userSelectedCrossPeakID: UUID?

    /// Peaks detected from the FLC (diagonal/shear) tap.
    @Published var flcPeaks: [ResonantPeak] = []

    /// Averaged FFT spectrum from the FLC tap, once captured.
    @Published var flcSpectrum: (magnitudes: [Float], frequencies: [Float])?

    /// Intermediate auto-selected UUID from HPS analysis of the FLC phase.
    @Published var autoSelectedFlcPeakID: UUID?

    /// The dominant FLC peak stored when the FLC phase finalises.
    @Published var selectedFlcPeak: ResonantPeak?

    /// Explicit user override for the FLC peak selection.
    @Published var userSelectedFlcPeakID: UUID?

    // MARK: - Effective Peak Selection (Three-Layer Resolution)

    /// Resolved UUID for the longitudinal (fL) peak, applying three-layer priority.
    ///
    /// Priority order: ``userSelectedLongitudinalPeakID`` > ``selectedLongitudinalPeak``
    /// > ``autoSelectedLongitudinalPeakID``.
    ///
    /// Views and material-property calculations should read this property rather than
    /// consulting the three underlying sources directly.
    var effectiveLongitudinalPeakID: UUID? {
        userSelectedLongitudinalPeakID ?? selectedLongitudinalPeak?.id ?? autoSelectedLongitudinalPeakID
    }

    /// Resolved UUID for the cross-grain (fC) peak.
    ///
    /// Priority order: ``userSelectedCrossPeakID`` > ``selectedCrossPeak``
    /// > ``autoSelectedCrossPeakID``.
    var effectiveCrossPeakID: UUID? {
        userSelectedCrossPeakID ?? selectedCrossPeak?.id ?? autoSelectedCrossPeakID
    }

    /// Resolved UUID for the FLC (diagonal/shear) peak.
    ///
    /// Priority order: ``userSelectedFlcPeakID`` > ``selectedFlcPeak``
    /// > ``autoSelectedFlcPeakID``.
    var effectiveFlcPeakID: UUID? {
        userSelectedFlcPeakID ?? selectedFlcPeak?.id ?? autoSelectedFlcPeakID
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
    /// Hysteresis margin loaded from a saved measurement, in dB.
    @Published var loadedHysteresisMargin: Float?
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

    /// Plate dimensions loaded from a saved measurement (length in mm).
    @Published var loadedPlateLength: Float?
    /// Plate width loaded from a saved measurement, in mm.
    @Published var loadedPlateWidth: Float?
    /// Plate thickness loaded from a saved measurement, in mm.
    @Published var loadedPlateThickness: Float?
    /// Plate mass loaded from a saved measurement, in grams.
    @Published var loadedPlateMass: Float?
    /// Guitar body length for Gore calculation loaded from a saved measurement, in mm.
    @Published var loadedGuitarBodyLength: Float?
    /// Guitar body width for Gore calculation loaded from a saved measurement, in mm.
    @Published var loadedGuitarBodyWidth: Float?
    /// Plate stiffness preset loaded from a saved measurement.
    @Published var loadedPlateStiffnessPreset: PlateStiffnessPreset?
    /// Custom plate stiffness loaded from a saved measurement.
    @Published var loadedCustomPlateStiffness: Float?
    /// FLC measurement flag loaded from a saved measurement.
    @Published var loadedMeasureFlc: Bool?
    /// Brace length loaded from a saved measurement, in mm.
    @Published var loadedBraceLength: Float?
    /// Brace width loaded from a saved measurement, in mm.
    @Published var loadedBraceWidth: Float?
    /// Brace height loaded from a saved measurement, in mm.
    @Published var loadedBraceThickness: Float?
    /// Brace mass loaded from a saved measurement, in grams.
    @Published var loadedBraceMass: Float?

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
    @Published var comparisonSpectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String, peaks: [ResonantPeak], guitarType: GuitarType?)] = []

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

    /// Target duration of the gated capture window, in seconds.
    ///
    /// 400 ms captures the full plate ring-out while rejecting post-decay noise.
    static let gatedCaptureDuration: Double = 0.400

    /// Number of samples in one gated capture window at the current hardware sample rate.
    /// Target size of the gated-capture window, in samples.
    ///
    /// Set at capture-start time so the same accumulator infrastructure can serve
    /// different capture lengths: plate/brace uses ``gatedCaptureDuration`` (~400 ms);
    /// guitar uses the full ``fftSize`` so the resulting spectrum has the same
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
    /// Python's ``_gated_capture_phase = None``.
    var gatedCapturePhase: MaterialTapPhase? = nil

    /// Most recent hardware sample rate, in Hz.
    ///
    /// Set on the audio processing queue when a new audio buffer arrives.
    var mpmSampleRate: Double = 48000

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
    /// At ~10 ms audio buffer updates, α = 0.05 gives a time constant τ ≈ 190 ms:
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

    /// Combine cancellable storage for FFT and input-level subscriptions.
    var cancellables = Set<AnyCancellable>()

    /// History of (timestamp, inputLevelDB) samples used by the decay tracker.
    var peakMagnitudeHistory: [(time: Date, magnitude: Float)] = []

    /// Wall-clock time of the most recent detected tap.
    var lastTapTime: Date?

    /// Edge-triggered guard for the cooldown TAP_DEBUG line — set true the first
    /// chunk inside the cooldown window so we log once per cooldown rather than
    /// ~22 times.  Mirrors Python `_cooldown_logged`.
    var cooldownLogged: Bool = false

    /// Input level (dBFS) at the moment the most recent tap was detected.
    ///
    /// Used as the reference magnitude for ring-out time computation.
    var tapPeakLevel: Float = -100

    /// Minimum inter-tap interval to prevent double-trigger artefacts, in seconds.
    let tapCooldown: TimeInterval = 0.5

    /// Wall-clock time when `start()` or `startTapSequence()` was called.
    ///
    /// Used to enforce the warm-up period.
    var analyzerStartTime: Date?

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
    /// on a **rising edge** (transition from `false` to `true`).
    var isAboveThreshold: Bool = false

    /// Timer that bounds the ring-out decay tracking window.
    var decayTrackingTimer: Timer?

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
        // TapToneAnalyzer.start() — so analyzerStartTime would never be set and
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
        hysteresisMargin      = TapDisplaySettings.hysteresisMargin

        // Load any previously saved measurements from the Documents directory.
        loadPersistedMeasurements()

        setupSubscriptions()
    }

    // MARK: - Combine Setup

    /// Wires up Combine subscriptions to ``fftAnalyzer``'s published properties.
    ///
    /// Four subscriptions are created:
    /// 1. **FFT magnitudes + peakMagnitude** — drives ``analyzeMagnitudes(_:frequencies:peakMagnitude:)``
    ///    for peak detection and guitar-mode tap detection (~1 Hz).
    /// 2. **inputLevelDB (fast)** — drives ``trackDecayFast(inputLevel:)`` for ring-out tracking (~10 Hz).
    /// 3. **inputLevelDB (fast, plate/brace only)** — drives `detectTap(peakMagnitude:magnitudes:frequencies:)`
    ///    for plate/brace mode, where the long-window FFT is unreliable for short transient taps.
    /// 4. **routeChangeRestartCount** — triggers ``handleRouteChangeRestart()`` when the audio
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
                    self.mpmLock.unlock()
                    TAP_DEBUG("levelCrossing", "DEFERRED — snapshot pre-roll (\(preRollCount) samples) for main-thread startGatedCapture")
                    return
                }
            }
            self.gatedCaptureID += 1
            self.lastLevelCrossingCaptureID = self.gatedCaptureID
            self.gatedAccumBuffer = self.preRollBuffer
            if mt == .plate || mt == .brace {
                // Plate/brace: use the current phase and 400 ms window.
                self.gatedCapturePhase = self.materialTapPhase
                self.gatedCaptureSamples = Int(self.mpmSampleRate * TapToneAnalyzer.gatedCaptureDuration)

                // Keep the pre-roll even when it contains digital silence
                // (e.g. inter-tap gaps in a concatenated playback file).
                // The pre-roll positions the tap transient at ~sample 9600
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
            self.mpmLock.unlock()
            TAP_DEBUG("levelCrossing", "Gated capture started on audio queue | mode=\(mt) pre-roll \(preRollCount) samples, target \(target)")
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

        // Fast path: per-buffer input level → decay tracking (~10 Hz update).
        fftAnalyzer.$inputLevelDB
            .receive(on: DispatchQueue.main)
            .sink { [weak self] levelDB in
                self?.trackDecayFast(inputLevel: levelDB)
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
        fftAnalyzer.rmsLevelHandler = { [weak self] levelDB in
            DispatchQueue.main.async { [weak self] in
                self?.onRmsLevelChanged(levelDB)
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
            .sink { [weak self] clipping in
                guard let self = self else { return }
                if clipping {
                    self.statusMessage = TapToneAnalyzer.clippingWarningStatus
                } else {
                    self.statusMessage = self.latestRealStatus
                }
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
                guard newValue != TapToneAnalyzer.clippingWarningStatus else { return }
                self.latestRealStatus = newValue
                // If clipping is currently active, immediately re-override
                // so the analyzer's message doesn't briefly flash.
                if self.fftAnalyzer.isClipping {
                    self.statusMessage = TapToneAnalyzer.clippingWarningStatus
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Route Change Handling

    /// Responds to an audio engine restart triggered by a device or route change.
    ///
    /// Temporarily disables tap detection, resets the warm-up timer, and re-enables
    /// detection 2 seconds later (after the 65 536-sample FFT window has filled with
    /// valid post-restart data).  If detection was active before the route change it is
    /// restored; otherwise the analyzer returns to the "Ready" state.
    ///
    /// - Important: The 2-second settle delay is conservative to ensure `peakMagnitude`
    ///   reflects real audio data rather than silence or the engine startup transient
    ///   before `isAboveThreshold` is re-anchored.
    func handleRouteChangeRestart() {
        gtLog("🔄 TapToneAnalyzer: Handling route change restart - resetting detection state")

        let wasDetecting = isDetecting

        // Disable the New Tap and Resume buttons while reinitialising.
        isReadyForDetection = false
        isDetecting = false

        // Reset the warm-up timer so the new engine session starts cleanly.
        analyzerStartTime = Date()

        // Pre-set isAboveThreshold = true so the first FFT frame does not fire a false
        // rising edge.  The actual value will be corrected after the settle delay.
        isAboveThreshold = true
        tapDetected = false

        // Freeze the display on the last good spectrum while the pipeline refills with
        // valid data from the new device.  This prevents the transitional noise/silence
        // from the device switch showing as a bogus live waveform.
        // Only freeze if we were in live mode — don't disturb a frozen measurement result.
        let wasLive = (displayMode == .live)
        if wasLive {
            // Show a blank spectrum during the settle period rather than the old
            // device's spectrum, which would be confusing (wrong noise floor, wrong
            // shape).  Empty arrays signal the view to render nothing.
            setFrozenSpectrum(frequencies: [], magnitudes: [])
            displayMode = .frozen
            // Clear peak annotations so they don't float on a blank chart during settle.
            currentPeaks = []
            identifiedModes = []
        }

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

                    if wasLive {
                        self.setFrozenSpectrum(frequencies: [], magnitudes: [])
                        self.displayMode = .live
                    }

                    self.isReadyForDetection = true

                    if wasDetecting {
                        self.isDetecting = true
                        self.statusMessage = self.numberOfTaps == 1
                            ? "Tap the guitar..."
                            : "Tap the guitar \(self.numberOfTaps) times..."
                    } else {
                        self.statusMessage = "Ready"
                    }
                    gtLog("🔄 TapToneAnalyzer: Detection re-enabled after route change (current level: \(currentPeakMag) dB, threshold: \(self.tapDetectionThreshold) dB, above threshold: \(self.isAboveThreshold))")
                }
                .store(in: &self.cancellables)
        }
    }
}
