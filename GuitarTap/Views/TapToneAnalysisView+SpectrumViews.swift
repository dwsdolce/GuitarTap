//
//  TapToneAnalysisView+SpectrumViews.swift
//  GuitarTap
//

import SwiftUI

extension TapToneAnalysisView {

    // Computed properties to explicitly depend on @Published properties
    var displayFrequencies: [Float] {
        tap.isSpectrumFrozen ? tap.frozenFrequencies : fft.frequencies
    }

    var displayMagnitudes: [Float] {
        tap.isSpectrumFrozen ? tap.frozenMagnitudes : fft.magnitudes
    }

    /// Per-phase spectra for material/brace measurements, formatted for SpectrumView overlay
    var materialSpectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)] {
        let measurementType = TapDisplaySettings.measurementType
        guard !measurementType.isGuitar else { return [] }
        var result: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)] = []
        if let spec = tap.longitudinalSpectrum {
            result.append((magnitudes: spec.magnitudes, frequencies: spec.frequencies, color: .blue, label: "Longitudinal (L)"))
        }
        if measurementType == .material, let spec = tap.crossSpectrum {
            result.append((magnitudes: spec.magnitudes, frequencies: spec.frequencies, color: .orange, label: "Cross-grain (C)"))
        }
        if measurementType == .material, let spec = tap.flcSpectrum {
            result.append((magnitudes: spec.magnitudes, frequencies: spec.frequencies, color: .purple, label: "FLC"))
        }
        return result
    }

    var realTimeSpectrumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Prepare threshold lines for the chart
            let thresholds: [(value: Float, label: String, color: Color, lineWidth: CGFloat, dash: [CGFloat])] = {
                var lines: [(Float, String, Color, CGFloat, [CGFloat])] = []

                // Rising threshold (main threshold line)
                let risingThreshold = tap.tapDetectionThreshold
                if risingThreshold > minDB && risingThreshold < maxDB {
                    lines.append((
                        risingThreshold,
                        "Trigger: \(Int(risingThreshold)) dB",
                        .orange.opacity(0.7),
                        2.0,
                        [5, 3]
                    ))
                }

                // Falling threshold (hysteresis line)
                if tap.hysteresisMargin > 0.5 {
                    let fallingThreshold = risingThreshold - tap.hysteresisMargin
                    if fallingThreshold > minDB && fallingThreshold < maxDB {
                        lines.append((
                            fallingThreshold,
                            "Reset: \(Int(fallingThreshold)) dB",
                            .purple.opacity(0.5),
                            1.5,
                            [3, 3]
                        ))
                    }
                }

                // Peak detection threshold line
                let peakThreshold = tap.peakThreshold
                if peakThreshold > minDB && peakThreshold < maxDB {
                    lines.append((
                        peakThreshold,
                        "Peak: \(Int(peakThreshold)) dB",
                        .green.opacity(0.7),
                        1.5,
                        [8, 3]
                    ))
                }

                return lines
            }()

            // Spectrum Chart
            Group {
                #if os(macOS)
                SpectrumView(
                    frequencies: displayFrequencies,
                    magnitudes: displayMagnitudes,
                    minFreq: $minFreq,
                    maxFreq: $maxFreq,
                    minDB: $minDB,
                    maxDB: $maxDB,
                    isLogarithmic: .constant(false),
                    peaks: tap.visiblePeaks,
                    showModeBoundaries: true,
                    onFrequencyRangeChanged: updateFrequencyInputFields,
                    annotationOffsets: $tapToneAnalyzer.peakAnnotationOffsets,
                    materialSpectra: materialSpectra,
                    thresholdLines: thresholds,
                    onResetLabels: {
                        tapToneAnalyzer.resetAllAnnotationOffsets()
                    },
                    hasLabelsToReset: !tap.peakAnnotationOffsets.isEmpty,
                    isSpectrumFrozen: tap.isSpectrumFrozen,
                    primaryCurveColor: .red,
                    measurementType: TapDisplaySettings.measurementType,
                    selectedLongitudinalPeakID: tap.effectiveLongitudinalPeakID,
                    selectedCrossPeakID: tap.effectiveCrossPeakID,
                    selectedFlcPeakID: tap.effectiveFlcPeakID,
                    modeOverrides: tap.peakModeOverrides
                )
                #else
                SpectrumView(
                    frequencies: displayFrequencies,
                    magnitudes: displayMagnitudes,
                    minFreq: $minFreq,
                    maxFreq: $maxFreq,
                    minDB: $minDB,
                    maxDB: $maxDB,
                    isLogarithmic: .constant(false),
                    peaks: tap.visiblePeaks,
                    showModeBoundaries: true,
                    onFrequencyRangeChanged: updateFrequencyInputFields,
                    annotationOffsets: $tapToneAnalyzer.peakAnnotationOffsets,
                    materialSpectra: materialSpectra,
                    thresholdLines: thresholds,
                    onResetLabels: {
                        tapToneAnalyzer.resetAllAnnotationOffsets()
                    },
                    hasLabelsToReset: !tap.peakAnnotationOffsets.isEmpty,
                    isSpectrumFrozen: tap.isSpectrumFrozen,
                    primaryCurveColor: .red,
                    measurementType: TapDisplaySettings.measurementType,
                    selectedLongitudinalPeakID: tap.effectiveLongitudinalPeakID,
                    selectedCrossPeakID: tap.effectiveCrossPeakID,
                    selectedFlcPeakID: tap.effectiveFlcPeakID,
                    modeOverrides: tap.peakModeOverrides,
                    crosshairMode: $crosshairMode
                )
                #endif
            }
            // Force view to update when any relevant state changes
            .id("\(tap.isSpectrumFrozen)-\(fft.isRunning)-\(displayFrequencies.count)-\(displayMagnitudes.count)")
            .frame(minHeight: 250, maxHeight: .infinity)  // Allow to expand vertically
            #if os(iOS)
            .padding(isPhoneLandscape ? .horizontal : .all)
            #else
            .padding()
            #endif
            .background(Color.gray.opacity(0.05))
            .cornerRadius(10)
            .overlay(
                Group {
                    if !fft.isRunning {
                        VStack {
                            Image(systemName: "waveform.slash")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("Press Start to begin analysis")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .onAppear {
                            print("🚫 Overlay: NOT RUNNING shown")
                        }
                    } else if fft.frequencies.isEmpty {
                        VStack {
                            ProgressView()
                            Text("Loading...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .onAppear {
                            print("⏳ Overlay: LOADING shown (frequencies is empty)")
                        }
                    } else {
                        // Debug: Show when chart should be visible
                        Color.clear
                            .onAppear {
                                print("✅ Overlay: CHART VISIBLE (running=\(fft.isRunning), freq count=\(fft.frequencies.count), mag count=\(fft.magnitudes.count))")
                            }
                    }
                }
            )
        }
    }

    var decayTimeView: some View {
        Group {
            if !TapDisplaySettings.measurementType.isGuitar {
                // Material/brace measurement instructions
                materialInstructionsView
            } else {
                // Guitar mode: Ring-Out Time and Tap Tone Ratio
                guitarMetricsView
            }
        }
    }

    /// Material measurement instructions panel
    var materialInstructionsView: some View {
        GroupBox("Material Measurement") {
            VStack(alignment: .leading, spacing: 8) {
                // Current phase indicator
                HStack {
                    Circle()
                        .fill(materialPhaseColor)
                        .frame(width: 10, height: 10)
                    Text(tap.materialTapPhase.shortStatus)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(materialPhaseColor)
                    Spacer()
                    Text("Step \(materialPhaseStep)/\(TapDisplaySettings.measurementType == .brace ? 1 : (TapDisplaySettings.measureFlc ? 3 : 2))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Instructions based on current phase
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: materialPhaseIcon)
                        .font(.title2)
                        .foregroundColor(materialPhaseColor)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(materialPhaseTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(materialPhaseDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Color for current material measurement phase
    var materialPhaseColor: Color {
        switch tap.materialTapPhase {
        case .notStarted: return .gray
        case .capturingLongitudinal: return .blue
        case .waitingForCrossTap: return .orange
        case .capturingCross: return .orange
        case .waitingForFlcTap: return .purple
        case .capturingFlc: return .purple
        case .complete: return .green
        }
    }

    /// Step number for current material measurement phase
    var materialPhaseStep: Int {
        switch tap.materialTapPhase {
        case .notStarted, .capturingLongitudinal: return 1
        case .waitingForCrossTap, .capturingCross: return 2
        case .waitingForFlcTap, .capturingFlc: return 3
        case .complete: return TapDisplaySettings.measureFlc ? 3 : 2
        }
    }

    /// Icon for current material measurement phase
    var materialPhaseIcon: String {
        switch tap.materialTapPhase {
        case .notStarted: return "hand.tap"
        case .capturingLongitudinal: return "waveform"
        case .waitingForCrossTap: return "rotate.3d"
        case .capturingCross: return "waveform"
        case .waitingForFlcTap: return "rotate.3d"
        case .capturingFlc: return "waveform"
        case .complete: return "checkmark.circle.fill"
        }
    }

    /// Title for current material/brace measurement phase
    var materialPhaseTitle: String {
        let isBrace = TapDisplaySettings.measurementType == .brace
        switch tap.materialTapPhase {
        case .notStarted:
            return "Press 'New Tap' to Begin"
        case .capturingLongitudinal:
            return isBrace ? "Step 1: Longitudinal (fL) Mode" : "Step 1: Longitudinal (L) Mode"
        case .waitingForCrossTap:
            return "L Captured - Prepare for Step 2"
        case .capturingCross:
            return "Step 2: Cross-grain (C) Mode"
        case .waitingForFlcTap:
            return "C Captured - Prepare for Step 3"
        case .capturingFlc:
            return "Step 3: FLC (Diagonal) Mode"
        case .complete:
            return "Measurement Complete"
        }
    }

    /// Description for current material/brace measurement phase
    var materialPhaseDescription: String {
        let isBrace = TapDisplaySettings.measurementType == .brace
        switch tap.materialTapPhase {
        case .notStarted:
            if isBrace {
                return "Press 'New Tap' to begin the brace fL measurement."
            }
            let tapWord = TapDisplaySettings.measureFlc ? "three-tap" : "two-tap"
            return "Press 'New Tap' to begin the \(tapWord) material measurement process."
        case .capturingLongitudinal:
            if isBrace {
                return "Support the brace at ~22% from each end (nodal points). Tap the CENTER. The brace will vibrate along its length (grain direction)."
            }
            return "Support plate along SHORT edges at ~22% from each end. Tap the CENTER of the plate. The plate will bend along its length (grain direction)."
        case .waitingForCrossTap:
            return "Longitudinal mode captured! Now ROTATE the plate 90°, support along LONG edges at ~22% from each end. Tap the CENTER for cross-grain."
        case .capturingCross:
            return "Support plate along LONG edges at ~22% from each end. Tap the CENTER. The plate will bend across its width (perpendicular to grain)."
        case .waitingForFlcTap:
            return "Cross-grain mode captured! Now support the plate at all 4 CORNER nodal points (~22% from each corner). Tap the CENTER for FLC."
        case .capturingFlc:
            return "Support plate at all 4 nodal corner points (~22% from each corner). Tap the CENTER. Measures the plate's shear-related stiffness."
        case .complete:
            if isBrace {
                return "fL captured! Review the fL (blue) peak selection in the Results panel. Adjust if the auto-selection isn't correct."
            }
            let flcPart = TapDisplaySettings.measureFlc ? ", and FLC (purple)" : ""
            return "All modes captured! Review the L (blue), C (orange)\(flcPart) peak selections in the Results panel. Adjust if the auto-selection isn't correct."
        }
    }

    /// Guitar mode metrics view (Ring-Out Time and Tap Tone Ratio)
    var guitarMetricsView: some View {
        HStack(spacing: 12) {
            // Ring-Out Time
            GroupBox("Ring-Out Time") {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundColor(.blue)

                    if let decay = tap.currentDecayTime {
                        Text("\(decay, specifier: "%.2f") seconds")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("Decay Quality")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(decay.decayQuality)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(decay.decayQualityColor)
                        }
                    } else {
                        Text("Waiting for decay measurement...")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity)

            // Tap Tone Ratio
            GroupBox("Tap Tone Ratio") {
                HStack {
                    Image(systemName: "divide")
                        .foregroundColor(.purple)

                    if let ratio = tap.calculateTapToneRatio() {
                        Text("\(ratio, specifier: "%.2f")")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("Top / Air")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(ratio.tapToneRatioQuality)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(ratio.tapToneRatioQualityColor)
                        }
                    } else {
                        Text("Needs Air & Top peaks...")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
