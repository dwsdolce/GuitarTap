//
//  ChartLegend.swift
//  GuitarTap
//
// @parity view/spectrum-chart tests=test/chart-legend
//

import SwiftUI

/// The chart's legend for its overlaid curves — a comparison's measurements, a multi-tap measurement's taps, a
/// plate's or brace's phases: each curve's line and its label in the curve's colour, on the readout background.
/// It sits in the plot's upper-right corner, over everything in the plot, and wraps onto as many lines as it needs, each line
/// right-aligned; the plot keeps its size. The screen and the exported image draw the same legend, each in its own
/// sizes.
struct ChartLegend: View {
    let series: [(color: Color, label: String)]
    /// The labels' font: the screen's caption, or the exported image's size.
    var font: Font = .caption2
    /// The line drawn before each label.
    var swatch = CGSize(width: 16, height: 2)
    /// The space between entries on a line, and between lines.
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 4
    var padding = EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
    var cornerRadius: CGFloat = 6

    var body: some View {
        if !series.isEmpty {
            TrailingFlowLayout(spacing: spacing, lineSpacing: lineSpacing) {
                ForEach(Array(series.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(entry.color)
                            .frame(width: swatch.width, height: swatch.height)
                        Text(entry.label)
                            .font(font)
                            .foregroundColor(entry.color)
                            .lineLimit(1)
                    }
                    .fixedSize()
                }
            }
            .padding(padding)
            .background(Palette.color(.chartReadoutBackground), in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

extension ChartLegend {
    /// The legend over the chart, laid out in the plot's frame `plot`, its upper-right corner `inset` in from the
    /// plot's, so it wraps within the plot and never crosses its axes; drawn last in the chart's overlay, over the
    /// labels and the readout, and ignoring the pointer.
    func placed(in plot: CGRect, inset: CGFloat) -> some View {
        padding(inset)
            .frame(width: plot.width, height: plot.height, alignment: .topTrailing)
            .position(x: plot.midX, y: plot.midY)
            .allowsHitTesting(false)
    }
}

/// Lays its views out in lines as wide as it is offered, starting a new line when the next view does not fit, and
/// aligns each line to the trailing edge — the legend's entries, as the web's wrapping, right-aligned legend.
struct TrailingFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    /// The views' sizes in lines no wider than `width`; a view wider than `width` has a line of its own.
    func lines(_ sizes: [CGSize], width: CGFloat) -> [[Int]] {
        var lines: [[Int]] = []
        var current: [Int] = []
        var lineWidth: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let needed = current.isEmpty ? size.width : lineWidth + spacing + size.width
            if !current.isEmpty && needed > width {
                lines.append(current)
                current = [index]
                lineWidth = size.width
            } else {
                current.append(index)
                lineWidth = needed
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    private func lineSize(_ line: [Int], _ sizes: [CGSize]) -> CGSize {
        CGSize(width: line.map { sizes[$0].width }.reduce(0, +) + spacing * CGFloat(max(line.count - 1, 0)),
               height: line.map { sizes[$0].height }.max() ?? 0)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let lineSizes = lines(sizes, width: proposal.width ?? .infinity).map { lineSize($0, sizes) }
        return CGSize(width: lineSizes.map(\.width).max() ?? 0,
                      height: lineSizes.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lineSizes.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for line in lines(sizes, width: bounds.width) {
            let size = lineSize(line, sizes)
            var x = bounds.maxX - size.width
            for index in line {
                subviews[index].place(at: CGPoint(x: x, y: y + (size.height - sizes[index].height) / 2),
                                      proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += size.height + lineSpacing
        }
    }
}
