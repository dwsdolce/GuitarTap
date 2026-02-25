//
//  MeasurementsListView.swift
//  GuitarTap
//
//  Created by David Smith on 2/9/26.
//
import SwiftUI
internal import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct MeasurementsListView: View {
    @ObservedObject var analyzer: TapToneAnalyzer
    @Environment(\.dismiss) var dismiss
    @State private var showingExport = false
    @State private var exportText = ""
    @State private var isExporting = false  // Track export progress
    @State private var isGeneratingReport = false
    @State private var showingImportPicker = false
    @State private var importError: String?
    @State private var importSuccess: String?
    @State private var selectedMeasurement: TapToneMeasurement?
    #if os(macOS)
    @State private var detailWindowController: NSWindowController?
    #endif
    
    var body: some View {
        #if os(macOS)
        // macOS layout without NavigationView wrapper (sheet handles its own window)
        contentView
            .frame(minWidth: 600, minHeight: 400)
            .sheet(isPresented: $showingExport) {
                ExportView(text: exportText)
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        importFromFile(url: url)
                    }
                case .failure(let error):
                    importError = "Failed to open file: \(error.localizedDescription)"
                }
            }
            .alert("Import Error", isPresented: .constant(importError != nil)) {
                Button("OK") { importError = nil }
            } message: {
                if let error = importError {
                    Text(error)
                }
            }
            .alert("Import Successful", isPresented: .constant(importSuccess != nil)) {
                Button("OK") { importSuccess = nil }
            } message: {
                if let success = importSuccess {
                    Text(success)
                }
            }
            .alert("Microphone Not Connected", isPresented: Binding(
                get: { analyzer.microphoneWarning != nil },
                set: { if !$0 { analyzer.microphoneWarning = nil } }
            )) {
                Button("OK") { analyzer.microphoneWarning = nil }
            } message: {
                Text(analyzer.microphoneWarning ?? "")
            }
            .overlay {
                if isExporting {
                    LoadingOverlay(message: "Exporting measurements...")
                } else if isGeneratingReport {
                    LoadingOverlay(message: "Generating PDF report...")
                }
            }
        #else
        // iOS layout with NavigationView
        NavigationView {
            contentView
                .sheet(isPresented: $showingExport) {
                    ExportView(text: exportText)
                }
                .sheet(item: $selectedMeasurement) { measurement in
                    MeasurementDetailView(measurement: measurement, analyzer: analyzer)
                }
                .sheet(isPresented: $showingImportPicker) {
                    DocumentPickerView { url in
                        importFromFile(url: url)
                    }
                }
                .alert("Import Error", isPresented: .constant(importError != nil)) {
                    Button("OK") { importError = nil }
                } message: {
                    if let error = importError {
                        Text(error)
                    }
                }
                .alert("Import Successful", isPresented: .constant(importSuccess != nil)) {
                    Button("OK") { importSuccess = nil }
                } message: {
                    if let success = importSuccess {
                        Text(success)
                    }
                }
                .alert("Microphone Not Connected", isPresented: Binding(
                    get: { analyzer.microphoneWarning != nil },
                    set: { if !$0 { analyzer.microphoneWarning = nil } }
                )) {
                    Button("OK") { analyzer.microphoneWarning = nil }
                } message: {
                    Text(analyzer.microphoneWarning ?? "")
                }
                .overlay {
                    if isExporting {
                        LoadingOverlay(message: "Exporting measurements...")
                    } else if isGeneratingReport {
                        LoadingOverlay(message: "Generating PDF report...")
                    }
                }
        }
        #endif
    }
    
    @ViewBuilder
    private var contentView: some View {
        Group {
            if analyzer.savedMeasurements.isEmpty {
                // Empty state
                EmptyStateView(
                    icon: "tray",
                    title: "No Saved Measurements",
                    message: "Tap the guitar and click Save to store measurements for comparison."
                )
            } else {
                // Measurements list
                List {
                    Section {
                        Text("Total: \(analyzer.savedMeasurements.count) measurement\(analyzer.savedMeasurements.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    ForEach(analyzer.savedMeasurements) { measurement in
                        // Use Button for both platforms - macOS opens window, iOS shows sheet
                        Button(action: {
                            showDetail(for: measurement)
                        }) {
                            MeasurementRowView(measurement: measurement)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(action: {
                                analyzer.loadMeasurement(measurement)
                            }) {
                                Label("Load into View", systemImage: "arrow.down.doc")
                            }
                            
                            Divider()
                            
                            Button(action: {
                                showDetail(for: measurement)
                            }) {
                                Label("View Details", systemImage: "eye")
                            }
                            
                            Button(action: {
                                exportSingleMeasurement(measurement)
                            }) {
                                Label("Export as JSON/image", systemImage: "square.and.arrow.up")
                            }

                            Button(action: {
                                exportPDFReport(for: measurement)
                            }) {
                                Label("Export PDF Report", systemImage: "doc.richtext")
                            }

                            Divider()
                            
                            Button(role: .destructive, action: {
                                analyzer.deleteMeasurement(measurement)
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { index in
                            analyzer.deleteMeasurement(analyzer.savedMeasurements[index])
                        }
                    }
                }
            }
        }
        .navigationTitle("Saved Measurements")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingImportPicker = true }) {
                        Label("Import from JSON", systemImage: "square.and.arrow.down")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: deleteAll) {
                        Label("Delete All", systemImage: "trash")
                    }
                    .disabled(analyzer.savedMeasurements.isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingImportPicker = true }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive, action: deleteAll) {
                    Label("Delete All", systemImage: "trash")
                }
                .disabled(analyzer.savedMeasurements.isEmpty)
            }
            #endif
        }
    }
    
    private func exportSingleMeasurement(_ measurement: TapToneMeasurement) {
        isExporting = true
        analyzer.exportMeasurement(measurement) { json, measurement in
            MeasurementFileExporter.exportJSONAndImage(json: json, measurement: measurement) {
                self.isExporting = false
            }
        }
    }

    @MainActor
    private func exportPDFReport(for measurement: TapToneMeasurement) {
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
    
    private func deleteAll() {
        analyzer.savedMeasurements.removeAll()
    }
    
    private func showDetail(for measurement: TapToneMeasurement) {
        #if os(macOS)
        // On macOS, open in a new window to avoid nested sheet issues
        let detailView = MeasurementDetailView(measurement: measurement, analyzer: analyzer)
        let hostingController = NSHostingController(rootView: detailView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Measurement Details"
        window.setContentSize(NSSize(width: 600, height: 700))
        window.styleMask = [.titled, .closable, .resizable]
        window.makeKeyAndOrderFront(nil)
        
        let windowController = NSWindowController(window: window)
        windowController.showWindow(nil)
        
        // Store reference to prevent deallocation
        detailWindowController = windowController
        #else
        // On iOS, use sheet with item binding
        selectedMeasurement = measurement
        #endif
    }
    
    private func importFromFile(url: URL) {
        do {
            let data: Data
            
            // Handle security-scoped resource for sandboxed apps
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            data = try Data(contentsOf: url)
            let importedMeasurements = try analyzer.importMeasurements(from: data, baseURL: url)
            
            // If only 1 measurement was imported, automatically load it into the view
            var successMsg: String
            if importedMeasurements.count == 1, let measurement = importedMeasurements.first {
                analyzer.loadMeasurement(measurement)
                successMsg = "Successfully imported and loaded 1 measurement"
            } else {
                successMsg = "Successfully imported \(importedMeasurements.count) measurements"
            }

            // Fold any microphone warning into the success message so only one alert fires
            if let warning = analyzer.microphoneWarning {
                successMsg += "\n\n⚠️ " + warning
                analyzer.microphoneWarning = nil
            }
            importSuccess = successMsg
        } catch {
            importError = "Failed to import: \(error.localizedDescription)"
        }
    }
}

// MARK: - Document Picker View Wrapper

#if os(iOS)
/// A simple wrapper view for DocumentPicker that can be presented as a sheet
private struct DocumentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (URL) -> Void
    
    var body: some View {
        DocumentPickerRepresentable(onPick: { url in
            onPick(url)
            dismiss()
        })
        .ignoresSafeArea()
    }
}

/// UIViewControllerRepresentable that directly presents the picker
private struct DocumentPickerRepresentable: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        
        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                onPick(url)
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // Dismiss is handled by the wrapper view
        }
    }
}
#endif


