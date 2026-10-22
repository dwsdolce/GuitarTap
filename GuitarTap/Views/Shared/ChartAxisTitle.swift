// @parity view/spectrum-chart
//
//  ChartAxisTitle.swift
//  GuitarTap
//
// A spectrum chart's axis title — "Frequency (Hz)" under the chart, "FFT Magnitude (dB)" up its left side.
// Laid out beside the chart rather than given to it as .chartXAxisLabel / .chartYAxisLabel: the chart clips
// its plot area (so the spectrum is cut off at the chart's edges), and Swift Charts then draws no axis label.

import SwiftUI

struct ChartAxisTitle: View {
    let text: String
    let font: Font
    /// Up the left side, reading bottom to top.
    var vertical = false

    var body: some View {
        let title = Text(text)
            .font(font)
            .foregroundColor(Palette.color(.chartAxis))
            .fixedSize()
        if vertical {
            // Rotated in place: laid out as wide as the text is tall, centred on the chart's height.
            title
                .rotationEffect(.degrees(-90))
                .frame(width: 20)
                .frame(maxHeight: .infinity)
        } else {
            title
        }
    }
}
