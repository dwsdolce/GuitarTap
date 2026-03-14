//
//  RealtimeFFTAnalyzer+FFTProcessing.swift
//  GuitarTap
//

import AVFoundation
import Accelerate

// MARK: - FFT Processing

extension RealtimeFFTAnalyzer {

    /// Updates the frequency bin values based on the effective sample rate.
    ///
    /// Each bin represents a frequency range determined by:
    /// `frequency[i] = i * (sampleRate / fftSize)`
    func updateFrequencyBins() {
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
    func updateCalibrationCorrections() {
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
    func updateMetrics() {
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
    /// 3. Processes complete FFT-size chunks with configurable overlap
    /// 4. Resamples audio if hardware rate differs from target rate
    /// 5. Performs FFT on each chunk
    ///
    /// - Parameter buffer: The audio buffer captured from the microphone
    ///
    /// - Note: This method runs on the audioProcessingQueue, not the main thread or audio thread.
    ///         All buffer access is synchronized via bufferAccessQueue to prevent race conditions.
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
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

        // Deliver raw samples to MPM or other consumers (runs on audioProcessingQueue)
        rawSampleHandler?(samples, actualSampleRate)
        
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
    func resample(_ samples: [Float], from inputRate: Double, to outputRate: Double) -> [Float] {
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
    /// 1. Applies a rectangular window (all ones) to audio samples
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
    func performFFT(on samples: [Float]) {
        // Start timing the FFT processing
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Safety check: ensure FFT setup is valid
        guard let setup = fftSetup else { return }
        
        var samples = samples
        
        // Apply rectangular window (all ones — effectively no windowing) to audio samples.
        // This is intentional for the live display path: we favour flat amplitude
        // response over sidelobe suppression since the result is only used visually.
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
                
                // Update published properties on main thread for SwiftUI
                // Use DispatchQueue.main.async to avoid blocking audio processing
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    self.magnitudes = db
                    self.peakFrequency = peakFreq
                    self.peakMagnitude = peakMag
                    self.processingTimeMs = processingTime
                    self.avgProcessingTimeMs = avgTime
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
            print("⚠️ computeGatedFFT: failed to create DFT setup for size \(paddedSize)")
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
        vDSP_hann_window(&hannWindow, vDSP_Length(paddedSize), Int32(vDSP_HANN_NORM))
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
