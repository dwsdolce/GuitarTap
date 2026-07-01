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
/// | Analysis Range | Analysis min/max frequency; peak threshold (dBFS); max peaks; hysteresis margin |
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
    @Binding var analysisMinFreq: Float
    @Binding var analysisMaxFreq: Float
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
    @State var analysisMinFreqInput: String
    @State var analysisMaxFreqInput: String
    @State var peakMinThresholdInput: String

    // Measurement type setting
    @State var selectedMeasurementType: MeasurementType = TapDisplaySettings.measurementType

    // Unknown mode display setting
    @State var showUnknownModes: Bool = TapDisplaySettings.showUnknownModes

    // WAV dump toggle (diagnostics)
    @State var dumpCaptureAudio: Bool = TapDisplaySettings.dumpCaptureAudio

    // Plate dimensions (for plate measurement type)
    @State var plateLengthInput: String = String(format: "%.1f", TapDisplaySettings.plateLength)
    @State var plateWidthInput: String = String(format: "%.1f", TapDisplaySettings.plateWidth)
    @State var plateThicknessInput: String = String(format: "%.2f", TapDisplaySettings.plateThickness)
    @State var plateMassInput: String = String(format: "%.1f", TapDisplaySettings.plateMass)
    @State var measureFlc: Bool = TapDisplaySettings.measureFlc

    // Gore thicknessing settings
    @State var guitarBodyLengthInput: String = String(format: "%.0f", TapDisplaySettings.guitarBodyLength)
    @State var guitarBodyWidthInput: String = String(format: "%.0f", TapDisplaySettings.guitarBodyWidth)
    @State var plateStiffnessPreset: PlateStiffnessPreset = TapDisplaySettings.plateStiffnessPreset
    @State var customPlateStiffnessInput: String = String(format: "%.0f", TapDisplaySettings.customPlateStiffness)

    // Brace dimensions (for Brace measurement type)
    @State var braceLengthInput: String = String(format: "%.1f", TapDisplaySettings.braceLength)
    @State var braceWidthInput: String = String(format: "%.1f", TapDisplaySettings.braceWidth)
    @State var braceThicknessInput: String = String(format: "%.1f", TapDisplaySettings.braceThickness)
    @State var braceMassInput: String = String(format: "%.1f", TapDisplaySettings.braceMass)

    // Validation states
    @State var showValidationError = false
    @State var validationMessage = ""

    // Calibration states
    @State var showingCalibrationImporter = false
    @State var storedCalibrations: [MicrophoneCalibration] = []
    @State var calibrationImportError: String?
    @State var showingCalibrationError = false
    @State var selectedCalibrationID: UUID?
    @State var showingDeleteAllCalibrationsConfirmation = false

    // Advanced section expansion state
    @State private var showingAdvanced = false

    // Computed property for compact layout
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
    /// The `Bool` parameter is `true` when the measurement type or FLC toggle changed,
    /// indicating that the current measurement should be cancelled and restarted.
    var onApply: ((_ measurementChanged: Bool) -> Void)?

    init(minFreq: Binding<Float>,
         maxFreq: Binding<Float>,
         minDB: Binding<Float>,
         maxDB: Binding<Float>,
         analysisMinFreq: Binding<Float>,
         analysisMaxFreq: Binding<Float>,
         peakMinThreshold: Binding<Float>,
         fftAnalyzer: RealtimeFFTAnalyzer,
         onApply: ((_ measurementChanged: Bool) -> Void)? = nil) {

        self._minFreq = minFreq
        self._maxFreq = maxFreq
        self._minDB = minDB
        self._maxDB = maxDB
        self._analysisMinFreq = analysisMinFreq
        self._analysisMaxFreq = analysisMaxFreq
        self._peakMinThreshold = peakMinThreshold
        self.fftAnalyzer = fftAnalyzer
        self.onApply = onApply

        // Initialize display range inputs from persisted settings, not the current pan/zoomed session state
        self._minFreqInput = State(initialValue: String(format: "%.0f", TapDisplaySettings.minFrequency))
        self._maxFreqInput = State(initialValue: String(format: "%.0f", TapDisplaySettings.maxFrequency))
        self._minDBInput = State(initialValue: String(format: "%.0f", TapDisplaySettings.minMagnitude))
        self._maxDBInput = State(initialValue: String(format: "%.0f", TapDisplaySettings.maxMagnitude))
        self._analysisMinFreqInput = State(initialValue: String(format: "%.0f", analysisMinFreq.wrappedValue))
        self._analysisMaxFreqInput = State(initialValue: String(format: "%.0f", analysisMaxFreq.wrappedValue))
        self._peakMinThresholdInput = State(initialValue: String(format: "%.0f", peakMinThreshold.wrappedValue))
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
        analysisMinFreq: .constant(50),
        analysisMaxFreq: .constant(2000),
        peakMinThreshold: .constant(-60),
        fftAnalyzer: RealtimeFFTAnalyzer()
    )
}
