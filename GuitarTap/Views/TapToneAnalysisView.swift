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
    #if os(macOS)
    /// Stable class reference published into the focused scene for menu commands.
    /// Using `@State` with an `@Observable` class ensures the same instance is
    /// reused across every body re-evaluation, so `AppCommands` does not see a
    /// changed focused value on each audio frame.
    @State private var menuActions = MenuActions()
    #endif

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
    @State var showingHelp = false
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

    /// Drives the repeating opacity throb on the loaded-settings warning icon.
    @State var warningIconOpacity: Double = 1.0

    // Environment
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.displayScale) var displayScale
    #if os(iOS)
    @Environment(\.scenePhase) var scenePhase
    #endif

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

    /// Returns true if running on iPad in a regular (horizontal) size class.
    /// In this layout, the results panel is shown inline like macOS instead of as a sheet.
    var isIPadHorizontal: Bool {
        #if os(iOS)
        return !isPhone && horizontalSizeClass == .regular
        #else
        return false
        #endif
    }

    /// Returns true when the analyzer is in a plate/brace review phase.
    var isInReviewPhase: Bool {
        switch tapToneAnalyzer.materialTapPhase {
        case .reviewingLongitudinal, .reviewingCross, .reviewingFlc:
            return !TapDisplaySettings.measurementType.isGuitar
        default:
            return false
        }
    }

    /// Cancel button is enabled during any active tap detection sequence.
    /// During a review phase it acts as "Redo" and is always enabled.
    var cancelButtonEnabled: Bool {
        // "Redo" is available whenever we are in a review phase.
        if isInReviewPhase { return true }
        guard tapToneAnalyzer.isDetecting else { return false }
        // For plate/brace: always available during an active multi-phase sequence.
        guard TapDisplaySettings.measurementType.isGuitar else { return true }
        // Guitar: only useful in multi-tap mode before all taps are captured.
        guard tapToneAnalyzer.numberOfTaps > 1 else { return false }
        guard tapToneAnalyzer.currentTapCount < tapToneAnalyzer.numberOfTaps else { return false }
        return true
    }

    /// Pause/Resume button is enabled during any active tap detection sequence.
    /// During a review phase it acts as "Accept" and is always enabled.
    var pauseResumeButtonEnabled: Bool {
        if isInReviewPhase { return true }
        return tapToneAnalyzer.isDetecting || tapToneAnalyzer.isDetectionPaused
    }

    /// New Tap button is disabled only when there is nothing to start over from.
    ///
    /// For guitar mode it is disabled mid-sequence (the user must finish or cancel first).
    /// For plate/brace mode it is always enabled so the user can start over at any point,
    /// including while in a review phase or mid-capture.
    var newTapButtonDisabled: Bool {
        guard tapToneAnalyzer.displayMode != .comparison else { return false }
        guard fft.isRunning && tapToneAnalyzer.isReadyForDetection else { return true }
        // Plate/brace: always allow starting over (even during capture or review).
        if !TapDisplaySettings.measurementType.isGuitar { return false }
        // Guitar: disabled while a sequence is in progress and not yet complete.
        if tapToneAnalyzer.isDetecting { return true }
        if !tapToneAnalyzer.isMeasurementComplete { return true }
        return false
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
        let fft = RealtimeFFTAnalyzer(fftSize: 65536)

        // Use the SAME instance for both state objects so they share one audio session.
        _fftAnalyzer = StateObject(wrappedValue: fft)
        _tapToneAnalyzer = StateObject(wrappedValue: TapToneAnalyzer(fftAnalyzer: fft))
    }

    var body: some View {
        layoutContent
            .modifier(LoadedSettingsModifier(tap: tapToneAnalyzer,
                                            minFreq: $minFreq, maxFreq: $maxFreq,
                                            minDB: $minDB, maxDB: $maxDB,
                                            minFreqInput: $minFreqInput, maxFreqInput: $maxFreqInput,
                                            minDBInput: $minDBInput, maxDBInput: $maxDBInput,
                                            selectedLongitudinalPeakID: $selectedLongitudinalPeakID,
                                            selectedCrossPeakID: $selectedCrossPeakID,
                                            selectedFlcPeakID: $selectedFlcPeakID,
                                            expandFreqRange: expandFreqRangeToInclude))
            .modifier(AutoScaleModifier(fft: fftAnalyzer, tap: tapToneAnalyzer,
                                        isAutoScaleEnabled: $isAutoScaleEnabled,
                                        autoScaleAction: autoScaleDB))
            .modifier(LifecycleModifier(fft: fftAnalyzer, tap: tapToneAnalyzer,
                                        isAutoScaleEnabled: isAutoScaleEnabled,
                                        warningIconOpacity: $warningIconOpacity,
                                        showingMicrophonePermissionAlert: $showingMicrophonePermissionAlert,
                                        openURLImportSuccess: $openURLImportSuccess,
                                        openURLImportError: $openURLImportError,
                                        toggleAnalyzer: toggleAnalyzer,
                                        startAnalyzer: startAnalyzer,
                                        importMeasurementFromURL: importMeasurementFromURL))
        #if os(macOS)
            .focusedSceneValue(\.menuActions, menuActions)
            .onAppear { bindMenuActions() }
        #endif
    }

    // MARK: - Menu Actions (macOS only)

    #if os(macOS)
    /// Populate the stable `MenuActions` object with closures that capture
    /// `self`.  Called once from `onAppear`; the `MenuActions` instance itself
    /// never changes, so `AppCommands` does not see a new focused value on
    /// every audio frame.
    private func bindMenuActions() {
        menuActions.saveMeasurement   = { showingSaveSheet = true }
        menuActions.exportSpectrum    = { exportCurrentSpectrum() }
        menuActions.exportPDF         = { exportPDFReport() }
        menuActions.autoScaleDB       = { autoScaleDB() }
        menuActions.cycleAnnotations  = { tap.cycleAnnotationVisibility() }
        menuActions.showMetrics       = { showingMetrics = true }
        menuActions.showMeasurements  = { showingMeasurements = true }
        menuActions.showSettings      = { showingSettings = true }
    }
    #endif

    // MARK: - Layout content

    private var layoutContent: some View {
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
    }

    /// Import a measurement JSON file that was opened via AirDrop or the Files app.
    private func importMeasurementFromURL(_ url: URL) {
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let imported = try tapToneAnalyzer.importMeasurements(from: data)

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
            let nsError = error as NSError
            let isPermissionError = (nsError.domain == NSPOSIXErrorDomain && nsError.code == 1) ||
                                    (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError)
            let isFormatError = nsError.domain == NSCocoaErrorDomain &&
                                (nsError.code == NSFileReadCorruptFileError || nsError.code == 4864)
            if isPermissionError {
                openURLImportError = "Could not read \"\(url.lastPathComponent)\": the system denied access (error \(nsError.code))."
            } else if isFormatError {
                openURLImportError = "Could not import \"\(url.lastPathComponent)\": the file is not a valid GuitarTap measurement."
            } else {
                openURLImportError = "Could not import \"\(url.lastPathComponent)\": \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - ViewModifiers (extracted to keep body type-checker tractable)

/// Applies all `.onReceive` handlers for `loaded*` measurement settings published
/// by `TapToneAnalyzer` when a saved measurement is restored.
private struct LoadedSettingsModifier: ViewModifier {
    @ObservedObject var tap: TapToneAnalyzer

    @Binding var minFreq: Float
    @Binding var maxFreq: Float
    @Binding var minDB: Float
    @Binding var maxDB: Float
    @Binding var minFreqInput: String
    @Binding var maxFreqInput: String
    @Binding var minDBInput: String
    @Binding var maxDBInput: String
    @Binding var selectedLongitudinalPeakID: UUID?
    @Binding var selectedCrossPeakID: UUID?
    @Binding var selectedFlcPeakID: UUID?
    let expandFreqRange: (Float) -> Void

    func body(content: Content) -> some View {
        content
            // Single receiver for all four axis bounds — applying them together in one
            // render pass prevents transient states where e.g. minDB has the new value
            // while maxDB is still old, which caused SwiftUI Charts to clamp every data
            // point to the same level and render spurious vertical line artifacts.
            .onReceive(tap.$loadedAxisRange) { range in
                if let range = range {
                    print("  ⬇️ View received loadedAxisRange: \(range.minFreq)-\(range.maxFreq) Hz, \(range.minDB)-\(range.maxDB) dB")
                    minFreq = range.minFreq
                    maxFreq = range.maxFreq
                    minDB   = range.minDB
                    maxDB   = range.maxDB
                    minFreqInput = String(format: "%.0f", range.minFreq)
                    maxFreqInput = String(format: "%.0f", range.maxFreq)
                    minDBInput   = String(format: "%.0f", range.minDB)
                    maxDBInput   = String(format: "%.0f", range.maxDB)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        tap.loadedAxisRange = nil
                        tap.loadedMinFreq = nil
                        tap.loadedMaxFreq = nil
                        tap.loadedMinDB   = nil
                        tap.loadedMaxDB   = nil
                    }
                }
            }
            .onReceive(tap.$loadedTapDetectionThreshold) { threshold in
                if threshold != nil {
                    print("  ⬇️ View received loadedTapDetectionThreshold: \(threshold!)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedTapDetectionThreshold = nil }
                }
            }
            .onReceive(tap.$loadedHysteresisMargin) { hysteresis in
                if hysteresis != nil {
                    print("  ⬇️ View received loadedHysteresisMargin: \(hysteresis!)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedHysteresisMargin = nil }
                }
            }
            .onReceive(tap.$loadedNumberOfTaps) { taps in
                if taps != nil {
                    print("  ⬇️ View received loadedNumberOfTaps: \(taps!)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedNumberOfTaps = nil }
                }
            }
            .onReceive(tap.$loadedPeakThreshold) { threshold in
                if let threshold = threshold {
                    print("  ⬇️ View received loadedPeakThreshold: \(threshold)")
                    TapDisplaySettings.peakThreshold = threshold
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedPeakThreshold = nil }
                }
            }
            .onReceive(tap.$loadedShowUnknownModes) { showUnknown in
                if let showUnknown = showUnknown {
                    print("  ⬇️ View received loadedShowUnknownModes: \(showUnknown)")
                    TapDisplaySettings.showUnknownModes = showUnknown
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedShowUnknownModes = nil }
                }
            }
            .onReceive(tap.$loadedGuitarType) { guitarType in
                if let guitarType = guitarType {
                    print("  ⬇️ View received loadedGuitarType: \(guitarType.rawValue)")
                    TapDisplaySettings.guitarType = guitarType
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedGuitarType = nil }
                }
            }
            .onReceive(tap.$loadedMeasurementType) { measurementType in
                if let measurementType = measurementType {
                    print("  ⬇️ View received loadedMeasurementType: \(measurementType.shortName)")
                    TapDisplaySettings.measurementType = measurementType
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedMeasurementType = nil }
                }
            }
            .onReceive(tap.$loadedSelectedLongitudinalPeakID) { peakID in
                if let peakID = peakID {
                    print("  ⬇️ View received loadedSelectedLongitudinalPeakID: \(peakID)")
                    selectedLongitudinalPeakID = peakID
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedSelectedLongitudinalPeakID = nil }
                }
            }
            .onReceive(tap.$loadedSelectedCrossPeakID) { peakID in
                if let peakID = peakID {
                    print("  ⬇️ View received loadedSelectedCrossPeakID: \(peakID)")
                    selectedCrossPeakID = peakID
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedSelectedCrossPeakID = nil }
                }
            }
            .onReceive(tap.$loadedSelectedFlcPeakID) { peakID in
                if let peakID = peakID {
                    print("  ⬇️ View received loadedSelectedFlcPeakID: \(peakID)")
                    selectedFlcPeakID = peakID
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedSelectedFlcPeakID = nil }
                }
            }
            .onReceive(tap.$loadedPlateLength) { length in
                if let length = length {
                    print("  ⬇️ View received loadedPlateLength: \(length)mm")
                    if TapDisplaySettings.measurementType.isBrace {
                        TapDisplaySettings.braceLength = length
                    } else {
                        TapDisplaySettings.plateLength = length
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedPlateLength = nil }
                }
            }
            .onReceive(tap.$loadedPlateWidth) { width in
                if let width = width {
                    if TapDisplaySettings.measurementType.isBrace {
                        TapDisplaySettings.braceWidth = width
                    } else {
                        TapDisplaySettings.plateWidth = width
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedPlateWidth = nil }
                }
            }
            .onReceive(tap.$loadedPlateThickness) { thickness in
                if let thickness = thickness {
                    if TapDisplaySettings.measurementType.isBrace {
                        TapDisplaySettings.braceThickness = thickness
                    } else {
                        TapDisplaySettings.plateThickness = thickness
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedPlateThickness = nil }
                }
            }
            .onReceive(tap.$loadedPlateMass) { mass in
                if let mass = mass {
                    if TapDisplaySettings.measurementType.isBrace {
                        TapDisplaySettings.braceMass = mass
                    } else {
                        TapDisplaySettings.plateMass = mass
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedPlateMass = nil }
                }
            }
            .onReceive(tap.$loadedGuitarBodyLength) { value in
                if let value = value {
                    TapDisplaySettings.guitarBodyLength = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedGuitarBodyLength = nil }
                }
            }
            .onReceive(tap.$loadedGuitarBodyWidth) { value in
                if let value = value {
                    TapDisplaySettings.guitarBodyWidth = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedGuitarBodyWidth = nil }
                }
            }
            .onReceive(tap.$loadedPlateStiffnessPreset) { preset in
                if let preset = preset {
                    TapDisplaySettings.plateStiffnessPreset = preset
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedPlateStiffnessPreset = nil }
                }
            }
            .onReceive(tap.$loadedCustomPlateStiffness) { value in
                if let value = value {
                    TapDisplaySettings.customPlateStiffness = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedCustomPlateStiffness = nil }
                }
            }
            .onReceive(tap.$loadedMeasureFlc) { value in
                if let value = value {
                    TapDisplaySettings.measureFlc = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedMeasureFlc = nil }
                }
            }
            .onReceive(tap.$loadedBraceLength) { value in
                if let value = value {
                    TapDisplaySettings.braceLength = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedBraceLength = nil }
                }
            }
            .onReceive(tap.$loadedBraceWidth) { value in
                if let value = value {
                    TapDisplaySettings.braceWidth = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedBraceWidth = nil }
                }
            }
            .onReceive(tap.$loadedBraceThickness) { value in
                if let value = value {
                    TapDisplaySettings.braceThickness = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedBraceThickness = nil }
                }
            }
            .onReceive(tap.$loadedBraceMass) { value in
                if let value = value {
                    TapDisplaySettings.braceMass = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedBraceMass = nil }
                }
            }
            .onReceive(tap.$autoSelectedLongitudinalPeakID) { peakID in
                if let peakID = peakID {
                    selectedLongitudinalPeakID = peakID
                    if let peak = tap.longitudinalPeaks.first(where: { $0.id == peakID }) {
                        expandFreqRange(peak.frequency)
                    }
                }
            }
            .onReceive(tap.$autoSelectedCrossPeakID) { peakID in
                if let peakID = peakID {
                    selectedCrossPeakID = peakID
                    if let peak = tap.crossPeaks.first(where: { $0.id == peakID }) {
                        expandFreqRange(peak.frequency)
                    }
                }
            }
            .onReceive(tap.$autoSelectedFlcPeakID) { peakID in
                if let peakID = peakID {
                    selectedFlcPeakID = peakID
                    if let peak = tap.flcPeaks.first(where: { $0.id == peakID }) {
                        expandFreqRange(peak.frequency)
                    }
                }
            }
    }
}

/// Applies `.onReceive`/`.onChange` modifiers that drive the auto-scale dB feature.
private struct AutoScaleModifier: ViewModifier {
    @ObservedObject var fft: RealtimeFFTAnalyzer
    @ObservedObject var tap: TapToneAnalyzer
    @Binding var isAutoScaleEnabled: Bool
    let autoScaleAction: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(fft.$magnitudes) { newMagnitudes in
                let hasValidData = !newMagnitudes.isEmpty && newMagnitudes.contains { $0 > -99 }
                if isAutoScaleEnabled && hasValidData && fft.isRunning {
                    autoScaleAction()
                }
            }
            .onChange(of: fft.isRunning) { _, isNowRunning in
                if isNowRunning && isAutoScaleEnabled {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if isAutoScaleEnabled && fft.isRunning {
                            print("🔄 Auto-scale: Performing initial scale on analyzer start")
                            autoScaleAction()
                        }
                    }
                }
            }
            .onChange(of: tap.isMeasurementComplete) { _, isComplete in
                if isComplete && isAutoScaleEnabled {
                    isAutoScaleEnabled = false
                    print("🔄 Auto-scale dB disabled - measurement complete")
                }
            }
    }
}

/// Applies lifecycle modifiers: `.onAppear`, platform-specific window/scene observers,
/// microphone permission alert, and file-import alerts.
private struct LifecycleModifier: ViewModifier {
    @ObservedObject var fft: RealtimeFFTAnalyzer
    @ObservedObject var tap: TapToneAnalyzer
    let isAutoScaleEnabled: Bool
    @Binding var warningIconOpacity: Double
    @Binding var showingMicrophonePermissionAlert: Bool
    @Binding var openURLImportSuccess: String?
    @Binding var openURLImportError: String?
    let toggleAnalyzer: () -> Void
    let startAnalyzer: () -> Void
    let importMeasurementFromURL: (URL) -> Void

    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    func body(content: Content) -> some View {
        content
            .onChange(of: tap.showLoadedSettingsWarning) { _, active in
                if active {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        warningIconOpacity = 0.2
                    }
                } else {
                    withAnimation(.default) {
                        warningIconOpacity = 1.0
                    }
                }
            }
            .onAppear {
                // Auto-start the analyzer when the view first appears.
                // Guard against toggling off an already-running engine — on macOS, closing the
                // window hides the view without destroying the @StateObject, so onAppear fires
                // again on reopen.  Calling toggleAnalyzer() when the engine is already running
                // would stop it, leaving the app in a permanently-stalled "Starting..." state.
                if !fft.isRunning {
                    toggleAnalyzer()
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
            .onChange(of: fft.microphonePermissionDenied) { _, isDenied in
                // Fired when the 3-second post-start TCC check confirms permission is denied.
                // This catches the macOS TCC cache lag case where authorizationStatus briefly
                // reports .authorized after a forced restart even though the mic is still blocked.
                if isDenied {
                    showingMicrophonePermissionAlert = true
                    fft.microphonePermissionDenied = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { _ in
                // Stop the engine when the window is minimized to the Dock and restart when restored.
                // This mirrors the iOS background behaviour and avoids unnecessary CPU/audio use
                // while the window is hidden.
                if fft.isRunning { tap.stop() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { _ in
                if !fft.isRunning { startAnalyzer() }
            }
            #endif
            #if os(iOS)
            // Stop the engine when the app moves to the background (iOS will suspend audio anyway,
            // and keeping AVAudioEngine running burns battery and risks an OS kill).
            // Restart automatically when the scene becomes active again.
            // Note: .inactive fires for many transient system overlays (alerts, Control Centre,
            // notifications) — stopping/restarting on those causes a false tap from the audio
            // engine reinitialising.  Only .background signals a genuine move out of foreground.
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    if fft.isRunning { tap.stop() }
                case .active:
                    if !fft.isRunning { toggleAnalyzer() }
                default:
                    break
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
}

// MARK: - Preview

#Preview {
    TapToneAnalysisView()
}
