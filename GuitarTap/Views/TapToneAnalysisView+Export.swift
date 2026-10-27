// @parity view/main
/// # TapToneAnalysisView+Export
///
/// PDF report and spectrum PNG export flows for `TapToneAnalysisView`.
///
/// Every export from the main view is of the result on screen as the measurement it would be saved as
/// (``currentMeasurement()``: its name, notes, the chart's range and its time), drawn by the same code as
/// Saved Measurements draws a saved one — so an export cannot depend on what else the screen shows (a
/// multi-tap measurement's Taps view), and exporting before or after saving gives the same file.
///
/// ## Export flows
///
/// ### Spectrum PNG export (`exportCurrentSpectrum()`, in `+Actions`)
/// 1. Draws ``currentMeasurement()``'s image with `renderSpectrumImageForMeasurement` (or
///    `renderSpectrumImageForComparison`) — light scheme, fixed 2× scale; if it fails the export stops
///    and "Export Failed" is shown.
/// 2. Hands the PNG to `MeasurementFileExporter.deliver(...)` — the save dialog, or the share sheet.
///
/// ### PDF report export (`exportPDFReport()`)
/// 1. Builds the report of ``currentMeasurement()`` with `PDFReportGenerator.report(for:)`: a
///    multi-tap measurement's two pages, a comparison's report, or the single report.
/// 2. Hands it to `MeasurementFileExporter.deliver(...)` — the save dialog, or the share sheet.
///
/// All export methods are `@MainActor` because `ImageRenderer` requires
/// main-actor execution.
///
/// - SeeAlso: `PDFReportGenerator`, `MeasurementFileExporter`, `ExportableSpectrumChart`
//
//  TapToneAnalysisView+Export.swift
//  GuitarTap
//

import SwiftUI
internal import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

extension TapToneAnalysisView {

    // MARK: - The Measurement Exported

    /// The result on screen as the measurement it would be saved as: its name (the live name, else the
    /// loaded one), notes, the chart's range and its time (a loaded measurement's own, else now). A
    /// comparison of saved measurements is a comparison measurement; anything else — a multi-tap
    /// measurement whichever view of it is shown — the measurement.
    @MainActor
    func currentMeasurement() -> TapToneMeasurement? {
        let name = TapToneMeasurement.normalizedName(measurementName.isEmpty ? (tap.loadedMeasurementName ?? "") : measurementName)
        let noteText = TapToneMeasurement.normalizedNotes(notes.isEmpty ? (tap.loadedNotes ?? "") : notes)
        let timestamp = tap.sourceMeasurementTimestamp ?? Date()
        if tap.isSavedMeasurementComparison {
            return tap.makeComparisonMeasurement(measurementName: name, notes: noteText,
                                                 minFreq: minFreq, maxFreq: maxFreq, minDB: minDB, maxDB: maxDB,
                                                 timestamp: timestamp)
        }
        return tap.makeMeasurement(measurementName: name, notes: noteText,
                                   minFreq: minFreq, maxFreq: maxFreq, minDB: minDB, maxDB: maxDB,
                                   timestamp: timestamp)
    }

    // MARK: - Analysis Results' Menu

    /// What an item of Analysis Results' Export (or Share) menu does.
    @MainActor
    func performResultsExport(_ action: ExportMenus.ResultsAction) {
        switch action {
        case .shareSpectrum: exportCurrentSpectrum(as: .share)
        case .exportSpectrum: exportCurrentSpectrum(as: .export)
        case .sharePDF: exportPDFReport(as: .share)
        case .exportPDF: exportPDFReport(as: .export)
        }
    }

    // MARK: - PDF Report Export

    /// Builds the PDF report of ``currentMeasurement()`` — the same report Saved Measurements exports
    /// for it — and exports or shares it.
    @MainActor
    func exportPDFReport(as delivery: FileDelivery = .export) {
        // Re-entrancy guard: the PDF path presents an async, non-modal NSSavePanel, so a
        // repeated (or cross-type) click would stack panels (see isExportPanelInFlight, cleared on
        // every export completion path).
        guard !isExportPanelInFlight else { return }
        guard let measurement = currentMeasurement() else { return }
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
        MeasurementFileExporter.deliver(report.data, filename: "\(report.basename).pdf", contentType: .pdf, as: delivery) {
            self.isGeneratingReport = false
        }
    }
}
