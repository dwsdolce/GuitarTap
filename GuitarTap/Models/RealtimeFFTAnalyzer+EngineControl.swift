//
//  RealtimeFFTAnalyzer+EngineControl.swift
//  GuitarTap
//

import AVFoundation
import Accelerate
import OSLog

#if os(macOS)
import AudioToolbox
import CoreAudio
#endif

private let engineLog = Logger(subsystem: "com.dolcesfogato.GuitarTap", category: "Microphone")

// MARK: - Engine Control

extension RealtimeFFTAnalyzer {

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
        engineLog.info("=== Starting Audio Engine ===")

        // CRITICAL: Always remove any existing tap to prevent "Tap already exists" error
        // This must be done BEFORE stopping or resetting the engine.
        // We always attempt removal regardless of audioEngine.isRunning state because:
        // 1. The tap can persist even after the engine stops
        // 2. Route changes can leave the engine in an inconsistent state
        // 3. removeTap() is safe to call even if no tap exists
        // Remove any existing tap before teardown. Guard against nil on very first call
        // (inputNode is not assigned in init to avoid touching the audio hardware before
        // permission is confirmed).
        inputNode?.removeTap(onBus: 0)

        // Fully replace the audio engine with a fresh instance rather than reusing it.
        // After macOS force-restarts the app following a permission revocation, the existing
        // AVAudioEngine is in an irrecoverably broken state — reset() is not sufficient.
        //
        // IMPORTANT: Nil out inputNode before stopping / replacing the engine.
        // Holding a strong reference to the old inputNode while the engine tears down its
        // AUHAL unit on the AVAudioIOUnit queue causes a malloc-corruption crash
        // ("BUG IN CLIENT OF LIBMALLOC: memory corruption of free block") because
        // the main thread re-enters AVAudioEngineImpl::UpdateInputNode — which
        // sync-dispatches onto the same queue — while CoreAudio is still tearing
        // down the old IOProc on that queue.  Releasing the reference first lets
        // the old engine fully quiesce before the new one is created.
        inputNode = nil
        audioEngine.stop()
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
        
        #if os(macOS)
        // Request microphone permission explicitly on macOS
        // Note: On macOS 10.14+, apps need explicit permission to access the microphone
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            engineLog.info("Microphone permission: AUTHORIZED")
        case .notDetermined:
            engineLog.info("Microphone permission: NOT DETERMINED - requesting now...")
            // Request permission asynchronously. The callback fires on a background thread
            // once the user responds to the system prompt:
            // - Granted: start the engine automatically so the user doesn't have to tap Start again.
            // - Denied: signal the UI to show the permission alert.
            // - Still .notDetermined (user clicked "Open System Settings"): do nothing —
            //   they can grant access there and tap Start again.
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard let self else { return }
                if granted {
                    // Permission just granted — start the engine now so the user
                    // doesn't need to tap Start a second time.
                    DispatchQueue.main.async {
                        try? self.start()
                    }
                } else {
                    let finalStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                    if finalStatus == .denied || finalStatus == .restricted {
                        DispatchQueue.main.async {
                            self.microphonePermissionDenied = true
                        }
                    }
                    // If still .notDetermined (user dismissed to System Settings), do nothing.
                }
            }
            // Always return here — the callback above will start the engine if granted.
            return
        case .denied:
            engineLog.warning("Microphone permission: DENIED — throwing")
            throw NSError(domain: "RealtimeFFTAnalyzer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Microphone access denied"])
        case .restricted:
            throw NSError(domain: "RealtimeFFTAnalyzer", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Microphone access restricted"])
        @unknown default:
            break
        }
        
        #endif
        
        #if os(iOS)
        // Configure audio session for recording (iOS only)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setActive(true, options: [])
        } catch {
            throw error
        }
        #endif
        
        #if os(macOS)
        // Set the input device on the AUHAL unit before starting the engine.
        // AVAudioEngine does not expose a device-selection API directly; we must
        // reach into the underlying AudioUnit and set kAudioOutputUnitProperty_CurrentDevice.
        // This MUST happen after audioEngine.reset() (which re-creates the input node's
        // audio unit) but BEFORE audioEngine.start().
        if let device = selectedInputDevice, let audioUnit = inputNode.audioUnit {
            var deviceID = device.deviceID
            let setStatus = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if setStatus != noErr {
                engineLog.warning("Failed to set input device '\(device.name, privacy: .public)': error \(setStatus, privacy: .public) — will use system default")
            }
        }
        #endif

        // Start the audio engine
        try audioEngine.start()
        engineLog.info("Audio engine started")
        
        #if os(macOS)
        // CRITICAL FIX: Manually start the audio unit if it's not running.
        // This is a workaround for a macOS bug where AVAudioEngine.start() succeeds
        // but the underlying Audio Unit doesn't actually start.
        if let audioUnit = inputNode.audioUnit {
            var isRunning: UInt32 = 0
            var isRunningSize = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioUnitGetProperty(
                audioUnit,
                kAudioOutputUnitProperty_IsRunning,
                kAudioUnitScope_Global,
                0,
                &isRunning,
                &isRunningSize
            )
            if status == noErr && isRunning == 0 {
                engineLog.warning("Audio unit not running after engine start — starting manually")
                AudioUnitInitialize(audioUnit)
                let startStatus = AudioOutputUnitStart(audioUnit)
                if startStatus != noErr {
                    engineLog.error("Failed to start audio unit manually (error \(startStatus, privacy: .public))")
                }
            }
        }
        #endif

        // Get hardware format AFTER engine starts
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        actualSampleRate = hardwareFormat.sampleRate
        
        engineLog.info("Hardware sample rate: \(self.actualSampleRate, privacy: .public) Hz, channels: \(hardwareFormat.channelCount, privacy: .public)")
        
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

        // Create tap format matching hardware (use hardware channel count)
        // WORKAROUND: Some USB mics report 2 channels but are actually mono
        // If we detect this situation, force to 1 channel
        let effectiveChannelCount: AVAudioChannelCount
        if hardwareFormat.channelCount == 2 {
            // If the device name suggests it's a measurement mic (like UMIK), force mono
            if let deviceName = selectedInputDevice?.name.lowercased(),
               (deviceName.contains("umik") || deviceName.contains("measurement")) {
                effectiveChannelCount = 1
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
        
        // CRITICAL FIX: Use smaller buffer size for large FFTs
        // Using 1024 samples (~23ms at 44.1kHz) for faster level metering updates
        // This improves decay measurement precision from ~100ms to ~23ms
        // FFT accuracy is unaffected since samples are accumulated to fftSize regardless
        let maxSafeBufferSize: AVAudioFrameCount = 1024
        let requestedBufferSize = min(AVAudioFrameCount(fftSize), maxSafeBufferSize)
        
        // Verify the audio unit is still running before installing the tap (macOS diagnostic).
        // It can stop between engine.start() and here if inputNode was accessed unexpectedly.
        #if os(macOS)
        if let audioUnit = inputNode.audioUnit {
            var isRunning: UInt32 = 0
            var isRunningSize = UInt32(MemoryLayout<UInt32>.size)
            AudioUnitGetProperty(audioUnit, kAudioOutputUnitProperty_IsRunning,
                                 kAudioUnitScope_Global, 0, &isRunning, &isRunningSize)
            // If the audio unit stopped between engine.start() and here, manually
            // restarting the AUHAL is insufficient — AVAudioEngine's internal render
            // graph is already broken and the tap will never deliver buffers.
            // The only reliable recovery is a full engine teardown and restart.
            if isRunning == 0 {
                engineLog.warning("Audio unit stopped before tap install — performing full engine restart")
                inputNode.removeTap(onBus: 0)   // remove any stale tap first
                // Nil inputNode before stop/reset for the same reason as in the primary path:
                // prevents malloc corruption from re-entrant UpdateInputNode on the AVAudioIOUnit queue.
                inputNode = nil
                audioEngine.stop()
                audioEngine.reset()
                inputNode = audioEngine.inputNode

                // Re-apply device selection after reset (reset recreates the input node AU).
                if let device = selectedInputDevice, let freshAU = inputNode.audioUnit {
                    var deviceID = device.deviceID
                    let setStatus = AudioUnitSetProperty(
                        freshAU,
                        kAudioOutputUnitProperty_CurrentDevice,
                        kAudioUnitScope_Global,
                        0,
                        &deviceID,
                        UInt32(MemoryLayout<AudioDeviceID>.size)
                    )
                    if setStatus != noErr {
                        engineLog.warning("Failed to re-apply device '\(device.name, privacy: .public)' (error \(setStatus, privacy: .public))")
                    }
                }

                try audioEngine.start()
                engineLog.info("Audio engine restarted after reset")
                inputNode = audioEngine.inputNode
            }

            var inputSampleRate: Float64 = 0
            var inputSampleRateSize = UInt32(MemoryLayout<Float64>.size)
            let sampleRateStatus = AudioUnitGetProperty(audioUnit, kAudioUnitProperty_SampleRate,
                                                        kAudioUnitScope_Input, 1,
                                                        &inputSampleRate, &inputSampleRateSize)
            if sampleRateStatus == noErr {
                engineLog.info("Audio unit input sample rate: \(inputSampleRate, privacy: .public) Hz")
            }
        }
        #endif
        
        inputNode.installTap(onBus: 0, bufferSize: requestedBufferSize, format: tapFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            self.audioProcessingQueue.async {
                self.processAudioBuffer(buffer)
            }
        }
        engineLog.info("Audio tap installed")
        
        // Update frequency bins based on effective sample rate
        // This ensures frequency labels are correct
        updateFrequencyBins()
        
        // Update metrics based on actual configuration
        updateMetrics()

        #if os(macOS)
        // Register a sample-rate listener on the active device so a rate change
        // in Audio MIDI Setup while running triggers an automatic engine restart.
        if let device = selectedInputDevice {
            registerSampleRateListener(for: device.deviceID)
        }
        #endif

        // Update UI state - set isRunning to true on main thread
        DispatchQueue.main.async {
            self.isRunning = true
            self.engineStartTime = Date()  // Track start time
            
            #if os(iOS)
            // Refresh device list now that audio session is fully configured
            // This ensures USB devices that weren't visible before are now available
            self.loadAvailableInputDevices()
            #endif
            
            // Set up a timeout to check if audio buffers are arriving.
            // Also re-checks TCC permission status — on macOS, authorizationStatus can briefly
            // report .authorized after a forced restart even though the hardware is still
            // blocked. By 3 seconds the cache will have settled to the true state.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self else { return }
                if self.isRunning && !self.firstBufferReceived {
                    engineLog.warning("Audio engine started but no audio buffers received after 3 seconds")
                }
                #if os(macOS)
                // Detect permission denial even when TCC cache is stale.
                //
                // When macOS force-restarts the app after permission revocation, AVCaptureDevice
                // .authorizationStatus can report .authorized for many seconds while the audio
                // hardware is actually blocked. The hardware delivers a perfectly silent stream
                // (all-zero samples), which produces -infinity dB from the FFT.
                //
                // Real audio from any microphone — even in a very quiet room — will never be
                // exactly zero. So .isInfinite on peakMagnitude is a reliable signal that the
                // hardware is muted by the OS, regardless of what TCC says.
                //
                // We also check TCC directly in case the magnitude is merely very low but not
                // infinite (e.g. the engine delivered a handful of non-zero seed samples).
                guard self.isRunning else { return }
                let tccStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                let tccDenied = (tccStatus == .denied || tccStatus == .restricted)
                // -infinity dB means the FFT received a perfectly zero signal.
                // Real mics always produce some thermal/quantisation noise, so a
                // perfectly silent stream that is also receiving buffers (firstBufferReceived)
                // is a definitive sign the OS is silently muting our input.
                // Do NOT treat perfectSilence as denial when status is .notDetermined —
                // on a fresh install the system permission prompt may not have been answered
                // yet, so silent buffers are expected during that window.
                let perfectSilence = self.peakMagnitude.isInfinite
                    && self.peakMagnitude < 0
                    && self.firstBufferReceived
                    && tccStatus != .notDetermined
                engineLog.info("3s TCC check — status: \(tccStatus.rawValue, privacy: .public), peak: \(self.peakMagnitude, privacy: .public) dB, perfectSilence: \(perfectSilence, privacy: .public), buffersReceived: \(self.firstBufferReceived, privacy: .public)")
                if tccDenied || perfectSilence {
                    engineLog.warning("Microphone permission confirmed DENIED after 3s — tccDenied=\(tccDenied, privacy: .public), perfectSilence=\(perfectSilence, privacy: .public)")
                    self.stop()
                    self.microphonePermissionDenied = true
                }
                #endif
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
        engineLog.info("Stop requested")

        #if os(macOS)
        // Remove the sample-rate listener so it doesn't fire during the stop/restart cycle
        unregisterSampleRateListener()
        #endif

        // Always try to clean up, even if engine reports as not running
        // This handles cases where the engine started but never received audio
        if audioEngine.isRunning {
            // Remove the audio tap to stop receiving buffers
            inputNode.removeTap(onBus: 0)
            
            // Stop the audio engine
            audioEngine.stop()
        }
        
        // Clear the input buffer on the buffer access queue (async to avoid blocking)
        bufferAccessQueue.async { [weak self] in
            self?.inputBuffer.removeAll()
        }

        // Reset debug tracking
        firstBufferReceived = false
        fftCount = 0
        engineStartTime = nil

        // ALWAYS update UI state on main thread, even if engine wasn't running
        // This ensures the UI is responsive even if the engine is in a bad state
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
            self?.peakMagnitude = -100  // Reset to silent state
            self?.peakFrequency = 0
        }
    }
}
