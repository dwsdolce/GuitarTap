//
//  TapToneAnalyzer.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import SwiftUI
import Combine

// MARK: - Tap Tone Analysis Models

/// Represents a detected resonant peak in the frequency spectrum
struct ResonantPeak: Identifiable, Codable {
    let id: UUID
    let frequency: Float        // Hz
    let magnitude: Float        // dB
    let quality: Float          // Q factor (sharpness)
    let bandwidth: Float        // Hz at -3dB points
    let timestamp: Date
    
    init(frequency: Float, magnitude: Float, quality: Float = 0, bandwidth: Float = 0) {
        self.id = UUID()
        self.frequency = frequency
        self.magnitude = magnitude
        self.quality = quality
        self.bandwidth = bandwidth
        self.timestamp = Date()
    }
}

/// Guitar mode classification based on frequency ranges
enum GuitarMode: String, Codable {
    case helmholtz = "Helmholtz (Air)"
    case crossGrain = "Cross-Grain"
    case longGrain = "Long-Grain"
    case monopole = "Monopole"
    case dipole = "Dipole"
    case ringMode = "Ring Mode"
    case upperModes = "Upper Modes"
    case unknown = "Unknown"
    
    /// Classify a frequency into a guitar mode
    static func classify(frequency: Float) -> GuitarMode {
        switch frequency {
        case 85...115:
            return .helmholtz
        case 90...120 where frequency < 110:
            return .crossGrain
        case 180...220:
            return .longGrain
        case 200...280:
            return .monopole
        case 350...450:
            return .dipole
        case 600...850:
            return .ringMode
        case 850...:
            return .upperModes
        default:
            return .unknown
        }
    }
    
    /// Ideal frequency range for this mode
    var idealRange: ClosedRange<Float> {
        switch self {
        case .helmholtz: return 95...105
        case .crossGrain: return 95...110
        case .longGrain: return 190...210
        case .monopole: return 220...260
        case .dipole: return 380...420
        case .ringMode: return 650...750
        case .upperModes: return 850...2000
        case .unknown: return 0...20000
        }
    }
}

/// Represents a complete tap tone measurement
struct TapToneMeasurement: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let peaks: [ResonantPeak]
    let decayTime: Float?       // seconds
    let tapLocation: String?    // e.g., "Bridge", "Soundhole", "Upper Bout"
    let notes: String?
    let spectrumSnapshot: [Float]?  // Full spectrum for comparison
    
    init(peaks: [ResonantPeak], decayTime: Float? = nil, tapLocation: String? = nil, notes: String? = nil, spectrum: [Float]? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.peaks = peaks
        self.decayTime = decayTime
        self.tapLocation = tapLocation
        self.notes = notes
        self.spectrumSnapshot = spectrum
    }
    
    /// Get tap tone ratio (long-grain / cross-grain)
    var tapToneRatio: Float? {
        guard let crossGrain = peaks.first(where: { GuitarMode.classify(frequency: $0.frequency) == .crossGrain }),
              let longGrain = peaks.first(where: { GuitarMode.classify(frequency: $0.frequency) == .longGrain }) else {
            return nil
        }
        return longGrain.frequency / crossGrain.frequency
    }
}

// MARK: - Tap Tone Analyzer

/// Advanced tap tone analysis for guitar lutherie
final class TapToneAnalyzer: ObservableObject {
    
    // MARK: - Dependencies
    
    /// The underlying FFT analyzer
    private let fftAnalyzer: RealtimeFFTAnalyzer
    
    // MARK: - Configuration
    
    /// Minimum magnitude threshold for peak detection (dB)
    @Published var peakThreshold: Float = -60
    
    /// Minimum frequency for analysis (Hz)
    @Published var minFrequency: Float = 50
    
    /// Maximum frequency for analysis (Hz)
    @Published var maxFrequency: Float = 2000
    
    /// Number of peaks to track
    @Published var maxPeaks: Int = 10
    
    /// Decay threshold for ring-out measurement (dB below peak)
    @Published var decayThreshold: Float = 20
    
    /// Number of taps to average (1 = no averaging, 3-5 recommended)
    @Published var numberOfTaps: Int = 1
    
    /// Time window after tap to capture spectrum (seconds)
    @Published var captureWindow: TimeInterval = 0.2
    
    /// Tap detection threshold in dB (absolute magnitude level to trigger tap)
    @Published var tapDetectionThreshold: Float = -40.0
    
    /// Hysteresis margin in dB (prevents bouncing around threshold)
    /// Signal must fall this many dB below threshold before ready for next tap
    @Published var hysteresisMargin: Float = 3.0
    
    // MARK: - Published Results
    
    /// Currently detected peaks
    @Published var currentPeaks: [ResonantPeak] = []
    
    /// Identified modes with classifications
    @Published var identifiedModes: [(peak: ResonantPeak, mode: GuitarMode)] = []
    
    /// Current decay time (seconds)
    @Published var currentDecayTime: Float?
    
    /// Peak frequency history for tracking over time
    @Published var peakHistory: [[ResonantPeak]] = []
    
    /// Saved measurements
    @Published var savedMeasurements: [TapToneMeasurement] = []
    
    /// Average magnitude in current frame (for tap detection)
    @Published var averageMagnitude: Float = -100
    
    /// Current tap detection level (recent average + threshold)
    @Published var tapDetectionLevel: Float = -100
    
    /// Indicates if a tap was just detected
    @Published var tapDetected: Bool = false
    
    /// Detection state (disabled by default until user starts a tap sequence)
    @Published var isDetecting: Bool = false
    
    /// Current tap count in multi-tap sequence
    @Published var currentTapCount: Int = 0
    
    /// Progress of multi-tap sequence (0.0 to 1.0)
    @Published var tapProgress: Float = 0.0
    
    /// Status message for user feedback
    @Published var statusMessage: String = "Press Start to begin"
    
    /// Frozen spectrum data (captured when sequence completes)
    @Published var frozenFrequencies: [Float] = []
    @Published var frozenMagnitudes: [Float] = []
    
    /// Whether to display frozen spectrum instead of live data
    @Published var isSpectrumFrozen: Bool = false
    
    /// Custom offsets for peak annotations (keyed by peak ID) to prevent overlap
    @Published var peakAnnotationOffsets: [UUID: CGPoint] = [:]
    
    // MARK: - Private State
    
    private var cancellables = Set<AnyCancellable>()
    private var peakMagnitudeHistory: [(time: Date, magnitude: Float)] = []
    private var lastTapTime: Date?
    private let tapCooldown: TimeInterval = 0.5  // Minimum time between taps
    
    /// Time when the analyzer started (for warm-up period)
    private var analyzerStartTime: Date?
    
    /// Warm-up period in seconds - ignore taps during this time to prevent false detections
    private let warmupPeriod: TimeInterval = 0.5
    
    /// Storage for captured tap spectra (for averaging)
    private var capturedTaps: [(magnitudes: [Float], frequencies: [Float], captureTime: Date)] = []
    
    /// Storage for peaks from each tap (before averaging)
    private var tapsForAveraging: [[ResonantPeak]] = []
    
    /// Timer for capture window
    private var captureTimer: Timer?
    
    /// Track if signal is currently above threshold (for rising edge detection)
    private var isAboveThreshold: Bool = false
    
    // MARK: - Initialization
    
    init(fftAnalyzer: RealtimeFFTAnalyzer) {
        self.fftAnalyzer = fftAnalyzer
        setupSubscriptions()
    }
    
    // MARK: - Setup
    
    private func setupSubscriptions() {
        // Subscribe to FFT updates
        fftAnalyzer.$magnitudes
            .combineLatest(fftAnalyzer.$frequencies, fftAnalyzer.$peakMagnitude)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] magnitudes, frequencies, peakMag in
                self?.analyzeMagnitudes(magnitudes, frequencies: frequencies, peakMagnitude: peakMag)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Analysis Methods
    
    /// Main analysis pipeline
    private func analyzeMagnitudes(_ magnitudes: [Float], frequencies: [Float], peakMagnitude: Float) {
        // Don't analyze anything if the FFT analyzer isn't actually running
        guard fftAnalyzer.isRunning else {
            // Reset tap detection state to prevent false positives before start
            tapDetected = false
            return
        }
        
        // Calculate average magnitude for tap detection
        let validMags = magnitudes.filter { $0 > -100 }
        averageMagnitude = validMags.isEmpty ? -100 : validMags.reduce(0, +) / Float(validMags.count)
        
        // Only detect taps if detection is enabled
        if isDetecting {
            detectTap(peakMagnitude: peakMagnitude, magnitudes: magnitudes, frequencies: frequencies)
        }
        
        // Only analyze peaks if detection is enabled OR we're in capture window
        if isDetecting || captureTimer != nil {
            // Find peaks in spectrum
            let peaks = findPeaks(magnitudes: magnitudes, frequencies: frequencies)
            currentPeaks = peaks
            
            // Classify modes
            identifiedModes = peaks.map { peak in
                (peak: peak, mode: GuitarMode.classify(frequency: peak.frequency))
            }
            
            // Add to history
            if !peaks.isEmpty {
                peakHistory.append(peaks)
                if peakHistory.count > 100 {
                    peakHistory.removeFirst()
                }
            }
        }
        
        // Track peak magnitude for decay analysis
        trackDecay(peakMagnitude: peakMagnitude)
    }
    
    /// Find all significant peaks in the spectrum
    func findPeaks(magnitudes: [Float], frequencies: [Float]) -> [ResonantPeak] {
        guard magnitudes.count == frequencies.count else { return [] }
        
        var peaks: [ResonantPeak] = []
        let windowSize = 5  // Look at ±5 bins around each point
        
        // Find frequency range indices
        let startIdx = frequencies.firstIndex(where: { $0 >= minFrequency }) ?? 0
        let endIdx = frequencies.firstIndex(where: { $0 > maxFrequency }) ?? frequencies.count - 1
        
        // Define all modes to search for
        let modesToSearch: [GuitarMode] = [.helmholtz, .crossGrain, .longGrain, .monopole, .dipole, .ringMode, .upperModes]
        
        // For each mode, search its frequency range for peaks
        for mode in modesToSearch {
            let modeRange = mode.idealRange
            
            // Find indices for this mode's range
            let modeStartIdx = frequencies.firstIndex(where: { $0 >= modeRange.lowerBound }) ?? startIdx
            let modeEndIdx = frequencies.firstIndex(where: { $0 > modeRange.upperBound }) ?? endIdx
            
            // Skip if range is invalid
            guard modeStartIdx < modeEndIdx, modeStartIdx >= startIdx, modeEndIdx <= endIdx else { continue }
            
            // Scan for local maxima within this mode's range
            for i in max(modeStartIdx, startIdx + windowSize)..<min(modeEndIdx, endIdx - windowSize) {
                let magnitude = magnitudes[i]
                
                // Skip if below threshold
                guard magnitude > peakThreshold else { continue }
                
                // Check if local maximum
                var isLocalMax = true
                for offset in -windowSize...windowSize where offset != 0 {
                    if magnitudes[i + offset] >= magnitude {
                        isLocalMax = false
                        break
                    }
                }
                
                guard isLocalMax else { continue }
                
                // Calculate Q factor (sharpness) and bandwidth
                let (quality, bandwidth) = calculateQFactor(magnitudes: magnitudes, peakIndex: i, peakMagnitude: magnitude)
                
                let peak = ResonantPeak(
                    frequency: frequencies[i],
                    magnitude: magnitude,
                    quality: quality,
                    bandwidth: bandwidth
                )
                peaks.append(peak)
            }
        }
        
        // Remove duplicate peaks (in case mode ranges overlap)
        peaks = removeDuplicatePeaks(peaks)
        
        // Sort by magnitude but keep all peaks found in mode ranges
        return peaks.sorted(by: { $0.magnitude > $1.magnitude })
    }
    
    /// Remove duplicate peaks that are too close in frequency
    private func removeDuplicatePeaks(_ peaks: [ResonantPeak]) -> [ResonantPeak] {
        var uniquePeaks: [ResonantPeak] = []
        let frequencyTolerance: Float = 2.0  // Hz - peaks closer than this are considered duplicates
        
        for peak in peaks {
            // Check if we already have a peak at this frequency
            let isDuplicate = uniquePeaks.contains { existingPeak in
                abs(existingPeak.frequency - peak.frequency) < frequencyTolerance
            }
            
            if !isDuplicate {
                uniquePeaks.append(peak)
            } else {
                // If duplicate, keep the one with higher magnitude
                if let existingIndex = uniquePeaks.firstIndex(where: { abs($0.frequency - peak.frequency) < frequencyTolerance }) {
                    if peak.magnitude > uniquePeaks[existingIndex].magnitude {
                        uniquePeaks[existingIndex] = peak
                    }
                }
            }
        }
        
        return uniquePeaks
    }
    
    /// Calculate Q factor and bandwidth for a peak
    private func calculateQFactor(magnitudes: [Float], peakIndex: Int, peakMagnitude: Float) -> (quality: Float, bandwidth: Float) {
        let threshold = peakMagnitude - 3.0  // -3dB points
        
        // Find lower -3dB point
        var lowerIdx = peakIndex
        while lowerIdx > 0 && magnitudes[lowerIdx] > threshold {
            lowerIdx -= 1
        }
        
        // Find upper -3dB point
        var upperIdx = peakIndex
        while upperIdx < magnitudes.count - 1 && magnitudes[upperIdx] > threshold {
            upperIdx += 1
        }
        
        let lowerFreq = fftAnalyzer.frequencies[lowerIdx]
        let upperFreq = fftAnalyzer.frequencies[upperIdx]
        let centerFreq = fftAnalyzer.frequencies[peakIndex]
        
        let bandwidth = upperFreq - lowerFreq
        let quality = bandwidth > 0 ? centerFreq / bandwidth : 0
        
        return (quality: quality, bandwidth: bandwidth)
    }
    
    /// Detect tap events using rising edge detection with hysteresis
    private func detectTap(peakMagnitude: Float, magnitudes: [Float], frequencies: [Float]) {
        let now = Date()
        
        // Check if we're still in warm-up period (prevents false detections on startup)
        if let startTime = analyzerStartTime, now.timeIntervalSince(startTime) < warmupPeriod {
            tapDetected = false
            statusMessage = "Initializing... (\(String(format: "%.1f", warmupPeriod - now.timeIntervalSince(startTime)))s)"
            return
        }
        
        // Check cooldown
        if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) < tapCooldown {
            tapDetected = false
            return
        }
        
        // Update status message if ready and waiting for tap
        if currentTapCount == 0 && statusMessage.contains("Initializing") {
            statusMessage = numberOfTaps == 1 ? "Tap the guitar..." : "Tap the guitar \(numberOfTaps) times..."
        }
        
        // Update the detection level for UI display (shows rising threshold)
        tapDetectionLevel = tapDetectionThreshold
        
        // Hysteresis: Use different thresholds for rising vs falling edges
        let risingThreshold = tapDetectionThreshold
        let fallingThreshold = tapDetectionThreshold - hysteresisMargin
        
        // Determine if currently above threshold (with hysteresis)
        let currentlyAboveThreshold = isAboveThreshold ?
            (peakMagnitude > fallingThreshold) :  // When above: use lower threshold to stay "above"
            (peakMagnitude > risingThreshold)     // When below: use higher threshold to go "above"
        
        // Debug: Log state transitions (uncomment for troubleshooting)
        // if currentlyAboveThreshold != isAboveThreshold {
        //     print("🔄 Threshold crossing: \(isAboveThreshold ? "ABOVE→BELOW" : "BELOW→ABOVE") at \(peakMagnitude) dB (rising: \(risingThreshold), falling: \(fallingThreshold))")
        // }
        
        // Detect tap only when crossing from below to above threshold
        if currentlyAboveThreshold && !isAboveThreshold {
            // Rising edge detected! 📈
            tapDetected = true
            lastTapTime = now
            print("🎯 Tap detected! Peak: \(peakMagnitude) dB (threshold: \(risingThreshold) dB, hysteresis: \(hysteresisMargin) dB) [Rising Edge]")
            
            // Handle tap in multi-tap sequence
            handleTapDetection(magnitudes: magnitudes, frequencies: frequencies, time: now)
        } else {
            tapDetected = false
        }
        
        // Update state for next frame
        isAboveThreshold = currentlyAboveThreshold
    }
    
    /// Handle a detected tap in the multi-tap sequence
    private func handleTapDetection(magnitudes: [Float], frequencies: [Float], time: Date) {
        // Stop detection temporarily
        isDetecting = false
        
        // Store spectrum data immediately
        capturedTaps.append((magnitudes: magnitudes, frequencies: frequencies, captureTime: time))
        
        // Increment tap count
        currentTapCount += 1
        tapProgress = Float(currentTapCount) / Float(numberOfTaps)
        
        print("📊 Captured tap \(currentTapCount) of \(numberOfTaps)")
        
        // Start capture window timer to collect spectrum during ring-out
        captureTimer?.invalidate()
        captureTimer = Timer.scheduledTimer(withTimeInterval: captureWindow, repeats: false) { [weak self] _ in
            self?.finishCapture()
        }
        
        // Update status
        if currentTapCount < numberOfTaps {
            statusMessage = "Tap \(currentTapCount)/\(numberOfTaps) captured. Tap again..."
        } else {
            statusMessage = "All taps captured. Processing..."
        }
        
        // If we've collected all taps, process them
        if currentTapCount >= numberOfTaps {
            DispatchQueue.main.asyncAfter(deadline: .now() + captureWindow) { [weak self] in
                self?.processMultipleTaps()
            }
        } else {
            // Re-enable detection after cooldown for next tap
            DispatchQueue.main.asyncAfter(deadline: .now() + tapCooldown) { [weak self] in
                self?.isDetecting = true
                self?.tapDetected = false
            }
        }
    }
    
    /// Finish capturing spectrum after capture window
    private func finishCapture() {
        captureTimer?.invalidate()
        captureTimer = nil
    }
    
    /// Process multiple captured taps and average the results
    private func processMultipleTaps() {
        guard !capturedTaps.isEmpty else { return }
        
        print("🔬 Processing \(capturedTaps.count) taps for averaging...")
        
        // Extract peaks from each tap
        tapsForAveraging = capturedTaps.map { tap in
            findPeaks(magnitudes: tap.magnitudes, frequencies: tap.frequencies)
        }
        
        // Average the peaks
        let averagedPeaks = averagePeaks(from: tapsForAveraging)
        
        // Update current peaks with averaged results
        currentPeaks = averagedPeaks
        
        // Classify modes based on averaged peaks
        identifiedModes = averagedPeaks.map { peak in
            (peak: peak, mode: GuitarMode.classify(frequency: peak.frequency))
        }
        
        // Average the raw FFT spectrum across all taps
        let (avgMagnitudes, avgFrequencies) = averageSpectra(from: capturedTaps)
        
        // Freeze the averaged spectrum for display
        frozenFrequencies = avgFrequencies
        frozenMagnitudes = avgMagnitudes
        isSpectrumFrozen = true
        print("📸 Spectrum frozen with averaged data from \(capturedTaps.count) taps")
        
        // Update status
        statusMessage = "Analysis complete! \(averagedPeaks.count) peaks identified (averaged from \(capturedTaps.count) taps)."
        tapProgress = 1.0
        
        print("✅ Averaged \(tapsForAveraging.count) taps into \(averagedPeaks.count) peaks")
    }
    
    /// Average peaks across multiple taps
    private func averagePeaks(from tapPeaks: [[ResonantPeak]]) -> [ResonantPeak] {
        guard !tapPeaks.isEmpty else { return [] }
        
        // If only one tap, return its peaks
        if tapPeaks.count == 1 {
            return tapPeaks[0]
        }
        
        // Collect all unique peak frequencies (with tolerance)
        var peakGroups: [[ResonantPeak]] = []
        let frequencyTolerance: Float = 5.0  // Hz
        
        // Group similar peaks across taps
        for tapIndex in 0..<tapPeaks.count {
            for peak in tapPeaks[tapIndex] {
                // Try to find existing group
                var foundGroup = false
                for groupIndex in 0..<peakGroups.count {
                    let groupAvgFreq = peakGroups[groupIndex].map({ $0.frequency }).reduce(0, +) / Float(peakGroups[groupIndex].count)
                    if abs(peak.frequency - groupAvgFreq) < frequencyTolerance {
                        peakGroups[groupIndex].append(peak)
                        foundGroup = true
                        break
                    }
                }
                
                // Create new group if no match found
                if !foundGroup {
                    peakGroups.append([peak])
                }
            }
        }
        
        // Average each group
        var averagedPeaks: [ResonantPeak] = []
        for group in peakGroups {
            let avgFreq = group.map({ $0.frequency }).reduce(0, +) / Float(group.count)
            let avgMag = group.map({ $0.magnitude }).reduce(0, +) / Float(group.count)
            let avgQuality = group.map({ $0.quality }).reduce(0, +) / Float(group.count)
            let avgBandwidth = group.map({ $0.bandwidth }).reduce(0, +) / Float(group.count)
            
            let averagedPeak = ResonantPeak(
                frequency: avgFreq,
                magnitude: avgMag,
                quality: avgQuality,
                bandwidth: avgBandwidth
            )
            averagedPeaks.append(averagedPeak)
        }
        
        // Sort by magnitude and return top peaks
        return Array(averagedPeaks.sorted(by: { $0.magnitude > $1.magnitude }).prefix(maxPeaks))
    }
    
    /// Average raw FFT spectra across multiple taps
    private func averageSpectra(from taps: [(magnitudes: [Float], frequencies: [Float], captureTime: Date)]) -> (magnitudes: [Float], frequencies: [Float]) {
        guard !taps.isEmpty else { return ([], []) }
        
        // If only one tap, return its spectrum
        if taps.count == 1 {
            return (taps[0].magnitudes, taps[0].frequencies)
        }
        
        // Ensure all spectra have the same length
        let spectrumLength = taps[0].magnitudes.count
        guard taps.allSatisfy({ $0.magnitudes.count == spectrumLength }) else {
            print("⚠️ Warning: Spectrum lengths don't match, using first tap only")
            return (taps[0].magnitudes, taps[0].frequencies)
        }
        
        // Average magnitudes bin-by-bin
        var averagedMagnitudes = [Float](repeating: 0, count: spectrumLength)
        
        // Convert dB to linear (power), average, then convert back to dB
        for binIndex in 0..<spectrumLength {
            var linearSum: Float = 0
            
            for tap in taps {
                let magnitudeDB = tap.magnitudes[binIndex]
                // Convert dB to linear power: power = 10^(dB/10)
                let linearPower = pow(10.0, magnitudeDB / 10.0)
                linearSum += linearPower
            }
            
            // Average and convert back to dB
            let averageLinear = linearSum / Float(taps.count)
            averagedMagnitudes[binIndex] = 10.0 * log10(averageLinear)
        }
        
        // Frequencies should be identical across all taps, use first one
        let frequencies = taps[0].frequencies
        
        print("📊 Averaged \(taps.count) spectra: \(spectrumLength) bins each")
        
        return (magnitudes: averagedMagnitudes, frequencies: frequencies)
    }
    
    /// Track magnitude over time for decay analysis
    private func trackDecay(peakMagnitude: Float) {
        let now = Date()
        peakMagnitudeHistory.append((time: now, magnitude: peakMagnitude))
        
        // Keep only recent history (5 seconds)
        peakMagnitudeHistory = peakMagnitudeHistory.filter { now.timeIntervalSince($0.time) < 5.0 }
        
        // Calculate decay time if we have a tap
        if let tapTime = lastTapTime, peakMagnitudeHistory.count > 10 {
            currentDecayTime = measureDecayTime(tapTime: tapTime)
        }
    }
    
    /// Measure how long it takes for magnitude to decay
    private func measureDecayTime(tapTime: Date) -> Float? {
        // Find peak magnitude after tap
        let postTapHistory = peakMagnitudeHistory.filter { $0.time >= tapTime }
        guard let peakEntry = postTapHistory.max(by: { $0.magnitude < $1.magnitude }) else { return nil }
        
        let peakMag = peakEntry.magnitude
        let decayTarget = peakMag - decayThreshold
        
        // Find when it crossed the threshold
        if let decayEntry = postTapHistory.first(where: { $0.magnitude < decayTarget && $0.time > peakEntry.time }) {
            return Float(decayEntry.time.timeIntervalSince(peakEntry.time))
        }
        
        return nil
    }
    
    // MARK: - Measurement Management
    
    /// Save current measurement with optional metadata
    func saveMeasurement(tapLocation: String? = nil, notes: String? = nil, includeSpectrum: Bool = true) {
        let spectrum = includeSpectrum ? fftAnalyzer.magnitudes : nil
        
        let measurement = TapToneMeasurement(
            peaks: currentPeaks,
            decayTime: currentDecayTime,
            tapLocation: tapLocation,
            notes: notes,
            spectrum: spectrum
        )
        
        savedMeasurements.append(measurement)
        print("💾 Saved measurement with \(currentPeaks.count) peaks")
    }
    
    /// Delete a saved measurement
    func deleteMeasurement(_ measurement: TapToneMeasurement) {
        savedMeasurements.removeAll(where: { $0.id == measurement.id })
    }
    
    /// Export measurements as JSON
    func exportMeasurements() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        guard let data = try? encoder.encode(savedMeasurements),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return json
    }
    
    /// Import measurements from JSON
    func importMeasurements(json: String) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let data = json.data(using: .utf8),
              let measurements = try? decoder.decode([TapToneMeasurement].self, from: data) else {
            return false
        }
        
        savedMeasurements.append(contentsOf: measurements)
        return true
    }
    
    // MARK: - Analysis Helpers
    
    /// Get peaks within a frequency range
    func getPeaks(in range: ClosedRange<Float>) -> [ResonantPeak] {
        currentPeaks.filter { range.contains($0.frequency) }
    }
    
    /// Get the strongest peak for a specific mode
    func getPeak(for mode: GuitarMode) -> ResonantPeak? {
        identifiedModes
            .filter { $0.mode == mode }
            .max(by: { $0.peak.magnitude < $1.peak.magnitude })?
            .peak
    }
    
    /// Calculate tap tone ratio (ideal is ~2.0)
    func calculateTapToneRatio() -> Float? {
        guard let crossGrain = getPeak(for: .crossGrain),
              let longGrain = getPeak(for: .longGrain) else {
            return nil
        }
        return longGrain.frequency / crossGrain.frequency
    }
    
    /// Compare current measurement to a saved one
    func compareTo(_ measurement: TapToneMeasurement) -> [(current: ResonantPeak?, saved: ResonantPeak, difference: Float)] {
        measurement.peaks.map { savedPeak in
            let currentPeak = currentPeaks.min(by: { abs($0.frequency - savedPeak.frequency) < abs($1.frequency - savedPeak.frequency) })
            let difference = currentPeak.map { $0.frequency - savedPeak.frequency } ?? 0
            return (current: currentPeak, saved: savedPeak, difference: difference)
        }
    }
    
    // MARK: - Annotation Management
    
    /// Update the offset for a peak annotation
    func updateAnnotationOffset(for peakID: UUID, offset: CGPoint) {
        DispatchQueue.main.async { [weak self] in
            self?.peakAnnotationOffsets[peakID] = offset
        }
    }
    
    /// Get the offset for a peak annotation
    func getAnnotationOffset(for peakID: UUID) -> CGPoint {
        peakAnnotationOffsets[peakID] ?? .zero
    }
    
    /// Reset annotation offset for a peak
    func resetAnnotationOffset(for peakID: UUID) {
        DispatchQueue.main.async { [weak self] in
            self?.peakAnnotationOffsets.removeValue(forKey: peakID)
        }
    }
    
    /// Reset all annotation offsets
    func resetAllAnnotationOffsets() {
        DispatchQueue.main.async { [weak self] in
            self?.peakAnnotationOffsets = [:]
        }
    }
    
    // MARK: - Control
    
    /// Start analyzing
    func start() throws {
        try fftAnalyzer.start()
        analyzerStartTime = Date()  // Record start time for warm-up period
        print("🎬 Analyzer started - warm-up period: \(warmupPeriod)s")
        
        // Automatically start tap detection when analyzer starts
        startTapSequence()
    }
    
    /// Stop analyzing
    func stop() {
        fftAnalyzer.stop()
    }
    
    /// Reset analysis state
    func reset() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.currentPeaks = []
            self.identifiedModes = []
            self.currentDecayTime = nil
            self.peakHistory = []
            self.peakMagnitudeHistory = []
            self.lastTapTime = nil
            self.tapDetected = false
            self.isDetecting = false  // Disable detection until new sequence starts
            self.currentTapCount = 0
            self.tapProgress = 0.0
            self.capturedTaps = []
            self.tapsForAveraging = []
            self.captureTimer?.invalidate()
            self.captureTimer = nil
            self.isAboveThreshold = false  // Reset edge detection state
            self.analyzerStartTime = Date()  // Reset warm-up timer
            
            // Unfreeze spectrum
            self.isSpectrumFrozen = false
            self.frozenFrequencies = []
            self.frozenMagnitudes = []
            
            // Clear annotation offsets
            self.peakAnnotationOffsets = [:]
            
            self.statusMessage = "Press 'New Tap' to begin"
        }
    }
    
    /// Start a new tap detection sequence
    func startTapSequence() {
        print("🎬 Starting tap sequence: \(numberOfTaps) tap(s)")
        
        // Ensure all @Published updates happen on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Clear previous data
            self.capturedTaps = []
            self.tapsForAveraging = []
            self.currentTapCount = 0
            self.tapProgress = 0.0
            self.tapDetected = false
            self.isAboveThreshold = false  // Reset edge detection state
            
            // Reset warm-up timer to prevent immediate false detection
            self.analyzerStartTime = Date()
            
            // Unfreeze spectrum
            self.isSpectrumFrozen = false
            self.frozenFrequencies = []
            self.frozenMagnitudes = []
            
            // Enable detection
            self.isDetecting = true
            self.statusMessage = self.numberOfTaps == 1 ? "Tap the guitar..." : "Tap the guitar \(self.numberOfTaps) times..."
            
            // Clear current results
            self.currentPeaks = []
            self.identifiedModes = []
        }
    }
    
    /// Cancel current tap sequence and restart detection
    func cancelTapSequence() {
        print("❌ Tap sequence cancelled")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.capturedTaps = []
            self.tapsForAveraging = []
            self.currentTapCount = 0
            self.tapProgress = 0.0
            self.tapDetected = false
            self.isDetecting = true
            self.isAboveThreshold = false  // Reset edge detection state
            self.captureTimer?.invalidate()
            self.captureTimer = nil
            self.statusMessage = "Cancelled. Ready for new sequence."
        }
    }
    
    /// Resume detection after analysis
    func resumeDetection() {
        print("▶️ Resuming tap detection")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.isDetecting = true
            self.currentTapCount = 0
            self.tapProgress = 0.0
            self.capturedTaps = []
            self.tapsForAveraging = []
            self.tapDetected = false
            self.isAboveThreshold = false  // Reset edge detection state
            self.analyzerStartTime = Date()  // Reset warm-up timer to prevent false detection
            self.captureTimer?.invalidate()
            self.captureTimer = nil
            
            // Unfreeze spectrum
            self.isSpectrumFrozen = false
            self.frozenFrequencies = []
            self.frozenMagnitudes = []
            
            self.statusMessage = self.numberOfTaps == 1 ? "Tap the guitar..." : "Tap the guitar \(self.numberOfTaps) times..."
        }
    }
}
