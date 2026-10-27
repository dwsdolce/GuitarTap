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
/// | Export (`.guitartap`, image, PDF) | `MeasurementFileExporter.deliver` → `NSSavePanel` | — |
/// | Share | `MeasurementFileExporter.deliver` → `NSSharingServicePicker` | Share sheet |
///
/// ## Import Flow
///
/// The file importer / document picker calls `importFiles(_:)`, which
/// uses a security-scoped access pair (`startAccessingSecurityScopedResource`
/// / `stopAccessingSecurityScopedResource`) to read `.guitartap` files
/// outside the app sandbox, then calls `TapToneAnalyzer.importFiles(_:)`.
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
    /// What a select mode is ticking rows for — Delete › Selected…, or the library menu's Export Selected… or
    /// Share Selected… — as compare mode ticks rows to compare; nil when no select mode is on.
    @State private var selectingFor: SelectionPurpose?
    @State private var selectedIndices: Set<Int> = []
    private var isSelecting: Bool { selectingFor != nil }
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
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    if !urls.isEmpty {
                        importFiles(urls)
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
                    DocumentPickerView { urls in
                        importFiles(urls)
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
                    } else if isSelecting {
                        toggleSelection(at: index)
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
                    including: isComparing || isSelecting ? .subviews : .all
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
                      : selectingFor?.rowHelp ?? "Double-click to load measurement")
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
            selectedIndices.formIntersection(shownIndices)
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
                analyzer.deleteMeasurements(at: selectedIndices)
                exitSelection()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let n = selectedIndices.count
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
                } else if isSelecting {
                    Button("Cancel") { exitSelection() }
                } else {
                    Button("Done") { dismiss() }
                }
            }

            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                if let purpose = selectingFor {
                    Button(role: purpose == .delete ? .destructive : nil, action: { confirmSelection(purpose) }) {
                        Text("\(purpose.verb) (\(selectedIndices.count))")
                            .fontWeight(.semibold)
                    }
                    .disabled(selectedIndices.isEmpty)
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
                if !isComparing && !isSelecting {
                    SavedMeasurementsMoreMenu(
                        isEmpty: analyzer.savedMeasurements.isEmpty,
                        hasDuplicates: !analyzer.duplicateMeasurementIndices.isEmpty,
                        importMeasurement: { showingImportPicker = true },
                        panel: { performPanel($0) },
                        delete: deleteMenuActions
                    )
                }
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                if let purpose = selectingFor {
                    Button(role: purpose == .delete ? .destructive : nil, action: { confirmSelection(purpose) }) {
                        Label("\(purpose.verb) (\(selectedIndices.count))", systemImage: purpose.symbol)
                    }
                    .disabled(selectedIndices.isEmpty)
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
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                .disabled(isComparing || isSelecting)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ExportMenuItems(groups: ExportMenus.panel.entries(for: .current)) { performPanel($0) }
                } label: {
                    Label(ExportMenus.panel.button(for: .current), systemImage: ExportMenus.panel.symbol)
                }
                .disabled(analyzer.savedMeasurements.isEmpty || isComparing || isSelecting)
                .help("Share or export all the measurements, or the ones you select, as one .guitartap file")
            }

            ToolbarItem(placement: .primaryAction) {
                SavedMeasurementsDeleteMenu(hasDuplicates: !analyzer.duplicateMeasurementIndices.isEmpty,
                                            actions: deleteMenuActions)
                    .disabled(analyzer.savedMeasurements.isEmpty || isComparing || isSelecting)
            }
            #endif
        }
    }
    
    /// Exports or shares one measurement as its own `.guitartap` file.
    private func deliverMeasurement(_ measurement: TapToneMeasurement, as delivery: FileDelivery) {
        deliverMeasurements([measurement], filename: measurement.baseFilename, as: delivery)
    }

    /// Exports or shares `measurements` as one `.guitartap` file named `filename` — the form Import reads back.
    private func deliverMeasurements(_ measurements: [TapToneMeasurement], filename: String,
                                     as delivery: FileDelivery) {
        guard !measurements.isEmpty else { return }
        guard !isExportPanelInFlight else { return }   // re-entrancy: async NSSavePanel, cleared on every completion
        isExporting = true
        analyzer.exportMeasurements(measurements) { json in
            MeasurementFileExporter.deliver(Data(json.utf8), filename: "\(filename).guitartap",
                                            contentType: .guitarTapMeasurement, as: delivery) {
                self.isExporting = false
            }
        }
    }

    /// What an item of the library menu (Export on the Mac, Share on iOS) does: All shares or exports the whole
    /// library at once; Selected ticks the measurements first.
    private func performPanel(_ action: ExportMenus.PanelAction) {
        let stamp = Int(Date().timeIntervalSince1970)
        switch action {
        case .shareAll:
            deliverMeasurements(analyzer.savedMeasurements, filename: "guitartap-library-\(stamp)", as: .share)
        case .exportAll:
            deliverMeasurements(analyzer.savedMeasurements, filename: "guitartap-library-\(stamp)", as: .export)
        case .shareSelected:
            startSelection(.share)
        case .exportSelected:
            startSelection(.export)
        }
    }

    @MainActor
    private func exportSpectrumMeasurement(_ measurement: TapToneMeasurement, as delivery: FileDelivery) {
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
        guard let imageData else {
            isExporting = false
            return
        }
        MeasurementFileExporter.deliver(imageData, filename: "\(stem).png", contentType: .png, as: delivery) {
            self.isExporting = false
        }
    }

    @MainActor
    private func exportPDFReport(for measurement: TapToneMeasurement, as delivery: FileDelivery) {
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
        MeasurementFileExporter.deliver(report.data, filename: "\(report.basename).pdf", contentType: .pdf,
                                        as: delivery) {
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
            selected: { startSelection(.delete) }
        )
    }

    /// Starts a select mode for `purpose`, nothing ticked.
    private func startSelection(_ purpose: SelectionPurpose) {
        selectingFor = purpose
        selectedIndices = []
    }

    /// The select mode's confirming button: Delete asks first; Export and Share write the ticked measurements, in the
    /// library's order, as one file.
    private func confirmSelection(_ purpose: SelectionPurpose) {
        switch purpose {
        case .delete:
            showingDeleteSelectedConfirmation = true
        case .export, .share:
            let chosen = selectedIndices.sorted().map { analyzer.savedMeasurements[$0] }
            let delivery: FileDelivery = purpose == .share ? .share : .export
            // One measurement is named as its own Export or Share names it; several, neutrally.
            if chosen.count == 1, let only = chosen.first {
                deliverMeasurement(only, as: delivery)
            } else {
                let stamp = Int(Date().timeIntervalSince1970)
                deliverMeasurements(chosen, filename: "guitartap-measurements-\(stamp)", as: delivery)
            }
            exitSelection()
        }
    }

    private func toggleSelection(at index: Int) {
        if selectedIndices.contains(index) {
            selectedIndices.remove(index)
        } else {
            selectedIndices.insert(index)
        }
    }

    private func exitSelection() {
        selectingFor = nil
        selectedIndices = []
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
                Button(role: entry.action == .delete ? .destructive : nil) {
                    perform(entry.action, index: index, measurement: measurement)
                } label: {
                    Label(entry.title, systemImage: entry.symbol ?? "")
                }
            }
        }
        .menuIcons()
    }

    /// What a saved measurement's menu item does.
    private func perform(_ action: SavedMeasurementAction, index: Int, measurement: TapToneMeasurement) {
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
        case .shareMeasurement:
            deliverMeasurement(measurement, as: .share)
        case .exportMeasurement:
            deliverMeasurement(measurement, as: .export)
        case .shareSpectrum:
            exportSpectrumMeasurement(measurement, as: .share)
        case .exportSpectrum:
            exportSpectrumMeasurement(measurement, as: .export)
        case .sharePDF:
            exportPDFReport(for: measurement, as: .share)
        case .exportPDF:
            exportPDFReport(for: measurement, as: .export)
        case .delete:
            measurementPendingDelete = (index: index, measurement: measurement)
        }
    }

    @ViewBuilder
    private func compareRowContent(at index: Int, for measurement: TapToneMeasurement) -> some View {
        let isHovered = hoveredMeasurementIndex == index
        if isComparing || isSelecting {
            // Any measurement can be deleted; only one with a spectrum can be compared.
            let comparable = isSelecting || isComparable(measurement)
            let selected = isSelecting ? selectedIndices.contains(index) : selectedCompareIndices.contains(index)
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

    /// Imports the files chosen in the file picker — one or several — and shows the one message for them.
    private func importFiles(_ urls: [URL]) {
        // Update the shared last-used directory so subsequent save panels open here.
        #if os(macOS)
        if let first = urls.first {
            MeasurementFileExporter.lastUsedDirectory = first.deletingLastPathComponent()
        }
        #endif
        let files = urls.map { url in
            // A sandboxed app reads a chosen file inside a security-scoped access pair.
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return TapToneAnalyzer.ImportFile(name: url.lastPathComponent,
                                              contents: Result { try Data(contentsOf: url) })
        }
        let report = analyzer.importFiles(files)
        if report.imported {
            importSuccess = report.message
        } else {
            importError = report.message
        }
    }
}

// MARK: - Document Picker View Wrapper

#if os(iOS)
/// A simple wrapper view for DocumentPicker that can be presented as a sheet
private struct DocumentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: ([URL]) -> Void
    
    var body: some View {
        DocumentPickerRepresentable(onPick: { urls in
            onPick(urls)
            dismiss()
        })
        .ignoresSafeArea()
    }
}

/// UIViewControllerRepresentable that directly presents the picker
private struct DocumentPickerRepresentable: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.guitarTapMeasurement, .json])
        picker.allowsMultipleSelection = true
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
        let onPick: ([URL]) -> Void
        
        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if !urls.isEmpty {
                onPick(urls)
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
    let panel: (ExportMenus.PanelAction) -> Void
    let delete: SavedMeasurementsDeleteActions

    var body: some View {
        Menu {
            Button(action: importMeasurement) {
                Label("Import Measurement", systemImage: "square.and.arrow.down")
            }

            Menu {
                ExportMenuItems(groups: ExportMenus.panel.entries(for: .current), perform: panel)
            } label: {
                Label(ExportMenus.panel.button(for: .current), systemImage: ExportMenus.panel.symbol)
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

// MARK: - Export and Share

/// What a select mode in Saved Measurements ticks rows for.
enum SelectionPurpose {
    case delete, export, share

    /// The confirming button's word, before the count: Delete (3).
    var verb: String {
        switch self {
        case .delete: "Delete"
        case .export: "Export"
        case .share: "Share"
        }
    }

    /// The confirming button's icon on the Mac.
    var symbol: String {
        switch self {
        case .delete: "trash"
        case .export: "doc.badge.arrow.up"
        case .share: "square.and.arrow.up"
        }
    }

    /// A row's help while selecting.
    var rowHelp: String {
        switch self {
        case .delete: "Toggle selection for deletion"
        case .export: "Toggle selection for export"
        case .share: "Toggle selection for sharing"
        }
    }
}

/// A menu's items from its groups, a separator between groups — the library menu's and Analysis Results'.
struct ExportMenuItems<Action: Hashable>: View {
    let groups: [[MenuEntry<Action>]]
    let perform: (Action) -> Void

    var body: some View {
        ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
            if groupIndex > 0 { Divider() }
            ForEach(group, id: \.action) { entry in
                Button { perform(entry.action) } label: {
                    if let symbol = entry.symbol {
                        Label(entry.title, systemImage: symbol)
                    } else {
                        Text(entry.title)
                    }
                }
            }
        }
        .menuIcons()
    }
}

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
