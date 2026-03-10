//
//  SpectrumView+ChartContent.swift
//  GuitarTap
//
//  Chart content builders and mode/peak color helpers for SpectrumView.
//

import SwiftUI
import Charts

extension SpectrumView {

    // MARK: - Chart Content Builders

    /// Spectrum line chart content
    @ChartContentBuilder
    var spectrumLineContent: some ChartContent {
        ForEach(chartData) { dataPoint in
            // Clamp the magnitude to the currently displayed min and max DB values
            let clampedMagnitude = max(minDB, min(maxDB, dataPoint.magnitude))

            // Line mark shows the precise spectrum shape
            LineMark(
                x: .value("Frequency", dataPoint.frequency),
                y: .value("Magnitude", clampedMagnitude)
            )
            .foregroundStyle(.red)
            .lineStyle(StrokeStyle(lineWidth: 1))
        }
    }

    /// Mode boundary markers chart content (guitar mode only)
    @ChartContentBuilder
    var modeBoundaryContent: some ChartContent {
        // Only show guitar mode boundaries when in guitar measurement mode
        if showModeBoundaries && measurementType.isGuitar {
            ForEach(visibleModeBoundaries, id: \.frequency) { boundary in
                RuleMark(x: .value("Boundary", boundary.frequency))
                    .foregroundStyle(modeColor(for: boundary.mode).opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    .annotation(position: .top, alignment: .center) {
                        // Only show mode name at start of range (lower boundary)
                        if isStartOfModeRange(boundary.frequency, for: boundary.mode) {
                            Text(modeAbbreviation(for: boundary.mode))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(modeColor(for: boundary.mode))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(modeColor(for: boundary.mode).opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
            }
        }
    }

    /// Peak annotations chart content
    @ChartContentBuilder
    var peakAnnotationContent: some ChartContent {
        ForEach(visiblePeaks) { peak in
            // Peak marker - color depends on measurement type
            PointMark(
                x: .value("Frequency", peak.frequency),
                y: .value("Magnitude", peak.magnitude)
            )
            .foregroundStyle(peakColor(for: peak))
            .symbolSize(100)

            // Static annotation (for positioning reference only)
            PointMark(
                x: .value("Frequency", peak.frequency),
                y: .value("Magnitude", peak.magnitude)
            )
            .foregroundStyle(.clear)
            .annotation(position: .top, alignment: .center, spacing: 4) {
                // Non-interactive placeholder
                Color.clear
                    .frame(width: 80, height: 60)
                    .id("placeholder-\(peak.id)")
            }
        }
    }

    /// Per-phase spectrum overlay chart content (plate/brace measurements)
    @ChartContentBuilder
    var materialSpectraContent: some ChartContent {
        ForEach(Array(materialSpectra.enumerated()), id: \.offset) { seriesIndex, series in
            let dataPoints: [SpectrumDataPoint] = zip(series.frequencies, series.magnitudes)
                .filter { $0.0 >= minFreq && $0.0 <= maxFreq }
                .map { SpectrumDataPoint(frequency: $0.0, magnitude: $0.1) }
            ForEach(dataPoints) { dataPoint in
                let clampedMagnitude = max(minDB, min(maxDB, dataPoint.magnitude))
                LineMark(
                    x: .value("Frequency", dataPoint.frequency),
                    y: .value("Magnitude", clampedMagnitude)
                )
                .foregroundStyle(by: .value("Series", series.label))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
    }

    /// Threshold lines chart content (for tap detection visualization)
    @ChartContentBuilder
    var thresholdLinesContent: some ChartContent {
        if let thresholds = thresholdLines {
            ForEach(Array(thresholds.enumerated()), id: \.offset) { index, threshold in
                // Only show threshold if it's within the visible dB range
                if threshold.value >= minDB && threshold.value <= maxDB {
                    RuleMark(y: .value("Threshold", threshold.value))
                        .foregroundStyle(threshold.color)
                        .lineStyle(StrokeStyle(lineWidth: threshold.lineWidth, dash: threshold.dash))
                        .annotation(
                            position: index == 1 ? .bottom : .top,
                            alignment: index == 0 ? .trailing : .leading
                        ) {
                            Text(threshold.label)
                                .font(.caption2)
                                .fontWeight(index == 0 ? .medium : .regular)
                                .foregroundColor(threshold.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.9))
                                .cornerRadius(4)
                        }
                }
            }
        }
    }

    // MARK: - Color & Label Helpers

    /// Returns the appropriate color for a peak based on measurement type and selection
    func peakColor(for peak: ResonantPeak) -> Color {
        if measurementType.isGuitar {
            // Guitar mode: color by guitar mode classification
            return modeColor(for: GuitarMode.classify(frequency: peak.frequency))
        } else {
            // Plate/brace mode: color by L/C selection
            if peak.id == selectedLongitudinalPeakID {
                return .blue      // Longitudinal = blue
            } else if peak.id == selectedCrossPeakID {
                return .orange    // Cross-grain = orange
            } else if peak.id == selectedFlcPeakID {
                return .purple    // FLC = purple
            } else {
                return .secondary // Unselected = gray
            }
        }
    }

    /// Returns the color associated with a guitar mode
    func modeColor(for mode: GuitarMode) -> Color {
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

    /// Returns abbreviated mode name for boundary labels
    func modeAbbreviation(for mode: GuitarMode) -> String {
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

    /// Determines if this boundary frequency is the start (lower bound) of a mode range
    func isStartOfModeRange(_ frequency: Float, for mode: GuitarMode) -> Bool {
        return abs(frequency - mode.idealRange.lowerBound) < 0.1
    }
}
