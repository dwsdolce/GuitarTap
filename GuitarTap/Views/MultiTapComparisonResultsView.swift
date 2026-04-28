/// # MultiTapComparisonResultsView
///
/// A grid showing Air, Top, and Back resonance frequencies for each individual tap
/// in a completed multi-tap guitar sequence, plus a final "Averaged" row.
///
/// Displayed in the Analysis Results panel when `analyzer.showingMultiTapComparison` is true.
/// Layout mirrors `ComparisonResultsView`: colored dot + label | Air | Top | Back.
///
/// Rows:
/// - One per `TapEntry` (e.g. "Tap 1", "Tap 2", "Tap 3") using the comparison palette colors.
/// - A divider and a bold "Averaged" row drawn from the analyzer's current peaks.
///
//  MultiTapComparisonResultsView.swift
//  GuitarTap

import SwiftUI

struct MultiTapComparisonResultsView: View {

    /// Individual tap entries from the most recent (or loaded) multi-tap sequence.
    let tapEntries: [TapEntry]

    /// Current averaged peaks from the analyzer (used for the Averaged row).
    let averagedPeaks: [ResonantPeak]

    /// Guitar type active for mode classification.
    let guitarType: GuitarType?

    /// Colors drawn from the same fixed comparison palette used for saved-measurement comparisons.
    /// Must stay in sync with `TapToneAnalyzer.multiTapPalette` (private to that type).
    private let palette: [Color] = [.blue, .orange, .green, .purple, .teal]

    /// Columns shown in the table (Air, Top, Back).
    private let columns: [GuitarMode] = [.air, .top, .back]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()

            // Per-tap rows
            ForEach(Array(tapEntries.enumerated()), id: \.offset) { index, entry in
                let color = palette[index % palette.count]
                let selectedIDs = Set(entry.selectedPeakIDs)
                let selectedPeaks = entry.peaks.filter { selectedIDs.contains($0.id) }
                let modeFreqs = TapToneAnalyzer.resolvedModePeaks(
                    peaks: selectedPeaks,
                    guitarType: entry.snapshot.guitarType ?? guitarType
                )
                dataRow(
                    color: color,
                    label: "Tap \(entry.tapIndex)",
                    modeFreqs: modeFreqs,
                    bold: false
                )
                Divider()
                    .padding(.leading, 8)
            }

            // Averaged row — uses the same bold yellow as the chart overlay for visual consistency.
            let avgColor = TapToneAnalyzer.multiTapAvgColor
            let avgModeFreqs = TapToneAnalyzer.resolvedModePeaks(
                peaks: averagedPeaks,
                guitarType: guitarType
            )
            dataRow(
                color: avgColor,
                label: "Averaged",
                modeFreqs: avgModeFreqs,
                bold: true
            )
        }
        .font(.caption)
    }

    // MARK: - Private Views

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Tap")
                .fontWeight(.semibold)
                .frame(minWidth: 0, maxWidth: labelColumnWidth, alignment: .center)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            ForEach(columns, id: \.self) { mode in
                Text(mode.abbreviation)
                    .fontWeight(.semibold)
                    .frame(width: columnWidth, alignment: .center)
                    .padding(.trailing, 8)
                    .padding(.vertical, 6)
            }
        }
        .foregroundColor(.secondary)
    }

    private func dataRow(
        color: Color,
        label: String,
        modeFreqs: [GuitarMode: Float],
        bold: Bool
    ) -> some View {
        HStack(spacing: 0) {
            // Colored dot + label
            HStack(spacing: 5) {
                if bold {
                    // The averaged row uses a filled square instead of a dot to distinguish it.
                    Rectangle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Text(label)
                    .fontWeight(bold ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 0, maxWidth: labelColumnWidth, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            ForEach(columns, id: \.self) { mode in
                Text(frequencyText(modeFreqs[mode]))
                    .fontWeight(bold ? .semibold : .regular)
                    .foregroundColor(modeFreqs[mode] != nil ? .primary : .secondary)
                    .frame(width: columnWidth, alignment: .center)
                    .padding(.trailing, 8)
                    .padding(.vertical, 5)
            }
        }
    }

    // MARK: - Helpers

    private var labelColumnWidth: CGFloat { 110 }
    private var columnWidth: CGFloat { 72 }

    private func frequencyText(_ frequency: Float?) -> String {
        guard let f = frequency else { return "—" }
        return String(format: "%.1f Hz", f)
    }
}
