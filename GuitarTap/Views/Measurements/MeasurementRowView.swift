//
//  MeasurementRowView.swift
//  GuitarTap
//
// @parity view/measurements-list

/// # MeasurementRowView
///
/// A compact list-row cell for a single `TapToneMeasurement`.
///
/// Displays the measurementName (or "Measurement" as a fallback), the timestamp
/// formatted as an abbreviated date and short time, peak count, and optional
/// tap-tone ratio and decay time. A waveform indicator is shown when a
/// spectrum snapshot is available.
///
/// Used by `MeasurementsListView` inside a `ForEach` loop.
///
/// - SeeAlso: `MeasurementsListView`, `TapToneMeasurement`

import SwiftUI

struct MeasurementRowView<MenuItems: View>: View {
    let measurement: TapToneMeasurement
    var isHovered: Bool = false
    /// Per-row action items, shared with the list's right-click `.contextMenu` so the
    /// hover "⋯" button and right-click present the identical menu (same labels + icons).
    @ViewBuilder var menuItems: () -> MenuItems

    /// macOS hover "⋯" — now a functional Menu opening the same actions as right-click.
    @ViewBuilder private var ellipsisMenu: some View {
        #if os(macOS)
        Menu {
            menuItems()
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .opacity(isHovered ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .help("Actions")
        #endif
    }

    // Break down complex expressions for better compilation
    private var peaksText: String {
        "\(measurement.peaks.count) peaks"
    }
    
    private var ratioText: String? {
        if let ratio = measurement.tapToneRatio {
            return "Ratio: \(FieldPrecision.string(ratio, FieldPrecision.decayRatio))"
        }
        return nil
    }
    
    private var decayText: String? {
        if let decay = measurement.decayTime {
            return "Decay: \(FieldPrecision.string(decay, FieldPrecision.decayTimeS))s"
        }
        return nil
    }
    
    var body: some View {
        if measurement.isComparison {
            comparisonRowBody
        } else {
            measurementRowBody
        }
    }

    // MARK: - Comparison record layout

    private var comparisonRowBody: some View {
        let count = measurement.comparisonEntries?.count ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                // A nameless measurement is not a comparison — only fall back to "Comparison"
                // for an actual comparison record.
                Text(measurement.measurementName ?? (measurement.isComparison ? "Comparison" : "Measurement"))
                    .font(.headline)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.caption)
                        .foregroundColor(.blue)

                    Text(DateDisplay.string(measurement.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ellipsisMenu
                }
            }

            Text("\(count) spectra compared")
                .font(.caption)
                .foregroundColor(.secondary)

            if let notes = measurement.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Regular measurement layout

    private var measurementRowBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let measurementName = measurement.measurementName {
                    Text(measurementName)
                        .font(.headline)
                } else {
                    Text("Measurement")
                        .font(.headline)
                }
                
                Spacer()
                
                // Show indicators for attached data
                HStack(spacing: 6) {
                    if measurement.spectrumSnapshot != nil {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    Text(DateDisplay.string(measurement.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Disclosure chevron — standard affordance for a clickable detail row
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ellipsisMenu
                }
            }
            
            // Simplified metadata row
            HStack {
                Text(peaksText)
                
                if let ratio = ratioText {
                    Text("•")
                    Text(ratio)
                }
                
                if let decay = decayText {
                    Text("•")
                    Text(decay)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            if let notes = measurement.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
