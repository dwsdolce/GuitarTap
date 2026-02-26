//
//  SpectrumSettingsView.swift
//  GuitarTap
//
//  Created on 2/12/26.
//

import SwiftUI
internal import UniformTypeIdentifiers

/// Settings view for spectrum display and analysis parameters
struct SpectrumSettingsView: View {
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
    @Environment(\.dismiss) private var dismiss
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    
    // Local state for text input
    @State private var minFreqInput: String
    @State private var maxFreqInput: String
    @State private var minDBInput: String
    @State private var maxDBInput: String
    @State private var analysisMinFreqInput: String
    @State private var analysisMaxFreqInput: String
    @State private var peakThresholdInput: String
    @State private var maxPeaksInput: String
    @State private var captureAllPeaks: Bool
    
    // Measurement type setting
    @State private var selectedMeasurementType: MeasurementType = SpectrumDisplaySettings.measurementType
    
    // Unknown mode display setting
    @State private var showUnknownModes: Bool = SpectrumDisplaySettings.showUnknownModes
    
    // Material dimensions (for Material measurement type)
    @State private var materialLengthInput: String = String(format: "%.1f", SpectrumDisplaySettings.materialLength)
    @State private var materialWidthInput: String = String(format: "%.1f", SpectrumDisplaySettings.materialWidth)
    @State private var materialThicknessInput: String = String(format: "%.2f", SpectrumDisplaySettings.materialThickness)
    @State private var materialMassInput: String = String(format: "%.1f", SpectrumDisplaySettings.materialMass)
    @State private var measureFlc: Bool = SpectrumDisplaySettings.measureFlc

    // Gore thicknessing settings
    @State private var guitarBodyLengthInput: String = String(format: "%.0f", SpectrumDisplaySettings.guitarBodyLength)
    @State private var guitarBodyWidthInput: String = String(format: "%.0f", SpectrumDisplaySettings.guitarBodyWidth)
    @State private var plateStiffnessPreset: PlateStiffnessPreset = SpectrumDisplaySettings.plateStiffnessPreset
    @State private var customPlateStiffnessInput: String = String(format: "%.0f", SpectrumDisplaySettings.customPlateStiffness)

    // Brace dimensions (for Brace Material measurement type)
    @State private var braceLengthInput: String = String(format: "%.1f", SpectrumDisplaySettings.braceLength)
    @State private var braceWidthInput: String = String(format: "%.1f", SpectrumDisplaySettings.braceWidth)
    @State private var braceThicknessInput: String = String(format: "%.1f", SpectrumDisplaySettings.braceThickness)
    @State private var braceMassInput: String = String(format: "%.1f", SpectrumDisplaySettings.braceMass)
    
    // Validation states
    @State private var showValidationError = false
    @State private var validationMessage = ""
    
    // Calibration states
    @State private var showingCalibrationImporter = false
    @State private var storedCalibrations: [MicrophoneCalibration] = []
    @State private var calibrationImportError: String?
    @State private var showingCalibrationError = false
    @State private var selectedCalibrationID: UUID?
    
    // Computed property for compact layout
    private var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }
    
    init(minFreq: Binding<Float>,
         maxFreq: Binding<Float>,
         minDB: Binding<Float>,
         maxDB: Binding<Float>,
         analysisMinFreq: Binding<Float>,
         analysisMaxFreq: Binding<Float>,
         peakThreshold: Binding<Float>,
         maxPeaks: Binding<Int>,
         fftAnalyzer: RealtimeFFTAnalyzer) {
        
        self._minFreq = minFreq
        self._maxFreq = maxFreq
        self._minDB = minDB
        self._maxDB = maxDB
        self._analysisMinFreq = analysisMinFreq
        self._analysisMaxFreq = analysisMaxFreq
        self._peakThreshold = peakThreshold
        self._maxPeaks = maxPeaks
        self.fftAnalyzer = fftAnalyzer
        
        // Initialize text inputs with current values
        self._minFreqInput = State(initialValue: String(format: "%.0f", minFreq.wrappedValue))
        self._maxFreqInput = State(initialValue: String(format: "%.0f", maxFreq.wrappedValue))
        self._minDBInput = State(initialValue: String(format: "%.0f", minDB.wrappedValue))
        self._maxDBInput = State(initialValue: String(format: "%.0f", maxDB.wrappedValue))
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
                // MARK: - Measurement Type
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
                        minFreqInput = String(format: "%.0f", SpectrumDisplaySettings.minFrequency(for: newType))
                        maxFreqInput = String(format: "%.0f", SpectrumDisplaySettings.maxFrequency(for: newType))
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
                        
                        // Unknown modes toggle
                        Toggle(isOn: $showUnknownModes) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show Unknown Modes")
                                Text("Display peaks that don't fall within known mode ranges")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Show dimensions for material mode (plate)
                    if selectedMeasurementType == .material {
                        Divider()
                        
                        Text("Sample Dimensions")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Text("Length (along grain):")
                                .font(.subheadline)
                            Spacer()
                            TextField("mm", text: $materialLengthInput)
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
                            TextField("mm", text: $materialWidthInput)
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
                            TextField("mm", text: $materialThicknessInput)
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
                            TextField("g", text: $materialMassInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Text("g")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        Toggle(isOn: $measureFlc) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Measure FLC (Diagonal Tap)")
                                Text("Add a 3rd tap supporting plate at 4 corner nodal points to measure shear stiffness. Required for Gore target thickness.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let length = Float(materialLengthInput),
                           let width = Float(materialWidthInput),
                           let thickness = Float(materialThicknessInput),
                           let mass = Float(materialMassInput),
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
                            TextField("mm", text: $guitarBodyLengthInput)
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
                            TextField("mm", text: $guitarBodyWidthInput)
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
                    
                    // Show dimensions for brace mode
                    if selectedMeasurementType == .brace {
                        Divider()
                        
                        Text("Brace Dimensions")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Text("Length (along grain):")
                                .font(.subheadline)
                            Spacer()
                            TextField("mm", text: $braceLengthInput)
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
                            TextField("mm", text: $braceWidthInput)
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
                            TextField("mm", text: $braceThicknessInput)
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
                            TextField("g", text: $braceMassInput)
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
                
                // MARK: - Display Range Settings
                Section {
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
                        resetDisplaySettings()
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset Display Settings")
                            Spacer()
                        }
                        .font(.subheadline)
                    }
                    .padding(.top, 8)
                } header: {
                    Label("Display Settings", systemImage: "chart.xyaxis.line")
                        .font(.headline)
                } footer: {
                    Text("Controls what frequency and magnitude ranges are visible in the spectrum chart.")
                        .font(.caption)
                }
                
                // MARK: - Analysis Settings
                Section {
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
                    
                    // Peak Threshold
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Peak Detection Minimum")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack(spacing: 12) {
                            TextField("Min", text: $peakThresholdInput)
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
                    
                    // Max Peaks
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Maximum Peaks")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack(spacing: 12) {
                            // Text field for direct input
                            TextField("", text: $maxPeaksInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .disabled(captureAllPeaks)
                                .opacity(captureAllPeaks ? 0.5 : 1.0)
                                .onSubmit {
                                    // Update maxPeaks when user submits (if valid)
                                    if let value = Int(maxPeaksInput), value >= 1 {
                                        maxPeaks = value
                                    } else {
                                        // Restore valid value
                                        maxPeaksInput = "\(maxPeaks)"
                                    }
                                }
                            
                            Text("peaks")
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            // Stepper for increment/decrement (only when not in "all" mode)
                            Stepper("", value: Binding(
                                get: { maxPeaks == 0 ? SpectrumDisplaySettings.defaultMaxPeaks : maxPeaks },
                                set: { newValue in
                                    maxPeaks = newValue
                                    maxPeaksInput = "\(newValue)"
                                    captureAllPeaks = false
                                }
                            ), in: 1...100, step: 1)
                                .labelsHidden()
                                .disabled(captureAllPeaks)
                                .opacity(captureAllPeaks ? 0.5 : 1.0)
                        }
                        
                        // "All peaks" toggle
                        Toggle(isOn: Binding(
                            get: { captureAllPeaks },
                            set: { isOn in
                                captureAllPeaks = isOn
                                if isOn {
                                    maxPeaks = 0  // 0 means "all peaks"
                                    maxPeaksInput = "All"
                                } else {
                                    // Restore default when turning off
                                    maxPeaks = SpectrumDisplaySettings.defaultMaxPeaks
                                    maxPeaksInput = "\(maxPeaks)"
                                }
                            }
                        )) {
                            Text("Capture all peaks in analysis range")
                                .font(.subheadline)
                        }
                        
                        Text("Maximum number of peaks to detect. The strongest peak for each guitar mode is always included, then remaining slots are filled by magnitude. Set to 'All' to capture every peak above the threshold.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    
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
                } header: {
                    Label("Analysis Settings", systemImage: "waveform.path.ecg")
                        .font(.headline)
                } footer: {
                    Text("Controls how peaks are detected in the frequency spectrum.")
                        .font(.caption)
                }
                
                // MARK: - Audio Input & Calibration
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
                            print("🔄 Device selection changed to: \(device.name)")
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
                                deleteAllCalibrations()
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
                        Text("Select audio input device. Import a calibration file (.txt or .cal) from your measurement microphone to compensate for its frequency response. Calibrations are automatically associated with each device.")
                            .font(.caption)
                    }
                }
                
                // MARK: - FFT Processing Settings
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Hop Size Overlap")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text("\(Int(fftAnalyzer.hopSizeOverlap))%")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                                .frame(width: 50, alignment: .trailing)
                        }
                        
                        HStack(spacing: 8) {
                            Text("0%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Slider(value: $fftAnalyzer.hopSizeOverlap, in: 0...75, step: 5)
                            
                            Text("75%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Controls the overlap between FFT windows. Higher overlap provides smoother results but reduces frame rate.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            if fftAnalyzer.hopSizeOverlap == 0 {
                                Text("0% overlap: Maximum frame rate, no smoothing")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if fftAnalyzer.hopSizeOverlap <= 25 {
                                Text("Low overlap: Fast response with minimal smoothing")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if fftAnalyzer.hopSizeOverlap <= 50 {
                                Text("Medium overlap: Balanced response and smoothness")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text("High overlap: Smooth results, slower response")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .onChange(of: fftAnalyzer.hopSizeOverlap) { _, _ in
                        // Update metrics when hop size changes
                        // Note: This will only take effect after the analyzer is restarted
                    }
                } header: {
                    Label("FFT Processing", systemImage: "waveform.path")
                        .font(.headline)
                } footer: {
                    Text("Changes to hop size will take effect the next time the analyzer is started.")
                        .font(.caption)
                }

                // MARK: - About & Help
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
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 500, minHeight: 600)
            #endif
            .navigationTitle("Spectrum Settings")
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
    
    // MARK: - Calibration Helpers
    
    private func loadStoredCalibrations() {
        storedCalibrations = CalibrationStorage.shared.loadAll()
    }
    
    private func handleCalibrationImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                calibrationImportError = "Could not access the selected file. Please try again."
                showingCalibrationError = true
                return
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            do {
                let calibration = try CalibrationFileParser.parse(url: url)
                CalibrationStorage.shared.save(calibration)
                
                // Activate the newly imported calibration
                fftAnalyzer.activeCalibration = calibration
                
                // Refresh the list
                loadStoredCalibrations()
                
                print("✅ Imported calibration '\(calibration.name)' with \(calibration.correctionPoints.count) data points")
            } catch {
                calibrationImportError = error.localizedDescription
                showingCalibrationError = true
            }
            
        case .failure(let error):
            calibrationImportError = error.localizedDescription
            showingCalibrationError = true
        }
    }
    
    private func deleteAllCalibrations() {
        // Clear active calibration first
        fftAnalyzer.activeCalibration = nil
        
        // Delete all stored calibrations
        for calibration in storedCalibrations {
            CalibrationStorage.shared.delete(calibration)
        }
        
        // Refresh the list
        loadStoredCalibrations()
    }
    
    // MARK: - Layout Helpers
    
    /// Compact layout for iPhone - stacked vertically
    @ViewBuilder
    private func compactFrequencyRangeView(
        title: String,
        minBinding: Binding<String>,
        maxBinding: Binding<String>,
        unit: String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            VStack(spacing: 8) {
                HStack {
                    Text("Minimum:")
                        .frame(width: 80, alignment: .leading)
                        .foregroundColor(.secondary)
                    TextField("Min", text: minBinding)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(unit == "dB" ? .numbersAndPunctuation : .decimalPad)
                        #endif
                    Text(unit)
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .leading)
                }
                
                HStack {
                    Text("Maximum:")
                        .frame(width: 80, alignment: .leading)
                        .foregroundColor(.secondary)
                    TextField("Max", text: maxBinding)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(unit == "dB" ? .numbersAndPunctuation : .decimalPad)
                        #endif
                    Text(unit)
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .leading)
                }
            }
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
    
    /// Regular layout for iPad and macOS - horizontal
    @ViewBuilder
    private func regularFrequencyRangeView(
        title: String,
        minBinding: Binding<String>,
        maxBinding: Binding<String>,
        unit: String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack(spacing: 12) {
                TextField("Min", text: minBinding)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(unit == "dB" ? .numbersAndPunctuation : .decimalPad)
                    #endif
                    .frame(maxWidth: 100)
                
                Text("to")
                    .foregroundColor(.secondary)
                
                TextField("Max", text: maxBinding)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(unit == "dB" ? .numbersAndPunctuation : .decimalPad)
                    #endif
                    .frame(maxWidth: 100)
                
                Text(unit)
                    .foregroundColor(.secondary)
                    .font(.body)
            }
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private func modeRangeRow(_ label: String, range: ClosedRange<Float>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)
            Text("\(Int(range.lowerBound))-\(Int(range.upperBound)) Hz")
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Actions
    
    private func applySettings() {
        // Save measurement type and unknown mode setting
        SpectrumDisplaySettings.measurementType = selectedMeasurementType
        SpectrumDisplaySettings.showUnknownModes = showUnknownModes
        SpectrumDisplaySettings.measureFlc = measureFlc
        
        // Save material plate dimensions
        if selectedMeasurementType == .material {
            if let length = Float(materialLengthInput), length > 0 {
                SpectrumDisplaySettings.materialLength = length
            }
            if let width = Float(materialWidthInput), width > 0 {
                SpectrumDisplaySettings.materialWidth = width
            }
            if let thickness = Float(materialThicknessInput), thickness > 0 {
                SpectrumDisplaySettings.materialThickness = thickness
            }
            if let mass = Float(materialMassInput), mass > 0 {
                SpectrumDisplaySettings.materialMass = mass
            }

            // Save Gore thicknessing settings (always save regardless of FLC state)
            if let bodyLength = Float(guitarBodyLengthInput), bodyLength > 0 {
                SpectrumDisplaySettings.guitarBodyLength = bodyLength
            }
            if let bodyWidth = Float(guitarBodyWidthInput), bodyWidth > 0 {
                SpectrumDisplaySettings.guitarBodyWidth = bodyWidth
            }
            SpectrumDisplaySettings.plateStiffnessPreset = plateStiffnessPreset
            if plateStiffnessPreset == .custom,
               let customVal = Float(customPlateStiffnessInput), customVal > 0 {
                SpectrumDisplaySettings.customPlateStiffness = customVal
            }
        }

        // Save brace dimensions (separate keys from plate)
        if selectedMeasurementType == .brace {
            if let length = Float(braceLengthInput), length > 0 {
                SpectrumDisplaySettings.braceLength = length
            }
            if let width = Float(braceWidthInput), width > 0 {
                SpectrumDisplaySettings.braceWidth = width
            }
            if let thickness = Float(braceThicknessInput), thickness > 0 {
                SpectrumDisplaySettings.braceThickness = thickness
            }
            if let mass = Float(braceMassInput), mass > 0 {
                SpectrumDisplaySettings.braceMass = mass
            }
        }
        
        // Parse and validate display frequency range
        guard let newMinFreq = Float(minFreqInput),
              let newMaxFreq = Float(maxFreqInput) else {
            showError("Invalid display frequency values. Please enter valid numbers.")
            return
        }
        
        let validatedFreq = SpectrumDisplaySettings.validateFrequencyRange(
            minFreq: newMinFreq,
            maxFreq: newMaxFreq
        )
        
        // Parse and validate display magnitude range
        guard let newMinDB = Float(minDBInput),
              let newMaxDB = Float(maxDBInput) else {
            showError("Invalid display magnitude values. Please enter valid numbers.")
            return
        }
        
        let validatedDB = SpectrumDisplaySettings.validateMagnitudeRange(
            minDB: newMinDB,
            maxDB: newMaxDB
        )
        
        // Parse and validate analysis frequency range
        guard let newAnalysisMinFreq = Float(analysisMinFreqInput),
              let newAnalysisMaxFreq = Float(analysisMaxFreqInput) else {
            showError("Invalid analysis frequency values. Please enter valid numbers.")
            return
        }
        
        let validatedAnalysisFreq = SpectrumDisplaySettings.validateFrequencyRange(
            minFreq: newAnalysisMinFreq,
            maxFreq: newAnalysisMaxFreq
        )
        
        // Parse and validate peak threshold
        guard let newPeakThreshold = Float(peakThresholdInput) else {
            showError("Invalid peak threshold value. Please enter a valid number.")
            return
        }
        
        // Clamp peak threshold to reasonable range
        let clampedThreshold = max(-120, min(newPeakThreshold, 0))
        
        // Apply validated values to bindings
        minFreq = validatedFreq.min
        maxFreq = validatedFreq.max
        minDB = validatedDB.min
        maxDB = validatedDB.max
        analysisMinFreq = validatedAnalysisFreq.min
        analysisMaxFreq = validatedAnalysisFreq.max
        peakThreshold = clampedThreshold
        
        // Persist all settings to UserDefaults (frequency range is stored per measurement type)
        SpectrumDisplaySettings.setMinFrequency(validatedFreq.min, for: selectedMeasurementType)
        SpectrumDisplaySettings.setMaxFrequency(validatedFreq.max, for: selectedMeasurementType)
        SpectrumDisplaySettings.minMagnitude = validatedDB.min
        SpectrumDisplaySettings.maxMagnitude = validatedDB.max
        SpectrumDisplaySettings.analysisMinFrequency = validatedAnalysisFreq.min
        SpectrumDisplaySettings.analysisMaxFrequency = validatedAnalysisFreq.max
        SpectrumDisplaySettings.peakThreshold = clampedThreshold
        SpectrumDisplaySettings.maxPeaks = maxPeaks
        SpectrumDisplaySettings.hopSizeOverlap = fftAnalyzer.hopSizeOverlap
        
        // Update input fields with validated values (in case they were clamped)
        minFreqInput = String(format: "%.0f", validatedFreq.min)
        maxFreqInput = String(format: "%.0f", validatedFreq.max)
        minDBInput = String(format: "%.0f", validatedDB.min)
        maxDBInput = String(format: "%.0f", validatedDB.max)
        analysisMinFreqInput = String(format: "%.0f", validatedAnalysisFreq.min)
        analysisMaxFreqInput = String(format: "%.0f", validatedAnalysisFreq.max)
        peakThresholdInput = String(format: "%.0f", clampedThreshold)
        
        dismiss()
    }
    
    private func resetDisplaySettings() {
        // Reset display settings to defaults (frequency defaults vary by measurement type)
        minFreqInput = String(format: "%.0f", SpectrumDisplaySettings.defaultMinFrequency(for: selectedMeasurementType))
        maxFreqInput = String(format: "%.0f", SpectrumDisplaySettings.defaultMaxFrequency(for: selectedMeasurementType))
        minDBInput = String(format: "%.0f", SpectrumDisplaySettings.defaultMinMagnitude)
        maxDBInput = String(format: "%.0f", SpectrumDisplaySettings.defaultMaxMagnitude)
    }
    
    private func resetAnalysisSettings() {
        // Reset analysis settings to defaults
        analysisMinFreqInput = String(format: "%.0f", SpectrumDisplaySettings.defaultAnalysisMinFrequency)
        analysisMaxFreqInput = String(format: "%.0f", SpectrumDisplaySettings.defaultAnalysisMaxFrequency)
        peakThresholdInput = String(format: "%.0f", SpectrumDisplaySettings.defaultPeakThreshold)
        maxPeaks = SpectrumDisplaySettings.defaultMaxPeaks
        maxPeaksInput = "\(SpectrumDisplaySettings.defaultMaxPeaks)"
        captureAllPeaks = false
    }
    
    private func showError(_ message: String) {
        validationMessage = message
        showValidationError = true
    }
}

// MARK: - Preview

#Preview {
    SpectrumSettingsView(
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
