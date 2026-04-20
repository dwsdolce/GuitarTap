//
//  TapToneAnalysisView+SpectrumViews.swift
//  GuitarTap
//

/// # TapToneAnalysisView+SpectrumViews
///
/// Spectrum display properties and material-phase UI for `TapToneAnalysisView`.
///
/// ## Spectrum Data Sources
///
/// Two computed properties resolve which data is currently displayed:
///
/// | Property | Frozen | Live |
/// |---|---|---|
/// | `displayFrequencies` | `tap.frozenFrequencies` | `fft.frequencies` |
/// | `displayMagnitudes` | `tap.frozenMagnitudes` | `fft.magnitudes` |
///
/// The spectrum is frozen immediately after a tap is detected so the chart
/// holds the last captured FFT while the analyzer continues running.
///
/// ## Material Spectra Overlay
///
/// For plate and brace measurements `materialSpectra` assembles up to three
/// named series (longitudinal, cross-grain, FLC) from the analyzer's
/// per-phase `SpectrumSnapshot` properties. Guitar measurements return an
/// empty array and use the single red primary curve instead.
///
/// ## Threshold Lines
///
/// `realTimeSpectrumView` injects up to three dashed threshold lines into
/// `SpectrumView`:
/// - **Orange dashed** — rising tap trigger threshold
/// - **Purple dashed** — falling / reset hysteresis threshold
/// - **Green dashed** — peak detection threshold
///
/// Lines outside the current dB range are filtered out before passing to
/// the chart.
///
/// ## Material Phase UI
///
/// `materialInstructionsView` presents a step-by-step instruction card
/// driven by `tap.materialTapPhase`. In guitar mode nothing is shown below
/// the chart; Ring-Out Time and Tap Tone Ratio appear in the Results panel.
///
/// - SeeAlso: `TapToneAnalysisView+Layouts`, `SpectrumView`, `MaterialTapPhase`

import SwiftUI

extension TapToneAnalysisView {

    // Computed properties to explicitly depend on @Published properties.
    // displayFrequencies and displayMagnitudes are derived from a single
    // atomic snapshot so they always correspond to the same source — frozen
    // or live — and therefore always have matching lengths.  Reading
    // isMeasurementComplete twice (once per property) could produce
    // mismatched lengths when the flag flips between the two evaluations,
    // which causes SwiftUI Charts to render spurious vertical line artifacts.
    //
    // Guard: when isMeasurementComplete is true but frozenFrequencies is still
    // empty (transient race during loadMeasurement while the live FFT is still
    // publishing), return empty arrays rather than the live 32768-bin data.
    // This prevents the one-frame bar-forest artifact seen when a measurement
    // is loaded while the audio engine is running.
    private var displaySpectrum: (frequencies: [Float], magnitudes: [Float]) {
        // In comparison mode the main line must be suppressed — the comparison
        // overlays are drawn via materialSpectra.  Without this guard the live
        // FFT feed (fft.frequencies/magnitudes) bleeds through as a red jagged
        // waveform on top of the comparison curves.
        if tap.displayMode == .comparison {
            return ([], [])
        }
        if tap.isMeasurementComplete {
            // For plate/brace measurements frozen arrays are intentionally empty
            // (phase spectra live in materialSpectra); always return them as-is.
            // For guitar, guard against the transient empty-frozen / live-running race.
            if tap.frozenFrequencies.isEmpty && tap.materialTapPhase != .complete {
                return ([], [])
            }
            return (tap.frozenFrequencies, tap.frozenMagnitudes)
        } else {
            return (fft.frequencies, fft.magnitudes)
        }
    }

    var displayFrequencies: [Float] { displaySpectrum.frequencies }
    var displayMagnitudes:  [Float] { displaySpectrum.magnitudes  }

    /// Per-phase spectra for plate/brace measurements, plus any active comparison overlays.
    ///
    /// For guitar mode this returns only `comparisonSpectra` (empty when no comparison is loaded).
    /// For plate/brace mode this returns the per-phase spectra (longitudinal/cross/FLC).
    var materialSpectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)] {
        // Comparison mode takes priority over everything else — when the user has
        // selected measurements to compare, show those overlays regardless of
        // measurement type (guitar, plate, or brace).
        if tap.displayMode == .comparison {
            return tap.comparisonSpectra.map { (magnitudes: $0.magnitudes, frequencies: $0.frequencies, color: $0.color, label: $0.label) }
        }
        let measurementType = TapDisplaySettings.measurementType
        if measurementType.isGuitar {
            return []
        }
        var result: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)] = []
        if let spec = tap.longitudinalSpectrum {
            result.append((magnitudes: spec.magnitudes, frequencies: spec.frequencies, color: .blue, label: "Longitudinal (L)"))
        }
        if measurementType == .plate, let spec = tap.crossSpectrum {
            result.append((magnitudes: spec.magnitudes, frequencies: spec.frequencies, color: .orange, label: "Cross-grain (C)"))
        }
        if measurementType == .plate, let spec = tap.flcSpectrum {
            result.append((magnitudes: spec.magnitudes, frequencies: spec.frequencies, color: .purple, label: "FLC"))
        }
        return result
    }

    /// Chart title: the loaded measurement's location/name, or "New" when no measurement is loaded.
    var chartTitle: String {
        tap.loadedMeasurementName ?? "New"
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

                // Peak detection threshold line (guitar only — not used for plate/brace)
                if TapDisplaySettings.measurementType.isGuitar {
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
                }

                return lines
            }()

            // Spectrum Chart
            // Suppress single-measurement peak annotations while comparison is active —
            // the annotation positions belong to the previous measurement and would render
            // in the wrong place relative to the comparison curves.
            let isComparing = tap.displayMode == .comparison
            spectrumView(isComparing: isComparing, thresholds: thresholds)
            // Force view to update when any relevant state changes
            .id("\(tap.isMeasurementComplete)-\(fft.isRunning)-\(displayFrequencies.count)-\(displayMagnitudes.count)")
            .frame(minHeight: 200, maxHeight: .infinity)
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
                            Image(systemName: "waveform")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("Starting...")
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

    /// Builds the `SpectrumView` with all shared parameters, injecting
    /// `crosshairMode` on iOS only.
    @ViewBuilder
    func spectrumView(
        isComparing: Bool,
        thresholds: [(value: Float, label: String, color: Color, lineWidth: CGFloat, dash: [CGFloat])]
    ) -> some View {
        #if os(iOS)
        SpectrumView(
            frequencies: displayFrequencies,
            magnitudes: displayMagnitudes,
            minFreq: $minFreq,
            maxFreq: $maxFreq,
            minDB: $minDB,
            maxDB: $maxDB,
            isLogarithmic: .constant(false),
            peaks: isComparing ? nil : tap.currentPeaks,
            annotationPeaks: isComparing ? nil : tap.visiblePeaks,
            showModeBoundaries: true,
            onFrequencyRangeChanged: updateFrequencyInputFields,
            onAxisRangeReset: applyAxisRange,
            annotationOffsets: $tapToneAnalyzer.peakAnnotationOffsets,
            materialSpectra: materialSpectra,
            thresholdLines: isComparing ? [] : thresholds,
            onResetLabels: { tapToneAnalyzer.resetAllAnnotationOffsets() },
            hasLabelsToReset: !tap.peakAnnotationOffsets.isEmpty,
            isMeasurementComplete: tap.isMeasurementComplete,
            isReviewingMaterialPhase: tap.materialTapPhase.isReviewing,
            primaryCurveColor: .red,
            measurementType: TapDisplaySettings.measurementType,
            selectedLongitudinalPeakID: tap.effectiveLongitudinalPeakID,
            selectedCrossPeakID: tap.effectiveCrossPeakID,
            selectedFlcPeakID: tap.effectiveFlcPeakID,
            modeOverrides: tap.peakModeOverrides,
            peakModes: Dictionary(uniqueKeysWithValues: tap.identifiedModes.map { ($0.peak.id, $0.mode) }),
            highlightedPeakID: $tapToneAnalyzer.highlightedPeakID,
            chartTitle: "FFT Peaks — \(chartTitle)",
            crosshairMode: $crosshairMode
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
            peaks: isComparing ? nil : tap.currentPeaks,
            annotationPeaks: isComparing ? nil : tap.visiblePeaks,
            showModeBoundaries: true,
            onFrequencyRangeChanged: updateFrequencyInputFields,
            onAxisRangeReset: applyAxisRange,
            annotationOffsets: $tapToneAnalyzer.peakAnnotationOffsets,
            materialSpectra: materialSpectra,
            thresholdLines: isComparing ? [] : thresholds,
            onResetLabels: { tapToneAnalyzer.resetAllAnnotationOffsets() },
            hasLabelsToReset: !tap.peakAnnotationOffsets.isEmpty,
            isMeasurementComplete: tap.isMeasurementComplete,
            isReviewingMaterialPhase: tap.materialTapPhase.isReviewing,
            primaryCurveColor: .red,
            measurementType: TapDisplaySettings.measurementType,
            selectedLongitudinalPeakID: tap.effectiveLongitudinalPeakID,
            selectedCrossPeakID: tap.effectiveCrossPeakID,
            selectedFlcPeakID: tap.effectiveFlcPeakID,
            modeOverrides: tap.peakModeOverrides,
            peakModes: Dictionary(uniqueKeysWithValues: tap.identifiedModes.map { ($0.peak.id, $0.mode) }),
            highlightedPeakID: $tapToneAnalyzer.highlightedPeakID,
            chartTitle: "FFT Peaks — \(chartTitle)"
        )
        #endif
    }

    var decayTimeView: some View {
        Group {
            if !TapDisplaySettings.measurementType.isGuitar && tap.displayMode != .comparison {
                // Plate/brace measurement instructions (suppressed during comparison)
                materialInstructionsView
            }
            // Guitar mode: Ring-Out Time and Tap Tone Ratio are in the Results panel
        }
    }

    /// Material measurement instructions panel
    var materialInstructionsView: some View {
        GroupBox(TapDisplaySettings.measurementType == .brace ? "Brace Measurement" : "Plate Measurement") {
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
                    if TapDisplaySettings.measurementType != .brace {
                        let total = TapDisplaySettings.measureFlc ? 3 : 2
                        Text("Phase \(materialPhaseStep)/\(total)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
        case .capturingLongitudinal, .reviewingLongitudinal: return .blue
        case .capturingCross, .reviewingCross: return .orange
        case .waitingForFlcTap, .capturingFlc, .reviewingFlc: return .purple
        case .complete: return .green
        }
    }

    /// Step number for current material measurement phase
    var materialPhaseStep: Int {
        let isBrace = TapDisplaySettings.measurementType == .brace
        switch tap.materialTapPhase {
        case .notStarted, .capturingLongitudinal, .reviewingLongitudinal: return 1
        case .capturingCross, .reviewingCross: return 2
        case .waitingForFlcTap, .capturingFlc, .reviewingFlc: return 3
        case .complete: return isBrace ? 1 : (TapDisplaySettings.measureFlc ? 3 : 2)
        }
    }

    /// Icon for current material measurement phase
    var materialPhaseIcon: String {
        switch tap.materialTapPhase {
        case .notStarted: return "hand.tap"
        case .capturingLongitudinal: return "waveform"
        case .reviewingLongitudinal: return "checkmark.circle"
        case .capturingCross: return "waveform"
        case .reviewingCross: return "checkmark.circle"
        case .waitingForFlcTap: return "rotate.3d"
        case .capturingFlc: return "waveform"
        case .reviewingFlc: return "checkmark.circle"
        case .complete: return "checkmark.circle.fill"
        }
    }

    /// Title for current plate/brace measurement phase
    var materialPhaseTitle: String {
        let isBrace = TapDisplaySettings.measurementType == .brace
        switch tap.materialTapPhase {
        case .notStarted:
            return "Press \u{2018}New Tap\u{2019} to Begin"
        case .capturingLongitudinal:
            return isBrace ? "Step 1: Longitudinal (fL) Mode" : "Step 1: Longitudinal (L) Mode"
        case .reviewingLongitudinal:
            return "Review L Tap — Accept or Redo"
        case .capturingCross:
            return "Step 2: Cross-grain (C) Mode"
        case .reviewingCross:
            return "Review C Tap — Accept or Redo"
        case .waitingForFlcTap:
            return "C Captured \u{2014} Prepare for Step 3"
        case .capturingFlc:
            return "Step 3: FLC (Diagonal) Mode"
        case .reviewingFlc:
            return "Review FLC Tap — Accept or Redo"
        case .complete:
            return "Measurement Complete"
        }
    }

    /// Description for current plate/brace measurement phase
    var materialPhaseDescription: String {
        let isBrace = TapDisplaySettings.measurementType == .brace
        switch tap.materialTapPhase {
        case .notStarted:
            if isBrace {
                return "Press \u{2018}New Tap\u{2019} to begin the brace fL measurement."
            }
            let tapWord = TapDisplaySettings.measureFlc ? "three-tap" : "two-tap"
            return "Press \u{2018}New Tap\u{2019} to begin the \(tapWord) plate measurement process."
        case .capturingLongitudinal:
            if isBrace {
                return "Hold brace at 22% from one end along the length. Tap center."
            }
            return "Hold plate at 22% from one end along the length, near one long edge (not at the width node). Tap center."
        case .reviewingLongitudinal:
            return "L tap captured. Review the spectrum — press Accept to continue to the C tap, or Redo to re-capture."
        case .capturingCross:
            return "Hold plate at 22% from one end along the width, near one short edge (not at the length node). Tap center."
        case .reviewingCross:
            return "C tap captured. Review the spectrum — press Accept to continue, or Redo to re-capture."
        case .waitingForFlcTap:
            return "Cross-grain mode captured! Now hold plate at the midpoint of one long edge. Tap near the opposite corner (~22% from both sides) for FLC."
        case .capturingFlc:
            return "Hold plate at the midpoint of one long edge. Tap near the opposite corner (~22% from both the end and the side). Measures shear stiffness."
        case .reviewingFlc:
            return "FLC tap captured. Review the spectrum — press Accept to complete the measurement, or Redo to re-capture."
        case .complete:
            if isBrace {
                return "fL captured! Review the fL (blue) peak selection in the Results panel. Adjust if the auto-selection isn\u{2019}t correct."
            }
            let flcPart = TapDisplaySettings.measureFlc ? ", and FLC (purple)" : ""
            return "All modes captured! Review the L (blue), C (orange)\(flcPart) peak selections in the Results panel. Adjust if the auto-selection isn\u{2019}t correct."
        }
    }

}
