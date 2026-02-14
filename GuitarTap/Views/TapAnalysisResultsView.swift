//
//  TapAnalysisResultsView.swift
//  GuitarTap
//
//  Created by David Smith on 2/9/26.
//
import SwiftUI
import Charts

/// A view that displays tap tone analysis results in a dedicated panel.
struct TapAnalysisResultsView: View {
    @ObservedObject var analyzer: TapToneAnalyzer
    @ObservedObject var fftAnalyzer: RealtimeFFTAnalyzer
    
    // Frequency range for filtering
    var minFreq: Float
    var maxFreq: Float
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Analysis Results")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("Showing \(minFreq.formattedAsFrequency()) - \(maxFreq.formattedAsFrequency())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Current peaks display
                peaksAndModesSection
                
                Divider()
                
                // Ring-out time (decay)
                ringOutSection
                
                Divider()
                
                // Tap tone ratio
                ratioSection
                
                // Status indicator
                statusIndicator
            }
            .padding()
        }
    }
    
    // MARK: - Computed Properties
    
    /// Combined peaks with mode classifications, filtered to the current frequency range and sorted by frequency
    /// Optionally filters out unknown modes based on user setting
    private var sortedPeaksWithModes: [(peak: ResonantPeak, mode: GuitarMode)] {
        analyzer.currentPeaks
            .filter { peak in
                peak.frequency >= minFreq && peak.frequency <= maxFreq
            }
            .map { peak in
                (peak: peak, mode: GuitarMode.classify(frequency: peak.frequency))
            }
            .filter { item in
                // Filter out unknown modes if setting is disabled
                SpectrumDisplaySettings.showUnknownModes || item.mode.normalized != .unknown
            }
            .sorted { $0.peak.frequency < $1.peak.frequency }
    }
    
    // MARK: - Subviews
    
    private var peaksAndModesSection: some View {
        GroupBox("Detected Peaks & Modes") {
            if sortedPeaksWithModes.isEmpty {
                Text("No peaks detected in visible range")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sortedPeaksWithModes, id: \.peak.id) { item in
                        CombinedPeakModeRowView(peak: item.peak, mode: item.mode)
                    }
                }
            }
        }
    }
    
    private var ringOutSection: some View {
        GroupBox("Ring-Out Time") {
            if let decayTime = analyzer.currentDecayTime {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(decayTime, specifier: "%.2f") seconds")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Time to decay \(Int(analyzer.decayThreshold)) dB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text(decayTime.decayQuality)
                            .font(.headline)
                            .foregroundColor(decayTime.decayQualityColor)
                        
                        Text("Sustain quality")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("Waiting for decay measurement...")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }
    
    private var ratioSection: some View {
        GroupBox("Tap Tone Ratio") {
            if let ratio = analyzer.calculateTapToneRatio() {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(ratio, specifier: "%.2f") : 1")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Top / Air")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text(ratio.tapToneRatioQuality)
                            .font(.headline)
                            .foregroundColor(ratio.tapToneRatioQualityColor)
                        
                        Text("Ideal: 1.9 - 2.1")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("Need both Air and Top modes")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }
    
    private var statusIndicator: some View {
        HStack {
            Circle()
                .fill(fftAnalyzer.isRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            Text(fftAnalyzer.isRunning ? "Analyzing" : "Stopped")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
