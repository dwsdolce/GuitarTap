//
//  RealtimeFFTAnalyzer+EngineControl.swift
//  GuitarTap
//

import AVFoundation
import Accelerate
import OSLog

import AudioToolbox
#if os(macOS)
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
        // ── Select the input device on the AUHAL before starting the engine ──
        //
        // AVAudioEngine does not expose a device-selection API directly; we must
        // reach into the underlying AudioUnit and set kAudioOutputUnitProperty_CurrentDevice.
        // This MUST happen after audioEngine.reset() (which re-creates the input node's
        // audio unit) but BEFORE audioEngine.start().
        //
        // selectedInputDevice may be nil on the very first start() call because
        // loadAvailableInputDevicesMacOS() dispatches to DispatchQueue.main.async
        // and hasn't completed yet.  In that case, fall back to the persisted
        // device UID from UserDefaults and look up the CoreAudio device ID directly.
        if let audioUnit = inputNode.audioUnit {
            var targetDeviceID: AudioDeviceID = 0
            var targetDeviceName = "system default"

            if let device = selectedInputDevice {
                targetDeviceID = device.deviceID
                targetDeviceName = device.name
            } else if let savedUID = UserDefaults.standard.string(forKey: "selectedInputDeviceUID") {
                // Look up the AudioDeviceID for the persisted UID synchronously.
                targetDeviceID = Self.audioDeviceID(forUID: savedUID) ?? 0
                if targetDeviceID != 0 {
                    targetDeviceName = savedUID
                    engineLog.info("selectedInputDevice is nil — resolved persisted UID '\(savedUID, privacy: .public)' → device ID \(targetDeviceID, privacy: .public)")
                }
            }

            if targetDeviceID != 0 {
                var devID = targetDeviceID
                let setStatus = AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &devID,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                if setStatus != noErr {
                    engineLog.warning("Failed to set input device '\(targetDeviceName, privacy: .public)': error \(setStatus, privacy: .public) — will use system default")
                }
            }

            // ── Force the AUHAL to operate at the input device's native sample rate ──
            //
            // AVAudioEngine creates a CADefaultDeviceAggregate that combines the
            // selected input device with the system output.  The aggregate defaults
            // to the *output* device's sample rate (typically 44100 Hz for built-in
            // speakers), which causes CoreAudio to resample a 48000 Hz input to
            // 44100 — silently degrading FFT bin spacing and introducing artefacts.
            //
            // We query whichever device the AUHAL is actually using (whether we just
            // set it above or it was assigned by the system) and force its native
            // sample rate on both the device and the AUHAL.
            var auhalDeviceID = AudioDeviceID(0)
            var devIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
            AudioUnitGetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &auhalDeviceID,
                &devIDSize
            )

            if auhalDeviceID != 0 {
                var deviceNativeSR: Float64 = 0
                var srSize = UInt32(MemoryLayout<Float64>.size)
                var nomSRAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyNominalSampleRate,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                let getSRStatus = AudioObjectGetPropertyData(
                    auhalDeviceID, &nomSRAddr, 0, nil, &srSize, &deviceNativeSR
                )
                if getSRStatus == noErr && deviceNativeSR > 0 {
                    engineLog.info("AUHAL device ID=\(auhalDeviceID, privacy: .public), native SR=\(deviceNativeSR, privacy: .public) Hz — forcing this rate")

                    // Reinforce the nominal rate on the device itself
                    AudioObjectSetPropertyData(
                        auhalDeviceID, &nomSRAddr, 0, nil,
                        UInt32(MemoryLayout<Float64>.size), &deviceNativeSR
                    )

                    // Set the AUHAL output-scope (element 1 = hardware-facing input
                    // side) sample rate so CoreAudio doesn't resample through the
                    // aggregate device.
                    var auRate = deviceNativeSR
                    AudioUnitSetProperty(
                        audioUnit,
                        kAudioUnitProperty_SampleRate,
                        kAudioUnitScope_Output,
                        1,
                        &auRate,
                        UInt32(MemoryLayout<Float64>.size)
                    )
                }
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

                    // Re-apply native sample rate on device + AUHAL (same as primary path).
                    var nativeSR = device.sampleRate
                    var nominalSRAddr = AudioObjectPropertyAddress(
                        mSelector: kAudioDevicePropertyNominalSampleRate,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )
                    AudioObjectSetPropertyData(
                        deviceID,
                        &nominalSRAddr,
                        0, nil,
                        UInt32(MemoryLayout<Float64>.size),
                        &nativeSR
                    )
                    var desiredRate = device.sampleRate
                    AudioUnitSetProperty(
                        freshAU,
                        kAudioUnitProperty_SampleRate,
                        kAudioUnitScope_Output,
                        1,
                        &desiredRate,
                        UInt32(MemoryLayout<Float64>.size)
                    )
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
        engineLog.info("=== Starting file playback (direct injection): \(url.lastPathComponent, privacy: .public) ===")

        // ── 1. Stop the mic engine cleanly but DO NOT replace it. ────────
        // Keeping the original audioEngine instance preserves the AUHAL's
        // configured input-device state so start() can restart it without
        // "no object with given ID 0" errors after playback.
        inputNode?.removeTap(onBus: 0)
        audioEngine.stop()

        // Cancel any in-flight previous playback worker by bumping the
        // generation counter.  The worker checks this on each chunk.
        filePlaybackGeneration += 1

        // Drain any processAudioBuffer / processRawSamples calls that were
        // already dispatched to audioProcessingQueue before the tap was
        // removed.  A synchronous dispatch flushes all pending work first.
        audioProcessingQueue.sync { }

        // Clear the accumulation buffer so no stale mic audio is mixed into
        // the first FFT window from the file.
        bufferAccessQueue.sync { inputBuffer.removeAll() }

        // Let TapToneAnalyzer clear its pre-roll ring buffer now that the
        // mic is stopped and the audio queue is fully drained.  Without this,
        // mic noise that accumulated between startTapSequence (which clears
        // preRollBuffer) and startFromFile (which stops the engine) leaks
        // into the gated capture's pre-roll seed.  Python doesn't have this
        // problem because its stream.stop() runs inside start_from_file
        // before the pre-roll can accumulate anything.
        TAP_DEBUG("file_playback", "POST_ENGINE_STOP — calling postEngineStopHandler")
        postEngineStopHandler?()
        TAP_DEBUG("file_playback", "POST_ENGINE_STOP_DONE")

        // Reset ordinals so a new file's frames start at #1.
        fftFrameCounter = 0
        samplesConsumed = 0

        // ── 2. Open and read the audio file into a mono Float32 array. ───
        // Uses ExtAudioFile which supports all Core Audio formats (WAV, AIFF,
        // CAF, MP3, AAC, ALAC, FLAC, etc.) and handles format conversion and
        // mono downmix internally.  Mirrors Python's soundfile.read() behavior.
        let (monoSamples, fileSampleRate) = try Self.readAudioFileAsMonoFloat32(url: url)
        let frameCount = monoSamples.count

        TAP_DEBUG("file_playback", "FILE_READ | frames=\(frameCount) rate=\(Int(fileSampleRate))")

        actualSampleRate = fileSampleRate

        // ── 3. Configure state before launching the worker. ──────────────
        updateFrequencyBins()
        updateMetrics()

        magnitudes = [Float](repeating: -100, count: fftSize / 2)
        peakMagnitude = -100
        lastPublishTime = 0
        isRunning = true
        isPlayingFile = true
        playingFileName = url.deletingPathExtension().lastPathComponent
        engineStartTime = Date()

        let chunkSize = 1024
        let fileDuration = Double(frameCount) / fileSampleRate
        let chunkDuration = Double(chunkSize) / fileSampleRate
        let myGeneration = filePlaybackGeneration

        // ── FILE_DEBUG: file-playback START log ──────────────────────────
        let _expectedFftFrames = frameCount / fftSize
        TAP_DEBUG("file_playback", "START | path=\(playingFileName ?? "") samples=\(frameCount) rate=\(Int(fileSampleRate))Hz chunksize=\(chunkSize) chunkDuration=\(String(format: "%.1f", chunkDuration * 1000))ms expectedDuration=\(String(format: "%.3f", fileDuration))s fftSize=\(fftSize) expectedFftFrames=\(_expectedFftFrames)")

        // ── 4. Spawn a background worker that paces chunks at real time. ─
        // Mirrors Python _playback_worker: sleep(chunk_duration) between
        // chunks so TapToneAnalyzer's tap detection and gated capture see
        // the same timing as live audio.  Unlike the old AVAudioEngine path,
        // samples are injected directly via processRawSamples — no engine
        // dithering or resampling can alter the signal.
        let capturedFftSize = fftSize
        let capturedCompletion = completion

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let t0 = Date()
            var idx = 0
            var chunksPumped = 0

            while idx < frameCount {
                guard let self else { return }
                // Check if this worker has been superseded.
                guard self.filePlaybackGeneration == myGeneration else {
                    TAP_DEBUG("file_playback", "INTERRUPTED | idx=\(idx)/\(frameCount) chunksPumped=\(chunksPumped)")
                    return
                }

                let end = min(idx + chunkSize, frameCount)
                let chunk = Array(monoSamples[idx..<end])
                self.audioProcessingQueue.sync {
                    self.processRawSamples(chunk)
                }
                idx = end
                chunksPumped += 1
                Thread.sleep(forTimeInterval: chunkDuration)
            }

            guard let self else { return }

            let elapsed = Date().timeIntervalSince(t0)
            TAP_DEBUG("file_playback", "END | chunksPumped=\(chunksPumped) samplesPumped=\(idx) elapsed=\(String(format: "%.3f", elapsed))s expected=\(String(format: "%.3f", fileDuration))s realtimeRatio=\(String(format: "%.3f", elapsed / max(fileDuration, 1e-9)))x")

            // Guard: if a new file was opened while we were sleeping, skip cleanup.
            guard self.filePlaybackGeneration == myGeneration else { return }

            // ── Post-playback: flush partial buffer, then restart mic ────
            // The partial flush and preMicRestartHandler MUST run before the
            // mic restarts, otherwise mic noise fills the gated capture window.
            // Python does all of this synchronously on the worker thread before
            // calling stream.start().  We mirror that here: flush + handler run
            // on this background thread, then only the UI state update and mic
            // restart are dispatched to main.

            // 1. Force-flush any partial audio that accumulated in inputBuffer.
            TAP_DEBUG("file_playback", "PARTIAL_FLUSH — draining inputBuffer")
            self.audioProcessingQueue.sync {
                var partial: [Float] = []
                self.bufferAccessQueue.sync {
                    partial = self.inputBuffer
                    self.inputBuffer.removeAll()
                }
                TAP_DEBUG("file_playback", "PARTIAL_FLUSH | partialLen=\(partial.count) fftSize=\(capturedFftSize)")
                if !partial.isEmpty {
                    if partial.count < capturedFftSize {
                        partial.append(contentsOf: [Float](repeating: 0, count: capturedFftSize - partial.count))
                    }
                    TAP_DEBUG("file_playback", "PARTIAL_FLUSH_EMIT | emitting FFT frame with \(partial.count) samples")
                    self.performFFT(on: partial)
                    TAP_DEBUG("file_playback", "PARTIAL_FLUSH_EMIT_DONE")
                }
            }

            // 2. Flush any active gated capture before mic restart.
            //    Must run on main thread because finishGatedFFTCapture
            //    updates @Published properties.  Synchronous so the flush
            //    completes before mic restart.  Mirrors Python where the
            //    flush runs on the playback worker but Qt signal delivery
            //    is queued to main.
            TAP_DEBUG("file_playback", "PRE_MIC_RESTART — calling preMicRestartHandler")
            DispatchQueue.main.sync {
                self.preMicRestartHandler?()
            }
            TAP_DEBUG("file_playback", "PRE_MIC_RESTART_DONE")

            // 3. UI state + mic restart on main thread.
            TAP_DEBUG("file_playback", "MIC_RESTART — dispatching to main thread")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.filePlaybackGeneration == myGeneration else { return }

                TAP_DEBUG("file_playback", "MIC_RESTART — main thread: isPlayingFile=false, starting mic")
                self.isPlayingFile = false

                // Switch back to live mic.
                try? self.start()
                TAP_DEBUG("file_playback", "MIC_RESTART_DONE")
                capturedCompletion?()
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
    // MARK: - Audio File Reading (ExtAudioFile)

    /// Reads an audio file as mono Float32 samples using ExtAudioFile.
    /// Supports all formats Core Audio handles: WAV, AIFF, CAF, MP3, AAC,
    /// ALAC, FLAC, etc.  Mirrors Python's `soundfile.read()` behavior —
    /// opens the file, requests Float32 mono output, reads all frames.
    ///
    /// - Returns: A tuple of (mono Float32 samples, file sample rate in Hz).
    /// - Throws: If the file cannot be opened or read.
    static func readAudioFileAsMonoFloat32(url: URL) throws -> ([Float], Double) {
        var extAudioFile: ExtAudioFileRef?
        var status = ExtAudioFileOpenURL(url as CFURL, &extAudioFile)
        guard status == noErr, let audioFile = extAudioFile else {
            throw NSError(domain: "AudioFileReader", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey:
                                        "ExtAudioFileOpenURL failed with status \(status)"])
        }
        defer { ExtAudioFileDispose(audioFile) }

        // ── Get the file's native format to extract sample rate & channels ──
        var fileFormat = AudioStreamBasicDescription()
        var propSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = ExtAudioFileGetProperty(audioFile,
                                         kExtAudioFileProperty_FileDataFormat,
                                         &propSize, &fileFormat)
        guard status == noErr else {
            throw NSError(domain: "AudioFileReader", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey:
                                        "Failed to get file format: status \(status)"])
        }
        let fileSampleRate = fileFormat.mSampleRate
        let fileChannels = fileFormat.mChannelsPerFrame

        // ── Get total frame count ───────────────────────────────────────────
        var totalFrames: Int64 = 0
        propSize = UInt32(MemoryLayout<Int64>.size)
        status = ExtAudioFileGetProperty(audioFile,
                                         kExtAudioFileProperty_FileLengthFrames,
                                         &propSize, &totalFrames)
        guard status == noErr, totalFrames > 0 else {
            throw NSError(domain: "AudioFileReader", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey:
                                        "Failed to get frame count or file is empty: status \(status)"])
        }

        // ── Set client format to mono Float32 at the file's sample rate ─────
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: fileSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,    // mono — ExtAudioFile handles downmix
            mBitsPerChannel: 32,
            mReserved: 0
        )
        status = ExtAudioFileSetProperty(audioFile,
                                         kExtAudioFileProperty_ClientDataFormat,
                                         UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
                                         &clientFormat)
        guard status == noErr else {
            throw NSError(domain: "AudioFileReader", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey:
                                        "Failed to set client format: status \(status)"])
        }

        // ── Read all frames ─────────────────────────────────────────────────
        let frameCount = Int(totalFrames)
        var monoSamples = [Float](repeating: 0, count: frameCount)
        var framesRead = 0

        // Read in chunks to handle any partial reads
        let chunkSize = 16384
        while framesRead < frameCount {
            let framesToRead = min(chunkSize, frameCount - framesRead)
            var frameCountMutable = UInt32(framesToRead)

            let bufferList = AudioBufferList.allocate(maximumBuffers: 1)
            defer { free(bufferList.unsafeMutablePointer) }

            monoSamples.withUnsafeMutableBufferPointer { ptr in
                bufferList[0] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(framesToRead * 4),
                    mData: UnsafeMutableRawPointer(ptr.baseAddress! + framesRead)
                )
            }

            status = ExtAudioFileRead(audioFile, &frameCountMutable,
                                      bufferList.unsafeMutablePointer)
            guard status == noErr else {
                throw NSError(domain: "AudioFileReader", code: Int(status),
                              userInfo: [NSLocalizedDescriptionKey:
                                            "ExtAudioFileRead failed at frame \(framesRead): status \(status)"])
            }

            if frameCountMutable == 0 { break }  // EOF
            framesRead += Int(frameCountMutable)
        }

        // Trim if file was shorter than reported (shouldn't happen, but be safe)
        if framesRead < frameCount {
            monoSamples = Array(monoSamples.prefix(framesRead))
        }

        engineLog.info("readAudioFileAsMonoFloat32: \(framesRead) frames, \(fileChannels) ch, \(Int(fileSampleRate)) Hz (via ExtAudioFile)")

        return (monoSamples, fileSampleRate)
    }

    func stop() {
        engineLog.info("Stop requested")

        #if os(macOS)
        // Remove the sample-rate listener so it doesn't fire during the stop/restart cycle
        unregisterSampleRateListener()
        #endif

        // Cancel any in-flight file-playback worker.  Bumping the generation
        // counter causes the worker's next chunk-loop iteration to exit.
        filePlaybackGeneration += 1

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
