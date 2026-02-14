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
    
    // Pitch information
    let pitchNote: String?      // e.g., "A4", "C#3"
    let pitchCents: Double?     // Cents offset from nearest pitch
    let pitchFrequency: Double? // Frequency of nearest pitch
    
    init(frequency: Float, magnitude: Float, quality: Float = 0, bandwidth: Float = 0, pitchNote: String? = nil, pitchCents: Double? = nil, pitchFrequency: Double? = nil) {
        self.id = UUID()
        self.frequency = frequency
        self.magnitude = magnitude
        self.quality = quality
        self.bandwidth = bandwidth
        self.timestamp = Date()
        self.pitchNote = pitchNote
        self.pitchCents = pitchCents
        self.pitchFrequency = pitchFrequency
    }
    
    /// Computed property for formatted pitch information
    var formattedPitch: String {
        guard let note = pitchNote, let cents = pitchCents else {
            return "N/A"
        }
        let sign = cents >= 0 ? "+" : ""
        return "\(note) (\(sign)\(String(format: "%.0f", cents)) ¢)"
    }
}

/// Guitar resonance mode classification based on frequency ranges
/// Uses luthier-friendly terminology for completed instruments
enum GuitarMode: String, Codable {
    case air = "Air (Helmholtz)"      // Combined Helmholtz + coupled air/top mode
    case top = "Top"                   // Main top plate resonance (formerly long-grain)
    case back = "Back"                 // Back plate resonance (formerly monopole)
    case dipole = "Dipole"             // T(1,2) dipole mode
    case ringMode = "Ring Mode"        // Higher structural mode
    case upperModes = "Upper Modes"    // Higher frequency modes
    case unknown = "Unknown"
    
    // Legacy case mappings for backward compatibility with saved data
    case helmholtz = "Helmholtz (Air)"
    case crossGrain = "Cross-Grain"
    case longGrain = "Long-Grain"
    case monopole = "Monopole"
    
    /// Classify a frequency into a guitar mode using the current guitar type setting
    static func classify(frequency: Float) -> GuitarMode {
        return classify(frequency: frequency, guitarType: SpectrumDisplaySettings.guitarType)
    }
    
    /// Classify a frequency into a guitar mode for a specific guitar type
    static func classify(frequency: Float, guitarType: GuitarType) -> GuitarMode {
        let ranges = guitarType.modeRanges
        
        switch frequency {
        case ranges.air:
            return .air
        case ranges.top:
            return .top
        case ranges.back:
            return .back
        case ranges.dipole:
            return .dipole
        case ranges.ringMode:
            return .ringMode
        case ranges.upperModes:
            return .upperModes
        default:
            return .unknown
        }
    }
    
    /// Ideal frequency range for this mode (uses current guitar type setting)
    var idealRange: ClosedRange<Float> {
        return idealRange(for: SpectrumDisplaySettings.guitarType)
    }
    
    /// Ideal frequency range for this mode for a specific guitar type
    func idealRange(for guitarType: GuitarType) -> ClosedRange<Float> {
        let ranges = guitarType.idealRanges
        switch self.normalized {
        case .air: return ranges.air
        case .top: return ranges.top
        case .back: return ranges.back
        case .dipole: return ranges.dipole
        case .ringMode: return ranges.ringMode
        case .upperModes: return ranges.upperModes
        case .unknown: return 0...20000
        default: return 0...20000
        }
    }
    
    /// Display name for UI (handles legacy modes)
    var displayName: String {
        switch self {
        case .air, .helmholtz, .crossGrain: return "Air (Helmholtz)"
        case .top, .longGrain: return "Top"
        case .back, .monopole: return "Back"
        case .dipole: return "Dipole"
        case .ringMode: return "Ring Mode"
        case .upperModes: return "Upper Modes"
        case .unknown: return "Unknown"
        }
    }
    
    /// Normalized mode for comparisons (maps legacy modes to new ones)
    var normalized: GuitarMode {
        switch self {
        case .helmholtz, .crossGrain: return .air
        case .longGrain: return .top
        case .monopole: return .back
        default: return self
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
    let spectrumSnapshot: SpectrumSnapshot?  // Full spectrum data for recreation
    let chartImageFilename: String?   // Filename of associated PNG image (e.g., "measurement-uuid.png")
    let peakAnnotationOffsets: [UUID: CGPoint]?  // Custom annotation positions
    
    // Analysis settings (added for export/import)
    let tapDetectionThreshold: Float?  // dB
    let hysteresisMargin: Float?       // dB
    let numberOfTaps: Int?             // Number of taps averaged
    
    // Transient property - not saved in JSON, used for runtime image handling
    var chartImageData: Data?
    
    // Custom coding to exclude transient imageData from JSON
    enum CodingKeys: String, CodingKey {
        case id, timestamp, peaks, decayTime, tapLocation, notes
        case spectrumSnapshot, chartImageFilename, peakAnnotationOffsets
        case tapDetectionThreshold, hysteresisMargin, numberOfTaps
    }
    
    init(peaks: [ResonantPeak], 
         decayTime: Float? = nil, 
         tapLocation: String? = nil, 
         notes: String? = nil, 
         spectrum: SpectrumSnapshot? = nil,
         chartImageFilename: String? = nil,
         chartImageData: Data? = nil,
         annotationOffsets: [UUID: CGPoint]? = nil,
         tapDetectionThreshold: Float? = nil,
         hysteresisMargin: Float? = nil,
         numberOfTaps: Int? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.peaks = peaks
        self.decayTime = decayTime
        self.tapLocation = tapLocation
        self.notes = notes
        self.spectrumSnapshot = spectrum
        self.chartImageFilename = chartImageFilename
        self.chartImageData = chartImageData
        self.peakAnnotationOffsets = annotationOffsets
        self.tapDetectionThreshold = tapDetectionThreshold
        self.hysteresisMargin = hysteresisMargin
        self.numberOfTaps = numberOfTaps
    }
    
    /// Get tap tone ratio (Top / Air)
    /// This ratio indicates the relationship between the main top resonance and the air cavity resonance
    var tapToneRatio: Float? {
        guard let airPeak = peaks.first(where: { GuitarMode.classify(frequency: $0.frequency).normalized == .air }),
              let topPeak = peaks.first(where: { GuitarMode.classify(frequency: $0.frequency).normalized == .top }) else {
            return nil
        }
        return topPeak.frequency / airPeak.frequency
    }
    
    /// Generate base filename (without extension) for this measurement
    var baseFilename: String {
        let locationPart = tapLocation?.replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .lowercased() ?? "measurement"
        let timestampPart = Int(timestamp.timeIntervalSince1970)
        return "\(locationPart)-\(timestampPart)"
    }
}

/// Complete spectrum snapshot with all data needed to recreate the plot
struct SpectrumSnapshot: Codable {
    let frequencies: [Float]
    let magnitudes: [Float]
    let minFreq: Float
    let maxFreq: Float
    let minDB: Float
    let maxDB: Float
    let isLogarithmic: Bool
    
    init(frequencies: [Float], magnitudes: [Float], minFreq: Float, maxFreq: Float, minDB: Float, maxDB: Float, isLogarithmic: Bool) {
        self.frequencies = frequencies
        self.magnitudes = magnitudes
        self.minFreq = minFreq
        self.maxFreq = maxFreq
        self.minDB = minDB
        self.maxDB = maxDB
        self.isLogarithmic = isLogarithmic
    }
}

// MARK: - Tap Tone Analyzer

/// Advanced tap tone analysis for guitar lutherie
final class TapToneAnalyzer: ObservableObject {
    
    // MARK: - Dependencies
    
    /// The underlying FFT analyzer
    private let fftAnalyzer: RealtimeFFTAnalyzer
    
    /// Pitch calculator for musical note analysis
    private let pitchCalculator = Pitch(a4: 440.0)
    
    // MARK: - Configuration
    
    /// Minimum magnitude threshold for peak detection (dB)
    @Published var peakThreshold: Float = SpectrumDisplaySettings.defaultPeakThreshold
    
    /// Minimum frequency for analysis (Hz)
    @Published var minFrequency: Float = SpectrumDisplaySettings.analysisMinFrequency
    
    /// Maximum frequency for analysis (Hz)
    @Published var maxFrequency: Float = SpectrumDisplaySettings.analysisMaxFrequency
    
    /// Number of peaks to track
    @Published var maxPeaks: Int = 10
    
    /// Decay threshold for ring-out measurement (dB below peak)
    /// Default is 15 dB which works well with typical room noise floors
    @Published var decayThreshold: Float = 15
    
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
    private var tapPeakLevel: Float = -100  // The input level at tap detection time (for decay reference)
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
    
    /// Timer for decay tracking window (continues after tap detection)
    private var decayTrackingTimer: Timer?
    
    /// Whether we're currently tracking decay after a tap
    private var isTrackingDecay: Bool = false
    
    // MARK: - Initialization
    
    init(fftAnalyzer: RealtimeFFTAnalyzer) {
        self.fftAnalyzer = fftAnalyzer
        setupSubscriptions()
    }
    
    // MARK: - Setup
    
    private func setupSubscriptions() {
        // Subscribe to FFT updates (slow - only updates per FFT frame)
        fftAnalyzer.$magnitudes
            .combineLatest(fftAnalyzer.$frequencies, fftAnalyzer.$peakMagnitude)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] magnitudes, frequencies, peakMag in
                self?.analyzeMagnitudes(magnitudes, frequencies: frequencies, peakMagnitude: peakMag)
            }
            .store(in: &cancellables)
        
        // Subscribe to fast input level updates for decay tracking (~10Hz vs ~1Hz for FFT)
        fftAnalyzer.$inputLevelDB
            .receive(on: DispatchQueue.main)
            .sink { [weak self] levelDB in
                self?.trackDecayFast(inputLevel: levelDB)
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
            
        }
        
        // Always track peak magnitude for decay analysis (even when not detecting taps)
        // This ensures we can measure ring-out time after a tap is detected
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
        
        // Define all known modes to search for (excluding unknown)
        let knownModes: [GuitarMode] = [.helmholtz, .crossGrain, .longGrain, .monopole, .dipole, .ringMode, .upperModes]
        
        // Step 1: Search known mode ranges for peaks
        for mode in knownModes {
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
                
                // Calculate pitch information
                let freq = Double(frequencies[i])
                let pitchNote = pitchCalculator.note(frequency: freq)
                let pitchCents = pitchCalculator.cents(frequency: freq)
                let pitchFreq = pitchCalculator.freq0(frequency: freq)
                
                let peak = ResonantPeak(
                    frequency: frequencies[i],
                    magnitude: magnitude,
                    quality: quality,
                    bandwidth: bandwidth,
                    pitchNote: pitchNote,
                    pitchCents: pitchCents,
                    pitchFrequency: pitchFreq
                )
                peaks.append(peak)
            }
        }
        
        // Step 2: Search entire spectrum for peaks outside known mode ranges (unknown peaks)
        for i in (startIdx + windowSize)..<(endIdx - windowSize) {
            let magnitude = magnitudes[i]
            let frequency = frequencies[i]
            
            // Skip if below threshold
            guard magnitude > peakThreshold else { continue }
            
            // Check if this frequency is already covered by a known mode
            let isInKnownMode = knownModes.contains { mode in
                mode.idealRange.contains(frequency)
            }
            
            // Only process if outside known mode ranges
            guard !isInKnownMode else { continue }
            
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
            
            // Calculate pitch information
            let freq = Double(frequencies[i])
            let pitchNote = pitchCalculator.note(frequency: freq)
            let pitchCents = pitchCalculator.cents(frequency: freq)
            let pitchFreq = pitchCalculator.freq0(frequency: freq)
            
            let peak = ResonantPeak(
                frequency: frequencies[i],
                magnitude: magnitude,
                quality: quality,
                bandwidth: bandwidth,
                pitchNote: pitchNote,
                pitchCents: pitchCents,
                pitchFrequency: pitchFreq
            )
            peaks.append(peak)
        }
        
        // Remove duplicate peaks (in case of overlap)
        peaks = removeDuplicatePeaks(peaks)
        
        // Sort by magnitude descending (strongest peaks first)
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
            
            // Capture the recent peak input level for decay tracking reference
            // Use recentPeakLevelDB which holds the max level over the last 0.5s
            // This ensures we get the actual tap peak even though FFT detection is delayed
            tapPeakLevel = fftAnalyzer.recentPeakLevelDB
            print("🎯 Tap detected! FFT peak: \(String(format: "%.1f", peakMagnitude)) dB, Input peak: \(String(format: "%.1f", tapPeakLevel)) dB (threshold: \(risingThreshold) dB) [Rising Edge]")
            
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
        
        // Start decay tracking for ring-out time measurement
        // This continues for 3 seconds after the tap to capture full decay
        startDecayTracking()
        
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
    
    /// Start decay tracking after a tap is detected
    /// This runs for 3 seconds to capture the ring-out time
    private func startDecayTracking() {
        // Clear previous decay history and seed with the tap peak level
        let now = Date()
        peakMagnitudeHistory = [(time: now, magnitude: tapPeakLevel)]
        currentDecayTime = nil
        
        // Enable decay tracking
        isTrackingDecay = true
        
        // Stop decay tracking after 3 seconds (enough time to measure ring-out)
        decayTrackingTimer?.invalidate()
        decayTrackingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.stopDecayTracking()
        }
        
        // Debug output removed - decay tracking now works silently
    }
    
    /// Stop decay tracking
    private func stopDecayTracking() {
        isTrackingDecay = false
        decayTrackingTimer?.invalidate()
        decayTrackingTimer = nil
        
        // Log result for debugging
        if let decayTime = currentDecayTime {
            print("✅ Ring-out measured: \(String(format: "%.2f", decayTime)) seconds")
        } else {
            // Debug why it failed
            if let tapTime = lastTapTime {
                let postTapHistory = peakMagnitudeHistory.filter { $0.time >= tapTime }
                if let peakEntry = postTapHistory.max(by: { $0.magnitude < $1.magnitude }) {
                    let currentLevel = postTapHistory.last?.magnitude ?? -100
                    let target = peakEntry.magnitude - decayThreshold
                    print("⚠️ Ring-out not measured: peak=\(String(format: "%.1f", peakEntry.magnitude)) dB, final=\(String(format: "%.1f", currentLevel)) dB, target=\(String(format: "%.1f", target)) dB, samples=\(postTapHistory.count)")
                } else {
                    print("⚠️ Ring-out not measured: no peak found in \(peakMagnitudeHistory.count) samples")
                }
            } else {
                print("⚠️ Ring-out not measured: no tap time recorded")
            }
        }
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
    
    /// Track magnitude over time for decay analysis (slow - called per FFT frame)
    /// NOTE: This is now deprecated in favor of trackDecayFast which uses inputLevelDB
    private func trackDecay(peakMagnitude: Float) {
        // This function is kept for compatibility but decay tracking now uses trackDecayFast
        // which is called ~10x per second instead of ~1x per second
    }
    
    /// Fast decay tracking using input level (~10Hz update rate)
    /// This provides much better time resolution than tracking per FFT frame
    private func trackDecayFast(inputLevel: Float) {
        let now = Date()
        
        // Only track decay history if we're actively tracking after a tap
        guard isTrackingDecay else { return }
        
        peakMagnitudeHistory.append((time: now, magnitude: inputLevel))
        
        // Keep only recent history (5 seconds)
        peakMagnitudeHistory = peakMagnitudeHistory.filter { now.timeIntervalSince($0.time) < 5.0 }
        
        // Calculate decay time if we have a tap and enough history
        if let tapTime = lastTapTime, peakMagnitudeHistory.count > 10 {
            currentDecayTime = measureDecayTime(tapTime: tapTime)
        }
    }
    
    /// Measure how long it takes for magnitude to decay
    private func measureDecayTime(tapTime: Date) -> Float? {
        // Find peak magnitude after tap
        let postTapHistory = peakMagnitudeHistory.filter { $0.time >= tapTime }
        
        guard let peakEntry = postTapHistory.max(by: { $0.magnitude < $1.magnitude }) else {
            return nil
        }
        
        let peakMag = peakEntry.magnitude
        let decayTarget = peakMag - decayThreshold
        
        // Find when it crossed the threshold
        if let decayEntry = postTapHistory.first(where: { $0.magnitude < decayTarget && $0.time > peakEntry.time }) {
            let decayTime = Float(decayEntry.time.timeIntervalSince(peakEntry.time))
            return decayTime
        }
        
        return nil
    }
    
    // MARK: - Measurement Management
    
    /// Save current measurement with optional metadata and chart image
    func saveMeasurement(
        tapLocation: String? = nil, 
        notes: String? = nil, 
        includeSpectrum: Bool = true,
        chartImageData: Data? = nil,
        spectrumSnapshot: SpectrumSnapshot? = nil,
        annotationOffsets: [UUID: CGPoint]? = nil
    ) {
        let snapshot: SpectrumSnapshot?
        if includeSpectrum {
            snapshot = spectrumSnapshot ?? SpectrumSnapshot(
                frequencies: isSpectrumFrozen ? frozenFrequencies : fftAnalyzer.frequencies,
                magnitudes: isSpectrumFrozen ? frozenMagnitudes : fftAnalyzer.magnitudes,
                minFreq: SpectrumDisplaySettings.minFrequency,
                maxFreq: SpectrumDisplaySettings.maxFrequency,
                minDB: SpectrumDisplaySettings.minMagnitude,
                maxDB: SpectrumDisplaySettings.maxMagnitude,
                isLogarithmic: false
            )
        } else {
            snapshot = nil
        }
        
        // Generate filename if image data is provided
        let imageFilename: String?
        if chartImageData != nil {
            let locationPart = tapLocation?.replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "/", with: "-")
                .lowercased() ?? "measurement"
            let timestampPart = Int(Date().timeIntervalSince1970)
            imageFilename = "\(locationPart)-\(timestampPart).png"
        } else {
            imageFilename = nil
        }
        
        let measurement = TapToneMeasurement(
            peaks: currentPeaks,
            decayTime: currentDecayTime,
            tapLocation: tapLocation,
            notes: notes,
            spectrum: snapshot,
            chartImageFilename: imageFilename,
            chartImageData: chartImageData,
            annotationOffsets: annotationOffsets ?? peakAnnotationOffsets,
            tapDetectionThreshold: tapDetectionThreshold,
            hysteresisMargin: hysteresisMargin,
            numberOfTaps: numberOfTaps
        )
        
        savedMeasurements.append(measurement)
        print("💾 Saved measurement with \(currentPeaks.count) peaks, image: \(imageFilename ?? "none")")
    }
    
    /// Delete a saved measurement
    func deleteMeasurement(_ measurement: TapToneMeasurement) {
        savedMeasurements.removeAll(where: { $0.id == measurement.id })
    }
    
    /// Import measurements from JSON data and optionally load associated images
    /// Returns the array of imported measurements
    func importMeasurements(from jsonData: Data, baseURL: URL? = nil) throws -> [TapToneMeasurement] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        var measurements = try decoder.decode([TapToneMeasurement].self, from: jsonData)
        
        // If baseURL is provided, try to load associated images
        if let baseURL = baseURL {
            for i in 0..<measurements.count {
                if let filename = measurements[i].chartImageFilename {
                    let imageURL = baseURL.deletingLastPathComponent().appendingPathComponent(filename)
                    if let imageData = try? Data(contentsOf: imageURL) {
                        measurements[i].chartImageData = imageData
                        print("📷 Loaded image: \(filename)")
                    }
                }
            }
        }
        
        // Add imported measurements
        savedMeasurements.append(contentsOf: measurements)
        
        print("📥 Imported \(measurements.count) measurements")
        return measurements
    }
    
    /// Loaded spectrum display ranges (used when restoring measurements)
    @Published var loadedMinFreq: Float?
    @Published var loadedMaxFreq: Float?
    @Published var loadedMinDB: Float?
    @Published var loadedMaxDB: Float?
    
    /// Loaded analysis settings (used when restoring measurements)
    @Published var loadedTapDetectionThreshold: Float?
    @Published var loadedHysteresisMargin: Float?
    @Published var loadedNumberOfTaps: Int?
    
    /// Load a measurement's data into the current view (recreate the plot)
    func loadMeasurement(_ measurement: TapToneMeasurement) {
        print("🔄 Loading measurement...")
        
        // Restore peaks
        currentPeaks = measurement.peaks
        
        // Restore decay time
        currentDecayTime = measurement.decayTime
        
        // Restore spectrum if available
        if let snapshot = measurement.spectrumSnapshot {
            frozenFrequencies = snapshot.frequencies
            frozenMagnitudes = snapshot.magnitudes
            isSpectrumFrozen = true
            
            // Restore display ranges - publish these to trigger view updates
            print("  📊 Publishing display ranges: \(snapshot.minFreq)-\(snapshot.maxFreq) Hz, \(snapshot.minDB)-\(snapshot.maxDB) dB")
            loadedMinFreq = snapshot.minFreq
            loadedMaxFreq = snapshot.maxFreq
            loadedMinDB = snapshot.minDB
            loadedMaxDB = snapshot.maxDB
        } else {
            print("  ⚠️ No spectrum snapshot in measurement")
            // Even without a snapshot, freeze the current spectrum to prevent changes
            isSpectrumFrozen = true
        }
        
        // Stop tap detection when loading a measurement (frozen state)
        isDetecting = false
        currentTapCount = 0
        tapProgress = 0.0
        statusMessage = "Loaded measurement (frozen). Press 'Resume' or 'New Tap' to continue."
        print("  🧊 Spectrum frozen, tap detection disabled")
        
        // Restore annotation offsets
        if let offsets = measurement.peakAnnotationOffsets {
            peakAnnotationOffsets = offsets
            print("  🏷️ Restored \(offsets.count) annotation offsets")
        }
        
        // Restore analysis settings if available - set both internal and published values
        if let threshold = measurement.tapDetectionThreshold {
            print("  🎯 Publishing tap threshold: \(threshold) dB")
            tapDetectionThreshold = threshold
            loadedTapDetectionThreshold = threshold
        } else {
            print("  ⚠️ No tap threshold in measurement")
        }
        
        if let hysteresis = measurement.hysteresisMargin {
            print("  🔄 Publishing hysteresis: \(hysteresis) dB")
            hysteresisMargin = hysteresis
            loadedHysteresisMargin = hysteresis
        } else {
            print("  ⚠️ No hysteresis in measurement")
        }
        
        if let taps = measurement.numberOfTaps {
            print("  🔢 Publishing number of taps: \(taps)")
            numberOfTaps = taps
            loadedNumberOfTaps = taps
        } else {
            print("  ⚠️ No number of taps in measurement")
        }
        
        print("✅ Loaded measurement with \(measurement.peaks.count) peaks (frozen)")
    }
    
    /// Export a single measurement as JSON with image (calls completion with JSON and measurement)
    func exportMeasurement(_ measurement: TapToneMeasurement, completion: @escaping (String, TapToneMeasurement) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            if let data = try? encoder.encode([measurement]),
               let json = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    completion(json, measurement)
                }
            }
        }
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
    
    /// Get the strongest peak for a specific mode (handles legacy mode names via normalization)
    func getPeak(for mode: GuitarMode) -> ResonantPeak? {
        identifiedModes
            .filter { $0.mode.normalized == mode.normalized }
            .max(by: { $0.peak.magnitude < $1.peak.magnitude })?
            .peak
    }
    
    /// Calculate tap tone ratio (ideal is ~2.0)
    /// Ratio of Top resonance to Air resonance frequency
    func calculateTapToneRatio() -> Float? {
        guard let airPeak = getPeak(for: .air),
              let topPeak = getPeak(for: .top) else {
            return nil
        }
        return topPeak.frequency / airPeak.frequency
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
    /// - Parameters:
    ///   - peakID: The unique identifier for the peak
    ///   - offset: The new offset position
    /// - Note: Always called on main thread to ensure UI consistency
    func updateAnnotationOffset(for peakID: UUID, offset: CGPoint) {
        // If already on main thread, update directly to avoid deadlock
        if Thread.isMainThread {
            peakAnnotationOffsets[peakID] = offset
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakAnnotationOffsets[peakID] = offset
            }
        }
    }
    
    /// Get the offset for a peak annotation
    /// - Parameter peakID: The unique identifier for the peak
    /// - Returns: The current offset, or .zero if not customized
    func getAnnotationOffset(for peakID: UUID) -> CGPoint {
        peakAnnotationOffsets[peakID] ?? .zero
    }
    
    /// Reset annotation offset for a specific peak
    /// - Parameter peakID: The unique identifier for the peak
    func resetAnnotationOffset(for peakID: UUID) {
        if Thread.isMainThread {
            peakAnnotationOffsets.removeValue(forKey: peakID)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakAnnotationOffsets.removeValue(forKey: peakID)
            }
        }
    }
    
    /// Reset all annotation offsets to default positions
    func resetAllAnnotationOffsets() {
        if Thread.isMainThread {
            peakAnnotationOffsets = [:]
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakAnnotationOffsets = [:]
            }
        }
    }
    
    /// Apply annotation offsets from a measurement (used when loading saved measurements)
    /// - Parameter offsets: Dictionary of peak IDs to offset positions
    func applyAnnotationOffsets(_ offsets: [UUID: CGPoint]) {
        if Thread.isMainThread {
            peakAnnotationOffsets = offsets
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakAnnotationOffsets = offsets
            }
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
            
            // Stop decay tracking
            self.isTrackingDecay = false
            self.decayTrackingTimer?.invalidate()
            self.decayTrackingTimer = nil
            
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
            
            // Reset decay tracking
            self.currentDecayTime = nil
            self.peakMagnitudeHistory = []
            self.isTrackingDecay = false
            self.decayTrackingTimer?.invalidate()
            self.decayTrackingTimer = nil
            
            // IMPORTANT: Initialize threshold state based on current audio level
            // This prevents false "rising edge" detection when starting
            let currentPeakMag = self.fftAnalyzer.peakMagnitude
            self.isAboveThreshold = (currentPeakMag > self.tapDetectionThreshold)
            
            if self.isAboveThreshold {
                print("⚠️ Starting with audio already above threshold (\(currentPeakMag) dB > \(self.tapDetectionThreshold) dB) - will wait for signal to drop first")
            }
            
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
            
            // Stop decay tracking
            self.isTrackingDecay = false
            self.decayTrackingTimer?.invalidate()
            self.decayTrackingTimer = nil
            
            // IMPORTANT: Initialize threshold state based on current audio level
            // This prevents false "rising edge" detection when cancelling
            let currentPeakMag = self.fftAnalyzer.peakMagnitude
            self.isAboveThreshold = (currentPeakMag > self.tapDetectionThreshold)
            
            if self.isAboveThreshold {
                print("⚠️ Cancelling with audio already above threshold (\(currentPeakMag) dB > \(self.tapDetectionThreshold) dB) - will wait for signal to drop first")
            }
            
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
            
            // IMPORTANT: Initialize threshold state based on current audio level
            // This prevents false "rising edge" detection when resuming
            let currentPeakMag = self.fftAnalyzer.peakMagnitude
            self.isAboveThreshold = (currentPeakMag > self.tapDetectionThreshold)
            
            if self.isAboveThreshold {
                print("⚠️ Resuming with audio already above threshold (\(currentPeakMag) dB > \(self.tapDetectionThreshold) dB) - will wait for signal to drop first")
            }
            
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
