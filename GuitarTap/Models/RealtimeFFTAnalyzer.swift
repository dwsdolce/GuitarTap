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
    
    /// The actual sample rate of the audio hardware
    /// - Note: This is determined at runtime when the audio engine starts
    private var actualSampleRate: Double = 0
    
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
    @Published var peakMagnitude: Float = 0
    
    /// Indicates whether the analyzer is currently running and processing audio
    @Published var isRunning: Bool = false
    
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
    /// Depends on hop size (overlap). With 50% overlap: sampleRate / (fftSize / 2)
    @Published var frameRate: Float = 0
    
    /// Processing time in milliseconds - time taken to process the last FFT frame
    @Published var processingTimeMs: Float = 0
    
    /// Average processing time over the last several frames (milliseconds)
    @Published var avgProcessingTimeMs: Float = 0
    
    /// Circular buffer for tracking recent processing times
    private var processingTimeHistory: [Float] = []
    private let processingTimeHistorySize = 30  // Track last 30 frames
    
    // MARK: - Initialization
    
    /// Creates a new real-time FFT analyzer with specified configuration.
    ///
    /// - Parameters:
    ///   - fftSize: The size of the FFT window. Must be a power of 2. Larger values provide
    ///              better frequency resolution but slower time response. Default is 4096.
    ///              Common values: 2048, 4096, 8192, 16384
    ///   - targetSampleRate: The desired sample rate for processing. Default is 44100 Hz.
    ///                      If hardware uses a different rate, audio will be resampled.
    ///
    /// - Note: The frequency resolution will be `targetSampleRate / fftSize` Hz per bin.
    ///         For example, 48000 Hz / 16384 = ~2.93 Hz per bin.
    init(fftSize: Int = 4096, targetSampleRate: Double = 44100) {
        self.fftSize = fftSize
        self.targetSampleRate = targetSampleRate
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
        
        // Calculate frequency bins based on target sample rate
        updateFrequencyBins()
        
        // Initialize metrics
        updateMetrics()
    }
    
    /// Cleans up resources when the analyzer is deallocated
    deinit {
        stop()
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
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
        // Get the input format from the hardware
        // This tells us the actual sample rate and channel configuration
        let inputFormat = inputNode.inputFormat(forBus: 0)
        actualSampleRate = inputFormat.sampleRate
        
        print("Hardware sample rate: \(actualSampleRate) Hz")
        print("Target sample rate: \(targetSampleRate) Hz")
        print("FFT size: \(fftSize)")
        
        // Update frequency bins based on target sample rate
        // This ensures frequency labels are correct regardless of hardware sample rate
        updateFrequencyBins()
        
        // Update metrics based on actual configuration
        updateMetrics()
        
        // Install tap on input node to receive audio buffers
        // The tap captures audio data before it's processed by other nodes
        // Audio callback happens on a real-time audio thread provided by AVAudioEngine
        let bufferSize = AVAudioFrameCount(fftSize)
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            // Immediately dispatch to our dedicated processing queue to avoid blocking the audio thread
            // The audio thread must return quickly to prevent dropouts and glitches
            guard let self = self else { return }
            self.audioProcessingQueue.async {
                self.processAudioBuffer(buffer)
            }
        }
        
        // Request microphone permission and start the audio engine
        try audioEngine.start()
        
        // Update UI state on main thread since this property is @Published
        DispatchQueue.main.async {
            self.isRunning = true
        }
        
        print("Audio engine started successfully")
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
        if audioEngine.isRunning {
            // Remove the audio tap to stop receiving buffers
            inputNode.removeTap(onBus: 0)
            
            // Stop the audio engine
            audioEngine.stop()
            
            // Clear the input buffer on the buffer access queue
            bufferAccessQueue.sync {
                inputBuffer.removeAll()
            }
            
            // Update UI state on main thread
            DispatchQueue.main.async {
                self.isRunning = false
            }
            
            print("Audio engine stopped")
        }
    }
    
    // MARK: - Private Processing Methods
    
    /// Updates the frequency bin values based on the target sample rate.
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
        // Calculate the frequency resolution per bin
        let binWidth = Float(targetSampleRate) / Float(fftSize)
        
        // Populate frequency array
        // Only need fftSize/2 bins because FFT of real data is symmetric
        for i in 0..<(fftSize / 2) {
            frequencies[i] = Float(i) * binWidth
        }
    }
    
    /// Updates all performance and analysis metrics based on current configuration.
    ///
    /// This method calculates:
    /// - Frequency resolution (Hz per bin)
    /// - Bandwidth (total frequency range)
    /// - Sample length (time duration of each FFT window)
    /// - Frame rate (FFT calculations per second, accounting for overlap)
    private func updateMetrics() {
        let sampleRate = Float(targetSampleRate)
        let fftSizeFloat = Float(fftSize)
        
        // Frequency resolution: how many Hz each bin represents
        frequencyResolution = sampleRate / fftSizeFloat
        
        // Bandwidth: maximum frequency we can analyze (Nyquist frequency)
        bandwidth = sampleRate / 2.0
        
        // Sample length: how long in time each FFT window represents
        sampleLengthSeconds = fftSizeFloat / sampleRate
        
        // Frame rate: with 50% overlap, hop size is fftSize/2
        // Number of frames per second = sampleRate / hopSize
        let hopSize = fftSizeFloat / 2.0
        frameRate = sampleRate / hopSize
        
        print("=== Analysis Metrics ===")
        print("Frequency Resolution: \(frequencyResolution) Hz")
        print("Bandwidth: \(bandwidth) Hz (0 Hz to \(bandwidth) Hz)")
        print("Sample Length: \(sampleLengthSeconds * 1000) ms (\(sampleLengthSeconds) seconds)")
        print("Frame Rate: \(frameRate) Hz")
        print("=======================")
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
        guard let channelData = buffer.floatChannelData else { return }
        
        // Extract samples from the first channel
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        
        // Thread-safe: Accumulate samples in input buffer using synchronized access
        bufferAccessQueue.sync {
            inputBuffer.append(contentsOf: samples)
        }
        
        // Process when we have enough samples for an FFT
        // Use 50% overlap (hop size = fftSize/2) for smoother frequency response
        var shouldContinue = true
        while shouldContinue {
            var chunk: [Float]?
            
            // Thread-safe: Check and extract chunk from buffer
            bufferAccessQueue.sync {
                if inputBuffer.count >= fftSize {
                    // Extract a chunk of samples
                    chunk = Array(inputBuffer.prefix(fftSize))
                    
                    // Remove half the samples (50% overlap)
                    // This provides better time resolution while maintaining frequency accuracy
                    inputBuffer.removeFirst(fftSize / 2)
//                    inputBuffer.removeFirst(fftSize)

                } else {
                    shouldContinue = false
                }
            }
            
            // Process the chunk outside the synchronized block to minimize lock time
            if let chunk = chunk {
                // Resample if needed to match target sample rate
                let processedChunk: [Float]
                if abs(actualSampleRate - targetSampleRate) > 1.0 {
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
            
            // Update published properties on main thread for SwiftUI
            DispatchQueue.main.async {
                self.magnitudes = db
                self.peakFrequency = peakFreq
                self.peakMagnitude = peakMag
                self.processingTimeMs = processingTime
                self.avgProcessingTimeMs = avgTime
            }
        }
    }
}

