//
//  TapSettingsView+Sections.swift
//  GuitarTap
//

/// # TapSettingsView+Sections
///
/// The six `Form` sections that make up the `TapSettingsView` body, extracted
/// as `@ViewBuilder` computed properties.
///
/// ## Sections
///
/// | Property | Section |
/// |---|---|
/// | `measurementTypeSection` | Measurement-type picker, guitar mode ranges, plate/brace dimensions, Gore thicknessing |
/// | `displayRangeSection` | Display frequency range, magnitude range, Save Current View / Reset buttons |
/// | `analysisSettingsSection` | Analysis frequency range, peak threshold, max peaks, hysteresis margin |
/// | `audioInputSection` | Audio-input device picker, calibration picker, import / delete calibration |
/// | `aboutSection` | App version, copyright, Help navigation link |
///
/// The sections depend on the layout helpers in `TapSettingsView+LayoutHelpers`
/// and call the action methods in `TapSettingsView+Actions`.
///
/// - SeeAlso: `TapSettingsView`, `TapSettingsView+Actions`, `TapSettingsView+LayoutHelpers`

import SwiftUI
import AVFoundation

extension TapSettingsView {

    // MARK: - Measurement Type Section

    @ViewBuilder
    var measurementTypeSection: some View {
        Section {
            Picker("Measurement Type", selection: $selectedMeasurementType) {
                ForEach(MeasurementType.allCases) { type in
                    Text(type.rawValue)
                        .tag(type)
                }
            }
            #if os(iOS)
            .pickerStyle(.navigationLink)
            #endif
            .onChange(of: selectedMeasurementType) { _, newType in
                // Load the stored frequency range for the new type (falls back to type defaults)
                minFreqInput = String(format: "%.0f", TapDisplaySettings.minFrequency(for: newType))
                maxFreqInput = String(format: "%.0f", TapDisplaySettings.maxFrequency(for: newType))
            }

            // Show description for selected type
            Text(selectedMeasurementType.description)
                .font(.caption)
                .foregroundColor(.secondary)

            // Show guitar-specific options for guitar types
            if selectedMeasurementType.isGuitar, let guitarType = selectedMeasurementType.guitarType {
                // Show frequency ranges for selected guitar type
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mode Frequency Ranges")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    let ranges = guitarType.modeRanges
                    HStack {
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
                    .font(.caption)
                }
                .padding(.vertical, 4)

            }

            // Show dimensions for plate mode
            if selectedMeasurementType == .plate {
                Divider()

                Text("Sample Dimensions")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    Text("Length (along grain):")
                        .font(.subheadline)
                    Spacer()
                    TextField("", text: $plateLengthInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("mm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Width (cross grain):")
                        .font(.subheadline)
                    Spacer()
                    TextField("", text: $plateWidthInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("mm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Thickness:")
                        .font(.subheadline)
                    Spacer()
                    TextField("", text: $plateThicknessInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("mm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Mass:")
                        .font(.subheadline)
                    Spacer()
                    TextField("", text: $plateMassInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("g")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let length = Float(plateLengthInput),
                   let width = Float(plateWidthInput),
                   let thickness = Float(plateThicknessInput),
                   let mass = Float(plateMassInput),
                   length > 0, width > 0, thickness > 0, mass > 0 {
                    let dims = MaterialDimensions(lengthMM: length, widthMM: width, thicknessMM: thickness, massGrams: mass)
                    HStack {
                        Text("Calculated Density:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.3f g/cm³", dims.densityGPerCm3))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }

                Divider()

                Toggle(isOn: $measureFlc) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Measure FLC (Diagonal Tap)")
                        Text("Add a 3rd tap: hold plate at midpoint of one long edge, tap near opposite corner. Measures shear stiffness for Gore target thickness.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                Text("Gore Target Thickness — Body Dimensions")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Finished guitar body dimensions used in Gore's Eq. 4.5-7 to calculate target plate thickness.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Body Length (a):")
                        .font(.subheadline)
                    Spacer()
                    TextField("", text: $guitarBodyLengthInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("mm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Lower Bout Width (b):")
                        .font(.subheadline)
                    Spacer()
                    TextField("", text: $guitarBodyWidthInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("mm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                Text("Plate Vibrational Stiffness (f_vs)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Picker("Panel Type", selection: $plateStiffnessPreset) {
                    ForEach(PlateStiffnessPreset.allCases) { preset in
                        Text(preset.shortName).tag(preset)
                    }
                }
                #if os(iOS)
                .pickerStyle(.navigationLink)
                #endif

                if plateStiffnessPreset == .custom {
                    HStack {
                        Text("Custom f_vs value:")
                            .font(.subheadline)
                        Spacer()
                        TextField("value", text: $customPlateStiffnessInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                }
            }

            // Show dimensions for brace mode (both FFT and MPM variants)
            if selectedMeasurementType == .brace {
                Divider()

                Text("Brace Dimensions")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    Text("Length (along grain):")
                        .font(.subheadline)
                    Spacer()
                    TextField("", text: $braceLengthInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("mm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Width (breadth):")
                        .font(.subheadline)
                    Spacer()
                    TextField("", text: $braceWidthInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("mm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Height (tap direction):")
                            .font(.subheadline)
                        Text("Brace height when lying flat — this is the t dimension in the stiffness formula")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    TextField("", text: $braceThicknessInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("mm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Mass:")
                        .font(.subheadline)
                    Spacer()
                    TextField("", text: $braceMassInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("g")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let length = Float(braceLengthInput),
                   let width = Float(braceWidthInput),
                   let thickness = Float(braceThicknessInput),
                   let mass = Float(braceMassInput),
                   length > 0, width > 0, thickness > 0, mass > 0 {
                    let dims = MaterialDimensions(lengthMM: length, widthMM: width, thicknessMM: thickness, massGrams: mass)
                    HStack {
                        Text("Calculated Density:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.3f g/cm³", dims.densityGPerCm3))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }
        } header: {
            Label("Measurement Type", systemImage: selectedMeasurementType.isGuitar ? "guitars" : "square.3.layers.3d")
                .font(.headline)
        } footer: {
            if selectedMeasurementType.isGuitar {
                Text("Select your guitar type for accurate mode classification.")
                    .font(.caption)
            } else {
                Text("Enter the dimensions and mass of your rectangular wood sample. The app will calculate stiffness, speed of sound, and radiation ratio from the tap frequencies.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Display Range Section

    @ViewBuilder
    var displayRangeSectionContent: some View {
        // Frequency Range
        if isCompact {
            compactFrequencyRangeView(
                title: "Frequency Range",
                minBinding: $minFreqInput,
                maxBinding: $maxFreqInput,
                unit: "Hz",
                description: "Frequency range shown in the spectrum chart"
            )
        } else {
            regularFrequencyRangeView(
                title: "Frequency Range",
                minBinding: $minFreqInput,
                maxBinding: $maxFreqInput,
                unit: "Hz",
                description: "Frequency range shown in the spectrum chart"
            )
        }

        // Magnitude Range
        if isCompact {
            compactFrequencyRangeView(
                title: "Magnitude Range",
                minBinding: $minDBInput,
                maxBinding: $maxDBInput,
                unit: "dB",
                description: "Magnitude range shown in the spectrum chart"
            )
        } else {
            regularFrequencyRangeView(
                title: "Magnitude Range",
                minBinding: $minDBInput,
                maxBinding: $maxDBInput,
                unit: "dB",
                description: "Magnitude range shown in the spectrum chart"
            )
        }

        Button {
            saveCurrentView()
        } label: {
            HStack {
                Spacer()
                Image(systemName: "square.and.arrow.down")
                Text("Save Current View")
                Spacer()
            }
            .font(.subheadline)
        }
        .padding(.top, 8)
        Button(role: .destructive) {
            resetDisplaySettingsToDefaults()
        } label: {
            HStack {
                Spacer()
                Image(systemName: "arrow.counterclockwise.circle")
                Text("Reset to Defaults")
                Spacer()
            }
            .font(.subheadline)
        }
    }

    // MARK: - Analysis Settings Section

    @ViewBuilder
    var analysisSettingsSectionContent: some View {
        // Show Unknown Modes (guitar only)
        if selectedMeasurementType.isGuitar {
            Toggle(isOn: $showUnknownModes) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Unknown Modes")
                    Text("Display peaks that don't fall within known mode ranges")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }

        // Analysis Frequency Range
            if isCompact {
                compactFrequencyRangeView(
                    title: "Analysis Frequency Range",
                    minBinding: $analysisMinFreqInput,
                    maxBinding: $analysisMaxFreqInput,
                    unit: "Hz",
                    description: "Frequency range used for peak detection"
                )
            } else {
                regularFrequencyRangeView(
                    title: "Analysis Frequency Range",
                    minBinding: $analysisMinFreqInput,
                    maxBinding: $analysisMaxFreqInput,
                    unit: "Hz",
                    description: "Frequency range used for peak detection"
                )
            }

            // Peak Threshold (guitar only — not used for plate/brace)
            VStack(alignment: .leading, spacing: 12) {
                Text("Peak Detection Minimum")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 12) {
                    TextField("Min", text: $peakMinThresholdInput)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                        .frame(maxWidth: isCompact ? .infinity : 120)

                    Text("dB")
                        .foregroundColor(.secondary)
                        .font(.body)
                }

                Text("Minimum magnitude for peak detection. Typical range: -60 to -40 dB")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .disabled(!selectedMeasurementType.isGuitar)
            .opacity(selectedMeasurementType.isGuitar ? 1 : 0.4)

            Divider()

            // Dump Capture Audio (diagnostics)
            Toggle(isOn: $dumpCaptureAudio) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dump Capture Audio")
                    Text("Save each captured tap as a WAV file in Documents/GuitarTap")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                resetAnalysisSettings()
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset Analysis Settings")
                    Spacer()
                }
                .font(.subheadline)
            }
            .padding(.top, 8)
    }

    // MARK: - Audio Input & Calibration Section

    @ViewBuilder
    var audioInputSection: some View {
        if !fftAnalyzer.availableInputDevices.isEmpty {
            Section {
                // Device picker
                Picker("Audio Input Device", selection: $fftAnalyzer.selectedInputDevice) {
                    ForEach(fftAnalyzer.availableInputDevices) { device in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                                .font(.body)
                            Text("Sample Rate: \(String(format: "%.0f", device.sampleRate / 1000)) kHz")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(device as AVAudioDevice?)
                    }
                }
                #if os(iOS)
                .pickerStyle(.navigationLink)
                #endif
                .onChange(of: fftAnalyzer.selectedInputDevice) { oldDevice, newDevice in
                    guard let device = newDevice, device.uid != oldDevice?.uid else { return }
                    gtLog("🔄 Device selection changed to: \(device.name)")
                    // Update calibration picker to reflect device's calibration
                    selectedCalibrationID = fftAnalyzer.activeCalibration?.id
                }

                if let selectedDevice = fftAnalyzer.selectedInputDevice {
                    HStack {
                        Text("Sample Rate:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(String(format: "%.0f", selectedDevice.sampleRate)) Hz")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }

                // Calibration subsection
                Divider()

                // Calibration picker (if any calibrations are stored)
                if !storedCalibrations.isEmpty {
                    Picker("Calibration", selection: $selectedCalibrationID) {
                        Text("None (Uncalibrated)")
                            .tag(nil as UUID?)

                        ForEach(storedCalibrations) { calibration in
                            Text(calibration.name)
                                .tag(calibration.id as UUID?)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.navigationLink)
                    #endif
                    .onChange(of: selectedCalibrationID) { _, newID in
                        if let id = newID {
                            fftAnalyzer.activeCalibration = storedCalibrations.first { $0.id == id }
                        } else {
                            fftAnalyzer.activeCalibration = nil
                        }
                    }
                } else {
                    HStack {
                        Text("Calibration:")
                            .font(.subheadline)
                        Spacer()
                        Text("None")
                            .foregroundColor(.secondary)
                    }
                }

                // Import button
                Button {
                    showingCalibrationImporter = true
                } label: {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                        Text("Import Calibration File...")
                    }
                }

                // Show calibration details if one is active
                if let calibration = fftAnalyzer.activeCalibration {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                if let sens = calibration.sensitivityFactor {
                                    Text("Sensitivity: \(String(format: "%.2f", sens)) dB")
                                        .font(.caption)
                                }
                                Text("Data points: \(calibration.correctionPoints.count)")
                                    .font(.caption)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if let first = calibration.correctionPoints.first,
                                   let last = calibration.correctionPoints.last {
                                    Text("\(String(format: "%.0f", first.frequency))-\(String(format: "%.0f", last.frequency)) Hz")
                                        .font(.caption)
                                }
                            }
                        }
                        .foregroundColor(.secondary)
                    }
                }

                // Delete calibrations (if any exist)
                if !storedCalibrations.isEmpty {
                    Button(role: .destructive) {
                        showingDeleteAllCalibrationsConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete All Calibrations")
                        }
                    }
                }
            } header: {
                Label("Audio Input & Calibration", systemImage: "mic.fill")
                    .font(.headline)
            } footer: {
                Text("Audio input and calibration changes take effect immediately and are not affected by Cancel. Calibrations are automatically associated with each device.")
                    .font(.caption)
            }
        }
    }

    // MARK: - About & Help Section

    @ViewBuilder
    var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundColor(.secondary)
            }

            if let copyright = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String {
                Text(copyright)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            NavigationLink {
                HelpView()
            } label: {
                Label("Help", systemImage: "questionmark.circle")
            }
        } header: {
            Label("About & Help", systemImage: "info.circle")
                .font(.headline)
        }
    }
}
