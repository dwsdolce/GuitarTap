//
//  MeasurementDetailView.swift
//  GuitarTap
//
// @parity view/measurement-detail

/// # MeasurementDetailView
///
/// Detail panel for a single saved `TapToneMeasurement`.
///
/// ## Platform Differences
///
/// - **macOS**: Rendered bare (`contentView` without a `NavigationView`),
///   presented in a dedicated `NSWindowController` opened from
///   `MeasurementsListView`. Toolbar items provide Load, Export, and PDF
///   Report actions. Loading closes the detail window by calling
///   `NSApplication.shared.keyWindow?.close()`.
/// - **iOS**: Wrapped in a `NavigationView` with nav-bar toolbar items.
///
/// ## Load Flow
///
/// Tapping Load shows a confirmation alert ("replace current analysis?") then
/// calls `analyzer.loadMeasurement(_:)`.
///
/// ## Export Flow
///
/// The PDF report flow uses `PDFReportGenerator` with an off-screen
/// `ExportableSpectrumChart` rendered by `ImageRenderer`.
///
/// - SeeAlso: `MeasurementsListView`, `PDFReportGenerator`

import SwiftUI

struct MeasurementDetailView: View {
    let index: Int
    @State var measurement: TapToneMeasurement
    @ObservedObject var analyzer: TapToneAnalyzer
    @Environment(\.dismiss) var dismiss
    @State private var isExporting = false
    @State private var isGeneratingReport = false
    @State private var chartImage: Image?
    @State private var showingLoadConfirmation = false
    @State private var showingEdit = false
    
    var body: some View {
        // The detail view is read-only.  Load / Edit / Export / PDF Report
        // are all reachable from the popup menu on the row in the
        // Measurements list (MeasurementsListView), so no duplicate
        // controls are presented here.
        #if os(macOS)
        // On macOS in a separate window — the window's own close button
        // dismisses the view; no in-view Close control is needed.
        contentView
            .frame(minWidth: 600, minHeight: 500)
        #else
        // On iOS, NavigationLink provides the navigation context.  Keep
        // only the Done button as the cancellation action.
        contentView
            .navigationTitle("Measurement Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        #endif
    }
    
    /// Single Settings-vocabulary type word for the Details pane:
    /// Acoustic / Classical / Flamenco / Generic / Plate / Brace / Comparison.
    @ViewBuilder
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Info
                GroupBox("Measurement Info") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let measurementName = measurement.measurementName {
                                HStack {
                                    Text("Measurement Name:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(measurementName)
                                        .font(.body)
                                        .fontWeight(.medium)
                                }
                            }
                            
                            HStack {
                                Text("Date:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(DateDisplay.string(measurement.timestamp))
                                    .font(.body)
                            }
                            
                            HStack {
                                Text("Measurement Type:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(measurement.measurementTypeShortName)
                                    .font(.body)
                            }

                            if let taps = measurement.numberOfTaps {
                                HStack {
                                    Text("Number of Taps:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(taps)")
                                        .font(.body)
                                }
                            }

                            if let mic = measurement.microphoneName {
                                HStack {
                                    Text("Microphone:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(mic)
                                        .font(.body)
                                }
                            }

                            if let cal = measurement.calibrationName {
                                HStack {
                                    Text("Calibration:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(cal)
                                        .font(.body)
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
                    
                    // Comparison records show the per-spectrum Air/Top/Back table; everything
                    // else shows the identified (selected) peaks only.
                    if let entries = measurement.comparisonEntries {
                        GroupBox("Compared Spectra (\(entries.count))") {
                            ComparisonResultsView(spectra: entries.map { entry in
                                let c = entry.colorComponents
                                let color = Color(
                                    red: c.indices.contains(0) ? c[0] : 0,
                                    green: c.indices.contains(1) ? c[1] : 0,
                                    blue: c.indices.contains(2) ? c[2] : 1,
                                    opacity: c.indices.contains(3) ? c[3] : 1
                                )
                                return (magnitudes: entry.snapshot.magnitudes,
                                        frequencies: entry.snapshot.frequencies,
                                        color: color,
                                        label: entry.label,
                                        peaks: entry.peaks,
                                        guitarType: entry.guitarType,
                                        modeIDs: entry.modePeakIDs ?? [:])
                            })
                            .padding(.vertical, 4)
                        }
                    } else {
                        // Identified Peaks = the selected peaks only, sorted by frequency.
                        // Plate/brace skip guitar-mode classification.
                        let isMaterialMeasurement = measurement.longitudinalSnapshot != nil || measurement.selectedLongitudinalPeakID != nil
                        let selectedIDs = measurement.effectiveSelectedPeakIDs
                        let shownPeaks = measurement.peaks
                            .filter { selectedIDs.contains($0.id) }
                            .sorted(by: { $0.frequency < $1.frequency })
                        // Context-aware mode map so overlapping ranges (e.g. classical Top/Back) show distinct labels.
                        let modeMap: [UUID: GuitarMode] = isMaterialMeasurement ? [:] : GuitarMode.classifyAll(shownPeaks)

                        GroupBox("Identified Peaks") {
                            if shownPeaks.isEmpty {
                                Text("No identified peaks")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(shownPeaks) { peak in
                                        let mode = modeMap[peak.id] ?? .unknown
                                        let effectiveLabel: String = {
                                            if isMaterialMeasurement {
                                                if peak.id == measurement.selectedLongitudinalPeakID { return "Longitudinal" }
                                                if peak.id == measurement.selectedCrossPeakID { return "Cross-grain" }
                                                if peak.id == measurement.selectedFlcPeakID { return "FLC" }
                                                return "Peak"
                                            }
                                            switch measurement.peakModeOverrides?[peak.id] ?? .auto {
                                            case .auto: return mode.displayName
                                            case .assigned(let label): return label
                                            }
                                        }()
                                        let isOverridden = !isMaterialMeasurement && measurement.peakModeOverrides?[peak.id].flatMap {
                                            if case .assigned = $0 { return $0 }
                                            return nil
                                        } != nil
                                        CombinedPeakModeRowView(
                                            peak: peak,
                                            mode: mode,
                                            effectiveModeLabel: effectiveLabel,
                                            isManualOverride: isOverridden,
                                            isSelected: true
                                        )
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
            MeasurementFileExporter.exportJSON(json: json, measurement: measurement) {
                self.isExporting = false
            }
        }
    }

    @MainActor
    private func generatePDFReport() {
        if measurement.tapEntries?.isEmpty == false {
            generateMultiTapPDFReport()
        } else {
            generateSinglePDFReport()
        }
    }

    @MainActor
    private func generateSinglePDFReport() {
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

    @MainActor
    private func generateMultiTapPDFReport() {
        guard let tapEntries = measurement.tapEntries, !tapEntries.isEmpty else { return }
        isGeneratingReport = true

        let avgImageData = renderSpectrumImageForMeasurement(measurement)
        let avgReportData = PDFReportData.from(measurement: measurement, spectrumImageData: avgImageData)
        let cmpImageData = renderSpectrumImageForMultiTap(measurement)

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
        if let avgSnap = measurement.spectrumSnapshot {
            let avgCGColor = avgColor.cgColor ?? avgColor.resolve(in: .init()).cgColor
            let avgComps: [Double]
            if let c = avgCGColor.components, c.count >= 3 {
                avgComps = [Double(c[0]), Double(c[1]), Double(c[2]), c.count >= 4 ? Double(c[3]) : 1.0]
            } else { avgComps = [1.0, 0.85, 0.0, 1.0] }
            let selectedIDs = measurement.effectiveSelectedPeakIDs
            cmpEntries.append(ComparisonEntry(id: UUID(), label: "Averaged",
                colorComponents: avgComps, snapshot: avgSnap,
                peaks: measurement.peaks.filter { selectedIDs.contains($0.id) },
                guitarType: measurement.spectrumSnapshot?.guitarType, sourceMeasurementID: nil))
        }

        // Per-tap rows = each tap's own auto; Averaged row = the definitive (override-aware) modes,
        // tagged where overridden.
        let avgInfo = measurement.definitiveModeInfo()
        let modeFrequencies = cmpEntries.map { entry -> (label: String, color: Color, air: Float?, top: Float?, back: Float?, overrideModes: Set<GuitarMode>) in
            let c = entry.colorComponents
            let color = Color(red: c[0], green: c[1], blue: c[2], opacity: c.count >= 4 ? c[3] : 1.0)
            if entry.label == "Averaged" {
                return (entry.label, color, avgInfo[.air]?.frequency, avgInfo[.top]?.frequency,
                        avgInfo[.back]?.frequency, Set(avgInfo.filter { $0.value.isOverride }.keys))
            }
            let modePeaks = TapToneAnalyzer.resolvedModePeaks(peaks: entry.peaks, guitarType: entry.guitarType)
            return (entry.label, color, modePeaks[.air]?.frequency, modePeaks[.top]?.frequency,
                    modePeaks[.back]?.frequency, [])
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
}
