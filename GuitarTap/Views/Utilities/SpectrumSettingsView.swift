//
//  SpectrumSettingsView.swift
//  GuitarTap
//
//  Created on 2/12/26.
//

import SwiftUI

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
    
    // Validation states
    @State private var showValidationError = false
    @State private var validationMessage = ""
    
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
         fftAnalyzer: RealtimeFFTAnalyzer) {
        
        self._minFreq = minFreq
        self._maxFreq = maxFreq
        self._minDB = minDB
        self._maxDB = maxDB
        self._analysisMinFreq = analysisMinFreq
        self._analysisMaxFreq = analysisMaxFreq
        self._peakThreshold = peakThreshold
        self.fftAnalyzer = fftAnalyzer
        
        // Initialize text inputs with current values
        self._minFreqInput = State(initialValue: String(format: "%.0f", minFreq.wrappedValue))
        self._maxFreqInput = State(initialValue: String(format: "%.0f", maxFreq.wrappedValue))
        self._minDBInput = State(initialValue: String(format: "%.0f", minDB.wrappedValue))
        self._maxDBInput = State(initialValue: String(format: "%.0f", maxDB.wrappedValue))
        self._analysisMinFreqInput = State(initialValue: String(format: "%.0f", analysisMinFreq.wrappedValue))
        self._analysisMaxFreqInput = State(initialValue: String(format: "%.0f", analysisMaxFreq.wrappedValue))
        self._peakThresholdInput = State(initialValue: String(format: "%.0f", peakThreshold.wrappedValue))
    }
    
    var body: some View {
        NavigationStack {
            Form {
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
                    
//                    Divider()
//                        .padding(.vertical, 4)
                    
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
                    
//                    Divider()
//                        .padding(.vertical, 4)
                    
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
                } header: {
                    Label("Analysis Settings", systemImage: "waveform.path.ecg")
                        .font(.headline)
                } footer: {
                    Text("Controls how peaks are detected in the frequency spectrum.")
                        .font(.caption)
                }
                
                // MARK: - Audio Input Device
                if !fftAnalyzer.availableInputDevices.isEmpty {
                    Section {
                        Picker("Audio Input Device", selection: Binding(
                            get: { fftAnalyzer.selectedInputDevice ?? fftAnalyzer.availableInputDevices.first },
                            set: { newDevice in
                                if let device = newDevice {
                                    do {
                                        try fftAnalyzer.setInputDevice(device)
                                    } catch {
                                        print("❌ Failed to set input device: \(error)")
                                    }
                                }
                            }
                        )) {
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
                        
                        if let selectedDevice = fftAnalyzer.selectedInputDevice {
                            HStack {
                                Text("Current Sample Rate:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(String(format: "%.0f", selectedDevice.sampleRate)) Hz")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                    } header: {
                        Label("Audio Input", systemImage: "mic.fill")
                            .font(.headline)
                    } footer: {
                        Text("Select the audio input device for analysis. USB microphones like UMIK-1 will appear here when connected.")
                            .font(.caption)
                    }
                }
                
                // MARK: - Reset to Defaults
                Section {
                    Button {
                        resetToDefaults()
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset All to Defaults")
                            Spacer()
                        }
                    }
                    .font(.body)
                } footer: {
                    Text("Resets all settings to factory defaults")
                        .font(.caption)
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
        }
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
    
    // MARK: - Actions
    
    private func applySettings() {
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
        
        // Apply validated values
        minFreq = validatedFreq.min
        maxFreq = validatedFreq.max
        minDB = validatedDB.min
        maxDB = validatedDB.max
        analysisMinFreq = validatedAnalysisFreq.min
        analysisMaxFreq = validatedAnalysisFreq.max
        peakThreshold = clampedThreshold
        
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
    
    private func resetToDefaults() {
        minFreqInput = String(format: "%.0f", SpectrumDisplaySettings.minFrequency)
        maxFreqInput = String(format: "%.0f", SpectrumDisplaySettings.maxFrequency)
        minDBInput = String(format: "%.0f", SpectrumDisplaySettings.minMagnitude)
        maxDBInput = String(format: "%.0f", SpectrumDisplaySettings.maxMagnitude)
        analysisMinFreqInput = String(format: "%.0f", SpectrumDisplaySettings.analysisMinFrequency)
        analysisMaxFreqInput = String(format: "%.0f", SpectrumDisplaySettings.analysisMaxFrequency)
        peakThresholdInput = String(format: "%.0f", SpectrumDisplaySettings.defaultPeakThreshold)
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
        fftAnalyzer: RealtimeFFTAnalyzer(fftSize: 8192, targetSampleRate: 48000)
    )
}
