//
//  ExportableSpectrumChart.swift
//  GuitarTap
//

/// # ExportableSpectrumChart
///
/// A stripped-down, static spectrum chart suitable for off-screen rendering
/// with `ImageRenderer`.
///
/// ## Why a Separate View?
///
/// `SpectrumView` uses AppKit `NSEvent` monitors, hover effects, and
/// gesture recognizers that prevent `ImageRenderer` from capturing it
/// reliably. `ExportableSpectrumChart` reproduces the same visual appearance
/// using only stateless SwiftUI Charts primitives so the renderer can
/// produce a pixel-accurate PNG without interactive side effects.
///
/// ## Supported Overlay Layers
///
/// 1. **Spectrum line** — primary (red) or per-phase colored series
/// 2. **Mode boundaries** — dashed vertical `RuleMark` lines in mode colors
/// 3. **Peak annotations** — symbols + labels with `ConnectionLineShape`
///    connection lines, positions offset by `annotationOffsets`
///
/// ## Peak Coloring
///
/// - Guitar mode: peaks colored by `GuitarMode` (air=cyan, top=green, etc.)
/// - Plate/brace mode: L=blue, C=orange, FLC=purple, unselected=secondary
///
/// ## Connection Lines
///
/// Because `Path` views don't render correctly inside a `ZStack` when using
/// `ImageRenderer`, connection lines are drawn with `ConnectionLineShape`
/// (a `Shape`-conforming type), which renders correctly in all contexts.
///
/// - SeeAlso: `SpectrumView`, `MeasurementFileExporter`

import SwiftUI
import Charts

// MARK: - Connection Line Shape for Export

/// A simple Shape that draws a line between two points.
/// Used in ExportableSpectrumChart where Path views don't render correctly in ZStack.
private struct ConnectionLineShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

// MARK: - Static Export Spectrum View

/// A simplified, static version of SpectrumView designed for ImageRenderer export.
/// This view removes all interactive elements (gestures, hover effects, context menus)
/// that can cause ImageRenderer to fail.
struct ExportableSpectrumChart: View {
    /// Raw frequency bins (Hz) from the FFT output.
    let frequencies: [Float]
    /// Magnitude values (dBFS) corresponding to each frequency bin.
    let magnitudes: [Float]
    /// Minimum frequency (Hz) of the visible chart range.
    let minFreq: Float
    /// Maximum frequency (Hz) of the visible chart range.
    let maxFreq: Float
    /// Minimum magnitude (dBFS) of the visible chart range.
    let minDB: Float
    /// Maximum magnitude (dBFS) of the visible chart range.
    let maxDB: Float
    /// When `true`, the frequency axis uses a logarithmic scale.
    let isLogarithmic: Bool
    /// Peaks to annotate. Pass `nil` to suppress all peak annotations.
    var peaks: [ResonantPeak]?
    /// Whether to draw guitar mode boundary lines.
    var showModeBoundaries: Bool = true
    /// Per-peak label positions in absolute data-space (x = Hz, y = dB).
    /// When `.zero` or absent, the default position (70pt above peak) is used.
    var annotationOffsets: [UUID: CGPoint] = [:]
    /// Override for `TapDisplaySettings.showUnknownModes`. Pass `nil` to use
    /// the global setting.
    var showUnknownModes: Bool? = nil

    // Plate/brace measurement mode support
    /// Measurement type determining color coding and boundary visibility.
    var measurementType: MeasurementType = .acoustic
    /// ID of the peak selected as the longitudinal (L) mode.
    var selectedLongitudinalPeakID: UUID?
    /// ID of the peak selected as the cross-grain (C) mode.
    var selectedCrossPeakID: UUID?
    /// ID of the peak selected as the FLC (diagonal) mode.
    var selectedFlcPeakID: UUID?

    /// Per-peak user-assigned mode overrides. An empty dictionary means all
    /// peaks use automatic `GuitarMode` classification.
    var modeOverrides: [UUID: UserAssignedMode] = [:]

    /// Pre-computed context-aware mode assignments, keyed by peak UUID.
    ///
    /// Pass `Dictionary(uniqueKeysWithValues: analyzer.identifiedModes.map { ($0.peak.id, $0.mode) })`
    /// so peaks in overlapping ranges (e.g. classical Top/Back) get distinct labels.
    /// When empty, the chart falls back to computing a local classification from ``visiblePeaks``.
    var peakModes: [UUID: GuitarMode] = [:]

    /// Per-phase spectra overlay for plate/brace measurements. Each element
    /// provides a labeled, colored spectrum series drawn alongside the primary
    /// curve.
    var materialSpectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)] = []

    private var chartData: [SpectrumDataPoint] {
        zip(frequencies, magnitudes)
            .filter { $0.0 >= minFreq && $0.0 <= maxFreq }
            .map { SpectrumDataPoint(sourceEpoch: 0, frequency: $0.0, magnitude: $0.1) }
    }

    private var visibleModeBoundaries: [(frequency: Float, mode: GuitarMode)] {
        // Don't show guitar mode boundaries when in plate/brace mode
        guard measurementType.isGuitar else { return [] }

        let allModes: [GuitarMode] = [.air, .top, .back, .dipole, .ringMode, .upperModes]
        var boundaries: [(Float, GuitarMode)] = []

        for mode in allModes {
            let range = mode.modeRange
            if range.lowerBound >= minFreq && range.lowerBound <= maxFreq {
                boundaries.append((range.lowerBound, mode))
            }
            if range.upperBound >= minFreq && range.upperBound <= maxFreq {
                boundaries.append((range.upperBound, mode))
            }
        }

        return boundaries
    }

    private var visiblePeaks: [ResonantPeak] {
        let filtered = peaks?.filter { $0.frequency >= minFreq && $0.frequency <= maxFreq } ?? []

        // In plate/brace mode, show all peaks (no guitar mode filtering)
        if !measurementType.isGuitar {
            return filtered
        }

        // Use explicit parameter if provided, otherwise fall back to global setting
        let shouldShowUnknown = showUnknownModes ?? TapDisplaySettings.showUnknownModes
        if shouldShowUnknown {
            return filtered
        } else {
            return filtered.filter { GuitarMode.isKnown(frequency: $0.frequency) }
        }
    }

    private var frequencyAxisValues: [Double] {
        let lo = Double(minFreq)
        let hi = Double(maxFreq)
        let scale: AxisScale = isLogarithmic ? AxisScale.logarithmic() : .linear
        return AxisTickGenerator.generateTicks(min: lo, max: hi, maxTicks: 8, scale: scale)
            .filter { $0 >= lo && $0 <= hi }
    }

    /// Context-aware mode map for all visible peaks, preferring the pre-computed map
    /// from ``peakModes`` (derived from ``TapToneAnalyzer/identifiedModes``).
    ///
    /// Falls back to computing a local classification from ``visiblePeaks`` when
    /// ``peakModes`` is empty (e.g. when called from the PDF generator without an analyzer).
    private var peakModeMap: [UUID: GuitarMode] {
        peakModes.isEmpty ? GuitarMode.classifyAll(visiblePeaks) : peakModes
    }

    /// Returns the appropriate color for a peak based on measurement type and selection.
    private func peakColor(for peak: ResonantPeak) -> Color {
        if measurementType.isGuitar {
            // Freeform user-defined label → teal.
            if case .assigned(let label) = modeOverrides[peak.id],
               GuitarMode.fromDisplayName(label) == nil {
                return GuitarMode.userDefinedColor
            }
            return (peakModeMap[peak.id] ?? .unknown).color
        } else {
            // Plate/brace mode: color by L/C/FLC selection
            if peak.id == selectedLongitudinalPeakID {
                return .blue
            } else if peak.id == selectedCrossPeakID {
                return .orange
            } else if peak.id == selectedFlcPeakID {
                return .purple
            } else {
                return .secondary
            }
        }
    }

    /// Returns the mode label for a peak, respecting user overrides for guitar measurements.
    private func peakModeLabel(for peak: ResonantPeak) -> String {
        if measurementType.isGuitar {
            switch modeOverrides[peak.id] ?? .auto {
            case .auto:
                return (peakModeMap[peak.id] ?? .unknown).displayName
            case .assigned(let label):
                return label
            }
        } else {
            if peak.id == selectedLongitudinalPeakID {
                return "Longitudinal"
            } else if peak.id == selectedCrossPeakID {
                return "Cross-grain"
            } else if peak.id == selectedFlcPeakID {
                return "FLC"
            } else {
                return "Peak"
            }
        }
    }

    /// Compute the annotation label center in chart-local pixels from a stored absolute
    /// data-space position, the chart frame, and the axis bounds.
    ///
    /// - Returns: The pixel coordinate for the annotation card center.
    ///   When ``annotationOffsets`` has no entry for the peak (or the stored value is `.zero`),
    ///   the default position (70 pt above the peak marker) is returned.
    private func annotationPosition(
        for peak: ResonantPeak,
        peakPosition: CGPoint,
        frame: CGRect
    ) -> CGPoint {
        let offset = annotationOffsets[peak.id] ?? .zero
        let freqRange = CGFloat(maxFreq - minFreq)
        let dbRange   = CGFloat(maxDB   - minDB)
        guard offset != .zero, freqRange > 0, dbRange > 0 else {
            return CGPoint(x: peakPosition.x, y: peakPosition.y - 70)
        }
        let ax = frame.minX + ((offset.x - CGFloat(minFreq)) / freqRange) * frame.width
        let ay = frame.minY + (1.0 - (offset.y - CGFloat(minDB)) / dbRange) * frame.height
        return CGPoint(x: ax, y: ay)
    }

    private func isStartOfModeRange(_ frequency: Float, for mode: GuitarMode) -> Bool {
        return abs(frequency - mode.modeRange.lowerBound) < 0.1
    }

    /// Build filtered chart data for a single plate/brace spectrum series
    private func seriesData(frequencies: [Float], magnitudes: [Float]) -> [SpectrumDataPoint] {
        zip(frequencies, magnitudes)
            .filter { $0.0 >= minFreq && $0.0 <= maxFreq }
            .map { SpectrumDataPoint(sourceEpoch: 0, frequency: $0.0, magnitude: $0.1) }
    }

    /// Title shown above the chart. Defaults to "FFT Peaks" to match the live view.
    var chartTitle: String = "FFT Peaks"

    var body: some View {
        VStack(spacing: 0) {
            Text(chartTitle)
                .font(.system(size: 24, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 16)

            ZStack(alignment: .topLeading) {
                // The chart
                Chart {
                    // Per-phase spectra overlay (plate/brace) or single spectrum (guitar)
                    if !materialSpectra.isEmpty {
                        ForEach(Array(materialSpectra.enumerated()), id: \.offset) { index, series in
                            let data = seriesData(frequencies: series.frequencies, magnitudes: series.magnitudes)
                            ForEach(data) { dataPoint in
                                let clamped = max(minDB, min(maxDB, dataPoint.magnitude))
                                LineMark(
                                    x: .value("Frequency", dataPoint.frequency),
                                    y: .value("Magnitude", clamped)
                                )
                                .foregroundStyle(by: .value("Series", series.label))
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            }
                        }
                    } else {
                        // Spectrum line
                        ForEach(chartData) { dataPoint in
                            let clampedMagnitude = max(minDB, min(maxDB, dataPoint.magnitude))
                            LineMark(
                                x: .value("Frequency", dataPoint.frequency),
                                y: .value("Magnitude", clampedMagnitude)
                            )
                            .foregroundStyle(.red)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }

                    // Mode boundaries
                    if showModeBoundaries {
                        ForEach(visibleModeBoundaries, id: \.frequency) { boundary in
                            RuleMark(x: .value("Boundary", boundary.frequency))
                                .foregroundStyle(boundary.mode.color.opacity(0.3))
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [8, 8]))
                                .annotation(
                                    position: .top,
                                    alignment: .center,
                                    spacing: 4,
                                    overflowResolution: .init(x: .fit, y: .fit(to: .plot))
                                ) {
                                    if isStartOfModeRange(boundary.frequency, for: boundary.mode) {
                                        Text(boundary.mode.abbreviation)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(boundary.mode.color)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(boundary.mode.color.opacity(0.15))
                                            .cornerRadius(6)
                                    }
                                }
                        }
                    }

                    // Peak markers only (no inline annotations)
                    // Peaks below minDB are hidden entirely — not clamped to the bottom.
                    ForEach(visiblePeaks.filter { $0.magnitude >= minDB }) { peak in
                        let clampedMag = min(maxDB, peak.magnitude)
                        PointMark(
                            x: .value("Frequency", peak.frequency),
                            y: .value("Magnitude", clampedMag)
                        )
                        .foregroundStyle(peakColor(for: peak))
                        .symbolSize(200)
                    }
                }
                .chartForegroundStyleScale(
                    domain: materialSpectra.map { $0.label },
                    range: materialSpectra.map { $0.color }
                )
                .chartLegend(.hidden)
                .chartPlotStyle { plotArea in
                    plotArea.border(Color.gray, width: 1)
                }
                .chartXScale(domain: Double(minFreq)...Double(maxFreq), type: isLogarithmic ? .log : .linear)
                .chartYScale(domain: Double(minDB)...Double(maxDB))
                .chartXAxis {
                    AxisMarks(values: frequencyAxisValues) { value in
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(AxisTickGenerator.formatTickLabel(doubleValue))
                                    .font(.system(size: 12))
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartXAxisLabel(alignment: .center) {
                    Text("Frequency (Hz)")
                        .font(.system(size: 16, weight: .medium))
                        .padding(8)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .stride(by: 20)) { _ in
                        AxisValueLabel()
                            .font(.system(size: 12))
                        AxisGridLine()
                    }
                }
                .chartYAxisLabel(position: .leading, alignment: .center) {
                    Text("FFT Magnitude (dB)")
                        .font(.system(size: 16, weight: .medium))
                        .rotationEffect(.degrees(180))
                        .padding(8)
                }
                .chartOverlay { proxy in
                    // Use ChartProxy for accurate positioning
                    GeometryReader { geometry in
                        if let plotFrame = proxy.plotFrame {
                            let frame = geometry[plotFrame]

                            // Connection lines layer
                            ForEach(visiblePeaks) { peak in
                                if let peakX = proxy.position(forX: peak.frequency),
                                   let peakY = proxy.position(forY: Double(peak.magnitude)) {
                                    let peakPosition = CGPoint(x: frame.minX + peakX, y: frame.minY + peakY)
                                    let annPos = annotationPosition(for: peak, peakPosition: peakPosition, frame: frame)
                                    ConnectionLineShape(
                                        from: CGPoint(x: annPos.x, y: annPos.y + 50),
                                        to: peakPosition
                                    )
                                    .stroke(peakColor(for: peak).opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                                }
                            }

                            // Annotations layer
                            ForEach(visiblePeaks) { peak in
                                if let peakX = proxy.position(forX: peak.frequency),
                                   let peakY = proxy.position(forY: Double(peak.magnitude)) {
                                    let peakPosition = CGPoint(x: frame.minX + peakX, y: frame.minY + peakY)
                                    let annPos = annotationPosition(for: peak, peakPosition: peakPosition, frame: frame)
                                    let annotationX = annPos.x
                                    let annotationY = annPos.y

                                    VStack(spacing: 6) {
                                        Text(peakModeLabel(for: peak))
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(peakColor(for: peak))

                                        // Only show pitch info for guitar mode
                                        if measurementType.isGuitar, let pitchNote = peak.pitchNote {
                                            let sign = (peak.pitchCents ?? 0) >= 0 ? "+" : ""
                                            let centsStr = peak.pitchCents.map { "\(sign)\(Int($0.rounded())) ¢" } ?? ""
                                            HStack(spacing: 4) {
                                                Image(systemName: "music.note")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.purple)
                                                Text(pitchNote)
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundColor(.purple)
                                                if !centsStr.isEmpty {
                                                    Text(centsStr)
                                                        .font(.system(size: 14))
                                                        .foregroundColor(.purple.opacity(0.8))
                                                }
                                            }
                                        }

                                        Text(peak.frequency.formattedAsFrequency())
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.primary)

                                        Text("\(peak.magnitude, specifier: "%.1f") dB")
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(10)
                                    .background(Color.white.opacity(0.95))
                                    .cornerRadius(10)
                                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                                    .position(x: annotationX, y: annotationY)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Shared Export View Builder

/// Builds the full spectrum export composite view — chart, header, peak summary, and
/// mode legend — from explicit data parameters.
///
/// Used by both the live export path (`TapToneAnalysisView+Export`) and the
/// measurement export path (`renderSpectrumImageForMeasurement`) so that "Export Spectrum Image"
/// produces an identical image regardless of whether it is triggered from the live
/// analysis view or from a saved measurement.
///
/// - Parameters:
///   - frequencies: FFT frequency bins (Hz).
///   - magnitudes: FFT magnitude values (dBFS).
///   - minFreq: Minimum displayed frequency (Hz).
///   - maxFreq: Maximum displayed frequency (Hz).
///   - minDB: Minimum displayed magnitude (dBFS).
///   - maxDB: Maximum displayed magnitude (dBFS).
///   - peaks: Detected resonant peaks to annotate.
///   - annotationOffsets: Per-peak label drag offsets, keyed by peak UUID.
///   - showUnknownModes: Whether to show peaks classified as unknown guitar modes.
///   - measurementType: Guitar, plate, or brace — controls colour coding and boundary visibility.
///   - selectedLongitudinalPeakID: UUID of the selected longitudinal (L) peak (plate/brace).
///   - selectedCrossPeakID: UUID of the selected cross-grain (C) peak (plate).
///   - selectedFlcPeakID: UUID of the selected FLC peak (plate, optional).
///   - modeOverrides: Per-peak user-assigned mode label overrides.
///   - materialSpectra: Per-phase spectrum series for plate/brace overlays.
///   - dateLabel: Date/time string shown in the header (e.g. formatted measurement timestamp).
/// - Returns: A self-contained `View` suitable for off-screen rendering with `ImageRenderer`.
@MainActor
func makeExportableSpectrumView(
    frequencies: [Float],
    magnitudes: [Float],
    minFreq: Float,
    maxFreq: Float,
    minDB: Float,
    maxDB: Float,
    peaks: [ResonantPeak],
    annotationOffsets: [UUID: CGPoint] = [:],
    showUnknownModes: Bool? = nil,
    measurementType: MeasurementType = .acoustic,
    selectedLongitudinalPeakID: UUID? = nil,
    selectedCrossPeakID: UUID? = nil,
    selectedFlcPeakID: UUID? = nil,
    modeOverrides: [UUID: UserAssignedMode] = [:],
    peakModes: [UUID: GuitarMode] = [:],
    materialSpectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)] = [],
    dateLabel: String,
    chartTitle: String = "FFT Peaks",
    softwareVersion: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }(),
    platform: String = {
        #if os(macOS)
        return "macOS"
        #elseif os(iOS)
        return "iOS/iPadOS"
        #else
        return "Apple"
        #endif
    }()
) -> some View {
    let formatFreq: (Float) -> String = { freq in
        freq >= 1000 ? String(format: "%.1fk Hz", freq / 1000) : String(format: "%.0f Hz", freq)
    }

    return VStack(alignment: .leading, spacing: 16) {
        // Header
        VStack(alignment: .leading, spacing: 8) {
            Text("Guitar Tap Tone Analysis - Frequency Response")
                .font(.title)
                .fontWeight(.bold)

            HStack {
                Text("Date: \(dateLabel)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Range: \(formatFreq(minFreq)) - \(formatFreq(maxFreq))")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("•")
                    .foregroundColor(.secondary)

                Text("\(Int(minDB)) to \(Int(maxDB)) dB")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            HStack(spacing: 16) {
                // Measurement type
                HStack(spacing: 4) {
                    Text("Type:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(measurementType.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Text("•")
                    .foregroundColor(.secondary)

                // Platform
                HStack(spacing: 4) {
                    Text("Platform:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(platform)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                if !softwareVersion.isEmpty {
                    Text("•")
                        .foregroundColor(.secondary)

                    // Software version
                    HStack(spacing: 4) {
                        Text("GuitarTap")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("v\(softwareVersion)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }

                Spacer()
            }

            if !materialSpectra.isEmpty {
                Text("Comparing \(materialSpectra.count) measurements")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if !peaks.isEmpty {
                Text("Detected Peaks: \(peaks.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()

        // Chart
        ExportableSpectrumChart(
            frequencies: frequencies,
            magnitudes: magnitudes,
            minFreq: minFreq,
            maxFreq: maxFreq,
            minDB: minDB,
            maxDB: maxDB,
            isLogarithmic: false,
            peaks: peaks,
            showModeBoundaries: true,
            annotationOffsets: annotationOffsets,
            showUnknownModes: showUnknownModes,
            measurementType: measurementType,
            selectedLongitudinalPeakID: selectedLongitudinalPeakID,
            selectedCrossPeakID: selectedCrossPeakID,
            selectedFlcPeakID: selectedFlcPeakID,
            modeOverrides: modeOverrides,
            peakModes: peakModes,
            materialSpectra: materialSpectra,
            chartTitle: chartTitle
        )
        .frame(width: 1400, height: 800)
        .padding()

        // Peak Summary
        if !peaks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Detected Peaks Summary")
                    .font(.headline)
                    .padding(.horizontal)

                HStack(spacing: 20) {
                    let summaryModeMap = peakModes.isEmpty ? GuitarMode.classifyAll(peaks) : peakModes
                    ForEach(peaks.prefix(8).sorted(by: { $0.frequency < $1.frequency })) { peak in
                        let mode = summaryModeMap[peak.id] ?? .unknown
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

        // Legend: comparison curve labels or guitar mode key
        if !materialSpectra.isEmpty {
            HStack(spacing: 20) {
                Text("Measurements:")
                    .font(.caption)
                    .fontWeight(.semibold)

                ForEach(Array(materialSpectra.enumerated()), id: \.offset) { _, series in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(series.color)
                            .frame(width: 24, height: 4)
                        Text(series.label)
                            .font(.caption)
                    }
                }
            }
            .padding()
        } else {
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
    }
    .background(Color.white)
    .padding()
}
// MARK: - Render Spectrum Image for Measurement

/// Renders the spectrum chart for a saved measurement to PNG data using `ImageRenderer`.
///
/// Builds the full composite export view (header + chart + peak summary + legend) from
/// the measurement's stored snapshot data, producing output identical to the spectrum
/// image exported from the live analysis view.
///
/// Used by both `exportSpectrumMeasurement` (direct PNG export) and
/// `PDFReportGenerator` (PDF embedding), so both outputs are always consistent.
///
/// - Parameter measurement: The saved measurement to render a chart for.
/// - Returns: PNG-encoded chart image, or `nil` if no snapshot is available.
@MainActor
func renderSpectrumImageForMeasurement(_ measurement: TapToneMeasurement) -> Data? {
    let primarySnapshot = measurement.spectrumSnapshot ?? measurement.longitudinalSnapshot
    guard let snap = primarySnapshot else { return nil }

    var materialSpectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)] = []
    if let longSnap = measurement.longitudinalSnapshot {
        materialSpectra.append((longSnap.magnitudes, longSnap.frequencies, .blue, "Longitudinal"))
    }
    if let crossSnap = measurement.crossSnapshot {
        materialSpectra.append((crossSnap.magnitudes, crossSnap.frequencies, .orange, "Cross-grain"))
    }
    if let flcSnap = measurement.flcSnapshot {
        materialSpectra.append((flcSnap.magnitudes, flcSnap.frequencies, .purple, "FLC"))
    }

    let measurementType = snap.measurementType ?? .classical

    // Mirror TapToneAnalyzer.visiblePeaks: filter by annotationVisibilityMode and selectedPeakIDs
    let allPeaks = measurement.peaks
    let visibilityMode = measurement.annotationVisibilityMode ?? .all
    let selectedIDs = Set(measurement.selectedPeakIDs ?? allPeaks.map { $0.id })
    let visiblePeaks: [ResonantPeak]
    switch visibilityMode {
    case .all:      visiblePeaks = allPeaks
    case .selected: visiblePeaks = allPeaks.filter { selectedIDs.contains($0.id) }
    case .none:     visiblePeaks = []
    }

    let compositeView = makeExportableSpectrumView(
        frequencies: snap.frequencies,
        magnitudes: snap.magnitudes,
        minFreq: snap.minFreq,
        maxFreq: snap.maxFreq,
        minDB: snap.minDB,
        maxDB: snap.maxDB,
        peaks: visiblePeaks,
        annotationOffsets: measurement.peakAnnotationOffsets ?? [:],
        showUnknownModes: snap.showUnknownModes,
        measurementType: measurementType,
        selectedLongitudinalPeakID: measurement.selectedLongitudinalPeakID,
        selectedCrossPeakID: measurement.selectedCrossPeakID,
        selectedFlcPeakID: measurement.selectedFlcPeakID,
        modeOverrides: measurement.peakModeOverrides ?? [:],
        peakModes: GuitarMode.classifyAll(visiblePeaks),
        materialSpectra: materialSpectra,
        dateLabel: measurement.timestamp.formatted(),
        chartTitle: "FFT Peaks — \(measurement.measurementName ?? "New")"
    )

    let renderer = ImageRenderer(content: compositeView)
    renderer.scale = 2.0

    #if os(iOS)
    guard let uiImage = renderer.uiImage,
          let pngData = uiImage.pngData() else { return nil }
    return pngData
    #elseif os(macOS)
    guard let nsImage = renderer.nsImage,
          let tiffData = nsImage.tiffRepresentation,
          let bitmapImage = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapImage.representation(using: .png, properties: [:]) else { return nil }
    return pngData
    #endif
}

/// Renders the per-tap comparison overlay chart for a saved multi-tap `TapToneMeasurement`
/// to a PNG-encoded `Data` value.
///
/// Mirrors `renderSpectrumImageForComparison(_:)` but sources data from
/// `measurement.tapEntries` instead of `measurement.comparisonEntries`, assigning
/// colors from the same fixed palette used by the live multi-tap comparison UI.
///
/// - Parameter measurement: A saved multi-tap guitar record (must have non-nil `tapEntries`).
/// - Returns: PNG-encoded chart image, or `nil` if `tapEntries` is absent or empty.
@MainActor
func renderSpectrumImageForMultiTap(_ measurement: TapToneMeasurement) -> Data? {
    guard let entries = measurement.tapEntries, !entries.isEmpty else { return nil }

    // Same palette used by the live UI (TapToneAnalyzer.multiTapPalette) and
    // MultiTapComparisonResultsView.palette.
    let palette: [Color] = [.blue, .orange, .green, .purple, .teal]
    let avgColor = TapToneAnalyzer.multiTapAvgColor

    var spectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)] =
        entries.enumerated().map { index, entry in
            (magnitudes: entry.snapshot.magnitudes,
             frequencies: entry.snapshot.frequencies,
             color: palette[index % palette.count],
             label: "Tap \(entry.tapIndex)")
        }

    // Append the averaged spectrum (stored in spectrumSnapshot) as the final overlay.
    if let avgSnap = measurement.spectrumSnapshot {
        spectra.append((magnitudes: avgSnap.magnitudes,
                        frequencies: avgSnap.frequencies,
                        color: avgColor,
                        label: "Averaged"))
    }

    let snaps = entries.map(\.snapshot)
    let compositeView = makeExportableSpectrumView(
        frequencies: [],
        magnitudes: [],
        minFreq: snaps.map(\.minFreq).min() ?? 50,
        maxFreq: snaps.map(\.maxFreq).max() ?? 1000,
        minDB:   snaps.map(\.minDB).min()   ?? -100,
        maxDB:   snaps.map(\.maxDB).max()   ?? 0,
        peaks: [],
        measurementType: .classical,
        materialSpectra: spectra,
        dateLabel: measurement.timestamp.formatted(),
        chartTitle: "Tap Comparison — \(measurement.measurementName ?? "Multi-Tap")"
    )

    let renderer = ImageRenderer(content: compositeView)
    renderer.scale = 2.0

    #if os(iOS)
    guard let uiImage = renderer.uiImage,
          let pngData = uiImage.pngData() else { return nil }
    return pngData
    #elseif os(macOS)
    guard let nsImage = renderer.nsImage,
          let tiffData = nsImage.tiffRepresentation,
          let bitmapImage = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapImage.representation(using: .png, properties: [:]) else { return nil }
    return pngData
    #endif
}

/// Renders the comparison overlay chart for a saved comparison `TapToneMeasurement`
/// to a PNG-encoded `Data` value.
///
/// This is the comparison-side parallel to `renderSpectrumImageForMeasurement`:
/// both are free functions in `ExportableSpectrumChart.swift` and both are called
/// from `MeasurementsListView` to supply the spectrum image for spectrum-export and
/// PDF-report actions.
///
/// - Parameter measurement: A saved comparison record (must have non-nil `comparisonEntries`).
/// - Returns: PNG-encoded chart image, or `nil` if `comparisonEntries` is absent.
@MainActor
func renderSpectrumImageForComparison(_ measurement: TapToneMeasurement) -> Data? {
    guard let entries = measurement.comparisonEntries else { return nil }

    let comparisonSpectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)] = entries.map { entry in
        let c = entry.colorComponents
        let color = Color(red: c[0], green: c[1], blue: c[2], opacity: c.count >= 4 ? c[3] : 1.0)
        return (magnitudes: entry.snapshot.magnitudes, frequencies: entry.snapshot.frequencies,
                color: color, label: entry.label)
    }
    let snaps = entries.map(\.snapshot)
    let compositeView = makeExportableSpectrumView(
        frequencies: [],
        magnitudes: [],
        minFreq: snaps.map(\.minFreq).min() ?? 50,
        maxFreq: snaps.map(\.maxFreq).max() ?? 1000,
        minDB:   snaps.map(\.minDB).min()   ?? -100,
        maxDB:   snaps.map(\.maxDB).max()   ?? 0,
        peaks: [],
        measurementType: .classical,
        materialSpectra: comparisonSpectra,
        dateLabel: measurement.timestamp.formatted(),
        chartTitle: "Comparison — \(measurement.measurementName ?? "Comparison")"
    )

    let renderer = ImageRenderer(content: compositeView)
    renderer.scale = 2.0

    #if os(iOS)
    guard let uiImage = renderer.uiImage,
          let pngData = uiImage.pngData() else { return nil }
    return pngData
    #elseif os(macOS)
    guard let nsImage = renderer.nsImage,
          let tiffData = nsImage.tiffRepresentation,
          let bitmapImage = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapImage.representation(using: .png, properties: [:]) else { return nil }
    return pngData
    #endif
}
