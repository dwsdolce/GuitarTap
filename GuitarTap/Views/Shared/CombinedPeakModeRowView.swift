//
//  CombinedPeakModeRowView.swift
//  GuitarTap
//
//  Created by David Smith on 2/9/26.
//
import SwiftUI

struct CombinedPeakModeRowView: View {
    let peak: ResonantPeak
    let mode: GuitarMode
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Mode icon and color
            VStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .foregroundColor(mode.color)
                    .font(.title3)
                    .frame(width: 30, height: 30)
                
                // Mode range indicator
                if mode != .unknown && mode != .upperModes {
                    let inRange = mode.idealRange.contains(peak.frequency)
                    Image(systemName: inRange ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(inRange ? .green : .orange)
                        .font(.caption2)
                }
            }
            
            // Peak and mode information
            VStack(alignment: .leading, spacing: 6) {
                // Mode name and frequency
                HStack {
                    Text(mode.rawValue)
                        .font(.headline)
                        .foregroundColor(mode.color)
                    
                    Spacer()
                    
                    Text("\(peak.frequency, specifier: "%.2f") Hz")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                // Peak details
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("Q:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(peak.quality, specifier: "%.1f")")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    HStack(spacing: 4) {
                        Text("BW:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(peak.bandwidth, specifier: "%.1f") Hz")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    // Magnitude with color coding
                    Text("\(peak.magnitude, specifier: "%.1f") dB")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(magnitudeColor(peak.magnitude))
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(mode.color.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func magnitudeColor(_ mag: Float) -> Color {
        if mag >= -40.0 {
            return .green
        } else if mag >= -60.0 {
            return .blue
        } else if mag >= -80.0 {
            return .orange
        } else {
            return .red
        }
    }
}
