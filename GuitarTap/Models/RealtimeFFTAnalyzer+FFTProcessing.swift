//
//  RealtimeFFTAnalyzer+FFTProcessing.swift
//  GuitarTap
//
// @parity dsp/fft
// @parity dsp/guitar-fft

import AVFoundation
import Accelerate

// MARK: - FFT Processing

extension RealtimeFFTAnalyzer {

    /// Updates the frequency bin values based on the effective sample rate.
    ///
    /// Each bin represents a frequency range determined by:
    /// `frequency[i] = i * (sampleRate / fftSize)`
    func updateFrequencyBins() {
        // Calculate the frequency resolution per bin
        let binWidth = Float(actualSampleRate) / Float(fftSize)
        
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
    func updateCalibrationCorrections() {
        guard let calibration = activeCalibration else {
            calibrationCorrections = []
            return
        }
        
        // Pre-compute corrections for all frequency bins
        calibrationCorrections = calibration.corrections(for: frequencies)
    }
    
    /// Updates all performance and analysis metrics based on current configuration.
    ///
    /// This method calculates:
    /// - Frequency resolution (Hz per bin)
    /// - Bandwidth (total frequency range)
    /// - Sample length (time duration of each FFT window)
    /// - Frame rate (FFT calculations per second, accounting for overlap)
    func updateMetrics() {
        let sampleRate = Float(actualSampleRate)
        let fftSizeFloat = Float(fftSize)
        
        // Calculate metrics
        let freqRes = sampleRate / fftSizeFloat
        let bw = sampleRate / 2.0
        let sampleLen = fftSizeFloat / sampleRate
        
        // Frame rate: one FFT frame per fftSize samples (0% overlap, hop = fftSize)
        let fr = sampleRate / fftSizeFloat
        
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
    /// 3. Processes complete FFT-size chunks
    /// 4. Performs FFT on each chunk
    ///
    /// - Parameter buffer: The audio buffer captured from the microphone
    ///
    /// - Note: This method runs on the audioProcessingQueue, not the main thread or audio thread.
    ///         All buffer access is synchronized via bufferAccessQueue to prevent race conditions.
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Safety check: ensure we have channel data
        guard let channelData = buffer.floatChannelData else {
            gtLog("⚠️ No channel data in buffer!")
            return
        }
        
        // Extract samples from the first channel
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        
        processRawSamples(samples)
    }

    /// Process raw Float32 samples through the full audio pipeline: raw-sample
    /// delivery, RMS/clipping detection, level-crossing tap trigger, FFT
    /// accumulation and execution.
    ///
    /// Called from `processAudioBuffer` (mic/engine path) and directly from the
    /// file-playback sample pump (direct-injection path that bypasses
    /// AVAudioEngine to avoid dithering noise).
    func processRawSamples(_ samples: [Float]) {
        if !firstBufferReceived {
            firstBufferReceived = true
        }

        // Deliver raw samples to MPM or other consumers (runs on audioProcessingQueue)
        rawSampleHandler?(samples, actualSampleRate)
        
        // Calculate fast input level (RMS) for decay tracking
        // This updates on every audio buffer (~43Hz with 1024 buffer) instead of per FFT frame
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        let levelDB = rms > 0 ? 20 * log10(rms) : -100
        let wallNow = Date()

        // ── Input-clipping detection ────────────────────────────────
        // Sample-domain check (peak |sample| ≥ 0.99) catches transient
        // peaks; RMS check (>= 0 dBFS) catches sustained clipping.  Either
        // condition holds the clipping state True for clipHoldSeconds before
        // clearing.  Edge-triggered publish so SwiftUI only re-renders on
        // True↔False transitions.  Mirrors Python `_FftProcessingThread`
        // clipping detection block.
        var peakAbs: Float = 0
        vDSP_maxmgv(samples, 1, &peakAbs, vDSP_Length(samples.count))
        let chunkClipped = (peakAbs >= 0.99) || (levelDB >= 0)
        if chunkClipped {
            self.lastClipTime = wallNow
        }
        let newClipState: Bool = {
            guard let last = self.lastClipTime else { return false }
            return wallNow.timeIntervalSince(last) < self.clipHoldSeconds
        }()

        // ── Audio-queue fast-path: snapshot pre-roll at threshold crossing ──
        // Fires BEFORE the main-thread dispatch so the pre-roll buffer is
        // captured at the exact audio buffer that crosses the threshold,
        // eliminating the Combine dispatch delay that otherwise shifts the
        // pre-roll past the tap attack transient.
        //
        // Requires ``levelCrossingConfirmationChunks`` consecutive
        // above-threshold chunks (default 2 = ~43 ms) before firing.  This
        // rejects brief noise bumps that would otherwise consume a phase's
        // gated capture window — especially during file playback where
        // there's no human review-time gap between phases.  ``alignCaptureToOnset``
        // re-anchors the FFT window to the sample-precise onset, so the few
        // chunks of trigger delay introduced here are invisible downstream.
        if isPlayingFile {
            TAP_DEBUG("processRawSamples", "LEVEL_CHECK | armed=\(levelCrossingArmed) levelDB=\(String(format: "%.1f", levelDB)) threshold=\(String(format: "%.1f", levelCrossingThreshold)) prevDB=\(String(format: "%.1f", previousLevelDB)) chunkLen=\(samples.count) fileSamplePos=\(samplesConsumed)")
        }
        if levelCrossingArmed {
            let aboveThreshold = levelDB > levelCrossingThreshold
            let prevAboveThreshold = previousLevelDB > levelCrossingThreshold
            let confirmTarget = Self.levelCrossingConfirmationChunks
            if aboveThreshold {
                if levelCrossingConsecutiveAbove > 0 {
                    // Already counting — extend the run.
                    levelCrossingConsecutiveAbove += 1
                } else if !prevAboveThreshold {
                    // Fresh rising edge — start a new candidate run.
                    levelCrossingConsecutiveAbove = 1
                    if isPlayingFile && confirmTarget > 1 {
                        TAP_DEBUG("processRawSamples", "LEVEL_CROSSING_PENDING | rmsDB=\(String(format: "%.1f", levelDB)) prevDB=\(String(format: "%.1f", previousLevelDB)) need=\(confirmTarget - 1) more")
                    }
                }
                // If aboveThreshold && counter == 0 && prevAboveThreshold,
                // signal was already above when arming happened — we wait
                // for a fall + rise (handled when level drops then climbs).
                if levelCrossingConsecutiveAbove >= confirmTarget {
                    levelCrossingArmed = false
                    if isPlayingFile {
                        TAP_DEBUG("processRawSamples", "LEVEL_CROSSING_FIRED | rmsDB=\(String(format: "%.1f", levelDB)) prevDB=\(String(format: "%.1f", previousLevelDB)) confirmedBy=\(confirmTarget)")
                    }
                    // didSet on levelCrossingArmed resets the counter.
                    levelCrossingHandler?()
                }
            } else {
                // Below threshold — abort any in-progress candidate run.
                if levelCrossingConsecutiveAbove > 0 && isPlayingFile {
                    TAP_DEBUG("processRawSamples", "LEVEL_CROSSING_CANCELED | rmsDB=\(String(format: "%.1f", levelDB)) (signal fell below after \(levelCrossingConsecutiveAbove)/\(confirmTarget) chunks)")
                }
                levelCrossingConsecutiveAbove = 0
            }
        }
        previousLevelDB = levelDB

        // ── Direct RMS callback (mirrors Python rmsLevelChanged signal) ──
        // Called on the audio processing queue, exactly like rawSampleHandler
        // and levelCrossingHandler.  TapToneAnalyzer wires this to
        // onRmsLevelChanged so tap detection runs synchronously per chunk
        // during both live mic and file playback — identical to Python's
        // proc_thread.rmsLevelChanged.connect(self._on_rms_level_changed).
        rmsLevelHandler?(levelDB)

        // Update @Published properties on main thread for UI (level meter,
        // clipping indicator).  This is display-only — tap detection no
        // longer depends on this path.
        DispatchQueue.main.async {
            self.inputLevelDB = levelDB

            // Track recent peak: update if current level is higher, or if peak has expired
            if levelDB > self.recentPeakLevelDB || wallNow.timeIntervalSince(self.recentPeakTime) > self.peakHoldDuration {
                self.recentPeakLevelDB = levelDB
                self.recentPeakTime = wallNow
            }

            // Edge-triggered publish so SwiftUI re-renders only on transitions.
            if newClipState != self.isClipping {
                self.isClipping = newClipState
            }
        }
        
        // Thread-safe: Accumulate samples in input buffer using synchronized access
        bufferAccessQueue.sync {
            inputBuffer.append(contentsOf: samples)
        }
        
        // Process when we have enough samples for an FFT (0% overlap, hop = fftSize)
        let hopSize = fftSize
        
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
                performFFT(on: chunk)
            }
        }
    }
    
    /// Performs the pure FFT computation on a block of audio samples and returns
    /// the magnitude spectrum in dBFS.
    ///
    /// This method contains the deterministic DSP core shared by `performFFT(on:)`
    /// (streaming/display path) and the test suite.  It has no side effects: it
    /// reads `fftSetup` and `window` from `self` but
    /// writes nothing — all results are returned.
    ///
    /// - Parameter samples: Audio samples to analyse, must be of length `fftSize`.
    /// - Returns: Magnitude spectrum in dBFS, length `fftSize / 2`, or an empty
    ///   array if the FFT setup is not available.
    func computeFFT(on samples: [Float]) -> [Float] {
        guard let setup = fftSetup else { return [] }

        var samples = samples

        // Apply rectangular window (all ones — effectively no windowing).
        // Intentional for the live display path: flat amplitude response is
        // preferable to sidelobe suppression for a real-time visualisation.
        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(fftSize))

        // Deinterleave even/odd samples into split-complex format required by vDSP_DFT_zrop:
        // even indices → real parts, odd indices → imaginary parts.
        var realParts = [Float](repeating: 0, count: fftSize / 2)
        var imagParts = [Float](repeating: 0, count: fftSize / 2)
        for i in 0..<(fftSize / 2) {
            realParts[i] = samples[i * 2]
            imagParts[i] = samples[i * 2 + 1]
        }

        // Execute FFT in-place
        realParts.withUnsafeMutableBufferPointer { realPtr in
            imagParts.withUnsafeMutableBufferPointer { imagPtr in
                vDSP_DFT_Execute(setup, realPtr.baseAddress!, imagPtr.baseAddress!,
                                 realPtr.baseAddress!, imagPtr.baseAddress!)
            }
        }

        // Compute magnitudes, normalise by fftSize, convert to dB
        var mags = [Float](repeating: 0, count: fftSize / 2)
        realParts.withUnsafeBufferPointer { realPtr in
            imagParts.withUnsafeBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: realPtr.baseAddress!),
                    imagp: UnsafeMutablePointer(mutating: imagPtr.baseAddress!)
                )
                var scale: Float = 1.0 / Float(fftSize)
                vDSP_vsmul(splitComplex.realp, 1, &scale, splitComplex.realp, 1, vDSP_Length(fftSize / 2))
                vDSP_vsmul(splitComplex.imagp, 1, &scale, splitComplex.imagp, 1, vDSP_Length(fftSize / 2))
                vDSP_zvabs(&splitComplex, 1, &mags, 1, vDSP_Length(fftSize / 2))
            }
        }

        var db = [Float](repeating: -100, count: fftSize / 2)
        var ref: Float = 1.0
        vDSP_vdbcon(mags, 1, &ref, &db, 1, vDSP_Length(fftSize / 2), 1)

        return db
    }

    /// Performs a Fast Fourier Transform on audio samples and updates published magnitude data.
    ///
    /// Delegates the pure DSP work to `computeFFT(on:)`, applies microphone calibration
    /// corrections, then publishes the results on the main thread.  Also tracks processing
    /// time and throttles UI updates.
    ///
    /// Calibration is applied here (not inside `computeFFT`) so that `computeFFT` remains
    /// a truly pure function — its output depends only on its input `samples` argument and
    /// the FFT configuration, not on any mutable instance state like `calibrationCorrections`.
    /// This mirrors the Python architecture where `dft_anal` is a side-effect-free module-level
    /// function and calibration is applied by the caller (`_FftProcessingThread.run()`).
    ///
    /// - Parameter samples: Audio samples to analyze, must be of length fftSize
    ///
    /// - Note: This method runs on the audioProcessingQueue. Results are published
    ///         on the main thread via @Published properties for SwiftUI compatibility.
    func performFFT(on samples: [Float]) {
        let startTime = CFAbsoluteTimeGetCurrent()

        var db = computeFFT(on: samples)
        guard !db.isEmpty else { return }

        // Apply microphone calibration corrections if available.
        // Kept here (not in computeFFT) so computeFFT remains a pure function.
        // Mirrors Python _FftProcessingThread.run(): mag_y_db = mag_y_db + calibration.
        if !calibrationCorrections.isEmpty && calibrationCorrections.count == db.count {
            vDSP_vadd(db, 1, calibrationCorrections, 1, &db, 1, vDSP_Length(db.count))
        }

        // ── FILE_DEBUG: per-FFT-frame trace ─────────────────────────────
        // Records frame ordinal, file-time of frame start, peakMag, dominant-
        // bin frequency, and whether the file-playback source is the active
        // producer.  Mirrors the equivalent block in Python
        // _FftProcessingThread.run().
        fftFrameCounter += 1
        samplesConsumed += fftSize

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
            
            fftCount += 1

            // Throttle UI updates to avoid flooding main queue
            let currentTime = CFAbsoluteTimeGetCurrent()
            let shouldPublish = (currentTime - lastPublishTime) >= minPublishInterval
            
            if shouldPublish {
                lastPublishTime = currentTime
                
                // Update published properties on main thread for SwiftUI
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    self.magnitudes = db
                    self.peakFrequency = peakFreq
                    self.peakMagnitude = peakMag
                    self.processingTimeMs = processingTime
                    self.avgProcessingTimeMs = avgTime
                    // displayLevelDB updates at the same rate as the graph (gated by shouldPublish)
                    self.displayLevelDB = self.inputLevelDB
                }
            }
        }
    }
    
    // MARK: - Gated FFT (for plate/brace tap measurement)

    /// Run a one-shot FFT on a pre-captured sample buffer and return linear
    /// magnitudes and a matching frequency axis.
    ///
    /// Unlike `performFFT(on:)` this method:
    ///  - Accepts an arbitrary-length buffer (zero-padded to the next power of
    ///    two, capped at 32 768 samples for ~0.74 Hz/bin resolution at 44.1 kHz)
    ///  - Creates a temporary DFT setup rather than reusing the continuous one
    ///  - Returns raw values rather than publishing them
    ///  - Applies `activeCalibration` corrections at the bin frequencies
    ///
    /// - Parameters:
    ///   - samples:    PCM samples captured immediately after tap detection.
    ///   - sampleRate: The hardware sample rate at the time of capture.
    /// - Returns: A tuple of `(magnitudes, frequencies)` in dB and Hz respectively.
    func computeGatedFFT(samples: [Float], sampleRate: Double) -> (magnitudes: [Float], frequencies: [Float]) {
        // Choose FFT size: next power-of-two >= sample count, capped at 32768.
        // 32768 samples @ 44100 Hz ≈ 743 ms window, freq resolution ≈ 1.35 Hz/bin.
        let targetSize = 32768
        let paddedSize = min(targetSize, nextPowerOfTwo(samples.count))

        guard let setup = vDSP_DFT_zrop_CreateSetup(
            nil,
            vDSP_Length(paddedSize),
            vDSP_DFT_Direction.FORWARD
        ) else {
            gtLog("⚠️ computeGatedFFT: failed to create DFT setup for size \(paddedSize)")
            return ([], [])
        }
        defer { vDSP_DFT_DestroySetup(setup) }

        // Zero-pad (or truncate) to paddedSize, then apply a Hann window.
        // Unlike the live display path (which uses a rectangular window for simplicity),
        // this result is what gets saved and analysed: peak frequencies feed mode
        // classification, Q-factor calculation, and plate/brace property formulas.
        // The Hann window suppresses spectral sidelobes by ~31 dB compared to a
        // rectangular window, giving sharper, cleaner peaks and therefore more accurate
        // frequency and Q readings. The amplitude roll-off at the frame edges is
        // not a concern here because the captured buffer naturally starts and ends
        // near silence (pre-roll silence → tap transient → decaying ring → silence).
        var padded = [Float](repeating: 0, count: paddedSize)
        let copyCount = min(samples.count, paddedSize)
        padded[0..<copyCount] = samples[0..<copyCount]

        var hannWindow = [Float](repeating: 0, count: paddedSize)
        // Use HANN_DENORM (standard unit-peak Hann window) rather than HANN_NORM.
        // HANN_NORM energy-normalises the window by scaling each sample by √(8/3),
        // which inflates magnitudes by +4.26 dB when combined with 1/N normalisation.
        // HANN_DENORM produces w[n] = 0.5·(1 − cos(2πn/N)) with peak = 1.0, matching
        // the standard Hann window used by numpy (np.hanning) in the Python port.
        vDSP_hann_window(&hannWindow, vDSP_Length(paddedSize), Int32(vDSP_HANN_DENORM))
        vDSP_vmul(padded, 1, hannWindow, 1, &padded, 1, vDSP_Length(paddedSize))

        // Deinterleave into split-complex format required by vDSP_DFT_zrop
        var realParts = [Float](repeating: 0, count: paddedSize / 2)
        var imagParts = [Float](repeating: 0, count: paddedSize / 2)
        for i in 0..<(paddedSize / 2) {
            realParts[i] = padded[i * 2]
            imagParts[i] = padded[i * 2 + 1]
        }

        realParts.withUnsafeMutableBufferPointer { rp in
            imagParts.withUnsafeMutableBufferPointer { ip in
                vDSP_DFT_Execute(setup,
                                 rp.baseAddress!, ip.baseAddress!,
                                 rp.baseAddress!, ip.baseAddress!)
            }
        }

        // Compute magnitudes, normalise, convert to dB
        var mags = [Float](repeating: 0, count: paddedSize / 2)
        realParts.withUnsafeBufferPointer { rp in
            imagParts.withUnsafeBufferPointer { ip in
                var sc = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: rp.baseAddress!),
                    imagp: UnsafeMutablePointer(mutating: ip.baseAddress!)
                )
                var scale: Float = 1.0 / Float(paddedSize)
                vDSP_vsmul(sc.realp, 1, &scale, sc.realp, 1, vDSP_Length(paddedSize / 2))
                vDSP_vsmul(sc.imagp, 1, &scale, sc.imagp, 1, vDSP_Length(paddedSize / 2))
                vDSP_zvabs(&sc, 1, &mags, 1, vDSP_Length(paddedSize / 2))
            }
        }

        var db = [Float](repeating: -160, count: paddedSize / 2)
        var ref: Float = 1.0
        vDSP_vdbcon(mags, 1, &ref, &db, 1, vDSP_Length(paddedSize / 2), 1)

        // Build frequency axis
        let binWidth = Float(sampleRate) / Float(paddedSize)
        let freqs = (0..<(paddedSize / 2)).map { Float($0) * binWidth }

        // Apply microphone calibration at our bin frequencies using the same
        // bulk-interpolation helper used by the continuous FFT path.
        if let cal = activeCalibration {
            let corrections = cal.corrections(for: freqs)
            if corrections.count == db.count {
                vDSP_vadd(db, 1, corrections, 1, &db, 1, vDSP_Length(db.count))
            }
        }

        return (magnitudes: db, frequencies: freqs)
    }

    /// Returns the smallest power of two that is ≥ `n`.
    ///
    /// Used to choose the zero-padding size for `computeGatedFFT`, which requires
    /// a power-of-two sample count. Returns 2 for any `n` ≤ 1.
    ///
    /// - Parameter n: Input value.
    /// - Returns: Smallest power of two ≥ `n` (minimum 2).
    func nextPowerOfTwo(_ n: Int) -> Int {
        guard n > 1 else { return 2 }
        var p = 2
        while p < n { p <<= 1 }
        return p
    }
}
