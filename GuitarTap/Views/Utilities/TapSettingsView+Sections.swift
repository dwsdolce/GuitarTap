//
//  TapSettingsView+Sections.swift
//  GuitarTap
//

/// # TapSettingsView+Sections
///
/// The sections of the `TapSettingsView` body, extracted as `@ViewBuilder` computed properties and
/// drawn with the sheet's own layout (`TapSettingsView+LayoutHelpers`).
///
/// ## Sections
///
/// | Property | Section |
/// |---|---|
/// | `audioInputSection` | Audio-input device picker, sample rate, calibration picker, import / delete all |
/// | `measurementTypeSection` | Measurement-type picker, then a titled box per group: mode ranges, or plate / brace dimensions and Gore |
/// | `advancedRow` | The Advanced disclosure row |
/// | `displaySettingsSection` | Appearance, display frequency and magnitude range, Save Current View / Reset |
/// | `analysisSettingsSection` | Show-unknown-modes, peak detection minimum, dump-capture-audio, Reset |
/// | `aboutSection` | App version, copyright, Quick Start Guide, User Manual |
///
/// - SeeAlso: `TapSettingsView`, `TapSettingsView+Actions`, `TapSettingsView+LayoutHelpers`

import SwiftUI
import AVFoundation

extension TapSettingsView {

    // MARK: - Audio Input & Calibration Section

    @ViewBuilder
    var audioInputSection: some View {
        if !inputDevices.isEmpty {
            settingsSection("Audio Input & Calibration", icon: "mic.fill",
                            note: "Audio input and calibration changes take effect immediately and are not affected by Cancel. Calibrations are automatically associated with each device.") {
                settingsRow("Audio Input Device") {
                    Picker("Audio Input Device", selection: Binding(
                        get: { selectedDevice },
                        set: { fftAnalyzer.selectedInputDevice = $0 }
                    )) {
                        ForEach(inputDevices) { device in
                            Text(device.name)
                                .tag(device as AVAudioDevice?)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .onChange(of: selectedDevice) { oldDevice, newDevice in
                        guard let device = newDevice, device.uid != oldDevice?.uid else { return }
                        gtLog("🔄 Device selection changed to: \(device.name)")
                        // Update calibration picker to reflect device's calibration
                        selectedCalibrationID = fftAnalyzer.activeCalibration?.id
                    }
                }

                if let selectedDevice {
                    settingsRow("Sample Rate") {
                        Text(formattedAsWholeHertz(selectedDevice.sampleRate))
                    }
                }

                settingsRow("Calibration") {
                    Picker("Calibration", selection: $selectedCalibrationID) {
                        Text("None (Uncalibrated)")
                            .tag(nil as UUID?)
                        ForEach(storedCalibrations) { calibration in
                            Text(calibration.name)
                                .tag(calibration.id as UUID?)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .onChange(of: selectedCalibrationID) { _, newID in
                        if let id = newID {
                            fftAnalyzer.activeCalibration = storedCalibrations.first { $0.id == id }
                        } else {
                            fftAnalyzer.activeCalibration = nil
                        }
                    }
                }

                // The active calibration's details
                if let calibration = activeCalibration {
                    HStack(alignment: .top) {
                        let details = calibration.details
                        VStack(alignment: .leading, spacing: 2) {
                            if let sensitivity = details.sensitivity {
                                Text(sensitivity)
                            }
                            Text(details.dataPoints)
                        }
                        Spacer()
                        if let range = details.range {
                            Text(range)
                        }
                    }
                    .font(SettingsType.caption)
                    .foregroundColor(Palette.color(.textSecondary))
                }

                settingsActionButtons {
                    Button {
                        showingCalibrationImporter = true
                    } label: {
                        Label("Import Calibration File…", systemImage: "doc.badge.plus")
                    }
                    if !storedCalibrations.isEmpty {
                        Button {
                            showingDeleteAllCalibrationsConfirmation = true
                        } label: {
                            Label("Delete All Calibrations", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Measurement Type Section

    /// The measurement type, then one titled box per group of its settings — the guitar's mode
    /// ranges, or a plate's or brace's dimensions.
    @ViewBuilder
    var measurementTypeSection: some View {
        settingsSection("Measurement Type",
                        icon: selectedMeasurementType.isGuitar ? "guitars" : "square.3.layers.3d",
                        note: selectedMeasurementType.isGuitar
                            ? "Select your guitar type for accurate mode classification."
                            : "Enter the dimensions and mass of your rectangular wood sample. The app will calculate stiffness, speed of sound, and radiation ratio from the tap frequencies.") {
            settingsRow("Measurement Type") {
                Picker("Measurement Type", selection: $selectedMeasurementType) {
                    ForEach(MeasurementType.allCases) { type in
                        Text(type.rawValue)
                            .tag(type)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .onChange(of: selectedMeasurementType) { _, newType in
                    // Load the stored frequency range for the new type (falls back to type defaults)
                    minFreqInput = FieldPrecision.string(TapDisplaySettings.minFrequency(for: newType), FieldPrecision.frequencyHz)
                    maxFreqInput = FieldPrecision.string(TapDisplaySettings.maxFrequency(for: newType), FieldPrecision.frequencyHz)
                }
            }
            settingsDescription(selectedMeasurementType.description)
        }

        // Guitar: the selected type's mode frequency ranges
        if selectedMeasurementType.isGuitar, let guitarType = selectedMeasurementType.guitarType {
            settingsGroup("Mode Frequency Ranges") {
                let ranges = guitarType.modeRanges
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        modeRangeRow("Air:", range: ranges.air)
                        modeRangeRow("Top:", range: ranges.top)
                        modeRangeRow("Back:", range: ranges.back)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        modeRangeRow("Dipole:", range: ranges.dipole)
                        modeRangeRow("Ring:", range: ranges.ringMode)
                    }
                }
                .font(SettingsType.caption)
                .padding(.vertical, 2)
            }
        }

        // Plate: its sample, the diagonal tap, and the Gore target's body and stiffness
        if selectedMeasurementType == .plate {
            settingsGroup("Sample Dimensions") {
                dimensionRow("Length (along grain)", text: $plateLengthInput, decimals: FieldPrecision.linearDimensionMM, unit: "mm")
                dimensionRow("Width (cross grain)", text: $plateWidthInput, decimals: FieldPrecision.linearDimensionMM, unit: "mm")
                dimensionRow("Thickness", text: $plateThicknessInput, decimals: FieldPrecision.linearDimensionMM, unit: "mm")
                dimensionRow("Mass", text: $plateMassInput, decimals: FieldPrecision.massG, unit: "g")
                densityRow(length: plateLengthInput, width: plateWidthInput, thickness: plateThicknessInput, mass: plateMassInput)
                settingsToggleRow("Measure Diagonal (fLC) Tap",
                                  description: "Add a 3rd tap: hold plate at midpoint of one long edge, tap near opposite corner. Measures shear stiffness for Gore target thickness.",
                                  isOn: $measureFlc)
            }

            settingsGroup("Gore Target Thickness — Body Dimensions") {
                settingsDescription("Finished guitar body dimensions used in Gore's Eq. 4.5-7 to calculate target plate thickness.")
                dimensionRow("Body Length (a)", text: $guitarBodyLengthInput, decimals: FieldPrecision.bodyDimensionMM, unit: "mm")
                dimensionRow("Lower Bout Width (b)", text: $guitarBodyWidthInput, decimals: FieldPrecision.bodyDimensionMM, unit: "mm")
            }

            settingsGroup("Plate Vibrational Stiffness (f_vs)") {
                settingsRow("Panel Type") {
                    Picker("Panel Type", selection: $plateStiffnessPreset) {
                        ForEach(PlateStiffnessPreset.allCases) { preset in
                            Text(preset.shortName).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                if plateStiffnessPreset == .custom {
                    settingsRow("Custom f_vs value") {
                        ValidatedNumberField(text: $customPlateStiffnessInput, decimals: FieldPrecision.stiffness, placeholder: "value")
                            .frame(width: settingsFieldWidth)
                        unitLabel("")
                    }
                }
            }
        }

        // Brace: its dimensions
        if selectedMeasurementType == .brace {
            settingsGroup("Brace Dimensions") {
                dimensionRow("Length (along grain)", text: $braceLengthInput, decimals: FieldPrecision.linearDimensionMM, unit: "mm")
                dimensionRow("Width (breadth)", text: $braceWidthInput, decimals: FieldPrecision.linearDimensionMM, unit: "mm")
                dimensionRow("Height (tap direction)", text: $braceThicknessInput, decimals: FieldPrecision.linearDimensionMM, unit: "mm",
                             note: "Brace height when lying flat — this is the t dimension in the stiffness formula")
                dimensionRow("Mass", text: $braceMassInput, decimals: FieldPrecision.massG, unit: "g")
                densityRow(length: braceLengthInput, width: braceWidthInput, thickness: braceThicknessInput, mass: braceMassInput)
            }
        }
    }

    // MARK: - Advanced

    /// The Advanced disclosure: a row in its own box — the icon and label, then the chevron at the
    /// right edge (down when closed, up when open).
    var advancedRow: some View {
        settingsBox {
            Button {
                showingAdvanced.toggle()
            } label: {
                HStack(spacing: 6) {
                    Label("Advanced", systemImage: "gearshape.2")
                        .font(SettingsType.title)
                        .foregroundColor(Palette.color(.textPrimary))
                    Spacer()
                    Image(systemName: showingAdvanced ? "chevron.up" : "chevron.down")
                        .font(SettingsType.caption)
                        .foregroundColor(Palette.color(.textSecondary))
                }
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Display Settings Section

    var displaySettingsSection: some View {
        settingsSection("Display Settings", icon: "chart.xyaxis.line") {
            settingsRow("Appearance") {
                Picker("Appearance", selection: $selectedAppearance) {
                    ForEach(Appearance.allCases) { appearance in
                        Text(appearance.label)
                            .tag(appearance)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            settingsDescription("System follows the operating system's Light or Dark setting")

            rangeRow(title: "Frequency Range", minBinding: $minFreqInput, maxBinding: $maxFreqInput,
                     decimals: FieldPrecision.frequencyHz, unit: "Hz",
                     description: "Frequency range shown in the spectrum chart")
            rangeRow(title: "Magnitude Range", minBinding: $minDBInput, maxBinding: $maxDBInput,
                     decimals: FieldPrecision.magnitudeDB, unit: "dB",
                     description: "Magnitude range shown in the spectrum chart")

            settingsActionButtons {
                Button {
                    saveCurrentView()
                } label: {
                    Label("Save Current View", systemImage: "square.and.arrow.down")
                }
                Button {
                    resetDisplaySettingsToDefaults()
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
            }
        }
    }

    // MARK: - Analysis Settings Section

    var analysisSettingsSection: some View {
        settingsSection("Analysis Settings", icon: "waveform.path.ecg") {
            // Show Unknown Modes (guitar only)
            if selectedMeasurementType.isGuitar {
                settingsToggleRow("Show Unknown Modes",
                                  description: "Display peaks that don't fall within known mode ranges",
                                  isOn: $showUnknownModes)
            }

            // The analysis frequency range (30–2000 Hz) is a fixed constant, not a user setting —
            // it bounds the useful modal region and never needs changing. See
            // TapDisplaySettings.analysisMinFrequency.

            // Peak Detection Minimum (guitar only — not used for plate/brace)
            VStack(alignment: .leading, spacing: 0) {
                settingsRow("Peak Detection Minimum") {
                    ValidatedNumberField(text: $peakMinThresholdInput, decimals: FieldPrecision.magnitudeDB,
                                         placeholder: "Min", allowsNegative: true)
                        .frame(width: settingsFieldWidth)
                    unitLabel("dB")
                }
                settingsDescription("Minimum magnitude for peak detection. Typical range: -60 to -40 dB")
            }
            .disabled(!selectedMeasurementType.isGuitar)
            .opacity(selectedMeasurementType.isGuitar ? 1 : Palette.opacity(.controlNotApplicable))

            // Dump Capture Audio (diagnostics). Names no folder: under the sandbox this is the app's
            // own Documents, not the user's — the folder is its own field below. One WAV per
            // measurement, not one per tap: the per-tap dumps were dropped for a single session recording.
            settingsToggleRow("Dump Capture Audio",
                              description: "Save the captured audio of each measurement as a WAV file",
                              isOn: $dumpCaptureAudio)

            // WAV-dump folder: where the recordings go, with buttons to open / change it.
            if dumpCaptureAudio {
                #if os(macOS)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved to")
                        .font(SettingsType.caption)
                        .foregroundColor(Palette.color(.textSecondary))
                    Text(dumpFolderDisplayPath)
                        .font(SettingsType.caption)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    settingsActionButtons {
                        Button("Open Folder") { WavDumpFolder.openFolder() }
                        Button("Change…") {
                            if WavDumpFolder.chooseFolder() {
                                dumpFolderDisplayPath = WavDumpFolder.currentFolder.path
                            }
                        }
                        // Shown always, disabled when already on the default — the button-visibility
                        // principle (disable, don't remove, a control that does nothing right now).
                        Button("Use Default") {
                            WavDumpFolder.useDefaultFolder()
                            dumpFolderDisplayPath = WavDumpFolder.currentFolder.path
                        }
                        .disabled(!WavDumpFolder.hasCustomFolder)
                    }
                }
                #else
                settingsDescription("Saved in the app's Documents folder — reach it in Files → On My iPhone/iPad → Guitar Tap.")
                #endif
            }

            settingsActionButtons {
                Button {
                    resetAnalysisSettings()
                } label: {
                    Label("Reset Analysis Settings", systemImage: "arrow.counterclockwise")
                }
            }
        }
    }

    // MARK: - About & Help Section

    var aboutSection: some View {
        settingsSection("About & Help", icon: "info.circle") {
            settingsRow("Version") {
                Text(appVersion)
                    .foregroundColor(Palette.color(.textSecondary))
            }

            if let copyright = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String {
                settingsDescription(copyright)
            }

            NavigationLink {
                HelpView()
            } label: {
                settingsLinkRow("Quick Start Guide", icon: "questionmark.circle", trailingIcon: "chevron.right")
            }
            .buttonStyle(.plain)

            // A button rather than a Link, so the row is drawn like Quick Start Guide's (a Link is
            // tinted throughout and keeps its colour in an inactive window).
            if let url = DocumentationLinks.userManual {
                Button {
                    openURL(url)
                } label: {
                    settingsLinkRow("User Manual", icon: "book.closed", trailingIcon: "arrow.up.forward.square")
                }
                .buttonStyle(.plain)
            }
        }
    }
}
