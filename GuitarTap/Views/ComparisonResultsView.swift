/// # ComparisonResultsView
///
/// A grid showing Air, Top, and Back resonance frequencies for each spectrum
/// in an active comparison. Displayed in the Analysis Results panel when
/// `displayMode == .comparison`.
///
/// Rows = one per compared spectrum (up to 5), with the spectrum's chart colour
/// shown as a dot in the first column. Columns = Air, Top, Back.
/// A `—` is shown when no peak for that mode was found in the selected peaks.
///
//  ComparisonResultsView.swift
//  GuitarTap
// @parity view/comparison-results

import SwiftUI

struct ComparisonResultsView: View {

    /// The comparison spectra from `TapToneAnalyzer.comparisonSpectra`.
    let spectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String, peaks: [ResonantPeak], guitarType: GuitarType?)]

    /// Columns shown in the table (Air, Top, Back).
    private let columns: [GuitarMode] = [.air, .top, .back]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()
            ForEach(Array(spectra.enumerated()), id: \.offset) { index, entry in
                let modeFreqs = TapToneAnalyzer.resolvedModePeaks(
                    peaks: entry.peaks,
                    guitarType: entry.guitarType
                ).mapValues { $0.frequency }
                dataRow(entry: entry, modeFreqs: modeFreqs)
                if index < spectra.count - 1 {
                    Divider()
                        .padding(.leading, 8)
                }
            }
        }
        .font(.caption)
    }

    // MARK: - Private Views

    private var headerRow: some View {
        HStack(spacing: 0) {
            // Spectrum label column
            Text("Spectrum")
                .fontWeight(.semibold)
                .frame(minWidth: 0, maxWidth: 190, alignment: .center)
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
        entry: (magnitudes: [Float], frequencies: [Float], color: Color, label: String, peaks: [ResonantPeak], guitarType: GuitarType?),
        modeFreqs: [GuitarMode: Float]
    ) -> some View {
        HStack(spacing: 0) {
            // Coloured dot + label
            HStack(spacing: 5) {
                Circle()
                    .fill(entry.color)
                    .frame(width: 8, height: 8)
                Text(entry.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 0, maxWidth: 190, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            ForEach(columns, id: \.self) { mode in
                Text(frequencyText(modeFreqs[mode]))
                    .foregroundColor(modeFreqs[mode] != nil ? .primary : .secondary)
                    .frame(width: columnWidth, alignment: .center)
                    .padding(.trailing, 8)
                    .padding(.vertical, 5)
            }
        }
    }

    // MARK: - Helpers

    private var columnWidth: CGFloat { 72 }

    private func frequencyText(_ frequency: Float?) -> String {
        guard let f = frequency else { return "—" }
        return String(format: "%.1f Hz", f)
    }
}
