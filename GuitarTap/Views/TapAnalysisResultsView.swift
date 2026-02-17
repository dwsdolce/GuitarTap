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
    
    // Material mode selection state - exposed via bindings for parent view to use
    @Binding var selectedLongitudinalPeakID: UUID?
    @Binding var selectedCrossPeakID: UUID?
    
    // Current measurement type
    private var measurementType: MeasurementType {
        SpectrumDisplaySettings.measurementType
    }
    
    /// Effective longitudinal peak ID - uses binding value if set, otherwise falls back to auto-selected
    private var effectiveLongitudinalPeakID: UUID? {
        selectedLongitudinalPeakID ?? analyzer.autoSelectedLongitudinalPeakID
    }
    
    /// Effective cross-grain peak ID - uses binding value if set, otherwise falls back to auto-selected
    private var effectiveCrossPeakID: UUID? {
        selectedCrossPeakID ?? analyzer.autoSelectedCrossPeakID
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Analysis Results")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    HStack {
                        Text("Showing \(minFreq.formattedAsFrequency()) - \(maxFreq.formattedAsFrequency())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(measurementType.shortName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(measurementType.isGuitar ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                // Current peaks display
                peaksAndModesSection
                
                // Material-specific sections
                if measurementType == .material {
                    Divider()
                    materialPropertiesSection
                } else {
                    // Guitar-specific sections
                    Divider()
                    
                    // Ring-out time (decay)
                    ringOutSection
                    
                    Divider()
                    
                    // Tap tone ratio
                    ratioSection
                }
                
                // Status indicator
                statusIndicator
            }
            .padding()
        }
    }
    
    // MARK: - Computed Properties
    
    /// Combined peaks with mode classifications, filtered to the current frequency range and sorted by frequency
    /// Optionally filters out unknown modes based on user setting (guitar mode only)
    private var sortedPeaksWithModes: [(peak: ResonantPeak, mode: GuitarMode)] {
        analyzer.currentPeaks
            .filter { peak in
                peak.frequency >= minFreq && peak.frequency <= maxFreq
            }
            .map { peak in
                (peak: peak, mode: GuitarMode.classify(frequency: peak.frequency))
            }
            .filter { item in
                // For material mode, show all peaks (don't filter by guitar mode)
                // For guitar mode, optionally filter out unknown modes
                measurementType == .material || SpectrumDisplaySettings.showUnknownModes || item.mode.normalized != .unknown
            }
            .sorted { $0.peak.frequency < $1.peak.frequency }
    }
    
    // MARK: - Subviews
    
    private var peaksAndModesSection: some View {
        GroupBox(measurementType == .material ? "Detected Peaks" : "Detected Peaks & Modes") {
            if sortedPeaksWithModes.isEmpty {
                Text("No peaks detected in visible range")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // For material measurements, show selectable peaks
                    if measurementType == .material {
                        ForEach(sortedPeaksWithModes, id: \.peak.id) { item in
                            MaterialPeakRowView(
                                peak: item.peak,
                                isLongitudinal: effectiveLongitudinalPeakID == item.peak.id,
                                isCross: effectiveCrossPeakID == item.peak.id,
                                onSelectLongitudinal: {
                                    if effectiveLongitudinalPeakID == item.peak.id {
                                        // Deselect - clear both binding and auto-selected
                                        selectedLongitudinalPeakID = nil
                                        analyzer.autoSelectedLongitudinalPeakID = nil
                                    } else {
                                        selectedLongitudinalPeakID = item.peak.id
                                        // Can't be both
                                        if effectiveCrossPeakID == item.peak.id {
                                            selectedCrossPeakID = nil
                                            analyzer.autoSelectedCrossPeakID = nil
                                        }
                                    }
                                },
                                onSelectCross: {
                                    if effectiveCrossPeakID == item.peak.id {
                                        // Deselect - clear both binding and auto-selected
                                        selectedCrossPeakID = nil
                                        analyzer.autoSelectedCrossPeakID = nil
                                    } else {
                                        selectedCrossPeakID = item.peak.id
                                        // Can't be both
                                        if effectiveLongitudinalPeakID == item.peak.id {
                                            selectedLongitudinalPeakID = nil
                                            analyzer.autoSelectedLongitudinalPeakID = nil
                                        }
                                    }
                                }
                            )
                        }
                        
                        // Instructions and guidance
                        VStack(alignment: .leading, spacing: 6) {
                            Divider()
                                .padding(.vertical, 4)
                            
                            Text("Two-Tap Measurement Process:")
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("**1. Longitudinal (L) Tap**")
                                            .font(.caption2)
                                        Text("Support plate along SHORT edges (at ~22% from ends). Tap center. The plate bends along its length (grain direction).")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                } icon: {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 8, height: 8)
                                }
                                
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("**2. Cross-grain (C) Tap**")
                                            .font(.caption2)
                                        Text("Rotate 90°, support along LONG edges. Tap center. The plate bends across its width (perpendicular to grain).")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                } icon: {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            
                            Text("The strongest peak from each tap is auto-selected. Adjust selections above if needed.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .italic()
                                .padding(.top, 2)
                        }
                        .padding(.top, 4)
                    } else {
                        // Standard guitar mode display
                        ForEach(sortedPeaksWithModes, id: \.peak.id) { item in
                            CombinedPeakModeRowView(peak: item.peak, mode: item.mode)
                        }
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
    
    // MARK: - Material Properties Section
    
    /// Computed material properties based on selected peaks and dimensions
    private var calculatedMaterialProperties: MaterialProperties? {
        guard let longPeakID = effectiveLongitudinalPeakID,
              let crossPeakID = effectiveCrossPeakID,
              let longPeak = sortedPeaksWithModes.first(where: { $0.peak.id == longPeakID })?.peak,
              let crossPeak = sortedPeaksWithModes.first(where: { $0.peak.id == crossPeakID })?.peak else {
            return nil
        }
        
        let dimensions = MaterialDimensions(
            lengthMM: SpectrumDisplaySettings.materialLength,
            widthMM: SpectrumDisplaySettings.materialWidth,
            thicknessMM: SpectrumDisplaySettings.materialThickness,
            massGrams: SpectrumDisplaySettings.materialMass
        )
        
        return MaterialProperties(
            dimensions: dimensions,
            fundamentalFrequencyLong: longPeak.frequency,
            fundamentalFrequencyCross: crossPeak.frequency
        )
    }
    
    private var materialPropertiesSection: some View {
        GroupBox("Material Properties") {
            if let props = calculatedMaterialProperties {
                VStack(alignment: .leading, spacing: 16) {
                    // Frequencies used
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Longitudinal: \(props.fundamentalFrequencyLong, specifier: "%.1f") Hz")
                                .font(.caption)
                            Text("Cross-grain: \(props.fundamentalFrequencyCross, specifier: "%.1f") Hz")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    Divider()
                    
                    // Speed of Sound
                    propertyRow(
                        title: "Speed of Sound",
                        longValue: "\(Int(props.speedOfSoundLong)) m/s",
                        crossValue: "\(Int(props.speedOfSoundCross)) m/s"
                    )
                    
                    // Young's Modulus
                    propertyRow(
                        title: "Young's Modulus (E)",
                        longValue: String(format: "%.2f GPa", props.youngsModulusLongGPa),
                        crossValue: String(format: "%.2f GPa", props.youngsModulusCrossGPa)
                    )
                    
                    // Specific Modulus (E/ρ) - the key metric
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Specific Modulus (E/ρ)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Longitudinal:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(String(format: "%.1f", props.specificModulusLong))
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(qualityColor(for: props.spruceQualityLong))
                                    Text("GPa/(g/cm³)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(props.spruceQualityLong.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(qualityColor(for: props.spruceQualityLong))
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Cross-grain:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(String(format: "%.2f", props.specificModulusCross))
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(qualityColor(for: props.spruceQualityCross))
                                    Text("GPa/(g/cm³)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(props.spruceQualityCross.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(qualityColor(for: props.spruceQualityCross))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Radiation Ratio
                    propertyRow(
                        title: "Radiation Ratio (R)",
                        longValue: String(format: "%.1f", props.radiationRatioLong),
                        crossValue: String(format: "%.1f", props.radiationRatioCross)
                    )
                    
                    // Cross/Long Ratio
                    HStack {
                        Text("Cross/Long Ratio:")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.3f", props.crossLongRatio))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("(typical: 0.04-0.08)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // Overall Quality Assessment
                    HStack {
                        Text("Overall Quality:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text(props.overallQuality.rawValue)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(qualityColor(for: props.overallQuality))
                    }
                    .padding(.vertical, 4)
                }
            } else {
                VStack(spacing: 12) {
                    if selectedLongitudinalPeakID == nil && selectedCrossPeakID == nil {
                        Text("Select peaks above to calculate properties")
                            .foregroundColor(.secondary)
                    } else if selectedLongitudinalPeakID == nil {
                        Text("Select a longitudinal (L) peak")
                            .foregroundColor(.orange)
                    } else {
                        Text("Select a cross-grain (C) peak")
                            .foregroundColor(.orange)
                    }
                    
                    Text("Tip: The longitudinal mode is typically the higher frequency peak")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func propertyRow(title: String, longValue: String, crossValue: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            HStack {
                Text("L: \(longValue)")
                    .font(.caption)
                Spacer()
                Text("C: \(crossValue)")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
    }
    
    private func qualityColor(for quality: WoodQuality) -> Color {
        switch quality {
        case .excellent: return .green
        case .veryGood: return .mint
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        }
    }
}

// MARK: - Material Peak Row View

/// A row view for displaying a peak with material mode selection buttons
struct MaterialPeakRowView: View {
    let peak: ResonantPeak
    let isLongitudinal: Bool
    let isCross: Bool
    let onSelectLongitudinal: () -> Void
    let onSelectCross: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Frequency and magnitude
            VStack(alignment: .leading, spacing: 2) {
                Text(peak.frequency.formattedAsFrequency())
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("\(peak.magnitude, specifier: "%.1f") dB")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Mode selection buttons
            HStack(spacing: 8) {
                Button(action: onSelectLongitudinal) {
                    Text("L")
                        .font(.headline)
                        .fontWeight(.bold)
                        .frame(width: 36, height: 36)
                        .background(isLongitudinal ? Color.blue : Color.secondary.opacity(0.2))
                        .foregroundColor(isLongitudinal ? .white : .primary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: onSelectCross) {
                    Text("C")
                        .font(.headline)
                        .fontWeight(.bold)
                        .frame(width: 36, height: 36)
                        .background(isCross ? Color.orange : Color.secondary.opacity(0.2))
                        .foregroundColor(isCross ? .white : .primary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
