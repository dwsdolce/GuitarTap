//
//  MeasurementsListView.swift
//  GuitarTap
//
//  Created by David Smith on 2/9/26.
//
import SwiftUI
internal import UniformTypeIdentifiers

struct MeasurementsListView: View {
    @ObservedObject var analyzer: TapToneAnalyzer
    @Environment(\.dismiss) var dismiss
    @State private var showingExport = false
    @State private var exportText = ""
    @State private var isExporting = false  // Track export progress
    @State private var showingImportPicker = false
    @State private var importError: String?
    @State private var importSuccess: String?
    @State private var selectedMeasurement: TapToneMeasurement?
    @State private var detailWindowController: NSWindowController?
    
    var body: some View {
        #if os(macOS)
        // macOS layout without NavigationView wrapper (sheet handles its own window)
        contentView
            .frame(minWidth: 600, minHeight: 400)
            .sheet(isPresented: $showingExport) {
                ExportView(text: exportText)
            }
            .background(importSheet)
            .overlay {
                if isExporting {
                    LoadingOverlay(message: "Exporting measurements...")
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
                .background(importSheet)
                .overlay {
                    if isExporting {
                        LoadingOverlay(message: "Exporting measurements...")
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
                                showDetail(for: measurement)
                            }) {
                                Label("View Details", systemImage: "eye")
                            }
                            
                            Button(action: {
                                exportSingleMeasurement(measurement)
                            }) {
                                Label("Export as JSON/image", systemImage: "square.and.arrow.up")
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
}

extension MeasurementsListView {
    var importSheet: some View {
        Group {
            #if os(iOS)
            if showingImportPicker {
                DocumentPicker(isPresented: $showingImportPicker) { url in
                    importFromFile(url: url)
                }
            }
            #endif
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
        #if os(macOS)
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
            let count = try analyzer.importMeasurements(from: data, baseURL: url)
            importSuccess = "Successfully imported \(count) measurement\(count == 1 ? "" : "s")"
        } catch {
            importError = "Failed to import: \(error.localizedDescription)"
        }
    }
}
