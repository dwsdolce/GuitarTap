//
//  RealtimeFFTAnalyzer.swift
//  GuitarTap
//
//  Created by David Smith on 12/31/25.
//

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
///        │         ├─ RMS level → inputLevelDB / recentPeakLevelDB (main thread, ~10 Hz)
///        │         ├─ rawSampleHandler → TapToneAnalyzer pre-roll + gated capture
///        │         └─ inputBuffer accumulation
///        │                  └─ when ≥ fftSize samples:
///        │                         performFFT(on:) → magnitudes / peakMagnitude (main, ~2 Hz)
///
/// computeGatedFFT(samples:sampleRate:) — called externally by TapToneAnalyzer,
///        not part of the continuous tap path
/// ```
///
/// ## Continuous vs. Gated FFT
/// The **continuous** path produces one spectrum frame per hop interval. The
/// frame rate is controlled by `hopSizeOverlap`:
/// ```
/// hop = fftSize × (1 − overlap/100)
/// frameRate = sampleRate / hop
/// ```
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
/// let analyzer = RealtimeFFTAnalyzer(fftSize: 16384, targetSampleRate: 48000)
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
                    print("📊 Auto-loaded calibration '\(deviceCalibration.name)' for device '\(selectedInputDevice?.name ?? "unknown")'")
                } else {
                    // No calibration for this device - clear any active calibration
                    setCalibrationWithoutSavingDeviceMapping(nil)
                    print("📊 No calibration for device '\(selectedInputDevice?.name ?? "unknown")' - using uncalibrated mode")
                }
            }

            #if os(macOS)
            // On macOS, if the engine is running and this change came from the user
            // (not from setInputDevice's own assignment), restart the engine with the new device.
            guard !isApplyingDeviceSwitch, isRunning, selectedInputDevice?.uid != oldValue?.uid else { return }
            print("🔄 Device changed while running — restarting engine for: \(selectedInputDevice?.name ?? "unknown")")
            isApplyingDeviceSwitch = true
            stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                do {
                    try self.start()
                    print("✅ Engine restarted with new device: \(self.selectedInputDevice?.name ?? "unknown")")
                } catch {
                    print("❌ Failed to restart engine after device change: \(error)")
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
    
    /// The size of the FFT window. Must be a power of 2.
    /// Larger sizes provide better frequency resolution but slower time response.
    /// - Note: Output will contain `fftSize / 2` frequency bins
    let fftSize: Int
    
    /// The vDSP FFT setup object used for performing fast Fourier transforms
    /// - Note: This is created once during initialization and reused for performance
    var fftSetup: vDSP_DFT_Setup?
    
    // MARK: - Sample Rate Management
    
    /// The desired sample rate for FFT processing
    /// - Note: If the hardware sample rate differs, audio will be resampled to match this rate
    let targetSampleRate: Double
    
    /// Whether to use hardware sample rate directly instead of resampling
    /// - Note: When true, targetSampleRate is ignored and hardware rate is used
    let useHardwareSampleRate: Bool
    
    /// The actual sample rate of the audio hardware in Hz.
    /// - Note: This is determined at runtime when the audio engine starts; 0 when stopped.
    @Published var actualSampleRate: Double = 0
    
    /// Hop size overlap percentage (0-75%)
    /// - Note: 0% = no overlap (hop size = fftSize), 75% = maximum overlap (hop size = fftSize/4)
    /// - Default: 0% for maximum frame rate (loaded from persisted settings)
    @Published var hopSizeOverlap: Float = TapDisplaySettings.hopSizeOverlap
    
    // MARK: - Audio Buffers
    
    /// Accumulates incoming audio samples until there's enough data for FFT processing
    /// - Note: Samples are removed with configurable overlap for smoother frequency response
    /// - Important: Access only on bufferAccessQueue to prevent race conditions
    var inputBuffer: [Float] = []
    
    /// Buffer for storing resampled audio data when hardware sample rate differs from target
    var resampledBuffer: [Float] = []
    
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

    /// Input level gated to the FFT publish rate for display purposes.
    /// Updates in lockstep with `magnitudes`/`peakMagnitude` (i.e. at the FFT frame rate),
    /// so the status-bar level number refreshes at the same cadence as the graph.
    @Published var displayLevelDB: Float = -100
    
    /// Maximum input level observed over the last `peakHoldDuration` seconds (dBFS).
    ///
    /// Updated on every audio buffer callback (~10 Hz). Because the continuous FFT
    /// window is ~400 ms, `peakMagnitude` lags the actual tap transient by up to that
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
                    print("📊 Associated calibration '\(calibration.name)' with device '\(selectedInputDevice?.name ?? "unknown")'")
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
    
    /// Pre-computed calibration corrections for each frequency bin
    /// This avoids interpolation overhead during real-time FFT processing
    var calibrationCorrections: [Float] = []

    // MARK: - Raw Sample Callback (for gated FFT)

    /// Optional callback that receives raw PCM samples on `audioProcessingQueue`.
    ///
    /// Set by ``TapToneAnalyzer`` to feed the gated FFT pre-roll ring buffer and
    /// the gated accumulation buffer used for plate/brace measurements. Called on
    /// every audio buffer at the hardware callback rate (~10 Hz at 1024 samples).
    ///
    /// - Important: Do **not** update any `@Published` properties or touch UIKit/SwiftUI
    ///   from this callback — it runs on a background queue.
    var rawSampleHandler: (([Float], Double) -> Void)?
    
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
    
    /// Applies a calibration without persisting a device→calibration mapping.
    ///
    /// Used by `selectedInputDevice.didSet` when auto-loading a device-specific
    /// calibration from `CalibrationStorage`. Setting `activeCalibration` directly
    /// would trigger `activeCalibration.didSet`, which would re-save the mapping and
    /// create a redundant write. The `isLoadingDeviceCalibration` guard breaks the loop.
    func setCalibrationWithoutSavingDeviceMapping(_ calibration: MicrophoneCalibration?) {
        isLoadingDeviceCalibration = true
        activeCalibration = calibration
        isLoadingDeviceCalibration = false
    }

    /// Indicates whether the analyzer is currently running and processing audio.
    @Published var isRunning: Bool = false

    /// Set to true when permission is confirmed denied after start (macOS TCC cache lag).
    /// The view observes this to show the "Microphone Access Required" alert.
    /// Reset to false after the alert has been handled.
    @Published var microphonePermissionDenied: Bool = false
    
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
    /// Depends on hop size (overlap). With 25% overlap: sampleRate / (fftSize * 3/4)
    @Published var frameRate: Float = 0
    
    /// Processing time in milliseconds - time taken to process the last FFT frame
    @Published var processingTimeMs: Float = 0
    
    /// Average processing time over the last several frames (milliseconds)
    @Published var avgProcessingTimeMs: Float = 0
    
    /// Circular buffer for tracking recent processing times
    var processingTimeHistory: [Float] = []
    let processingTimeHistorySize = 30  // Track last 30 frames
    
    /// Tracks the last time we published UI updates to avoid flooding the main queue
    var lastPublishTime: CFAbsoluteTime = 0
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
    
    // MARK: - Initialization
    
    /// Creates a new real-time FFT analyzer with specified configuration.
    ///
    /// - Parameters:
    ///   - fftSize: The size of the FFT window. Must be a power of 2. Larger values provide
    ///              better frequency resolution but slower time response. Default is 4096.
    ///              Common values: 2048, 4096, 8192, 16384
    ///   - targetSampleRate: The desired sample rate for processing. Default is 44100 Hz.
    ///                      If hardware uses a different rate, audio will be resampled.
    ///   - useHardwareSampleRate: If true, uses hardware's native sample rate instead of resampling.
    ///                           Default is true for better performance and compatibility.
    ///
    /// - Note: The frequency resolution will be `sampleRate / fftSize` Hz per bin.
    ///         For example, 48000 Hz / 16384 = ~2.93 Hz per bin.
    init(fftSize: Int = 4096, targetSampleRate: Double = 44100, useHardwareSampleRate: Bool = true) {
        self.fftSize = fftSize
        self.targetSampleRate = targetSampleRate
        self.useHardwareSampleRate = useHardwareSampleRate
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
        stop()
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }

        #if os(macOS)
        unregisterMacOSHardwareListener()
        #endif

        #if os(iOS)
        // Remove audio session observers
        NotificationCenter.default.removeObserver(self)
        #endif
    }
}
