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
/// decay time. Attachment indicators (photo, waveform) are shown when a
/// chart image or spectrum snapshot is available.
///
/// Used by `MeasurementsListView` inside a `ForEach` loop.
///
/// - SeeAlso: `MeasurementsListView`, `TapToneMeasurement`

import SwiftUI

struct MeasurementRowView: View {
    let measurement: TapToneMeasurement
    
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
                    if measurement.chartImageFilename != nil || measurement.chartImageData != nil {
                        Image(systemName: "photo.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    if measurement.spectrumSnapshot != nil {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    Text(measurement.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
