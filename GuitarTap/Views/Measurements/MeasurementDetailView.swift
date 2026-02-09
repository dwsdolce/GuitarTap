//
//  MeasurementDetailView.swift
//  GuitarTap
//
//  Created by David Smith on 2/9/26.
//
import SwiftUI

struct MeasurementDetailView: View {
    let measurement: TapToneMeasurement
    @ObservedObject var analyzer: TapToneAnalyzer
    @Environment(\.dismiss) var dismiss
    @State private var showingExport = false
    @State private var exportText = ""
    @State private var isExporting = false
    @State private var chartImage: Image?
    @State private var showingLoadConfirmation = false
    
    var body: some View {
        #if os(macOS)
        // On macOS in a separate window, no NavigationView needed
        contentView
            .frame(minWidth: 600, minHeight: 500)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: loadMeasurement) {
                        Label("Load", systemImage: "arrow.down.doc")
                    }
                    .help("Load this measurement into the main analysis view")
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { exportMeasurement() }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .help("Export measurement data (JSON) and chart image")
                }
            }
            .sheet(isPresented: $showingExport) {
                ExportView(text: exportText)
            }
            .alert("Load Measurement", isPresented: $showingLoadConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Load") {
                    analyzer.loadMeasurement(measurement)
                    // Close the window
                    if let window = NSApplication.shared.keyWindow {
                        window.close()
                    }
                }
            } message: {
                Text("This will replace the current analysis view with this measurement's data, including peaks and spectrum. Continue?")
            }
            .overlay {
                if isExporting {
                    LoadingOverlay(message: "Exporting...")
                }
            }
        #else
        // On iOS, NavigationLink provides the navigation context
        contentView
            .navigationTitle("Measurement Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: loadMeasurement) {
                        Label("Load", systemImage: "arrow.down.doc")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { exportMeasurement() }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showingExport) {
                ExportView(text: exportText)
            }
            .alert("Load Measurement", isPresented: $showingLoadConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Load") {
                    analyzer.loadMeasurement(measurement)
                    dismiss()
                }
            } message: {
                Text("This will replace the current analysis view with this measurement's data, including peaks and spectrum. Continue?")
            }
            .overlay {
                if isExporting {
                    LoadingOverlay(message: "Exporting...")
                }
            }
        #endif
    }
    
    @ViewBuilder
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Info
                GroupBox("Measurement Info") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let location = measurement.tapLocation {
                                HStack {
                                    Text("Location:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(location)
                                        .font(.body)
                                        .fontWeight(.medium)
                                }
                            }
                            
                            HStack {
                                Text("Date:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(measurement.timestamp, style: .date)
                                    .font(.body)
                                Text("at")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(measurement.timestamp, style: .time)
                                    .font(.body)
                            }
                            
                            if let decay = measurement.decayTime {
                                HStack {
                                    Text("Ring-Out:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(decay, specifier: "%.2f") seconds")
                                        .font(.body)
                                        .fontWeight(.medium)
                                }
                            }
                            
                            if let ratio = measurement.tapToneRatio {
                                HStack {
                                    Text("Tap Tone Ratio:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(ratio, specifier: "%.2f") : 1")
                                        .font(.body)
                                        .fontWeight(.medium)
                                }
                            }
                            
                            if let notes = measurement.notes, !notes.isEmpty {
                                Divider()
                                Text("Notes:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(notes)
                                    .font(.body)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Peaks
                    GroupBox("Detected Peaks (\(measurement.peaks.count))") {
                        if measurement.peaks.isEmpty {
                            Text("No peaks detected")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(measurement.peaks.sorted(by: { $0.frequency < $1.frequency })) { peak in
                                    let mode = GuitarMode.classify(frequency: peak.frequency)
                                    CombinedPeakModeRowView(peak: peak, mode: mode)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
    }
    
    private func loadMeasurement() {
        showingLoadConfirmation = true
    }
    
    private func exportMeasurement() {
        isExporting = true
        analyzer.exportMeasurement(measurement) { json, measurement in
            MeasurementFileExporter.exportJSONAndImage(json: json, measurement: measurement) {
                self.isExporting = false
            }
        }
    }
}
