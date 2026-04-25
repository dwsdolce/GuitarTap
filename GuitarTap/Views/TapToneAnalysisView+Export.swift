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
    /// When `tap.displayMode == .comparison`, routes to `exportComparisonPDFReport()` instead.
    @MainActor
    func exportPDFReport() {
        if tap.displayMode == .comparison {
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
            tapLocation: tapLocation.isEmpty ? nil : tapLocation,
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
            let modeFreqs = TapToneAnalyzer.resolvedModePeaks(peaks: entry.peaks, guitarType: entry.guitarType)
            return (
                label: entry.label,
                color: entry.color,
                air:  modeFreqs[.air],
                top:  modeFreqs[.top],
                back: modeFreqs[.back]
            )
        }

        let reportData = ComparisonPDFReportData(
            timestamp: Date(),
            comparisonLabel: tap.loadedMeasurementName ?? (tapLocation.isEmpty ? nil : tapLocation),
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

        let label = tap.loadedMeasurementName ?? tapLocation
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

    func createExportableSpectrumView() -> some View {
        let isComparing = tap.displayMode == .comparison
        let subtitle = tapLocation.isEmpty ? (tap.loadedMeasurementName ?? "New") : tapLocation
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
            dateLabel: Date().formatted(),
            chartTitle: chartTitle
        )
    }
}
