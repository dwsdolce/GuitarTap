//
//  ExportableSpectrumChart.swift
//  GuitarTap
//
//  A simplified, static spectrum chart designed for ImageRenderer export.
//

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
    let frequencies: [Float]
    let magnitudes: [Float]
    let minFreq: Float
    let maxFreq: Float
    let minDB: Float
    let maxDB: Float
    let isLogarithmic: Bool
    var peaks: [ResonantPeak]?
    var showModeBoundaries: Bool = true
    var annotationOffsets: [UUID: CGPoint] = [:]
    var showUnknownModes: Bool? = nil  // If nil, uses global setting

    // Material measurement mode support
    var measurementType: MeasurementType = .acoustic
    var selectedLongitudinalPeakID: UUID?
    var selectedCrossPeakID: UUID?
    var selectedFlcPeakID: UUID?

    // Per-peak user mode overrides (empty = all peaks use auto-classification)
    var modeOverrides: [UUID: UserAssignedMode] = [:]

    /// Per-phase spectra overlay for material/brace measurements
    var materialSpectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)] = []

    private var chartData: [SpectrumDataPoint] {
        zip(frequencies, magnitudes)
            .filter { $0.0 >= minFreq && $0.0 <= maxFreq }
            .map { SpectrumDataPoint(frequency: $0.0, magnitude: $0.1) }
    }

    private var visibleModeBoundaries: [(frequency: Float, mode: GuitarMode)] {
        // Don't show guitar mode boundaries when in material mode
        guard measurementType.isGuitar else { return [] }

        let allModes: [GuitarMode] = [.air, .top, .back, .dipole, .ringMode, .upperModes]
        var boundaries: [(Float, GuitarMode)] = []

        for mode in allModes {
            let range = mode.idealRange
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

        // In material mode, show all peaks (no guitar mode filtering)
        if !measurementType.isGuitar {
            return filtered
        }

        // Use explicit parameter if provided, otherwise fall back to global setting
        let shouldShowUnknown = showUnknownModes ?? TapDisplaySettings.showUnknownModes
        if shouldShowUnknown {
            return filtered
        } else {
            return filtered.filter { GuitarMode.classify(frequency: $0.frequency).normalized != .unknown }
        }
    }

    private var frequencyAxisValues: [Double] {
        if isLogarithmic {
            return AxisTickGenerator.generateTicks(min: Double(minFreq), max: Double(maxFreq), maxTicks: 8, scale: AxisScale.logarithmic())
        } else {
            return AxisTickGenerator.generateTicks(min: Double(minFreq), max: Double(maxFreq), maxTicks: 8, scale: AxisScale.linear)
        }
    }

    private func modeColor(for mode: GuitarMode) -> Color {
        switch mode.normalized {
        case .air: return .cyan
        case .top: return .green
        case .back: return .orange
        case .dipole: return .red
        case .ringMode: return .purple
        case .upperModes: return .gray
        case .unknown: return .secondary
        default: return .secondary
        }
    }

    /// Returns the appropriate color for a peak based on measurement type and selection
    private func peakColor(for peak: ResonantPeak) -> Color {
        if measurementType.isGuitar {
            return modeColor(for: GuitarMode.classify(frequency: peak.frequency))
        } else {
            // Material mode: color by L/C/FLC selection
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
                return GuitarMode.classify(frequency: peak.frequency).displayName
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

    private func modeAbbreviation(for mode: GuitarMode) -> String {
        switch mode.normalized {
        case .air: return "Air"
        case .top: return "Top"
        case .back: return "Back"
        case .dipole: return "DP"
        case .ringMode: return "Ring"
        case .upperModes: return "Upper"
        case .unknown: return "?"
        default: return "?"
        }
    }

    private func isStartOfModeRange(_ frequency: Float, for mode: GuitarMode) -> Bool {
        return abs(frequency - mode.idealRange.lowerBound) < 0.1
    }

    /// Build filtered chart data for a single material spectrum series
    private func seriesData(frequencies: [Float], magnitudes: [Float]) -> [SpectrumDataPoint] {
        zip(frequencies, magnitudes)
            .filter { $0.0 >= minFreq && $0.0 <= maxFreq }
            .map { SpectrumDataPoint(frequency: $0.0, magnitude: $0.1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("FFT Peaks")
                    .font(.system(size: 24, weight: .semibold))
                Spacer()
            }
            .padding(.bottom, 16)

            ZStack(alignment: .topLeading) {
                // The chart
                Chart {
                    // Per-phase spectra overlay (material/brace) or single spectrum (guitar)
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
                                .foregroundStyle(modeColor(for: boundary.mode).opacity(0.3))
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [8, 8]))
                                .annotation(position: .top, alignment: .center) {
                                    if isStartOfModeRange(boundary.frequency, for: boundary.mode) {
                                        Text(modeAbbreviation(for: boundary.mode))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(modeColor(for: boundary.mode))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(modeColor(for: boundary.mode).opacity(0.15))
                                            .cornerRadius(6)
                                    }
                                }
                        }
                    }

                    // Peak markers only (no inline annotations)
                    ForEach(visiblePeaks) { peak in
                        PointMark(
                            x: .value("Frequency", peak.frequency),
                            y: .value("Magnitude", peak.magnitude)
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
                                    let peakPosition = CGPoint(
                                        x: frame.minX + peakX,
                                        y: frame.minY + peakY
                                    )
                                    let offset = annotationOffsets[peak.id] ?? .zero
                                    let annotationX = peakPosition.x + offset.x
                                    let annotationY = peakPosition.y - 70 + offset.y

                                    ConnectionLineShape(
                                        from: CGPoint(x: annotationX, y: annotationY + 50),
                                        to: peakPosition
                                    )
                                    .stroke(peakColor(for: peak).opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                                }
                            }

                            // Annotations layer
                            ForEach(visiblePeaks) { peak in
                                if let peakX = proxy.position(forX: peak.frequency),
                                   let peakY = proxy.position(forY: Double(peak.magnitude)) {
                                    let peakPosition = CGPoint(
                                        x: frame.minX + peakX,
                                        y: frame.minY + peakY
                                    )
                                    let offset = annotationOffsets[peak.id] ?? .zero
                                    let annotationX = peakPosition.x + offset.x
                                    let annotationY = peakPosition.y - 70 + offset.y

                                    VStack(spacing: 6) {
                                        Text(peakModeLabel(for: peak))
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(peakColor(for: peak))

                                        // Only show pitch info for guitar mode
                                        if measurementType.isGuitar, let pitchNote = peak.pitchNote {
                                            HStack(spacing: 4) {
                                                Image(systemName: "music.note")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.purple)
                                                Text(pitchNote)
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundColor(.purple)
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
