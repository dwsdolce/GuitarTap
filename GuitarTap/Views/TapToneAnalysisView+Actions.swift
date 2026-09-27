/// # TapToneAnalysisView+Actions
///
/// User-initiated action handlers for `TapToneAnalysisView`.
///
/// This extension contains all methods that respond to toolbar button taps and
/// menu selections:
///
/// - **`toggleAnalyzer()`** — Starts or stops the audio engine.  On iOS, requests
///   microphone permission before starting using the appropriate API for the
///   OS version (iOS 17+ uses `AVAudioApplication`, earlier uses
///   `AVAudioSession`).  On macOS, checks `AVCaptureDevice.authorizationStatus`
///   and shows an alert if the user has denied access.  A macOS-specific error
///   path handles `kAudioUnitErr_Unauthorized` (−10877) — the OS silently mutes
///   the audio engine after permission is revoked, even while
///   `authorizationStatus` still reports `.authorized` from its TCC cache.
///
/// - **`startAnalyzer()`** — Calls `TapToneAnalyzer.start()` after configuring
///   the `AVAudioSession` on iOS.  Surfaces permission errors as an alert.
///
/// - **`startNewTapSequence()`** — Resets the analyzer for a new tap cycle,
///   synchronizing spectrum display state (axis ranges, selected peak IDs)
///   with the current `TapDisplaySettings`.
///
/// - **`cancelCurrentTap()`** — Cancels an in-progress multi-tap sequence and
///   clears all related state.
///
/// - **`loadMeasurement(_:)`** — Restores a persisted `TapToneMeasurement` into
///   the analyzer and updates the view's axis range bindings from the
///   `loaded*` published properties.
///
/// - SeeAlso: `TapToneAnalyzer+Control`, `TapToneAnalyzer+MeasurementManagement`
//
//  TapToneAnalysisView+Actions.swift
//  GuitarTap
//

import SwiftUI
import AVFoundation

extension TapToneAnalysisView {

    // MARK: - Actions

    func toggleAnalyzer() {
        if fft.isRunning {
            tap.stop()
        } else {
            #if os(iOS)
            // On iOS, request microphone permission first.
            // If already denied, requestRecordPermission returns false immediately without showing a dialog.
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.startAnalyzer()
                        } else {
                            self.showingMicrophonePermissionAlert = true
                        }
                    }
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.startAnalyzer()
                        } else {
                            self.showingMicrophonePermissionAlert = true
                        }
                    }
                }
            }
            #else
            // On macOS, check permission before starting; show alert if denied.
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .denied || status == .restricted {
                showingMicrophonePermissionAlert = true
            } else {
                startAnalyzer()
            }
            #endif
        }
    }

    func startAnalyzer() {
        // AVAudioEngine.start() is safe to call from the main thread
        // Don't dispatch to background - this can cause deadlocks when the engine
        // tries to update @Published properties on main thread
        do {
            #if os(iOS)
            // Configure audio session for iOS
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
            #endif

            try self.tapToneAnalyzer.start()
        } catch {
            gtLog("❌ Failed to start analyzer: \(error)")
            #if os(macOS)
            // Surface permission errors as an alert.
            // kAudioUnitErr_Unauthorized (-10877) means the audio engine was denied by TCC —
            // this happens when macOS restarts the app after revoking permission and the TCC
            // cache hasn't yet updated, so authorizationStatus still reports .authorized.
            // Our own domain codes 1/2 cover the cases where the status check fires correctly.
            let nsError = error as NSError
            let isPermissionError = (nsError.domain == "RealtimeFFTAnalyzer" && (nsError.code == 1 || nsError.code == 2))
                                 || nsError.code == -10877
            if isPermissionError {
                showingMicrophonePermissionAlert = true
            } else if nsError.code == 1937010544 {
                // kAUStartIO ('iost') — transient Core Audio I/O start failure.
                // Typically caused by a Continuity Audio device connecting or disconnecting
                // at the same moment the engine tries to start.  Retry once after a short
                // settle delay; surface an error only if the retry also fails.
                gtLog("⚠️ kAUStartIO race detected — retrying engine start in 1 s")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    do {
                        try tapToneAnalyzer.start()
                        gtLog("✅ Engine started successfully on kAUStartIO retry")
                    } catch {
                        gtLog("❌ Engine start retry failed: \(error)")
                        engineStartError = "The audio engine could not start (error \((error as NSError).code)). Try switching the audio input device in Settings, or restart the app.\n\nDetails: \(error.localizedDescription)"
                    }
                }
            } else {
                // Surface unexpected engine errors so the user isn't silently stuck on "Starting...".
                // Include the error code to help diagnose hardware-specific failures.
                engineStartError = "The audio engine could not start (error \(nsError.code)). Try switching the audio input device in Settings, or restart the app.\n\nDetails: \(error.localizedDescription)"
            }
            #endif
        }
    }

    /// Opens a user-selected audio file and feeds it through the FFT/tap-detection pipeline
    /// instead of the microphone.  This gives a perfectly reproducible signal for cross-platform
    /// comparisons.
    ///
    /// - Parameters:
    ///   - url: The audio file to play (WAV, AIFF, etc.).
    ///   - calibrationURL: Optional microphone calibration file (.txt, .cal) to apply
    ///     during playback.  If provided, the calibration is parsed and temporarily
    ///     set on the FFT analyzer for the duration of playback, then the previous
    ///     calibration is restored.
    func openAudioFile(_ url: URL, calibrationURL: URL?) {
        // Gain access to the security-scoped resource.
        // On iOS with cloud storage providers (Dropbox, iCloud Drive, etc.) this grants
        // the sandbox permission to read the file.  We must keep access open for the full
        // playback duration because AVAudioEngine reads audio asynchronously after open.
        // The completion closure passed to startFromFile releases it when playback ends.
        let accessing = url.startAccessingSecurityScopedResource()
        let accessingCal = calibrationURL?.startAccessingSecurityScopedResource() ?? false

        do {
            // The analyzer applies the calibration, arms the sequence and starts the file (the app's one
            // Play File path, which the file-playback regressions also run).
            try tapToneAnalyzer.playFile(url: url, calibrationURL: calibrationURL) {
                // Playback ended and the engine is back on the microphone — safe to release access.
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            if accessingCal { calibrationURL?.stopAccessingSecurityScopedResource() }
        } catch {
            if accessing { url.stopAccessingSecurityScopedResource() }
            if accessingCal { calibrationURL?.stopAccessingSecurityScopedResource() }
            engineStartError = "Could not play audio file: \(error.localizedDescription)"
            return
        }
    }

    func saveMeasurement(name: String, noteText: String) {
        // The Save sheet owns the edit; it hands the values here on confirm. Mirror them into the
        // transient view fields the save/export paths read (Python sets self._measurement_name /
        // self._notes on dialog-accept the same way), then clear them below once the save is done —
        // so nothing persists into the next measurement.
        measurementName = name
        notes = noteText
        if tap.isSavedMeasurementComparison {
            tap.saveComparison(
                measurementName: TapToneMeasurement.normalizedName(measurementName),
                notes: TapToneMeasurement.normalizedNotes(notes)
            )
            measurementName = ""
            notes = ""
            showingSaveSheet = false
            return
        }

        isSavingMeasurement = true

        // Pass only view-layer state: axis range floats, device identity, and
        // effective peak role IDs. The model builds all SpectrumSnapshot objects
        // internally from its own state (frozen/live FFT, longitudinalSpectrum etc.)
        // using makePhaseSnapshot. Mirrors Python TapToneAnalysisView.save_measurement().
        tapToneAnalyzer.saveMeasurement(
            measurementName: TapToneMeasurement.normalizedName(measurementName),
            notes: TapToneMeasurement.normalizedNotes(notes),
            includeSpectrum: true,
            annotationOffsets: tap.peakAnnotationOffsets,
            selectedLongitudinalPeakID: tap.effectiveLongitudinalPeakID,
            selectedCrossPeakID: tap.effectiveCrossPeakID,
            selectedFlcPeakID: tap.effectiveFlcPeakID,
            microphoneName: fft.selectedInputDevice?.name,
            microphoneUID: fft.selectedInputDevice?.uid,
            calibrationName: fft.activeCalibration?.name,
            sampleRate: fft.actualSampleRate > 0 ? fft.actualSampleRate : nil,
            minFreq: minFreq,
            maxFreq: maxFreq,
            minDB: minDB,
            maxDB: maxDB
        )

        measurementName = ""
        notes = ""
        showingSaveSheet = false
        isSavingMeasurement = false
    }

    // MARK: - Spectrum Display Helpers

    func updateFrequencyInputFields() {
        minFreqInput = String(format: "%.0f", minFreq)
        maxFreqInput = String(format: "%.0f", maxFreq)
    }

    /// Apply all four axis values atomically — called by ``SpectrumView``'s
    /// `onAxisRangeReset` callback so that all four `@State` vars are
    /// mutated in a single closure.  SwiftUI coalesces the mutations into one
    /// render pass, preventing the transient `minDB > maxDB` state that
    /// causes the clamping artifact when individual `@Binding` writes arrive
    /// in separate update cycles.
    func applyAxisRange(minFreq: Float, maxFreq: Float, minDB: Float, maxDB: Float) {
        self.minFreq    = minFreq
        self.maxFreq    = maxFreq
        self.minDB      = minDB
        self.maxDB      = maxDB
        self.minFreqInput = String(format: "%.0f", minFreq)
        self.maxFreqInput = String(format: "%.0f", maxFreq)
        self.minDBInput   = String(format: "%.0f", minDB)
        self.maxDBInput   = String(format: "%.0f", maxDB)
    }

    /// Expand the frequency display range to ensure the given frequency is visible.
    /// Adds 10% padding above/below. Used when plate/brace peaks are auto-selected
    /// to ensure they're always in view even if outside the persisted default range.
    func expandFreqRangeToInclude(_ frequency: Float) {
        // Material only: a guitar range is the user's analysis window and is not widened for them.
        guard !TapDisplaySettings.measurementType.isGuitar else { return }
        // The RULE lives in DisplayRange so Python and web share it and all three can test it.
        let widened = DisplayRange.expanded(toInclude: frequency, min: minFreq, max: maxFreq)
        if widened.max != maxFreq {
            maxFreq = widened.max
            maxFreqInput = String(format: "%.0f", maxFreq)
        }
        if widened.min != minFreq {
            minFreq = widened.min
            minFreqInput = String(format: "%.0f", minFreq)
        }
    }

    func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.1fk Hz", freq / 1000)
        } else {
            return String(format: "%.0f Hz", freq)
        }
    }

    /// Auto-scale the dB range to fit the current signal
    func autoScaleDB() {
        // When comparing, scale to fit all comparison curves; otherwise use the displayed spectrum.
        let sourceMagnitudes: [Float]
        if tap.displayMode == .comparison {
            sourceMagnitudes = tap.comparisonSpectra.flatMap { $0.magnitudes }
        } else {
            sourceMagnitudes = displayMagnitudes
        }
        let mags = sourceMagnitudes.filter { $0 > -100 && $0 < 20 }
        guard !mags.isEmpty else {
            gtLog("⚠️ No valid magnitudes to auto-scale")
            return
        }

        let minMag = mags.min() ?? -100
        let maxMag = mags.max() ?? 0

        // Add 10% padding above and below
        let range = maxMag - minMag
        let padding = max(10, range * 0.1)  // At least 10 dB padding

        let newMinDB = max(-120, minMag - padding)
        let newMaxDB = min(20, maxMag + padding)

        // Ensure minimum 20 dB range
        if newMaxDB - newMinDB < 20 {
            let center = (newMinDB + newMaxDB) / 2
            minDB = center - 10
            maxDB = center + 10
        } else {
            minDB = newMinDB
            maxDB = newMaxDB
        }

        // Update input fields
        minDBInput = String(format: "%.0f", minDB)
        maxDBInput = String(format: "%.0f", maxDB)

        gtLog("📏 Auto-scaled dB range: \(String(format: "%.1f", minDB)) to \(String(format: "%.1f", maxDB)) dB (signal range: \(String(format: "%.1f", minMag)) to \(String(format: "%.1f", maxMag)) dB)")
    }

    /// Toggles auto-scale mode on/off
    func toggleAutoScale() {
        isAutoScaleEnabled.toggle()

        if isAutoScaleEnabled {
            gtLog("🔄 Auto-scale dB enabled - will scale on each update")
            // Perform initial auto-scale
            autoScaleDB()
        } else {
            gtLog("🔄 Auto-scale dB disabled - resetting to default range")
            // Reset to default values
            resetDBToDefaults()
        }
    }

    /// Resets the dB range to default settings
    func resetDBToDefaults() {
        minDB = TapDisplaySettings.minMagnitude
        maxDB = TapDisplaySettings.maxMagnitude
        minDBInput = String(format: "%.0f", minDB)
        maxDBInput = String(format: "%.0f", maxDB)
        gtLog("↩️ Reset dB range to defaults: \(minDB) to \(maxDB) dB")
    }

    // MARK: - Spectrum Export

    func exportCurrentSpectrum() {
        // Re-entrancy guard: NSSavePanel.begin is async and non-modal, so a second click
        // while a panel is open would stack another panel (see isExportPanelInFlight).
        guard !isExportPanelInFlight else { return }
        isExportingSpectrum = true

        DispatchQueue.main.async {
            let spectrumView = self.createExportableSpectrumView()
            let renderer = ImageRenderer(content: spectrumView)

            // Use display scale from environment
            renderer.scale = self.displayScale

            // Get PNG data using helper
            #if os(iOS)
            guard let uiImage = renderer.uiImage,
                  let pngData = uiImage.pngData() else {
                self.isExportingSpectrum = false
                return
            }
            #elseif os(macOS)
            guard let nsImage = renderer.nsImage,
                  let tiffData = nsImage.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
                self.isExportingSpectrum = false
                return
            }
            #endif

            // Stem from the live name, else the loaded name, else "spectrum".
            let effectiveName = self.measurementName.isEmpty ? self.tap.loadedMeasurementName : self.measurementName
            let filename = "\(ExportFilename.stem(name: effectiveName, timestamp: Date(), unnamed: "spectrum")).png"
            FileExportHelper.exportFile(data: pngData, filename: filename, contentType: .png) { success in
                self.isExportingSpectrum = false
                if !success {
                    gtLog("❌ Failed to export spectrum")
                }
            }
        }
    }

    // MARK: - Results Window

    /// Opens or toggles the Results panel in the macOS split view.
    func showResults() {
        showingResults = true
    }
}
