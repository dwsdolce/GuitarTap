//
//  MeasurementsListView.swift
//  GuitarTap
//
// @parity view/measurements-list

/// # MeasurementsListView
///
/// Sheet-presented list of all saved `TapToneMeasurement` records, with
/// import, export, and detail-navigation capabilities.
///
/// ## Custom UTType
///
/// `UTType.guitarTapMeasurement` (`com.dolcesfogato.guitartap.measurement`)
/// is declared here and in `Info.plist` so that `.guitartap` files can be
/// opened from Mail, AirDrop, and the Files app.
///
/// ## Platform Differences
///
/// | Feature | macOS | iOS |
/// |---|---|---|
/// | Detail navigation | `NSWindowController` (`detailWindowController`) | `NavigationLink` |
/// | Import | `.fileImporter` with `UTType.guitarTapMeasurement` | `DocumentPicker` |
/// | Export (JSON) | `MeasurementFileExporter.exportJSON` → `NSSavePanel` | Share sheet |
///
/// ## Import Flow
///
/// The file importer / document picker calls `importFromFile(url:)`, which
/// uses a security-scoped access pair (`startAccessingSecurityScopedResource`
/// / `stopAccessingSecurityScopedResource`) to read `.guitartap` files
/// outside the app sandbox, then calls `TapToneAnalyzer.importMeasurement`.
///
/// ## AirDrop / Open-URL
///
/// Files opened via AirDrop or "Open in…" are routed through
/// `Notification.Name.openMeasurementFile` posted by `GuitarTapApp`. This
/// view observes the notification and calls `importFromFile(url:)` when
/// received.
///
/// - SeeAlso: `MeasurementDetailView`, `MeasurementFileExporter`

import SwiftUI
internal import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension UTType {
    /// GuitarTap measurement file (.guitartap). Conforms to public.json.
    static let guitarTapMeasurement = UTType(exportedAs: "com.dolcesfogato.guitartap.measurement")
}

struct MeasurementsListView: View {
    @ObservedObject var analyzer: TapToneAnalyzer
    @Environment(\.dismiss) var dismiss
    @State private var isExporting = false  // Track export progress
    @State private var isGeneratingReport = false
    @State private var showingImportPicker = false
    @State private var importError: String?
    @State private var importSuccess: String?
    @State private var selectedDetailTarget: (index: Int, measurement: TapToneMeasurement)?
    // Compare mode state
    @State private var isComparing: Bool = false
    @State private var selectedCompareIndices: Set<Int> = []
    @State private var hoveredMeasurementIndex: Int?
    @State private var measurementPendingDelete: (index: Int, measurement: TapToneMeasurement)?
    @State private var showingDeleteAllConfirmation = false
    @State private var editTarget: (index: Int, measurement: TapToneMeasurement)?
    #if os(macOS)
    @State private var detailWindowController: NSWindowController?
    #endif
    
    var body: some View {
        #if os(macOS)
        // macOS layout without NavigationView wrapper (sheet handles its own window)
        contentView
            .frame(minWidth: 600, minHeight: 400)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Text("Saved Measurements")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    Divider()
                }
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.guitarTapMeasurement, .json],
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
            // Use only a previously user-selected directory as the default — never a
            // programmatically constructed path.  A synthetic ~/Documents/GuitarTap URL
            // has no sandbox extension; the fileImporter may navigate there but the
            // resulting URL can fail Data(contentsOf:) with EPERM.
            // Note: fileDialogCustomizationID is intentionally absent — it would cause
            // macOS to persist its own directory preference for the panel, overriding
            // the lastUsedDirectory hint on subsequent launches.
            .fileDialogDefaultDirectory(MeasurementFileExporter.lastUsedDirectory)
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
                .sheet(isPresented: Binding(
                    get: { selectedDetailTarget != nil },
                    set: { if !$0 { selectedDetailTarget = nil } }
                )) {
                    if let target = selectedDetailTarget {
                        MeasurementDetailView(index: target.index, measurement: target.measurement, analyzer: analyzer)
                    }
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
                    
                    ForEach(Array(analyzer.savedMeasurements.enumerated()), id: \.offset) { index, measurement in
                        Button(action: {
                            // Single tap: only acts in compare mode
                            if isComparing {
                                toggleCompareSelection(at: index, for: measurement)
                            }
                        }) {
                            compareRowContent(at: index, for: measurement)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // Double-tap loads the measurement and dismisses the list.
                        // Dismiss first so the sheet is gone before loadMeasurement()
                        // sets @Published properties (including microphoneWarning).
                        // The load is deferred so the sheet teardown completes cleanly
                        // and the mic warning alert fires only on the main view.
                        .onTapGesture(count: 2) {
                            if !isComparing {
                                let m = measurement
                                dismiss()
                                DispatchQueue.main.async {
                                    analyzer.loadMeasurement(m)
                                }
                            }
                        }
                        #if os(macOS)
                        .onHover { inside in
                            hoveredMeasurementIndex = inside ? index : nil
                            if inside {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        #endif
                        .help(isComparing ? "Toggle selection for comparison" : "Double-click to load measurement")
                        .contextMenu { rowMenuContents(index: index, measurement: measurement) }
                    }
                    .onDelete { indexSet in
                        if let index = indexSet.first {
                            measurementPendingDelete = (index: index, measurement: analyzer.savedMeasurements[index])
                        }
                    }
                }
            }
        }
        .alert("Delete Measurement?", isPresented: Binding(
            get: { measurementPendingDelete != nil },
            set: { if !$0 { measurementPendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let target = measurementPendingDelete {
                    analyzer.deleteMeasurement(at: target.index)
                }
                measurementPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                measurementPendingDelete = nil
            }
        } message: {
            if let target = measurementPendingDelete {
                Text("Are you sure you want to delete \"\(target.measurement.measurementName ?? "Measurement")\"? This cannot be undone.")
            }
        }
        .alert("Delete All Measurements?", isPresented: $showingDeleteAllConfirmation) {
            Button("Delete All", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete all \(analyzer.savedMeasurements.count) saved measurements. This cannot be undone.")
        }
        .sheet(isPresented: Binding(
            get: { editTarget != nil },
            set: { if !$0 { editTarget = nil } }
        )) {
            if let target = editTarget {
                EditMeasurementView(index: target.index, measurement: target.measurement, analyzer: analyzer)
            }
        }
        .navigationTitle("Saved Measurements")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if isComparing {
                    Button("Cancel") { exitCompareMode() }
                } else {
                    Button("Done") { dismiss() }
                }
            }

            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                if isComparing {
                    Button(action: openComparison) {
                        Text("Compare (\(selectedCompareIndices.count))")
                            .fontWeight(.semibold)
                    }
                    .disabled(selectedCompareIndices.count < 2)
                } else {
                    Button(action: { isComparing = true }) {
                        Label("Compare", systemImage: "waveform.path")
                    }
                    .disabled(comparableMeasurements.count < 2)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !isComparing {
                    Menu {
                        Button(action: { showingImportPicker = true }) {
                            Label("Import Measurement", systemImage: "square.and.arrow.down")
                        }

                        Button(action: { exportAllMeasurements() }) {
                            Label("Export All Measurements", systemImage: "square.and.arrow.up")
                        }
                        .disabled(analyzer.savedMeasurements.isEmpty)

                        Divider()

                        Button(role: .destructive, action: { showingDeleteAllConfirmation = true }) {
                            Label("Delete All", systemImage: "trash")
                        }
                        .disabled(analyzer.savedMeasurements.isEmpty)
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                if isComparing {
                    Button(action: openComparison) {
                        Label("Compare (\(selectedCompareIndices.count))", systemImage: "waveform.path")
                    }
                    .disabled(selectedCompareIndices.count < 2)
                } else {
                    Button(action: { isComparing = true }) {
                        Label("Compare…", systemImage: "waveform.path")
                    }
                    .disabled(comparableMeasurements.count < 2)
                    .help("Select measurements to overlay on a comparison chart")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingImportPicker = true }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .disabled(isComparing)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: { exportAllMeasurements() }) {
                        Label("Export All… (Share / AirDrop)", systemImage: "square.and.arrow.up")
                    }
                    Button(action: { saveAllMeasurementsToDisk() }) {
                        Label("Save All to Disk…", systemImage: "arrow.down.doc")
                    }
                } label: {
                    Label("Export All", systemImage: "square.and.arrow.up")
                }
                .disabled(analyzer.savedMeasurements.isEmpty || isComparing)
                .help("Export the whole library as one .guitartap file (share/AirDrop or save to disk)")
            }

            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive, action: { showingDeleteAllConfirmation = true }) {
                    Label("Delete All", systemImage: "trash")
                }
                .disabled(analyzer.savedMeasurements.isEmpty || isComparing)
            }
            #endif
        }
    }
    
    private func exportSingleMeasurement(_ measurement: TapToneMeasurement) {
        isExporting = true
        analyzer.exportMeasurement(measurement) { json, measurement in
            MeasurementFileExporter.exportJSON(json: json, measurement: measurement) {
                self.isExporting = false
            }
        }
    }

    /// Export the whole library as one `.guitartap` file (backup / migration to another
    /// platform or browser). Reuses the JSON form persisted to saved_measurements.json.
    private func exportAllMeasurements() {
        guard !analyzer.savedMeasurements.isEmpty else { return }
        isExporting = true
        analyzer.exportAllMeasurements { json in
            let name = "guitartap-library-\(Int(Date().timeIntervalSince1970))"
            MeasurementFileExporter.exportJSON(json: json, suggestedName: name) {
                self.isExporting = false
            }
        }
    }

    #if os(macOS)
    private func saveMeasurementToDisk(_ measurement: TapToneMeasurement) {
        isExporting = true
        analyzer.exportMeasurement(measurement) { json, measurement in
            MeasurementFileExporter.saveMeasurementToDisk(json: json, measurement: measurement) {
                self.isExporting = false
            }
        }
    }

    /// Save the whole library to a chosen file via NSSavePanel (macOS "Save All to Disk…").
    private func saveAllMeasurementsToDisk() {
        guard !analyzer.savedMeasurements.isEmpty else { return }
        isExporting = true
        analyzer.exportAllMeasurements { json in
            let name = "guitartap-library-\(Int(Date().timeIntervalSince1970))"
            MeasurementFileExporter.saveMeasurementsToDisk(json: json, suggestedName: name) {
                self.isExporting = false
            }
        }
    }
    #endif

    @MainActor
    private func exportSpectrumMeasurement(_ measurement: TapToneMeasurement) {
        isExporting = true

        let imageData: Data? = measurement.isComparison
            ? renderSpectrumImageForComparison(measurement)
            : renderSpectrumImageForMeasurement(measurement)

        // PNG uses the "spectrum" default word, not baseFilename's "measurement" (§2b).
        let stem = ExportFilename.stem(name: measurement.measurementName, timestamp: measurement.timestamp, unnamed: "spectrum")
        MeasurementFileExporter.exportSpectrumImage(imageData: imageData, basename: stem) {
            self.isExporting = false
        }
    }

    @MainActor
    private func exportPDFReport(for measurement: TapToneMeasurement) {
        isGeneratingReport = true
        let spectrumImageData = renderSpectrumImageForMeasurement(measurement)
        let reportData = PDFReportData.from(measurement: measurement, spectrumImageData: spectrumImageData)
        guard let pdfData = PDFReportGenerator.generate(data: reportData) else {
            gtLog("❌ Failed to generate PDF report")
            isGeneratingReport = false
            return
        }
        MeasurementFileExporter.exportPDF(data: pdfData, basename: reportData.baseFilename) {
            self.isGeneratingReport = false
        }
    }

    /// Generates a two-page PDF for a saved multi-tap guitar measurement:
    /// page 1 is the averaged result report, page 2 is the per-tap comparison report.
    @MainActor
    private func exportMultiTapPDFReport(for measurement: TapToneMeasurement) {
        guard let tapEntries = measurement.tapEntries, !tapEntries.isEmpty else { return }
        isGeneratingReport = true

        // Page 1 — averaged spectrum image and report data
        let avgImageData = renderSpectrumImageForMeasurement(measurement)
        let avgReportData = PDFReportData.from(measurement: measurement, spectrumImageData: avgImageData)

        // Page 2 — per-tap comparison overlay image
        let cmpImageData = renderSpectrumImageForMultiTap(measurement)

        // Build ComparisonPDFReportData from tapEntries
        let palette: [Color] = [.blue, .orange, .green, .purple, .teal]
        let avgColor = TapToneAnalyzer.multiTapAvgColor

        var cmpEntries: [ComparisonEntry] = tapEntries.enumerated().map { index, entry in
            let color = palette[index % palette.count]
            let cgColor = color.cgColor ?? color.resolve(in: .init()).cgColor
            let comps: [Double]
            if let c = cgColor.components, c.count >= 3 {
                comps = [Double(c[0]), Double(c[1]), Double(c[2]), c.count >= 4 ? Double(c[3]) : 1.0]
            } else { comps = [0.0, 0.0, 1.0, 1.0] }
            let selectedIDs = Set(entry.selectedPeakIDs)
            return ComparisonEntry(id: UUID(), label: "Tap \(entry.tapIndex)",
                colorComponents: comps, snapshot: entry.snapshot,
                peaks: entry.peaks.filter { selectedIDs.contains($0.id) },
                guitarType: entry.snapshot.guitarType, sourceMeasurementID: nil)
        }
        // Averaged entry from the measurement's stored averaged snapshot + peaks
        if let avgSnap = measurement.spectrumSnapshot {
            let avgCGColor = avgColor.cgColor ?? avgColor.resolve(in: .init()).cgColor
            let avgComps: [Double]
            if let c = avgCGColor.components, c.count >= 3 {
                avgComps = [Double(c[0]), Double(c[1]), Double(c[2]), c.count >= 4 ? Double(c[3]) : 1.0]
            } else { avgComps = [1.0, 0.85, 0.0, 1.0] }
            let selectedIDs = Set(measurement.selectedPeakIDs ?? measurement.peaks.map { $0.id })
            cmpEntries.append(ComparisonEntry(id: UUID(), label: "Averaged",
                colorComponents: avgComps, snapshot: avgSnap,
                peaks: measurement.peaks.filter { selectedIDs.contains($0.id) },
                guitarType: measurement.spectrumSnapshot?.guitarType, sourceMeasurementID: nil))
        }

        let modeFrequencies = cmpEntries.map { entry in
            let c = entry.colorComponents
            let color = Color(red: c[0], green: c[1], blue: c[2], opacity: c.count >= 4 ? c[3] : 1.0)
            let modePeaks = TapToneAnalyzer.resolvedModePeaks(peaks: entry.peaks, guitarType: entry.guitarType)
            return (label: entry.label, color: color,
                    air: modePeaks[.air]?.frequency, top: modePeaks[.top]?.frequency, back: modePeaks[.back]?.frequency)
        }

        let cmpReportData = ComparisonPDFReportData(
            timestamp: measurement.timestamp,
            comparisonLabel: measurement.measurementName,
            notes: measurement.notes,
            spectrumImageData: cmpImageData,
            entries: cmpEntries,
            modeFrequencies: modeFrequencies
        )

        guard let pdfData = PDFReportGenerator.generateMultiTapReport(
            averaged: avgReportData, comparison: cmpReportData) else {
            gtLog("❌ Failed to generate multi-tap PDF report")
            isGeneratingReport = false
            return
        }
        MeasurementFileExporter.exportPDF(data: pdfData, basename: avgReportData.baseFilename) {
            self.isGeneratingReport = false
        }
    }

    @MainActor
    private func exportComparisonPDFReport(for measurement: TapToneMeasurement) {
        guard let entries = measurement.comparisonEntries else { return }
        isGeneratingReport = true

        let spectrumImageData = renderSpectrumImageForComparison(measurement)

        // Build per-entry mode frequency rows
        let modeFrequencies = entries.map { entry in
            let c = entry.colorComponents
            let color = Color(red: c[0], green: c[1], blue: c[2], opacity: c.count >= 4 ? c[3] : 1.0)
            let modePeaks = TapToneAnalyzer.resolvedModePeaks(peaks: entry.peaks, guitarType: entry.guitarType)
            return (
                label: entry.label,
                color: color,
                air:  modePeaks[.air]?.frequency,
                top:  modePeaks[.top]?.frequency,
                back: modePeaks[.back]?.frequency
            )
        }

        let reportData = ComparisonPDFReportData(
            timestamp: measurement.timestamp,
            comparisonLabel: measurement.measurementName,
            notes: measurement.notes,
            spectrumImageData: spectrumImageData,
            entries: entries,
            modeFrequencies: modeFrequencies
        )

        // A comparison report is just a report (§2b): "report" default, not "measurement".
        let basename = ExportFilename.stem(name: measurement.measurementName, timestamp: measurement.timestamp, unnamed: "report")

        guard let pdfData = PDFReportGenerator.generateComparison(data: reportData) else {
            gtLog("❌ Failed to generate comparison PDF report")
            isGeneratingReport = false
            return
        }
        MeasurementFileExporter.exportPDF(data: pdfData, basename: basename) {
            self.isGeneratingReport = false
        }
    }

    private func deleteAll() {
        analyzer.savedMeasurements.removeAll()
    }
    
    private func showDetail(index: Int, measurement: TapToneMeasurement) {
        #if os(macOS)
        // On macOS, open in a new window to avoid nested sheet issues
        let detailView = MeasurementDetailView(index: index, measurement: measurement, analyzer: analyzer)
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
        selectedDetailTarget = (index: index, measurement: measurement)
        #endif
    }
    
    // MARK: - Compare Mode Helpers

    /// Guitar measurements that have a spectrum snapshot (eligible for comparison).
    private var comparableMeasurements: [TapToneMeasurement] {
        analyzer.savedMeasurements.filter { $0.spectrumSnapshot != nil }
    }

    /// Whether a measurement can be selected in compare mode.
    private func isComparable(_ measurement: TapToneMeasurement) -> Bool {
        measurement.spectrumSnapshot != nil
    }

    /// The measurements currently selected for comparison, in list order.
    private var selectedCompareMeasurements: [TapToneMeasurement] {
        analyzer.savedMeasurements.enumerated()
            .filter { selectedCompareIndices.contains($0.offset) }
            .map { $0.element }
    }

    private func toggleCompareSelection(at index: Int, for measurement: TapToneMeasurement) {
        guard isComparable(measurement) else { return }
        if selectedCompareIndices.contains(index) {
            selectedCompareIndices.remove(index)
        } else {
            selectedCompareIndices.insert(index)
        }
    }

    private func exitCompareMode() {
        isComparing = false
        selectedCompareIndices = []
    }

    private func openComparison() {
        guard selectedCompareIndices.count >= 2 else { return }
        analyzer.loadComparison(measurements: selectedCompareMeasurements)
        exitCompareMode()
        dismiss()
    }

    /// Row content that adds a selection checkbox overlay when in compare mode.
    @ViewBuilder
    private func rowMenuContents(index: Int, measurement: TapToneMeasurement) -> some View {
        Button(action: {
            let m = measurement
            dismiss()
            DispatchQueue.main.async {
                analyzer.loadMeasurement(m)
            }
        }) {
            Label("Load into View", systemImage: "arrow.down.doc")
        }
        
        Divider()
        
        Button(action: {
            showDetail(index: index, measurement: measurement)
        }) {
            Label("View Details", systemImage: "eye")
        }

        Button(action: {
            editTarget = (index: index, measurement: measurement)
        }) {
            Label("Edit Name & Notes", systemImage: "pencil")
        }

        Button(action: {
            exportSingleMeasurement(measurement)
        }) {
            Label("Export Measurement", systemImage: "doc.badge.arrow.up")
        }

        #if os(macOS)
        Button(action: {
            saveMeasurementToDisk(measurement)
        }) {
            Label("Save Measurement to Disk…", systemImage: "arrow.down.doc")
        }
        #endif

        Button(action: {
            exportSpectrumMeasurement(measurement)
        }) {
            Label("Export Spectrum", systemImage: "chart.line.uptrend.xyaxis")
        }

        Button(action: {
            if measurement.tapEntries?.isEmpty == false {
                exportMultiTapPDFReport(for: measurement)
            } else if measurement.isComparison {
                exportComparisonPDFReport(for: measurement)
            } else {
                exportPDFReport(for: measurement)
            }
        }) {
            Label("Export PDF Report", systemImage: "doc.richtext")
        }

        Divider()
        
        Button(role: .destructive, action: {
            measurementPendingDelete = (index: index, measurement: measurement)
        }) {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func compareRowContent(at index: Int, for measurement: TapToneMeasurement) -> some View {
        let isHovered = hoveredMeasurementIndex == index
        if isComparing {
            HStack(spacing: 10) {
                let comparable = isComparable(measurement)
                let selected = selectedCompareIndices.contains(index)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(selected ? .accentColor : (comparable ? .secondary : .secondary.opacity(0.4)))
                MeasurementRowView(measurement: measurement, isHovered: isHovered) { rowMenuContents(index: index, measurement: measurement) }
                    .opacity(comparable ? 1.0 : 0.4)
            }
        } else {
            MeasurementRowView(measurement: measurement, isHovered: isHovered) { rowMenuContents(index: index, measurement: measurement) }
        }
    }

    private func importFromFile(url: URL) {
        // Update the shared last-used directory so subsequent save panels open here.
        #if os(macOS)
        MeasurementFileExporter.lastUsedDirectory = url.deletingLastPathComponent()
        #endif
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
            let importedMeasurements = try analyzer.importMeasurements(from: data)
            
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
            importError = importErrorMessage(for: error, url: url)
        }
    }

    /// Returns a user-facing error message for an import failure.
    /// Provides actionable guidance when the failure is a sandbox permission error.
    private func importErrorMessage(for error: Error, url: URL) -> String {
        let nsError = error as NSError
        let isPermissionError = (nsError.domain == NSPOSIXErrorDomain && nsError.code == 1) ||
                                (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError)
        let isFormatError = nsError.domain == NSCocoaErrorDomain &&
                            (nsError.code == NSFileReadCorruptFileError || nsError.code == 4864 /* Swift.DecodingError */)
        if isPermissionError {
            return "Could not read \"\(url.lastPathComponent)\": the system denied access (error \(nsError.code))."
        }
        if isFormatError {
            return "Could not import \"\(url.lastPathComponent)\": the file is not a valid GuitarTap measurement."
        }
        return "Could not import \"\(url.lastPathComponent)\": \(error.localizedDescription)"
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
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.guitarTapMeasurement, .json])
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


