//
//  TapAnalysisResultsView.swift
//  GuitarTap
//
//  Created by David Smith on 02/08/26.
//

import SwiftUI
import Charts

/// A view that displays tap tone analysis results in a dedicated panel.
///
/// This view shows:
/// - Detected peaks with frequency, magnitude, and quality factor
/// - Identified guitar modes (Helmholtz, cross-grain, long-grain, etc.)
/// - Tap tone ratio analysis
/// - Peak tracking history over time
///
/// ## Example Usage
/// ```swift
/// TapAnalysisResultsView(analyzer: tapToneAnalyzer)
/// ```
struct TapAnalysisResultsView: View {
    @ObservedObject var analyzer: TapToneAnalyzer
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                Text("Analysis Results")
                    .font(.headline)
                    .fontWeight(.bold)
                
                // Current peaks display
                currentPeaksView
                
                Divider()
                
                // Mode identification
                modeIdentificationView
                
                Divider()
                
                // Tap tone ratio
                tapToneRatioView
                
                Divider()
                
                // Peak history chart
                peakHistoryChart
                
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
    }
    
    // MARK: - Subviews
    
    private var currentPeaksView: some View {
        GroupBox("Detected Peaks") {
            if analyzer.currentPeaks.isEmpty {
                Text("No peaks detected")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(analyzer.currentPeaks.prefix(5)) { peak in
                        PeakRowView(peak: peak)
                    }
                }
            }
        }
    }
    
    private var modeIdentificationView: some View {
        GroupBox("Identified Modes") {
            if analyzer.identifiedModes.isEmpty {
                Text("No modes identified")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(analyzer.identifiedModes.prefix(8), id: \.peak.id) { item in
                        ModeRowView(peak: item.peak, mode: item.mode)
                    }
                }
            }
        }
    }
    
    private var tapToneRatioView: some View {
        GroupBox("Tap Tone Ratio") {
            if let ratio = analyzer.calculateTapToneRatio() {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(ratio, specifier: "%.2f") : 1")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Long-grain / Cross-grain")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text(ratioQuality(ratio))
                            .font(.headline)
                            .foregroundColor(ratioQualityColor(ratio))
                        
                        Text("Ideal: 1.9 - 2.1")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("Need both cross-grain and long-grain modes")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }
    
    private var peakHistoryChart: some View {
        GroupBox("Peak Tracking") {
            if analyzer.peakHistory.isEmpty {
                Text("No history available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart {
                    ForEach(Array(analyzer.peakHistory.enumerated()), id: \.offset) { index, peaks in
                        ForEach(peaks.prefix(5)) { peak in
                            LineMark(
                                x: .value("Time", index),
                                y: .value("Frequency", peak.frequency)
                            )
                            .foregroundStyle(by: .value("Mode", GuitarMode.classify(frequency: peak.frequency).rawValue))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                    }
                }
                .frame(height: 250)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    /// Evaluates the quality of a tap tone ratio
    private func ratioQuality(_ ratio: Float) -> String {
        switch ratio {
        case 1.9...2.1:
            return "Excellent"
        case 1.7...1.9, 2.1...2.3:
            return "Good"
        case 1.5...1.7, 2.3...2.5:
            return "Fair"
        default:
            return "Needs Adjustment"
        }
    }
    
    /// Returns a color indicating ratio quality
    private func ratioQualityColor(_ ratio: Float) -> Color {
        switch ratio {
        case 1.9...2.1:
            return .green
        case 1.7...1.9, 2.1...2.3:
            return .blue
        case 1.5...1.7, 2.3...2.5:
            return .orange
        default:
            return .red
        }
    }
}

// MARK: - Preview

#Preview {
    TapAnalysisResultsView(analyzer: TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer(fftSize: 8192, targetSampleRate: 48000)))
        .frame(width: 400)
}
