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
// @parity view/main

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

    @State var measurementName: String = ""
    @State var notes: String = ""
    @State var isLandscape: Bool = true
    @State var showingSaveSheet = false
    @State var showingMeasurements = false
    @State var showingMetrics = false
    /// An export's chart could not be drawn, so nothing was written.
    @State var exportFailed = false
    @State var showingResults = false
    @State var showingSettings = false
    @State var showingHelp = false
    @State var showingHelpMenu = false
    @State var isExportingSpectrum = false
    @State var isSavingMeasurement = false
    @State var isGeneratingReport = false

    /// True while any file-export panel (spectrum PNG or PDF report) is in flight. The export
    /// actions guard on this so a repeated — or cross-type — click can't stack a second async,
    /// non-modal `NSSavePanel`. Cleared on every completion path, so it can't wedge.
    var isExportPanelInFlight: Bool { isExportingSpectrum || isGeneratingReport }
    @State var showingMicrophonePermissionAlert = false
    @State var engineStartError: String? = nil
    @State var showingPlayFileSheet = false
    @State private var openURLImportSuccess: String? = nil
    @State private var openURLImportError: String? = nil

    // Spectrum display state (loaded from persisted settings)
    @State var minFreq: Float = TapDisplaySettings.minFrequency
    @State var maxFreq: Float = TapDisplaySettings.maxFrequency
    @State var minDB: Float = TapDisplaySettings.minMagnitude
    @State var maxDB: Float = TapDisplaySettings.maxMagnitude
    @State var minFreqInput: String = FieldPrecision.string(TapDisplaySettings.minFrequency, FieldPrecision.frequencyHz)
    @State var maxFreqInput: String = FieldPrecision.string(TapDisplaySettings.maxFrequency, FieldPrecision.frequencyHz)
    @State var minDBInput: String = FieldPrecision.string(TapDisplaySettings.minMagnitude, FieldPrecision.magnitudeDB)
    @State var maxDBInput: String = FieldPrecision.string(TapDisplaySettings.maxMagnitude, FieldPrecision.magnitudeDB)
    /// The range a loaded measurement put on the chart (as widened onto its peaks), while the chart is
    /// still showing it; `nil` when no load is in view. A new measurement returns to the saved range
    /// only if the user has not moved the chart since the load.
    @State var loadedChartRange: DisplayRange.ChartRange? = nil

    // Auto-scale dB state
    @State var isAutoScaleEnabled = false

    #if os(iOS)
    // Crosshair cursor mode (iOS only)
    @State var crosshairMode = false
    // Wrong-platform guard: shown when the iOS build is run on macOS
    @State private var showingWrongPlatformAlert = false
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

    /// The analyzer state the button rule reads, gathered from the model and this view.
    ///
    /// The rule itself lives in `ButtonEnablement.swift` so the view and the
    /// button-enablement test exercise ONE implementation — mirrors web, where `App.tsx`
    /// and `button-enablement.test.ts` both import `buttonRule`.
    var buttonState: ButtonState {
        ButtonState(detectionState: tapToneAnalyzer.detectionState,
                    isMeasurementComplete: tapToneAnalyzer.isMeasurementComplete,
                    isReadyForDetection: tapToneAnalyzer.isReadyForDetection,
                    fftIsRunning: fft.isRunning,
                    displayMode: tapToneAnalyzer.displayMode,
                    measurementType: TapDisplaySettings.measurementType,
                    materialTapPhase: tapToneAnalyzer.materialTapPhase,
                    numberOfTaps: tapToneAnalyzer.numberOfTaps,
                    isPlayingFile: fft.isPlayingFile)
    }

    /// The tap-count control is locked once a tap has been captured, so the total cannot change
    /// mid-measurement; it unlocks when the measurement completes. Python's
    /// `tap_num_spin.setEnabled` and web's `tapsLocked` compute the same thing.
    ///
    /// Deliberately NOT part of `buttonRule`: that rule answers which of the three ACTION buttons
    /// are live, and a numeric input's lock is a different question about a different control.
    var tapCountLocked: Bool {
        tapToneAnalyzer.currentTapCount > 0 && !tapToneAnalyzer.isMeasurementComplete
    }

    /// Cancel restarts the current sequence; it's offered during a review phase (where it
    /// acts as "Redo") or while an active multi-step sequence is in progress.
    var cancelButtonEnabled: Bool { buttonRule(buttonState).cancelEnabled }

    /// Pause/Resume button is enabled during any active tap detection sequence.
    /// During a review phase it acts as "Accept" and is always enabled.
    var pauseResumeButtonEnabled: Bool { buttonRule(buttonState).pauseEnabled }

    /// New Tap starts a fresh measurement, so it's disabled only while a sequence is in
    /// flight (capturing, paused, or reviewing) and enabled otherwise: once a measurement
    /// is complete *and* in the disarmed-idle state the Dump Capture Audio folder guard can
    /// produce, so the user can re-arm.  Always enabled in comparison mode; disabled
    /// when the FFT isn't running/ready.
    var newTapButtonDisabled: Bool { buttonRule(buttonState).newTapDisabled }

    /// Creates the view and its paired audio analyzers.
    ///
    /// A single `RealtimeFFTAnalyzer` is constructed and passed to both
    /// `@StateObject` wrappers so they share the same audio engine instance.
    /// The FFT size is a constant inside `RealtimeFFTAnalyzer` (65 536 points,
    /// ≈0.73 Hz/bin at 48 kHz).
    init() {
        // Create a single FFT analyzer instance.
        // FFT size (65 536) is a constant inside RealtimeFFTAnalyzer.
        let fft = RealtimeFFTAnalyzer()

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
                                            loadedChartRange: $loadedChartRange,
                                            expandFreqRange: expandFreqRangeToInclude))
            // A new sequence (New Tap, Play File, Cancel, a re-arm) after a load or a comparison returns
            // the chart to the saved range, unless the user has moved it since. startTapSequence is the
            // only place isMeasurementComplete is set false, and @Published announces every assignment,
            // so each false is a sequence start (onChange would see only a change from true).
            .onReceive(tapToneAnalyzer.$isMeasurementComplete) { isComplete in
                if !isComplete { applyNewMeasurementRange() }
            }
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
        .sheet(isPresented: $showingPlayFileSheet) {
            PlayFileSheet { audioURL, calibrationURL in
                #if os(macOS)
                MeasurementFileExporter.lastUsedDirectory = audioURL.deletingLastPathComponent()
                #endif
                openAudioFile(audioURL, calibrationURL: calibrationURL)
            }
        }
        .alert("Export Failed", isPresented: $exportFailed) {
            Button("OK") { }
        } message: {
            Text(ExportRenderError.message)
        }
        #if os(macOS)
            .focusedSceneValue(\.menuActions, menuActions)
            .onAppear { bindMenuActions() }
            .onChange(of: tap.hasResultToSaveOrExport, initial: true) { _, hasResult in
                menuActions.hasResultToSaveOrExport = hasResult
            }
            .alert("Audio Engine Error", isPresented: Binding(
                get: { engineStartError != nil },
                set: { if !$0 { engineStartError = nil } }
            )) {
                Button("OK", role: .cancel) { engineStartError = nil }
            } message: {
                Text(engineStartError ?? "")
            }
        #else
            .onAppear {
                if ProcessInfo.processInfo.isiOSAppOnMac {
                    showingWrongPlatformAlert = true
                }
            }
            .alert("Wrong Version", isPresented: $showingWrongPlatformAlert) {
                Button("Quit") {
                    exit(0)
                }
            } message: {
                Text("You are running the iOS version of GuitarTap on a Mac. Please install the Mac version from the App Store or TestFlight for the best experience.")
            }
        #endif
    }

    // MARK: - Menu Actions (macOS only)

    #if os(macOS)
    /// Populate the stable `MenuActions` object with closures that capture
    /// `self`.  Called once from `onAppear`; the `MenuActions` instance itself
    /// never changes, so `AppCommands` does not see a new focused value on
    /// every audio frame.
    private func bindMenuActions() {
        menuActions.openAudioFile     = { showingPlayFileSheet = true }
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
            openURLImportSuccess = try tapToneAnalyzer.importAndLoadMeasurements(from: data)
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
    @Binding var loadedChartRange: DisplayRange.ChartRange?
    let expandFreqRange: (Float) -> Void

    func body(content: Content) -> some View {
        content
            // Single receiver for all four axis bounds — applying them together in one
            // render pass prevents transient states where e.g. minDB has the new value
            // while maxDB is still old, which caused SwiftUI Charts to clamp every data
            // point to the same level and render spurious vertical line artifacts.
            .onReceive(tap.$loadedAxisRange) { range in
                if let range = range {
                    gtLog("  ⬇️ View received loadedAxisRange: \(range.minFreq)-\(range.maxFreq) Hz, \(range.minDB)-\(range.maxDB) dB")
                    minFreq = range.minFreq
                    maxFreq = range.maxFreq
                    minDB   = range.minDB
                    maxDB   = range.maxDB
                    minFreqInput = FieldPrecision.string(range.minFreq, FieldPrecision.frequencyHz)
                    maxFreqInput = FieldPrecision.string(range.maxFreq, FieldPrecision.frequencyHz)
                    minDBInput   = FieldPrecision.string(range.minDB, FieldPrecision.magnitudeDB)
                    maxDBInput   = FieldPrecision.string(range.maxDB, FieldPrecision.magnitudeDB)
                    loadedChartRange = DisplayRange.ChartRange(minFreq: range.minFreq, maxFreq: range.maxFreq,
                                                               minDB: range.minDB, maxDB: range.maxDB)
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
                    gtLog("  ⬇️ View received loadedTapDetectionThreshold: \(threshold!)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedTapDetectionThreshold = nil }
                }
            }
            .onReceive(tap.$loadedNumberOfTaps) { taps in
                if taps != nil {
                    gtLog("  ⬇️ View received loadedNumberOfTaps: \(taps!)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedNumberOfTaps = nil }
                }
            }
            .onReceive(tap.$loadedPeakThreshold) { threshold in
                if let threshold = threshold {
                    gtLog("  ⬇️ View received loadedPeakThreshold: \(threshold)")
                    TapDisplaySettings.peakMinThreshold = threshold
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedPeakThreshold = nil }
                }
            }
            .onReceive(tap.$loadedShowUnknownModes) { showUnknown in
                if let showUnknown = showUnknown {
                    gtLog("  ⬇️ View received loadedShowUnknownModes: \(showUnknown)")
                    TapDisplaySettings.showUnknownModes = showUnknown
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedShowUnknownModes = nil }
                }
            }
            .onReceive(tap.$loadedGuitarType) { guitarType in
                if let guitarType = guitarType {
                    gtLog("  ⬇️ View received loadedGuitarType: \(guitarType.rawValue)")
                    TapDisplaySettings.guitarType = guitarType
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedGuitarType = nil }
                }
            }
            .onReceive(tap.$loadedMeasurementType) { measurementType in
                if let measurementType = measurementType {
                    gtLog("  ⬇️ View received loadedMeasurementType: \(measurementType.shortName)")
                    TapDisplaySettings.measurementType = measurementType
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedMeasurementType = nil }
                }
            }
            .onReceive(tap.$loadedSelectedLongitudinalPeakID) { peakID in
                if let peakID = peakID {
                    gtLog("  ⬇️ View received loadedSelectedLongitudinalPeakID: \(peakID)")
                    selectedLongitudinalPeakID = peakID
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedSelectedLongitudinalPeakID = nil }
                }
            }
            .onReceive(tap.$loadedSelectedCrossPeakID) { peakID in
                if let peakID = peakID {
                    gtLog("  ⬇️ View received loadedSelectedCrossPeakID: \(peakID)")
                    selectedCrossPeakID = peakID
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedSelectedCrossPeakID = nil }
                }
            }
            .onReceive(tap.$loadedSelectedFlcPeakID) { peakID in
                if let peakID = peakID {
                    gtLog("  ⬇️ View received loadedSelectedFlcPeakID: \(peakID)")
                    selectedFlcPeakID = peakID
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tap.loadedSelectedFlcPeakID = nil }
                }
            }
            .onReceive(tap.$selectedLongitudinalPeak) { peak in
                if let peak {
                    selectedLongitudinalPeakID = peak.id
                    expandFreqRange(peak.frequency)
                }
            }
            .onReceive(tap.$selectedCrossPeak) { peak in
                if let peak {
                    selectedCrossPeakID = peak.id
                    expandFreqRange(peak.frequency)
                }
            }
            .onReceive(tap.$selectedFlcPeak) { peak in
                if let peak {
                    selectedFlcPeakID = peak.id
                    expandFreqRange(peak.frequency)
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
                            gtLog("🔄 Auto-scale: Performing initial scale on analyzer start")
                            autoScaleAction()
                        }
                    }
                }
            }
            .onChange(of: tap.isMeasurementComplete) { _, isComplete in
                if isComplete && isAutoScaleEnabled {
                    isAutoScaleEnabled = false
                    gtLog("🔄 Auto-scale dB disabled - measurement complete")
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
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                // Stop the engine when the *main* window is closed.  On macOS with a single
                // Window scene, closing hides the view without destroying the @StateObject, so
                // deinit never fires.  Without this handler the audio engine runs indefinitely
                // in the background after the window is dismissed.  Mirrors the iOS .background
                // handler.
                //
                // IMPORTANT: NSWindow.willCloseNotification fires for every window, including
                // sheets, popovers, share panels, and the Help/Measurements windows.
                //
                // We must not use `NSApplication.shared.mainWindow` as the identity check:
                // it is unreliable because it transiently points to whichever window is
                // currently key — including the AirDrop share panel — so dismissing a share
                // sheet can spuriously stop the engine.
                //
                // Instead, identify the main app window by:
                //   1. Not being an NSPanel subclass (share sheets, colour pickers, etc. are panels).
                //   2. Having the app's known main-window title (excludes the Help window).
                guard let closingWindow = notification.object as? NSWindow,
                      !closingWindow.isKind(of: NSPanel.self),
                      closingWindow.title == appTitle else { return }
                if fft.isRunning { tap.stop() }
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
                    // Use startAnalyzer() directly rather than toggleAnalyzer(): permission is
                    // already established (the engine was running before backgrounding), so the
                    // async permission-check round-trip in toggleAnalyzer() is unnecessary and
                    // would trigger a spurious route-change restart + 3 s settle on every resume.
                    // Mirrors the macOS deminimize handler which also calls startAnalyzer() directly.
                    if !fft.isRunning { startAnalyzer() }
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
            // The load's microphone warning — its microphone not found, a different recording
            // setup, or a microphone that cannot be opened — under the title set with it. The
            // alert is on the main view so it survives the Measurements sheet dismissing.
            .alert(tap.microphoneWarningTitle, isPresented: Binding(
                get: { tap.microphoneWarning != nil },
                set: { if !$0 { tap.microphoneWarning = nil } }
            )) {
                Button("OK") { tap.microphoneWarning = nil }
            } message: {
                Text(tap.microphoneWarning ?? "")
            }
            // A microphone switched to while running (plugged in, or a fallback) that cannot be
            // opened — the previous one is kept. Settings shows its own while the sheet is open.
            .alert("Microphone Unavailable", isPresented: Binding(
                get: { fft.inputDeviceOpenFailure != nil },
                set: { if !$0 { fft.inputDeviceOpenFailure = nil } }
            )) {
                Button("OK") { fft.inputDeviceOpenFailure = nil }
            } message: {
                Text(fft.inputDeviceOpenFailure ?? "")
            }
    }
}

// MARK: - Preview

#Preview {
    TapToneAnalysisView()
}
