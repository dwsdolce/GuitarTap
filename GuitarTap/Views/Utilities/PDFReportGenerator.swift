/// # PDFReportGenerator
///
/// Generates a single-page PDF tap tone analysis report from a
/// `PDFReportData` value struct.
///
/// ## Architecture
///
/// ```
/// TapToneMeasurement  ──►  PDFReportData.from(measurement:)
///                               │
///                               ▼
///                        PDFReportGenerator.generate(data:)
///                               │
///                               ▼ (ImageRenderer on @MainActor)
///                        PDFReportContentView
///                               │
///                               ▼
///                        CGContext PDF page  ──►  Data (PDF bytes)
/// ```
///
/// `PDFReportData` is a plain value type that carries everything the renderer
/// needs: timestamps, peaks, material properties, spectrum image data, and
/// display-range bounds.  The static factory `PDFReportData.from(measurement:)`
/// re-derives computed `PlateProperties` / `BraceProperties` from the
/// measurement's saved dimensions and frequency IDs, matching the logic used
/// in the live analysis view.
///
/// `PDFReportGenerator.generate(data:)` must be called on the `@MainActor`
/// because `ImageRenderer` is main-actor-bound.  It renders
/// `PDFReportContentView` into a single `CGContext` PDF page whose size
/// matches the SwiftUI view's natural size.
///
/// ## Page layout
///
/// The US Letter-width page (612 pt) is divided vertically into sections:
/// - Header: app name + accent bar + timestamp
/// - Metadata: measurement name, measurement type, frequency range, microphone
/// - Spectrum image (if present, max 220 pt tall)
/// - Peaks table: frequency, magnitude, note, and mode/role columns
/// - Tap instructions (plate/brace measurements only)
/// - Analysis results: guitar (ring-out + tap tone ratio),
///   plate (computed properties + Gore target thickness),
///   or brace (computed properties)
/// - Footer: GuitarTap version + generation timestamp
///
/// The page margin is 36 pt on all sides; content width is 540 pt.
///
/// - SeeAlso: `MeasurementFileExporter`, `TapToneAnalysisView+Export`
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

/// All data required to render a PDF tap tone analysis report.
///
/// `PDFReportData` is a pure value type; it contains no ObservableObject
/// references.  Create it from a saved measurement with the
/// `from(measurement:)` factory, or construct it directly for custom reports.
///
/// Material property objects (`plateProperties`, `braceProperties`) are
/// computed from the measurement's stored dimensions and peak IDs inside
/// `from(measurement:)` so the PDF accurately reflects the live analysis.
struct PDFReportData {
    /// Date and time the measurement was captured.
    let timestamp: Date
    /// User-supplied measurement name label (e.g., "Martin 1943", "Ramirez 1975").
    let measurementName: String?
    /// Free-text notes entered by the user at save time.
    let notes: String?
    /// Type of measurement: guitar, plate, or brace.
    let measurementType: MeasurementType
    /// Guitar body type (classical, steel-string, etc.) — used for mode classification.
    let guitarType: GuitarType
    /// All detected peaks, already filtered to the display frequency range.
    let peaks: [ResonantPeak]
    /// The set of peak IDs that are selected/visible in the report.
    let selectedPeakIDs: Set<UUID>
    /// Ring-out time in seconds (time for the signal to decay 15 dB), or `nil`
    /// if decay tracking was not performed.
    let decayTime: Float?
    /// Tap tone ratio (fTop / fAir), or `nil` for non-guitar measurements.
    let tapToneRatio: Float?
    /// PNG-encoded spectrum chart image, or `nil` if none was captured.
    let spectrumImageData: Data?
    /// Lower bound of the displayed frequency range, in Hz.
    let minFreq: Float
    /// Upper bound of the displayed frequency range, in Hz.
    let maxFreq: Float
    /// Computed plate stiffness properties, or `nil` for non-plate measurements.
    let plateProperties: PlateProperties?
    /// Computed brace stiffness properties, or `nil` for non-brace measurements.
    let braceProperties: BraceProperties?
    /// Peak ID of the selected longitudinal frequency (plate/brace), or `nil`.
    let selectedLongitudinalPeakID: UUID?
    /// Peak ID of the selected cross-grain frequency (plate only), or `nil`.
    let selectedCrossPeakID: UUID?
    /// Peak ID of the selected FLC (diagonal shear) frequency (plate only), or `nil`.
    let selectedFlcPeakID: UUID?

    /// Per-peak user mode overrides; empty means all peaks use auto-classification.
    var peakModeOverrides: [UUID: UserAssignedMode] = [:]

    /// Context-aware mode classification for all peaks, keyed by peak UUID.
    /// Computed via ``GuitarMode/classifyAll(_:guitarType:)`` so overlapping ranges
    /// (e.g. classical Top/Back) resolve correctly.  Used by the peak table and
    /// chart summary in place of per-frequency `GuitarMode.classify(frequency:guitarType:)`.
    var peakModes: [UUID: GuitarMode] = [:]

    // MARK: Microphone info
    /// Display name of the recording microphone, or `nil` if unavailable.
    let microphoneName: String?
    /// Name of the applied calibration profile, or `nil` if uncalibrated.
    let calibrationName: String?

    // MARK: Gore thicknessing inputs (for plate measurements)
    /// Guitar body length used for Gore target thickness calculation, in mm.
    let guitarBodyLength: Float
    /// Guitar body width used for Gore target thickness calculation, in mm.
    let guitarBodyWidth: Float
    /// Vibrational stiffness value (f_vs) used in the Gore equation.
    let plateStiffness: Float
    /// Named preset that produced `plateStiffness`, or `.custom` for a manual value.
    let plateStiffnessPreset: PlateStiffnessPreset

    /// Builds a `PDFReportData` from a persisted `TapToneMeasurement`.
    ///
    /// The factory re-derives `PlateProperties` / `BraceProperties` from the
    /// measurement's stored peak IDs and snapshot dimensions so that computed
    /// values match the live analysis view.  Peaks are filtered to those within
    /// the saved display frequency range.
    ///
    /// - Parameter measurement: The saved measurement to generate a report for.
    /// - Parameter spectrumImageData: Optional pre-rendered spectrum image (PNG) to embed;
    ///   when `nil`, the report renders without an embedded chart image.
    /// - Returns: A fully populated `PDFReportData` ready for `PDFReportGenerator.generate(data:)`.
    static func from(measurement: TapToneMeasurement, spectrumImageData: Data? = nil) -> PDFReportData {
        let snapshot = measurement.spectrumSnapshot
        let anySnapshot = snapshot ?? measurement.longitudinalSnapshot ?? measurement.crossSnapshot
        let measurementType = anySnapshot?.measurementType ?? .classical
        let guitarType = anySnapshot?.guitarType ?? .classical

        // Compute material properties if applicable
        var plateProps: PlateProperties? = nil
        var braceProps: BraceProperties? = nil
        if measurementType == .plate {
            let longID = measurement.selectedLongitudinalPeakID
            let crossID = measurement.selectedCrossPeakID
            let flcID = measurement.selectedFlcPeakID
            if let longPeak = measurement.peaks.first(where: { $0.id == longID }),
               let crossPeak = measurement.peaks.first(where: { $0.id == crossID }) {
                let flcPeak = measurement.peaks.first(where: { $0.id == flcID })
                let dims = MaterialDimensions(
                    lengthMM: anySnapshot?.plateLength ?? 0,
                    widthMM: anySnapshot?.plateWidth ?? 0,
                    thicknessMM: anySnapshot?.plateThickness ?? 0,
                    massGrams: anySnapshot?.plateMass ?? 0
                )
                if dims.length > 0 && dims.mass > 0 {
                    plateProps = PlateProperties(
                        dimensions: dims,
                        fundamentalFrequencyLong: longPeak.frequency,
                        fundamentalFrequencyCross: crossPeak.frequency,
                        fundamentalFrequencyFlc: flcPeak?.frequency
                    )
                }
            }
        } else if measurementType == .brace {
            let longID = measurement.selectedLongitudinalPeakID
            if let longPeak = measurement.peaks.first(where: { $0.id == longID }) {
                let dims = MaterialDimensions(
                    lengthMM: anySnapshot?.braceLength ?? 0,
                    widthMM: anySnapshot?.braceWidth ?? 0,
                    thicknessMM: anySnapshot?.braceThickness ?? 0,
                    massGrams: anySnapshot?.braceMass ?? 0
                )
                if dims.length > 0 && dims.mass > 0 {
                    braceProps = BraceProperties(
                        dimensions: dims,
                        fundamentalFrequencyLong: longPeak.frequency
                    )
                }
            }
        }

        // For guitar measurements snapshot holds the display range; for plate/brace
        // measurements spectrumSnapshot is nil and the range lives in the per-phase snapshots.
        let displaySnapshot = snapshot ?? anySnapshot
        let minFreq = displaySnapshot?.minFreq ?? 50
        let maxFreq = displaySnapshot?.maxFreq ?? 1000

        // Filter peaks to those within the saved display frequency range
        let rangeFilteredPeaks = measurement.peaks.filter {
            $0.frequency >= minFreq && $0.frequency <= maxFreq
        }

        return PDFReportData(
            timestamp: measurement.timestamp,
            measurementName: measurement.measurementName,
            notes: measurement.notes,
            measurementType: measurementType,
            guitarType: guitarType,
            peaks: rangeFilteredPeaks,
            selectedPeakIDs: measurement.effectiveSelectedPeakIDs,
            decayTime: measurement.decayTime,
            tapToneRatio: measurement.tapToneRatio,
            spectrumImageData: spectrumImageData,
            minFreq: minFreq,
            maxFreq: maxFreq,
            plateProperties: plateProps,
            braceProperties: braceProps,
            selectedLongitudinalPeakID: measurement.selectedLongitudinalPeakID,
            selectedCrossPeakID: measurement.selectedCrossPeakID,
            selectedFlcPeakID: measurement.selectedFlcPeakID,
            peakModeOverrides: measurement.peakModeOverrides ?? [:],
            peakModes: GuitarMode.classifyAll(rangeFilteredPeaks, guitarType: guitarType),
            microphoneName: measurement.microphoneName,
            calibrationName: measurement.calibrationName,
            guitarBodyLength: anySnapshot?.guitarBodyLength ?? TapDisplaySettings.guitarBodyLength,
            guitarBodyWidth: anySnapshot?.guitarBodyWidth ?? TapDisplaySettings.guitarBodyWidth,
            plateStiffness: {
                let preset = anySnapshot?.plateStiffnessPreset ?? TapDisplaySettings.plateStiffnessPreset
                if preset == .custom {
                    return anySnapshot?.customPlateStiffness ?? TapDisplaySettings.customPlateStiffness
                }
                return preset.value
            }(),
            plateStiffnessPreset: anySnapshot?.plateStiffnessPreset ?? TapDisplaySettings.plateStiffnessPreset
        )
    }

    /// Filename stem (without extension) for this report.
    ///
    /// Derived from `measurementName` (spaces and slashes replaced with dashes,
    /// lowercased) and a Unix timestamp, e.g. `"bridge-plate-1740000000"`.
    var baseFilename: String {
        ExportFilename.stem(name: measurementName, timestamp: timestamp, unnamed: "report")
    }
}

// MARK: - PDF Generator

/// Generates PDF data by rendering `PDFReportContentView` via `ImageRenderer`.
struct PDFReportGenerator {

    /// Renders a single-page PDF for the supplied report data.
    ///
    /// Internally creates a `PDFReportContentView`, renders it with
    /// `ImageRenderer`, and writes the output to a `CGContext` PDF page whose
    /// media box matches the SwiftUI view's natural size.
    ///
    /// - Parameter data: The report data to render.
    /// - Returns: Raw PDF `Data` on success, or `nil` if the `CGDataConsumer`
    ///   or `CGContext` could not be created.
    /// - Important: Must be called on the `@MainActor` because `ImageRenderer`
    ///   requires it.
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

/// SwiftUI view that lays out the full tap tone analysis report page.
///
/// Designed for off-screen rendering via `ImageRenderer`; not intended to be
/// displayed in a live view hierarchy.
///
/// The page is US Letter width (612 pt) with 36 pt margins, giving a content
/// width of 540 pt.  Sections are stacked vertically with fixed `Spacer` gaps;
/// the natural height of the view determines the PDF page height.
private struct PDFReportContentView: View {
    /// All data needed to populate the report sections.
    let data: PDFReportData

    /// Total page width in points (US Letter width).
    private let pageWidth: CGFloat = 612
    /// Horizontal and vertical page margin in points.
    private let margin: CGFloat = 36
    /// Available content width = `pageWidth - 2 × margin` (540 pt).
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
            tapInstructionsSection
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
                Text(DateDisplay.string(data.timestamp))
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
            if let measurementName = data.measurementName, !measurementName.isEmpty {
                metaRow(label: "Measurement Name", value: measurementName)
            }
            metaRow(label: "Type", value: data.measurementType.rawValue)  // rawValue is the display name
            if let notes = data.notes, !notes.isEmpty {
                metaRow(label: "Notes", value: notes)
            }
            metaRow(label: "Frequency Range",
                    value: "\(data.minFreq.formattedAsFrequency()) – \(data.maxFreq.formattedAsFrequency())")
            if let mic = data.microphoneName {
                let calSuffix = data.calibrationName.map { " · calibrated (\($0))" } ?? " · uncalibrated"
                metaRow(label: "Microphone", value: mic + calSuffix)
            }
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label + ":")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
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
                .frame(width: contentWidth)
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
            .filter { data.selectedPeakIDs.contains($0.id) }
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
        if data.measurementType == .plate || data.measurementType == .brace {
            Text("Role")
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }

    /// Returns the effective mode label for a peak, applying any user override.
    ///
    /// If the peak has a user-assigned mode in `data.peakModeOverrides`, the
    /// override label is returned with a `" *"` suffix to indicate it was
    /// manually set.  Otherwise the auto-classified `GuitarMode.displayName` is
    /// returned without a suffix.
    ///
    /// - Parameter peak: The peak whose mode label is needed.
    /// - Returns: A tuple with the display label string and a flag indicating
    ///   whether the label came from a user override.
    private func effectiveModeLabel(for peak: ResonantPeak) -> (label: String, isOverridden: Bool) {
        switch data.peakModeOverrides[peak.id] ?? .auto {
        case .auto:
            let mode = data.peakModes[peak.id] ?? .unknown
            return (mode.displayName, false)
        case .assigned(let label):
            return (label + " *", true)
        }
    }

    private func peakRow(for peak: ResonantPeak) -> some View {
        let modeInfo = data.measurementType.isGuitar ? effectiveModeLabel(for: peak) : nil
        let mode = data.peakModes[peak.id] ?? .unknown

        // Determine effective color: freeform user-defined label → teal,
        // predefined override → overridden mode's color, auto → classified mode's color.
        let effectiveColor: Color = {
            if case .assigned(let label) = data.peakModeOverrides[peak.id] {
                if let overriddenMode = GuitarMode.fromDisplayName(label) {
                    return modeColor(overriddenMode)
                }
                return GuitarMode.userDefinedColor
            }
            return modeColor(mode)
        }()

        return HStack(spacing: 0) {
            Text(String(format: "%.1f Hz", peak.frequency))
                .frame(width: 90, alignment: .leading)
            Text(String(format: "%.1f dB", peak.magnitude))
                .frame(width: 80, alignment: .leading)
            Text(peak.pitchNote ?? "–")
                .frame(width: 80, alignment: .leading)
            if data.measurementType.isGuitar {
                let label = modeInfo?.label ?? mode.displayName
                let isOverridden = modeInfo?.isOverridden ?? false
                Text(label)
                    .font(isOverridden ? .system(size: 10).italic() : .system(size: 10))
                    .foregroundColor(effectiveColor)
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
        if data.measurementType == .plate {
            let isLong = peak.id == data.selectedLongitudinalPeakID
            let isCross = peak.id == data.selectedCrossPeakID
            let isFlc = peak.id == data.selectedFlcPeakID
            Group {
                if isLong {
                    Text("Longitudinal (fL)")
                        .foregroundColor(.blue)
                } else if isCross {
                    Text("Cross-grain (fC)")
                        .foregroundColor(.orange)
                } else if isFlc {
                    Text("Diagonal (fLC)")
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
                    Text("Longitudinal (fL)")
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

    // MARK: - Tap Instructions

    @ViewBuilder
    private var tapInstructionsSection: some View {
        if data.measurementType == .plate {
            let hasFlc = data.selectedFlcPeakID != nil
            VStack(alignment: .leading, spacing: 6) {
                sectionDivider
                Spacer().frame(height: 6)
                Text(hasFlc ? "Three-Tap Measurement Process:" : "Two-Tap Measurement Process:")
                    .font(.system(size: 10, weight: .semibold))

                tapInstructionRow(color: .blue,
                                  title: "1. Longitudinal (fL) Tap",
                                  detail: "Hold plate at 22% from one end along the length, near one long edge (not at the width node). Tap center.")
                tapInstructionRow(color: .orange,
                                  title: "2. Cross-grain (fC) Tap",
                                  detail: "Rotate 90°. Hold plate at 22% from one end along the width, near one short edge (not at the length node). Tap center.")
                if hasFlc {
                    tapInstructionRow(color: .purple,
                                      title: "3. Diagonal (fLC) Tap",
                                      detail: "Hold plate at the midpoint of one long edge. Tap near the opposite corner (~22% from both the end and the side). Measures shear stiffness.")
                }
                Text("The strongest peak from each tap is auto-selected.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .italic()
            }
            Spacer().frame(height: 14)
        } else if data.measurementType == .brace {
            VStack(alignment: .leading, spacing: 6) {
                sectionDivider
                Spacer().frame(height: 6)
                Text("Single-Tap Measurement (fL only):")
                    .font(.system(size: 10, weight: .semibold))

                tapInstructionRow(color: .blue,
                                  title: "1. Longitudinal (fL) Tap",
                                  detail: "Hold brace at 22% from one end along the length. Tap center.")
                Text("The strongest peak is auto-selected.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .italic()
            }
            Spacer().frame(height: 14)
        }
    }

    private func tapInstructionRow(color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Analysis Results

    @ViewBuilder
    private var analysisSection: some View {
        switch data.measurementType {
        case .plate:
            if let props = data.plateProperties {
                // Same order as the Results panel: Sample Dimensions → Body Dimensions → Gore target
                // (just the number) → Plate Properties (GLC lives among the moduli there).
                dimensionsSubsection(dims: props.dimensions)
                Spacer().frame(height: 14)
                sectionDivider
                Spacer().frame(height: 14)
                plateBodyDimensionsPDFSection(props)
                Spacer().frame(height: 14)
                sectionDivider
                Spacer().frame(height: 14)
                goreThicknessPDFSection(props)
                Spacer().frame(height: 14)
                sectionDivider
                Spacer().frame(height: 14)
                plateSection(props)
            }
        case .brace:
            if let props = data.braceProperties {
                // Sample Dimensions first, then the derived Brace Properties.
                dimensionsSubsection(dims: props.dimensions)
                Spacer().frame(height: 14)
                sectionDivider
                Spacer().frame(height: 14)
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
                        subtitle: "Time to decay 15 dB",
                        detail: decay.decayQuality,
                        detailSubtitle: "Sustain quality",
                        detailColor: decay.decayQualityColor
                    )
                }

                // Tap tone ratio
                if let ratio = data.tapToneRatio {
                    analysisBox(
                        title: "Tap Tone Ratio",
                        value: String(format: "%.2f : 1", ratio),
                        subtitle: "Top / Air",
                        detail: ratio.tapToneRatioQuality,
                        detailColor: ratio.tapToneRatioQualityColor,
                        hint: "Ideal: 1.9–2.1"
                    )
                }
            }
        }
    }

    private func analysisBox(title: String, value: String, subtitle: String? = nil,
                             detail: String, detailSubtitle: String? = nil,
                             detailColor: Color, hint: String? = nil) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(detailColor)
                if let detailSubtitle {
                    Text(detailSubtitle)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                if let hint {
                    Text(hint)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.07))
        .cornerRadius(6)
    }

    // MARK: Plate Analysis

    private func plateSection(_ props: PlateProperties) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plate Properties")
                .font(.system(size: 13, weight: .semibold))

            // (fL / fC / fLC are inputs, shown in the Detected Peaks table — not repeated here.)

            HStack(alignment: .top, spacing: 0) {
                // Left column
                VStack(alignment: .leading, spacing: 6) {
                    platePropRow("Speed of Sound (L)",
                                   String(format: "%.0f m/s", props.speedOfSoundLong))
                    platePropRow("Speed of Sound (C)",
                                   String(format: "%.0f m/s", props.speedOfSoundCross))
                    platePropRow("Young's Modulus (L)",
                                   String(format: "%.2f GPa", props.youngsModulusLongGPa))
                    platePropRow("Young's Modulus (C)",
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
                    platePropRow("Radiation Ratio (L)",
                                   String(format: "%.1f", props.radiationRatioLong))
                    platePropRow("Radiation Ratio (C)",
                                   String(format: "%.1f", props.radiationRatioCross))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // GLC shear modulus (if the Diagonal fLC tap was performed)
            if let glc = props.goreShearModulus {
                platePropRow("GLC (Shear Modulus)",
                               String(format: "%.3f GPa", glc / 1.0e9))
            } else {
                Text("GLC assumed 0 — fLC tap not performed")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .italic()
            }

            // Cross/Long ratio, Long/Cross ratio
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    platePropRow("Cross/Long Ratio",
                                   String(format: "%.3f", props.crossLongRatio))
                    Text("typical: 0.04–0.08")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .italic()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    platePropRow("Long/Cross Ratio",
                                   String(format: "%.1f", props.longCrossRatio))
                    Text("typical: 12–25")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .italic()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Overall Quality — prominent row
            HStack {
                Text("Overall Quality:")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(props.overallQuality.rawValue)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(props.overallQuality.color)
                Spacer()
            }
            .padding(8)
            .background(Color.gray.opacity(0.07))
            .cornerRadius(4)
        }
    }

    private func braceSection(_ props: BraceProperties) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Brace Properties")
                .font(.system(size: 13, weight: .semibold))

            // (fL is an input, shown in the Detected Peaks table — not repeated here.)

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    platePropRow("Speed of Sound",
                                   String(format: "%.0f m/s", props.speedOfSoundLong))
                    platePropRow("Young's Modulus (E)",
                                   String(format: "%.2f GPa", props.youngsModulusLongGPa))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    specificModulusRow("Specific Modulus",
                                      value: props.specificModulusLong,
                                      quality: props.spruceQuality)
                    platePropRow("Radiation Ratio",
                                   String(format: "%.1f", props.radiationRatioLong))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Overall Quality — prominent row
            HStack {
                Text("Overall Quality:")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(props.spruceQuality.rawValue)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(props.spruceQuality.color)
                Spacer()
            }
            .padding(8)
            .background(Color.gray.opacity(0.07))
            .cornerRadius(4)
        }
    }

    /// Renders a compact row of sample input dimensions.
    private func dimensionsSubsection(dims: MaterialDimensions) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sample Dimensions")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            // Geometry on first line
            HStack(spacing: 0) {
                platePropRow("Length", FieldPrecision.string(dims.length * 1000, FieldPrecision.linearDimensionMM) + " mm")
                    .frame(maxWidth: .infinity, alignment: .leading)
                platePropRow("Width", FieldPrecision.string(dims.width * 1000, FieldPrecision.linearDimensionMM) + " mm")
                    .frame(maxWidth: .infinity, alignment: .leading)
                platePropRow("Thickness", FieldPrecision.string(dims.thickness * 1000, FieldPrecision.linearDimensionMM) + " mm")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Mass and density on second line
            HStack(spacing: 0) {
                platePropRow("Mass", FieldPrecision.string(dims.mass * 1000, FieldPrecision.massG) + " g")
                    .frame(maxWidth: .infinity, alignment: .leading)
                platePropRow("Density", String(format: "%.3f g/cm³", dims.densityGPerCm3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(6)
        .background(Color.gray.opacity(0.06))
        .cornerRadius(4)
    }

    /// Renders the plate Gore body inputs — finished-guitar body dimensions (a, b) and panel
    /// stiffness (f_vs). Mirrors the Results panel's Body Dimensions section; feeds only the Gore target.
    private func plateBodyDimensionsPDFSection(_ props: PlateProperties) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Body Dimensions")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)

            let presetLabel = data.plateStiffnessPreset == .custom
                ? String(format: "f_vs = %.0f (custom)", data.plateStiffness)
                : "f_vs = \(Int(data.plateStiffness)) (\(data.plateStiffnessPreset.rawValue))"
            // Body dims on the first line; panel stiffness on its own line — the preset label is long
            // and wraps awkwardly if squeezed into a third column.
            HStack(spacing: 0) {
                platePropRow("Body Length (a)",
                             FieldPrecision.string(data.guitarBodyLength, FieldPrecision.bodyDimensionMM) + " mm")
                    .frame(maxWidth: .infinity, alignment: .leading)
                platePropRow("Lower Bout Width (b)",
                             FieldPrecision.string(data.guitarBodyWidth, FieldPrecision.bodyDimensionMM) + " mm")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            platePropRow("Panel Stiffness", presetLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .background(Color.gray.opacity(0.06))
        .cornerRadius(4)
    }

    /// Renders the Gore target thickness result (plate measurements only) — just the number. The
    /// inputs live in the Body Dimensions section above, and GLC among the Plate Properties moduli.
    @ViewBuilder
    private func goreThicknessPDFSection(_ props: PlateProperties) -> some View {
        if let hd = props.goreTargetThickness(
            bodyLengthMm: data.guitarBodyLength,
            bodyWidthMm: data.guitarBodyWidth,
            vibrationalStiffness: data.plateStiffness) {

            VStack(alignment: .leading, spacing: 4) {
                Text("Gore Target Thickness")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.2f mm", hd))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(red: 0.15, green: 0.35, blue: 0.75))
                    Spacer()
                }
            }
            .padding(6)
            .background(Color(red: 0.15, green: 0.35, blue: 0.75).opacity(0.07))
            .cornerRadius(4)
        }
    }

    private func platePropRow(_ label: String, _ value: String) -> some View {
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
                .foregroundColor(quality.color)
            Text("(\(quality.rawValue))")
                .font(.system(size: 9))
                .foregroundColor(quality.color)
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
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
                Text("Generated by GuitarTap \(version) (\(build))")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Spacer()
                Text(DateDisplay.string(Date()))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Comparison Report Data

/// All data required to render a PDF comparison report.
///
/// Create from the analyzer's `comparisonSpectra` and `comparisonSnapshots`
/// in `exportComparisonPDFReport()`, then pass to
/// `PDFReportGenerator.generateComparison(data:)`.
struct ComparisonPDFReportData {
    /// Date and time the report was generated.
    let timestamp: Date
    /// User-supplied name for the comparison (from `measurementName`), or `nil`.
    let comparisonLabel: String?
    /// Free-text notes from the save form, or `nil`.
    let notes: String?
    /// PNG-encoded spectrum overlay chart image, or `nil` if unavailable.
    let spectrumImageData: Data?
    /// The comparison entries — one per overlaid spectrum.
    let entries: [ComparisonEntry]
    /// Resolved Air/Top/Back frequencies per entry, keyed by entry index.
    let modeFrequencies: [(label: String, color: Color, air: Float?, top: Float?, back: Float?, overrideModes: Set<GuitarMode>)]
}

// MARK: - Comparison PDF Generator (extension on PDFReportGenerator)

extension PDFReportGenerator {

    /// Renders a two-page PDF for a multi-tap guitar measurement.
    ///
    /// Page 1 is the standard averaged-result report (`PDFReportContentView`).
    /// Page 2 is the per-tap comparison report (`ComparisonPDFReportContentView`).
    /// Both pages are written into a single PDF `CGContext` so the result is one file.
    ///
    /// - Parameters:
    ///   - averaged: Report data for the averaged spectrum page.
    ///   - comparison: Report data for the per-tap comparison page.
    /// - Returns: Raw PDF `Data` on success, or `nil` if the context could not be created.
    /// - Important: Must be called on the `@MainActor` because `ImageRenderer` requires it.
    @MainActor
    static func generateMultiTapReport(averaged: PDFReportData, comparison: ComparisonPDFReportData) -> Data? {
        let mutableData = NSMutableData()

        // Page 1 — averaged result
        let avgRenderer = ImageRenderer(content: PDFReportContentView(data: averaged))
        var contextCreated = false
        var pdfContext: CGContext?

        avgRenderer.render { size, draw in
            guard let consumer = CGDataConsumer(data: mutableData) else { return }
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }
            pdfContext = context
            contextCreated = true
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
        }

        guard contextCreated, let context = pdfContext else { return nil }

        // Page 2 — per-tap comparison
        let cmpRenderer = ImageRenderer(content: ComparisonPDFReportContentView(data: comparison))
        cmpRenderer.render { size, draw in
            var mediaBox = CGRect(origin: .zero, size: size)
            withUnsafeBytes(of: &mediaBox) { ptr in
                let data = CFDataCreate(nil, ptr.baseAddress?.assumingMemoryBound(to: UInt8.self), ptr.count)
                context.beginPDFPage([kCGPDFContextMediaBox as String: data as Any] as CFDictionary)
            }
            draw(context)
            context.endPDFPage()
        }

        context.closePDF()
        return mutableData.length > 0 ? mutableData as Data : nil
    }

    /// Renders a single-page PDF comparison report.
    ///
    /// - Parameter data: The comparison report data to render.
    /// - Returns: Raw PDF `Data` on success, or `nil` if the context could not be created.
    /// - Important: Must be called on the `@MainActor` because `ImageRenderer` requires it.
    @MainActor
    static func generateComparison(data: ComparisonPDFReportData) -> Data? {
        let contentView = ComparisonPDFReportContentView(data: data)
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

// MARK: - Comparison PDF Content View

/// SwiftUI view that lays out the comparison report page for off-screen rendering.
///
/// Sections (top to bottom):
/// 1. Header — "GuitarTap" + "Comparison Report" subtitle + date/time
/// 2. Blue accent bar
/// 3. Metadata — comparison label, notes, spectrum count, frequency range
/// 4. Spectrum image (if present)
/// 5. Divider
/// 6. Peak mode table — Air / Top / Back frequencies per spectrum
/// 7. Footer — version + generation timestamp
private struct ComparisonPDFReportContentView: View {
    let data: ComparisonPDFReportData

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
            peakModeTableSection
            footerSection
        }
        .padding(margin)
        .frame(width: pageWidth)
        .background(Color.white)
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GuitarTap")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color(red: 0.15, green: 0.35, blue: 0.75))
                Text("Comparison Report")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(DateDisplay.string(data.timestamp))
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

    // MARK: Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label = data.comparisonLabel, !label.isEmpty {
                metaRow(label: "Comparison", value: label)
            }
            if let notes = data.notes, !notes.isEmpty {
                metaRow(label: "Notes", value: notes)
            }
            metaRow(label: "Spectra", value: "\(data.entries.count) spectra compared")
            if let firstSnap = data.entries.first?.snapshot,
               let lastSnap = data.entries.last?.snapshot {
                let minF = data.entries.map(\.snapshot.minFreq).min() ?? firstSnap.minFreq
                let maxF = data.entries.map(\.snapshot.maxFreq).max() ?? lastSnap.maxFreq
                metaRow(label: "Frequency Range",
                        value: "\(minF.formattedAsFrequency()) – \(maxF.formattedAsFrequency())")
            }
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

    // MARK: Spectrum Image

    @ViewBuilder
    private func spectrumSection(imageData: Data) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Frequency Spectrum")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            reportImage(from: imageData)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: contentWidth)
                .background(Color(white: 0.05))
                .cornerRadius(6)
        }
    }

    private func reportImage(from imageData: Data) -> Image {
        #if os(iOS)
        if let img = UIImage(data: imageData) { return Image(uiImage: img) }
        #elseif os(macOS)
        if let img = NSImage(data: imageData) { return Image(nsImage: img) }
        #endif
        return Image(systemName: "photo")
    }

    // MARK: Divider

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 1)
    }

    // MARK: Peak Mode Table

    private let modeColumns: [(label: String, mode: GuitarMode, keyPath: KeyPath<(label: String, color: Color, air: Float?, top: Float?, back: Float?, overrideModes: Set<GuitarMode>), Float?>)] = [
        ("Air", .air, \.air),
        ("Top", .top, \.top),
        ("Back", .back, \.back)
    ]

    private var peakModeTableSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Peak Mode Comparison")
                .font(.system(size: 13, weight: .semibold))

            // Table header
            HStack(spacing: 0) {
                Text("Spectrum")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                ForEach(modeColumns, id: \.label) { col in
                    Text(col.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 90, alignment: .trailing)
                        .padding(.trailing, 6)
                        .padding(.vertical, 4)
                }
            }
            .background(Color.gray.opacity(0.1))
            .cornerRadius(4)

            // Data rows
            ForEach(Array(data.modeFrequencies.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    // Coloured dot + label
                    HStack(spacing: 5) {
                        Circle()
                            .fill(row.color)
                            .frame(width: 8, height: 8)
                        Text(row.label)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)

                    ForEach(modeColumns, id: \.label) { col in
                        let freq = row[keyPath: col.keyPath]
                        // A user-overridden value is shown italic with a " *" suffix — the SAME
                        // convention page 1's peak table uses for an overridden mode label — so it is
                        // not read as the averaged spectrum's auto-detected peak.
                        let isOverride = row.overrideModes.contains(col.mode)
                        Text((freq.map { String(format: "%.1f Hz", $0) } ?? "—") + (isOverride ? " *" : ""))
                            .font(isOverride ? .system(size: 10).italic() : .system(size: 10))
                            .foregroundColor(freq != nil ? .primary : .secondary)
                            .frame(width: 90, alignment: .trailing)
                            .padding(.trailing, 6)
                            .padding(.vertical, 4)
                    }
                }
                .font(.system(size: 10))
            }
        }
    }

    // MARK: Footer

    private var footerSection: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 16)
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1)
            Spacer().frame(height: 8)
            HStack {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
                Text("Generated by GuitarTap \(version) (\(build))")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Spacer()
                Text(DateDisplay.string(Date()))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
}
