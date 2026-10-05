//
//  ChartStyle.swift
//  GuitarTap
//
// @parity view/chart-style tests=test/chart-style
//
// How the spectrum chart draws its lines and points: widths, dashes, opacities and point sizes. Unlike the
// palette's colours these do not change with the colour scheme; they are pinned here so every edition draws the
// chart the same way. The screen and the exported image each have their own set.

import CoreGraphics

enum ChartStyle {
    struct Lines: Equatable {
        /// The live / frozen spectrum.
        let spectrumWidth: CGFloat
        /// Comparison, multi-tap and plate/brace phase curves.
        let overlayWidth: CGFloat
        /// Grid lines, one per axis tick (no minor lines).
        let gridWidth: CGFloat
        /// Mode boundaries, drawn in the mode's colour at `modeBoundaryOpacity`.
        let modeBoundaryWidth: CGFloat
        let modeBoundaryDash: [CGFloat]
        let modeBoundaryOpacity: Double
        /// The Peak Min line, drawn in `chart.peakMin` at `peakMinOpacity`.
        let peakMinWidth: CGFloat
        let peakMinDash: [CGFloat]
        let peakMinOpacity: Double
        /// The crosshair.
        let crosshairWidth: CGFloat
        let crosshairDash: [CGFloat]
        /// The line from a peak label to its peak, in the peak's colour at `leaderOpacity`.
        let leaderWidth: CGFloat
        let leaderDash: [CGFloat]
        let leaderOpacity: Double
        /// A peak label's border.
        let labelBorderWidth: CGFloat
        /// A peak's dot, and the highlighted peak's star, as areas (pt²).
        let dotArea: CGFloat
        let highlightedDotArea: CGFloat
        /// The magnitude axis's tick spacing (dB), or `nil` to choose it from the visible range.
        let magnitudeStride: Double?
    }

    /// The chart on screen.
    static let screen = Lines(
        spectrumWidth: 1, overlayWidth: 1.5, gridWidth: 1,
        modeBoundaryWidth: 1.5, modeBoundaryDash: [5, 5], modeBoundaryOpacity: 0.3,
        peakMinWidth: 1.5, peakMinDash: [8, 3], peakMinOpacity: 0.7,
        crosshairWidth: 1, crosshairDash: [4, 3],
        leaderWidth: 1.5, leaderDash: [4, 3], leaderOpacity: 0.4,
        labelBorderWidth: 1.5,
        dotArea: 40, highlightedDotArea: 120,
        magnitudeStride: nil
    )

    /// The exported spectrum image (PNG, and the image in the PDF report).
    static let export = Lines(
        spectrumWidth: 2, overlayWidth: 2, gridWidth: 1,
        modeBoundaryWidth: 2, modeBoundaryDash: [8, 8], modeBoundaryOpacity: 0.3,
        peakMinWidth: 1.5, peakMinDash: [8, 3], peakMinOpacity: 0.7,
        crosshairWidth: 1, crosshairDash: [4, 3],
        leaderWidth: 2, leaderDash: [5, 4], leaderOpacity: 0.5,
        labelBorderWidth: 1.5,
        dotArea: 200, highlightedDotArea: 200,
        magnitudeStride: 20
    )
}
