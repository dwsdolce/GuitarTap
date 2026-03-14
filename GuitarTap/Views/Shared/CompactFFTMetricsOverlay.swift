//
//  CompactFFTMetricsOverlay.swift
//  GuitarTap
//

/// # CompactFFTMetricsOverlay
///
/// A compact, translucent overlay showing key FFT metrics.
///
/// This view can be overlaid on top of the spectrum chart or placed anywhere
/// to provide at-a-glance performance information without taking up much space.
/// It displays a green/gray status dot followed by frequency resolution, update
/// interval, sample rate, and dominant frequency.
///
/// ## Example Usage
/// ```swift
/// ZStack(alignment: .topTrailing) {
///     SpectrumView(...)
///
///     CompactFFTMetricsOverlay(analyzer: analyzer)
///         .padding(8)
/// }
/// ```
///
/// - SeeAlso: `FFTAnalysisMetricsView` for the full-detail metrics panel.

import SwiftUI

struct CompactFFTMetricsOverlay: View {
    @ObservedObject var analyzer: RealtimeFFTAnalyzer
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header with status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(analyzer.isRunning ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                
                Text("FFT Metrics")
                    .font(.caption)
                    .fontWeight(.bold)
            }
            
            Divider()
            
            // Key metrics in compact format
            MetricLine(
                icon: "waveform.path",
                label: "Res",
                value: formatFrequency(analyzer.frequencyResolution)
            )
            
            MetricLine(
                icon: "timer",
                label: "Time",
                value: String(format: "%.1f ms", analyzer.sampleLengthSeconds * 1000)
            )
            
            MetricLine(
                icon: "speedometer",
                label: "Rate",
                value: String(format: "%.1f Hz", analyzer.frameRate)
            )
            
            Divider()
            
            // Performance with color coding
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("CPU:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                let frameTimeMs = 1000.0 / analyzer.frameRate
                let cpuUsage = (analyzer.avgProcessingTimeMs / frameTimeMs) * 100
                
                Text(String(format: "%.1f%%", cpuUsage))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(cpuUsageColor(cpuUsage))
            }
            
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("Proc:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(String(format: "%.2f ms", analyzer.avgProcessingTimeMs))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .shadow(radius: 2)
    }
    
    // MARK: - Helper Functions
    
    private func formatFrequency(_ frequency: Float) -> String {
        if frequency >= 1000 {
            return String(format: "%.1f kHz", frequency / 1000)
        } else if frequency >= 1 {
            return String(format: "%.1f Hz", frequency)
        } else {
            return String(format: "%.2f Hz", frequency)
        }
    }
    
    private func cpuUsageColor(_ usage: Float) -> Color {
        if usage < 50 {
            return .green
        } else if usage < 80 {
            return .yellow
        } else if usage < 95 {
            return .orange
        } else {
            return .red
        }
    }
}

/// A single line in the compact metrics display
struct MetricLine: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text(label + ":")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Preview

#Preview("Compact Overlay - Running") {
    ZStack(alignment: .topTrailing) {
        // Simulated spectrum background
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 400, height: 300)
            .cornerRadius(10)
        
        CompactFFTMetricsOverlay(
            analyzer: {
                let analyzer = RealtimeFFTAnalyzer(fftSize: 8192, targetSampleRate: 48000)
                return analyzer
            }()
        )
        .padding(12)
    }
}

#Preview("Compact Overlay - Alternative Position") {
    ZStack(alignment: .bottomLeading) {
        // Simulated spectrum background
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.green.opacity(0.3), .blue.opacity(0.3)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 400, height: 300)
            .cornerRadius(10)
        
        CompactFFTMetricsOverlay(
            analyzer: RealtimeFFTAnalyzer(fftSize: 16384, targetSampleRate: 96000)
        )
        .padding(12)
    }
}
