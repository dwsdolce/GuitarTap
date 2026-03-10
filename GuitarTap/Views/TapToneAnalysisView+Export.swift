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
    @MainActor
    func exportPDFReport() {
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
            microphoneName: fft.selectedInputDevice?.name,
            calibrationName: fft.activeCalibration?.name,
            guitarBodyLength: TapDisplaySettings.guitarBodyLength,
            guitarBodyWidth: TapDisplaySettings.guitarBodyWidth,
            plateStiffness: TapDisplaySettings.plateStiffness,
            plateStiffnessPreset: TapDisplaySettings.plateStiffnessPreset
        )

        guard let pdfData = PDFReportGenerator.generate(data: reportData) else {
            print("❌ Failed to generate PDF report")
            isGeneratingReport = false
            return
        }

        MeasurementFileExporter.exportPDF(data: pdfData, basename: reportData.baseFilename) {
            self.isGeneratingReport = false
        }
    }

    @ViewBuilder
    func createExportableSpectrumView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Guitar Tap Tone Analysis - Frequency Response")
                    .font(.title)
                    .fontWeight(.bold)

                HStack {
                    Text("Date: \(Date().formatted())")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("Range: \(formatFrequency(minFreq)) - \(formatFrequency(maxFreq))")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text("\(Int(minDB)) to \(Int(maxDB)) dB")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                if !tap.currentPeaks.isEmpty {
                    Text("Detected Peaks: \(tap.currentPeaks.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            // Chart - use static export version to avoid ImageRenderer issues
            ExportableSpectrumChart(
                frequencies: tap.isSpectrumFrozen ?
                    tap.frozenFrequencies : fft.frequencies,
                magnitudes: tap.isSpectrumFrozen ?
                    tap.frozenMagnitudes : fft.magnitudes,
                minFreq: minFreq,
                maxFreq: maxFreq,
                minDB: minDB,
                maxDB: maxDB,
                isLogarithmic: false,
                peaks: tap.visiblePeaks,
                showModeBoundaries: true,
                annotationOffsets: tap.peakAnnotationOffsets,
                showUnknownModes: TapDisplaySettings.showUnknownModes,
                measurementType: TapDisplaySettings.measurementType,
                selectedLongitudinalPeakID: tap.effectiveLongitudinalPeakID,
                selectedCrossPeakID: tap.effectiveCrossPeakID,
                selectedFlcPeakID: tap.effectiveFlcPeakID,
                modeOverrides: tap.peakModeOverrides,
                materialSpectra: materialSpectra
            )
            .frame(width: 1400, height: 800)
            .padding()

            // Peak Summary
            if !tap.currentPeaks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Detected Peaks Summary")
                        .font(.headline)
                        .padding(.horizontal)

                    HStack(spacing: 20) {
                        ForEach(tap.currentPeaks.prefix(8).sorted(by: { $0.frequency < $1.frequency })) { peak in
                            let mode = GuitarMode.classify(frequency: peak.frequency)
                            VStack(spacing: 4) {
                                Text("\(peak.frequency, specifier: "%.1f") Hz")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                Text(mode.displayName)
                                    .font(.caption2)
                                    .foregroundColor(mode.color)
                                Text("\(peak.magnitude, specifier: "%.1f") dB")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(mode.color.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
            }

            // Legend
            HStack(spacing: 20) {
                Text("Guitar Modes:")
                    .font(.caption)
                    .fontWeight(.semibold)

                ForEach([GuitarMode.air, .top, .back, .dipole, .ringMode], id: \.self) { mode in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(mode.color)
                            .frame(width: 12, height: 12)
                        Text(mode.displayName)
                            .font(.caption)
                    }
                }
            }
            .padding()
        }
        .background(Color.white)
        .padding()
    }
}
