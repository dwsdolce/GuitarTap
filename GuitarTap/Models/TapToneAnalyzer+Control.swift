//
//  TapToneAnalyzer+Control.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import Foundation

extension TapToneAnalyzer {

    // MARK: - Control

    /// Start analyzing
    func start() throws {
        try fftAnalyzer.start()
        analyzerStartTime = Date()  // Record start time for warm-up period
        print("🎬 Analyzer started - warm-up period: \(warmupPeriod)s")

        // Only auto-start tap detection on the initial user-initiated start.
        // Engine restarts due to device/route/sample-rate changes go through
        // handleRouteChangeRestart() instead, which preserves frozen spectra
        // and in-progress sequences.
        //
        // Evaluate the guard on the main queue so it runs after any pending
        // state changes (e.g. a pause that was dispatched just before this
        // restart) have settled. This prevents startTapSequence() from firing
        // mid-sequence after a HALC overload restart.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !self.isDetecting && !self.isSpectrumFrozen && !self.isDetectionPaused
                && self.currentTapCount == 0 {
                self.startTapSequence()
            }
        }
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
            self.sourceMeasurementTimestamp = nil  // No longer viewing a saved measurement
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
            
            // Reset plate/brace measurement state
            self.materialTapPhase = .notStarted
            self.longitudinalSpectrum = nil
            self.crossSpectrum = nil
            self.flcSpectrum = nil
            self.longitudinalPeaks = []
            self.crossPeaks = []
            self.flcPeaks = []
            self.autoSelectedLongitudinalPeakID = nil
            self.autoSelectedCrossPeakID = nil
            self.autoSelectedFlcPeakID = nil
            self.selectedLongitudinalPeak = nil
            self.selectedCrossPeak = nil
            self.selectedFlcPeak = nil
            self.userSelectedLongitudinalPeakID = nil
            self.userSelectedCrossPeakID = nil
            self.userSelectedFlcPeakID = nil
            self.materialCapturedTaps = []
            
            // Cancel any in-flight gated FFT capture
            self.gatedCaptureActive = false
            self.mpmLock.lock()
            self.gatedAccumBuffer = []
            self.mpmLock.unlock()
            
            self.statusMessage = "Press 'New Tap' to begin"
        }
    }
    
    /// Start a new tap detection sequence
    func startTapSequence() {
        let measurementType = TapDisplaySettings.measurementType
        let isPlateMode = measurementType == .plate
        let isBraceMode = measurementType == .brace
        let currentPeakMagImmediate = fftAnalyzer.peakMagnitude
        print("🎬 Starting tap sequence: \(numberOfTaps) tap(s), plate mode: \(isPlateMode), brace mode: \(isBraceMode)")
        print("🎬 Current FFT peak magnitude (immediate): \(currentPeakMagImmediate) dB, threshold: \(tapDetectionThreshold) dB")
        print("🎬 FFT analyzer running: \(fftAnalyzer.isRunning), frequencies count: \(fftAnalyzer.frequencies.count)")
        
        // Ensure all @Published updates happen on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Clear previous data
            self.capturedTaps = []
            self.tapsForAveraging = []
            self.currentTapCount = 0
            self.tapProgress = 0.0
            self.tapDetected = false
            self.isDetectionPaused = false
            // Reset noise floor estimate so it adapts to the current environment
            self.noiseFloorEstimate = self.fftAnalyzer.inputLevelDB
            
            // Reset decay tracking
            self.currentDecayTime = nil
            self.peakMagnitudeHistory = []
            self.isTrackingDecay = false
            self.decayTrackingTimer?.invalidate()
            self.decayTrackingTimer = nil
            
            // Reset plate/brace measurement state
            if isPlateMode || isBraceMode {
                self.materialTapPhase = .capturingLongitudinal
                self.longitudinalSpectrum = nil
                self.crossSpectrum = nil
                self.flcSpectrum = nil
                self.longitudinalPeaks = []
                self.crossPeaks = []
                self.flcPeaks = []
                self.autoSelectedLongitudinalPeakID = nil
                self.autoSelectedCrossPeakID = nil
                self.autoSelectedFlcPeakID = nil
                self.selectedLongitudinalPeak = nil
                self.selectedCrossPeak = nil
                self.selectedFlcPeak = nil
                self.userSelectedLongitudinalPeakID = nil
                self.userSelectedCrossPeakID = nil
                self.userSelectedFlcPeakID = nil
                self.materialCapturedTaps = []
                // Cancel any in-flight gated FFT capture
                self.gatedCaptureActive = false
                self.mpmLock.lock()
                self.gatedAccumBuffer = []
                self.mpmLock.unlock()
            } else {
                self.materialTapPhase = .notStarted
            }
            
            // IMPORTANT: Always start with isAboveThreshold = false
            // The warm-up period (0.5s) gives time for the audio level to settle,
            // and then we detect the first rising edge naturally.
            // Previously we tried to initialize based on current level, but this caused
            // issues when starting a new sequence while frozen spectrum showed high peaks
            // but actual live audio was quiet - we'd get stuck waiting for a "drop" that
            // never came because the live audio was already low.
            let currentPeakMag = self.fftAnalyzer.peakMagnitude
            print("🎬 Inside async block - FFT peak magnitude: \(currentPeakMag) dB, threshold: \(self.tapDetectionThreshold) dB")
            print("🎬 FFT analyzer state: running=\(self.fftAnalyzer.isRunning), magnitudes count=\(self.fftAnalyzer.magnitudes.count)")
            
            // Always start fresh - the warm-up period handles any transients
            // The justExitedWarmup flag ensures we sync with actual signal level
            // after warm-up ends, preventing false triggers from ambient noise
            self.isAboveThreshold = false
            self.justExitedWarmup = false  // Will be set true during warm-up
            print("✅ Starting with isAboveThreshold = false - ready for tap detection after warm-up")
            
            // Reset warm-up timer to prevent immediate false detection
            self.analyzerStartTime = Date()
            
            // Unfreeze spectrum
            self.isSpectrumFrozen = false
            self.frozenFrequencies = []
            self.frozenMagnitudes = []
            
            // Enable detection
            self.isDetecting = true
            
            // Set appropriate status message
            if isBraceMode {
                self.statusMessage = self.numberOfTaps > 1 ? "Ready for fL tap (×\(self.numberOfTaps))" : "Ready for fL tap"
            } else if isPlateMode {
                let measureFlc = TapDisplaySettings.measureFlc
                if self.numberOfTaps > 1 {
                    let phases = measureFlc ? "L, C, FLC" : "L, C"
                    self.statusMessage = "Ready for L tap (×\(self.numberOfTaps) each for \(phases))"
                } else {
                    self.statusMessage = "Ready for L tap"
                }
            } else {
                self.statusMessage = self.numberOfTaps == 1 ? "Tap the guitar..." : "Tap the guitar \(self.numberOfTaps) times..."
            }
            
            // Clear current results
            self.currentPeaks = []
            self.identifiedModes = []
        }
    }
    
    /// Pause tap detection mid-sequence; spectrum stays live so the user can experiment
    func pauseTapDetection() {
        guard isDetecting && !isDetectionPaused else { return }
        isDetecting = false
        isDetectionPaused = true
        statusMessage = "Detection paused – tap freely, then resume"
        print("⏸️ Tap detection paused at \(currentTapCount)/\(numberOfTaps)")
    }
    
    /// Resume tap detection after a pause, continuing the in-progress sequence
    func resumeTapDetection() {
        guard isDetectionPaused else { return }
        isDetectionPaused = false
        
        // Reset warm-up timer so the first audio frame after resume doesn't trigger immediately
        analyzerStartTime = Date()
        isAboveThreshold = false
        
        isDetecting = true
        
        let resumeType = TapDisplaySettings.measurementType
        let isPlateMode = resumeType == .plate
        let isBraceMode = resumeType == .brace
        if isPlateMode || isBraceMode {
            switch materialTapPhase {
            case .capturingLongitudinal: statusMessage = isBraceMode ? "Ready for fL tap" : "Ready for L tap"
            case .capturingFlc, .waitingForFlcTap: statusMessage = "Ready for FLC tap"
            default: statusMessage = "Ready for C tap"
            }
        } else if currentTapCount == 0 {
            statusMessage = numberOfTaps == 1 ? "Tap the guitar..." : "Tap the guitar \(numberOfTaps) times..."
        } else {
            statusMessage = "Tap \(currentTapCount)/\(numberOfTaps) captured. Tap again..."
        }
        print("▶️ Tap detection resumed at \(currentTapCount)/\(numberOfTaps)")
    }
    
    /// Cancel current tap sequence and restart detection
    func cancelTapSequence() {
        print("❌ Tap sequence cancelled")
        
        let measurementType = TapDisplaySettings.measurementType
        let isPlateMode = measurementType == .plate
        let isBraceMode = measurementType == .brace
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.capturedTaps = []
            self.tapsForAveraging = []
            self.currentTapCount = 0
            self.tapProgress = 0.0
            self.tapDetected = false
            self.isDetectionPaused = false
            self.isDetecting = true
            
            // Reset plate/brace measurement state
            if isPlateMode || isBraceMode {
                self.materialTapPhase = .capturingLongitudinal
                self.longitudinalSpectrum = nil
                self.crossSpectrum = nil
                self.flcSpectrum = nil
                self.longitudinalPeaks = []
                self.crossPeaks = []
                self.flcPeaks = []
                self.autoSelectedLongitudinalPeakID = nil
                self.autoSelectedCrossPeakID = nil
                self.autoSelectedFlcPeakID = nil
                self.selectedLongitudinalPeak = nil
                self.selectedCrossPeak = nil
                self.selectedFlcPeak = nil
                self.userSelectedLongitudinalPeakID = nil
                self.userSelectedCrossPeakID = nil
                self.userSelectedFlcPeakID = nil
                self.materialCapturedTaps = []
                // Cancel any in-flight gated FFT capture
                self.gatedCaptureActive = false
                self.mpmLock.lock()
                self.gatedAccumBuffer = []
                self.mpmLock.unlock()
            }
            
            // Stop decay tracking
            self.isTrackingDecay = false
            self.decayTrackingTimer?.invalidate()
            self.decayTrackingTimer = nil
            
            // Unfreeze spectrum
            self.isSpectrumFrozen = false
            self.frozenFrequencies = []
            self.frozenMagnitudes = []
            
            // Reset warm-up timer to prevent detection issues
            self.analyzerStartTime = Date()
            
            // Always start fresh - the warm-up period handles any transients
            self.isAboveThreshold = false
            
            self.captureTimer?.invalidate()
            self.captureTimer = nil
            
            // Set appropriate status message
            if isBraceMode {
                self.statusMessage = "Ready for fL tap"
            } else if isPlateMode {
                self.statusMessage = "Ready for L tap"
            } else {
                self.statusMessage = self.numberOfTaps == 1 ? "Tap the guitar..." : "Tap the guitar \(self.numberOfTaps) times..."
            }
        }
    }
}
