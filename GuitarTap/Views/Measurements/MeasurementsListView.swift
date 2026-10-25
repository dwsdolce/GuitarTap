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
/// Files opened via AirDrop or "Open in…" are imported by `TapToneAnalysisView`
/// (`Notification.Name.openMeasurementFile`, posted by `GuitarTapApp`), not here.
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

    /// True while any export/save panel is in flight — the actions guard on this so a repeated
    /// (or cross-type) click can't stack a second async, non-modal `NSSavePanel`.
    private var isExportPanelInFlight: Bool { isExporting || isGeneratingReport }
    @State private var showingImportPicker = false
    @State private var importError: String?
    /// An export's chart could not be drawn, so nothing was written.
    @State private var exportFailed = false
    @State private var importSuccess: String?
    @State private var selectedDetailTarget: (index: Int, measurement: TapToneMeasurement)?
    // Compare mode state
    @State private var isComparing: Bool = false
    @State private var selectedCompareIndices: Set<Int> = []
    @State private var hoveredMeasurementIndex: Int?
    @State private var measurementPendingDelete: (index: Int, measurement: TapToneMeasurement)?
    @State private var showingDeleteAllConfirmation = false
    @State private var showingDeleteDuplicatesConfirmation = false
    @State private var showingDeleteSelectedConfirmation = false
    // Delete › Selected…: ticking rows to delete, as compare mode ticks rows to compare.
    @State private var isSelectingToDelete = false
    @State private var selectedDeleteIndices: Set<Int> = []
    @State private var editTarget: (index: Int, measurement: TapToneMeasurement)?
    // Sort & Filter: what the list shows and in what order; the library keeps its own order.
    @State private var sort = TapDisplaySettings.savedMeasurementsSort
    @State private var ascending = TapDisplaySettings.savedMeasurementsAscending
    @State private var filter = TapDisplaySettings.savedMeasurementsFilter

    /// The positions in the library the list shows, in order.
    private var shownIndices: [Int] {
        SavedMeasurementsOrder.shown(SavedMeasurementsOrder.keys(analyzer.savedMeasurements),
                                     sort: sort, ascending: ascending, filter: filter)
    }
    #if os(macOS)
    @State private var detailWindowController: NSWindowController?
    #endif
    
    var body: some View {
        #if os(macOS)
        // macOS layout without NavigationStack wrapper (sheet handles its own window). The list behind AnyView,
        // which ends its type there, so `body`'s type stays shallow enough to decode on an iPhone's stack.
        AnyView(contentView)
            .frame(minWidth: 600, minHeight: 400)
            .sheetTitle("Saved Measurements")
            .paletteSurface(.backgroundPanel)
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
            .alert("Export Failed", isPresented: $exportFailed) {
                Button("OK") { }
            } message: {
                Text(ExportRenderError.message)
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
        #else
        // iOS layout with NavigationStack
        NavigationStack {
            AnyView(contentView)
                .paletteSurface(.backgroundPanel)
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
                .alert("Export Failed", isPresented: $exportFailed) {
                    Button("OK") { }
                } message: {
                    Text(ExportRenderError.message)
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
        }
        #endif
    }
    
    /// The line above the rows: the total, or — while a filter is on — how many of how many are shown, with an ×
    /// that shows all again.
    @ViewBuilder
    private var listCountLine: some View {
        let total = analyzer.savedMeasurements.count
        if let filter {
            HStack {
                Text("Showing \(shownIndices.count) of \(total) · \(filter)")
                Spacer()
                Button { self.filter = nil } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show all measurements")
            }
            .font(.caption)
            .foregroundColor(Palette.color(.textSecondary))
        } else {
            Text("Total: \(total) measurement\(total == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(Palette.color(.textSecondary))
        }
    }

    /// The list's rows, in the order shown.
    private var measurementRows: some View {
        List {
            ForEach(shownIndices, id: \.self) { index in
                let measurement = analyzer.savedMeasurements[index]
                Button(action: {
                    // Single tap: only acts in compare mode
                    if isComparing {
                        toggleCompareSelection(at: index, for: measurement)
                    } else if isSelectingToDelete {
                        toggleDeleteSelection(at: index)
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
                // Off in compare mode: while a double-tap gesture is attached, SwiftUI holds
                // every single click for the double-click interval, which made the compare
                // checkmarks lag the click.
                .gesture(
                    TapGesture(count: 2).onEnded {
                        let m = measurement
                        dismiss()
                        DispatchQueue.main.async {
                            analyzer.loadMeasurement(m)
                        }
                    },
                    including: isComparing || isSelectingToDelete ? .subviews : .all
                )
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
                .help(isComparing ? "Toggle selection for comparison"
                      : isSelectingToDelete ? "Toggle selection for deletion" : "Double-click to load measurement")
                .contextMenu { rowMenuContents(index: index, measurement: measurement) }
                #if os(macOS)
                // The row under the pointer on background.subtle, in every edition.
                .listRowBackground(hoveredMeasurementIndex == index ? Palette.color(.backgroundSubtle) : Color.clear)
                #endif
            }
            .onDelete { indexSet in
                // A row's position in the list shown → its place in the library.
                if let row = indexSet.first {
                    let index = shownIndices[row]
                    measurementPendingDelete = (index: index, measurement: analyzer.savedMeasurements[index])
                }
            }
            .paletteRows()
        }
    }

    @ViewBuilder
    var contentView: some View {
        Group {
            if analyzer.savedMeasurements.isEmpty {
                // Empty state
                EmptyStateView(
                    icon: "tray",
                    title: "No Saved Measurements",
                    message: "Tap the guitar and click Save to store measurements for comparison."
                )
            } else {
                // The total (or the filter's count) stays above the list; only the rows scroll.
                VStack(alignment: .leading, spacing: 0) {
                    listCountLine
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    // The rows behind AnyView, which ends their type there, so the list's type stays shallow
                    // enough to decode on an iPhone's stack.
                    AnyView(measurementRows)
                }
            }
        }
        .onChange(of: sort) { _, value in TapDisplaySettings.savedMeasurementsSort = value }
        .onChange(of: ascending) { _, value in TapDisplaySettings.savedMeasurementsAscending = value }
        .onChange(of: filter) { _, value in
            TapDisplaySettings.savedMeasurementsFilter = value
            // A measurement the filter hides cannot stay ticked for a comparison.
            selectedCompareIndices.formIntersection(shownIndices)
            selectedDeleteIndices.formIntersection(shownIndices)
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
        .alert("Delete Duplicates?", isPresented: $showingDeleteDuplicatesConfirmation) {
            Button("Delete", role: .destructive) { analyzer.deleteDuplicateMeasurements() }
            Button("Cancel", role: .cancel) { }
        } message: {
            let n = analyzer.duplicateMeasurementIndices.count
            Text("This will delete \(n) duplicate measurement\(n == 1 ? "" : "s"); the first copy of each is kept.")
        }
        .alert("Delete Selected Measurements?", isPresented: $showingDeleteSelectedConfirmation) {
            Button("Delete", role: .destructive) {
                analyzer.deleteMeasurements(at: selectedDeleteIndices)
                exitDeleteSelection()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let n = selectedDeleteIndices.count
            Text("This will permanently delete \(n) measurement\(n == 1 ? "" : "s"). This cannot be undone.")
        }
        .alert("Delete All Measurements?", isPresented: $showingDeleteAllConfirmation) {
            Button("Delete All", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            let n = analyzer.savedMeasurements.count
            Text("This will permanently delete all \(n) saved measurement\(n == 1 ? "" : "s"). This cannot be undone.")
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
                } else if isSelectingToDelete {
                    Button("Cancel") { exitDeleteSelection() }
                } else {
                    Button("Done") { dismiss() }
                }
            }

            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSelectingToDelete {
                    Button(role: .destructive, action: { showingDeleteSelectedConfirmation = true }) {
                        Text("Delete (\(selectedDeleteIndices.count))")
                            .fontWeight(.semibold)
                    }
                    .disabled(selectedDeleteIndices.isEmpty)
                } else if isComparing {
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
                SavedMeasurementsSortMenu(sort: $sort, ascending: $ascending, filter: $filter)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !isComparing && !isSelectingToDelete {
                    SavedMeasurementsMoreMenu(
                        isEmpty: analyzer.savedMeasurements.isEmpty,
                        hasDuplicates: !analyzer.duplicateMeasurementIndices.isEmpty,
                        importMeasurement: { showingImportPicker = true },
                        exportAll: { exportAllMeasurements() },
                        delete: deleteMenuActions
                    )
                }
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                if isSelectingToDelete {
                    Button(role: .destructive, action: { showingDeleteSelectedConfirmation = true }) {
                        Label("Delete (\(selectedDeleteIndices.count))", systemImage: "trash")
                    }
                    .disabled(selectedDeleteIndices.isEmpty)
                } else if isComparing {
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
                SavedMeasurementsSortMenu(sort: $sort, ascending: $ascending, filter: $filter)
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingImportPicker = true }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .disabled(isComparing || isSelectingToDelete)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: { exportAllMeasurements() }) {
                        Label("Export All… (Share / AirDrop)", systemImage: "square.and.arrow.up")
                    }
                    .menuIcons()
                    Button(action: { saveAllMeasurementsToDisk() }) {
                        Label("Save All to Disk…", systemImage: "arrow.down.doc")
                    }
                    .menuIcons()
                } label: {
                    Label("Export All", systemImage: "square.and.arrow.up")
                }
                .disabled(analyzer.savedMeasurements.isEmpty || isComparing || isSelectingToDelete)
                .help("Export the whole library as one .guitartap file (share/AirDrop or save to disk)")
            }

            ToolbarItem(placement: .primaryAction) {
                SavedMeasurementsDeleteMenu(hasDuplicates: !analyzer.duplicateMeasurementIndices.isEmpty,
                                            actions: deleteMenuActions)
                    .disabled(analyzer.savedMeasurements.isEmpty || isComparing || isSelectingToDelete)
            }
            #endif
        }
    }
    
    private func exportSingleMeasurement(_ measurement: TapToneMeasurement) {
        guard !isExportPanelInFlight else { return }   // re-entrancy: async NSSavePanel, cleared on every completion
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
        guard !isExportPanelInFlight else { return }
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
        guard !isExportPanelInFlight else { return }
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
        guard !isExportPanelInFlight else { return }
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
        guard !isExportPanelInFlight else { return }
        isExporting = true

        let imageData: Data?
        do {
            imageData = measurement.isComparison
                ? try renderSpectrumImageForComparison(measurement)
                : try renderSpectrumImageForMeasurement(measurement)
        } catch {
            isExporting = false
            exportFailed = true
            return
        }

        // PNG uses the "spectrum" default word, not baseFilename's "measurement".
        let stem = ExportFilename.stem(name: measurement.measurementName, timestamp: measurement.timestamp, unnamed: "spectrum")
        MeasurementFileExporter.exportSpectrumImage(imageData: imageData, basename: stem) {
            self.isExporting = false
        }
    }

    @MainActor
    private func exportPDFReport(for measurement: TapToneMeasurement) {
        guard !isExportPanelInFlight else { return }
        isGeneratingReport = true
        let report: (data: Data, basename: String)?
        do {
            report = try PDFReportGenerator.report(for: measurement)
        } catch {
            isGeneratingReport = false
            exportFailed = true
            return
        }
        guard let report else {
            gtLog("❌ Failed to generate PDF report")
            isGeneratingReport = false
            return
        }
        MeasurementFileExporter.exportPDF(data: report.data, basename: report.basename) {
            self.isGeneratingReport = false
        }
    }

    private func deleteAll() {
        analyzer.deleteAllMeasurements()
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

    /// The Delete menu's three choices: All…, Duplicates… and Selected….
    private var deleteMenuActions: SavedMeasurementsDeleteActions {
        SavedMeasurementsDeleteActions(
            all: { showingDeleteAllConfirmation = true },
            duplicates: { showingDeleteDuplicatesConfirmation = true },
            selected: { isSelectingToDelete = true; selectedDeleteIndices = [] }
        )
    }

    private func toggleDeleteSelection(at index: Int) {
        if selectedDeleteIndices.contains(index) {
            selectedDeleteIndices.remove(index)
        } else {
            selectedDeleteIndices.insert(index)
        }
    }

    private func exitDeleteSelection() {
        isSelectingToDelete = false
        selectedDeleteIndices = []
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
        // A saved measurement's menu, from its groups (`SavedMeasurementMenu`), a separator between them.
        ForEach(Array(SavedMeasurementMenu.groups.enumerated()), id: \.offset) { groupIndex, group in
            if groupIndex > 0 { Divider() }
            ForEach(group, id: \.action) { entry in
                if shows(entry) {
                    Button(role: entry.action == .delete ? .destructive : nil) {
                        perform(entry.action, index: index, measurement: measurement)
                    } label: {
                        Label(entry.title, systemImage: entry.symbol)
                    }
                }
            }
        }
        .menuIcons()
    }

    /// Whether this edition shows `entry`: the Mac-only item on the Mac alone.
    private func shows(_ entry: SavedMeasurementMenuEntry) -> Bool {
        #if os(macOS)
        true
        #else
        !entry.macOSOnly
        #endif
    }

    /// What a saved measurement's menu item does.
    private func perform(_ action: SavedMeasurementMenuEntry.Action, index: Int, measurement: TapToneMeasurement) {
        switch action {
        case .load:
            let m = measurement
            dismiss()
            DispatchQueue.main.async {
                analyzer.loadMeasurement(m)
            }
        case .details:
            showDetail(index: index, measurement: measurement)
        case .edit:
            editTarget = (index: index, measurement: measurement)
        case .exportMeasurement:
            exportSingleMeasurement(measurement)
        case .saveToDisk:
            #if os(macOS)
            saveMeasurementToDisk(measurement)
            #endif
        case .exportSpectrum:
            exportSpectrumMeasurement(measurement)
        case .exportPDF:
            exportPDFReport(for: measurement)
        case .delete:
            measurementPendingDelete = (index: index, measurement: measurement)
        }
    }

    @ViewBuilder
    private func compareRowContent(at index: Int, for measurement: TapToneMeasurement) -> some View {
        let isHovered = hoveredMeasurementIndex == index
        if isComparing || isSelectingToDelete {
            // Any measurement can be deleted; only one with a spectrum can be compared.
            let comparable = isSelectingToDelete || isComparable(measurement)
            let selected = isSelectingToDelete ? selectedDeleteIndices.contains(index) : selectedCompareIndices.contains(index)
            // A measurement that cannot be compared dims as one group — its circle and its row.
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(Palette.color(selected ? .accentText : .textSecondary))
                MeasurementRowView(measurement: measurement, isHovered: isHovered) { rowMenuContents(index: index, measurement: measurement) }
            }
            .opacity(comparable ? 1.0 : Palette.opacity(.controlNotApplicable))
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
            importSuccess = try analyzer.importAndLoadMeasurements(from: data)
        } catch {
            importError = TapToneAnalyzer.importErrorMessage(for: error, fileName: url.lastPathComponent)
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



// MARK: - Sort & Filter

/// Saved Measurements' Sort & Filter menu: the sort — choosing the ticked one again reverses it, the arrow showing
/// which way — and the one type shown, or all. Its own view, so the list's type stays shallow.
struct SavedMeasurementsSortMenu: View {
    @Binding var sort: SavedMeasurementsSort
    @Binding var ascending: Bool
    @Binding var filter: String?

    var body: some View {
        Menu {
            Section("Sort by") {
                // Toggles, which a menu draws with the system's tick (a Label's icon is not shown in a macOS menu).
                ForEach(SavedMeasurementsSort.allCases) { key in
                    Toggle(isOn: Binding(
                        get: { key == sort },
                        set: { _ in
                            if key == sort { ascending.toggle() } else { sort = key; ascending = true }
                        }
                    )) {
                        Text(key == sort ? "\(key.title)  \(ascending ? "↑" : "↓")" : key.title)
                    }
                }
            }
            Section("Show") {
                filterItem("All", value: nil)
                ForEach(SavedMeasurementsOrder.filterTypes, id: \.self) { type in
                    filterItem(type, value: type)
                }
            }
        } label: {
            Label("Sort & Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Sort the list, or show one type of measurement")
    }

    private func filterItem(_ title: String, value: String?) -> some View {
        Toggle(title, isOn: Binding(get: { filter == value }, set: { _ in filter = value }))
    }
}

#if os(iOS)
/// Saved Measurements' More (⋯) menu on iPad and iPhone.
struct SavedMeasurementsMoreMenu: View {
    let isEmpty: Bool
    let hasDuplicates: Bool
    let importMeasurement: () -> Void
    let exportAll: () -> Void
    let delete: SavedMeasurementsDeleteActions

    var body: some View {
        Menu {
            Button(action: importMeasurement) {
                Label("Import Measurement", systemImage: "square.and.arrow.down")
            }

            Button(action: exportAll) {
                Label("Export All Measurements", systemImage: "square.and.arrow.up")
            }
            .disabled(isEmpty)

            Divider()

            Menu {
                SavedMeasurementsDeleteItems(hasDuplicates: hasDuplicates, actions: delete)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(isEmpty)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }
}
#endif

// MARK: - Delete

/// The Delete menu's three choices.
struct SavedMeasurementsDeleteActions {
    let all: () -> Void
    let duplicates: () -> Void
    let selected: () -> Void
}

/// The Delete menu's items: All… (every measurement), Duplicates… (every later copy of a measurement already in the
/// library — disabled when there are none) and Selected… (tick the rows to delete, as compare mode does).
struct SavedMeasurementsDeleteItems: View {
    let hasDuplicates: Bool
    let actions: SavedMeasurementsDeleteActions

    var body: some View {
        Button(role: .destructive, action: actions.all) {
            Label("All…", systemImage: "trash")
        }
        Button(role: .destructive, action: actions.duplicates) {
            Label("Duplicates…", systemImage: "square.on.square")
        }
        .disabled(!hasDuplicates)
        Button(action: actions.selected) {
            Label("Selected…", systemImage: "checkmark.circle")
        }
    }
}

/// Saved Measurements' Delete menu in the toolbar (macOS).
struct SavedMeasurementsDeleteMenu: View {
    let hasDuplicates: Bool
    let actions: SavedMeasurementsDeleteActions

    var body: some View {
        Menu {
            SavedMeasurementsDeleteItems(hasDuplicates: hasDuplicates, actions: actions).menuIcons()
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .help("Delete all measurements, the duplicates, or the ones you select")
    }
}
