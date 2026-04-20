//
//  MeasurementRowView.swift
//  GuitarTap
//

/// # MeasurementRowView
///
/// A compact list-row cell for a single `TapToneMeasurement`.
///
/// Displays the tap location (or "Measurement" as a fallback), the timestamp
/// formatted as a time string, peak count, and optional tap-tone ratio and
/// decay time. A waveform indicator is shown when a spectrum snapshot is
/// available.
///
/// Used by `MeasurementsListView` inside a `ForEach` loop.
///
/// - SeeAlso: `MeasurementsListView`, `TapToneMeasurement`

import SwiftUI

struct MeasurementRowView: View {
    let measurement: TapToneMeasurement
    var isHovered: Bool = false
    
    // Break down complex expressions for better compilation
    private var peaksText: String {
        "\(measurement.peaks.count) peaks"
    }
    
    private var ratioText: String? {
        if let ratio = measurement.tapToneRatio {
            return "Ratio: \(String(format: "%.2f", ratio))"
        }
        return nil
    }
    
    private var decayText: String? {
        if let decay = measurement.decayTime {
            return "Decay: \(String(format: "%.2f", decay))s"
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
                Text(measurement.tapLocation ?? "Comparison")
                    .font(.headline)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.caption)
                        .foregroundColor(.blue)

                    Text(measurement.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    #if os(macOS)
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .opacity(isHovered ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                    #endif
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
                if let location = measurement.tapLocation {
                    Text(location)
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
                    
                    Text(measurement.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Disclosure chevron — standard affordance for a clickable detail row
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    #if os(macOS)
                    // Ellipsis hint — appears on hover to signal right-click context menu
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .opacity(isHovered ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                    #endif
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
