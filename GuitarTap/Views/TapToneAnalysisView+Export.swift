/// # TapToneAnalysisView+Export
///
/// PDF report and spectrum PNG export flows for `TapToneAnalysisView`.
///
/// ## Export flows
///
/// ### Spectrum PNG export (`exportSpectrumImage()`)
/// 1. Calls `createExportableSpectrumView()` to build an off-screen
///    `ExportableSpectrumChart` with current peaks, overlays, and axis range.
/// 2. Renders it to PNG data using `ImageRenderer` at the device's display scale.
/// 3. Delegates to `MeasurementFileExporter.exportSpectrumImage(...)` to present
///    the platform share sheet / save panel.
///
/// ### PDF report export (`exportPDFReport()`)
/// 1. Renders the spectrum to PNG (same `ImageRenderer` path as above).
/// 2. Re-derives `PlateProperties` / `BraceProperties` from the current
///    analyzer state (peak IDs + `TapDisplaySettings` dimensions).
/// 3. Builds a `PDFReportData` value and calls `PDFReportGenerator.generate(data:)`.
/// 4. Delegates to `MeasurementFileExporter.exportPDF(...)` to present the
///    platform share sheet / save panel.
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

#if os(macOS)
import AppKit
#endif

extension TapToneAnalysisView {

    // MARK: - PDF Report Export

    /// Renders the current spectrum as PNG, builds report data, generates a PDF, and exports it.
    ///
    /// - Multi-tap guitar measurements always produce a two-page PDF (averaged + per-tap comparison),
    ///   regardless of which view is currently displayed.
    /// - Saved-measurement comparisons (`displayMode == .comparison`) produce a single comparison page.
    /// - All other cases produce a single averaged-result page.
    @MainActor
    func exportPDFReport() {
        if !tap.tapEntries.isEmpty {
            exportMultiTapPDFReport()
            return
        }
        if tap.isSavedMeasurementComparison {
            exportComparisonPDFReport()
            return
        }

        isGeneratingReport = true

        // Render current spectrum to PNG data (same technique as save/exportSpectrum)
        let spectrumView = createExportableSpectrumView()
        let imageRenderer = ImageRenderer(content: spectrumView)
        imageRenderer.scale = displayScale

        var spectrumImageData: Data?
        #if os(iOS)
        if let uiImage = imageRenderer.uiImage {
            spectrumImageData = uiImage.pngData()
        }
        #elseif os(macOS)
        if let nsImage = imageRenderer.nsImage,
           let tiffData = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData) {
            spectrumImageData = bitmap.representation(using: .png, properties: [:])
        }
        #endif

        // Compute material properties if applicable
        let measurementType = TapDisplaySettings.measurementType
        var plateProps: PlateProperties? = nil
        var braceProps: BraceProperties? = nil
        if measurementType == .plate {
            let effLong = tap.effectiveLongitudinalPeakID
            let effCross = tap.effectiveCrossPeakID
            let effFlc = tap.effectiveFlcPeakID
            let allPlatePeaks = tap.longitudinalPeaks + tap.crossPeaks + tap.flcPeaks + tap.currentPeaks
            if let longPeak = allPlatePeaks.first(where: { $0.id == effLong }),
               let crossPeak = allPlatePeaks.first(where: { $0.id == effCross }) {
                let flcFreq: Float? = allPlatePeaks.first(where: { $0.id == effFlc })?.frequency
                let dims = MaterialDimensions(
                    lengthMM: TapDisplaySettings.plateLength,
                    widthMM: TapDisplaySettings.plateWidth,
                    thicknessMM: TapDisplaySettings.plateThickness,
                    massGrams: TapDisplaySettings.plateMass
                )
                if dims.length > 0 && dims.mass > 0 {
                    plateProps = PlateProperties(
                        dimensions: dims,
                        fundamentalFrequencyLong: longPeak.frequency,
                        fundamentalFrequencyCross: crossPeak.frequency,
                        fundamentalFrequencyFlc: flcFreq
                    )
                }
            }
        } else if measurementType == .brace {
            let effLong = tap.effectiveLongitudinalPeakID
            let allBracePeaks = tap.longitudinalPeaks + tap.currentPeaks
            if let longPeak = allBracePeaks.first(where: { $0.id == effLong }) {
                let dims = MaterialDimensions(
                    lengthMM: TapDisplaySettings.braceLength,
                    widthMM: TapDisplaySettings.braceWidth,
                    thicknessMM: TapDisplaySettings.braceThickness,
                    massGrams: TapDisplaySettings.braceMass
                )
                if dims.length > 0 && dims.mass > 0 {
                    braceProps = BraceProperties(
                        dimensions: dims,
                        fundamentalFrequencyLong: longPeak.frequency
                    )
                }
            }
        }

        // Only include peaks within the currently displayed frequency range
        let rangeFilteredPeaks = tap.currentPeaks.filter {
            $0.frequency >= minFreq && $0.frequency <= maxFreq
        }

        let reportData = PDFReportData(
            timestamp: tap.sourceMeasurementTimestamp ?? Date(),
            measurementName: measurementName.isEmpty ? tap.loadedMeasurementName : measurementName,
            notes: notes.isEmpty ? nil : notes,
            measurementType: measurementType,
            guitarType: TapDisplaySettings.guitarType,
            peaks: rangeFilteredPeaks,
            selectedPeakIDs: tap.selectedPeakIDs,
            decayTime: tap.currentDecayTime,
            tapToneRatio: tap.calculateTapToneRatio(),
            spectrumImageData: spectrumImageData,
            minFreq: minFreq,
            maxFreq: maxFreq,
            plateProperties: plateProps,
            braceProperties: braceProps,
            selectedLongitudinalPeakID: tap.effectiveLongitudinalPeakID,
            selectedCrossPeakID: tap.effectiveCrossPeakID,
            selectedFlcPeakID: tap.effectiveFlcPeakID,
            peakModeOverrides: tap.peakModeOverrides,
            peakModes: Dictionary(uniqueKeysWithValues: tap.identifiedModes.map { ($0.peak.id, $0.mode) }),
            microphoneName: fft.selectedInputDevice?.name,
            calibrationName: fft.activeCalibration?.name,
            guitarBodyLength: TapDisplaySettings.guitarBodyLength,
            guitarBodyWidth: TapDisplaySettings.guitarBodyWidth,
            plateStiffness: TapDisplaySettings.plateStiffness,
            plateStiffnessPreset: TapDisplaySettings.plateStiffnessPreset
        )

        guard let pdfData = PDFReportGenerator.generate(data: reportData) else {
            gtLog("❌ Failed to generate PDF report")
            isGeneratingReport = false
            return
        }

        MeasurementFileExporter.exportPDF(data: pdfData, basename: reportData.baseFilename) {
            self.isGeneratingReport = false
        }
    }

    /// Renders the comparison overlay chart as PNG, builds comparison report data, generates a PDF, and exports it.
    @MainActor
    func exportComparisonPDFReport() {
        isGeneratingReport = true

        // Render the comparison overlay chart to PNG
        let spectrumView = createExportableSpectrumView()
        let imageRenderer = ImageRenderer(content: spectrumView)
        imageRenderer.scale = displayScale

        var spectrumImageData: Data?
        #if os(iOS)
        if let uiImage = imageRenderer.uiImage {
            spectrumImageData = uiImage.pngData()
        }
        #elseif os(macOS)
        if let nsImage = imageRenderer.nsImage,
           let tiffData = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData) {
            spectrumImageData = bitmap.representation(using: .png, properties: [:])
        }
        #endif

        // Build per-entry mode frequency rows
        let modeFrequencies = tap.comparisonSpectra.map { entry in
            let modePeaks = TapToneAnalyzer.resolvedModePeaks(peaks: entry.peaks, guitarType: entry.guitarType)
            return (
                label: entry.label,
                color: entry.color,
                air:  modePeaks[.air]?.frequency,
                top:  modePeaks[.top]?.frequency,
                back: modePeaks[.back]?.frequency
            )
        }

        let reportData = ComparisonPDFReportData(
            timestamp: Date(),
            comparisonLabel: tap.loadedMeasurementName ?? (measurementName.isEmpty ? nil : measurementName),
            notes: notes.isEmpty ? nil : notes,
            spectrumImageData: spectrumImageData,
            entries: tap.comparisonSnapshots.enumerated().map { index, snap in
                // Reconstruct a minimal ComparisonEntry just for the metadata section
                let entry = tap.comparisonSpectra[index]
                let cgColor: CGColor = entry.color.cgColor ?? entry.color.resolve(in: .init()).cgColor
                let comps: [Double]
                if let c = cgColor.components, c.count >= 3 {
                    comps = [Double(c[0]), Double(c[1]), Double(c[2]), c.count >= 4 ? Double(c[3]) : 1.0]
                } else {
                    comps = [0.0, 0.0, 1.0, 1.0]
                }
                return ComparisonEntry(
                    id: UUID(),
                    label: entry.label,
                    colorComponents: comps,
                    snapshot: snap,
                    peaks: entry.peaks,
                    guitarType: entry.guitarType,
                    sourceMeasurementID: nil
                )
            },
            modeFrequencies: modeFrequencies
        )

        let label = tap.loadedMeasurementName ?? measurementName
        let basename = label.isEmpty
            ? "report-\(Int(Date().timeIntervalSince1970))"
            : label.replacingOccurrences(of: " ", with: "-").lowercased()
                + "-\(Int(Date().timeIntervalSince1970))"

        guard let pdfData = PDFReportGenerator.generateComparison(data: reportData) else {
            gtLog("❌ Failed to generate comparison PDF report")
            isGeneratingReport = false
            return
        }

        MeasurementFileExporter.exportPDF(data: pdfData, basename: basename) {
            self.isGeneratingReport = false
        }
    }

    /// Renders both the averaged spectrum and the per-tap comparison overlay as PNG,
    /// then generates a two-page PDF (averaged report + comparison report) and exports it.
    ///
    /// Called when `tap.tapEntries` is non-empty, regardless of which view is currently shown.
    @MainActor
    func exportMultiTapPDFReport() {
        isGeneratingReport = true

        // ── Page 1: averaged spectrum image ──────────────────────────────────
        // Always rendered from the frozen averaged spectrum, independent of displayMode.
        let avgSpectrumView = createAveragedSpectrumView()
        let avgRenderer = ImageRenderer(content: avgSpectrumView)
        avgRenderer.scale = displayScale

        var avgImageData: Data?
        #if os(iOS)
        if let uiImage = avgRenderer.uiImage { avgImageData = uiImage.pngData() }
        #elseif os(macOS)
        if let nsImage = avgRenderer.nsImage,
           let tiff = nsImage.tiffRepresentation,
           let bmp = NSBitmapImageRep(data: tiff) {
            avgImageData = bmp.representation(using: .png, properties: [:])
        }
        #endif

        // ── Page 1: build PDFReportData (averaged) ────────────────────────────
        let measurementType = TapDisplaySettings.measurementType
        var plateProps: PlateProperties? = nil
        var braceProps: BraceProperties? = nil
        if measurementType == .plate {
            let effLong = tap.effectiveLongitudinalPeakID
            let effCross = tap.effectiveCrossPeakID
            let effFlc = tap.effectiveFlcPeakID
            let allPlatePeaks = tap.longitudinalPeaks + tap.crossPeaks + tap.flcPeaks + tap.currentPeaks
            if let longPeak = allPlatePeaks.first(where: { $0.id == effLong }),
               let crossPeak = allPlatePeaks.first(where: { $0.id == effCross }) {
                let flcFreq: Float? = allPlatePeaks.first(where: { $0.id == effFlc })?.frequency
                let dims = MaterialDimensions(
                    lengthMM: TapDisplaySettings.plateLength, widthMM: TapDisplaySettings.plateWidth,
                    thicknessMM: TapDisplaySettings.plateThickness, massGrams: TapDisplaySettings.plateMass)
                if dims.length > 0 && dims.mass > 0 {
                    plateProps = PlateProperties(dimensions: dims,
                        fundamentalFrequencyLong: longPeak.frequency,
                        fundamentalFrequencyCross: crossPeak.frequency,
                        fundamentalFrequencyFlc: flcFreq)
                }
            }
        } else if measurementType == .brace {
            let effLong = tap.effectiveLongitudinalPeakID
            let allBracePeaks = tap.longitudinalPeaks + tap.currentPeaks
            if let longPeak = allBracePeaks.first(where: { $0.id == effLong }) {
                let dims = MaterialDimensions(
                    lengthMM: TapDisplaySettings.braceLength, widthMM: TapDisplaySettings.braceWidth,
                    thicknessMM: TapDisplaySettings.braceThickness, massGrams: TapDisplaySettings.braceMass)
                if dims.length > 0 && dims.mass > 0 {
                    braceProps = BraceProperties(dimensions: dims, fundamentalFrequencyLong: longPeak.frequency)
                }
            }
        }
        let rangeFilteredPeaks = tap.currentPeaks.filter { $0.frequency >= minFreq && $0.frequency <= maxFreq }
        let avgReportData = PDFReportData(
            timestamp: tap.sourceMeasurementTimestamp ?? Date(),
            measurementName: measurementName.isEmpty ? tap.loadedMeasurementName : measurementName,
            notes: notes.isEmpty ? nil : notes,
            measurementType: measurementType,
            guitarType: TapDisplaySettings.guitarType,
            peaks: rangeFilteredPeaks,
            selectedPeakIDs: tap.selectedPeakIDs,
            decayTime: tap.currentDecayTime,
            tapToneRatio: tap.calculateTapToneRatio(),
            spectrumImageData: avgImageData,
            minFreq: minFreq, maxFreq: maxFreq,
            plateProperties: plateProps, braceProperties: braceProps,
            selectedLongitudinalPeakID: tap.effectiveLongitudinalPeakID,
            selectedCrossPeakID: tap.effectiveCrossPeakID,
            selectedFlcPeakID: tap.effectiveFlcPeakID,
            peakModeOverrides: tap.peakModeOverrides,
            peakModes: Dictionary(uniqueKeysWithValues: tap.identifiedModes.map { ($0.peak.id, $0.mode) }),
            microphoneName: fft.selectedInputDevice?.name,
            calibrationName: fft.activeCalibration?.name,
            guitarBodyLength: TapDisplaySettings.guitarBodyLength,
            guitarBodyWidth: TapDisplaySettings.guitarBodyWidth,
            plateStiffness: TapDisplaySettings.plateStiffness,
            plateStiffnessPreset: TapDisplaySettings.plateStiffnessPreset
        )

        // ── Page 2: comparison overlay spectrum image ─────────────────────────
        let cmpSpectrumView = createMultiTapComparisonSpectrumView()
        let cmpRenderer = ImageRenderer(content: cmpSpectrumView)
        cmpRenderer.scale = displayScale

        var cmpImageData: Data?
        #if os(iOS)
        if let uiImage = cmpRenderer.uiImage { cmpImageData = uiImage.pngData() }
        #elseif os(macOS)
        if let nsImage = cmpRenderer.nsImage,
           let tiff = nsImage.tiffRepresentation,
           let bmp = NSBitmapImageRep(data: tiff) {
            cmpImageData = bmp.representation(using: .png, properties: [:])
        }
        #endif

        // ── Page 2: build ComparisonPDFReportData ─────────────────────────────
        let palette: [Color] = [.blue, .orange, .green, .purple, .teal]
        let avgColor = TapToneAnalyzer.multiTapAvgColor

        var cmpEntries: [ComparisonEntry] = tap.tapEntries.enumerated().map { index, entry in
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
        // Averaged entry
        let avgCGColor = avgColor.cgColor ?? avgColor.resolve(in: .init()).cgColor
        let avgComps: [Double]
        if let c = avgCGColor.components, c.count >= 3 {
            avgComps = [Double(c[0]), Double(c[1]), Double(c[2]), c.count >= 4 ? Double(c[3]) : 1.0]
        } else { avgComps = [1.0, 0.85, 0.0, 1.0] }
        let avgSnap = SpectrumSnapshot(
            frequencies: tap.frozenFrequencies, magnitudes: tap.frozenMagnitudes,
            minFreq: TapDisplaySettings.minFrequency, maxFreq: TapDisplaySettings.maxFrequency,
            minDB: TapDisplaySettings.minMagnitude, maxDB: 0, isLogarithmic: false,
            showUnknownModes: TapDisplaySettings.showUnknownModes,
            guitarType: TapDisplaySettings.guitarType,
            measurementType: TapDisplaySettings.measurementType)
        let avgSelectedPeaks = tap.currentPeaks.filter { tap.selectedPeakIDs.contains($0.id) }
        cmpEntries.append(ComparisonEntry(id: UUID(), label: "Averaged",
            colorComponents: avgComps, snapshot: avgSnap,
            peaks: avgSelectedPeaks,
            guitarType: TapDisplaySettings.guitarType, sourceMeasurementID: nil))

        let modeFrequencies = cmpEntries.map { entry in
            let c = entry.colorComponents
            let color = Color(red: c[0], green: c[1], blue: c[2], opacity: c.count >= 4 ? c[3] : 1.0)
            let modePeaks = TapToneAnalyzer.resolvedModePeaks(peaks: entry.peaks, guitarType: entry.guitarType)
            return (label: entry.label, color: color,
                    air: modePeaks[.air]?.frequency, top: modePeaks[.top]?.frequency, back: modePeaks[.back]?.frequency)
        }

        let cmpReportData = ComparisonPDFReportData(
            timestamp: tap.sourceMeasurementTimestamp ?? Date(),
            comparisonLabel: measurementName.isEmpty ? nil : measurementName,
            notes: notes.isEmpty ? nil : notes,
            spectrumImageData: cmpImageData,
            entries: cmpEntries,
            modeFrequencies: modeFrequencies
        )

        // ── Generate and export ───────────────────────────────────────────────
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

    /// Builds an off-screen spectrum view showing all per-tap overlays plus the averaged spectrum,
    /// mirroring the live multi-tap comparison chart.
    func createMultiTapComparisonSpectrumView() -> some View {
        let palette: [Color] = [.blue, .orange, .green, .purple, .teal]
        let avgColor = TapToneAnalyzer.multiTapAvgColor

        var spectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)] =
            tap.tapEntries.enumerated().map { index, entry in
                (magnitudes: entry.snapshot.magnitudes, frequencies: entry.snapshot.frequencies,
                 color: palette[index % palette.count], label: "Tap \(entry.tapIndex)")
            }
        spectra.append((magnitudes: tap.frozenMagnitudes, frequencies: tap.frozenFrequencies,
                        color: avgColor, label: "Averaged"))

        let snaps = tap.tapEntries.map(\.snapshot)
        let subtitle = measurementName.isEmpty ? (tap.loadedMeasurementName ?? "Multi-Tap") : measurementName
        return makeExportableSpectrumView(
            frequencies: [], magnitudes: [],
            minFreq: snaps.map(\.minFreq).min() ?? minFreq,
            maxFreq: snaps.map(\.maxFreq).max() ?? maxFreq,
            minDB:   snaps.map(\.minDB).min()   ?? minDB,
            maxDB:   snaps.map(\.maxDB).max()   ?? maxDB,
            peaks: [], measurementType: TapDisplaySettings.measurementType,
            materialSpectra: spectra,
            dateLabel: DateDisplay.string(Date()),
            chartTitle: "Tap Comparison — \(subtitle)"
        )
    }

    /// Builds an off-screen spectrum view always showing the frozen averaged spectrum and its
    /// annotations, independent of the current `displayMode`.
    ///
    /// Used by `exportMultiTapPDFReport()` so page 1 always contains the averaged result even
    /// when the multi-tap comparison chart is currently displayed.
    func createAveragedSpectrumView() -> some View {
        let subtitle = measurementName.isEmpty ? (tap.loadedMeasurementName ?? "New") : measurementName
        return makeExportableSpectrumView(
            frequencies: tap.frozenFrequencies,
            magnitudes: tap.frozenMagnitudes,
            minFreq: minFreq, maxFreq: maxFreq, minDB: minDB, maxDB: maxDB,
            peaks: tap.visiblePeaks,
            annotationOffsets: tap.peakAnnotationOffsets,
            showUnknownModes: TapDisplaySettings.showUnknownModes,
            measurementType: TapDisplaySettings.measurementType,
            selectedLongitudinalPeakID: tap.effectiveLongitudinalPeakID,
            selectedCrossPeakID: tap.effectiveCrossPeakID,
            selectedFlcPeakID: tap.effectiveFlcPeakID,
            modeOverrides: tap.peakModeOverrides,
            peakModes: Dictionary(uniqueKeysWithValues: tap.identifiedModes.map { ($0.peak.id, $0.mode) }),
            materialSpectra: materialSpectra,
            dateLabel: DateDisplay.string(Date()),
            chartTitle: "FFT Peaks — \(subtitle)"
        )
    }

    func createExportableSpectrumView() -> some View {
        let isComparing = tap.isSavedMeasurementComparison
        let subtitle = measurementName.isEmpty ? (tap.loadedMeasurementName ?? "New") : measurementName
        let chartTitle = "FFT Peaks — \(subtitle)"
        return makeExportableSpectrumView(
            frequencies: tap.isMeasurementComplete ? tap.frozenFrequencies : fft.frequencies,
            magnitudes: tap.isMeasurementComplete ? tap.frozenMagnitudes : fft.magnitudes,
            minFreq: minFreq,
            maxFreq: maxFreq,
            minDB: minDB,
            maxDB: maxDB,
            peaks: isComparing ? [] : tap.visiblePeaks,
            annotationOffsets: isComparing ? [:] : tap.peakAnnotationOffsets,
            showUnknownModes: TapDisplaySettings.showUnknownModes,
            measurementType: TapDisplaySettings.measurementType,
            selectedLongitudinalPeakID: tap.effectiveLongitudinalPeakID,
            selectedCrossPeakID: tap.effectiveCrossPeakID,
            selectedFlcPeakID: tap.effectiveFlcPeakID,
            modeOverrides: tap.peakModeOverrides,
            peakModes: Dictionary(uniqueKeysWithValues: tap.identifiedModes.map { ($0.peak.id, $0.mode) }),
            materialSpectra: materialSpectra,
            dateLabel: DateDisplay.string(Date()),
            chartTitle: chartTitle
        )
    }
}
