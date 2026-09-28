//
//  TapSettingsView.swift
//  GuitarTap
//
// @parity view/settings

/// # TapSettingsView
///
/// Settings sheet for spectrum display range, analysis parameters,
/// measurement type, material dimensions, and audio device selection.
///
/// ## Settings Groups
///
/// | Section | Parameters |
/// |---|---|
/// | Measurement Type | Guitar type, plate/brace selection; mode-frequency ranges; unknown-modes toggle (guitar); plate/brace dimensions, FLC toggle, Gore body dimensions, stiffness preset (plate); brace dimensions (brace) |
/// | Display Range | Min/max frequency (Hz) and dB range; validated text-field input |
/// | Analysis Range | Show-unknown-modes toggle (guitar); analysis min/max frequency; peak detection minimum (dBFS); dump-capture-audio toggle |
/// | Audio Input & Calibration | Microphone / input device picker; calibration import, selection, and deletion |
/// | About & Help | App version, copyright, help link |
///
/// ## Validation
///
/// All numeric fields use companion `@State` text strings initialized from the
/// bound `Float`/`Int` values in `init`. Changes are validated and applied when
/// the user taps the Apply button (or dismisses on iOS). Invalid or
/// out-of-range inputs revert to the last good value. Pressing Apply calls
/// `onApply` which triggers `TapToneAnalyzer.reclassifyPeaks()` to refresh
/// results with the new ranges.
///
/// ## Calibration Import
///
/// A UMIK-1 microphone calibration file (`.txt`, one frequency/dB pair per
/// line) can be imported via the file importer; the data is parsed by
/// `MicrophoneCalibration` and stored in `RealtimeFFTAnalyzer`.
///
/// ## File Organisation
///
/// | File | Contents |
/// |---|---|
/// | `TapSettingsView.swift` | Properties, `init`, `body` |
/// | `TapSettingsView+Sections.swift` | Six `@ViewBuilder` form-section properties |
/// | `TapSettingsView+LayoutHelpers.swift` | `compactFrequencyRangeView`, `regularFrequencyRangeView`, `modeRangeRow` |
/// | `TapSettingsView+Actions.swift` | Validation, persistence, and calibration-management actions |
///
/// - SeeAlso: `TapDisplaySettings`, `MicrophoneCalibration`

import SwiftUI
internal import UniformTypeIdentifiers

/// Settings sheet for spectrum display and analysis parameters.
struct TapSettingsView: View {
    // Display settings
    @Binding var minFreq: Float
    @Binding var maxFreq: Float
    @Binding var minDB: Float
    @Binding var maxDB: Float

    // Analysis settings
    @Binding var peakMinThreshold: Float

    // FFT Analyzer for audio device selection
    @ObservedObject var fftAnalyzer: RealtimeFFTAnalyzer

    // Dismiss action
    @Environment(\.dismiss) var dismiss

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    // Local state for text input
    @State var minFreqInput: String
    @State var maxFreqInput: String
    @State var minDBInput: String
    @State var maxDBInput: String
    @State var peakMinThresholdInput: String

    // Measurement type setting
    @State var selectedMeasurementType: MeasurementType = TapDisplaySettings.measurementType

    // Unknown mode display setting
    @State var showUnknownModes: Bool = TapDisplaySettings.showUnknownModes

    // WAV dump toggle (diagnostics)
    @State var dumpCaptureAudio: Bool = TapDisplaySettings.dumpCaptureAudio

    // Plate dimensions (for plate measurement type)
    @State var plateLengthInput: String = FieldPrecision.string(TapDisplaySettings.plateLength, FieldPrecision.linearDimensionMM)
    @State var plateWidthInput: String = FieldPrecision.string(TapDisplaySettings.plateWidth, FieldPrecision.linearDimensionMM)
    @State var plateThicknessInput: String = FieldPrecision.string(TapDisplaySettings.plateThickness, FieldPrecision.linearDimensionMM)
    @State var plateMassInput: String = FieldPrecision.string(TapDisplaySettings.plateMass, FieldPrecision.massG)
    @State var measureFlc: Bool = TapDisplaySettings.measureFlc

    // Gore thicknessing settings
    @State var guitarBodyLengthInput: String = FieldPrecision.string(TapDisplaySettings.guitarBodyLength, FieldPrecision.bodyDimensionMM)
    @State var guitarBodyWidthInput: String = FieldPrecision.string(TapDisplaySettings.guitarBodyWidth, FieldPrecision.bodyDimensionMM)
    @State var plateStiffnessPreset: PlateStiffnessPreset = TapDisplaySettings.plateStiffnessPreset
    @State var customPlateStiffnessInput: String = FieldPrecision.string(TapDisplaySettings.customPlateStiffness, FieldPrecision.stiffness)

    // Brace dimensions (for Brace measurement type)
    @State var braceLengthInput: String = FieldPrecision.string(TapDisplaySettings.braceLength, FieldPrecision.linearDimensionMM)
    @State var braceWidthInput: String = FieldPrecision.string(TapDisplaySettings.braceWidth, FieldPrecision.linearDimensionMM)
    @State var braceThicknessInput: String = FieldPrecision.string(TapDisplaySettings.braceThickness, FieldPrecision.linearDimensionMM)
    @State var braceMassInput: String = FieldPrecision.string(TapDisplaySettings.braceMass, FieldPrecision.massG)

    // Validation states
    @State var showValidationError = false
    @State var validationMessage = ""

    // Dump Capture Audio folder — displayed path, refreshed after Change… / Use Default.
    @State var dumpFolderDisplayPath = WavDumpFolder.currentFolder.path

    // Calibration states
    @State var showingCalibrationImporter = false
    @State var storedCalibrations: [MicrophoneCalibration] = []
    @State var calibrationImportError: String?
    @State var showingCalibrationError = false
    @State var selectedCalibrationID: UUID?
    @State var showingDeleteAllCalibrationsConfirmation = false

    // Advanced section expansion state
    @State private var showingAdvanced = false

    /// Whether the layout should use the compact (narrow iOS) form.
    var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    /// App version string for the About section.
    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// Called when the user presses Apply (not Cancel).
    /// `measurementChanged` is `true` when the measurement type or FLC toggle changed, indicating the
    /// current measurement should be cancelled and restarted. `guitarTypeChanged` is `true` for a
    /// guitar-subtype change (e.g. Classical → Flamenco) that keeps the capture but re-derives
    /// classification and selection for the new type. Both false = a display-only Apply (Peak Min,
    /// dB, range) that must NOT disturb peaks, classification or selection.
    var onApply: ((_ measurementChanged: Bool, _ guitarTypeChanged: Bool) -> Void)?

    /// Binds the display/analysis values and seeds the companion text-input `@State`
    /// strings from persisted settings (not the current pan/zoomed session state).
    init(minFreq: Binding<Float>,
         maxFreq: Binding<Float>,
         minDB: Binding<Float>,
         maxDB: Binding<Float>,
         peakMinThreshold: Binding<Float>,
         fftAnalyzer: RealtimeFFTAnalyzer,
         onApply: ((_ measurementChanged: Bool, _ guitarTypeChanged: Bool) -> Void)? = nil) {

        self._minFreq = minFreq
        self._maxFreq = maxFreq
        self._minDB = minDB
        self._maxDB = maxDB
        self._peakMinThreshold = peakMinThreshold
        self.fftAnalyzer = fftAnalyzer
        self.onApply = onApply

        // Initialize display range inputs from persisted settings, not the current pan/zoomed session state
        self._minFreqInput = State(initialValue: FieldPrecision.string(TapDisplaySettings.minFrequency, FieldPrecision.frequencyHz))
        self._maxFreqInput = State(initialValue: FieldPrecision.string(TapDisplaySettings.maxFrequency, FieldPrecision.frequencyHz))
        self._minDBInput = State(initialValue: FieldPrecision.string(TapDisplaySettings.minMagnitude, FieldPrecision.magnitudeDB))
        self._maxDBInput = State(initialValue: FieldPrecision.string(TapDisplaySettings.maxMagnitude, FieldPrecision.magnitudeDB))
        self._peakMinThresholdInput = State(initialValue: FieldPrecision.string(peakMinThreshold.wrappedValue, FieldPrecision.magnitudeDB))
    }

    var body: some View {
        NavigationStack {
            Form {
                audioInputSection
                measurementTypeSection
                Section {
                    DisclosureGroup(isExpanded: $showingAdvanced) {
                        // Content intentionally empty — the two sub-sections
                        // below render at Form top-level so their headers
                        // appear outside the gray background.
                    } label: {
                        Label("Advanced", systemImage: "gearshape.2")
                            .font(.headline)
                    }
                    .disclosureGroupStyle(FormDisclosureGroupStyle())
                }
                if showingAdvanced {
                    Section {
                        displayRangeSectionContent
                    } header: {
                        Label("Display Settings", systemImage: "chart.xyaxis.line")
                            .font(.headline)
                    }
                    Section {
                        analysisSettingsSectionContent
                    } header: {
                        Label("Analysis Settings", systemImage: "waveform.path.ecg")
                            .font(.headline)
                    }
                }
                aboutSection
            }
            .legacyScrollers()
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 500, minHeight: 600)
            #endif
            .navigationTitle("Tap Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applySettings()
                    }
                    .fontWeight(.semibold)
                }
            }
            // A microphone chosen here that cannot be opened — the previous one is kept.
            .alert("Microphone Unavailable", isPresented: Binding(
                get: { fftAnalyzer.inputDeviceOpenFailure != nil },
                set: { if !$0 { fftAnalyzer.inputDeviceOpenFailure = nil } }
            )) {
                Button("OK") { fftAnalyzer.inputDeviceOpenFailure = nil }
            } message: {
                Text(fftAnalyzer.inputDeviceOpenFailure ?? "")
            }
            .alert("Invalid Settings", isPresented: $showValidationError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
            .alert("Calibration Import Error", isPresented: $showingCalibrationError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(calibrationImportError ?? "Unknown error")
            }
            .alert("Delete All Calibrations?", isPresented: $showingDeleteAllCalibrationsConfirmation) {
                Button("Delete All", role: .destructive) { deleteAllCalibrations() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all \(storedCalibrations.count) saved calibrations. This cannot be undone.")
            }
            .fileImporter(
                isPresented: $showingCalibrationImporter,
                allowedContentTypes: [.text, .plainText, .data, .calibrationFile],
                allowsMultipleSelection: false
            ) { result in
                handleCalibrationImport(result)
            }
            .onAppear {
                loadStoredCalibrations()
                selectedCalibrationID = fftAnalyzer.activeCalibration?.id
            }
        }
    }
}

// MARK: - Preview

#Preview {
    TapSettingsView(
        minFreq: .constant(75),
        maxFreq: .constant(350),
        minDB: .constant(-100),
        maxDB: .constant(0),
        peakMinThreshold: .constant(-60),
        fftAnalyzer: RealtimeFFTAnalyzer()
    )
}
