//
//  RealtimeFFTAnalyzer.swift
//  GuitarTap
//
//  Created by David Smith on 12/31/25.
//

import SwiftUI
import AVFoundation
import Accelerate
import Charts
import Combine

#if os(macOS)
import AudioToolbox
import CoreAudio
#endif

// MARK: - FFT Analyzer

/// A real-time Fast Fourier Transform (FFT) analyzer that captures audio from the device's microphone
/// and computes frequency spectrum data for visualization.
///
/// This class uses Apple's Accelerate framework for high-performance FFT calculations and AVFoundation
/// for audio capture. It handles sample rate conversion, windowing, and converts the FFT output to
/// a logarithmic dB scale suitable for audio visualization.
///
/// ## Example Usage
/// ```swift
/// let analyzer = RealtimeFFTAnalyzer(fftSize: 16384, targetSampleRate: 48000)
/// try analyzer.start()
/// // Access analyzer.magnitudes and analyzer.frequencies for visualization
/// analyzer.stop()
/// ```
///
/// - Note: This class requires microphone permissions. Ensure you've added the
///   `NSMicrophoneUsageDescription` key to your Info.plist file.
final class RealtimeFFTAnalyzer: ObservableObject {
    
    // MARK: - Audio Engine Components
    
    /// The main audio engine that manages audio processing graph and I/O
    private var audioEngine: AVAudioEngine
    
    /// The audio input node representing the device's microphone
    private var inputNode: AVAudioInputNode
    
    /// The currently selected audio input device
    @Published var selectedInputDevice: AVAudioDevice? {
        didSet {
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
        }
    }
    
    /// List of available audio input devices
    @Published var availableInputDevices: [AVAudioDevice] = []
    
    // MARK: - Thread Management
    
    /// Dedicated serial queue for audio processing to avoid blocking the main thread
    /// All audio buffer processing and FFT calculations happen on this queue
    private let audioProcessingQueue = DispatchQueue(
        label: "com.realtimefft.audioprocessing",
        qos: .userInteractive
    )
    
    /// Serial queue for synchronizing access to shared buffers
    /// Prevents race conditions when reading/writing audio data
    private let bufferAccessQueue = DispatchQueue(
        label: "com.realtimefft.bufferaccess",
        qos: .userInteractive
    )
    
    // MARK: - FFT Configuration
    
    /// The size of the FFT window. Must be a power of 2.
    /// Larger sizes provide better frequency resolution but slower time response.
    /// - Note: Output will contain `fftSize / 2` frequency bins
    private let fftSize: Int
    
    /// The vDSP FFT setup object used for performing fast Fourier transforms
    /// - Note: This is created once during initialization and reused for performance
    private var fftSetup: vDSP_DFT_Setup?
    
    // MARK: - Sample Rate Management
    
    /// The desired sample rate for FFT processing
    /// - Note: If the hardware sample rate differs, audio will be resampled to match this rate
    private let targetSampleRate: Double
    
    /// Whether to use hardware sample rate directly instead of resampling
    /// - Note: When true, targetSampleRate is ignored and hardware rate is used
    private let useHardwareSampleRate: Bool
    
    /// The actual sample rate of the audio hardware
    /// - Note: This is determined at runtime when the audio engine starts
    private var actualSampleRate: Double = 0
    
    /// Hop size overlap percentage (0-75%)
    /// - Note: 0% = no overlap (hop size = fftSize), 75% = maximum overlap (hop size = fftSize/4)
    /// - Default: 0% for maximum frame rate (loaded from persisted settings)
    @Published var hopSizeOverlap: Float = SpectrumDisplaySettings.hopSizeOverlap
    
    // MARK: - Audio Buffers
    
    /// Accumulates incoming audio samples until there's enough data for FFT processing
    /// - Note: Samples are removed with 50% overlap for smoother frequency response
    /// - Important: Access only on bufferAccessQueue to prevent race conditions
    private var inputBuffer: [Float] = []
    
    /// Buffer for storing resampled audio data when hardware sample rate differs from target
    private var resampledBuffer: [Float] = []
    
    /// Hann window coefficients applied to audio samples before FFT to reduce spectral leakage
    /// - Note: The window is pre-computed during initialization for performance
    private var window: [Float] = []
    
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
    
    /// Fast input level in dB - updated on every audio buffer callback (~10Hz with 4096 buffer)
    /// Use this for decay tracking instead of peakMagnitude which only updates per FFT frame
    @Published var inputLevelDB: Float = -100
    
    /// Recent peak input level in dB - tracks the maximum level over the last 2 seconds
    /// Use this to capture the actual tap peak even when FFT detection is delayed
    /// Must be longer than FFT processing time (~1.5s for 65536 samples @ 44.1kHz)
    
    /// Counter that increments each time the engine restarts due to an audio route change
    /// Observers can watch this to reset their state (e.g., warmup timers, threshold state)
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
    private var calibrationCorrections: [Float] = []
    
    /// Flag to prevent re-saving device mapping when loading device-specific calibration
    private var isLoadingDeviceCalibration = false

    #if os(macOS)
    /// Retained block for the CoreAudio hardware device-list change listener
    private var hardwareListenerBlock: AudioObjectPropertyListenerBlock?
    #endif
    
    /// Sets calibration without updating the device mapping (used when auto-loading device calibration)
    private func setCalibrationWithoutSavingDeviceMapping(_ calibration: MicrophoneCalibration?) {
        isLoadingDeviceCalibration = true
        activeCalibration = calibration
        isLoadingDeviceCalibration = false
    }
    @Published var recentPeakLevelDB: Float = -100
    private var recentPeakTime: Date = Date.distantPast
    private let peakHoldDuration: TimeInterval = 2.0  // How long to hold the peak
    
    /// Indicates whether the analyzer is currently running and processing audio
    @Published var isRunning: Bool = false // {
//        didSet {
//            print("🔄 isRunning changed from \(oldValue) to \(isRunning) on thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")")
//        }
//    }
    
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
    private var processingTimeHistory: [Float] = []
    private let processingTimeHistorySize = 30  // Track last 30 frames
    
    /// Tracks the last time we published UI updates to avoid flooding the main queue
    private var lastPublishTime: CFAbsoluteTime = 0
    private let minPublishInterval: CFAbsoluteTime = 0.5  // Update every 500ms (2 Hz) to avoid overwhelming SwiftUI
    
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
        self.inputNode = audioEngine.inputNode
        
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
        
        // Create Hann window for reducing spectral leakage
        // The Hann window tapers the edges of each audio frame to zero,
        // which reduces artifacts in the frequency domain
        self.window = [Float](repeating: 0, count: fftSize)
//        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        // Use a Boxcar window instead of Hann window
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
    
    // MARK: - Public Control Methods
    
    /// Starts the audio engine and begins capturing and analyzing audio from the microphone.
    ///
    /// This method:
    /// 1. Configures the audio input format
    /// 2. Installs a tap on the input node to receive audio buffers
    /// 3. Starts the audio engine
    /// 4. Updates the `isRunning` property on the main thread
    ///
    /// - Throws: An error if the audio engine fails to start or if microphone permissions are denied
    ///
    /// - Note: Requires microphone permissions. Add `NSMicrophoneUsageDescription` to Info.plist
    func start() throws {
        print("=== Starting Audio Engine ===")
        
        // CRITICAL: Always remove any existing tap to prevent "Tap already exists" error
        // This must be done BEFORE stopping or resetting the engine.
        // We always attempt removal regardless of audioEngine.isRunning state because:
        // 1. The tap can persist even after the engine stops
        // 2. Route changes can leave the engine in an inconsistent state
        // 3. removeTap() is safe to call even if no tap exists
        print("🔧 Removing any existing tap before restart...")
        inputNode.removeTap(onBus: 0)
        
        // Reset the audio engine to ensure clean state
        audioEngine.stop()
        audioEngine.reset()
        inputNode = audioEngine.inputNode
        
        #if os(macOS)
        // Request microphone permission explicitly on macOS
        // Note: On macOS 10.14+, apps need explicit permission to access the microphone
        print("🔐 Checking microphone permission...")
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("✅ Microphone permission: AUTHORIZED")
        case .notDetermined:
            print("⚠️ Microphone permission: NOT DETERMINED - requesting now...")
            // Request permission synchronously (this will show system dialog)
            let semaphore = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("🔐 Permission request result: \(granted ? "GRANTED" : "DENIED")")
                semaphore.signal()
            }
            semaphore.wait()
        case .denied:
            print("❌ Microphone permission: DENIED")
            print("   → Go to System Settings > Privacy & Security > Microphone")
            print("   → Enable permission for this app")
        case .restricted:
            print("⚠️ Microphone permission: RESTRICTED (parental controls or MDM)")
        @unknown default:
            print("⚠️ Microphone permission: UNKNOWN STATUS")
        }
        
        #endif
        
        #if os(iOS)
        // Configure audio session for recording (iOS only)
        print("🎙️ Configuring iOS audio session...")
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Set category to record mode
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            
            // Activate the session
            try audioSession.setActive(true, options: [])
            print("✅ Audio session activated successfully")
            
            // Log current session state
            print("   - Sample rate: \(audioSession.sampleRate) Hz")
            print("   - Input available: \(audioSession.isInputAvailable)")
            print("   - Input channels: \(audioSession.inputNumberOfChannels)")
            
            if let currentRoute = audioSession.currentRoute.inputs.first {
                print("   - Current input: \(currentRoute.portName)")
            } else {
                print("   ⚠️ WARNING: No input route detected!")
            }
        } catch {
            print("❌ Failed to configure audio session: \(error)")
            throw error
        }
        #endif
        
        // Start the audio engine
        // On macOS, device should already be configured above
        print("🎤 Starting audio engine...")
        try audioEngine.start()
        print("✅ Audio engine started")
        
        #if os(macOS)
        // CRITICAL FIX: Manually start the audio unit if it's not running
        // This is a workaround for a macOS bug where AVAudioEngine.start() succeeds
        // but the underlying Audio Unit doesn't actually start
        if let audioUnit = inputNode.audioUnit {
            // Check if it's running
            var isRunning: UInt32 = 0
            var isRunningSize = UInt32(MemoryLayout<UInt32>.size)
            var status = AudioUnitGetProperty(
                audioUnit,
                kAudioOutputUnitProperty_IsRunning,
                kAudioUnitScope_Global,
                0,
                &isRunning,
                &isRunningSize
            )
            
            if status == noErr && isRunning == 0 {
                print("⚠️ Audio unit not running after engine start - initializing and starting it...")
                
                // First, ensure the audio unit is initialized
                status = AudioUnitInitialize(audioUnit)
                if status != noErr && status != kAudioUnitErr_Initialized {
                    print("⚠️ Failed to initialize audio unit (error \(status))")
                } else if status == kAudioUnitErr_Initialized {
                    print("ℹ️ Audio unit already initialized")
                }
                
                // Now try to start it
                status = AudioOutputUnitStart(audioUnit)
                
                if status == noErr {
                    print("✅ Successfully started audio unit manually")
                    
                    // Verify it's now running
                    AudioUnitGetProperty(
                        audioUnit,
                        kAudioOutputUnitProperty_IsRunning,
                        kAudioUnitScope_Global,
                        0,
                        &isRunning,
                        &isRunningSize
                    )
                    print("🔍 Audio unit now running: \(isRunning == 1 ? "YES" : "NO")")
                } else {
                    print("❌ Failed to start audio unit manually (error \(status))")
                    print("   Error name: \(status == -10867 ? "kAudioUnitErr_Uninitialized" : status == -10875 ? "kAudioUnitErr_Uninitialized" : "Unknown")")
                }
            } else if status == noErr {
                print("✅ Audio unit already running")
            } else {
                print("⚠️ Could not check audio unit status (error \(status))")
            }
        }
        
        // Verify which device we're actually using
        if let audioUnit = inputNode.audioUnit {
            var actualDeviceID: AudioDeviceID = 0
            var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
            let getStatus = AudioUnitGetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &actualDeviceID,
                &propertySize
            )
            
            if getStatus == noErr {
                print("🎤 Actual device ID after start: \(actualDeviceID)")
                
                if let device = selectedInputDevice {
                    if actualDeviceID == device.deviceID {
                        print("✅ Using requested device: \(device.name)")
                    } else {
                        print("⚠️ Device mismatch! Requested \(device.deviceID) (\(device.name)), got \(actualDeviceID)")
                        print("   This usually means the device couldn't be set - using system default")
                    }
                }
            }
        }
        #endif
        
        // IMPORTANT: Ensure we have the latest input node reference after any restarts
        inputNode = audioEngine.inputNode
        
        // Get hardware format AFTER engine starts and input node is refreshed
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        actualSampleRate = hardwareFormat.sampleRate
        
        print("Hardware format: \(hardwareFormat)")
        print("Hardware sample rate: \(actualSampleRate) Hz")
        print("Channels: \(hardwareFormat.channelCount)")
        
        // Validate sample rate
        guard actualSampleRate > 0 else {
            audioEngine.stop()
            throw NSError(
                domain: "RealtimeFFTAnalyzer",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Audio hardware not available. Sample rate is 0 Hz. Check microphone permissions and ensure an audio input device is connected."]
            )
        }
        
        let effectiveSampleRate = useHardwareSampleRate ? actualSampleRate : targetSampleRate
        
        print("Target sample rate: \(targetSampleRate) Hz")
        print("Using sample rate: \(effectiveSampleRate) Hz")
        print("FFT size: \(fftSize)")
        
        // Create tap format matching hardware (use hardware channel count)
        // WORKAROUND: Some USB mics report 2 channels but are actually mono
        // If we detect this situation, force to 1 channel
        let effectiveChannelCount: AVAudioChannelCount
        if hardwareFormat.channelCount == 2 {
            print("⚠️ Device reports 2 channels - checking if it's actually mono...")
            // If the device name suggests it's a measurement mic (like UMIK), force mono
            if let deviceName = selectedInputDevice?.name.lowercased(),
               (deviceName.contains("umik") || deviceName.contains("measurement")) {
                effectiveChannelCount = 1
                print("   → Forcing to 1 channel (mono) for measurement microphone")
            } else {
                effectiveChannelCount = AVAudioChannelCount(hardwareFormat.channelCount)
            }
        } else {
            effectiveChannelCount = AVAudioChannelCount(hardwareFormat.channelCount)
        }
        
        guard let tapFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hardwareFormat.sampleRate,
            channels: effectiveChannelCount,
            interleaved: false
        ) else {
            audioEngine.stop()
            throw NSError(
                domain: "RealtimeFFTAnalyzer",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"]
            )
        }
        
        print("Tap format: \(tapFormat)")
        
        // CRITICAL FIX: Use smaller buffer size for large FFTs
        // Using 1024 samples (~23ms at 44.1kHz) for faster level metering updates
        // This improves decay measurement precision from ~100ms to ~23ms
        // FFT accuracy is unaffected since samples are accumulated to fftSize regardless
        let maxSafeBufferSize: AVAudioFrameCount = 1024
        let requestedBufferSize = min(AVAudioFrameCount(fftSize), maxSafeBufferSize)
        
        print("Requested buffer size: \(requestedBufferSize) samples (max safe: \(maxSafeBufferSize))")
        print("Will accumulate to: \(fftSize) samples for FFT")
        
        // Check if the input node is actually receiving data
        #if os(macOS)
        if let audioUnit = inputNode.audioUnit {
            // Check if the audio unit is running
            var isRunning: UInt32 = 0
            var isRunningSize = UInt32(MemoryLayout<UInt32>.size)
            let isRunningStatus = AudioUnitGetProperty(
                audioUnit,
                kAudioOutputUnitProperty_IsRunning,
                kAudioUnitScope_Global,
                0,
                &isRunning,
                &isRunningSize
            )
            
            if isRunningStatus == noErr {
                print("🔍 Audio unit running status: \(isRunning == 1 ? "YES" : "NO")")
            } else {
                print("⚠️ Could not check audio unit running status: \(isRunningStatus)")
            }
            
            // Check the input sample rate
            var inputSampleRate: Float64 = 0
            var inputSampleRateSize = UInt32(MemoryLayout<Float64>.size)
            let sampleRateStatus = AudioUnitGetProperty(
                audioUnit,
                kAudioUnitProperty_SampleRate,
                kAudioUnitScope_Input,
                1,  // Input element
                &inputSampleRate,
                &inputSampleRateSize
            )
            
            if sampleRateStatus == noErr {
                print("🔍 Audio unit input sample rate: \(inputSampleRate) Hz")
            }
        }
        #endif
        
        inputNode.installTap(onBus: 0, bufferSize: requestedBufferSize, format: tapFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            self.audioProcessingQueue.async {
                self.processAudioBuffer(buffer)
            }
        }
        print("✅ Audio tap installed successfully")
        
        // Update frequency bins based on effective sample rate
        // This ensures frequency labels are correct
        updateFrequencyBins()
        
        // Update metrics based on actual configuration
        updateMetrics()
        
//        print("Audio engine started successfully")
        
        // Update UI state - set isRunning to true on main thread
        DispatchQueue.main.async {
            self.isRunning = true
            self.engineStartTime = Date()  // Track start time
//            print("✓ Set isRunning = true - value is now: \(self.isRunning)")
            
            #if os(iOS)
            // Refresh device list now that audio session is fully configured
            // This ensures USB devices that weren't visible before are now available
            self.loadAvailableInputDevices()
            #endif
            
            // Set up a timeout to check if audio buffers are arriving
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self else { return }
                if self.isRunning && !self.firstBufferReceived {
                    print("⚠️ WARNING: Audio engine started but no audio buffers received after 3 seconds!")
                    print("⚠️ This usually means:")
                    print("   1. Microphone permission was denied (check System Settings > Privacy & Security > Microphone)")
                    print("   2. No input device is connected or selected")
                    print("   3. The input device is in use by another application")
                    print("⚠️ Try stopping and restarting, or check your audio input settings.")
                }
            }
        }
    }
    
    /// Stops the audio engine and releases audio resources.
    ///
    /// This method:
    /// 1. Removes the audio tap from the input node
    /// 2. Stops the audio engine
    /// 3. Updates the `isRunning` property on the main thread
    /// 4. Clears any pending audio processing tasks
    ///
    /// - Note: It's safe to call this method multiple times or when already stopped
    func stop() {
        print("🛑 Stop requested - engine running: \(audioEngine.isRunning), isRunning flag: \(isRunning)")
        
        // Always try to clean up, even if engine reports as not running
        // This handles cases where the engine started but never received audio
        if audioEngine.isRunning {
            // Remove the audio tap to stop receiving buffers
            inputNode.removeTap(onBus: 0)
            
            // Stop the audio engine
            audioEngine.stop()
            
            print("✅ Audio engine stopped")
        }
        
        // Clear the input buffer on the buffer access queue (async to avoid blocking)
        bufferAccessQueue.async {
            self.inputBuffer.removeAll()
        }
        
        // Reset debug tracking
        firstBufferReceived = false
        fftCount = 0
        engineStartTime = nil
        
        // ALWAYS update UI state on main thread, even if engine wasn't running
        // This ensures the UI is responsive even if the engine is in a bad state
        DispatchQueue.main.async {
            self.isRunning = false
            self.peakMagnitude = -100  // Reset to silent state
            self.peakFrequency = 0
            print("✅ isRunning set to false on main thread")
        }
    }
    
    // MARK: - Private Processing Methods
    
    // Debug tracking
    private var firstBufferReceived = false
    private var fftCount = 0
    private var engineStartTime: Date?  // Track when engine started for timeout detection
    
    /// Updates the frequency bin values based on the effective sample rate.
    ///
    /// Each bin represents a frequency range determined by:
    /// `frequency[i] = i * (sampleRate / fftSize)`
    ///
    /// For example, with a 48000 Hz sample rate and 16384 FFT size:
    /// - Bin 0 = 0 Hz (DC component)
    /// - Bin 1 = 2.93 Hz
    /// - Bin 2 = 5.86 Hz
    /// - ...
    /// - Bin 8192 = 24000 Hz (Nyquist frequency)
    private func updateFrequencyBins() {
        // Use effective sample rate based on configuration
        let effectiveSampleRate = useHardwareSampleRate ? actualSampleRate : targetSampleRate
        
        // Calculate the frequency resolution per bin
        let binWidth = Float(effectiveSampleRate) / Float(fftSize)
        
        // Populate frequency array - use local array to avoid publishing on background thread
        var newFrequencies = [Float](repeating: 0, count: fftSize / 2)
        for i in 0..<(fftSize / 2) {
            newFrequencies[i] = Float(i) * binWidth
        }
        
        // Update published property on main thread
        DispatchQueue.main.async {
            self.frequencies = newFrequencies
            // Re-compute calibration corrections for new frequency bins
            self.updateCalibrationCorrections()
        }
    }
    
    /// Updates pre-computed calibration corrections when calibration or frequencies change.
    ///
    /// Pre-computing corrections avoids real-time interpolation overhead during FFT processing.
    /// Called when:
    /// - A new calibration is loaded
    /// - Frequency bins are updated (sample rate changes)
    private func updateCalibrationCorrections() {
        guard let calibration = activeCalibration else {
            calibrationCorrections = []
            return
        }
        
        // Pre-compute corrections for all frequency bins
        calibrationCorrections = calibration.corrections(for: frequencies)
        print("📊 Calibration '\(calibration.name)' applied with \(calibration.correctionPoints.count) correction points")
    }
    
    /// Updates all performance and analysis metrics based on current configuration.
    ///
    /// This method calculates:
    /// - Frequency resolution (Hz per bin)
    /// - Bandwidth (total frequency range)
    /// - Sample length (time duration of each FFT window)
    /// - Frame rate (FFT calculations per second, accounting for overlap)
    private func updateMetrics() {
        // Use effective sample rate based on configuration
        let effectiveSampleRate = useHardwareSampleRate ? actualSampleRate : targetSampleRate
        let sampleRate = Float(effectiveSampleRate)
        let fftSizeFloat = Float(fftSize)
        
        // Calculate metrics
        let freqRes = sampleRate / fftSizeFloat
        let bw = sampleRate / 2.0
        let sampleLen = fftSizeFloat / sampleRate
        
        // Frame rate calculation based on hop size overlap setting
        // overlap% -> hop size multiplier
        // 0% -> 1.0 (no overlap, hop = fftSize)
        // 25% -> 0.75 (hop = fftSize * 3/4)
        // 50% -> 0.5 (hop = fftSize / 2)
        // 75% -> 0.25 (hop = fftSize / 4)
        let overlapFraction = hopSizeOverlap / 100.0
        let hopSizeMultiplier = 1.0 - overlapFraction
        let hopSize = fftSizeFloat * hopSizeMultiplier
        let fr = sampleRate / hopSize
        
        print("=== Analysis Metrics ===")
        print("Frequency Resolution: \(freqRes) Hz")
        print("Bandwidth: \(bw) Hz (0 Hz to \(bw) Hz)")
        print("Sample Length: \(sampleLen * 1000) ms (\(sampleLen) seconds)")
        print("Hop Size: \(Int(hopSize)) samples (\(Int(hopSizeOverlap))% overlap)")
        print("Frame Rate: \(fr) Hz")
        print("=======================")
        
        // Update published properties on main thread
        DispatchQueue.main.async {
            self.frequencyResolution = freqRes
            self.bandwidth = bw
            self.sampleLengthSeconds = sampleLen
            self.frameRate = fr
        }
    }
    
    /// Processes an incoming audio buffer from the microphone.
    ///
    /// This method:
    /// 1. Extracts float samples from the PCM buffer
    /// 2. Accumulates samples in the input buffer (thread-safe)
    /// 3. Processes complete FFT-size chunks with 50% overlap
    /// 4. Resamples audio if hardware rate differs from target rate
    /// 5. Performs FFT on each chunk
    ///
    /// - Parameter buffer: The audio buffer captured from the microphone
    ///
    /// - Note: This method runs on the audioProcessingQueue, not the main thread or audio thread.
    ///         All buffer access is synchronized via bufferAccessQueue to prevent race conditions.
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Safety check: ensure we have channel data
        guard let channelData = buffer.floatChannelData else {
            print("⚠️ No channel data in buffer!")
            return
        }
        
        // Extract samples from the first channel
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        
        // Debug: Print first time we receive audio
        if !firstBufferReceived {
            print("🎤 First audio buffer received! Frame length: \(frameLength)")
            print("🎤 Sample values (first 5): \(samples.prefix(5).map { String(format: "%.4f", $0) }.joined(separator: ", "))")
            firstBufferReceived = true
        }
        
        // Calculate fast input level (RMS) for decay tracking
        // This updates on every audio buffer (~10Hz with 4096 buffer) instead of per FFT frame
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        let levelDB = rms > 0 ? 20 * log10(rms) : -100
        let now = Date()
        
        // Update input level and recent peak on main thread
        DispatchQueue.main.async {
            self.inputLevelDB = levelDB
            
            // Track recent peak: update if current level is higher, or if peak has expired
            if levelDB > self.recentPeakLevelDB || now.timeIntervalSince(self.recentPeakTime) > self.peakHoldDuration {
                self.recentPeakLevelDB = levelDB
                self.recentPeakTime = now
            }
        }
        
        // Thread-safe: Accumulate samples in input buffer using synchronized access
        bufferAccessQueue.sync {
            inputBuffer.append(contentsOf: samples)
        }
        
        // Process when we have enough samples for an FFT
        // Calculate hop size based on overlap setting
        // overlap% -> hop size multiplier
        // 0% -> 1.0 (no overlap, hop = fftSize)
        // 25% -> 0.75 (hop = fftSize * 3/4)
        // 50% -> 0.5 (hop = fftSize / 2)
        // 75% -> 0.25 (hop = fftSize / 4)
        let overlapFraction = hopSizeOverlap / 100.0
        let hopSizeMultiplier = 1.0 - overlapFraction
        let hopSize = Int(Float(fftSize) * hopSizeMultiplier)
        
        var shouldContinue = true
        while shouldContinue {
            var chunk: [Float]?
            
            // Thread-safe: Check and extract chunk from buffer
            bufferAccessQueue.sync {
                if inputBuffer.count >= fftSize {
                    // Extract a chunk of samples
                    chunk = Array(inputBuffer.prefix(fftSize))
                    
                    // Remove samples based on hop size
                    inputBuffer.removeFirst(hopSize)

                } else {
                    shouldContinue = false
                }
            }
            
            // Process the chunk outside the synchronized block to minimize lock time
            if let chunk = chunk {
                // Resample only if not using hardware rate and rates differ
                let processedChunk: [Float]
                if !useHardwareSampleRate && abs(actualSampleRate - targetSampleRate) > 1.0 {
                    processedChunk = resample(chunk, from: actualSampleRate, to: targetSampleRate)
                } else {
                    processedChunk = chunk
                }
                
                // Perform FFT on the processed chunk
                performFFT(on: processedChunk)
            }
        }
    }
    
    /// Resamples audio data from one sample rate to another using linear interpolation.
    ///
    /// This simple resampler uses linear interpolation between samples. For production
    /// applications requiring higher quality, consider using AVAudioConverter or a
    /// more sophisticated resampling algorithm.
    ///
    /// - Parameters:
    ///   - samples: The input audio samples
    ///   - inputRate: The current sample rate of the input
    ///   - outputRate: The desired output sample rate
    ///
    /// - Returns: Resampled audio data at the target sample rate, padded or truncated to fftSize
    private func resample(_ samples: [Float], from inputRate: Double, to outputRate: Double) -> [Float] {
        // Calculate the resampling ratio
        let ratio = outputRate / inputRate
        let outputLength = Int(Double(samples.count) * ratio)
        var output = [Float](repeating: 0, count: outputLength)
        
        // Simple linear interpolation resampling
        // For each output sample, interpolate between two input samples
        for i in 0..<outputLength {
            // Calculate the corresponding position in the input array
            let srcIndex = Double(i) / ratio
            let idx0 = Int(floor(srcIndex))
            let idx1 = min(idx0 + 1, samples.count - 1)
            let frac = Float(srcIndex - Double(idx0))
            
            // Linear interpolation between samples
            output[i] = samples[idx0] * (1.0 - frac) + samples[idx1] * frac
        }
        
        // Ensure output is exactly fftSize by padding or truncating
        if output.count > fftSize {
            return Array(output.prefix(fftSize))
        } else if output.count < fftSize {
            // Pad with zeros
            output.append(contentsOf: [Float](repeating: 0, count: fftSize - output.count))
        }
        
        return output
    }
    
    /// Performs a Fast Fourier Transform on audio samples and updates published magnitude data.
    ///
    /// This method:
    /// 1. Applies a Hann window to reduce spectral leakage
    /// 2. Converts samples to split complex format (real/imaginary parts)
    /// 3. Executes the FFT using vDSP
    /// 4. Calculates magnitude spectrum
    /// 5. Converts to logarithmic dB scale
    /// 6. Finds and publishes the peak frequency
    /// 7. Tracks processing time for performance monitoring
    ///
    /// - Parameter samples: Audio samples to analyze, must be of length fftSize
    ///
    /// - Note: This method runs on the audioProcessingQueue. Results are published 
    ///         on the main thread via @Published properties for SwiftUI compatibility.
    private func performFFT(on samples: [Float]) {
        // Start timing the FFT processing
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Safety check: ensure FFT setup is valid
        guard let setup = fftSetup else { return }
        
        var samples = samples
        
        // Apply Hann window to reduce spectral leakage
        // Spectral leakage occurs when the signal's frequency doesn't align perfectly
        // with the FFT bin centers. Windowing reduces this artifact.
        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(fftSize))
        
        // Prepare for FFT - convert to split complex format
        // vDSP requires data in a specific format with real and imaginary parts separated
        var realParts = [Float](repeating: 0, count: fftSize / 2)
        var imagParts = [Float](repeating: 0, count: fftSize / 2)
        
        // Deinterleave even/odd samples into real/imaginary parts
        // This is required by the vDSP_DFT_zrop format:
        // - Even indices (0, 2, 4, ...) go to real parts
        // - Odd indices (1, 3, 5, ...) go to imaginary parts
        for i in 0..<(fftSize / 2) {
            realParts[i] = samples[i * 2]
            imagParts[i] = samples[i * 2 + 1]
        }
        
        // Perform FFT using vDSP's optimized implementation
        realParts.withUnsafeMutableBufferPointer { realPtr in
            imagParts.withUnsafeMutableBufferPointer { imagPtr in
                vDSP_DFT_Execute(setup, realPtr.baseAddress!, imagPtr.baseAddress!,
                                realPtr.baseAddress!, imagPtr.baseAddress!)
            }
        }
        
        // Calculate magnitudes from complex FFT output
        // Magnitude = sqrt(real^2 + imag^2)
        var mags = [Float](repeating: 0, count: fftSize / 2)
        realParts.withUnsafeBufferPointer { realPtr in
            imagParts.withUnsafeBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: realPtr.baseAddress!),
                    imagp: UnsafeMutablePointer(mutating: imagPtr.baseAddress!)
                )
                // Scale to normalize amplitude
                var scale: Float = 1.0 / Float(fftSize)

                vDSP_vsmul(splitComplex.realp, 1, &scale, splitComplex.realp, 1, vDSP_Length(fftSize / 2))
                vDSP_vsmul(splitComplex.imagp, 1, &scale, splitComplex.imagp, 1, vDSP_Length(fftSize / 2))
                
                // vDSP_zvabs computes the absolute value (magnitude) of complex numbers
                vDSP_zvabs(&splitComplex, 1, &mags, 1, vDSP_Length(fftSize / 2))
            }
        }
        
        // Convert to dB scale for better visualization
        // dB = 20 * log10(magnitude / reference)
        // Using reference = 1.0 and flag = 1 gives: dB = 20 * log10(magnitude)
        var db = [Float](repeating: -100, count: fftSize / 2)
        var ref: Float = 1.0
        vDSP_vdbcon(mags, 1, &ref, &db, 1, vDSP_Length(fftSize / 2), 1)
        
        // Apply microphone calibration corrections if available
        // This compensates for the microphone's frequency response
        if !calibrationCorrections.isEmpty && calibrationCorrections.count == db.count {
            vDSP_vadd(db, 1, calibrationCorrections, 1, &db, 1, vDSP_Length(db.count))
        }
        
        // Find peak frequency in the spectrum
        if let maxIndex = db.enumerated().max(by: { $0.element < $1.element })?.offset {
            let peakFreq = frequencies[maxIndex]
            let peakMag = db[maxIndex]
            
            // Calculate processing time
            let endTime = CFAbsoluteTimeGetCurrent()
            let processingTime = Float((endTime - startTime) * 1000)  // Convert to milliseconds
            
            // Update processing time history for averaging
            processingTimeHistory.append(processingTime)
            if processingTimeHistory.count > processingTimeHistorySize {
                processingTimeHistory.removeFirst()
            }
            
            // Calculate average processing time
            let avgTime = processingTimeHistory.reduce(0, +) / Float(processingTimeHistory.count)
            
            // Debug: Print when FFT completes
            fftCount += 1
            if fftCount % 30 == 0 {  // Print every 30 FFTs (about every 15 seconds at 2Hz frame rate)
                print("📈 FFT #\(fftCount) complete - Peak: \(String(format: "%.1f", peakMag)) dB @ \(String(format: "%.1f", peakFreq)) Hz")
            }
            
            // Throttle UI updates to avoid flooding main queue
            let currentTime = CFAbsoluteTimeGetCurrent()
            let shouldPublish = (currentTime - lastPublishTime) >= minPublishInterval
            
            if shouldPublish {
                lastPublishTime = currentTime
                
//                print("⏰ Attempting to /*dispatch*/ UI update to main queue...")
                
                // Update published properties on main thread for SwiftUI
                // Use DispatchQueue.main.async to avoid blocking audio processing
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
//                    print("🎨 INSIDE main.async block - updating magnitudes array (length: \(db.count))")
                    
                    self.magnitudes = db
                    self.peakFrequency = peakFreq
                    self.peakMagnitude = peakMag
                    self.processingTimeMs = processingTime
                    self.avgProcessingTimeMs = avgTime
                    
//                    print("🎨 Updated all properties - magnitudes[0]: \(self.magnitudes[0]) dB")
                    
                    // Debug: Confirm update happened
//                    if self.fftCount % 10 == 0 {
//                        print("✨ Published to main thread - Peak is now: \(self.peakMagnitude) dB")
//                    }
                }
                
//                print("⏰ Dispatched! Waiting for main queue to process it...")
//            } else {
//                // Skipped publish due to throttling
//                if fftCount % 100 == 0 {
//                    print("⏭️ Skipped publish (throttled) - \(Int((currentTime - lastPublishTime) * 1000))ms since last")
//                }
            }
        }
    }
    
    // MARK: - Audio Device Selection
    
    /// Loads the list of available audio input devices
    private func loadAvailableInputDevices() {
        #if os(macOS)
        loadAvailableInputDevicesMacOS()
        #else
        loadAvailableInputDevicesIOS()
        #endif
    }
    
    #if os(macOS)
    /// Loads the list of available audio input devices on macOS
    private func loadAvailableInputDevicesMacOS() {
        var devices: [AVAudioDevice] = []
        
        // Use Core Audio to enumerate audio devices
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else {
            print("⚠️ Could not get audio device count")
            return
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else {
            print("⚠️ Could not get audio devices")
            return
        }
        
        // Filter for input devices and get their info
        for deviceID in deviceIDs {
            // Check if device has input channels
            var streamPropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            
            status = AudioObjectGetPropertyDataSize(
                deviceID,
                &streamPropertyAddress,
                0,
                nil,
                &dataSize
            )
            
            guard status == noErr else { continue }
            
            let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferList.deallocate() }
            
            status = AudioObjectGetPropertyData(
                deviceID,
                &streamPropertyAddress,
                0,
                nil,
                &dataSize,
                bufferList
            )
            
            guard status == noErr else { continue }
            
            // Use withUnsafePointer to safely access the mBuffers tuple
            let channelCount = withUnsafePointer(to: &bufferList.pointee.mBuffers) { buffersPtr in
                let bufferCount = Int(bufferList.pointee.mNumberBuffers)
                var count = 0
                for i in 0..<bufferCount {
                    let bufferPtr = buffersPtr.advanced(by: i)
                    count += Int(bufferPtr.pointee.mNumberChannels)
                }
                return count
            }
            
            // Skip devices with no input channels
            guard channelCount > 0 else { continue }
            
            // Get device name
            var namePropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            // Use Unmanaged for CFString to avoid object reference issues
            var cfStringRef: Unmanaged<CFString>?
            dataSize = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
            
            status = AudioObjectGetPropertyData(
                deviceID,
                &namePropertyAddress,
                0,
                nil,
                &dataSize,
                &cfStringRef
            )
            
            let name: String
            if status == noErr, let cfString = cfStringRef?.takeUnretainedValue() {
                name = cfString as String
            } else {
                name = "Unknown Device"
            }
            
            // Get sample rate
            var sampleRateAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var sampleRate: Float64 = 48000.0
            dataSize = UInt32(MemoryLayout<Float64>.size)
            
            status = AudioObjectGetPropertyData(
                deviceID,
                &sampleRateAddress,
                0,
                nil,
                &dataSize,
                &sampleRate
            )
            
            // Get device UID
            var uidPropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            // Use Unmanaged for CFString to avoid object reference issues
            var cfUIDRef: Unmanaged<CFString>?
            dataSize = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
            
            status = AudioObjectGetPropertyData(
                deviceID,
                &uidPropertyAddress,
                0,
                nil,
                &dataSize,
                &cfUIDRef
            )
            
            let uid: String
            if status == noErr, let cfUID = cfUIDRef?.takeUnretainedValue() {
                uid = cfUID as String
            } else {
                uid = "\(deviceID)"
            }
            
            let device = AVAudioDevice(
                name: name,
                uid: uid,
                sampleRate: sampleRate,
                deviceID: deviceID
            )
            
            devices.append(device)
            print("🎤 Found input device: \(name) @ \(sampleRate) Hz (UID: \(uid))")
        }
        
        DispatchQueue.main.async {
            let previousDevices = self.availableInputDevices
            self.availableInputDevices = devices

            if previousDevices.isEmpty {
                // ── Initial load: priority-based auto-selection ──────────────────
                guard !devices.isEmpty else { return }

                // Priority 1: Built-in microphone
                if let builtInMic = devices.first(where: { $0.uid.contains("BuiltInMicrophone") }) {
                    self.selectedInputDevice = builtInMic
                    print("🎤 Auto-selected built-in mic: \(builtInMic.name)")
                } else {
                    // Priority 2: System default input device
                    var defaultDeviceID: AudioDeviceID = 0
                    var defaultDeviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
                    var defaultDeviceAddress = AudioObjectPropertyAddress(
                        mSelector: kAudioHardwarePropertyDefaultInputDevice,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )
                    let status = AudioObjectGetPropertyData(
                        AudioObjectID(kAudioObjectSystemObject),
                        &defaultDeviceAddress,
                        0,
                        nil,
                        &defaultDeviceIDSize,
                        &defaultDeviceID
                    )
                    if status == noErr, defaultDeviceID != 0,
                       let defaultDevice = devices.first(where: { $0.deviceID == defaultDeviceID }) {
                        self.selectedInputDevice = defaultDevice
                        print("🎤 Auto-selected system default: \(defaultDevice.name) (ID: \(defaultDeviceID))")
                    } else {
                        // Priority 3: First available device
                        self.selectedInputDevice = devices.first
                        print("🎤 Auto-selected first device: \(devices.first!.name)")
                    }
                }
            } else {
                // ── Device list changed (connect or disconnect) ──────────────────
                let newlyConnected = devices.filter { newDev in
                    !previousDevices.contains(where: { $0.uid == newDev.uid })
                }

                if let firstNew = newlyConnected.first {
                    // New device plugged in — switch to it automatically
                    self.selectedInputDevice = firstNew
                    print("🎤 New device connected, auto-selected: \(firstNew.name)")
                } else if let current = self.selectedInputDevice,
                          !devices.contains(where: { $0.uid == current.uid }) {
                    // Currently selected device was unplugged — fall back
                    if let builtIn = devices.first(where: { $0.uid.contains("BuiltInMicrophone") }) {
                        self.selectedInputDevice = builtIn
                        print("🎤 '\(current.name)' disconnected, switched to built-in: \(builtIn.name)")
                    } else {
                        self.selectedInputDevice = devices.first
                        print("🎤 '\(current.name)' disconnected, switched to: \(devices.first?.name ?? "none")")
                    }
                }
                // If selected device is still present, no change needed
            }
        }
        
        print("🎤 Found \(devices.count) audio input device(s) total")
    }

    /// Registers a CoreAudio listener so the device list refreshes when hardware changes.
    private func registerMacOSHardwareListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // CoreAudio may call this on any thread; loadAvailableInputDevicesMacOS
            // dispatches to main internally for all @Published updates.
            self?.loadAvailableInputDevices()
        }
        hardwareListenerBlock = block
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil,
            block
        )
        if status != noErr {
            print("⚠️ Failed to register CoreAudio device change listener: \(status)")
        } else {
            print("✅ Registered CoreAudio device change listener")
        }
    }

    /// Removes the CoreAudio hardware change listener.
    private func unregisterMacOSHardwareListener() {
        guard let block = hardwareListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil,
            block
        )
        hardwareListenerBlock = nil
    }
    #endif
    
    #if os(iOS)
    /// Loads the list of available audio input devices on iOS
    private func loadAvailableInputDevicesIOS() {
        let session = AVAudioSession.sharedInstance()
        var devices: [AVAudioDevice] = []
        
        // CRITICAL: Only configure audio session if not already running
        // If the engine is running, changing the category can invalidate the audio tap
        // and cause the app to stop receiving audio data.
        if !audioEngine.isRunning {
            // Configure audio session BEFORE querying available inputs
            // Without setting the category to .record or .playAndRecord, iOS will NOT
            // expose external USB audio devices (like UMIK-1) in availableInputs.
            do {
                // Use .playAndRecord to maximize device discovery
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetoothA2DP])
                try session.setActive(true, options: [])
                print("🎙️ iOS audio session configured for device enumeration")
            } catch {
                print("⚠️ Failed to configure audio session for device enumeration: \(error)")
                // Continue anyway - we may still get some devices
            }
        } else {
            print("🎙️ Skipping audio session reconfiguration - engine is running")
        }
        
        // Get available inputs from AVAudioSession
        guard let availableInputs = session.availableInputs else {
            print("⚠️ No audio inputs available")
            
            // Add current route as fallback
            if let currentInput = session.currentRoute.inputs.first {
                let device = AVAudioDevice(
                    name: currentInput.portName,
                    uid: currentInput.uid,
                    sampleRate: session.sampleRate,
                    port: currentInput
                )
                devices.append(device)
            }
            
            DispatchQueue.main.async {
                self.availableInputDevices = devices
                if let first = devices.first {
                    self.selectedInputDevice = first
                }
            }
            return
        }
        
        // Convert AVAudioSessionPortDescription to AVAudioDevice
        // Filter out invalid or unusable ports
        for port in availableInputs {
            // Skip ports with empty or invalid names
            guard !port.portName.isEmpty else {
                print("⚠️ Skipping port with empty name (UID: \(port.uid))")
                continue
            }
            
            // Create device - avoid directly printing portType.rawValue as it may contain
            // internal values that trigger warnings
            let device = AVAudioDevice(
                name: port.portName,
                uid: port.uid,
                sampleRate: session.sampleRate,
                port: port
            )
            devices.append(device)
            
            // Safe logging - only print known port types
            let portTypeDescription = getPortTypeDescription(port.portType)
            print("🎤 Found input device: \(port.portName) [\(portTypeDescription)] @ \(session.sampleRate) Hz")
        }
        
        DispatchQueue.main.async {
            self.availableInputDevices = devices
            
            // Try to select the current input, or first device
            if let currentInput = session.currentRoute.inputs.first,
               let matchingDevice = devices.first(where: { $0.uid == currentInput.uid }) {
                self.selectedInputDevice = matchingDevice
            } else if let first = devices.first {
                self.selectedInputDevice = first
            }
        }
        
        print("🎤 Found \(devices.count) audio input device(s) total")
    }
    
    /// Returns a human-readable description of the port type without triggering internal enum warnings
    private func getPortTypeDescription(_ portType: AVAudioSession.Port) -> String {
        switch portType {
        case .builtInMic:
            return "Built-in Microphone"
        case .headsetMic:
            return "Headset Microphone"
        case .lineIn:
            return "Line In"
        case .airPlay:
            return "AirPlay"
        case .bluetoothA2DP:
            return "Bluetooth A2DP"
        case .bluetoothLE:
            return "Bluetooth LE"
        case .bluetoothHFP:
            return "Bluetooth Hands-Free"
        case .usbAudio:
            return "USB Audio"
        case .carAudio:
            return "CarPlay"
        case .virtual:
            return "Virtual"
        default:
            // Don't print the raw value for unknown types as it may trigger warnings
            return "Audio Input"
        }
    }
    
    /// Handles audio route changes (e.g., headphones plugged in/out, USB devices connected)
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        print("🔄 Audio route changed: \(reason)")
        
        // Track if engine was running before handling the change
        let wasRunning = isRunning
        
        switch reason {
        case .newDeviceAvailable:
            print("🎤 New audio device connected")
            // Reload device list when devices are added
            loadAvailableInputDevices()
            
            // If the engine was running, restart it to pick up the new device configuration
            // This ensures the audio tap is properly reconfigured for the new route
            if wasRunning {
                print("🔄 Restarting audio engine after device connection...")
                restartEngineAfterRouteChange()
            }
            
        case .oldDeviceUnavailable:
            print("🎤 Audio device disconnected")
            // Reload device list when devices are removed
            loadAvailableInputDevices()
            
            // If the engine was running, restart it to use the fallback device
            if wasRunning {
                print("🔄 Restarting audio engine after device disconnection...")
                restartEngineAfterRouteChange()
            }
            
        case .categoryChange:
            print("🎤 Audio category changed - refreshing device list")
            // Don't restart on category change as it may have been triggered by our own code
            loadAvailableInputDevices()
            
        default:
            break
        }
    }
    
    /// Restarts the audio engine after a route change
    /// This ensures the audio tap is properly reconfigured for the new audio route
    private func restartEngineAfterRouteChange() {
        // Use a slight delay to allow the system to settle after the route change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            
            // Only restart if we're still supposed to be running
            guard self.isRunning else {
                print("🔄 Skipping restart - analyzer was stopped")
                return
            }
            
            print("🔄 Performing engine restart...")
            self.stop()
            
            // Give the system a moment to clean up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                do {
                    try self.start()
                    // Notify observers that a route change restart occurred
                    // This allows TapToneAnalyzer to reset its warmup timer and threshold state
                    self.routeChangeRestartCount += 1
                    print("✅ Audio engine restarted successfully after route change (restart #\(self.routeChangeRestartCount))")
                } catch {
                    print("❌ Failed to restart audio engine: \(error)")
                }
            }
        }
    }
    #endif
    
    /// Sets the audio input device
    /// - Parameter device: The audio device to use for input
    /// - Throws: An error if the device cannot be set
    func setInputDevice(_ device: AVAudioDevice) throws {
        print("🎤 Attempting to set input device to: \(device.name)")
        
        #if os(iOS)
        // On iOS, set the preferred input using AVAudioSession
        let session = AVAudioSession.sharedInstance()
        
        guard let port = device.port else {
            throw NSError(
                domain: "RealtimeFFTAnalyzer",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Invalid audio port"]
            )
        }
        
        do {
            try session.setPreferredInput(port)
            print("✓ Successfully set input to: \(device.name)")
        } catch {
            print("⚠️ Failed to set preferred input: \(error)")
            throw error
        }
        #else
        // macOS: Need to restart the engine with new device
        let wasRunning = audioEngine.isRunning
        
        if wasRunning {
            stop()
        }
        #endif
        
        // Update the selected device
        DispatchQueue.main.async {
            self.selectedInputDevice = device
        }
        
        #if os(macOS)
        // If it was running, restart with the new device
        if wasRunning {
            // Give the system a moment to clean up
            Thread.sleep(forTimeInterval: 0.1)
            try start()
        }
        #else
        // On iOS, just reload device list to refresh current state
        loadAvailableInputDevices()
        #endif
    }
}


