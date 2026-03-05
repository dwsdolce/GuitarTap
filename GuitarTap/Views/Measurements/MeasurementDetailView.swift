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
    @State private var isGeneratingReport = false
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

                ToolbarItem(placement: .primaryAction) {
                    Button(action: { generatePDFReport() }) {
                        Label("PDF Report", systemImage: "doc.richtext")
                    }
                    .help("Export a PDF analysis report including the spectrum chart")
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
                } else if isGeneratingReport {
                    LoadingOverlay(message: "Generating PDF report...")
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
                    Menu {
                        Button(action: { exportMeasurement() }) {
                            Label("Export Data (JSON)", systemImage: "square.and.arrow.up")
                        }
                        Button(action: { generatePDFReport() }) {
                            Label("Export PDF Report", systemImage: "doc.richtext")
                        }
                    } label: {
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
                } else if isGeneratingReport {
                    LoadingOverlay(message: "Generating PDF report...")
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
                    
                    // Peaks (filtered based on unknown mode setting)
                    let selectedIDs = Set(measurement.selectedPeakIDs ?? measurement.peaks.map { $0.id })
                    let filteredPeaks = measurement.peaks
                        .sorted(by: { $0.frequency < $1.frequency })
                        .filter { peak in
                            TapDisplaySettings.showUnknownModes ||
                            GuitarMode.classify(frequency: peak.frequency).normalized != .unknown
                        }
                    let selectedCount = filteredPeaks.filter { selectedIDs.contains($0.id) }.count
                    let unselectedCount = filteredPeaks.filter { !selectedIDs.contains($0.id) }.count

                    GroupBox("Detected Peaks (\(selectedCount) selected\(unselectedCount > 0 ? ", \(unselectedCount) unselected" : ""))") {
                        if filteredPeaks.isEmpty {
                            Text("No peaks detected")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(filteredPeaks) { peak in
                                    let mode = GuitarMode.classify(frequency: peak.frequency)
                                    let isSelected = selectedIDs.contains(peak.id)
                                    CombinedPeakModeRowView(peak: peak, mode: mode, isSelected: isSelected)
                                        .opacity(isSelected ? 1.0 : 0.4)
                                        .overlay(alignment: .trailing) {
                                            if !isSelected {
                                                Image(systemName: "star.slash")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
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

    @MainActor
    private func generatePDFReport() {
        isGeneratingReport = true
        let reportData = PDFReportData.from(measurement: measurement)
        guard let pdfData = PDFReportGenerator.generate(data: reportData) else {
            print("❌ Failed to generate PDF report")
            isGeneratingReport = false
            return
        }
        MeasurementFileExporter.exportPDF(data: pdfData, basename: reportData.baseFilename) {
            self.isGeneratingReport = false
        }
    }
}
