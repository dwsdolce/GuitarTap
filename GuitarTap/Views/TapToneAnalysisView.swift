/// # TapToneAnalysisView
///
/// The root screen of GuitarTap — live spectrum display, tap detection
/// controls, and access to saved measurements.
///
/// ## Architecture
///
/// `TapToneAnalysisView` owns two `@StateObject` instances that share the same
/// `RealtimeFFTAnalyzer`:
///
/// ```
/// RealtimeFFTAnalyzer  (65536-point FFT, 48 kHz target)
///      │
///      ├── @StateObject fftAnalyzer  ─ live audio engine
///      └── @StateObject tapToneAnalyzer ─ peak detection & measurement management
/// ```
///
/// The analyzer pair is created in `init()` so both objects refer to the
/// *same* FFT engine instance.  Sharing the engine avoids double audio
/// sessions and lets `TapToneAnalyzer` read pre-computed FFT data directly
/// from `RealtimeFFTAnalyzer`'s published properties.
///
/// ## Extensions
///
/// | File | Contents |
/// |------|----------|
/// | `TapToneAnalysisView+Actions.swift`   | Start/stop, new tap, cancel, load measurement |
/// | `TapToneAnalysisView+Controls.swift`  | Toolbar and control panel subviews |
/// | `TapToneAnalysisView+Export.swift`    | PDF report and spectrum PNG export flows |
/// | `TapToneAnalysisView+Layouts.swift`   | macOS / iPad / iPhone layout selection |
/// | `TapToneAnalysisView+SpectrumViews.swift` | Spectrum chart configuration builder |
///
/// ## Platform layout
///
/// | Platform         | Layout |
/// |------------------|--------|
/// | macOS            | Horizontal `HSplitView`: spectrum+info on the left, results panel on the right (when shown). Status bar below. All other panels are sheets. |
/// | iPad             | Vertical stack inside a `NavigationView`. All secondary panels are sheets. |
/// | iPhone (portrait) | Vertical stack. All secondary panels are sheets. |
/// | iPhone (landscape) | `HStack`: 200 pt scrollable controls panel on left, spectrum on right. |
///
/// ## State coordination
///
/// - `loadedMinFreq` / `loadedMaxFreq` / `loadedMinDB` / `loadedMaxDB` are
///   `@Published` on `TapToneAnalyzer` and observed via `.onReceive` to update
///   the view's `@State` axis range without triggering a new tap cycle.
/// - `isAutoScaleEnabled` activates a min-magnitude auto-scale algorithm that
///   polls `fftAnalyzer.magnitudeData` on the analysis queue.
/// - `selectedLongitudinalPeakID` / `selectedCrossPeakID` / `selectedFlcPeakID`
///   mirror `tapToneAnalyzer.effectiveXxxPeakID` for the spectrum chart overlay.
///
/// - SeeAlso: `RealtimeFFTAnalyzer`, `TapToneAnalyzer`, `SpectrumView`
//
//  TapToneAnalysisView.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import SwiftUI
import Charts
import AVFoundation

#if os(macOS)
import AppKit
#endif

#if os(iOS)
import UIKit
#endif

// MARK: - Main Tap Tone Analysis View

/// Root view for GuitarTap, providing the live spectrum display, tap detection
/// controls, and navigation to saved measurements and settings.
struct TapToneAnalysisView: View {
    /// The live audio FFT engine; private to prevent external re-starts.
    @StateObject private var fftAnalyzer: RealtimeFFTAnalyzer
    /// The tap-tone peak detector and measurement manager, shared with the view.
    @StateObject var tapToneAnalyzer: TapToneAnalyzer

    /// Convenience accessor for `fftAnalyzer` (preserves `@StateObject` encapsulation).
    var fft: RealtimeFFTAnalyzer { fftAnalyzer }
    /// Convenience accessor for `tapToneAnalyzer`.
    var tap: TapToneAnalyzer { tapToneAnalyzer }

    @State var tapLocation: String = ""
    @State var notes: String = ""
    @State var isLandscape: Bool = true
    @State var showingSaveSheet = false
    @State var showingMeasurements = false
    @State var showingMetrics = false
    @State var showingResults = false
    @State var showingSettings = false
    @State var isExportingSpectrum = false
    @State var isSavingMeasurement = false
    @State var isGeneratingReport = false
    @State var showingMicrophonePermissionAlert = false
    @State private var openURLImportSuccess: String? = nil
    @State private var openURLImportError: String? = nil

    // Spectrum display state (loaded from persisted settings)
    @State var minFreq: Float = TapDisplaySettings.minFrequency
    @State var maxFreq: Float = TapDisplaySettings.maxFrequency
    @State var minDB: Float = TapDisplaySettings.minMagnitude
    @State var maxDB: Float = TapDisplaySettings.maxMagnitude
    @State var minFreqInput: String = String(format: "%.0f", TapDisplaySettings.minFrequency)
    @State var maxFreqInput: String = String(format: "%.0f", TapDisplaySettings.maxFrequency)
    @State var minDBInput: String = String(format: "%.0f", TapDisplaySettings.minMagnitude)
    @State var maxDBInput: String = String(format: "%.0f", TapDisplaySettings.maxMagnitude)

    // Auto-scale dB state
    @State var isAutoScaleEnabled = false

    #if os(iOS)
    // Crosshair cursor mode (iOS only)
    @State var crosshairMode = false
    #endif

    // Plate/brace measurement mode state
    @State var selectedLongitudinalPeakID: UUID?
    @State var selectedCrossPeakID: UUID?
    @State var selectedFlcPeakID: UUID?

    // Environment
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.displayScale) var displayScale

    /// Returns true if running on iPhone (not iPad)
    var isPhone: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    /// Returns true if we should use compact layout (iPhone in any orientation)
    var useCompactLayout: Bool {
        #if os(iOS)
        return isPhone
        #else
        return false
        #endif
    }

    /// Returns true if iPhone is in landscape orientation (very limited vertical space)
    var isPhoneLandscape: Bool {
        #if os(iOS)
        return isPhone && verticalSizeClass == .compact
        #else
        return false
        #endif
    }

    /// Cancel button should only be enabled during active multi-tap detection
    var cancelButtonEnabled: Bool {
        // Must be multi-tap mode
        guard tapToneAnalyzer.numberOfTaps > 1 else { return false }
        // Must be actively detecting
        guard tapToneAnalyzer.isDetecting else { return false }
        // Must not have completed all taps
        guard tapToneAnalyzer.currentTapCount < tapToneAnalyzer.numberOfTaps else { return false }
        return true
    }

    /// Pause/Resume button is enabled during any active multi-tap, plate, or brace sequence
    var pauseResumeButtonEnabled: Bool {
        // In plate/brace mode, detection management is always relevant
        if !TapDisplaySettings.measurementType.isGuitar {
            return tapToneAnalyzer.isDetecting || tapToneAnalyzer.isDetectionPaused
        }
        // In guitar mode, only enabled for multi-tap sequences
        guard tapToneAnalyzer.numberOfTaps > 1 else { return false }
        return tapToneAnalyzer.isDetecting || tapToneAnalyzer.isDetectionPaused
    }

    /// Creates the view and its paired audio analyzers.
    ///
    /// A single `RealtimeFFTAnalyzer` is constructed with a 65,536-point FFT
    /// (≈0.67 Hz/bin at 48 kHz) and passed to both `@StateObject` wrappers so
    /// they share the same audio engine instance.
    init() {
        // Create a single FFT analyzer instance.
        // 65,536 FFT size gives maximum frequency resolution (0.67 Hz/bin @ 44.1 kHz).
        // With 25% overlap, this gives ~1.8 Hz frame rate.
        let fft = RealtimeFFTAnalyzer(fftSize: 65536, targetSampleRate: 48000)

        // Use the SAME instance for both state objects so they share one audio session.
        _fftAnalyzer = StateObject(wrappedValue: fft)
        _tapToneAnalyzer = StateObject(wrappedValue: TapToneAnalyzer(fftAnalyzer: fft))
    }

    var body: some View {
        Group {
            #if os(macOS)
            macOSLayout
            #else
            iOSLayout
            #endif
        }
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { isLandscape = geo.size.width > geo.size.height }
                .onChange(of: geo.size) { _, size in isLandscape = size.width > size.height }
        })
        .onReceive(tapToneAnalyzer.$loadedMinFreq) { minFreq in
            if let minFreq = minFreq {
                print("  ⬇️ View received loadedMinFreq: \(minFreq)")
                self.minFreq = minFreq
                self.minFreqInput = String(format: "%.0f", minFreq)
                // Clear the loaded value after applying (with small delay to ensure UI updates)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedMinFreq = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedMaxFreq) { maxFreq in
            if let maxFreq = maxFreq {
                print("  ⬇️ View received loadedMaxFreq: \(maxFreq)")
                self.maxFreq = maxFreq
                self.maxFreqInput = String(format: "%.0f", maxFreq)
                // Clear the loaded value after applying (with small delay to ensure UI updates)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedMaxFreq = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedMinDB) { minDB in
            if let minDB = minDB {
                print("  ⬇️ View received loadedMinDB: \(minDB)")
                self.minDB = minDB
                self.minDBInput = String(format: "%.0f", minDB)
                // Clear the loaded value after applying (with small delay to ensure UI updates)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedMinDB = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedMaxDB) { maxDB in
            if let maxDB = maxDB {
                print("  ⬇️ View received loadedMaxDB: \(maxDB)")
                self.maxDB = maxDB
                self.maxDBInput = String(format: "%.0f", maxDB)
                // Clear the loaded value after applying (with small delay to ensure UI updates)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedMaxDB = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedTapDetectionThreshold) { threshold in
            if threshold != nil {
                print("  ⬇️ View received loadedTapDetectionThreshold: \(threshold!)")
                // Settings are already updated in the analyzer via bindings
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedTapDetectionThreshold = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedHysteresisMargin) { hysteresis in
            if hysteresis != nil {
                print("  ⬇️ View received loadedHysteresisMargin: \(hysteresis!)")
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedHysteresisMargin = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedNumberOfTaps) { taps in
            if taps != nil {
                print("  ⬇️ View received loadedNumberOfTaps: \(taps!)")
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedNumberOfTaps = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedPeakThreshold) { threshold in
            if let threshold = threshold {
                print("  ⬇️ View received loadedPeakThreshold: \(threshold)")
                TapDisplaySettings.peakThreshold = threshold
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedPeakThreshold = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedShowUnknownModes) { showUnknown in
            if let showUnknown = showUnknown {
                print("  ⬇️ View received loadedShowUnknownModes: \(showUnknown)")
                TapDisplaySettings.showUnknownModes = showUnknown
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedShowUnknownModes = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedGuitarType) { guitarType in
            if let guitarType = guitarType {
                print("  ⬇️ View received loadedGuitarType: \(guitarType.rawValue)")
                TapDisplaySettings.guitarType = guitarType
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedGuitarType = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedMeasurementType) { measurementType in
            if let measurementType = measurementType {
                print("  ⬇️ View received loadedMeasurementType: \(measurementType.shortName)")
                TapDisplaySettings.measurementType = measurementType
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedMeasurementType = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedSelectedLongitudinalPeakID) { peakID in
            if let peakID = peakID {
                print("  ⬇️ View received loadedSelectedLongitudinalPeakID: \(peakID)")
                self.selectedLongitudinalPeakID = peakID
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedSelectedLongitudinalPeakID = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedSelectedCrossPeakID) { peakID in
            if let peakID = peakID {
                print("  ⬇️ View received loadedSelectedCrossPeakID: \(peakID)")
                self.selectedCrossPeakID = peakID
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedSelectedCrossPeakID = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedSelectedFlcPeakID) { peakID in
            if let peakID = peakID {
                print("  ⬇️ View received loadedSelectedFlcPeakID: \(peakID)")
                self.selectedFlcPeakID = peakID
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedSelectedFlcPeakID = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedPlateLength) { length in
            if let length = length {
                print("  ⬇️ View received loadedPlateLength: \(length)mm")
                if TapDisplaySettings.measurementType.isBrace {
                    TapDisplaySettings.braceLength = length
                } else {
                    TapDisplaySettings.plateLength = length
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedPlateLength = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedPlateWidth) { width in
            if let width = width {
                if TapDisplaySettings.measurementType.isBrace {
                    TapDisplaySettings.braceWidth = width
                } else {
                    TapDisplaySettings.plateWidth = width
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedPlateWidth = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedPlateThickness) { thickness in
            if let thickness = thickness {
                if TapDisplaySettings.measurementType.isBrace {
                    TapDisplaySettings.braceThickness = thickness
                } else {
                    TapDisplaySettings.plateThickness = thickness
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedPlateThickness = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedPlateMass) { mass in
            if let mass = mass {
                if TapDisplaySettings.measurementType.isBrace {
                    TapDisplaySettings.braceMass = mass
                } else {
                    TapDisplaySettings.plateMass = mass
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedPlateMass = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedGuitarBodyLength) { value in
            if let value = value {
                TapDisplaySettings.guitarBodyLength = value
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedGuitarBodyLength = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedGuitarBodyWidth) { value in
            if let value = value {
                TapDisplaySettings.guitarBodyWidth = value
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedGuitarBodyWidth = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedPlateStiffnessPreset) { preset in
            if let preset = preset {
                TapDisplaySettings.plateStiffnessPreset = preset
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedPlateStiffnessPreset = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedCustomPlateStiffness) { value in
            if let value = value {
                TapDisplaySettings.customPlateStiffness = value
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedCustomPlateStiffness = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedMeasureFlc) { value in
            if let value = value {
                TapDisplaySettings.measureFlc = value
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedMeasureFlc = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedBraceLength) { value in
            if let value = value {
                TapDisplaySettings.braceLength = value
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedBraceLength = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedBraceWidth) { value in
            if let value = value {
                TapDisplaySettings.braceWidth = value
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedBraceWidth = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedBraceThickness) { value in
            if let value = value {
                TapDisplaySettings.braceThickness = value
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedBraceThickness = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedBraceMass) { value in
            if let value = value {
                TapDisplaySettings.braceMass = value
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedBraceMass = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$autoSelectedLongitudinalPeakID) { peakID in
            // When plate measurement auto-selects a longitudinal peak, update the view state
            if let peakID = peakID {
                self.selectedLongitudinalPeakID = peakID
                // Expand display range to include this peak
                if let peak = tapToneAnalyzer.longitudinalPeaks.first(where: { $0.id == peakID }) {
                    expandFreqRangeToInclude(peak.frequency)
                }
            }
        }
        .onReceive(tapToneAnalyzer.$autoSelectedCrossPeakID) { peakID in
            // When plate measurement auto-selects a cross-grain peak, update the view state
            if let peakID = peakID {
                self.selectedCrossPeakID = peakID
                // Expand display range to include this peak
                if let peak = tapToneAnalyzer.crossPeaks.first(where: { $0.id == peakID }) {
                    expandFreqRangeToInclude(peak.frequency)
                }
            }
        }
        .onReceive(tapToneAnalyzer.$autoSelectedFlcPeakID) { peakID in
            // When plate measurement auto-selects an FLC peak, update the view state
            if let peakID = peakID {
                self.selectedFlcPeakID = peakID
                // Expand display range to include this peak
                if let peak = tapToneAnalyzer.flcPeaks.first(where: { $0.id == peakID }) {
                    expandFreqRangeToInclude(peak.frequency)
                }
            }
        }
        .onReceive(fftAnalyzer.$magnitudes) { newMagnitudes in
            // Auto-scale dB when enabled and spectrum updates
            // Note: Check for non-empty magnitudes that aren't all -100 (initialization value)
            let hasValidData = !newMagnitudes.isEmpty && newMagnitudes.contains { $0 > -99 }
            if isAutoScaleEnabled && hasValidData && fftAnalyzer.isRunning {
                autoScaleDB()
            }
        }
        .onChange(of: fftAnalyzer.isRunning) { _, isNowRunning in
            // When analyzer starts running, perform initial auto-scale if enabled
            if isNowRunning && isAutoScaleEnabled {
                // Wait a moment for first valid data to arrive
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if self.isAutoScaleEnabled && self.fftAnalyzer.isRunning {
                        print("🔄 Auto-scale: Performing initial scale on analyzer start")
                        self.autoScaleDB()
                    }
                }
            }
        }
        .onChange(of: tapToneAnalyzer.isSpectrumFrozen) { _, isFrozen in
            // Disable auto-scale when spectrum is frozen (tap detected)
            if isFrozen && isAutoScaleEnabled {
                isAutoScaleEnabled = false
                print("🔄 Auto-scale dB disabled - tap detected, spectrum frozen")
            }
        }
        #if os(macOS)
        .onAppear {
            // On macOS, System Settings can force-restart the app after revoking microphone
            // access. Delay slightly so the window is fully presented before showing the alert.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let status = AVCaptureDevice.authorizationStatus(for: .audio)
                if status == .denied || status == .restricted {
                    showingMicrophonePermissionAlert = true
                }
            }
        }
        .onChange(of: fftAnalyzer.microphonePermissionDenied) { _, isDenied in
            // Fired when the 3-second post-start TCC check confirms permission is denied.
            // This catches the macOS TCC cache lag case where authorizationStatus briefly
            // reports .authorized after a forced restart even though the mic is still blocked.
            if isDenied {
                showingMicrophonePermissionAlert = true
                fftAnalyzer.microphonePermissionDenied = false
            }
        }
        #endif
        .alert("Microphone Access Required", isPresented: $showingMicrophonePermissionAlert) {
            Button("Open Settings") {
                #if os(iOS)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                #elseif os(macOS)
                // The newer .extension URL is unreliable on non-developer/non-admin accounts
                // (can route to wrong pane). The legacy preference: scheme works consistently
                // across all account types on macOS Ventura, Sonoma, and Sequoia.
                let micPrivacyURLs = [
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
                    "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone"
                ]
                for urlString in micPrivacyURLs {
                    if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                        break
                    }
                }
                #endif
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("GuitarTap needs microphone access to analyse tap tones. Please enable it in System Settings → Privacy & Security → Microphone.")
        }
        // Handle files opened via AirDrop, Files app, or other system mechanisms
        .onReceive(NotificationCenter.default.publisher(for: .openMeasurementFile)) { notification in
            guard let url = notification.object as? URL else { return }
            importMeasurementFromURL(url)
        }
        .alert("Import Successful", isPresented: .init(
            get: { openURLImportSuccess != nil },
            set: { if !$0 { openURLImportSuccess = nil } }
        )) {
            Button("OK", role: .cancel) { openURLImportSuccess = nil }
        } message: {
            Text(openURLImportSuccess ?? "")
        }
        .alert("Import Error", isPresented: .init(
            get: { openURLImportError != nil },
            set: { if !$0 { openURLImportError = nil } }
        )) {
            Button("OK", role: .cancel) { openURLImportError = nil }
        } message: {
            Text(openURLImportError ?? "")
        }
    }

    /// Import a measurement JSON file that was opened via AirDrop or the Files app.
    private func importMeasurementFromURL(_ url: URL) {
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let imported = try tapToneAnalyzer.importMeasurements(from: data, baseURL: url)

            var message: String
            if imported.count == 1, let measurement = imported.first {
                tapToneAnalyzer.loadMeasurement(measurement)
                message = "Successfully imported and loaded 1 measurement"
            } else {
                message = "Successfully imported \(imported.count) measurements"
            }

            if let warning = tapToneAnalyzer.microphoneWarning {
                message += "\n\n⚠️ " + warning
                tapToneAnalyzer.microphoneWarning = nil
            }
            openURLImportSuccess = message
        } catch {
            openURLImportError = "Failed to import: \(error.localizedDescription)"
        }
    }
}

// MARK: - Preview

#Preview {
    TapToneAnalysisView()
}
