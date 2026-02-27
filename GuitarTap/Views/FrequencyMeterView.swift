//
//  FrequencyMeterView.swift
//  GuitarTap
//
//  SwiftUI view for MPM-based frequency meter measurements (Plate MPM and Brace MPM).
//  Replaces the spectrum display for these measurement types, showing a large
//  frequency readout that updates-and-holds after each tap.
//

import SwiftUI
import AVFoundation

// MARK: - Main FrequencyMeterView

struct FrequencyMeterView: View {
    @ObservedObject var tapToneAnalyzer: TapToneAnalyzer
    @ObservedObject var fftAnalyzer: RealtimeFFTAnalyzer

    // Environment
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    private let pitch = Pitch()

    private var measurementType: MeasurementType {
        SpectrumDisplaySettings.measurementType
    }

    private var isBrace: Bool {
        measurementType == .braceMPM
    }

    /// Returns true if iPhone (not iPad)
    private var isPhone: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            // Phase header strip
            phaseHeaderView
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            // Main frequency display — fills available space
            ScrollView {
                VStack(spacing: 20) {
                    // Big frequency readout
                    frequencyReadoutView
                        .padding(.horizontal)
                        .padding(.top, 16)

                    // Confidence and level bars
                    metersView
                        .padding(.horizontal)

                    // Results panel (appears once measurement is complete)
                    if tapToneAnalyzer.materialTapPhase == .complete {
                        Divider()
                        propertiesPanel
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 16)
                }
            }


        }
    }

    // MARK: - Phase Header

    private var phaseHeaderView: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(phaseColor)
                .frame(width: 10, height: 10)

            Text(phaseTitle)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(phaseColor)

            Spacer()

            // Step indicator
            let totalSteps = isBrace ? 1 : 2
            let step = currentStep
            Text("Step \(step)/\(totalSteps)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Frequency Readout

    private var frequencyReadoutView: some View {
        VStack(spacing: 8) {
            if let freq = tapToneAnalyzer.mpmDetectedFrequency {
                // Large frequency display
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", freq))
                        .font(.system(size: isPhone ? 60 : 80, weight: .bold, design: .rounded))
                        .foregroundColor(tapToneAnalyzer.mpmIsCapturing ? .blue : .primary)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3), value: freq)

                    Text("Hz")
                        .font(.system(size: isPhone ? 28 : 36, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.bottom, isPhone ? 8 : 12)
                }

                // Note name + cents
                let noteString = pitch.note(frequency: Double(freq))
                let centsOffset = pitch.cents(frequency: Double(freq))
                let sign = centsOffset >= 0 ? "+" : ""
                HStack(spacing: 4) {
                    Text(noteString)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text("(\(sign)\(String(format: "%.0f", centsOffset)) ¢)")
                        .font(.title3)
                        .foregroundColor(abs(centsOffset) < 5 ? .green : abs(centsOffset) < 15 ? .orange : .red)
                }
            } else {
                // Placeholder when no reading yet
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("---.-")
                            .font(.system(size: isPhone ? 60 : 80, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("Hz")
                            .font(.system(size: isPhone ? 28 : 36, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.3))
                            .padding(.bottom, isPhone ? 8 : 12)
                    }
                    Text(phaseDescription)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }
            }

            // Capture activity indicator
            if tapToneAnalyzer.mpmIsCapturing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Capturing…")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.07))
        )
    }

    // MARK: - Meters (Confidence + Level)

    /// dB range displayed on the Level bar
    private let levelBarMinDB: Float = -80
    private let levelBarMaxDB: Float = 0

    private var metersView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Confidence bar — shown after a result is available
            if tapToneAnalyzer.mpmDetectedFrequency != nil {
                meterRow(
                    label: "Confidence",
                    value: Double(tapToneAnalyzer.mpmConfidence),
                    maxValue: 1.0,
                    valueText: String(format: "%.2f", tapToneAnalyzer.mpmConfidence),
                    color: tapToneAnalyzer.mpmConfidence >= 0.85 ? .green
                         : tapToneAnalyzer.mpmConfidence >= 0.70 ? .orange : .red,
                    thresholdFraction: nil
                )
            }

            // Live input level bar — uses the same peakMagnitude (FFT spectral peak)
            // signal that the tap detector monitors.  inputLevelDB is raw RMS and is
            // on a different scale; peakMagnitude is what actually drives tap detection.
            //   Orange line  = rising threshold (Threshold slider) — tap fires here
            //   Shaded band  = hysteresis zone (Hysteresis slider) — level must drop
            //                  below the bottom of this band before the next tap fires
            let levelDB = fftAnalyzer.peakMagnitude
            let range = levelBarMaxDB - levelBarMinDB
            let normalizedLevel = max(0.0, min(1.0, Double((levelDB - levelBarMinDB) / range)))
            let aboveThreshold = levelDB > tapToneAnalyzer.tapDetectionThreshold
            let risingFraction  = Double((tapToneAnalyzer.tapDetectionThreshold - levelBarMinDB) / range)
            let fallingFraction = Double((tapToneAnalyzer.tapDetectionThreshold - tapToneAnalyzer.hysteresisMargin - levelBarMinDB) / range)
            levelMeterRow(
                levelValue: normalizedLevel,
                valueText: String(format: "%.0f dB", levelDB),
                color: aboveThreshold ? .green : .blue,
                risingFraction:  max(0, min(1, risingFraction)),
                fallingFraction: max(0, min(1, fallingFraction))
            )
        }
    }

    private func meterRow(label: String, value: Double, maxValue: Double, valueText: String, color: Color, thresholdFraction: Double?) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * min(1, value / maxValue), height: 8)
                        .animation(.easeOut(duration: 0.08), value: value)

                    // Threshold marker line
                    if let tf = thresholdFraction {
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 2, height: 14)
                            .offset(x: geo.size.width * tf - 1)
                    }
                }
            }
            .frame(height: 14)

            Text(valueText)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 54, alignment: .trailing)
                .monospacedDigit()
        }
    }

    /// Level bar variant for the tap-detection signal, with a rising-threshold
    /// marker and a shaded hysteresis band between falling and rising thresholds.
    private func levelMeterRow(levelValue: Double, valueText: String, color: Color, risingFraction: Double, fallingFraction: Double) -> some View {
        HStack(spacing: 10) {
            Text("Level")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)

                    // Hysteresis band (shaded region between falling and rising thresholds)
                    let bandLeft  = w * fallingFraction
                    let bandWidth = max(0, w * (risingFraction - fallingFraction))
                    Rectangle()
                        .fill(Color.orange.opacity(0.20))
                        .frame(width: bandWidth, height: 8)
                        .offset(x: bandLeft)

                    // Level fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: w * min(1, levelValue), height: 8)
                        .animation(.easeOut(duration: 0.08), value: levelValue)

                    // Rising-threshold marker (solid orange — tap fires here)
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: 2, height: 14)
                        .offset(x: w * risingFraction - 1)

                    // Falling-threshold marker (outline orange — level must drop below here for next tap)
                    Rectangle()
                        .fill(Color.orange.opacity(0.6))
                        .frame(width: 2, height: 14)
                        .offset(x: w * fallingFraction - 1)
                }
            }
            .frame(height: 14)

            Text(valueText)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 54, alignment: .trailing)
                .monospacedDigit()
        }
    }

    // MARK: - Properties Panel

    @ViewBuilder
    private var propertiesPanel: some View {
        if isBrace {
            bracePropertiesSummary
        } else {
            platePropertiesSummary
        }
    }

    private var platePropertiesSummary: some View {
        GroupBox("Measurement Results") {
            if let fL = tapToneAnalyzer.mpmLongitudinalFrequency,
               let fC = tapToneAnalyzer.mpmCrossFrequency {
                let dims = MaterialDimensions(
                    lengthMM: SpectrumDisplaySettings.materialLength,
                    widthMM: SpectrumDisplaySettings.materialWidth,
                    thicknessMM: SpectrumDisplaySettings.materialThickness,
                    massGrams: SpectrumDisplaySettings.materialMass
                )
                let props = MaterialProperties(
                    dimensions: dims,
                    fundamentalFrequencyLong: fL,
                    fundamentalFrequencyCross: fC
                )
                platePropertiesContent(props: props, fL: fL, fC: fC)
            } else if let fL = tapToneAnalyzer.mpmLongitudinalFrequency {
                // After L tap but before C tap
                VStack(alignment: .leading, spacing: 6) {
                    Text("fL: \(String(format: "%.1f", fL)) Hz  (\(pitch.note(frequency: Double(fL))))")
                        .font(.subheadline)
                    Text("Rotate 90° and tap again for cross-grain (fC)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Text("Tap to begin measurement")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private func platePropertiesContent(props: MaterialProperties, fL: Float, fC: Float) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Frequencies
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("fL: \(String(format: "%.1f", fL)) Hz")
                        .font(.caption)
                    Text("fC: \(String(format: "%.1f", fC)) Hz")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                Spacer()
            }

            Divider()

            // Speed of Sound
            summaryPropertyRow(
                title: "Speed of Sound",
                longValue: "\(Int(props.speedOfSoundLong)) m/s",
                crossValue: "\(Int(props.speedOfSoundCross)) m/s"
            )

            // Young's Modulus
            summaryPropertyRow(
                title: "Young's Modulus (E)",
                longValue: String(format: "%.2f GPa", props.youngsModulusLongGPa),
                crossValue: String(format: "%.2f GPa", props.youngsModulusCrossGPa)
            )

            // Specific Modulus — highlighted
            VStack(alignment: .leading, spacing: 6) {
                Text("Specific Modulus (E/ρ)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("L:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(format: "%.1f", props.specificModulusLong))
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(qualityColor(for: props.spruceQualityLong))
                            Text("GPa/(g/cm³)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text(props.spruceQualityLong.rawValue)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(qualityColor(for: props.spruceQualityLong))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("C:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(format: "%.2f", props.specificModulusCross))
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(qualityColor(for: props.spruceQualityCross))
                            Text("GPa/(g/cm³)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text(props.spruceQualityCross.rawValue)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(qualityColor(for: props.spruceQualityCross))
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            // Overall Quality
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
        }
    }

    private var bracePropertiesSummary: some View {
        GroupBox("Brace Measurement Results") {
            if let fL = tapToneAnalyzer.mpmLongitudinalFrequency {
                let dims = MaterialDimensions(
                    lengthMM: SpectrumDisplaySettings.braceLength,
                    widthMM: SpectrumDisplaySettings.braceWidth,
                    thicknessMM: SpectrumDisplaySettings.braceThickness,
                    massGrams: SpectrumDisplaySettings.braceMass
                )
                let props = BraceProperties(
                    dimensions: dims,
                    fundamentalFrequencyLong: fL
                )
                VStack(alignment: .leading, spacing: 12) {
                    // Frequency
                    Text("fL: \(String(format: "%.1f", fL)) Hz  (\(pitch.note(frequency: Double(fL))))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    // Properties grid: 2×2 layout with label above value
                    HStack(alignment: .top, spacing: 12) {
                        // Speed of Sound
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Speed of Sound")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(props.speedOfSoundLong)) m/s")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Young's Modulus
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Young's Modulus (E)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.2f GPa", props.youngsModulusLongGPa))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        // Specific Modulus — highlighted
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Specific Modulus (E/ρ)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(String(format: "%.1f", props.specificModulusLong))
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(qualityColor(for: props.spruceQuality))
                                Text("GPa/(g/cm³)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Text(props.spruceQuality.rawValue)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(qualityColor(for: props.spruceQuality))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Radiation Ratio
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Radiation Ratio (R)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f", props.radiationRatioLong))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("Tap to begin measurement")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }

    // MARK: - Phase Helpers

    private var phaseColor: Color {
        switch tapToneAnalyzer.materialTapPhase {
        case .notStarted: return .gray
        case .capturingLongitudinal: return .blue
        case .waitingForCrossTap: return .orange
        case .capturingCross: return .orange
        case .waitingForFlcTap, .capturingFlc: return .purple
        case .complete: return .green
        }
    }

    private var currentStep: Int {
        switch tapToneAnalyzer.materialTapPhase {
        case .notStarted, .capturingLongitudinal: return 1
        case .waitingForCrossTap, .capturingCross: return 2
        case .waitingForFlcTap, .capturingFlc: return 3
        case .complete: return isBrace ? 1 : 2
        }
    }

    private var phaseTitle: String {
        switch tapToneAnalyzer.materialTapPhase {
        case .notStarted:
            return "Ready to Measure"
        case .capturingLongitudinal:
            return isBrace ? "Step 1: Longitudinal (fL) Tap" : "Step 1: Longitudinal (fL) Tap"
        case .waitingForCrossTap:
            return "fL Captured — Rotate 90° for Cross Tap"
        case .capturingCross:
            return "Step 2: Cross-grain (fC) Tap"
        case .waitingForFlcTap, .capturingFlc:
            return "Step 3: FLC Tap"
        case .complete:
            return "Measurement Complete"
        }
    }

    private var phaseDescription: String {
        switch tapToneAnalyzer.materialTapPhase {
        case .notStarted:
            if isBrace {
                return "Press 'New Tap', support the brace at ~22% from each end, then tap the center."
            }
            return "Press 'New Tap', support the plate along SHORT edges at ~22% from ends, then tap the center."
        case .capturingLongitudinal:
            if isBrace {
                return "Support the brace at ~22% from each end (nodal points). Tap the CENTER. The brace will vibrate along its length."
            }
            return "Support plate along SHORT edges at ~22% from each end. Tap the CENTER of the plate."
        case .waitingForCrossTap:
            return "fL captured! Rotate the plate 90°, support along LONG edges at ~22% from each end. Tap New Tap, then tap center."
        case .capturingCross:
            return "Support plate along LONG edges at ~22% from each end. Tap the CENTER."
        case .waitingForFlcTap, .capturingFlc:
            return "Support plate at all 4 corner nodal points (~22% from each corner). Tap the CENTER."
        case .complete:
            return "Tap 'Save' to store this measurement."
        }
    }

    // MARK: - Helper Views

    private func summaryPropertyRow(title: String, longValue: String, crossValue: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
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
        case .veryGood:  return .mint
        case .good:      return .blue
        case .fair:      return .orange
        case .poor:      return .red
        }
    }
}
