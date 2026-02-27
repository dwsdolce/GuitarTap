//
//  TapToneAnalyzer.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import SwiftUI
import Combine

// MARK: - Tap Tone Analyzer

/// Advanced tap tone analysis for guitar lutherie
final class TapToneAnalyzer: ObservableObject {
    
    // MARK: - Dependencies
    
    /// The underlying FFT analyzer
    let fftAnalyzer: RealtimeFFTAnalyzer
    
    /// Pitch calculator for musical note analysis
    let pitchCalculator = Pitch(a4: 440.0)
    
    // MARK: - Configuration
    
    /// Minimum magnitude threshold for peak detection (dB)
    @Published var peakThreshold: Float = SpectrumDisplaySettings.defaultPeakThreshold
    
    /// Minimum frequency for analysis (Hz)
    @Published var minFrequency: Float = SpectrumDisplaySettings.analysisMinFrequency
    
    /// Maximum frequency for analysis (Hz)
    @Published var maxFrequency: Float = SpectrumDisplaySettings.analysisMaxFrequency
    
    /// Number of peaks to track (persisted in SpectrumDisplaySettings)
    @Published var maxPeaks: Int = SpectrumDisplaySettings.maxPeaks
    
    /// Decay threshold for ring-out measurement (dB below peak)
    /// Default is 15 dB which works well with typical room noise floors
    @Published var decayThreshold: Float = 15
    
    /// Number of taps to average (1 = no averaging, 3-5 recommended)
    @Published var numberOfTaps: Int = 1
    
    /// Time window after tap to capture spectrum (seconds)
    @Published var captureWindow: TimeInterval = 0.2
    
    /// Tap detection threshold in dB (absolute magnitude level to trigger tap)
    @Published var tapDetectionThreshold: Float = SpectrumDisplaySettings.defaultTapDetectionThreshold
    
    /// Hysteresis margin in dB (prevents bouncing around threshold)
    /// Signal must fall this many dB below threshold before ready for next tap
    @Published var hysteresisMargin: Float = SpectrumDisplaySettings.defaultHysteresisMargin
    
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
    
    /// Whether tap detection is temporarily paused mid-sequence (spectrum stays live)
    @Published var isDetectionPaused: Bool = false
    
    /// Whether the analyzer is ready for tap detection (false during audio route change reinitialization)
    @Published var isReadyForDetection: Bool = true
    
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
    
    /// Set of peak IDs that should be hidden from annotation display
    @Published var hiddenPeakIDs: Set<UUID> = []
    
    /// Whether all peak annotations are currently visible (convenience for UI toggle)
    var areAllPeaksVisible: Bool {
        hiddenPeakIDs.isEmpty
    }
    
    /// Toggle visibility of a specific peak
    func togglePeakVisibility(_ peakID: UUID) {
        if hiddenPeakIDs.contains(peakID) {
            hiddenPeakIDs.remove(peakID)
        } else {
            hiddenPeakIDs.insert(peakID)
        }
    }
    
    /// Show all peak annotations
    func showAllPeaks() {
        hiddenPeakIDs.removeAll()
    }
    
    /// Hide all peak annotations
    func hideAllPeaks() {
        hiddenPeakIDs = Set(currentPeaks.map { $0.id })
    }
    
    /// Get visible peaks (filtered by hiddenPeakIDs)
    var visiblePeaks: [ResonantPeak] {
        currentPeaks.filter { !hiddenPeakIDs.contains($0.id) }
    }
    
    // MARK: - Material Measurement State
    
    /// Current phase of material tap sequence (two-tap process for L and C modes)
    @Published var materialTapPhase: MaterialTapPhase = .notStarted
    
    /// Captured spectrum from longitudinal tap (support along short edges, plate bends along length)
    @Published var longitudinalSpectrum: (magnitudes: [Float], frequencies: [Float])?
    
    /// Captured spectrum from cross-grain tap (support along long edges, plate bends across width)
    @Published var crossSpectrum: (magnitudes: [Float], frequencies: [Float])?
    
    /// Peaks detected from longitudinal tap
    @Published var longitudinalPeaks: [ResonantPeak] = []
    
    /// Peaks detected from cross-grain tap
    @Published var crossPeaks: [ResonantPeak] = []
    
    /// Auto-selected longitudinal peak ID (strongest peak from L tap)
    @Published var autoSelectedLongitudinalPeakID: UUID?
    
    /// The peak selected for the longitudinal (fL) phase — set directly when the phase completes
    @Published var selectedLongitudinalPeak: ResonantPeak?
    
    /// User override for longitudinal peak selection (nil = use selectedLongitudinalPeak)
    @Published var userSelectedLongitudinalPeakID: UUID?
    
    /// Auto-selected cross-grain peak ID (strongest peak from C tap)
    @Published var autoSelectedCrossPeakID: UUID?
    
    /// The peak selected for the cross-grain (fC) phase — set directly when the phase completes
    @Published var selectedCrossPeak: ResonantPeak?
    
    /// User override for cross-grain peak selection (nil = use selectedCrossPeak)
    @Published var userSelectedCrossPeakID: UUID?
    
    /// Peaks detected from FLC (diagonal/shear) tap
    @Published var flcPeaks: [ResonantPeak] = []
    
    /// Captured spectrum from FLC tap
    @Published var flcSpectrum: (magnitudes: [Float], frequencies: [Float])?
    
    /// Auto-selected FLC peak ID (strongest peak from FLC tap)
    @Published var autoSelectedFlcPeakID: UUID?
    
    /// The peak selected for the FLC (diagonal/shear) phase — set directly when the phase completes
    @Published var selectedFlcPeak: ResonantPeak?
    
    /// User override for FLC peak selection (nil = use selectedFlcPeak)
    @Published var userSelectedFlcPeakID: UUID?
    
    // MARK: - Effective Selection (single source of truth for views)
    
    /// The ID of the peak that represents fL — user override takes precedence, then phase-stored peak, then auto-selected
    var effectiveLongitudinalPeakID: UUID? {
        userSelectedLongitudinalPeakID ?? selectedLongitudinalPeak?.id ?? autoSelectedLongitudinalPeakID
    }
    
    /// The ID of the peak that represents fC — user override takes precedence, then phase-stored peak, then auto-selected
    var effectiveCrossPeakID: UUID? {
        userSelectedCrossPeakID ?? selectedCrossPeak?.id ?? autoSelectedCrossPeakID
    }
    
    /// The ID of the peak that represents fLC — user override takes precedence, then phase-stored peak, then auto-selected
    var effectiveFlcPeakID: UUID? {
        userSelectedFlcPeakID ?? selectedFlcPeak?.id ?? autoSelectedFlcPeakID
    }
    
    // MARK: - Loaded/Restored State (used when loading saved measurements)

    /// Loaded spectrum display ranges (used when restoring measurements)
    @Published var loadedMinFreq: Float?
    @Published var loadedMaxFreq: Float?
    @Published var loadedMinDB: Float?
    @Published var loadedMaxDB: Float?
    
    /// Loaded analysis settings (used when restoring measurements)
    @Published var loadedTapDetectionThreshold: Float?
    @Published var loadedHysteresisMargin: Float?
    @Published var loadedNumberOfTaps: Int?
    @Published var loadedShowUnknownModes: Bool?
    @Published var loadedGuitarType: GuitarType?
    @Published var loadedMeasurementType: MeasurementType?
    
    /// Warning shown when a loaded/imported measurement's microphone is unavailable
    @Published var microphoneWarning: String?

    /// Loaded material measurement data (used when restoring measurements)
    @Published var loadedSelectedLongitudinalPeakID: UUID?
    @Published var loadedSelectedCrossPeakID: UUID?
    @Published var loadedSelectedFlcPeakID: UUID?
    @Published var loadedMaterialLength: Float?
    @Published var loadedMaterialWidth: Float?
    @Published var loadedMaterialThickness: Float?
    @Published var loadedMaterialMass: Float?

    // MARK: - Gated FFT Private State

    /// Lock protecting gatedAccumBuffer (accessed from both audio and main queue)
    let mpmLock = NSLock()

    /// Whether the gated-FFT capture window is currently open.
    var gatedCaptureActive: Bool = false

    /// Accumulated raw samples for the current gated FFT capture window.
    var gatedAccumBuffer: [Float] = []

    /// Target capture duration for the gated FFT window (seconds).
    /// 400 ms captures the plate ring-out while rejecting post-decay noise.
    static let gatedCaptureDuration: Double = 0.400

    /// Number of samples to capture, derived from the actual hardware sample rate.
    var gatedCaptureSamples: Int { Int(mpmSampleRate * TapToneAnalyzer.gatedCaptureDuration) }

    /// Called on the main thread once the gated capture window fills.
    /// Receives `(samples, sampleRate, phase)` and runs `computeGatedFFT` then
    /// routes to the appropriate phase handler.
    var gatedCaptureCompletion: (([Float], Double, MaterialTapPhase) -> Void)?

    /// The material phase that was active when gated capture started.
    var gatedCapturePhase: MaterialTapPhase = .notStarted

    /// Most recent hardware sample rate (set on the audio queue)
    var mpmSampleRate: Double = 48000

    // MARK: - Pre-roll Ring Buffer
    //
    // The tap detection subscriber runs on the main thread, while raw audio buffers
    // arrive on the audio processing queue.  By the time detectTap fires and
    // startGatedCapture sets gatedCaptureActive=true, several buffers carrying the
    // tap transient have already passed through accumulateGatedSamples and been
    // discarded — so the gated window captures only the decaying tail or silence.
    //
    // Solution: continuously keep the last `preRollSamples` worth of raw audio in a
    // circular buffer (preRollBuffer).  When startGatedCapture is called it seeds
    // gatedAccumBuffer with the ring buffer contents so the tap attack is included.

    /// Duration of the pre-roll look-back in seconds (200 ms catches the tap attack).
    static let preRollDuration: Double = 0.200

    /// Number of pre-roll samples at the current sample rate.
    var preRollSamples: Int { Int(mpmSampleRate * TapToneAnalyzer.preRollDuration) }

    /// Circular pre-roll buffer — always holds the last `preRollSamples` raw samples.
    var preRollBuffer: [Float] = []

    // MARK: - Noise Floor Estimation (material/brace modes)

    /// Exponential moving average of inputLevelDB, used as the noise floor estimate for
    /// relative tap detection in material/brace modes.  Updated only when not detecting
    /// a tap (i.e. when the signal is at its background level).
    var noiseFloorEstimate: Float = -60

    /// EMA alpha for noise floor tracking — slower rise to avoid including tap energy,
    /// faster fall so the estimate recovers quickly between taps.
    /// α ≈ 1 - exp(-dt/τ).  At ~10 ms buffer updates, α=0.05 gives τ ≈ 190 ms.
    let noiseFloorAlpha: Float = 0.05

    // MARK: - Private State

    var cancellables = Set<AnyCancellable>()
    var peakMagnitudeHistory: [(time: Date, magnitude: Float)] = []
    var lastTapTime: Date?
    var tapPeakLevel: Float = -100  // The input level at tap detection time (for decay reference)
    let tapCooldown: TimeInterval = 0.5  // Minimum time between taps
    
    /// Time when the analyzer started (for warm-up period)
    var analyzerStartTime: Date?
    
    /// Warm-up period in seconds - ignore taps during this time to prevent false detections
    let warmupPeriod: TimeInterval = 0.5
    
    /// Storage for captured tap spectra (for averaging) - guitar mode
    var capturedTaps: [(magnitudes: [Float], frequencies: [Float], captureTime: Date)] = []
    
    /// Storage for captured spectra within current material phase (for multi-tap averaging)
    var materialCapturedTaps: [(magnitudes: [Float], frequencies: [Float], captureTime: Date)] = []
    
    /// Storage for peaks from each tap (before averaging)
    var tapsForAveraging: [[ResonantPeak]] = []
    
    /// Timer for capture window
    var captureTimer: Timer?
    
    /// Track if signal is currently above threshold (for rising edge detection)
    var isAboveThreshold: Bool = false
    
    /// Timer for decay tracking window (continues after tap detection)
    var decayTrackingTimer: Timer?
    
    /// Whether we're currently tracking decay after a tap
    var isTrackingDecay: Bool = false

    /// Track if we just exited warm-up period (to sync threshold state without triggering)
    var justExitedWarmup: Bool = false

    // MARK: - Initialization
    
    init(fftAnalyzer: RealtimeFFTAnalyzer) {
        self.fftAnalyzer = fftAnalyzer
        
        // Load persisted analysis settings
        peakThreshold = SpectrumDisplaySettings.peakThreshold
        minFrequency = SpectrumDisplaySettings.analysisMinFrequency
        maxFrequency = SpectrumDisplaySettings.analysisMaxFrequency
        
        // Load persisted tap detection settings
        tapDetectionThreshold = SpectrumDisplaySettings.tapDetectionThreshold
        hysteresisMargin = SpectrumDisplaySettings.hysteresisMargin
        
        // Load persisted measurements
        loadPersistedMeasurements()
        
        setupSubscriptions()
    }
    
    // MARK: - Setup
    
    func setupSubscriptions() {
        // Set up raw sample handler for gated FFT capture — accumulates samples into the buffer
        fftAnalyzer.rawSampleHandler = { [weak self] samples, sampleRate in
            self?.accumulateGatedSamples(samples, sampleRate: sampleRate)
        }

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

        // Fast tap detection for material/brace modes using per-buffer RMS level.
        //
        // The long-window FFT (65536 samples ≈ 1.5 s) dilutes a short tap impact by
        // ~15 dB, making the FFT peakMagnitude an unreliable trigger for transient taps.
        // inputLevelDB updates every audio buffer (~10 ms) with the instantaneous RMS level,
        // allowing the hysteresis logic to see the signal fall after a tap so that the
        // next rising edge can be detected correctly.  Guitar/classical mode continues
        // to use the FFT path so that the magnitudes array at tap time is analyzed.
        fftAnalyzer.$inputLevelDB
            .receive(on: DispatchQueue.main)
            .sink { [weak self] levelDB in
                guard let self = self else { return }
                let type = SpectrumDisplaySettings.measurementType
                guard type == .material || type == .brace else { return }
                guard self.isDetecting && !self.isDetectionPaused else { return }
                self.detectTap(peakMagnitude: levelDB,
                               magnitudes: self.fftAnalyzer.magnitudes,
                               frequencies: self.fftAnalyzer.frequencies)
            }
            .store(in: &cancellables)
        
        // Subscribe to route change restart notifications
        // When the audio engine restarts due to a device change, reset tap detection state
        // to prevent false detections from the audio startup transient
        fftAnalyzer.$routeChangeRestartCount
            .dropFirst() // Ignore initial value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleRouteChangeRestart()
            }
            .store(in: &cancellables)
    }
    
    /// Handles audio route change restart by resetting tap detection state
    /// This prevents false tap detections when the audio engine restarts
    func handleRouteChangeRestart() {
        print("🔄 TapToneAnalyzer: Handling route change restart - resetting detection state")
        
        // Remember if we were detecting before the route change
        let wasDetecting = isDetecting
        
        // Mark analyzer as not ready - this disables New Tap and Resume buttons
        isReadyForDetection = false
        
        // Temporarily disable detection to prevent false positives during restart
        isDetecting = false
        
        // Reset warmup timer to prevent false detections during audio startup
        analyzerStartTime = Date()
        
        // Reset threshold state to prevent false rising edge detection
        // IMPORTANT: Set to true so the first FFT frame won't trigger a rising edge
        // The actual state will be corrected once valid FFT data arrives
        isAboveThreshold = true
        
        // Reset tap detection flag
        tapDetected = false
        
        // Update status message
        statusMessage = "Audio device changed - reinitializing..."
        
        // Re-enable detection after FFT has had time to produce valid data
        // FFT with 65536 samples at 48kHz takes ~1.36 seconds, so wait 2 seconds to be safe
        // This ensures peakMagnitude has been updated with real data before we check it
        let fftSettleTime: TimeInterval = 2.0
        DispatchQueue.main.asyncAfter(deadline: .now() + fftSettleTime) { [weak self] in
            guard let self = self else { return }
            // Only re-enable if we haven't been stopped in the meantime
            if self.fftAnalyzer.isRunning {
                // Re-initialize threshold state based on current audio level
                // This MUST happen before enabling detection
                let currentPeakMag = self.fftAnalyzer.peakMagnitude
                self.isAboveThreshold = (currentPeakMag > self.tapDetectionThreshold)
                
                // Mark analyzer as ready again - this enables New Tap and Resume buttons
                self.isReadyForDetection = true
                
                // Re-enable detection if it was active before
                if wasDetecting {
                    self.isDetecting = true
                    self.statusMessage = self.numberOfTaps == 1 ? "Tap the guitar..." : "Tap the guitar \(self.numberOfTaps) times..."
                } else {
                    self.statusMessage = "Ready"
                }
                print("🔄 TapToneAnalyzer: Detection re-enabled after route change (current level: \(currentPeakMag) dB, threshold: \(self.tapDetectionThreshold) dB, above threshold: \(self.isAboveThreshold))")
            }
        }
    }
}
