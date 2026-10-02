//
//  FFTAnalysisMetricsView.swift
//  GuitarTap
//
// @parity view/analysis-metrics

/// # FFTAnalysisMetricsView
///
/// Full-detail FFT analysis metrics and performance diagnostics panel.
///
/// Presented in a sheet (iOS) or macOS sheet on demand from the Metrics
/// toolbar button in `TapToneAnalysisView`. Organized into three `GroupBox`
/// sections plus a running/stopped status indicator:
///
/// | Section | Metrics |
/// |---|---|
/// | Analysis Configuration | Frequency resolution (Hz/bin), bin count, sample rate (Hz), bandwidth (Hz), sample length (s), frame rate (Hz) |
/// | Performance | Processing time (ms), average processing (ms), CPU usage (%) |
/// | Peak Detection | Peak frequency (Hz), peak magnitude (dB) |
///
/// All values are read from `@ObservedObject var analyzer: RealtimeFFTAnalyzer`
/// and update live while the analyzer is running.
///
/// - SeeAlso: `RealtimeFFTAnalyzer`

import SwiftUI

struct FFTAnalysisMetricsView: View {
    @ObservedObject var analyzer: RealtimeFFTAnalyzer
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Analysis Configuration Section
            GroupBox("Analysis Configuration") {
                VStack(alignment: .leading, spacing: 8) {
                    MetricRow(
                        label: "Frequency Resolution",
                        value: analyzer.frequencyResolution.formattedAsFrequency(),
                        subtitle: "Hz per bin"
                    )

                    Divider()

                    MetricRow(
                        label: "Bin Count",
                        value: analyzer.frequencies.isEmpty ? "—" : analyzer.frequencies.count.formatted(),
                        subtitle: "FFT output bins (guitar mode only)"
                    )
                    
                    Divider()
                    
                    MetricRow(
                        label: "Sample Rate",
                        value: analyzer.actualSampleRate > 0
                            ? formattedAsWholeHertz(analyzer.actualSampleRate)
                            : "—",
                        subtitle: "Hardware capture rate"
                    )

                    Divider()

                    MetricRow(
                        label: "Bandwidth",
                        value: formattedAsWholeHertz(Double(analyzer.bandwidth)),
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
                        value: analyzer.frameRate.formattedAsFrequency(),
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
                        value: analyzer.peakFrequency.formattedAsFrequency(),
                        subtitle: "Dominant frequency"
                    )
                    
                    Divider()
                    
                    MetricRow(
                        label: "Peak Magnitude",
                        value: "\(FieldPrecision.string(analyzer.peakMagnitude, FieldPrecision.peakMagnitudeDB)) dB",
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
    FFTAnalysisMetricsView(analyzer: RealtimeFFTAnalyzer())
        .frame(width: 400)
}
