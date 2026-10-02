/// # SpectrumView+ChartContent
///
/// `@ChartContentBuilder` properties and color/label helpers for `SpectrumView`.
///
/// This extension segregates the declarative Swift Charts content builders from
/// the main `SpectrumView` body and its gesture/interaction logic.  Each
/// `@ChartContentBuilder` var produces a distinct visual layer that is composed
/// inside the `Chart { }` block.
///
/// ## Layers (rendered bottom to top)
///
/// 1. `spectrumLineContent` — primary red `LineMark` of the FFT spectrum.
/// 2. `modeBoundaryContent` — vertical `RuleMark` lines at guitar mode boundaries
///    (only when `showModeBoundaries` and `measurementType.isGuitar`).
/// 3. `peakAnnotationContent` — `PointMark` dots at each detected peak with
///    invisible placeholder annotations for label positioning.
/// 4. `materialSpectraContent` — coloured `LineMark` overlays for plate/brace
///    per-phase spectra (longitudinal, cross, FLC).
/// 5. `thresholdLinesContent` — horizontal `RuleMark` lines showing tap
///    detection thresholds.
///
/// - SeeAlso: `SpectrumView`, `SpectrumView+GestureHandlers`
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

    /// Primary spectrum curve: a red `LineMark` for each point in `chartData`. The line runs through
    /// the chart's edges and the plot area clips it, so it reaches every edge with its true shape.
    @ChartContentBuilder
    var spectrumLineContent: some ChartContent {
        ForEach(chartData) { dataPoint in
            // Line mark shows the precise spectrum shape
            LineMark(
                x: .value("Frequency", dataPoint.frequency),
                y: .value("Magnitude", dataPoint.magnitude)
            )
            .foregroundStyle(.red)
            .lineStyle(StrokeStyle(lineWidth: 1))
        }
    }

    /// Guitar mode boundary markers: vertical dashed `RuleMark` lines at mode
    /// frequency boundaries, with abbreviated mode labels at the start of each band.
    ///
    /// Only rendered when `showModeBoundaries` is `true` and the current
    /// `measurementType` is a guitar type.  Labels are shown only at the lower
    /// boundary of each mode range (determined by `isStartOfModeRange(_:for:)`).
    @ChartContentBuilder
    var modeBoundaryContent: some ChartContent {
        // Only show guitar mode boundaries when in guitar measurement mode
        if showModeBoundaries && measurementType.isGuitar {
            ForEach(visibleModeBoundaries, id: \.frequency) { boundary in
                RuleMark(x: .value("Boundary", boundary.frequency))
                    .foregroundStyle(boundary.mode.color.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    .annotation(
                        position: .top,
                        alignment: .center,
                        spacing: 4,
                        overflowResolution: .init(x: .fit, y: .fit(to: .plot))
                    ) {
                        // Only show mode name at start of range (lower boundary)
                        if isStartOfModeRange(boundary.frequency, for: boundary.mode) {
                            Text(boundary.mode.abbreviation)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(boundary.mode.color)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(boundary.mode.color.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
            }
        }
    }

    /// `PointMark` dots for every peak in the visible frequency range.
    ///
    /// All peaks always show a dot regardless of annotation visibility mode.
    /// The highlighted peak (``highlightedPeakID``) renders larger as a red `star.fill` (macOS only).
    /// A second invisible `PointMark` with a `Color.clear` annotation is placed at
    /// each *annotation-visible* peak position to serve as a size placeholder for the
    /// draggable overlay labels rendered in `PeakAnnotations`.
    @ChartContentBuilder
    var peakAnnotationContent: some ChartContent {
        // Layer 1: always-visible dots for every peak in range whose magnitude
        // falls within the visible dB window.  Peaks below minDB are omitted
        // entirely — clamping them to the bottom would crowd the axis line.
        ForEach(allPeaksInRange.filter { $0.magnitude >= minDB }) { peak in
            let clampedMag = min(maxDB, peak.magnitude)
            #if os(macOS)
            let isHighlighted = currentHighlightedPeakID == peak.id
            if isHighlighted {
                PointMark(
                    x: .value("Frequency", peak.frequency),
                    y: .value("Magnitude", clampedMag)
                )
                .foregroundStyle(Color.red)
                .symbol {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.red)
                }
                .symbolSize(120)
            } else {
                PointMark(
                    x: .value("Frequency", peak.frequency),
                    y: .value("Magnitude", clampedMag)
                )
                .foregroundStyle(peakColor(for: peak))
                .symbol(.circle)
                .symbolSize(40)
            }
            #else
            PointMark(
                x: .value("Frequency", peak.frequency),
                y: .value("Magnitude", clampedMag)
            )
            .foregroundStyle(peakColor(for: peak))
            .symbol(.circle)
            .symbolSize(40)
            #endif
        }

        // Layer 2: invisible placeholder annotations for draggable labels (annotation-visible peaks only)
        // Also filtered to only peaks within the visible dB range.
        ForEach(visiblePeaks.filter { $0.magnitude >= minDB }) { peak in
            let clampedMag = min(maxDB, peak.magnitude)
            PointMark(
                x: .value("Frequency", peak.frequency),
                y: .value("Magnitude", clampedMag)
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

    /// Coloured `LineMark` overlays for each phase in `materialSpectra`.
    ///
    /// Used during plate and brace measurements to show the longitudinal, cross,
    /// and FLC tap spectra side-by-side.  Each series is differentiated by the
    /// `foregroundStyle(by: .value("Series", label))` modifier so Swift Charts
    /// automatically builds a legend entry for each.
    @ChartContentBuilder
    var materialSpectraContent: some ChartContent {
        ForEach(Array(materialSpectra.enumerated()), id: \.offset) { seriesIndex, series in
            let count = min(series.frequencies.count, series.magnitudes.count)
            let dataPoints: [SpectrumDataPoint] = DisplayRange
                .drawnIndices(of: Array(series.frequencies.prefix(count)), min: minFreq, max: maxFreq)
                .map { SpectrumDataPoint(sourceEpoch: 0, frequency: series.frequencies[$0], magnitude: series.magnitudes[$0]) }
            ForEach(dataPoints) { dataPoint in
                LineMark(
                    x: .value("Frequency", dataPoint.frequency),
                    y: .value("Magnitude", dataPoint.magnitude)
                )
                .foregroundStyle(by: .value("Series", series.label))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
    }

    /// Horizontal `RuleMark` lines showing tap detection thresholds.
    ///
    /// Each threshold entry in `thresholdLines` specifies a dB value, label
    /// text, color, line width, and dash pattern.  Lines outside the visible
    /// dB range are omitted.  Labels alternate between `.top`/`.bottom` and
    /// `.trailing`/`.leading` alignment to reduce overlap between adjacent
    /// thresholds (e.g., tap level and noise floor).
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

    /// Context-aware mode classification for peaks, preferring the pre-computed map
    /// passed in via ``peakModes`` (derived from ``TapToneAnalyzer/identifiedModes``).
    ///
    /// Falls back to computing a local ``GuitarMode/classifyAll(_:guitarType:)`` on
    /// ``allPeaksInRange`` when ``peakModes`` is empty (e.g. in previews or comparison mode).
    var peakModeMap: [UUID: GuitarMode] {
        peakModes.isEmpty ? GuitarMode.classifyAll(allPeaksInRange) : peakModes
    }

    /// Returns the display color for a peak marker.
    ///
    /// In guitar mode, the color is determined by the context-aware ``peakModeMap``
    /// (e.g. `.cyan` for the air resonance).  In plate/brace mode, peaks are colored
    /// by their selected role: blue for longitudinal, orange for cross-grain, purple
    /// for FLC, and `.secondary` for unselected peaks.
    ///
    /// - Parameter peak: The detected resonant peak to color.
    /// - Returns: A `Color` reflecting the peak's mode or plate role.
    func peakColor(for peak: ResonantPeak) -> Color {
        if measurementType.isGuitar {
            // Guitar mode: context-aware classification avoids duplicate mode labels
            // in overlapping ranges (e.g. classical Top/Back overlap at 190–230 Hz).
            return (peakModeMap[peak.id] ?? .unknown).color
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

    /// Determines if this boundary frequency is the start (lower bound) of a mode range
    func isStartOfModeRange(_ frequency: Float, for mode: GuitarMode) -> Bool {
        return abs(frequency - mode.modeRange.lowerBound) < 0.1
    }
}
