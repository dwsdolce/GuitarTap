//
//  PDFReportGenerator.swift
//  GuitarTap
//
//  Created by David Smith on 2/24/26.
//

import SwiftUI
import CoreGraphics

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Report Data

/// All data needed to generate a PDF tap tone analysis report
struct PDFReportData {
    let timestamp: Date
    let tapLocation: String?
    let notes: String?
    let measurementType: MeasurementType
    let guitarType: GuitarType
    let peaks: [ResonantPeak]
    let hiddenPeakIDs: Set<UUID>
    let decayTime: Float?
    let tapToneRatio: Float?
    let spectrumImageData: Data?
    let minFreq: Float
    let maxFreq: Float
    let materialProperties: MaterialProperties?
    let selectedLongitudinalPeakID: UUID?
    let selectedCrossPeakID: UUID?
    let selectedFlcPeakID: UUID?

    /// Build report data from a saved TapToneMeasurement
    static func from(measurement: TapToneMeasurement) -> PDFReportData {
        let snapshot = measurement.spectrumSnapshot
        let measurementType = snapshot?.measurementType ?? .classical
        let guitarType = snapshot?.guitarType ?? .classical

        // Compute material properties if applicable
        var materialProps: MaterialProperties? = nil
        if measurementType == .material || measurementType == .brace {
            let longID = measurement.selectedLongitudinalPeakID
            let crossID = measurement.selectedCrossPeakID
            let flcID = measurement.selectedFlcPeakID

            if let longPeak = measurement.peaks.first(where: { $0.id == longID }) {
                let crossPeak = measurement.peaks.first(where: { $0.id == crossID })
                let flcPeak = measurement.peaks.first(where: { $0.id == flcID })

                if measurementType == .brace {
                    let dims = MaterialDimensions(
                        lengthMM: snapshot?.materialLength ?? 0,
                        widthMM: snapshot?.materialWidth ?? 0,
                        thicknessMM: snapshot?.materialThickness ?? 0,
                        massGrams: snapshot?.materialMass ?? 0
                    )
                    if dims.length > 0 && dims.mass > 0 {
                        materialProps = MaterialProperties(
                            dimensions: dims,
                            fundamentalFrequencyLong: longPeak.frequency,
                            fundamentalFrequencyCross: crossPeak?.frequency ?? longPeak.frequency,
                            fundamentalFrequencyFlc: nil
                        )
                    }
                } else if let crossPeak = crossPeak {
                    let dims = MaterialDimensions(
                        lengthMM: snapshot?.materialLength ?? 0,
                        widthMM: snapshot?.materialWidth ?? 0,
                        thicknessMM: snapshot?.materialThickness ?? 0,
                        massGrams: snapshot?.materialMass ?? 0
                    )
                    if dims.length > 0 && dims.mass > 0 {
                        materialProps = MaterialProperties(
                            dimensions: dims,
                            fundamentalFrequencyLong: longPeak.frequency,
                            fundamentalFrequencyCross: crossPeak.frequency,
                            fundamentalFrequencyFlc: flcPeak?.frequency
                        )
                    }
                }
            }
        }

        // Filter peaks to those within the saved display frequency range
        let minFreq = snapshot?.minFreq ?? 0
        let maxFreq = snapshot?.maxFreq ?? Float.greatestFiniteMagnitude
        let rangeFilteredPeaks = measurement.peaks.filter {
            $0.frequency >= minFreq && $0.frequency <= maxFreq
        }

        return PDFReportData(
            timestamp: measurement.timestamp,
            tapLocation: measurement.tapLocation,
            notes: measurement.notes,
            measurementType: measurementType,
            guitarType: guitarType,
            peaks: rangeFilteredPeaks,
            hiddenPeakIDs: Set(measurement.hiddenPeakIDs ?? []),
            decayTime: measurement.decayTime,
            tapToneRatio: measurement.tapToneRatio,
            spectrumImageData: measurement.chartImageData,
            minFreq: snapshot?.minFreq ?? 50,
            maxFreq: snapshot?.maxFreq ?? 1000,
            materialProperties: materialProps,
            selectedLongitudinalPeakID: measurement.selectedLongitudinalPeakID,
            selectedCrossPeakID: measurement.selectedCrossPeakID,
            selectedFlcPeakID: measurement.selectedFlcPeakID
        )
    }

    /// Filename base (without extension) for this report
    var baseFilename: String {
        let locationPart = tapLocation?
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .lowercased() ?? "report"
        let timestampPart = Int(timestamp.timeIntervalSince1970)
        return "\(locationPart)-\(timestampPart)"
    }
}

// MARK: - PDF Generator

struct PDFReportGenerator {

    /// Generate PDF data for the given report data.
    /// Must be called on the main actor (ImageRenderer requirement).
    @MainActor
    static func generate(data: PDFReportData) -> Data? {
        let contentView = PDFReportContentView(data: data)
        let renderer = ImageRenderer(content: contentView)

        let mutableData = NSMutableData()

        renderer.render { size, draw in
            guard let consumer = CGDataConsumer(data: mutableData) else { return }
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }

        return mutableData.length > 0 ? mutableData as Data : nil
    }
}

// MARK: - PDF Report Content View

/// A SwiftUI view that renders the full tap tone analysis report.
/// Designed for off-screen rendering via ImageRenderer.
private struct PDFReportContentView: View {
    let data: PDFReportData

    private let pageWidth: CGFloat = 612
    private let margin: CGFloat = 36
    private var contentWidth: CGFloat { pageWidth - margin * 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            accentBar
            metadataSection
            Spacer().frame(height: 14)
            if let imageData = data.spectrumImageData {
                spectrumSection(imageData: imageData)
                Spacer().frame(height: 14)
            }
            sectionDivider
            Spacer().frame(height: 14)
            peaksSection
            Spacer().frame(height: 14)
            analysisSection
            footerSection
        }
        .padding(margin)
        .frame(width: pageWidth)
        .background(Color.white)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GuitarTap")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color(red: 0.15, green: 0.35, blue: 0.75))
                Text("Tap Tone Analysis Report")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(data.timestamp, style: .date)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(data.timestamp, style: .time)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.bottom, 8)
    }

    private var accentBar: some View {
        Rectangle()
            .fill(Color(red: 0.15, green: 0.35, blue: 0.75))
            .frame(height: 3)
            .padding(.bottom, 12)
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let location = data.tapLocation, !location.isEmpty {
                metaRow(label: "Location", value: location)
            }
            metaRow(label: "Type", value: data.measurementType.rawValue)
            if let notes = data.notes, !notes.isEmpty {
                metaRow(label: "Notes", value: notes)
            }
            metaRow(label: "Frequency Range",
                    value: "\(data.minFreq.formattedAsFrequency()) – \(data.maxFreq.formattedAsFrequency())")
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label + ":")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(.primary)
        }
    }

    // MARK: - Spectrum Image

    @ViewBuilder
    private func spectrumSection(imageData: Data) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Frequency Spectrum")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            reportImage(from: imageData)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: contentWidth)
                .frame(maxHeight: 220)
                .background(Color(white: 0.05))
                .cornerRadius(6)
        }
    }

    private func reportImage(from data: Data) -> Image {
        #if os(iOS)
        if let img = UIImage(data: data) { return Image(uiImage: img) }
        #elseif os(macOS)
        if let img = NSImage(data: data) { return Image(nsImage: img) }
        #endif
        return Image(systemName: "photo")
    }

    // MARK: - Divider

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 1)
    }

    // MARK: - Peaks

    private var visibleSortedPeaks: [ResonantPeak] {
        data.peaks
            .filter { !data.hiddenPeakIDs.contains($0.id) }
            .sorted { $0.frequency < $1.frequency }
    }

    private var peaksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Detected Peaks")
                .font(.system(size: 13, weight: .semibold))

            if visibleSortedPeaks.isEmpty {
                Text("No peaks detected in this measurement.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                // Table header
                peakTableHeader
                    .padding(.bottom, 2)

                // Rows
                ForEach(visibleSortedPeaks) { peak in
                    peakRow(for: peak)
                }
            }
        }
    }

    private var peakTableHeader: some View {
        HStack(spacing: 0) {
            Text("Frequency")
                .frame(width: 90, alignment: .leading)
            Text("Magnitude")
                .frame(width: 80, alignment: .leading)
            Text("Note")
                .frame(width: 80, alignment: .leading)
            if data.measurementType.isGuitar {
                Text("Mode")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Q Factor")
                    .frame(width: 70, alignment: .leading)
                peakRoleHeader
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(.secondary)
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(4)
    }

    @ViewBuilder
    private var peakRoleHeader: some View {
        if data.measurementType == .material {
            Text("Role")
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
        } else if data.measurementType == .brace {
            Text("Role")
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }

    private func peakRow(for peak: ResonantPeak) -> some View {
        HStack(spacing: 0) {
            Text(String(format: "%.1f Hz", peak.frequency))
                .frame(width: 90, alignment: .leading)
            Text(String(format: "%.1f dB", peak.magnitude))
                .frame(width: 80, alignment: .leading)
            Text(peak.pitchNote ?? "–")
                .frame(width: 80, alignment: .leading)
            if data.measurementType.isGuitar {
                let mode = GuitarMode.classify(frequency: peak.frequency, guitarType: data.guitarType)
                Text(mode.displayName)
                    .foregroundColor(modeColor(mode))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(String(format: "%.1f", peak.quality))
                    .frame(width: 70, alignment: .leading)
                peakRoleCell(for: peak)
            }
        }
        .font(.system(size: 10))
        .foregroundColor(.primary)
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func peakRoleCell(for peak: ResonantPeak) -> some View {
        if data.measurementType == .material {
            let isLong = peak.id == data.selectedLongitudinalPeakID
            let isCross = peak.id == data.selectedCrossPeakID
            let isFlc = peak.id == data.selectedFlcPeakID
            Group {
                if isLong {
                    Text("Longitudinal (L)")
                        .foregroundColor(.blue)
                } else if isCross {
                    Text("Cross-grain (C)")
                        .foregroundColor(.orange)
                } else if isFlc {
                    Text("FLC (Diagonal)")
                        .foregroundColor(.purple)
                } else {
                    Text("–")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if data.measurementType == .brace {
            let isLong = peak.id == data.selectedLongitudinalPeakID
            Group {
                if isLong {
                    Text("fL (Longitudinal)")
                        .foregroundColor(.blue)
                } else {
                    Text("–")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func modeColor(_ mode: GuitarMode) -> Color {
        switch mode.normalized {
        case .air: return Color(red: 0.0, green: 0.5, blue: 0.8)
        case .top: return Color(red: 0.2, green: 0.65, blue: 0.2)
        case .back: return Color(red: 0.8, green: 0.4, blue: 0.0)
        case .dipole: return Color(red: 0.6, green: 0.0, blue: 0.8)
        case .ringMode: return Color(red: 0.8, green: 0.0, blue: 0.4)
        default: return .secondary
        }
    }

    // MARK: - Analysis Results

    @ViewBuilder
    private var analysisSection: some View {
        switch data.measurementType {
        case .material:
            if let props = data.materialProperties {
                materialSection(props)
            }
        case .brace:
            if let props = data.materialProperties {
                braceSection(props)
            }
        default:
            // Guitar types
            guitarAnalysisSection
        }
    }

    // MARK: Guitar Analysis

    private var guitarAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Analysis Results")
                .font(.system(size: 13, weight: .semibold))

            HStack(alignment: .top, spacing: 16) {
                // Ring-out time
                if let decay = data.decayTime {
                    analysisBox(
                        title: "Ring-Out Time",
                        value: String(format: "%.2f s", decay),
                        detail: decay.decayQuality,
                        detailColor: decay.decayQualityColor
                    )
                }

                // Tap tone ratio
                if let ratio = data.tapToneRatio {
                    analysisBox(
                        title: "Tap Tone Ratio",
                        value: String(format: "%.2f : 1", ratio),
                        detail: ratio.tapToneRatioQuality,
                        detailColor: ratio.tapToneRatioQualityColor
                    )
                }
            }
        }
    }

    private func analysisBox(title: String, value: String, detail: String, detailColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold))
            Text(detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(detailColor)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.07))
        .cornerRadius(6)
    }

    // MARK: Material Analysis

    private func materialSection(_ props: MaterialProperties) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Material Properties")
                .font(.system(size: 13, weight: .semibold))

            HStack(alignment: .top, spacing: 0) {
                // Left column
                VStack(alignment: .leading, spacing: 6) {
                    materialPropRow("Speed of Sound (L)",
                                   String(format: "%.0f m/s", props.speedOfSoundLong))
                    materialPropRow("Speed of Sound (C)",
                                   String(format: "%.0f m/s", props.speedOfSoundCross))
                    materialPropRow("Young's Modulus (L)",
                                   String(format: "%.2f GPa", props.youngsModulusLongGPa))
                    materialPropRow("Young's Modulus (C)",
                                   String(format: "%.2f GPa", props.youngsModulusCrossGPa))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right column
                VStack(alignment: .leading, spacing: 6) {
                    specificModulusRow("Specific Modulus (L)",
                                      value: props.specificModulusLong,
                                      quality: props.spruceQualityLong)
                    specificModulusRow("Specific Modulus (C)",
                                      value: props.specificModulusCross,
                                      quality: props.spruceQualityCross)
                    materialPropRow("Radiation Ratio (L)",
                                   String(format: "%.1f", props.radiationRatioLong))
                    materialPropRow("Radiation Ratio (C)",
                                   String(format: "%.1f", props.radiationRatioCross))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Cross/Long ratio and overall quality
            HStack(spacing: 12) {
                materialPropRow("Cross/Long Ratio",
                               String(format: "%.3f", props.crossLongRatio))
                materialPropRow("Overall Quality",
                               props.overallQuality.rawValue)
            }
        }
    }

    private func braceSection(_ props: MaterialProperties) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Brace Properties")
                .font(.system(size: 13, weight: .semibold))

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    materialPropRow("Speed of Sound",
                                   String(format: "%.0f m/s", props.speedOfSoundLong))
                    materialPropRow("Young's Modulus (E)",
                                   String(format: "%.2f GPa", props.youngsModulusLongGPa))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    specificModulusRow("Specific Modulus",
                                      value: props.specificModulusLong,
                                      quality: props.spruceQualityLong)
                    materialPropRow("Radiation Ratio",
                                   String(format: "%.1f", props.radiationRatioLong))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func materialPropRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label + ":")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
        }
    }

    private func specificModulusRow(_ label: String, value: Float, quality: WoodQuality) -> some View {
        HStack(spacing: 6) {
            Text(label + ":")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(String(format: "%.1f", value))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(qualityColor(for: quality))
            Text("(\(quality.rawValue))")
                .font(.system(size: 9))
                .foregroundColor(qualityColor(for: quality))
        }
    }

    private func qualityColor(for quality: WoodQuality) -> Color {
        switch quality {
        case .excellent: return Color(red: 0.0, green: 0.5, blue: 0.9)
        case .veryGood: return Color(red: 0.0, green: 0.6, blue: 0.0)
        case .good: return .green
        case .fair: return .orange
        case .poor: return .red
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 16)
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1)
            Spacer().frame(height: 8)
            HStack {
                Text("Generated by GuitarTap")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Spacer()
                Text(Date().formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
}
