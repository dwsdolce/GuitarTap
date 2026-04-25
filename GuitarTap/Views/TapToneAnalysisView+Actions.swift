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
    /// On macOS the `.fileImporter` SwiftUI modifier handles the picker; this method is called
    /// directly with the resolved security-scoped URL.
    func openAudioFile(_ url: URL) {
        // Gain access to the security-scoped resource.
        // On iOS with cloud storage providers (Dropbox, iCloud Drive, etc.) this grants
        // the sandbox permission to read the file.  We must keep access open for the full
        // playback duration because AVAudioEngine reads audio asynchronously after open.
        // The completion closure passed to startFromFile releases it when playback ends.
        let accessing = url.startAccessingSecurityScopedResource()
        do {
            try fft.startFromFile(url) {
                // Called on the main thread after playback completes and the engine has
                // switched back to the microphone — safe to release access here.
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
        } catch {
            if accessing { url.stopAccessingSecurityScopedResource() }
            engineStartError = "Could not play audio file: \(error.localizedDescription)"
            return
        }
        // Kick off tap detection (bypasses fftAnalyzer.start() since engine is already running).
        // skipWarmup: the audio source is a deterministic file, so the 0.5s warm-up is not
        // needed to suppress microphone startup noise.  The tap transient may also appear within
        // the first 0.5 s of the recording, so skipping warm-up ensures it is not suppressed.
        tapToneAnalyzer.startTapSequence(skipWarmup: true)
    }

    func saveMeasurement() {
        if tap.displayMode == .comparison {
            tap.saveComparison(
                tapLocation: tapLocation.isEmpty ? nil : tapLocation,
                notes: notes.isEmpty ? nil : notes
            )
            tapLocation = ""
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
            tapLocation: tapLocation.isEmpty ? nil : tapLocation,
            notes: notes.isEmpty ? nil : notes,
            includeSpectrum: true,
            annotationOffsets: tap.peakAnnotationOffsets,
            selectedLongitudinalPeakID: tap.effectiveLongitudinalPeakID,
            selectedCrossPeakID: tap.effectiveCrossPeakID,
            selectedFlcPeakID: tap.effectiveFlcPeakID,
            microphoneName: fft.selectedInputDevice?.name,
            microphoneUID: fft.selectedInputDevice?.uid,
            calibrationName: fft.activeCalibration?.name,
            minFreq: minFreq,
            maxFreq: maxFreq,
            minDB: minDB,
            maxDB: maxDB
        )

        tapLocation = ""
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
    /// ``onAxisRangeReset`` callback so that all four ``@State`` vars are
    /// mutated in a single closure.  SwiftUI coalesces the mutations into one
    /// render pass, preventing the transient ``minDB > maxDB`` state that
    /// causes the clamping artifact when individual ``@Binding`` writes arrive
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
        guard !TapDisplaySettings.measurementType.isGuitar else { return }
        let padding = frequency * 0.10
        if frequency > maxFreq {
            maxFreq = frequency + padding
            maxFreqInput = String(format: "%.0f", maxFreq)
        }
        if frequency < minFreq {
            minFreq = max(1, frequency - padding)
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

            // Export using platform-appropriate method
            let filename = "spectrum-\(Int(Date().timeIntervalSince1970)).png"
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
