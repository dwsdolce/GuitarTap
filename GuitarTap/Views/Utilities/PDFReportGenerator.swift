// @parity view/pdf-report tests=test/pdf-report,test/export-e2e

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
    var peakModeOverrides: [UUID: String] = [:]

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
        let measurementType = anySnapshot?.measurementType ?? .generic
        let guitarType = anySnapshot?.guitarType ?? .generic

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
            // The measurement's own modes — classified among all its peaks, as the file, the Details
            // pane and the live screen have them; never among the peaks in range.
            peakModes: measurement.autoModes,
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
        // Printed on white: the light appearance, whatever the screen's.
        let renderer = ImageRenderer(content: contentView.environment(\.colorScheme, .light))

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

/// The report's typeface: Helvetica, which every edition's PDF has, so the three editions lay the report
/// out alike.
private func pdfFontName(bold: Bool, italic: Bool) -> String {
    italic ? "Helvetica-Oblique" : bold ? "Helvetica-Bold" : "Helvetica"
}

/// Report text, each line exactly `size` points tall with the text on its bottom: macOS sets Helvetica so, iOS
/// sets every line taller (a taller ascender), and the report must be the same on every device. A text that may
/// wrap gives `wrapWidth`: it is broken into lines there as SwiftUI breaks it (TextKit, the standard
/// strategy, which avoids a lone word on the last line), and the lines are stacked at that height.
private struct PDFText: View {
    let string: String
    let size: CGFloat
    var bold = false
    var italic = false
    var wrapWidth: CGFloat?

    init(_ string: String, _ size: CGFloat, bold: Bool = false, italic: Bool = false, wrapWidth: CGFloat? = nil) {
        self.string = string
        self.size = size
        self.bold = bold
        self.italic = italic
        self.wrapWidth = wrapWidth
    }

    var body: some View {
        let font = Font.custom(pdfFontName(bold: bold, italic: italic), fixedSize: size)
        let lines = wrapWidth.map { Self.lines(of: string, font: pdfFontName(bold: bold, italic: italic),
                                               size: size, width: $0) } ?? [string]
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(font)
                    .frame(height: size, alignment: .bottomLeading)
            }
        }
    }

    /// `string` broken into lines in `font` at `size`, at `width`.
    static func lines(of string: String, font: String, size: CGFloat, width: CGFloat) -> [String] {
        let style = NSMutableParagraphStyle()
        style.lineBreakStrategy = .standard
        let storage = NSTextStorage(string: string, attributes: [
            .font: CTFontCreateWithName(font as CFString, size, nil), .paragraphStyle: style])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let characters = string as NSString
        var lines: [String] = []
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, glyphs, _ in
            let range = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            lines.append(characters.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return lines.isEmpty ? [string] : lines
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
        // Text with no colour of its own is the report's text colour, not the system's black.
        .foregroundStyle(Palette.color(.pdfText))
        .padding(margin)
        .frame(width: pageWidth)
        .background(Palette.color(.backgroundPanel))
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                PDFText("GuitarTap", 22, bold: true)
                    .foregroundColor(Palette.color(.pdfAccent))
                PDFText("Tap Tone Analysis Report", 13)
                    .foregroundColor(Palette.color(.pdfSecondary))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                PDFText(DateDisplay.string(data.timestamp), 11)
                    .foregroundColor(Palette.color(.pdfSecondary))
            }
        }
        .padding(.bottom, 8)
    }

    private var accentBar: some View {
        Rectangle()
            .fill(Palette.color(.pdfAccent))
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
            // No recorded microphone means it is unknown (a played file, say): say so, and keep the calibration.
            let calSuffix = data.calibrationName.map { " · calibrated (\($0))" } ?? " · uncalibrated"
            metaRow(label: "Microphone", value: (data.microphoneName ?? "unknown") + calSuffix)
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            PDFText(label + ":", 11, bold: true)
                .foregroundColor(Palette.color(.pdfSecondary))
                .frame(width: 120, alignment: .leading)
            PDFText(value, 11, wrapWidth: contentWidth - 120 - 6)
                .foregroundColor(Palette.color(.pdfText))
        }
    }

    // MARK: - Spectrum Image

    @ViewBuilder
    private func spectrumSection(imageData: Data) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PDFText("Frequency Spectrum", 12, bold: true)
                .foregroundColor(Palette.color(.pdfSecondary))

            reportImage(from: imageData)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: contentWidth)
                .background(Palette.color(.pdfChartMatte))
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
            .fill(Palette.color(.pdfDivider))
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
            PDFText("Detected Peaks", 13, bold: true)

            if visibleSortedPeaks.isEmpty {
                PDFText("No peaks detected in this measurement.", 11)
                    .foregroundColor(Palette.color(.pdfSecondary))
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
            PDFText("Frequency", 10, bold: true)
                .frame(width: 90, alignment: .leading)
            PDFText("Magnitude", 10, bold: true)
                .frame(width: 80, alignment: .leading)
            PDFText("Note", 10, bold: true)
                .frame(width: 80, alignment: .leading)
            if data.measurementType.isGuitar {
                PDFText("Mode", 10, bold: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                PDFText("Q Factor", 10, bold: true)
                    .frame(width: 70, alignment: .leading)
                peakRoleHeader
            }
        }
        .foregroundColor(Palette.color(.pdfSecondary))
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Palette.color(.pdfPill))
        .cornerRadius(4)
    }

    @ViewBuilder
    private var peakRoleHeader: some View {
        if data.measurementType == .plate || data.measurementType == .brace {
            PDFText("Role", 10, bold: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(Palette.color(.pdfSecondary))
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
        if let label = data.peakModeOverrides[peak.id] { return (label + " *", true) }
        return ((data.peakModes[peak.id] ?? .unknown).displayName, false)
    }

    private func peakRow(for peak: ResonantPeak) -> some View {
        let modeInfo = data.measurementType.isGuitar ? effectiveModeLabel(for: peak) : nil
        let mode = data.peakModes[peak.id] ?? .unknown

        // Determine effective color: freeform user-defined label → teal,
        // predefined override → overridden mode's color, auto → classified mode's color.
        let effectiveColor: Color = {
            if let label = data.peakModeOverrides[peak.id] {
                if let overriddenMode = GuitarMode.fromDisplayName(label) {
                    return Palette.color(overriddenMode)
                }
                return Palette.userDefined
            }
            return Palette.color(mode)
        }()

        return HStack(spacing: 0) {
            PDFText("\(FieldPrecision.string(peak.frequency, FieldPrecision.peakFrequencyHz)) Hz", 10)
                .frame(width: 90, alignment: .leading)
            PDFText("\(FieldPrecision.string(peak.magnitude, FieldPrecision.peakMagnitudeDB)) dB", 10)
                .frame(width: 80, alignment: .leading)
            PDFText(peak.pitchNote ?? "–", 10)
                .frame(width: 80, alignment: .leading)
            if data.measurementType.isGuitar {
                let label = modeInfo?.label ?? mode.displayName
                let isOverridden = modeInfo?.isOverridden ?? false
                // The Mode column: the content, less the row's padding and the columns before it.
                PDFText(label, 10, italic: isOverridden, wrapWidth: contentWidth - 2 * 6 - (90 + 80 + 80))
                    .foregroundColor(effectiveColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                PDFText(FieldPrecision.string(peak.quality, FieldPrecision.qFactor), 10)
                    .frame(width: 70, alignment: .leading)
                peakRoleCell(for: peak)
            }
        }
        .foregroundColor(Palette.color(.pdfText))
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
                    PDFText("Longitudinal (fL)", 10)
                        .foregroundColor(Palette.color(.materialLongitudinal))
                } else if isCross {
                    PDFText("Cross-grain (fC)", 10)
                        .foregroundColor(Palette.color(.materialCross))
                } else if isFlc {
                    PDFText("Diagonal (fLC)", 10)
                        .foregroundColor(Palette.color(.materialFlc))
                } else {
                    PDFText("–", 10)
                        .foregroundColor(Palette.color(.pdfSecondary))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if data.measurementType == .brace {
            let isLong = peak.id == data.selectedLongitudinalPeakID
            Group {
                if isLong {
                    PDFText("Longitudinal (fL)", 10)
                        .foregroundColor(Palette.color(.materialLongitudinal))
                } else {
                    PDFText("–", 10)
                        .foregroundColor(Palette.color(.pdfSecondary))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                PDFText(hasFlc ? "Three-Tap Measurement Process:" : "Two-Tap Measurement Process:", 10, bold: true)

                tapInstructionRow(color: Palette.color(.materialLongitudinal),
                                  title: "1. Longitudinal (fL) Tap",
                                  detail: "Hold plate at 22% from one end along the length, near one long edge (not at the width node). Tap center.")
                tapInstructionRow(color: Palette.color(.materialCross),
                                  title: "2. Cross-grain (fC) Tap",
                                  detail: "Rotate 90°. Hold plate at 22% from one end along the width, near one short edge (not at the length node). Tap center.")
                if hasFlc {
                    tapInstructionRow(color: Palette.color(.materialFlc),
                                      title: "3. Diagonal (fLC) Tap",
                                      detail: "Hold plate at the midpoint of one long edge. Tap near the opposite corner (~22% from both the end and the side). Measures shear stiffness.")
                }
                PDFText("The strongest peak from each tap is auto-selected.", 9, italic: true)
                    .foregroundColor(Palette.color(.pdfSecondary))
            }
            Spacer().frame(height: 14)
        } else if data.measurementType == .brace {
            VStack(alignment: .leading, spacing: 6) {
                sectionDivider
                Spacer().frame(height: 6)
                PDFText("Single-Tap Measurement (fL only):", 10, bold: true)

                tapInstructionRow(color: Palette.color(.materialLongitudinal),
                                  title: "1. Longitudinal (fL) Tap",
                                  detail: "Hold brace at 22% from one end along the length. Tap center.")
                PDFText("The strongest peak is auto-selected.", 9, italic: true)
                    .foregroundColor(Palette.color(.pdfSecondary))
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
                // Beside the dot: the content, less the dot and the gap.
                PDFText(title, 10, bold: true, wrapWidth: contentWidth - 7 - 6)
                PDFText(detail, 9, wrapWidth: contentWidth - 7 - 6)
                    .foregroundColor(Palette.color(.pdfSecondary))
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
            PDFText("Analysis Results", 13, bold: true)

            HStack(alignment: .top, spacing: 16) {
                // Ring-out time
                if let decay = data.decayTime {
                    analysisBox(
                        title: "Ring-Out Time",
                        value: "\(FieldPrecision.string(decay, FieldPrecision.decayTimeS)) s",
                        subtitle: "Time to decay 15 dB",
                        detail: decay.decayQuality(for: data.guitarType),
                        detailSubtitle: "Sustain quality",
                        detailColor: decay.decayQualityColor(for: data.guitarType)
                    )
                }

                // Tap tone ratio
                if let ratio = data.tapToneRatio {
                    analysisBox(
                        title: "Tap Tone Ratio",
                        value: "\(FieldPrecision.string(ratio, FieldPrecision.decayRatio)) : 1",
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
                PDFText(title, 10, bold: true)
                    .foregroundColor(Palette.color(.pdfSecondary))
                PDFText(value, 18, bold: true)
                if let subtitle {
                    PDFText(subtitle, 9)
                        .foregroundColor(Palette.color(.pdfSecondary))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                PDFText(detail, 10)
                    .foregroundColor(detailColor)
                if let detailSubtitle {
                    PDFText(detailSubtitle, 9)
                        .foregroundColor(Palette.color(.pdfSecondary))
                }
                if let hint {
                    PDFText(hint, 9, italic: true)
                        .foregroundColor(Palette.color(.pdfSecondary))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.color(.pdfBox))
        .cornerRadius(6)
    }

    // MARK: Plate Analysis

    private func plateSection(_ props: PlateProperties) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PDFText("Plate Properties", 13, bold: true)

            // (fL / fC / fLC are inputs, shown in the Detected Peaks table — not repeated here.)

            HStack(alignment: .top, spacing: 0) {
                // Left column
                VStack(alignment: .leading, spacing: 6) {
                    platePropRow("Speed of Sound (L)",
                                   "\(FieldPrecision.string(props.speedOfSoundLong, FieldPrecision.speedOfSoundMS)) m/s")
                    platePropRow("Speed of Sound (C)",
                                   "\(FieldPrecision.string(props.speedOfSoundCross, FieldPrecision.speedOfSoundMS)) m/s")
                    platePropRow("Young's Modulus (L)",
                                   "\(FieldPrecision.string(props.youngsModulusLongGPa, FieldPrecision.youngsModulusGPa)) GPa")
                    platePropRow("Young's Modulus (C)",
                                   "\(FieldPrecision.string(props.youngsModulusCrossGPa, FieldPrecision.youngsModulusGPa)) GPa")
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
                                   FieldPrecision.string(props.radiationRatioLong, FieldPrecision.radiationRatio))
                    platePropRow("Radiation Ratio (C)",
                                   FieldPrecision.string(props.radiationRatioCross, FieldPrecision.radiationRatio))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // GLC shear modulus (if the Diagonal fLC tap was performed)
            if let glc = props.goreShearModulus {
                platePropRow("GLC (Shear Modulus)",
                               "\(FieldPrecision.string(glc / 1.0e9, FieldPrecision.shearModulusGPa)) GPa")
            } else {
                PDFText("GLC assumed 0 — fLC tap not performed", 10, italic: true)
                    .foregroundColor(Palette.color(.pdfSecondary))
            }

            // Cross/Long ratio, Long/Cross ratio
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    platePropRow("Cross/Long Ratio",
                                   FieldPrecision.string(props.crossLongRatio, FieldPrecision.crossLongRatio))
                    PDFText("typical: 0.04–0.08", 9, italic: true)
                        .foregroundColor(Palette.color(.pdfSecondary))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    platePropRow("Long/Cross Ratio",
                                   FieldPrecision.string(props.longCrossRatio, FieldPrecision.longCrossRatio))
                    PDFText("typical: 12–25", 9, italic: true)
                        .foregroundColor(Palette.color(.pdfSecondary))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Overall Quality — prominent row
            HStack {
                PDFText("Overall Quality:", 10, bold: true)
                    .foregroundColor(Palette.color(.pdfSecondary))
                PDFText(props.overallQuality.rawValue, 13, bold: true)
                    .foregroundColor(Palette.color(props.overallQuality))
                Spacer()
            }
            .padding(8)
            .background(Palette.color(.pdfBox))
            .cornerRadius(4)
        }
    }

    private func braceSection(_ props: BraceProperties) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PDFText("Brace Properties", 13, bold: true)

            // (fL is an input, shown in the Detected Peaks table — not repeated here.)

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    platePropRow("Speed of Sound",
                                   "\(FieldPrecision.string(props.speedOfSoundLong, FieldPrecision.speedOfSoundMS)) m/s")
                    platePropRow("Young's Modulus (E)",
                                   "\(FieldPrecision.string(props.youngsModulusLongGPa, FieldPrecision.youngsModulusGPa)) GPa")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    specificModulusRow("Specific Modulus",
                                      value: props.specificModulusLong,
                                      quality: props.spruceQuality)
                    platePropRow("Radiation Ratio",
                                   FieldPrecision.string(props.radiationRatioLong, FieldPrecision.radiationRatio))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Overall Quality — prominent row
            HStack {
                PDFText("Overall Quality:", 10, bold: true)
                    .foregroundColor(Palette.color(.pdfSecondary))
                PDFText(props.spruceQuality.rawValue, 13, bold: true)
                    .foregroundColor(Palette.color(props.spruceQuality))
                Spacer()
            }
            .padding(8)
            .background(Palette.color(.pdfBox))
            .cornerRadius(4)
        }
    }

    /// Renders a compact row of sample input dimensions.
    private func dimensionsSubsection(dims: MaterialDimensions) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PDFText("Sample Dimensions", 10, bold: true)
                .foregroundColor(Palette.color(.pdfSecondary))
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
                platePropRow("Density", "\(FieldPrecision.string(dims.densityGPerCm3, FieldPrecision.densityGPerCm3)) g/cm³")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(6)
        .background(Palette.color(.pdfBox))
        .cornerRadius(4)
    }

    /// Renders the plate Gore body inputs — finished-guitar body dimensions (a, b) and panel
    /// stiffness (f_vs). Mirrors the Results panel's Body Dimensions section; feeds only the Gore target.
    private func plateBodyDimensionsPDFSection(_ props: PlateProperties) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PDFText("Body Dimensions", 10, bold: true)
                .foregroundColor(Palette.color(.pdfSecondary))

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
        .background(Palette.color(.pdfBox))
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
                PDFText("Gore Target Thickness", 10, bold: true)
                    .foregroundColor(Palette.color(.pdfSecondary))

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    PDFText("\(FieldPrecision.string(hd, FieldPrecision.goreThicknessMM)) mm", 16, bold: true)
                        .foregroundColor(Palette.color(.pdfAccent))
                    Spacer()
                }
            }
            .padding(6)
            .background(Palette.color(.pdfGoreBox))
            .cornerRadius(4)
        }
    }

    private func platePropRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            PDFText(label + ":", 10)
                .foregroundColor(Palette.color(.pdfSecondary))
            PDFText(value, 10, bold: true)
        }
    }

    private func specificModulusRow(_ label: String, value: Float, quality: WoodQuality) -> some View {
        HStack(spacing: 6) {
            PDFText(label + ":", 10)
                .foregroundColor(Palette.color(.pdfSecondary))
            PDFText(FieldPrecision.string(value, FieldPrecision.specificModulus), 10, bold: true)
                .foregroundColor(Palette.color(quality))
            PDFText("(\(quality.rawValue))", 9)
                .foregroundColor(Palette.color(quality))
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 16)
            Rectangle()
                .fill(Palette.color(.pdfDivider))
                .frame(height: 1)
            Spacer().frame(height: 8)
            HStack {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
                PDFText("Generated by GuitarTap Swift \(version) (\(build))", 9)
                    .foregroundColor(Palette.color(.pdfSecondary))
                Spacer()
                PDFText(DateDisplay.string(Date()), 9)
                    .foregroundColor(Palette.color(.pdfSecondary))
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
        let avgRenderer = ImageRenderer(content: PDFReportContentView(data: averaged).environment(\.colorScheme, .light))
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
        let cmpRenderer = ImageRenderer(content: ComparisonPDFReportContentView(data: comparison).environment(\.colorScheme, .light))
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
        // Printed on white: the light appearance, whatever the screen's.
        let renderer = ImageRenderer(content: contentView.environment(\.colorScheme, .light))

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
        // Text with no colour of its own is the report's text colour, not the system's black.
        .foregroundStyle(Palette.color(.pdfText))
        .padding(margin)
        .frame(width: pageWidth)
        .background(Palette.color(.backgroundPanel))
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                PDFText("GuitarTap", 22, bold: true)
                    .foregroundColor(Palette.color(.pdfAccent))
                PDFText("Comparison Report", 13)
                    .foregroundColor(Palette.color(.pdfSecondary))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                PDFText(DateDisplay.string(data.timestamp), 11)
                    .foregroundColor(Palette.color(.pdfSecondary))
            }
        }
        .padding(.bottom, 8)
    }

    private var accentBar: some View {
        Rectangle()
            .fill(Palette.color(.pdfAccent))
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
            PDFText(label + ":", 11, bold: true)
                .foregroundColor(Palette.color(.pdfSecondary))
                .frame(width: 100, alignment: .leading)
            PDFText(value, 11, wrapWidth: contentWidth - 100 - 6)
                .foregroundColor(Palette.color(.pdfText))
        }
    }

    // MARK: Spectrum Image

    @ViewBuilder
    private func spectrumSection(imageData: Data) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PDFText("Frequency Spectrum", 12, bold: true)
                .foregroundColor(Palette.color(.pdfSecondary))

            reportImage(from: imageData)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: contentWidth)
                .background(Palette.color(.pdfChartMatte))
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
            .fill(Palette.color(.pdfDivider))
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
            PDFText("Peak Mode Comparison", 13, bold: true)

            // Table header
            HStack(spacing: 0) {
                PDFText("Spectrum", 10, bold: true)
                    .foregroundColor(Palette.color(.pdfSecondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                ForEach(modeColumns, id: \.label) { col in
                    PDFText(col.label, 10, bold: true)
                        .foregroundColor(Palette.color(.pdfSecondary))
                        .frame(width: 90, alignment: .trailing)
                        .padding(.trailing, 6)
                        .padding(.vertical, 4)
                }
            }
            .background(Palette.color(.pdfPill))
            .cornerRadius(4)

            // Data rows
            ForEach(Array(data.modeFrequencies.enumerated()), id: \.offset) { _, row in
                // Top-aligned: a long name wraps rather than being cut, and the dot and the values
                // stay level with its first line.
                HStack(alignment: .top, spacing: 0) {
                    // Coloured dot + label
                    HStack(alignment: .top, spacing: 5) {
                        Circle()
                            .fill(row.color)
                            .frame(width: 8, height: 8)
                            .padding(.top, 1)
                        // The Spectrum column: the content, less the three value columns, the padding and the dot.
                        PDFText(row.label, 10, wrapWidth: contentWidth - 3 * (90 + 6) - 2 * 6 - (8 + 5))
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)

                    ForEach(modeColumns, id: \.label) { col in
                        let freq = row[keyPath: col.keyPath]
                        // A user-overridden value is shown italic with a " *" suffix — the SAME
                        // convention page 1's peak table uses for an overridden mode label — so it is
                        // not read as the averaged spectrum's auto-detected peak.
                        let isOverride = row.overrideModes.contains(col.mode)
                        PDFText((freq.map { "\(FieldPrecision.string($0, FieldPrecision.peakFrequencyHz)) Hz" } ?? "—") + (isOverride ? " *" : ""), 10, italic: isOverride)
                            .foregroundColor(Palette.color(freq != nil ? .pdfText : .pdfSecondary))
                            .frame(width: 90, alignment: .trailing)
                            .padding(.trailing, 6)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    // MARK: Footer

    private var footerSection: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 16)
            Rectangle()
                .fill(Palette.color(.pdfDivider))
                .frame(height: 1)
            Spacer().frame(height: 8)
            HStack {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
                PDFText("Generated by GuitarTap Swift \(version) (\(build))", 9)
                    .foregroundColor(Palette.color(.pdfSecondary))
                Spacer()
                PDFText(DateDisplay.string(Date()), 9)
                    .foregroundColor(Palette.color(.pdfSecondary))
            }
        }
    }
}

// MARK: - A Saved Measurement's Report

extension PDFReportGenerator {
    /// The PDF report for a saved measurement and its file basename: a multi-tap measurement's two pages
    /// (the averaged result, then the per-tap comparison), a comparison's report, or the single report.
    /// What the measurement list and detail export.
    @MainActor
    /// - Throws: ``ExportRenderError`` when a chart could not be drawn — the report is not written without it.
    static func report(for measurement: TapToneMeasurement) throws -> (data: Data, basename: String)? {
        if measurement.tapEntries?.isEmpty == false {
            let averaged = PDFReportData.from(measurement: measurement,
                                              spectrumImageData: try renderSpectrumImageForMeasurement(measurement))
            guard let comparison = try multiTapComparisonData(for: measurement),
                  let data = generateMultiTapReport(averaged: averaged, comparison: comparison) else { return nil }
            return (data, averaged.baseFilename)
        }
        if measurement.isComparison {
            guard let comparison = try comparisonData(for: measurement),
                  let data = generateComparison(data: comparison) else { return nil }
            // A comparison report is just a report: "report" default, not "measurement".
            return (data, ExportFilename.stem(name: measurement.measurementName, timestamp: measurement.timestamp,
                                              unnamed: "report"))
        }
        let single = PDFReportData.from(measurement: measurement,
                                        spectrumImageData: try renderSpectrumImageForMeasurement(measurement))
        guard let data = generate(data: single) else { return nil }
        return (data, single.baseFilename)
    }

    /// A multi-tap measurement's per-tap comparison page: one row per tap (each tap's own modes) and the
    /// averaged row (the definitive, override-aware modes).
    @MainActor
    static func multiTapComparisonData(for measurement: TapToneMeasurement) throws -> ComparisonPDFReportData? {
        let cmpEntries = measurement.multiTapComparisonEntries
        guard !cmpEntries.isEmpty else { return nil }

        let avgInfo = measurement.definitiveModeInfo()
        let modeFrequencies = cmpEntries.enumerated().map { index, entry -> (label: String, color: Color, air: Float?, top: Float?, back: Float?, overrideModes: Set<GuitarMode>) in
            let color = Palette.comparisonColor(index: index, label: entry.label)
            if entry.label == "Averaged" {
                return (entry.label, color, avgInfo[.air]?.frequency, avgInfo[.top]?.frequency,
                        avgInfo[.back]?.frequency, Set(avgInfo.filter { $0.value.isOverride }.keys))
            }
            let modePeaks = TapToneAnalyzer.resolvedModePeaks(peaks: entry.peaks, guitarType: entry.guitarType)
            return (entry.label, color, modePeaks[.air]?.frequency, modePeaks[.top]?.frequency,
                    modePeaks[.back]?.frequency, [])
        }

        return ComparisonPDFReportData(
            timestamp: measurement.timestamp,
            comparisonLabel: measurement.measurementName,
            notes: measurement.notes,
            spectrumImageData: try renderSpectrumImageForMultiTap(measurement),
            entries: cmpEntries,
            modeFrequencies: modeFrequencies
        )
    }

    /// A saved comparison's report: one row per compared measurement, from its stored definitive modes.
    @MainActor
    static func comparisonData(for measurement: TapToneMeasurement) throws -> ComparisonPDFReportData? {
        guard let entries = measurement.comparisonEntries else { return nil }
        let modeFrequencies = entries.enumerated().map { index, entry -> (label: String, color: Color, air: Float?, top: Float?, back: Float?, overrideModes: Set<GuitarMode>) in
            let color = Palette.comparisonColor(index: index, label: entry.label)
            return (entry.label, color, entry.modeFrequency(.air), entry.modeFrequency(.top),
                    entry.modeFrequency(.back), [])
        }
        return ComparisonPDFReportData(
            timestamp: measurement.timestamp,
            comparisonLabel: measurement.measurementName,
            notes: measurement.notes,
            spectrumImageData: try renderSpectrumImageForComparison(measurement),
            entries: entries,
            modeFrequencies: modeFrequencies
        )
    }
}
