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
    /// The live frame — the processing times and the peak — observed on its own: the analyzer no longer
    /// announces a frame.
    @ObservedObject private var frame: LiveFrame

    init(analyzer: RealtimeFFTAnalyzer) {
        self.analyzer = analyzer
        self.frame = analyzer.frame
    }
    
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

                    PaletteDivider()

                    MetricRow(
                        label: "Bin Count",
                        value: analyzer.frequencies.isEmpty ? "—" : analyzer.frequencies.count.formatted(),
                        subtitle: "FFT output bins (guitar mode only)"
                    )
                    
                    PaletteDivider()
                    
                    MetricRow(
                        label: "Sample Rate",
                        value: analyzer.actualSampleRate > 0
                            ? formattedAsWholeHertz(analyzer.actualSampleRate)
                            : "—",
                        subtitle: "Hardware capture rate"
                    )

                    PaletteDivider()

                    MetricRow(
                        label: "Bandwidth",
                        value: formattedAsWholeHertz(Double(analyzer.bandwidth)),
                        subtitle: "0 Hz to Nyquist"
                    )
                    
                    PaletteDivider()
                    
                    MetricRow(
                        label: "Sample Length",
                        value: String(format: "%.2f s", analyzer.sampleLengthSeconds),
                        subtitle: "Time window duration"
                    )
                    
                    PaletteDivider()
                    
                    MetricRow(
                        label: "Frame Rate",
                        value: analyzer.frameRate.formattedAsFrequency(),
                        subtitle: "FFT calculations/sec"
                    )
                }
                .padding(8)
            }
            .groupBoxStyle(.palette)
            
            // Performance Section
            GroupBox("Performance") {
                VStack(alignment: .leading, spacing: 8) {
                    MetricRow(
                        label: "Processing Time",
                        value: String(format: "%.3f ms", frame.processingTimeMs),
                        subtitle: "Last frame",
                        valueColor: processingTimeColor(frame.processingTimeMs)
                    )
                    
                    PaletteDivider()
                    
                    MetricRow(
                        label: "Average Processing",
                        value: String(format: "%.3f ms", frame.avgProcessingTimeMs),
                        subtitle: "30-frame average",
                        valueColor: processingTimeColor(frame.avgProcessingTimeMs)
                    )
                    
                    PaletteDivider()
                    
                    // CPU headroom calculation
                    let frameTimeMs = 1000.0 / analyzer.frameRate
                    let cpuUsage = (frame.avgProcessingTimeMs / frameTimeMs) * 100
                    
                    MetricRow(
                        label: "CPU Usage",
                        value: String(format: "%.1f%%", cpuUsage),
                        subtitle: "Of available frame time",
                        valueColor: cpuUsageColor(cpuUsage)
                    )
                }
                .padding(8)
            }
            .groupBoxStyle(.palette)
            
            // Peak Detection Section
            GroupBox("Peak Detection") {
                VStack(alignment: .leading, spacing: 8) {
                    MetricRow(
                        label: "Peak Frequency",
                        value: frame.peakFrequency.formattedAsFrequency(),
                        subtitle: "Dominant frequency"
                    )
                    
                    PaletteDivider()
                    
                    MetricRow(
                        label: "Peak Magnitude",
                        value: "\(FieldPrecision.string(frame.peakMagnitude, FieldPrecision.peakMagnitudeDB)) dB",
                        subtitle: "Signal strength"
                    )
                }
                .padding(8)
            }
            .groupBoxStyle(.palette)
            
            // Status indicator
            HStack {
                Circle()
                    .fill(Palette.color(analyzer.isRunning ? .statusRunning : .statusStopped))
                    .frame(width: 8, height: 8)
                
                Text(analyzer.isRunning ? "Analyzing" : "Stopped")
                    .font(.caption)
                    .foregroundColor(Palette.color(.textSecondary))
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
            return Palette.color(.metricGood)
        } else if ratio < 0.8 {
            return Palette.color(.metricFair)
        } else if ratio < 0.95 {
            return Palette.color(.metricHigh)
        } else {
            return Palette.color(.metricOverload)
        }
    }
    
    /// Returns a color indicating CPU usage level
    private func cpuUsageColor(_ usage: Float) -> Color {
        if usage < 50 {
            return Palette.color(.metricGood)
        } else if usage < 80 {
            return Palette.color(.metricFair)
        } else if usage < 95 {
            return Palette.color(.metricHigh)
        } else {
            return Palette.color(.metricOverload)
        }
    }
}

/// A reusable row component for displaying metric information
struct MetricRow: View {
    let label: String
    let value: String
    let subtitle: String
    var valueColor: Color = Palette.color(.textPrimary)
    
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(Palette.color(.textPrimary))
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Palette.color(.textSecondary))
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
