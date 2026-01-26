//
//  TapToneAnalysisView.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import SwiftUI
import Charts

// MARK: - Main Tap Tone Analysis View

struct TapToneAnalysisView: View {
    @StateObject private var fftAnalyzer = RealtimeFFTAnalyzer(fftSize: 65536, targetSampleRate: 48000)
    @StateObject private var tapToneAnalyzer: TapToneAnalyzer
    
    @State private var tapLocation: String = ""
    @State private var notes: String = ""
    @State private var showingSaveSheet = false
    @State private var showingMeasurements = false
    
    init() {
        let fft = RealtimeFFTAnalyzer(fftSize: 65536, targetSampleRate: 48000)
        _fftAnalyzer = StateObject(wrappedValue: fft)
        _tapToneAnalyzer = StateObject(wrappedValue: TapToneAnalyzer(fftAnalyzer: fft))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with controls
                headerView
                
                Divider()
                
                // Main content
                ScrollView {
                    VStack(spacing: 20) {
                        // Tap detection indicator
                        tapIndicatorView
                        
                        // Current peaks display
                        currentPeaksView
                        
                        // Mode identification
                        modeIdentificationView
                        
                        // Decay time
                        decayTimeView
                        
                        // Tap tone ratio
                        tapToneRatioView
                        
                        // Peak history chart
                        peakHistoryChart
                    }
                    .padding()
                }
            }
            .navigationTitle("Tap Tone Analysis")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingMeasurements = true }) {
                        Label("Measurements", systemImage: "list.bullet")
                    }
                }
            }
            .sheet(isPresented: $showingSaveSheet) {
                SaveMeasurementSheet(
                    tapLocation: $tapLocation,
                    notes: $notes,
                    onSave: saveMeasurement
                )
            }
            .sheet(isPresented: $showingMeasurements) {
                MeasurementsListView(analyzer: tapToneAnalyzer)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            // Start/Stop button
            Button(action: toggleAnalyzer) {
                Label(
                    fftAnalyzer.isRunning ? "Stop" : "Start",
                    systemImage: fftAnalyzer.isRunning ? "stop.circle.fill" : "play.circle.fill"
                )
                .foregroundColor(fftAnalyzer.isRunning ? .red : .green)
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            // Save button
            Button(action: { showingSaveSheet = true }) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(tapToneAnalyzer.currentPeaks.isEmpty)
            
            // Reset button
            Button(action: tapToneAnalyzer.reset) {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    private var tapIndicatorView: some View {
        HStack {
            Circle()
                .fill(tapToneAnalyzer.tapDetected ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 20, height: 20)
            
            Text(tapToneAnalyzer.tapDetected ? "Tap Detected!" : "Waiting for tap...")
                .font(.headline)
                .foregroundColor(tapToneAnalyzer.tapDetected ? .green : .secondary)
            
            Spacer()
            
            Text("\(tapToneAnalyzer.averageMagnitude, specifier: "%.1f") dB")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var currentPeaksView: some View {
        GroupBox("Detected Peaks") {
            if tapToneAnalyzer.currentPeaks.isEmpty {
                Text("No peaks detected")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(tapToneAnalyzer.currentPeaks.prefix(5)) { peak in
                        PeakRowView(peak: peak)
                    }
                }
            }
        }
    }
    
    private var modeIdentificationView: some View {
        GroupBox("Identified Modes") {
            if tapToneAnalyzer.identifiedModes.isEmpty {
                Text("No modes identified")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(tapToneAnalyzer.identifiedModes.prefix(8), id: \.peak.id) { item in
                        ModeRowView(peak: item.peak, mode: item.mode)
                    }
                }
            }
        }
    }
    
    private var decayTimeView: some View {
        GroupBox("Ring-Out Time") {
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.blue)
                
                if let decay = tapToneAnalyzer.currentDecayTime {
                    Text("\(decay, specifier: "%.2f") seconds")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("Decay Quality")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(decayQuality(decay))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(decayQualityColor(decay))
                    }
                } else {
                    Text("Waiting for decay measurement...")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private var tapToneRatioView: some View {
        GroupBox("Tap Tone Ratio") {
            if let ratio = tapToneAnalyzer.calculateTapToneRatio() {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(ratio, specifier: "%.2f") : 1")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Long-grain / Cross-grain")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text(ratioQuality(ratio))
                            .font(.headline)
                            .foregroundColor(ratioQualityColor(ratio))
                        
                        Text("Ideal: 1.9 - 2.1")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("Need both cross-grain and long-grain modes")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }
    
    private var peakHistoryChart: some View {
        GroupBox("Peak Tracking") {
            if tapToneAnalyzer.peakHistory.isEmpty {
                Text("No history available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart {
                    ForEach(Array(tapToneAnalyzer.peakHistory.enumerated()), id: \.offset) { index, peaks in
                        ForEach(peaks.prefix(5)) { peak in
                            LineMark(
                                x: .value("Time", index),
                                y: .value("Frequency", peak.frequency)
                            )
                            .foregroundStyle(by: .value("Mode", GuitarMode.classify(frequency: peak.frequency).rawValue))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                    }
                }
                .frame(height: 250)
            }
        }
    }
    
    // MARK: - Actions
    
    private func toggleAnalyzer() {
        if fftAnalyzer.isRunning {
            fftAnalyzer.stop()
        } else {
            do {
                try tapToneAnalyzer.start()
            } catch {
                print("Failed to start: \(error)")
            }
        }
    }
    
    private func saveMeasurement() {
        tapToneAnalyzer.saveMeasurement(
            tapLocation: tapLocation.isEmpty ? nil : tapLocation,
            notes: notes.isEmpty ? nil : notes,
            includeSpectrum: true
        )
        tapLocation = ""
        notes = ""
        showingSaveSheet = false
    }
    
    // MARK: - Helpers
    
    private func decayQuality(_ time: Float) -> String {
        switch time {
        case 0..<0.5: return "Very Short"
        case 0.5..<1.0: return "Short"
        case 1.0..<2.0: return "Good"
        case 2.0..<3.0: return "Excellent"
        default: return "Very Long"
        }
    }
    
    private func decayQualityColor(_ time: Float) -> Color {
        switch time {
        case 0..<0.5: return .red
        case 0.5..<1.0: return .orange
        case 1.0..<2.0: return .green
        case 2.0..<3.0: return .blue
        default: return .purple
        }
    }
    
    private func ratioQuality(_ ratio: Float) -> String {
        let difference = abs(ratio - 2.0)
        switch difference {
        case 0..<0.1: return "Excellent"
        case 0.1..<0.2: return "Good"
        case 0.2..<0.3: return "Fair"
        default: return "Needs Work"
        }
    }
    
    private func ratioQualityColor(_ ratio: Float) -> Color {
        let difference = abs(ratio - 2.0)
        switch difference {
        case 0..<0.1: return .green
        case 0.1..<0.2: return .blue
        case 0.2..<0.3: return .orange
        default: return .red
        }
    }
}

// MARK: - Supporting Views

struct PeakRowView: View {
    let peak: ResonantPeak
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(peak.frequency, specifier: "%.2f") Hz")
                    .font(.headline)
                
                HStack {
                    Text("Q: \(peak.quality, specifier: "%.1f")")
                    Text("•")
                    Text("BW: \(peak.bandwidth, specifier: "%.1f") Hz")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(peak.magnitude, specifier: "%.1f") dB")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(magnitudeColor(peak.magnitude))
        }
        .padding(.vertical, 4)
    }
    
    private func magnitudeColor(_ mag: Float) -> Color {
        if mag >= -40.0 {
            return .green
        } else if mag >= -60.0 {
            return .blue
        } else if mag >= -80.0 {
            return .orange
        } else {
            return .red
        }
    }
}

struct ModeRowView: View {
    let peak: ResonantPeak
    let mode: GuitarMode
    
    var body: some View {
        HStack {
            Image(systemName: modeIcon)
                .foregroundColor(modeColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.rawValue)
                    .font(.headline)
                
                Text("\(peak.frequency, specifier: "%.2f") Hz")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if mode != .unknown && mode != .upperModes {
                let inRange = mode.idealRange.contains(peak.frequency)
                Image(systemName: inRange ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(inRange ? .green : .orange)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var modeIcon: String {
        switch mode {
        case .helmholtz: return "wind"
        case .crossGrain: return "arrow.left.and.right"
        case .longGrain: return "arrow.up.and.down"
        case .monopole: return "circle.fill"
        case .dipole: return "circle.lefthalf.filled"
        case .ringMode: return "circle.dashed"
        case .upperModes: return "waveform"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private var modeColor: Color {
        switch mode {
        case .helmholtz: return .cyan
        case .crossGrain: return .blue
        case .longGrain: return .green
        case .monopole: return .orange
        case .dipole: return .red
        case .ringMode: return .purple
        case .upperModes: return .gray
        case .unknown: return .secondary
        }
    }
}

struct SaveMeasurementSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var tapLocation: String
    @Binding var notes: String
    let onSave: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Tap Location") {
                    TextField("e.g., Bridge, Soundhole, Upper Bout", text: $tapLocation)
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Save Measurement")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }
}

struct MeasurementsListView: View {
    @ObservedObject var analyzer: TapToneAnalyzer
    @Environment(\.dismiss) var dismiss
    @State private var showingExport = false
    @State private var exportText = ""
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(analyzer.savedMeasurements) { measurement in
                    MeasurementRowView(measurement: measurement)
                }
                .onDelete { indexSet in
                    indexSet.forEach { index in
                        analyzer.deleteMeasurement(analyzer.savedMeasurements[index])
                    }
                }
            }
            .navigationTitle("Saved Measurements")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: exportMeasurements) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showingExport) {
                ExportView(text: exportText)
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }
    
    private func exportMeasurements() {
        if let json = analyzer.exportMeasurements() {
            exportText = json
            showingExport = true
        }
    }
}

struct MeasurementRowView: View {
    let measurement: TapToneMeasurement
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let location = measurement.tapLocation {
                    Text(location)
                        .font(.headline)
                } else {
                    Text("Measurement")
                        .font(.headline)
                }
                
                Spacer()
                
                Text(measurement.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("\(measurement.peaks.count) peaks")
                
                if let ratio = measurement.tapToneRatio {
                    Text("•")
                    Text("Ratio: \(ratio, specifier: "%.2f")")
                }
                
                if let decay = measurement.decayTime {
                    Text("•")
                    Text("Decay: \(decay, specifier: "%.2f")s")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            if let notes = measurement.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ExportView: View {
    let text: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .textSelection(.enabled)
            }
            .navigationTitle("Export Data")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: text)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }
}

// MARK: - Preview

#Preview {
    TapToneAnalysisView()
}
