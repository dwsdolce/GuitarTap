//
//  TapSettingsView.swift
//  GuitarTap
//

/// # TapSettingsView
///
/// Settings sheet for spectrum display range, analysis parameters,
/// measurement type, material dimensions, and audio device selection.
///
/// ## Settings Groups
///
/// | Section | Parameters |
/// |---|---|
/// | Measurement Type | Guitar type, plate/brace selection; updates mode-frequency ranges |
/// | Display Range | Min/max frequency (Hz) and dB range; validated text-field input |
/// | Analysis Range | Analysis min/max frequency; peak threshold (dBFS); max peaks |
/// | Material Dimensions | Plate/brace length, width, thickness (mm), mass (g) |
/// | Gore Thicknessing | Guitar body length, target frequencies for thicknessing model |
/// | FLC Measurement | Measure FLC (diagonal) shear mode toggle |
/// | Unknown Modes | Toggle display of guitar peaks outside the known mode bands |
/// | Audio Device | Microphone / input device picker (`RealtimeFFTAnalyzer.availableDevices`) |
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
    @Binding var peakThreshold: Float
    @Binding var maxPeaks: Int

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
    @State var peakThresholdInput: String
    @State var maxPeaksInput: String
    @State var captureAllPeaks: Bool

    // Measurement type setting
    @State var selectedMeasurementType: MeasurementType = TapDisplaySettings.measurementType

    // Unknown mode display setting
    @State var showUnknownModes: Bool = TapDisplaySettings.showUnknownModes

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
    var onApply: (() -> Void)?

    init(minFreq: Binding<Float>,
         maxFreq: Binding<Float>,
         minDB: Binding<Float>,
         maxDB: Binding<Float>,
         analysisMinFreq: Binding<Float>,
         analysisMaxFreq: Binding<Float>,
         peakThreshold: Binding<Float>,
         maxPeaks: Binding<Int>,
         fftAnalyzer: RealtimeFFTAnalyzer,
         onApply: (() -> Void)? = nil) {

        self._minFreq = minFreq
        self._maxFreq = maxFreq
        self._minDB = minDB
        self._maxDB = maxDB
        self._analysisMinFreq = analysisMinFreq
        self._analysisMaxFreq = analysisMaxFreq
        self._peakThreshold = peakThreshold
        self._maxPeaks = maxPeaks
        self.fftAnalyzer = fftAnalyzer
        self.onApply = onApply

        // Initialize display range inputs from persisted settings, not the current pan/zoomed session state
        self._minFreqInput = State(initialValue: String(format: "%.0f", TapDisplaySettings.minFrequency))
        self._maxFreqInput = State(initialValue: String(format: "%.0f", TapDisplaySettings.maxFrequency))
        self._minDBInput = State(initialValue: String(format: "%.0f", TapDisplaySettings.minMagnitude))
        self._maxDBInput = State(initialValue: String(format: "%.0f", TapDisplaySettings.maxMagnitude))
        self._analysisMinFreqInput = State(initialValue: String(format: "%.0f", analysisMinFreq.wrappedValue))
        self._analysisMaxFreqInput = State(initialValue: String(format: "%.0f", analysisMaxFreq.wrappedValue))
        self._peakThresholdInput = State(initialValue: String(format: "%.0f", peakThreshold.wrappedValue))

        // Initialize maxPeaks input - 0 means "all peaks"
        let peaksValue = maxPeaks.wrappedValue
        self._captureAllPeaks = State(initialValue: peaksValue == 0)
        self._maxPeaksInput = State(initialValue: peaksValue == 0 ? "All" : "\(peaksValue)")
    }

    var body: some View {
        NavigationStack {
            Form {
                measurementTypeSection
                displayRangeSection
                analysisSettingsSection
                audioInputSection
                fftProcessingSection
                aboutSection
            }
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
                    Button("Apply") {
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
        peakThreshold: .constant(-60),
        maxPeaks: .constant(10),
        fftAnalyzer: RealtimeFFTAnalyzer(fftSize: 8192, targetSampleRate: 48000)
    )
}
