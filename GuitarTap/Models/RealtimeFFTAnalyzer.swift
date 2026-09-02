//
//  RealtimeFFTAnalyzer.swift
//  GuitarTap
//
//  Created by David Smith on 12/31/25.
//
// @parity audio/realtime-analyzer tests=test/file-playback,test/tap-decisions
/// # RealtimeFFTAnalyzer
///
/// A real-time FFT analyser that captures audio from the device microphone,
/// computes a continuous magnitude spectrum, and publishes results for live
/// visualisation and tap-tone analysis.
///
/// ## File Organisation
/// The implementation is split across four files:
/// - `RealtimeFFTAnalyzer.swift` — class declaration, all stored properties, `init`, `deinit`
/// - `RealtimeFFTAnalyzer+EngineControl.swift` — `start()` and `stop()`
/// - `RealtimeFFTAnalyzer+FFTProcessing.swift` — continuous and gated FFT, resampling, metrics
/// - `RealtimeFFTAnalyzer+DeviceManagement.swift` — device enumeration, CoreAudio/AVAudioSession listeners, `setInputDevice`
///
/// ## Architecture
/// ```
/// AVAudioInputNode tap (1 024-sample buffers, hardware rate)
///        │
///        ├──► audioProcessingQueue
///        │         ├─ RMS level → inputLevelDB / recentPeakLevelDB (main thread, ~43 Hz)
///        │         ├─ rawSampleHandler → TapToneAnalyzer pre-roll + gated capture
///        │         └─ inputBuffer accumulation
///        │                  └─ when ≥ fftSize samples:
///        │                         performFFT(on:) → magnitudes / peakMagnitude (main, ~0.7 Hz)
///
/// computeGatedFFT(samples:sampleRate:) — called externally by TapToneAnalyzer,
///        not part of the continuous tap path
/// ```
///
/// ## Continuous vs. Gated FFT
/// The **continuous** path produces one spectrum frame per FFT window (0% overlap, hop = fftSize).
/// The window is **rectangular** (all ones — effectively no windowing) for simplicity on
/// the live display path where sidelobe suppression is less important than
/// amplitude accuracy.
///
/// The **gated** path (`computeGatedFFT`) transforms a short pre-captured PCM
/// buffer for plate/brace measurements. It uses a **Hann window** for better
/// frequency resolution and lower sidelobes, since the result feeds material
/// property calculations.
///
/// ## Platform Differences
///
/// | Feature | macOS | iOS |
/// |---|---|---|
/// | Device selection | CoreAudio `AudioDeviceID` via AUHAL | `AVAudioSession.setPreferredInput` |
/// | Device change events | `AudioObjectAddPropertyListenerBlock` | `AVAudioSession.routeChangeNotification` |
/// | Permission check | `AVCaptureDevice.authorizationStatus` + 3-second TCC-stale detection | Handled by system |
/// | Permission-denied signal | Silent all-zero stream → `peakMagnitude.isInfinite` | Not needed |
///
/// ## Permission Handling (macOS)
/// macOS TCC can cache `.authorized` even after a revocation. The analyser
/// uses a delayed check at t = +3 s: if the peak magnitude is −∞ (perfectly
/// silent all-zero stream) and buffers *are* arriving, the OS is silently
/// muting the input. In that case `microphonePermissionDenied` is set `true`
/// and the engine is stopped.
///
/// ## Thread Safety
/// - Audio buffer delivery: `audioProcessingQueue` (serial, `.userInteractive`)
/// - Shared buffer access: `bufferAccessQueue` (serial, `.userInteractive`)
/// - All `@Published` property updates: main thread only
///
/// ## Example Usage
/// ```swift
/// let analyzer = RealtimeFFTAnalyzer()
/// try analyzer.start()
/// // Observe analyzer.magnitudes and analyzer.frequencies for visualisation
/// analyzer.stop()
/// ```
///
/// - Note: Requires `NSMicrophoneUsageDescription` in Info.plist.

import SwiftUI
import AVFoundation
import Accelerate
import Charts
import Combine
import OSLog

#if os(macOS)
import AudioToolbox
import CoreAudio
#endif

private let micLog = Logger(subsystem: "com.dolcesfogato.GuitarTap", category: "Microphone")

// MARK: - FFT Analyzer

/// Real-time FFT analyzer for the live spectrum.
///
/// Owns the `AVAudioEngine` graph, taps the microphone, runs a windowed FFT on the
/// captured buffers, and publishes magnitude / peak updates to the UI. The class is
/// split across four files: this one (declaration + init/deinit),
/// `+EngineControl` (start/stop), `+FFTProcessing` (computeFFT, peak detection,
/// parabolic interpolation, Q-factor, HPS), and `+DeviceManagement` (device
/// enumeration + CoreAudio / AVAudioSession listeners).
final class RealtimeFFTAnalyzer: ObservableObject {
    
    // MARK: - Audio Engine Components
    
    /// The main audio engine that manages audio processing graph and I/O
    var audioEngine: AVAudioEngine
    
    /// The audio input node representing the device's microphone.
    /// Not accessed until start() to avoid triggering the audio hardware before permission is confirmed.
    var inputNode: AVAudioInputNode!
    
    /// The currently selected audio input device
    @Published var selectedInputDevice: AVAudioDevice? {
        didSet {
            // Persist the selected device UID so it can be restored on next launch
            if let deviceUID = selectedInputDevice?.uid {
                UserDefaults.standard.set(deviceUID, forKey: "selectedInputDeviceUID")
            }

            // Automatically load device-specific calibration when device changes
            if let deviceUID = selectedInputDevice?.uid {
                if let deviceCalibration = CalibrationStorage.shared.calibration(forDeviceUID: deviceUID) {
                    // Device has a specific calibration - use it
                    // Use internal setter to avoid re-saving the mapping
                    setCalibrationWithoutSavingDeviceMapping(deviceCalibration)
                    gtLog("📊 Auto-loaded calibration '\(deviceCalibration.name)' for device '\(selectedInputDevice?.name ?? "unknown")'")
                } else {
                    // No calibration for this device - clear any active calibration
                    setCalibrationWithoutSavingDeviceMapping(nil)
                    gtLog("📊 No calibration for device '\(selectedInputDevice?.name ?? "unknown")' - using uncalibrated mode")
                }
            }

            #if os(macOS)
            // On macOS, if the engine is running and this change came from the user
            // (not from setInputDevice's own assignment), restart the engine with the new device.
            guard !isApplyingDeviceSwitch, isRunning, selectedInputDevice?.uid != oldValue?.uid else { return }
            gtLog("🔄 Device changed while running — restarting engine for: \(selectedInputDevice?.name ?? "unknown")")
            isApplyingDeviceSwitch = true
            stop()
            // Signal handleRouteChangeRestart() BEFORE starting the engine so the
            // display freezes (blank) before the new device's first FFT frame can
            // render.  routeChangeRestartCount is @Published and received on the main
            // queue via Combine, so the sink fires on the next main-queue drain —
            // which is guaranteed to precede any audio-tap callback dispatched from
            // the new engine session.
            self.routeChangeRestartCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                do {
                    try self.start()
                    gtLog("✅ Engine restarted with new device: \(self.selectedInputDevice?.name ?? "unknown") (restart #\(self.routeChangeRestartCount))")
                } catch {
                    gtLog("❌ Failed to restart engine after device change: \(error)")
                }
                self.isApplyingDeviceSwitch = false
            }
            #endif
        }
    }

    /// Guards against re-entrant engine restarts when selectedInputDevice is set programmatically
    var isApplyingDeviceSwitch = false
    
    /// List of available audio input devices
    @Published var availableInputDevices: [AVAudioDevice] = []
    
    // MARK: - Thread Management
    
    /// Dedicated serial queue for audio processing to avoid blocking the main thread
    /// All audio buffer processing and FFT calculations happen on this queue
    let audioProcessingQueue = DispatchQueue(
        label: "com.realtimefft.audioprocessing",
        qos: .userInteractive
    )
    
    /// Serial queue for synchronizing access to shared buffers
    /// Prevents race conditions when reading/writing audio data
    let bufferAccessQueue = DispatchQueue(
        label: "com.realtimefft.bufferaccess",
        qos: .userInteractive
    )
    
    // MARK: - FFT Configuration
    
    /// The size of the FFT window (65 536 points).
    ///
    /// This is a **compile-time constant** — it is never configurable at runtime.
    /// At 48 kHz the window spans ≈1.36 s with ≈0.73 Hz/bin resolution.
    /// Both the continuous display path (`performFFT`) and the guitar gated-
    /// capture path (`finishGuitarGatedCapture`) use this value.  The plate/
    /// brace gated path (`computeGatedFFT`) computes its own size independently.
    ///
    /// - Note: Output will contain `fftSize / 2` frequency bins.
    let fftSize: Int = 65536
    
    /// The vDSP FFT setup object used for performing fast Fourier transforms
    /// - Note: This is created once during initialization and reused for performance
    var fftSetup: vDSP_DFT_Setup?
    
    // MARK: - Sample Rate Management
    
    /// The actual sample rate of the audio hardware in Hz.
    /// - Note: This is determined at runtime when the audio engine starts; 0 when stopped.
    @Published var actualSampleRate: Double = 0
    
    // MARK: - Audio Buffers
    
    /// Accumulates incoming audio samples until there's enough data for FFT processing
    /// - Important: Access only on bufferAccessQueue to prevent race conditions
    var inputBuffer: [Float] = []

    // MARK: - FILE_DEBUG instrumentation

    /// Counter so each FFT frame produced by ``performFFT(on:)`` has a unique
    /// ordinal.  Used by FILE_DEBUG logs to correlate FFT frames with file-
    /// playback progress and tap detection.  Resets to 0 on each playback
    /// restart via ``prepareForFilePlayback(sampleRate:fileName:)``.
    /// Mirrors Python `_FftProcessingThread._fft_frame_counter`.
    var fftFrameCounter: Int = 0

    /// Running total of samples consumed by FFT frames (incremented by
    /// ``fftSize`` per frame).  Used to compute the file-time of each FFT
    /// frame for FILE_DEBUG logging.
    /// Mirrors Python `_FftProcessingThread._samples_consumed`.
    var samplesConsumed: Int = 0

    /// Seconds of AUDIO processed since the engine started — the audio clock.
    ///
    /// Advanced by `processRawSamples` (`samples.count / sampleRate`), so it tracks the audio itself
    /// rather than the wall clock. The detection **warm-up** is measured against this.
    ///
    /// Why: the warm-up must cover the first 0.5 s of AUDIO, not 0.5 s of wall-time. Live, the two
    /// coincide (audio is already flowing when a sequence arms). In FILE PLAYBACK they do not — the
    /// file is read and the engine reconfigured between arming and the first chunk, and if that setup
    /// takes longer than the warm-up, a wall-clock warm-up expires *before any audio arrives*: the
    /// warm-up never runs, the noise-floor re-anchor never fires, and the EMA latches at its seed value.
    /// That silently disabled relative detection in playback. An audio clock cannot be outrun by setup,
    /// and behaves identically whether playback is real-time paced or not.
    var audioElapsed: Double = 0

    /// Hann window coefficients applied to audio samples before FFT to reduce spectral leakage
    /// - Note: The window is pre-computed during initialization for performance
    var window: [Float] = []
    
    // MARK: - Published Output Properties
    
    /// Frequency spectrum magnitudes in dB scale
    /// - Note: Array length is `fftSize / 2`, ranging from -100 dB to ~0 dB
    @Published var magnitudes: [Float]
    
    /// Frequency values corresponding to each magnitude bin, in Hz
    /// - Note: Array length is `fftSize / 2`, evenly spaced from 0 Hz to Nyquist frequency
    @Published var frequencies: [Float]
    
    /// The frequency with the highest magnitude in the current frame, in Hz
    @Published var peakFrequency: Float = 0
    
    /// The magnitude of the peak frequency in dB
    /// Initialize to -100 dB (very quiet) to prevent false "above threshold" detection on startup
    @Published var peakMagnitude: Float = -100
    
    /// Fast input level in dB - updated on every audio buffer callback (~43Hz with 1024 buffer)
    /// Use this for decay tracking instead of peakMagnitude which only updates per FFT frame
    @Published var inputLevelDB: Float = -100

    /// Edge-triggered clipping flag — `true` when any audio chunk in the last
    /// ``clipHoldSeconds`` reached full scale (sample |x| ≥ 0.99) or RMS ≥ 0
    /// dBFS, `false` otherwise.  Drives a remediation message in the status
    /// bar (``TapToneAnalyzer`` swaps the displayed `statusMessage` when this toggles).  Mirrors Python
    /// `_FftProcessingThread.clippingChanged` signal + `is_clipping` flag.
    @Published var isClipping: Bool = false

    /// Hold any clip-detected chunk for this many seconds before declaring the
    /// input "no longer clipping".  Without the hold, the indicator would
    /// flicker every chunk as the signal oscillates around full scale during
    /// a tap's attack.
    let clipHoldSeconds: TimeInterval = 1.5

    /// Wall-clock time of the most recent chunk that triggered the clipping
    /// detector.  Compared against `clipHoldSeconds` on every chunk to drive
    /// the True→False transition of `isClipping`.
    var lastClipTime: Date?

    /// Input level gated to the FFT publish rate for display purposes.
    /// Updates in lockstep with `magnitudes`/`peakMagnitude` (i.e. at the FFT frame rate),
    /// so the status-bar level number refreshes at the same cadence as the graph.
    @Published var displayLevelDB: Float = -100
    
    /// Maximum input level observed over the last `peakHoldDuration` seconds (dBFS).
    ///
    /// Updated on every audio buffer callback (~43 Hz). Because the continuous FFT
    /// window is ~1.4 s, `peakMagnitude` lags the actual tap transient by up to that
    /// amount. `recentPeakLevelDB` captures the true tap peak before the FFT result
    /// arrives, and is used by ``TapToneAnalyzer`` as the `tapPeakLevel` reference for
    /// decay tracking.
    ///
    /// - Note: The hold duration is 2 seconds — longer than the worst-case FFT
    ///   processing latency (~1.5 s for 65 536 samples at 44.1 kHz).
    @Published var recentPeakLevelDB: Float = -100

    /// Timestamp of the most recent `recentPeakLevelDB` update; used to detect hold expiry.
    var recentPeakTime: Date = Date.distantPast

    /// Duration in seconds for which `recentPeakLevelDB` is held after a peak.
    let peakHoldDuration: TimeInterval = 2.0

    /// Counter that increments each time the engine restarts due to an audio route change.
    ///
    /// ``TapToneAnalyzer`` observes this via a Combine sink to reset its warm-up timer
    /// and `isAboveThreshold` state after a route change restart.
    @Published var routeChangeRestartCount: Int = 0
    
    // MARK: - Microphone Calibration
    
    /// The currently active microphone calibration, if any
    /// When set, calibration corrections are applied to FFT magnitude data
    @Published var activeCalibration: MicrophoneCalibration? {
        didSet {
            // Pre-compute corrections for current frequency bins when calibration changes
            updateCalibrationCorrections()
            
            // Skip saving device mapping if we're just loading a device-specific calibration
            guard !isLoadingDeviceCalibration else { return }
            
            // Persist the selection globally and associate with current device
            if let calibration = activeCalibration {
                CalibrationStorage.shared.activeCalibrationID = calibration.id
                
                // Also associate this calibration with the current device
                if let deviceUID = selectedInputDevice?.uid {
                    CalibrationStorage.shared.setCalibration(calibration.id, forDeviceUID: deviceUID)
                    gtLog("📊 Associated calibration '\(calibration.name)' with device '\(selectedInputDevice?.name ?? "unknown")'")
                }
            } else {
                CalibrationStorage.shared.activeCalibrationID = nil
                
                // Clear the device-specific mapping too
                if let deviceUID = selectedInputDevice?.uid {
                    CalibrationStorage.shared.setCalibration(nil, forDeviceUID: deviceUID)
                }
            }
        }
    }

    /// Temporarily overrides the active calibration for file playback.
    ///
    /// Unlike setting `activeCalibration` directly, this method does **not**
    /// persist the change to `CalibrationStorage` or the device-calibration
    /// mapping.  It reuses the existing `isLoadingDeviceCalibration` guard
    /// to suppress the `didSet` persistence logic.
    ///
    /// Call with `nil` to restore the previous calibration after playback.
    func setTemporaryCalibration(_ calibration: MicrophoneCalibration?) {
        isLoadingDeviceCalibration = true
        activeCalibration = calibration
        isLoadingDeviceCalibration = false
    }
    
    /// Pre-computed calibration corrections for each frequency bin
    /// This avoids interpolation overhead during real-time FFT processing
    var calibrationCorrections: [Float] = []

    // MARK: - Raw Sample Callback (for gated FFT)

    /// Optional callback that receives raw PCM samples on `audioProcessingQueue`.
    ///
    /// Set by ``TapToneAnalyzer`` to feed the gated FFT pre-roll ring buffer and
    /// the gated accumulation buffer used for plate/brace measurements. Called on
    /// every audio buffer at the hardware callback rate (~43 Hz at 1024 samples).
    ///
    /// - Important: Do **not** update any `@Published` properties or touch UIKit/SwiftUI
    ///   from this callback — it runs on a background queue.
    var rawSampleHandler: (([Float], Double) -> Void)?

    // MARK: - Audio-Queue RMS Level Callback

    /// Optional callback fired **synchronously on the audio processing queue**
    /// for every chunk with the per-chunk RMS level in dBFS.
    ///
    /// Mirrors Python `proc_thread.rmsLevelChanged` signal.
    /// ``TapToneAnalyzer`` wires this to `onRmsLevelChanged(_:)` so tap
    /// detection runs at ~43 Hz per chunk, identically to Python's
    /// `_on_rms_level_changed`.
    ///
    /// - Important: The callback runs on a background queue.  The handler
    ///   is responsible for dispatching to the main thread if needed.
    /// Per-chunk RMS callback: `(levelDB, audioTime)`.
    ///
    /// `audioTime` is `audioElapsed` AT THE MOMENT THIS CHUNK WAS PROCESSED — it travels WITH the
    /// sample rather than being read later by the consumer. That matters: the handler may be delivered
    /// to the main thread asynchronously, and the audio thread races ahead. Reading `audioElapsed` at
    /// the consumer would give the CURRENT audio time, not this chunk's — which silently skipped the
    /// detection warm-up when the audio thread got ahead (as it does at the start of file playback).
    var rmsLevelHandler: ((Float, Double) -> Void)?

    // MARK: - Audio-Queue Level-Crossing Callback

    /// Optional callback fired **synchronously on the audio processing queue**
    /// the first time `inputLevelDB` crosses `levelCrossingThreshold` from
    /// below on a rising edge.
    ///
    /// ``TapToneAnalyzer`` sets this to snapshot the pre-roll ring buffer at the
    /// exact audio buffer where the signal crosses the threshold.  This
    /// eliminates the main-thread Combine dispatch delay that otherwise shifts
    /// the pre-roll past the tap attack transient before
    /// ``TapToneAnalyzer/startGuitarGatedCapture()`` runs.
    ///
    /// The handler is auto-disarmed (``levelCrossingArmed`` set `false`) after
    /// it fires to prevent repeated invocations during the same tap's ring-out.
    /// ``TapToneAnalyzer`` re-arms it when detection is re-enabled.
    ///
    /// - Important: Runs on `audioProcessingQueue` — do **not** touch
    ///   `@Published` properties or UI state from this callback.
    var levelCrossingHandler: (() -> Void)?

    /// The dBFS threshold for ``levelCrossingHandler``.
    ///
    /// Kept in sync with ``TapToneAnalyzer/tapDetectionThreshold`` so the audio-
    /// queue fast-path fires at the same (or slightly earlier) level as the
    /// main-thread hysteresis detector.
    var levelCrossingThreshold: Float = -40

    /// When `true`, the next rising-edge crossing of ``levelCrossingThreshold``
    /// — confirmed by ``levelCrossingConfirmationChunks`` consecutive
    /// above-threshold chunks — will fire ``levelCrossingHandler``.  Set
    /// `false` after it fires; re-armed by ``TapToneAnalyzer`` when tap
    /// detection is re-enabled.
    var levelCrossingArmed: Bool = false {
        didSet {
            if levelCrossingArmed != oldValue {
                let thread = Thread.isMainThread ? "main" : "audio"
                TAP_DEBUG("levelCrossingArm", "ARMED=\(levelCrossingArmed) (was \(oldValue)) thread=\(thread)")
                // Reset the confirmation counter whenever arming state
                // transitions, so a fresh rising edge is required after each
                // arm.  Without this reset, arming while the signal is
                // already above threshold (and a stale counter is non-zero)
                // could spuriously fire on the next chunk.
                levelCrossingConsecutiveAbove = 0
            }
        }
    }

    /// Number of consecutive above-threshold audio chunks required to confirm
    /// a level crossing before ``levelCrossingHandler`` is fired.
    ///
    /// At a 1024-sample chunk and 48 kHz sample rate each chunk is ~21 ms,
    /// so the default of `2` requires ~43 ms of sustained signal above the
    /// threshold.  This rejects brief 1-chunk broadband bumps — for example
    /// handling noise between plate-mode phases — while still firing
    /// reliably on real taps, including high-Q brace ring-outs that may
    /// only spend ~2 chunks above the rising threshold before the per-chunk
    /// RMS decays below it.
    ///
    /// **Why 2 and not 3:** the brace test fixture
    /// (`brace-umik-1-swift-mac-1778816093.wav`) has a real tap whose
    /// per-chunk RMS drops below threshold after only the second chunk:
    ///   chunk 1: RMS -47.76 dB (above)
    ///   chunk 2: RMS -52.48 dB (above)
    ///   chunk 3: RMS -54.80 dB (below)
    /// A confirmation requirement of 3 would reject this real tap.  The
    /// observed plate-mode bump in `plate-umik-1-swift-mac-1778816330.wav`
    /// is a single-chunk excursion (RMS -46.78 dB then -53.55 dB), so 2
    /// already rejects it.
    ///
    /// The trade-off vs `1` (legacy fire-on-first-crossing):
    /// - Pros: filters single-chunk noise events that previously triggered
    ///   bogus gated captures — especially during file playback, which has
    ///   no human review-time gap between phases.
    /// - Cons: trigger fires `levelCrossingConfirmationChunks - 1` chunks
    ///   later than before.  `alignCaptureToOnset` compensates by
    ///   anchoring the FFT window to the sample-precise tap onset, so the
    ///   FFT input is unchanged.  A bump spanning 2+ chunks could still
    ///   slip through; a louder/higher value would start cutting into
    ///   weak marginal taps like the brace example above.
    ///
    /// This constant is also consulted by the main-thread tap detector
    /// (`TapToneAnalyzer.detectTap`) so both rising-edge paths apply
    /// the same confirmation logic — otherwise a bump rejected here can
    /// still fire the main-thread detector and start a bogus capture.
    static let levelCrossingConfirmationChunks: Int = 2

    /// Running count of consecutive above-threshold chunks within the
    /// current candidate rising-edge run.  Reset to `0` whenever the level
    /// drops back below threshold or arming state changes.  Counts up while
    /// armed and waiting for confirmation; once it reaches
    /// ``RealtimeFFTAnalyzer/levelCrossingConfirmationChunks`` the handler
    /// fires and the level crossing is disarmed.
    var levelCrossingConsecutiveAbove: Int = 0

    /// Tracks the previous buffer's level for rising-edge detection on the
    /// audio queue.  Updated every buffer inside ``processAudioBuffer(_:)``.
    var previousLevelDB: Float = -100
    
    /// Suppresses re-saving the device→calibration mapping during auto-load.
    ///
    /// When `selectedInputDevice.didSet` auto-loads a device-specific calibration,
    /// setting `activeCalibration` would normally also persist a new device mapping.
    /// This flag breaks the feedback loop so the association is only written
    /// when the user explicitly changes the calibration.
    var isLoadingDeviceCalibration = false

    #if os(macOS)
    /// Retained block for the CoreAudio `kAudioHardwarePropertyDevices` listener.
    /// Fires on any device connect/disconnect event and triggers
    /// `loadAvailableInputDevices()`.
    var hardwareListenerBlock: AudioObjectPropertyListenerBlock?

    /// Retained block for the CoreAudio `kAudioDevicePropertyNominalSampleRate`
    /// listener on the currently selected device. Fires when the user changes
    /// the sample rate in Audio MIDI Setup while the engine is running.
    var sampleRateListenerBlock: AudioObjectPropertyListenerBlock?

    /// The `AudioDeviceID` the sample-rate listener is currently registered
    /// against, or `0` if no listener is registered.
    var sampleRateListenerDeviceID: AudioDeviceID = 0
    #endif
    
    /// Indicates whether the analyzer is currently running and processing audio.
    @Published var isRunning: Bool = false

    // MARK: - WAV File Playback

    /// Identity token for the active file-playback worker.  Incremented each
    /// time `startFromFile` launches a new worker; the worker checks this value
    /// on each chunk to detect supersession by a newer playback.  Mirrors
    /// Python's `sentinel` list / `_file_playback_thread` identity guard.
    var filePlaybackGeneration: Int = 0

    /// True when audio is being sourced from a file rather than the microphone.
    /// The view observes this to show a "File" label near the device selector.
    @Published var isPlayingFile: Bool = false

    /// The display name (filename without extension) of the file currently being played,
    /// or nil when the audio source is the microphone.  Used as the chart title.
    @Published var playingFileName: String? = nil

    /// Called from the `startFromFile` asyncAfter block after the input buffer
    /// flush but BEFORE `try? self.start()` restarts the mic.  Used by
    /// `TapToneAnalyzer` to zero-pad and complete any active gated capture so
    /// mic noise cannot fill the remaining window.
    /// Mirrors Python `_on_pre_mic_restart` callback.
    var preMicRestartHandler: (() -> Void)?

    /// Called from `startFromFile` after the mic engine is stopped and the
    /// audio processing queue is drained, but BEFORE any file chunks are
    /// pumped.  Used by `TapToneAnalyzer` to clear `preRollBuffer` so no
    /// stale mic noise leaks into the gated capture's pre-roll seed.
    /// Mirrors Python: the mic stream is stopped before `_playback_worker`
    /// starts, so the pre-roll buffer naturally contains no mic audio.
    var postEngineStopHandler: (() -> Void)?

    /// Set to true when permission is confirmed denied after start (macOS TCC cache lag).
    /// The view observes this to show the "Microphone Access Required" alert.
    /// Reset to false after the alert has been handled.
    @Published var microphonePermissionDenied: Bool = false

    #if os(macOS)
    /// Called on the main thread when the user grants microphone permission during the
    /// first-launch `requestAccess` dialog. Set by `TapToneAnalyzer` so the full
    /// `TapToneAnalyzer.start()` path (which sets `warmupStartAudioTime` and kicks off
    /// `startTapSequence`) is taken instead of restarting only the FFT engine.
    var onPermissionGranted: (() -> Void)?

    /// Set true on the main thread the moment the user grants microphone permission, so the
    /// 3-second post-start silence check (RealtimeFFTAnalyzer+EngineControl) does not misread
    /// the brief HAL input-acquisition transition as a denial and show a false
    /// "Microphone Access Required" alert. Cleared by that check after one cycle.
    var permissionJustGranted: Bool = false
    #endif
    
    // MARK: - Performance and Analysis Metrics
    
    /// Frequency resolution in Hz - the frequency span of each FFT bin
    /// Calculated as: sampleRate / fftSize
    @Published var frequencyResolution: Float = 0
    
    /// Bandwidth in Hz - the total frequency range being analyzed (DC to Nyquist)
    /// Calculated as: sampleRate / 2
    @Published var bandwidth: Float = 0
    
    /// Sample length in time (seconds) - the duration of audio in each FFT window
    /// Calculated as: fftSize / sampleRate
    @Published var sampleLengthSeconds: Float = 0
    
    /// Frame rate in Hz - how many FFT analyses are performed per second
    /// Calculated as: sampleRate / fftSize (0% overlap, hop = fftSize)
    @Published var frameRate: Float = 0
    
    /// Processing time in milliseconds - time taken to process the last FFT frame
    @Published var processingTimeMs: Float = 0
    
    /// Average processing time over the last several frames (milliseconds)
    @Published var avgProcessingTimeMs: Float = 0
    
    /// Circular buffer for tracking recent processing times
    var processingTimeHistory: [Float] = []
    /// Number of recent frames retained for the processing-time moving average.
    let processingTimeHistorySize = 30
    
    /// Tracks the last time we published UI updates to avoid flooding the main queue
    var lastPublishTime: CFAbsoluteTime = 0
    /// Minimum interval between UI publishes (0.5 s ≈ 2 Hz) to avoid overwhelming SwiftUI.
    let minPublishInterval: CFAbsoluteTime = 0.5  // Update every 500ms (2 Hz) to avoid overwhelming SwiftUI
    
    // MARK: - Debug Tracking

    /// `true` after the first audio buffer callback fires. Used by the 3-second
    /// post-start check to distinguish "no buffers delivered" (hardware/permission
    /// problem) from "buffers delivered but silent" (TCC muted stream on macOS).
    var firstBufferReceived = false

    /// Running count of completed FFT frames, used to throttle console logging
    /// (prints every 30 frames, roughly every 15 s at 2 Hz frame rate).
    var fftCount = 0

    /// Time at which the audio engine most recently started. Used in the 3-second
    /// post-start diagnostic to determine whether to warn about missing buffers.
    var engineStartTime: Date?

    // MARK: - Buffer-delivery Watchdog
    //
    // Recovers from a silently-wedged audio I/O context: the tap stops delivering
    // buffers with no thrown error (e.g. another app forces the shared input through
    // a CADefaultDeviceAggregate, a sleep/wake, or an OS HAL glitch). Nothing else
    // notices, so the spectrum freezes indefinitely. A repeating timer detects the
    // silence and performs a clean, bounded, backed-off restart via `start()`.

    /// Monotonic timestamp (`CACurrentMediaTime`) of the most recent tap buffer.
    /// Stamped on the audio thread; read on the main thread by the watchdog.
    var lastBufferTime: CFTimeInterval = 0

    /// Repeating main-runloop timer that checks for buffer starvation.
    var watchdogTimer: Timer?

    /// Re-entrancy guard so overlapping notifications can't stack recovery restarts.
    var isRecoveringEngine = false

    /// Consecutive recovery attempts; reset to 0 once buffers resume.
    var watchdogRecoveryAttempts = 0

    /// Seconds with zero delivered buffers before the I/O is considered wedged.
    let watchdogSilenceThreshold: CFTimeInterval = 2.5

    /// Give up (and surface an error) after this many consecutive failed restarts,
    /// so a genuinely-unavailable device can't cause a restart storm.
    let watchdogMaxAttempts = 6

    // MARK: - Dead-input Watchdog
    //
    // A second, distinct failure mode: buffers keep arriving on schedule but carry
    // NO SIGNAL. Delivery looks perfectly healthy — `lastBufferTime` is stamped by
    // every buffer regardless of content — so the buffer-delivery watchdog above is
    // blind to it, the spectrum keeps updating, and every reading is silence.
    // Observed on macOS with a USB mic after wake-from-sleep and while idling
    // between taps: the AUHAL survives the device re-enumerating underneath it and
    // renders zeros forever.
    //
    // The discriminator is deliberately "impossibly quiet", never merely "quiet". A
    // real microphone always delivers its own self-noise — a UMIK-1 sits tens of dB
    // above this floor even in a silent room — so sustained near-digital-zero means
    // a dead stream, not a quiet workshop, and a legitimately silent room can never
    // trigger a restart.

    /// Monotonic timestamp (`CACurrentMediaTime`) of the last buffer that carried
    /// any signal at all. Stamped on the audio processing queue; read on the main
    /// thread by the watchdog (same relaxed access pattern as `lastBufferTime`).
    var lastSignalTime: CFTimeInterval = 0

    /// RMS below which a buffer counts as carrying no signal: 1e-5 = **-100 dBFS**.
    ///
    /// Calibrated from the recorded incidents (hub `AUDIO-WATCHDOG-SILENT-STREAM.md`),
    /// not from theory. A dead-but-present device was measured pinned at ≈ -100 dBFS
    /// while a live room reads ≈ -70 dBFS and a UMIK-1's Air peak ≈ -63 dBFS.
    ///
    /// Deliberately set at the BOTTOM of that range rather than mid-way. The UMIK-1 is
    /// an unusually quiet microphone and can sit near -90 dBFS in a silent room, so a
    /// mid-range threshold would call a quiet workshop a dead input and restart the
    /// engine during a measurement. The asymmetry is the point: a missed detection
    /// costs one more watchdog cycle, a false positive interrupts real work. Anything a
    /// live microphone produces — including a very quiet one in a silent room — stays
    /// clear of -100 dBFS; only a stream that is not producing audio at all goes below.
    ///
    /// RMS rather than peak deliberately: the documented floor/peak figures above are
    /// RMS-based, and all three editions must apply the identical criterion (peak is
    /// always ≥ RMS, so mixing them would give the ports different sensitivities).
    let deadInputRMSThreshold: Float = 1e-5

    /// Seconds of unbroken no-signal buffers before the input is considered dead.
    /// Much longer than the delivery threshold: this one infers from content, and a
    /// recorded incident persisted for minutes, so there is no value in being hasty
    /// and real cost in fighting a user who has legitimately muted their input.
    let watchdogDeadInputThreshold: CFTimeInterval = 15.0

    /// True once the input has produced real signal at any point since launch.
    ///
    /// The discriminator between "the OS is muting us" and "the device died": macOS
    /// permission cannot be silently revoked and re-granted mid-session, so silence
    /// that follows working audio is a dead input, never a permission problem. The
    /// post-start denial check relies on this to stop blaming the user's microphone
    /// permissions for a hardware failure.
    var hasEverReceivedSignal: Bool = false

    /// True once recovery has exhausted its attempts. Restart attempts stop, but the
    /// watchdog keeps WATCHING, so the app heals itself the moment audio returns
    /// instead of staying dead until it is relaunched.
    var watchdogRecoveryExhausted: Bool = false

    /// True while the input is delivering buffers that carry no signal.
    ///
    /// Surfaced in the status line rather than only auto-healed: the device-level
    /// failure in the recorded incidents could NOT be fixed by restarting the engine
    /// (it needed a USB re-enumeration), so recovery exhausts its attempts and stops.
    /// An app that says "no audio input" beats an app that looks alive while deaf.
    @Published var inputAppearsDead: Bool = false

    /// Observer token for `AVAudioEngineConfigurationChange`, held so it can be
    /// removed when the engine stops.
    var configurationChangeObserver: NSObjectProtocol?

    // MARK: - Testing Support

    /// When `true`, the analyzer was created via ``forTesting()`` and has no
    /// audio hardware wired.  Checked by `deinit` to skip hardware teardown and
    /// by `start()`/`stop()` to short-circuit engine operations.
    /// Mirrors Python `RealtimeFFTAnalyzer.for_testing()` which sets `stream = None`.
    private(set) var isForTesting: Bool = false

    /// Creates a `RealtimeFFTAnalyzer` suitable for unit testing.
    ///
    /// The returned instance has a fully functional FFT pipeline (vDSP setup,
    /// window, buffers, queues) but **no audio hardware**: no `AVAudioEngine`
    /// start, no device enumeration, no CoreAudio/route-change listeners.
    /// Use ``processFileData(samples:sampleRate:fileName:)`` to feed audio.
    ///
    /// The FFT size is the class-level constant (65 536); it is not
    /// configurable per-instance.
    ///
    /// Mirrors Python `RealtimeFFTAnalyzer.for_testing()`.
    static func forTesting() -> RealtimeFFTAnalyzer {
        return RealtimeFFTAnalyzer(forTesting: true)
    }

    // MARK: - Initialization
    
    /// Creates a new real-time FFT analyzer.
    ///
    /// The FFT size is the class-level constant (65 536) and cannot be
    /// overridden.  At 48 kHz this gives ≈0.73 Hz/bin resolution.
    ///
    /// - Parameter forTesting: When `true`, skips all audio hardware setup
    ///   (device enumeration, CoreAudio listeners, route-change observers).
    ///   The FFT pipeline is fully functional — only hardware I/O is omitted.
    ///   Default is `false`.
    init(forTesting: Bool = false) {
        self.isForTesting = forTesting
        self.audioEngine = AVAudioEngine()
        // inputNode is intentionally not accessed here — accessing it in init touches the
        // audio hardware and triggers -10877 (kAudioUnitErr_Unauthorized) on macOS when
        // permission was recently revoked. It is assigned in start() after the permission check.
        
        // Initialize FFT setup using vDSP's optimized DFT functions
        // This setup object is reused for all FFT operations for performance
        self.fftSetup = vDSP_DFT_zrop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            vDSP_DFT_Direction.FORWARD
        )
        
        // Pre-allocate output arrays to avoid repeated allocations
        // Initialize with -100 dB (very quiet) as a sensible default
        self.magnitudes = [Float](repeating: -100, count: fftSize / 2)
        self.frequencies = [Float](repeating: 0, count: fftSize / 2)
        
        // Rectangular window (all ones) for the continuous real-time display path.
        // A Hann window would reduce spectral leakage, but for a live monitoring
        // display flat amplitude response is preferable to sidelobe suppression, and
        // the rectangular window avoids the ~50% amplitude reduction that Hann applies
        // to samples near the frame edges. The gated FFT path (computeGatedFFT) uses
        // Hann instead, because that result is what gets saved and analysed.
        self.window = [Float](repeating: 0, count: fftSize)
        var one: Float = 1.0
        vDSP_vfill(&one, &window, 1, vDSP_Length(fftSize))
        
        // Note: Don't call updateFrequencyBins() or updateMetrics() here
        // because actualSampleRate is still 0. They will be called in start()
        // after the engine is running and actualSampleRate is known.

        // Skip all hardware setup when created for testing.
        // Mirrors Python for_testing() which sets stream = None and skips
        // _start_hotplug_monitor() and sd.InputStream() creation.
        guard !forTesting else { return }
        
        // Load available audio input devices
        // Note: This will trigger selectedInputDevice didSet which loads device-specific calibration
        loadAvailableInputDevices()

        #if os(macOS)
        // Register CoreAudio listener for device connect/disconnect on macOS
        registerMacOSHardwareListener()
        #endif

        #if os(iOS)
        // Observe audio route changes on iOS
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        #endif
    }
    
    /// Cleans up resources when the analyzer is deallocated
    deinit {
        if !isForTesting {
            stop()
        }
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }

        guard !isForTesting else { return }

        #if os(macOS)
        unregisterMacOSHardwareListener()
        #endif

        #if os(iOS)
        // Remove audio session observers
        NotificationCenter.default.removeObserver(self)
        #endif
    }
}
