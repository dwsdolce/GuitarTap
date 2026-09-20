//
//  DisplayRange.swift
//  GuitarTap
//
//  The rule for widening the chart's frequency axis so a newly identified peak is visible.
//
// @parity presentation/display-range

import Foundation

/// How the displayed frequency range grows to reveal a peak that falls outside it.
///
/// A plate or brace identifies fL / fC / fFLC by scanning a wide band (brace: 100–1200 Hz), and the
/// display range is per-measurement-type and persisted — so the peak a measurement just produced
/// can easily land off the edge of the chart. When that happens the axis widens to show it.
///
/// Extracted from `TapToneAnalysisView.expandFreqRangeToInclude(_:)` on 2026-09-20 so the rule is
/// testable and portable. It had lived only in a SwiftUI View extension: untested, and absent from
/// Python and web entirely, which is how a user-visible behaviour came to exist in one edition only.
enum DisplayRange {

    /// Ten percent of the peak's frequency, so the peak is not flush against the axis edge.
    static let paddingFraction: Float = 0.10

    /// The lowest frequency the axis may show. Below 1 Hz the log-ish axis has nothing to draw.
    static let floorHz: Float = 1

    /// `(minFreq, maxFreq)` widened so `frequency` is inside it, or unchanged if it already was.
    ///
    /// Only ever widens — a peak near the middle of the range leaves it alone, and a range is never
    /// narrowed to fit, because that would hide peaks the user is already looking at.
    static func expanded(
        toInclude frequency: Float,
        min minFreq: Float,
        max maxFreq: Float
    ) -> (min: Float, max: Float) {
        let padding = frequency * paddingFraction
        var lo = minFreq
        var hi = maxFreq
        if frequency > hi { hi = frequency + padding }
        if frequency < lo { lo = Swift.max(floorHz, frequency - padding) }
        return (lo, hi)
    }
}
