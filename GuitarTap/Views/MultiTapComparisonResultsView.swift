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
// @parity view/multi-tap-results

import SwiftUI

struct MultiTapComparisonResultsView: View {

    /// Individual tap entries from the most recent (or loaded) multi-tap sequence.
    let tapEntries: [TapEntry]

    /// The definitive Air/Top/Back for the Averaged row, each flagged if it is a user override.
    ///
    /// This is `analyzer.definitiveModeInfo()` — the same definitive rule the main panel and the
    /// ratio use, so the Averaged row agrees with them. It is NOT the per-tap classification: a tap's
    /// spectrum is separate from the averaged one and its peaks carry different UUIDs, so an override
    /// made on the averaged spectrum has no peak to attach to in a tap. Per-tap rows therefore show
    /// each tap's own auto-detected modes; only the Averaged row reflects the override, and an
    /// overridden value is tagged so it is not read as the averaged spectrum's auto peak.
    let averagedModes: [GuitarMode: (frequency: Float, isOverride: Bool)]

    /// Guitar type active for mode classification.
    let guitarType: GuitarType?


    /// Columns shown in the table (Air, Top, Back).
    private let columns: [GuitarMode] = [.air, .top, .back]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()

            // Per-tap rows — each tap's OWN auto-classification (its own spectrum, its own peaks).
            ForEach(Array(tapEntries.enumerated()), id: \.offset) { index, entry in
                let color = Palette.series(index)
                let modeFreqs = entry.resolvedModePeaks(guitarType: guitarType)
                    .mapValues { $0.frequency }
                dataRow(
                    color: color,
                    label: "Tap \(entry.tapIndex)",
                    modeFreqs: modeFreqs,
                    overrideModes: [],
                    bold: false
                )
                Divider()
                    .padding(.leading, 8)
            }

            // Averaged row — the DEFINITIVE Air/Top/Back (override-aware), tagged where overridden.
            let avgColor = Palette.seriesAverage
            dataRow(
                color: avgColor,
                label: "Averaged",
                modeFreqs: averagedModes.mapValues { $0.frequency },
                overrideModes: Set(averagedModes.filter { $0.value.isOverride }.keys),
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
        .foregroundColor(Palette.color(.textSecondary))
    }

    private func dataRow(
        color: Color,
        label: String,
        modeFreqs: [GuitarMode: Float],
        overrideModes: Set<GuitarMode>,
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
                // A user-overridden value is shown italic with a " *" suffix — the same convention
                // the PDF peak table uses — so it is not read as an auto-detected peak.
                let isOverride = overrideModes.contains(mode)
                Text(frequencyText(modeFreqs[mode]) + (isOverride ? " *" : ""))
                    .fontWeight(bold ? .semibold : .regular)
                    .italic(isOverride)
                    .foregroundColor(Palette.color(modeFreqs[mode] != nil ? .textPrimary : .textSecondary))
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
        return "\(FieldPrecision.string(f, FieldPrecision.peakFrequencyHz)) Hz"
    }
}
