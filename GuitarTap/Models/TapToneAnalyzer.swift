//
//  TapToneAnalyzer.swift
//  GuitarTap
//
//  Created on 1/25/26.
//
// @parity audio/tap-analyzer tests=test/tap-decisions,test/tap-progress,test/effective-peak-id,test/tap-count-change

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
/// ## Material Peaks (Plate / Brace)
///
/// A material measurement's peaks are its identified peaks, one per phase: `selectedLongitudinalPeak`
/// / `selectedCrossPeak` / `selectedFlcPeak`, each the dominant peak of the phase's averaged
/// spectrum, stored when the phase completes (``materialIdentifiedPeaks`` lists them in phase
/// order). There is no per-peak selection and no other material peak state — `allPeaks` and
/// `selectedPeakIDs` are guitar-only. A wrong peak is fixed by redoing the phase.
///
/// ``effectiveLongitudinalPeakID``, ``effectiveCrossPeakID`` and ``effectiveFlcPeakID`` expose the
/// identified peaks' ids to views.
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
    /// subscriptions, the engine's `audioFrameHandler`) but no audio hardware.  Use ``playFile(url:calibrationURL:completion:)`` — the app's own Play File path —
    /// to feed a WAV file through the pipeline.
    ///
    /// The FFT size is the class-level constant in `RealtimeFFTAnalyzer`
    /// (65 536); it is not configurable per-instance.
    ///
    /// Mirrors Python `TapToneAnalyzer.for_testing()`.
    static func forTesting(wallClock: WallClock = SystemWallClock()) -> TapToneAnalyzer {
        let fft = RealtimeFFTAnalyzer.forTesting()
        return TapToneAnalyzer(fftAnalyzer: fft, wallClock: wallClock)
    }

    // MARK: - Dependencies

    /// The underlying real-time FFT engine that delivers spectrum frames and input-level events.
    let fftAnalyzer: RealtimeFFTAnalyzer

    /// The wall clock the capture's safety timeout reads and schedules on — the system's in the app.
    let wallClock: WallClock

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
            // `armedPrompt()`, not `tapPrompt()`: the latter is the GUITAR prompt. At the start of a
            // plate or brace sequence the control is still unlocked (no tap has been captured), and
            // the prompt must stay "Ready for fL tap (×3 each for L, C)", not "Tap the guitar 3 times...".
            if isDetecting && currentTapCount == 0 {
                statusMessage = armedPrompt()
            }
            // NOTE: there is deliberately NO "reduce the count mid-sequence → finalise with the taps
            // already captured" branch here. The Taps stepper is disabled the moment a sequence has a
            // tap — `.disabled(tap.currentTapCount > 0 && !tap.isMeasurementComplete)`, on every
            // stepper on every platform — so the count simply cannot change mid-sequence; to change
            // it you cancel first. Such a branch would also be a trap: `loadMeasurement` writes
            // `numberOfTaps`, so a load during a live sequence would kick off `processMultipleTaps()`
            // mid-load, guarded only by call ordering.
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
    /// status), the phase advances in ``acceptCurrentPhase``, and ``armedPrompt()``. All three say the
    /// same words for a phase, so resuming or changing the tap count never rewords the instruction
    /// the user is following.
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
            // capturingLongitudinal / notStarted. "fL", not "L", for plate as well.
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
    /// The status is a function of state, so it is derived rather than chosen from fixed strings:
    /// mid-sequence it counts the taps already captured, and a finished measurement keeps "Analysis
    /// complete! N peaks…". It says nothing at all where the status is a RESULT announcement rather
    /// than a live prompt, because a completed or loaded measurement's status is not re-derivable
    /// and must not be thrown away.
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
            // which the analyzer holds, so it is still derived.
            guard TapDisplaySettings.measurementType.isGuitar else { return nil }
            return armedPrompt()
        }
        return "Ready"
    }

    /// The status to show when a settle ends, given what the status said before it began.
    ///
    /// The whole decision in one pure function, so every edition can pin it: derive from state, and
    /// where the state's status is a result announcement rather than a prompt, put back what was
    /// there — so the "Audio device changed - reinitializing…" transient never stays up on a
    /// completed measurement.
    func restoredStatus(before: String) -> String {
        statusAfterSettle() ?? before
    }

    /// Guitar detection-loop status derived from the current state — the analyzer's
    /// equivalent of the web `setGuitarStatus(engineState)`.  `capturing == false` →
    /// the resting prompt (count 0) or the between-taps "…captured. Tap again…";
    /// `capturing == true` → the in-progress "Tap n/N capturing…" or, on the final tap,
    /// "All taps captured. Processing…".  (guitar mode keeps `currentTapCount ==
    /// capturedTaps.count`, so the provisional `+1` matches the old `capturedTaps.count + 1`.)
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

    /// After the LAST guitar tap, "All taps captured. Processing..." shows for this much AUDIO before the
    /// taps are averaged (``afterAudio(_:releasedAtFileEnd:_:)``, released at file end).
    let captureWindow: TimeInterval = 0.2

    /// Tap-detection threshold, in dBFS.
    ///
    /// For guitar mode this is an absolute FFT magnitude level.  For plate/brace mode it is
    /// combined with the noise-floor estimate to form a relative threshold.
    /// Persisted in ``TapDisplaySettings``.
    @Published var tapDetectionThreshold: Float = TapDisplaySettings.tapDetectionThreshold {
        didSet {
            TapDisplaySettings.tapDetectionThreshold = tapDetectionThreshold
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
    /// Held in ``peaks`` (``DetectedPeaks``), which alone announces a change to it.
    var allPeaks: [ResonantPeak] {
        get { peaks.allPeaks }
        set {
            peaks.allPeaks = newValue
            refreshDisplayedPeaks()
        }
    }

    /// The detected peaks — ``allPeaks``, ``peaksAbovePeakMin``, ``identifiedModes`` and ``selectedPeakIDs`` —
    /// published on their own: they change on every live frame while a sequence waits for a tap, and announced by
    /// the analyzer they would redraw every view that observes it at the frame rate.
    let peaks = DetectedPeaks()

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
    private(set) var peaksAbovePeakMin: [ResonantPeak] {
        get { peaks.peaksAbovePeakMin }
        set { peaks.peaksAbovePeakMin = newValue }
    }

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
    /// Held in ``peaks``, which alone announces a change to it.
    var identifiedModes: [(peak: ResonantPeak, mode: GuitarMode)] {
        get { peaks.identifiedModes }
        set { peaks.identifiedModes = newValue }
    }

    /// Ring-out time of the most recent guitar tap, in seconds — measured from its FFT window
    /// (``ringOutTime(_:from:to:sampleRate:threshold:)``).
    ///
    /// `nil` before a tap is captured, or when its level did not fall by `decayThreshold` dB within the
    /// window's audio.
    @Published var currentDecayTime: Float?

    /// All measurements saved during this session, ordered by save time.
    @Published var savedMeasurements: [TapToneMeasurement] = []

    /// The file this analyzer reads its library from and writes it to — ``measurementsFileURL``. A test
    /// gives an analyzer a file of its own, so suites running in parallel never write each other's.
    var libraryFileURL: URL = TapToneAnalyzer.measurementsFileURL

    /// Set when the library, or entries in it, could not be read at launch and it was kept aside — see
    /// ``setAsideUnreadableLibrary(at:)`` and ``keepCopyOfLibrary(at:unreadableCount:)``. The view shows it
    /// once in an alert and clears it.
    @Published var libraryLoadFailure: String?

    /// The library, or entries in it, could not be read and it could not be kept aside either, so it is
    /// never written this session: a save would replace the only copy of what it holds.
    var isLibraryWriteBlocked = false

    // MARK: - Published Detection State

    /// Whether the detector is listening, paused mid-sequence, or neither.
    ///
    /// One value rather than the `isDetecting` / `isDetectionPaused` pair it
    /// replaced: that pair could express "detecting AND paused", and every site
    /// touching either flag had to keep them consistent by hand.  Both remain
    /// available as computed reads below.
    @Published var detectionState: DetectionState = .idle {
        didSet {
            // Nothing to do for a same-value assignment: re-asserting the state the
            // detector is already in must not run the transition's work again.
            guard oldValue != detectionState else { return }
            TAP_DEBUG("detectionState", "\(oldValue.rawValue) → \(detectionState.rawValue) | complete=\(isMeasurementComplete) ready=\(isReadyForDetection) tapCount=\(currentTapCount)/\(numberOfTaps) capt=\(capturedTaps.count) phase=\(materialTapPhase) measType=\(TapDisplaySettings.measurementType) | isPlayingFile=\(fftAnalyzer.isPlayingFile)")
            // Brief call stack so we can see WHO changed the state (top 8 frames,
            // first one is the dispatch_wrap for swift property setters and is
            // skipped).  Strip the leading address columns to keep lines short.
            let frames = Thread.callStackSymbols.dropFirst().prefix(8)
                .map { $0.replacingOccurrences(of: "  +0x[0-9a-f]+", with: "", options: .regularExpression) }
                .joined(separator: " | ")
            TAP_DEBUG("detectionState.stack", frames)
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
    /// A flag of its own, not a `displayMode` value: `.frozen` means "a loaded measurement", and
    /// `displayMode` stays untouched during a settle, so a completed or loaded measurement keeps its
    /// spectrum and peaks. One flag for one fact.
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
    ///
    /// Every write by the analyzer is its latest real status, recorded here at the write — as
    /// Python's `_set_status_message` does — and then resolved against the input-condition
    /// overrides, so a write while the input is clipping or dead keeps the warning. The overrides'
    /// own writes (the warning strings) are not recorded. Re-assigning inside `didSet` does not
    /// call it again.
    // @parity state/status-message
    @Published var statusMessage: String = "Tap the guitar to begin" {
        didSet {
            guard statusMessage != TapToneAnalyzer.clippingWarningStatus,
                  statusMessage != TapToneAnalyzer.deadInputStatus,
                  statusMessage != TapToneAnalyzer.wrongDeviceStatus,
                  statusMessage != TapToneAnalyzer.couldNotRestartStatus,
                  statusMessage != TapToneAnalyzer.microphoneAccessStatus,
                  statusMessage != TapToneAnalyzer.couldNotStartStatus else { return }
            latestRealStatus = statusMessage
            applyStatusOverrides()
        }
    }

    /// Set true when the user tries to start a tap sequence (New Tap) while Dump Capture Audio is on
    /// but its folder can't be reached. The view shows a prompt — Change Location /
    /// Turn Off Saving / Cancel — and the sequence does not arm until it is resolved. macOS only.
    @Published var dumpFolderUnreachable: Bool = false

    /// A capture's audio waiting to be saved by Dump Capture Audio.
    struct CaptureRecording {
        let samples: [Float]
        let sampleRate: Double
        let label: String
        /// When it was captured — names the file, whenever it is written.
        let date: Date
    }

    /// Recordings that could not be written when their measurement finished (the chosen folder was
    /// no longer at its path, or the write failed). Held until the user chooses a folder or lets them
    /// go. macOS only.
    var heldCaptureRecordings: [CaptureRecording] = []

    /// Set true when a recording is held; the view asks the user to choose a folder, turn off saving,
    /// or cancel. macOS only.
    @Published var captureRecordingHeld: Bool = false

    /// The file name of the last capture audio Dump Capture Audio wrote, for the "saved" notice; `nil`
    /// when none is shown. A new sequence clears it.
    @Published var captureAudioSaved: String? = nil

    /// Whether the plate / brace peaks were restored by a load rather than identified by a capture. A
    /// load shows the range it was saved with, so its peaks do not widen the chart. Set by a load before it
    /// writes the peaks; cleared when a sequence starts, so every captured peak is not from a load.
    var materialPeaksFromLoad = false

    /// The user dismissed the "Capture audio saved" notice.
    func dismissCaptureAudioSaved() {
        captureAudioSaved = nil
    }

    /// The most recent analyzer-set status message, preserved while the
    /// clipping override is active so it can be restored when clipping clears.
    /// Recorded by `statusMessage`'s `didSet`.
    /// Mirrors Python `_latest_real_status`.
    var latestRealStatus: String = "Tap the guitar to begin"

    /// The device-change transient, shown by `handleRouteChangeRestart()` until the settle ends.
    /// Mirrors Python `ROUTE_CHANGE_STATUS`.
    static let routeChangeStatus = "Audio device changed - reinitializing..."

    /// What the status said before a device-change settle replaced it with the "reinitializing…"
    /// transient. Captured by the change that begins a settle, put back and cleared when the settle
    /// ends; a later change inside the settle supersedes its restore and keeps what was captured.
    ///
    /// A stored property rather than a local, matching Python `_status_before_settle` and web
    /// `statusBeforeSettle`, so the capture is observable and all three editions can pin it.
    var statusBeforeSettle: String?

    /// Whether the device-change settle in progress puts detection back to listening when it ends —
    /// captured by the change that begins it, since a later change inside the settle finds the
    /// detector already stood down. `nil` when no settle is in progress.
    var detectingBeforeSettle: Bool?

    /// Counts device changes. A settle's restore runs only if no later change has superseded it, so
    /// the settle always ends `fftSettleTime` of audio after the LAST change.
    var routeChangeGeneration = 0

    /// Counts abandoned captures (``abandonCapture()``). What a capture schedules — its processing, the
    /// next tap's re-arm — runs only if no abandon has come since, so nothing of a capture that New Tap or
    /// a load ended reaches the measurement after it.
    var captureGeneration = 0

    /// Sentinel string used to detect (and ignore) self-writes to
    /// `statusMessage` performed by the clipping-override path, so the
    /// `$statusMessage` sink doesn't store the warning into
    /// `latestRealStatus`.  Mirrors Python's identical override.
    static let clippingWarningStatus = "⚠\u{FE0E} Input clipping — reduce mic gain"

    /// Shown while the input delivers buffers that carry no signal. Outranks the
    /// clipping warning: a dead input cannot also be clipping, and if both were
    /// somehow set, "no audio" is the more actionable message.
    static let deadInputStatus = "⚠\u{FE0E} No audio input — check the microphone connection"

    /// Shown while the audio comes from a device other than the selected microphone and
    /// restarting has not brought the engine back to it. Ranks below a dead input and above
    /// clipping: the level being read is another microphone's.
    static let wrongDeviceStatus = "⚠\u{FE0E} Input is not the selected microphone — choose it again in Settings"

    /// Shown once the recovery has given up after restarts that failed: the input could not be opened
    /// again. Outranks every other input warning — it says the most about what is wrong.
    static let couldNotRestartStatus = "⚠\u{FE0E} The microphone could not be restarted — check its connection, or choose it again in Settings"

    /// Shown while the microphone permission is refused. Outranks every other input warning: without
    /// the permission there is no input to warn about.
    static let microphoneAccessStatus = "⚠\u{FE0E} Microphone access required — enable it in Settings, then restart GuitarTap"

    /// Shown while the input could not be started (a deliberate start failed for anything but the
    /// permission). Ranks just below the permission warning.
    static let couldNotStartStatus = "⚠\u{FE0E} The audio input could not be started — check it, or choose another input in Settings"

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
    /// wire shape, converted at the file boundary.
    @Published var peakModeOverrides: [UUID: String] = [:]

    /// UUIDs of peaks the user has marked as significant results.
    ///
    /// Unmarked peaks are displayed at reduced opacity and can be hidden by setting
    /// ``annotationVisibilityMode`` to `.selected`.
    /// Held in ``peaks``, which alone announces a change to it.
    var selectedPeakIDs: Set<UUID> {
        get { peaks.selectedPeakIDs }
        set { peaks.selectedPeakIDs = newValue }
    }

    /// The peak the user has focused by clicking a dot in the chart or a row in the results panel.
    ///
    /// Only one peak can be highlighted at a time. Setting this to a peak's UUID highlights
    /// the corresponding dot (chart) and row (results). Setting to `nil` clears the highlight.
    /// Both chart and results panel observe this via `@ObservedObject` on the shared analyzer.
    @Published var highlightedPeakID: UUID? = nil

    /// Whether the user has manually modified peak selections since the last auto-selection.
    ///
    /// Reset to automatic selection is offered only while it is `true`, and it is saved with the
    /// measurement. Reset to `false` by ``resetToAutoSelection()``, ``reanalyzePeaks()``, or by a new
    /// tap sequence completing.
    var userHasModifiedPeakSelection: Bool = false

    /// Frequencies (Hz) of the currently selected peaks, kept with `selectedPeakIDs` and saved with the
    /// measurement (`selectedPeakFrequencies`). Nothing reads it back.
    var selectedPeakFrequencies: [Float] = []

    /// True while `loadMeasurement` restores a measurement, so completing it there is told apart from a
    /// capture completing (a load brings its own material inputs).
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
        peakMode(for: peak) == .unknown && !hasManualOverride(for: peak.id)
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
        // mode the user assigned by hand.
        let mode = peakMode(for: winner)
        guard Self.singleHolderModes.contains(mode) else { return }

        for other in allPeaks
        where other.id != peakID
            && selectedPeakIDs.contains(other.id)
            && peakMode(for: other) == mode {
            selectedPeakIDs.remove(other.id)
        }
    }

    /// Clears the selection set so no peaks are marked as significant.
    func selectNoPeaks() {
        selectedPeakIDs.removeAll()
        userHasModifiedPeakSelection = true
    }

    // @parity state/visible-peaks tests=test/annotation-state,test/comparison
    /// Advances ``annotationVisibilityMode`` to the next state in the cycle:
    /// `all → selected → none → all`, and persists the new value to UserDefaults.
    func cycleAnnotationVisibility() {
        // All → Selected → None → All, on every measurement type. For material (plate/brace) there is
        // no per-peak selection, so `.selected` and `.all` render the same set (all identified peaks);
        // the mode is a shared setting and is never coerced on type change.
        annotationVisibilityMode = annotationVisibilityMode.next
        TapDisplaySettings.annotationVisibilityMode = annotationVisibilityMode
    }

    /// The peaks the chart marks: a guitar's above Peak Min, a plate's or brace's identified ones — none
    /// while a comparison is shown, which draws its entries' own.
    var chartPeaks: [ResonantPeak]? {
        guard displayMode != .comparison else { return nil }
        return TapDisplaySettings.measurementType.isGuitar ? peaksAbovePeakMin : materialIdentifiedPeaks
    }

    /// The peaks the chart labels: ``visiblePeaks`` — none while a comparison is shown.
    var chartAnnotationPeaks: [ResonantPeak]? {
        displayMode == .comparison ? nil : visiblePeaks
    }

    /// Whether the chart draws the guitar mode lines: not for a comparison of saved measurements,
    /// whose entries need not be of one guitar type. A multi-tap guitar's per-tap overlay keeps them.
    var showsModeBoundaries: Bool { !isSavedMeasurementComparison }

    /// The subset of ``peaksAbovePeakMin`` that should be rendered as annotations given
    /// the current ``annotationVisibilityMode``.
    ///
    /// In guitar mode, peaks classified as Unknown are excluded when
    /// ``TapDisplaySettings/showUnknownModes`` is `false`, keeping the chart
    /// consistent with the Analysis Results panel.
    var visiblePeaks: [ResonantPeak] {
        // Material (plate/brace): annotate the accumulated identified L/C/FLC (stable, persistent),
        // matching the web — NOT `peaksAbovePeakMin`, which churns through 87→126→3 raw peaks during
        // capture. There is no per-peak selection, so `.all`/`.selected` are equivalent.
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
    /// in phase order — a material measurement's peaks. The three `selected…Peak`s are the only
    /// material peak state (`allPeaks` / `selectedPeakIDs` are guitar-only); the chart, annotations,
    /// results panel, save and PDF all read them through here. Empty for guitar.
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

    /// The longitudinal (fL) peak — the dominant peak of the phase's averaged spectrum, stored when
    /// the phase finalises. `nil` before then, and after a Redo of the phase.
    @Published var selectedLongitudinalPeak: ResonantPeak?

    /// The cross-grain (fC) peak, stored when the cross-grain phase finalises.
    @Published var selectedCrossPeak: ResonantPeak?

    /// Averaged FFT spectrum from the FLC tap, once captured.
    @Published var flcSpectrum: (magnitudes: [Float], frequencies: [Float])?

    /// The FLC (torsional/twist) peak, stored when the FLC phase finalises.
    @Published var selectedFlcPeak: ResonantPeak?

    // MARK: - Effective Peak Selection
    //
    // `selected<Phase>Peak` is the identified peak, and the only one a phase keeps.

    /// UUID of the longitudinal (fL) peak, or `nil` before the phase finalises.
    ///
    /// There is nothing to resolve: this is the phase's identified peak. It is a named property
    /// because views and the material-property calculations read it, and because its two siblings
    /// exist for the other phases.
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

    /// There is something to save or export: a complete measurement (captured, loaded, multi-tap, or a
    /// finished plate/brace) or a comparison. Save, Export Spectrum and Export PDF — the buttons and the
    /// macOS menu commands — are enabled only then.
    var hasResultToSaveOrExport: Bool {
        isMeasurementComplete || displayMode == .comparison
    }

    // MARK: - Capture Provenance

    /// Where the current result came from when it is not the live input: a played file or a loaded
    /// measurement. `nil` while the sequence listens to the input. A played file has no microphone (the
    /// microphone that recorded a file is not known), the calibration it was played with (or none) and
    /// its sample rate; a loaded measurement has what the file recorded. Set by
    /// ``playFile(url:calibrationURL:completion:)`` and ``loadMeasurement(_:)``; a new sequence clears it.
    struct ResultProvenance {
        let microphoneName: String?
        let microphoneUID: String?
        let calibrationName: String?
        let sampleRate: Double?
    }
    var resultProvenance: ResultProvenance?

    /// The microphone the current result was captured with, as shown, saved and reported: the input
    /// device for a live result; the recorded one for a played file or a loaded measurement, `nil`
    /// (unknown) when there is none.
    var captureMicrophoneName: String? {
        resultProvenance.map { $0.microphoneName } ?? fftAnalyzer.selectedInputDevice?.name
    }

    /// The UID of ``captureMicrophoneName``'s device.
    var captureMicrophoneUID: String? {
        resultProvenance.map { $0.microphoneUID } ?? fftAnalyzer.selectedInputDevice?.uid
    }

    /// The calibration the current result was captured with: the input's for a live result, the
    /// recorded one otherwise (none for a file played uncalibrated).
    var captureCalibrationName: String? {
        resultProvenance.map { $0.calibrationName } ?? fftAnalyzer.activeCalibration?.name
    }

    /// The sample rate the current result was captured at: the input's for a live result (`nil` when the
    /// engine has no rate yet), the recorded one otherwise.
    var captureSampleRate: Double? {
        resultProvenance.map { $0.sampleRate }
            ?? (fftAnalyzer.actualSampleRate > 0 ? fftAnalyzer.actualSampleRate : nil)
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

    /// The chart axis range of the most recent load (a measurement's own range, or a comparison's
    /// union). The chart's range is view state: the view applies this when it is published, and a
    /// later load publishes again. The view never writes it.
    @Published var loadedAxisRange: LoadedAxisRange?

    /// Publish the loaded axis range — all four bounds in one value, so the view applies them in
    /// one render pass and never sees a mismatched pair.
    func setLoadedAxisRange(minFreq: Float, maxFreq: Float, minDB: Float, maxDB: Float) {
        loadedAxisRange = LoadedAxisRange(minFreq: minFreq, maxFreq: maxFreq,
                                         minDB: minDB, maxDB: maxDB)
    }

    /// The tap threshold and tap count the loaded measurement was taken with. The loaded-settings
    /// warning stays until the user changes either away from these.
    var loadedTapDetectionThreshold: Float?
    var loadedNumberOfTaps: Int?

    /// True while the user should be reminded that threshold and tap-count settings
    /// came from a loaded measurement rather than their own preferences.
    /// Set when a measurement is loaded; cleared when a new tap is successfully
    /// completed, when the user manually changes threshold or tap count, or on reset.
    @Published var showLoadedSettingsWarning: Bool = false

    /// Warning message shown after a load when the measurement's microphone is not found, its
    /// setup (calibration, sample rate) differs from the current one, or it cannot be opened.
    @Published var microphoneWarning: String?

    /// The title of the alert that shows `microphoneWarning`; set with it.
    @Published var microphoneWarningTitle: String = "Microphone Not Found"

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
    /// In comparison mode, whatever the measurement type, these are the chart's `overlaySpectra`, so
    /// the main `SpectrumView` draws them as its overlaid curves. Cleared by `clearComparison()` or a new tap sequence.
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

    /// The compared span while a comparison measurement is shown — the span of the compared measurements' saved
    /// views, the range a new comparison opens at — else nil. The chart's menu resets to it ("Comparison Range").
    /// Not a saved comparison's own range (`TapToneMeasurement.comparisonRange`), the view it was saved with.
    var comparedSpan: DisplayRange.ChartRange? {
        isSavedMeasurementComparison ? DisplayRange.spanning(comparisonSnapshots) : nil
    }

    // MARK: - Gated FFT State
    //
    // Main thread only: every chunk reaches the analyzer there, in order (`processAudioFrame`).

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

    /// Accumulated raw PCM samples for the current gated FFT capture window.
    ///
    /// Seeded with pre-roll content when the window opens; populated by
    /// ``accumulateGatedSamples(_:sampleRate:)``, a chunk at a time.
    var gatedAccumBuffer: [Float] = []

    /// Target duration of the gated capture buffer, in seconds.
    ///
    /// 500 ms is intentionally longer than ``gatedFFTWindowDuration`` so that
    /// `alignCaptureToOnset` always has at least 400 ms of audio available
    /// to extract a sample-aligned window — regardless of how full the
    /// pre-roll ring buffer happens to be when the tap is confirmed.
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

    /// Samples left between the noise re-measured before the tap and the tap's first sample above
    /// the threshold, so the measured stretch holds none of the tap's own rise.
    static let onsetNoiseGuardSamples: Int = 256

    /// How many times the onset may be found again from the noise just before it. It settles in
    /// one or two.
    static let onsetRefinementPasses: Int = 4

    /// Number of samples in one gated capture window at the current hardware sample rate.
    /// Target size of the gated-capture window, in samples.
    ///
    /// Set at capture-start time so the same accumulator infrastructure can serve
    /// different capture lengths: plate/brace uses ``gatedCaptureDuration`` (~500 ms);
    /// guitar uses the full `fftSize` so the resulting spectrum has the same
    /// frequency resolution as the live FFT path.
    var gatedCaptureSamples: Int = 0

    /// How many samples of a guitar tap's FFT window are audio; the rest of the window, to
    /// `fftSize`, is always zeros.
    ///
    /// A guitar capture is `fftSize` samples beginning ``preRollSamples`` before the trigger, and
    /// `alignCaptureToOnset` starts the window ``preOnsetDuration`` before the onset — so the
    /// window starts up to (pre-roll − pre-onset) into the capture, depending on how long after
    /// the onset the trigger's chunk boundary fell, and that many samples short of its end the
    /// capture runs out. Ending the audio that margin before the window's end, always, makes the
    /// window the same samples wherever the boundary fell: the same tap gives the same spectrum on
    /// every run and in every edition. What is left out is the last tenth of a second of a
    /// 1.4-second window.
    ///
    /// - Parameter sampleRate: The capture's sample rate in Hz.
    func guitarWindowAudioSamples(sampleRate: Double) -> Int {
        let margin = Int(sampleRate * TapToneAnalyzer.preRollDuration) - Int(sampleRate * TapToneAnalyzer.preOnsetDuration)
        return fftAnalyzer.fftSize - max(0, margin)
    }

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
    // identically through the pipeline.

    /// Session recording buffer — accumulates raw mic audio while detection
    /// is active.  Used to produce a single WAV per measurement that can be
    /// replayed through the pipeline to reproduce the original results.
    var sessionRecordingBuffer: [Float] = []

    /// Whether the session recording is actively accumulating samples.
    /// Set to `true` when a tap sequence starts, whatever Dump Capture Audio says: the bounded
    /// pre-roll is kept either way. Set to `false` during pause, at the first tap when the sequence is
    /// not being saved, when Dump Capture Audio is turned off after the first tap, when a loaded
    /// measurement or comparison ends the sequence, or when the measurement completes.
    var isSessionRecording = false

    /// Whether this sequence's recording is saved — read from Dump Capture Audio when the sequence
    /// starts, and again when the setting changes before the first tap (until then only the pre-roll
    /// exists, so it is still the start). Turning the setting on after the first tap takes effect
    /// from the next sequence; turning it off stops the recording at any point.
    var isSessionRecordingEnabled = false

    /// Checkpoint offsets (sample counts in `sessionRecordingBuffer`) for
    /// accepted plate phases.  When a phase is redone, the buffer is truncated
    /// to the last checkpoint so rejected audio is excluded from the saved WAV.
    var sessionCheckpoints: [Int] = []

    /// Sample rate captured at recording start, used for session WAV export.
    var sessionRecordingSampleRate: Double = 48000

    /// Bounded pre-roll for the session WAV.
    ///
    /// While armed and **before the first tap**, the session buffer keeps only the last
    /// ``sessionPreRollDuration`` of audio (trimmed on every chunk), so an app left armed for
    /// minutes does not accumulate minutes of silence — in RAM or in the saved WAV. It is kept with
    /// Dump Capture Audio off too, so turning the setting on before the first tap saves the same
    /// recording as having it on from the start. This latch is
    /// `true` from `startTapSequence` until the first gated capture begins, then stays `false`:
    /// once real recording starts, the buffer grows straight through so every tap, phase and redo
    /// checkpoint is preserved. Guarantees ≥ 0.5 s before the first tap (detection is suppressed
    /// during the warm-up), so every dumped WAV is a valid playback fixture.
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
    // 2. Every chunk reaches the pre-roll before it reaches the detector, in one sequence on the main
    //    thread (processAudioFrame), so the pre-roll holds the tap's attack when the tap is confirmed.

    /// Duration of the pre-roll look-back buffer, in seconds.
    ///
    /// 200 ms is enough to guarantee the tap attack is captured even on slow devices.
    static let preRollDuration: Double = 0.200

    /// Number of pre-roll samples at the current hardware sample rate.
    var preRollSamples: Int { Int(mpmSampleRate * TapToneAnalyzer.preRollDuration) }

    /// Circular buffer holding the most recent ``preRollSamples`` raw PCM samples.
    ///
    /// Written a chunk at a time by ``accumulateGatedSamples(_:sampleRate:)``; read when a capture starts.
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
    /// Used by ``removeDuplicatePeaks(_:)`` in `+PeakAnalysis`.
    static let peakProximityHz: Float = 2.0

    /// The absolute magnitude floor (dBFS) for the peak set persisted with a guitar measurement.
    ///
    /// A saved measurement records every peak down to this floor, not just those above the current
    /// Peak Min, so a reloaded measurement can reveal peaks below the capture-time Peak Min exactly
    /// as the live measurement can. −100 dB is the chart's `defaultMinMagnitude` and the Peak Min
    /// slider's lower bound, so a peak below it can neither be drawn nor admitted by Peak Min — there
    /// is nothing to gain by storing it.
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

    /// The audio clock as the analyzer has seen it: the audio time of the latest chunk delivered to
    /// ``onRmsLevelChanged(_:audioTime:)``, recorded on every chunk before any guard.
    ///
    /// The tap-lifecycle timers run on THIS clock, not the wall clock. File playback advances audio
    /// at "real time + processing time", so a wall-clock delay would cover a different stretch of
    /// audio on a slower run and move captures late in a sequence. Chunks reach the main thread in
    /// order, each carrying its own audio time, so a delay measured here covers exactly the same audio
    /// on every run. Never substitute `fftAnalyzer.audioElapsed` read on the main thread: the audio
    /// thread races ahead of it.
    var lastAudioTime: Double = 0

    /// The level (dBFS) of the chunk whose audio time is ``lastAudioTime`` — the input level the
    /// analyzer acts on: a new sequence seeds its noise floor from it, and each arming (a re-arm, a
    /// resume, a material phase) re-anchors the hysteresis latch from it. The published meter level
    /// (`fftAnalyzer.level.inputLevelDB`) is the display's, set a buffer at a time on the main
    /// thread, so it can lag the chunk detection has just seen.
    var lastChunkLevelDB: Float = -100

    /// The WALL time (``wallClock``) at which the latest chunk reached
    /// ``onRmsLevelChanged(_:audioTime:)`` — what the capture safety timeout measures its silence from
    /// (``afterAudioStall(_:while:_:)``).
    var lastChunkWallTime: TimeInterval = 0

    /// Tap-lifecycle actions waiting on the audio clock — see ``afterAudio(_:releasedAtFileEnd:_:)``.
    var pendingAudioActions: [(due: Double, releasedAtFileEnd: Bool, action: () -> Void)] = []

    /// Actions waiting for the next FFT frame — see ``afterNextFrame(_:)``.
    var pendingFrameActions: [(Float) -> Void] = []

    /// The rest after a capture before detection re-arms, and the hold before the FLC phase arms, in
    /// seconds of AUDIO (see ``afterAudio(_:releasedAtFileEnd:_:)``).
    let tapCooldown: TimeInterval = 0.5

    /// Value of the engine's AUDIO clock (`fftAnalyzer.audioElapsed`, in seconds of audio processed)
    /// when `start()` or `startTapSequence()` last armed a sequence. `nil` until first armed.
    ///
    /// Used to enforce the warm-up period. This is deliberately the AUDIO clock, not the wall clock:
    /// the warm-up must cover the first `warmupPeriod` of AUDIO. Live, the two coincide. In FILE
    /// PLAYBACK they do not — the file is read and the engine reconfigured between arming and the first
    /// chunk, and if that setup outlasts the warm-up, a wall-clock warm-up expires *before any audio
    /// arrives*: it never runs, the noise-floor re-anchor never fires, and the EMA latches at its seed.
    /// That silently disabled relative detection in playback.
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
    var detectTapConsecutiveAbove: Int = 0

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
    init(fftAnalyzer: RealtimeFFTAnalyzer, wallClock: WallClock = SystemWallClock()) {
        self.fftAnalyzer = fftAnalyzer
        self.wallClock = wallClock

        // When the user grants microphone permission in the system's request, the engine's
        // callback fires on a background thread.
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
                if RealtimeFFTAnalyzer.isPermissionError(error) {
                    self.fftAnalyzer.microphonePermissionDenied = true
                }
            }
        }

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
    /// 2. **audioFrameHandler (main thread, ~43 Hz)** — every chunk, in order, with its level and *audio-clock
    ///    timestamp*: ``processAudioFrame(_:levelDB:audioTime:sampleRate:)`` keeps the pre-roll, fills the
    ///    capture and drives `detectTap(...)` (the per-chunk rising-edge detector — guitar vs the ABSOLUTE
    ///    threshold, plate/brace vs the noise-floor-RELATIVE threshold). The long-window FFT is unreliable for
    ///    short transient taps, so no mode detects from the FFT-rate path.
    /// 3. **routeChangeRestartCount** — triggers ``handleRouteChangeRestart()`` when the audio
    ///    engine restarts after a device/route change.
    func setupSubscriptions() {
        // Every chunk, on the main thread, in order: the pre-roll, the capture, the clock and detection.
        fftAnalyzer.audioFrameHandler = { [weak self] samples, levelDB, audioTime in
            guard let self else { return }
            SlackProbe.shared.time(.mainChunk) {
                self.processAudioFrame(samples, levelDB: levelDB, audioTime: audioTime,
                                       sampleRate: self.fftAnalyzer.actualSampleRate)
            }
        }
        SlackProbe.shared.start()

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
        // Clear the pre-roll buffer after the engine stops, so any mic noise that leaked in between
        // startTapSequence (which clears preRollBuffer) and the engine stop is flushed; a mic chunk still
        // queued for the main thread is dropped when it arrives.
        // Do NOT pre-fill with zeros — the buffer fills naturally with real
        // audio as file chunks arrive through accumulateGatedSamples.
        // Pre-filling with zeros dilutes the gated capture signal by ~50%,
        // suppressing the spectral magnitude by ~6 dB.
        fftAnalyzer.postEngineStopHandler = { [weak self] in
            guard let self else { return }
            TAP_DEBUG("file_playback", "POST_ENGINE_STOP_HANDLER | mpmSampleRate=\(Int(self.mpmSampleRate)) preRollBefore=\(self.preRollBuffer.count)")
            self.preRollBuffer = []
            TAP_DEBUG("file_playback", "POST_ENGINE_STOP_HANDLER_DONE | preRollAfter=\(self.preRollBuffer.count)")
        }

        // Slow path: full FFT frame → onFftFrame (in +TapDetection.swift),
        // which delegates to analyzeMagnitudes for peak analysis.  The entry-
        // point method placement mirrors Python's on_fft_frame in
        // tap_tone_analyzer_tap_detection.py.
        fftAnalyzer.frame.$magnitudes
            .combineLatest(fftAnalyzer.$frequencies, fftAnalyzer.frame.$peakMagnitude)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] magnitudes, frequencies, peakMag in
                SlackProbe.shared.time(.frame) {
                    self?.onFftFrame(magnitudes: magnitudes, frequencies: frequencies, peakMagnitude: peakMag)
                }
            }
            .store(in: &cancellables)

        // Audio route change → reinitialise detection state after the engine restarts.
        fftAnalyzer.$routeChangeRestartCount
            .dropFirst()  // Ignore the initial published value (0).
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleRouteChangeRestart()
            }
            .store(in: &cancellables)

        // ── Input-clipping override ──────────────────────────────────────
        // When fftAnalyzer.level.isClipping toggles, swap the displayed
        // statusMessage between the analyzer's intended message
        // (preserved in latestRealStatus) and a remediation warning.
        // Set on the main thread, so applied at once — no queue hop. A @Published sink runs before
        // the property changes, so the analyzer keeps the new value itself, then applies it.
        // Mirrors Python `_set_clipping` and the web's `setClipping`.
        fftAnalyzer.level.$isClipping
            .sink { [weak self] clipping in
                self?.isClipping = clipping
                self?.applyStatusOverrides()
            }
            .store(in: &cancellables)

        // ── Dead-input override ──────────────────────────────────────────
        // Same mechanism as clipping, higher priority; the watchdog sets it on the main thread.
        // Mirrors Python.
        fftAnalyzer.$inputAppearsDead
            .sink { [weak self] dead in
                self?.inputAppearsDead = dead
                self?.applyStatusOverrides()
            }
            .store(in: &cancellables)

        // ── Microphone-permission override ───────────────────────────────
        // Same mechanism as the dead input, highest priority.
        fftAnalyzer.$microphonePermissionDenied
            .sink { [weak self] denied in
                self?.microphonePermissionDenied = denied
                self?.applyStatusOverrides()
            }
            .store(in: &cancellables)

        // ── Could-not-start override ─────────────────────────────────────
        fftAnalyzer.$inputCouldNotStart
            .sink { [weak self] failed in
                self?.inputCouldNotStart = failed
                self?.applyStatusOverrides()
            }
            .store(in: &cancellables)

        // ── Could-not-restart override ───────────────────────────────────
        // Same mechanism as the dead input, higher priority.
        fftAnalyzer.$inputCouldNotRestart
            .sink { [weak self] failed in
                self?.inputCouldNotRestart = failed
                self?.applyStatusOverrides()
            }
            .store(in: &cancellables)

        // ── Wrong-device override ────────────────────────────────────────
        fftAnalyzer.$inputIsNotSelectedDevice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyStatusOverrides()
            }
            .store(in: &cancellables)
    }

    /// The input is clipping — the engine's `level.isClipping`, kept here by its sink. Mirrors Python
    /// `is_clipping` and the web's `isClipping`.
    private(set) var isClipping = false

    /// The input appears dead — the engine's `inputAppearsDead`, kept here by its sink. Mirrors Python
    /// `input_appears_dead` and the web's `inputAppearsDead`.
    private(set) var inputAppearsDead = false

    /// The microphone permission is refused — the engine's `microphonePermissionDenied`, kept here by
    /// its sink. Mirrors Python `microphone_permission_denied` and the web's `microphonePermissionDenied`.
    private(set) var microphonePermissionDenied = false

    /// The input could not be started — the engine's `inputCouldNotStart`, kept here by its sink.
    /// Mirrors Python `input_could_not_start` and the web's `inputCouldNotStart`.
    private(set) var inputCouldNotStart = false

    /// The input could not be restarted — the engine's `inputCouldNotRestart`, kept here by its sink.
    /// Mirrors Python `input_could_not_restart` and the web's `inputCouldNotRestart`.
    private(set) var inputCouldNotRestart = false

    /// Resolves the displayed status against the active input-condition overrides.
    ///
    /// One place decides precedence — the microphone permission refused, then an input that could not
    /// be started, then one that could not be restarted, then dead input, then the wrong device, then clipping, then whatever the analyzer
    /// last set — so the override sinks cannot fight each other or leave a stale warning on screen
    /// after its condition clears.
    func applyStatusOverrides() {
        let resolved: String
        if microphonePermissionDenied {
            resolved = TapToneAnalyzer.microphoneAccessStatus
        } else if inputCouldNotStart {
            resolved = TapToneAnalyzer.couldNotStartStatus
        } else if inputCouldNotRestart {
            resolved = TapToneAnalyzer.couldNotRestartStatus
        } else if inputAppearsDead {
            resolved = TapToneAnalyzer.deadInputStatus
        } else if fftAnalyzer.inputIsNotSelectedDevice {
            resolved = TapToneAnalyzer.wrongDeviceStatus
        } else if isClipping {
            resolved = TapToneAnalyzer.clippingWarningStatus
        } else {
            resolved = latestRealStatus
        }
        if statusMessage != resolved { statusMessage = resolved }
    }

    // MARK: - Route Change Handling
    // @parity state/route-change-settle tests=test/notification

    /// Responds to an audio engine restart triggered by a device or route change.
    ///
    /// Temporarily disables tap detection, resets the warm-up, and re-enables detection once
    /// `fftSettleTime` of AUDIO has passed since the change (after the 65 536-sample FFT window has
    /// filled with valid post-restart data) and the next FFT frame has arrived. If detection was
    /// listening before the change it listens again; otherwise the analyzer returns to its prompt.
    /// A later change inside the settle supersedes this one's restore, so the settle always ends a
    /// full `fftSettleTime` after the last change.
    ///
    /// - Important: The 3-second settle delay is conservative to ensure `peakMagnitude`
    ///   reflects real audio data rather than silence or the engine startup transient
    ///   before `isAboveThreshold` is re-anchored.
    /// How much audio a device change waits before detection resumes: the FFT pipeline must fill with valid
    /// post-restart data (~1.36 s for 65 536 samples at 48 kHz); 3 s also covers the HALC startup transient that
    /// sometimes appears 2–2.5 s after a device hot-swap when the audio unit needs an internal recovery restart.
    /// On the AUDIO clock: what has to pass is that much audio from the new device.
    static let routeChangeSettleTime: TimeInterval = 3.0

    func handleRouteChangeRestart() {
        gtLog("🔄 TapToneAnalyzer: Handling route change restart - resetting detection state")

        let wasDetecting = (detectionState == .listening)
        // The change that begins a settle decides whether its end re-arms; a later change inside it
        // finds the detector already stood down.
        if detectingBeforeSettle == nil { detectingBeforeSettle = wasDetecting }

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
        // Blank only if a LIVE spectrum is on screen. `displayMode == .live` does not say that: no
        // completion path sets `.frozen`, so a finished measurement is still `.live`.
        // `isMeasurementComplete` is the field that says whether what you are looking at is a result.
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
        // transient up.
        //
        // `latestRealStatus`, NOT `statusMessage`: the latter is the OVERRIDE-RESOLVED string, so a
        // route change while the input is clipping or dead would preserve the warning sentinel and
        // put it back as though the analyzer had set it. The override layer re-resolves on its own
        // from the real status, so the real status is what has to survive the settle.
        //
        // Guarded so a route change during a settle does not capture the transient itself: a
        // captured `routeChangeStatus` would be put back by `restoredStatus(before:)` for every
        // state whose status is not re-derivable — a completed measurement, a material phase
        // prompt — and stay up until something else writes a status. The settle's end clears it, so
        // a value already here means a settle is in progress and the change that began it captured
        // the real status.
        if statusBeforeSettle == nil {
            statusBeforeSettle = latestRealStatus
        }
        statusMessage = Self.routeChangeStatus

        routeChangeGeneration += 1
        scheduleRouteChangeSettleEnd(generation: routeChangeGeneration, wasShowingLive: wasShowingLive)
    }

    /// The device-change settle's end, ``routeChangeSettleTime`` of audio after the change: on the next FFT
    /// frame, detection is re-anchored and re-enabled, the display unfrozen and the status put back. If the
    /// engine is restarting again at that moment — a retry after a start that failed — the settle waits that
    /// much audio from the restarted engine instead of ending without it, so it cannot be left waiting for
    /// good.
    func scheduleRouteChangeSettleEnd(generation: Int, wasShowingLive: Bool) {
        afterAudio(Self.routeChangeSettleTime) { [weak self] in
            guard let self, generation == self.routeChangeGeneration else { return }
            guard self.fftAnalyzer.isRunning else {
                self.scheduleRouteChangeSettleEnd(generation: generation, wasShowingLive: wasShowingLive)
                return
            }
            // Wait for the next FFT frame before re-anchoring detection and unfreezing the display.
            // This ensures both happen on the same frame — the first one the user actually sees —
            // preventing a false rising edge caused by a transient that arrives between the settle
            // ending and the re-anchor. isAboveThreshold stays true (blocking detection) until that
            // frame arrives.
            self.afterNextFrame { [weak self] peakMagnitude in
                guard let self, generation == self.routeChangeGeneration else { return }

                // Re-anchor isAboveThreshold to the level of the first frame that is actually
                // displayed, so the hysteresis detector starts in the correct state and cannot fire
                // a spurious rising edge.
                self.isAboveThreshold = (peakMagnitude > self.tapDetectionThreshold)

                if wasShowingLive { self.isSettling = false }

                self.isReadyForDetection = true

                if self.detectingBeforeSettle == true { self.detectionState = .listening }
                self.detectingBeforeSettle = nil
                // Derive the status from the state we are now in; where that is a result
                // announcement rather than a prompt, put back what was there before the settle.
                self.statusMessage = self.restoredStatus(before: self.statusBeforeSettle ?? "Ready")
                self.statusBeforeSettle = nil
                gtLog("🔄 TapToneAnalyzer: Detection re-enabled after route change (current level: \(peakMagnitude) dB, threshold: \(self.tapDetectionThreshold) dB, above threshold: \(self.isAboveThreshold))")
            }
        }
    }
}
