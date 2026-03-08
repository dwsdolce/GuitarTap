//
//  FFTAnalysisMetricsView.swift
//  GuitarTap
//
//  Created by David Smith on 01/03/26.
//

import SwiftUI

/// A view that displays detailed FFT analysis metrics and performance statistics.
///
/// This view shows:
/// - Frequency resolution and bandwidth
/// - Sample length and frame rate
/// - Real-time processing performance
/// - Peak frequency detection
///
/// ## Example Usage
/// ```swift
/// FFTAnalysisMetricsView(analyzer: analyzer)
/// ```
struct FFTAnalysisMetricsView: View {
    @ObservedObject var analyzer: RealtimeFFTAnalyzer
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("FFT Analysis Metrics")
                .font(.headline)
                .fontWeight(.bold)
            
            // Analysis Configuration Section
            GroupBox("Analysis Configuration") {
                VStack(alignment: .leading, spacing: 8) {
                    MetricRow(
                        label: "Frequency Resolution",
                        value: formatFrequency(analyzer.frequencyResolution),
                        subtitle: "Hz per bin"
                    )
                    
                    Divider()
                    
                    MetricRow(
                        label: "Sample Rate",
                        value: analyzer.actualSampleRate > 0
                            ? String(format: "%.0f Hz", analyzer.actualSampleRate)
                            : "—",
                        subtitle: "Hardware capture rate"
                    )

                    Divider()

                    MetricRow(
                        label: "Bandwidth",
                        value: formatFrequency(analyzer.bandwidth),
                        subtitle: "0 Hz to Nyquist"
                    )
                    
                    Divider()
                    
                    MetricRow(
                        label: "Sample Length",
                        value: String(format: "%.2f s", analyzer.sampleLengthSeconds),
                        subtitle: "Time window duration"
                    )
                    
                    Divider()
                    
                    MetricRow(
                        label: "Frame Rate",
                        value: String(format: "%.1f Hz", analyzer.frameRate),
                        subtitle: "FFT calculations/sec"
                    )
                }
                .padding(8)
            }
            
            // Performance Section
            GroupBox("Performance") {
                VStack(alignment: .leading, spacing: 8) {
                    MetricRow(
                        label: "Processing Time",
                        value: String(format: "%.3f ms", analyzer.processingTimeMs),
                        subtitle: "Last frame",
                        valueColor: processingTimeColor(analyzer.processingTimeMs)
                    )
                    
                    Divider()
                    
                    MetricRow(
                        label: "Average Processing",
                        value: String(format: "%.3f ms", analyzer.avgProcessingTimeMs),
                        subtitle: "30-frame average",
                        valueColor: processingTimeColor(analyzer.avgProcessingTimeMs)
                    )
                    
                    Divider()
                    
                    // CPU headroom calculation
                    let frameTimeMs = 1000.0 / analyzer.frameRate
                    let cpuUsage = (analyzer.avgProcessingTimeMs / frameTimeMs) * 100
                    
                    MetricRow(
                        label: "CPU Usage",
                        value: String(format: "%.1f%%", cpuUsage),
                        subtitle: "Of available frame time",
                        valueColor: cpuUsageColor(cpuUsage)
                    )
                }
                .padding(8)
            }
            
            // Peak Detection Section
            GroupBox("Peak Detection") {
                VStack(alignment: .leading, spacing: 8) {
                    MetricRow(
                        label: "Peak Frequency",
                        value: formatFrequency(analyzer.peakFrequency),
                        subtitle: "Dominant frequency"
                    )
                    
                    Divider()
                    
                    MetricRow(
                        label: "Peak Magnitude",
                        value: String(format: "%.1f dB", analyzer.peakMagnitude),
                        subtitle: "Signal strength"
                    )
                }
                .padding(8)
            }
            
            // Status indicator
            HStack {
                Circle()
                    .fill(analyzer.isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                Text(analyzer.isRunning ? "Analyzing" : "Stopped")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    // MARK: - Helper Functions
    
    /// Formats a frequency value with appropriate units (Hz or kHz)
    private func formatFrequency(_ frequency: Float) -> String {
        if frequency >= 1000 {
            return String(format: "%.2f kHz", frequency / 1000)
        } else {
            return String(format: "%.1f Hz", frequency)
        }
    }
    
    /// Returns a color indicating processing time health
    /// - Green: Fast processing (< 50% of frame time)
    /// - Yellow: Moderate (50-80% of frame time)
    /// - Orange: High (80-95% of frame time)
    /// - Red: Critical (> 95% of frame time)
    private func processingTimeColor(_ timeMs: Float) -> Color {
        let frameTimeMs = 1000.0 / analyzer.frameRate
        let ratio = timeMs / frameTimeMs
        
        if ratio < 0.5 {
            return .green
        } else if ratio < 0.8 {
            return .yellow
        } else if ratio < 0.95 {
            return .orange
        } else {
            return .red
        }
    }
    
    /// Returns a color indicating CPU usage level
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

/// A reusable row component for displaying metric information
struct MetricRow: View {
    let label: String
    let value: String
    let subtitle: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - Preview

#Preview {
    FFTAnalysisMetricsView(analyzer: RealtimeFFTAnalyzer(fftSize: 8192, targetSampleRate: 48000))
        .frame(width: 400)
}
