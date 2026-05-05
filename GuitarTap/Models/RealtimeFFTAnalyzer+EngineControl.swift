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

        // Reset the engine rather than replacing it with a new instance.
        //
        // Previously this created a new AVAudioEngine() on every start(). That caused a
        // malloc heap-corruption crash (EXC_BREAKPOINT in _xzm_xzone_malloc_freelist) because:
        //   1. audioEngine.stop() dispatches AUHAL teardown asynchronously on the AVAudioIOUnit queue.
        //   2. Accessing inputNode on the new engine immediately after causes
        //      AVAudioEngineImpl::UpdateInputNode to sync-dispatch onto that same queue
        //      while the old teardown is still running, corrupting the heap.
        //
        // audioEngine.reset() avoids this entirely: it resets connections and taps on
        // the same engine instance without replacing the underlying AUHAL unit, so
        // there is no teardown/startup race. The inputNode reference remains valid.
        //
        // Permission revocation causes a full process restart by macOS, so a fresh
        // AVAudioEngine() from init() is always available for that case anyway.
        audioEngine.stop()
        audioEngine.reset()
        // Assign inputNode on first call (it is intentionally left nil in init until
        // permissions are confirmed). On subsequent calls it remains valid across reset().
        if inputNode == nil {
            inputNode = audioEngine.inputNode
        }
        
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
                    // Permission just granted — resume via the owner's callback so the
                    // full TapToneAnalyzer.start() path runs (sets analyzerStartTime and
                    // kicks off startTapSequence). Falling back to self.start() would
                    // restart only the FFT engine, leaving tap detection never started.
                    DispatchQueue.main.async {
                        if let handler = self.onPermissionGranted {
                            handler()
                        } else {
                            try? self.start()
                        }
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
        
        engineLog.info("Hardware sample rate: \(self.actualSampleRate, privacy: .public) Hz, hardware channels: \(hardwareFormat.channelCount, privacy: .public) (tap will use mono)")
        
        // Validate sample rate
        guard actualSampleRate > 0 else {
            audioEngine.stop()
            throw NSError(
                domain: "RealtimeFFTAnalyzer",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Audio hardware not available. Sample rate is 0 Hz. Check microphone permissions and ensure an audio input device is connected."]
            )
        }
        
        // Always use a mono tap format.
        //
        // Rationale: processAudioBuffer() only ever reads channelData[0], so stereo or
        // multi-channel data beyond the first channel is discarded anyway.  More importantly,
        // some MacBook Pro models report 3-channel hardware formats (the built-in mic array
        // includes an ambient/beamforming channel).  Requesting a 3-channel tap format from
        // AVAudioEngine causes installTap to silently fail on those machines — the engine
        // starts but never delivers audio buffers, leaving the app permanently on "Starting…".
        // Forcing mono sidesteps this entirely: CoreAudio will downmix or extract channel 0
        // regardless of the hardware channel count.
        let effectiveChannelCount: AVAudioChannelCount = 1
        
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
    
    // MARK: - WAV File Playback

    /// Starts the audio engine fed from an audio file (WAV, AIFF, CAF, M4A) instead of the
    /// microphone.  The file is routed through the exact same `processAudioBuffer` → FFT →
    /// tap-detection pipeline as the live mic path.
    ///
    /// - Parameter url: URL of the audio file to play.
    /// - Parameter completion: Optional closure called on the main thread after the file has
    ///   finished playing and the engine has switched back to the microphone.  Use this to
    ///   release security-scoped resource access that must be held for the full playback
    ///   duration (e.g. files picked from Dropbox or iCloud Drive on iOS).
    /// - Throws: An error if the file cannot be opened or the engine fails to start.
    ///
    /// - Note: No microphone permission is required.  Call `stop()` to end playback early.
    func startFromFile(_ url: URL, completion: (() -> Void)? = nil) throws {
        engineLog.info("=== Starting Audio Engine from file: \(url.lastPathComponent, privacy: .public) ===")

        // Tear down any existing tap / engine (same preamble as start()).
        inputNode?.removeTap(onBus: 0)
        playerNode?.stop()
        playerNode = nil
        inputNode = nil
        audioEngine.stop()
        audioEngine = AVAudioEngine()

        // Drain any processAudioBuffer calls that were already dispatched to
        // audioProcessingQueue before the tap was removed.  removeTap() prevents
        // new dispatches but does NOT cancel work items already in the queue.
        // Those items would append stale mic samples to inputBuffer AFTER the
        // removeAll() below, contaminating the first file FFT frame with broadband
        // mic noise and producing a ragged spectrum instead of a clean ring-out.
        // A synchronous dispatch on the queue flushes all pending work first.
        audioProcessingQueue.sync { }

        // Clear the accumulation buffer so no stale mic audio is mixed into the
        // first FFT window from the file.
        bufferAccessQueue.sync { inputBuffer.removeAll() }

        // FILE_DEBUG: zero ordinals so a new file's frames start at #1.
        // Mirrors Python _FftProcessingThread.reset_state() block.
        fftFrameCounter = 0
        samplesConsumed = 0

        // Open the audio file.
        let audioFile = try AVAudioFile(forReading: url)
        let fileFormat = audioFile.processingFormat
        engineLog.info("File format: \(fileFormat, privacy: .public)")

        #if os(iOS)
        // On iOS the audio session must be configured BEFORE the engine graph is built.
        //
        // Why: AURemoteIO is locked to the hardware sample rate (e.g. 48000 Hz on iPad).
        // If the file is 44100 Hz and we build the graph at that rate, engine.start()
        // fails with -10851 (kAudioUnitErr_FormatNotSupported).
        //
        // Additionally, setPreferredSampleRate is only a *hint* — iOS may ignore it and
        // keep the hardware at its native rate.  AVAudioEngine then transparently resamples
        // the file to the hardware rate before delivering buffers to our tap.  We must
        // therefore read back the *actual* granted sample rate and use it for:
        //   1. The tap format (so the format matches what the engine actually delivers)
        //   2. actualSampleRate (so FFT bin→frequency math is correct)
        //
        // We use .playback category because no microphone is involved.
        let filePlaybackSession = AVAudioSession.sharedInstance()
        try filePlaybackSession.setCategory(.playback, mode: .default, options: [])
        try filePlaybackSession.setPreferredSampleRate(fileFormat.sampleRate)
        try filePlaybackSession.setActive(true, options: [])

        // Read the hardware rate iOS actually granted (may differ from file rate).
        let engineSampleRate = filePlaybackSession.sampleRate > 0
            ? filePlaybackSession.sampleRate
            : fileFormat.sampleRate
        if abs(engineSampleRate - fileFormat.sampleRate) > 1.0 {
            engineLog.info("iOS hardware rate (\(engineSampleRate) Hz) differs from file rate (\(fileFormat.sampleRate) Hz) — engine will resample; using hardware rate for FFT bins")
        }
        #else
        // On macOS AVAudioEngine handles any sample-rate conversion internally;
        // the tap always delivers audio at the file's native rate.
        let engineSampleRate = fileFormat.sampleRate
        #endif

        // actualSampleRate drives all FFT bin→frequency calculations.
        actualSampleRate = engineSampleRate

        // Build a mono Float32 format at the engine's sample rate.
        // Always mono: tap detection and FFT operate on a single channel.
        // The mainMixerNode handles stereo→mono downmix automatically when
        // a stereo file is connected with a mono format.
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: engineSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "RealtimeFFTAnalyzer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create mono format for file playback"])
        }

        // Create and attach a player node.
        let player = AVAudioPlayerNode()
        audioEngine.attach(player)
        // Connect player → mainMixerNode with the mono format.
        // AVAudioEngine handles both sample-rate conversion (file rate → engine rate)
        // and channel downmix (stereo → mono) automatically at the connection point.
        audioEngine.connect(player, to: audioEngine.mainMixerNode, format: monoFormat)

        // Install the tap on the player node — same buffer size as the mic path.
        // The tap format matches the connection format (mono), so no further
        // channel conversion is needed inside processAudioBuffer.
        let bufferSize: AVAudioFrameCount = 1024
        player.installTap(onBus: 0, bufferSize: bufferSize, format: monoFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.audioProcessingQueue.async {
                self.processAudioBuffer(buffer)
            }
        }

        // Calculate file duration (in wall-clock seconds) for the post-playback timer.
        // Always use the file's native length / file rate — the resampling doesn't change
        // how many real-time seconds the file takes to play.
        // .dataPlayedBack would be cleaner but fires immediately when there is no real
        // hardware output path, so we use a timed dispatch instead.
        let fileDuration = Double(audioFile.length) / fileFormat.sampleRate

        // Schedule the file for one-shot playback (no completion handler needed).
        player.scheduleFile(audioFile, at: nil)

        try audioEngine.start()
        player.play()

        // Capture identity so a second file opened before this timer fires won't
        // restart the mic and tear down the new file's engine.
        let scheduledPlayer = player
        playerNode = player

        // After the file has fully played, switch back to live mic.
        // Add a small buffer (0.3 s) to ensure all queued audio buffers have been
        // delivered to processAudioBuffer before we tear down the player.
        let _fileDurationLog = fileDuration
        let _t0Log = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + fileDuration + 0.3) { [weak self] in
            guard let self else { return }
            guard self.playerNode === scheduledPlayer else {
                // A new file opened before this timer fired — record the
                // interruption so the FILE_DEBUG trace shows it.
                TAP_DEBUG("file_playback", "INTERRUPTED | superseded by new playback")
                return
            }
            self.isPlayingFile = false
            self.playerNode = nil

            // ── FILE_DEBUG: file-playback END log ────────────────────
            // Mirrors Python _playback_worker END log.
            let _elapsed = Date().timeIntervalSince(_t0Log)
            let _ratio = _elapsed / max(_fileDurationLog, 1e-9)
            TAP_DEBUG("file_playback", "END | elapsed=\(String(format: "%.3f", _elapsed))s expected=\(String(format: "%.3f", _fileDurationLog))s realtimeRatio=\(String(format: "%.3f", _ratio))x")

            // Force-flush any partial audio that accumulated in inputBuffer.
            //
            // The file may be shorter than one FFT window (fftSize = 65536 samples,
            // ~1.49 s at 44.1 kHz).  When that happens processAudioBuffer never fills
            // the buffer to fftSize, so performFFT is never called — the file produces
            // zero FFT frames and tap detection never fires during playback.
            //
            // After this block returns we call start() to restart the live mic.
            // start() does NOT clear inputBuffer, so the ~39k file samples would still
            // be sitting there.  The first 25k mic samples then push the count past
            // 65536, and performFFT fires on a mix of file tail + live mic noise,
            // producing a ragged spectrum that trips tap detection with garbage data.
            //
            // Fix: drain the remaining file samples through performFFT right now
            // (zero-padding to fftSize so the transform is valid), then clear
            // inputBuffer before starting the mic so it begins from a clean slate.
            self.audioProcessingQueue.sync {
                var partial: [Float] = []
                self.bufferAccessQueue.sync {
                    partial = self.inputBuffer
                    self.inputBuffer.removeAll()
                }
                if !partial.isEmpty {
                    // Zero-pad to fftSize so performFFT receives an exactly-sized window.
                    // The padded zeros lower the average level but don't distort the
                    // ring-out peaks — the file signal is in the leading portion.
                    if partial.count < self.fftSize {
                        partial.append(contentsOf: [Float](repeating: 0, count: self.fftSize - partial.count))
                    }
                    self.performFFT(on: partial)
                }
            }

            // Switch back to live mic.  TapToneAnalyzer's auto-start guard
            // skips startTapSequence() when isMeasurementComplete is true,
            // preserving frozen results so New Tap stays enabled.
            try? self.start()
            // Release any security-scoped resource access (e.g. Dropbox / iCloud on iOS).
            // Must be called after the file is fully processed, not immediately after open.
            completion?()
        }

        // Update metrics for the file's sample rate.
        updateFrequencyBins()
        updateMetrics()

        // CRITICAL: Set isRunning = true synchronously before returning.
        // TapToneAnalyzer.analyzeMagnitudes() guards on fftAnalyzer.isRunning and returns
        // immediately when false — so the first FFT frame (which contains the tap transient)
        // would be discarded if isRunning were still false when it arrives.
        // startFromFile() is always called on the main thread (from openAudioFile), so this
        // write is safe without dispatch.
        //
        // Also reset magnitudes and peakMagnitude to silence so that the Combine
        // subscription in TapToneAnalyzer does not fire tap detection against the stale
        // mic spectrum that is still in those @Published properties.  Without this reset,
        // detectTap fires immediately with old mic data and freezes a ragged noise spectrum
        // instead of waiting for the first real FFT frame from the file.
        magnitudes = [Float](repeating: -100, count: fftSize / 2)
        peakMagnitude = -100
        // Reset the publish throttle so the forced end-of-file FFT frame (dispatched
        // ~1.2 s from now) is not suppressed by a recent live-mic publish timestamp.
        lastPublishTime = 0
        isRunning = true
        isPlayingFile = true
        playingFileName = url.deletingPathExtension().lastPathComponent
        engineStartTime = Date()
        engineLog.info("File playback started")

        // ── FILE_DEBUG: file-playback START log ─────────────────────────
        // Mirrors Python file_playback worker's START log.  Swift uses
        // AVAudioEngine (scheduleFile + play) rather than a sample-pump
        // thread, so per-chunk pacing fields don't apply; everything else
        // matches the Python format.
        let _expectedFftFrames = Int(audioFile.length) / fftSize
        let _chunkDurationMs = Double(bufferSize) / fileFormat.sampleRate * 1000.0
        TAP_DEBUG("file_playback", "START | path=\(playingFileName ?? "") samples=\(audioFile.length) rate=\(Int(fileFormat.sampleRate))Hz chunksize=\(bufferSize) chunkDuration=\(String(format: "%.1f", _chunkDurationMs))ms expectedDuration=\(String(format: "%.3f", fileDuration))s fftSize=\(fftSize) expectedFftFrames=\(_expectedFftFrames)")
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

        // Stop and remove the file player node if one is active.
        if let player = playerNode {
            player.stop()
            player.removeTap(onBus: 0)
            audioEngine.detach(player)
            playerNode = nil
        }

        // Always try to clean up, even if engine reports as not running
        // This handles cases where the engine started but never received audio
        if audioEngine.isRunning {
            // Remove the audio tap to stop receiving buffers
            inputNode?.removeTap(onBus: 0)

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
            self?.isPlayingFile = false
            self?.playingFileName = nil
            self?.peakMagnitude = -100  // Reset to silent state
            self?.peakFrequency = 0
        }
    }
}
