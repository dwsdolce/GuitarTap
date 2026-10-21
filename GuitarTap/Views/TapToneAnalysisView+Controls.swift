//
//  TapToneAnalysisView+Controls.swift
//  GuitarTap
//

/// # TapToneAnalysisView+Controls
///
/// Adaptive toolbar and tap-sequence control bar for `TapToneAnalysisView`.
///
/// ## Layout Strategy
///
/// The header and tap controls adapt to three form factors at runtime:
///
/// | Platform | Header | Tap Controls |
/// |---|---|---|
/// | iPhone (compact) | Icon-only button row | `compactTapControls` |
/// | iPhone landscape | Navigation bar items | `landscapeTapControls` |
/// | iPad | Navigation bar items | `regularTapControls` |
/// | macOS | `ViewThatFits` wide/medium/narrow variants | `regularTapControls` |
///
/// The macOS header uses `ViewThatFits` to automatically switch between a
/// wide single-row layout, a two-row medium layout, and an icon-only narrow
/// layout as the window is resized.
///
/// ## Tap Sequence Controls
///
/// `regularTapControls` and `compactTapControls` contain the New Tap, Cancel,
/// Taps stepper, Threshold slider, and Peak Min slider. The compact version
/// omits labels to fit narrow iPhone screens. The Hysteresis slider has been
/// moved to the Settings panel (`TapSettingsView`).
///
/// - SeeAlso: `TapToneAnalysisView+Layouts`, `TapToneAnalysisView+Actions`

import SwiftUI

extension TapToneAnalysisView {

    // MARK: - Subviews

    var headerView: some View {
        VStack(spacing: 12) {
            // Top row: Main controls - adaptive for iOS
            #if os(iOS)
            // On iOS the header is the iPhone's (the iPad shows its buttons in the navigation bar):
            // an icon-only button bar (all buttons except Start/Results/AutodB/Metrics/Settings, which are in the
            // nav bar)
            HStack(spacing: 8) {
                Spacer()

                Toggle(isOn: $crosshairMode) {
                    Image(systemName: crosshairMode ? "plus.viewfinder" : "dot.viewfinder")
                }
                .toggleStyle(.tinted(.accent))
                .accessibilityLabel("Crosshair")

                Button(action: { tap.cycleAnnotationVisibility() }) {
                    Image(systemName: tap.annotationVisibilityMode.iconName)
                }
                .buttonStyle(.tinted(.accent))
                .disabled((TapDisplaySettings.measurementType.isGuitar ? tap.peaksAbovePeakMin : tap.materialIdentifiedPeaks).isEmpty || tap.displayMode == .comparison)
                .help("Annotation visibility: \(tap.annotationVisibilityMode.label)")

                Button(action: { showingSaveSheet = true }) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.tinted(.accent))
                .disabled(!tap.hasResultToSaveOrExport)
                .accessibilityLabel("Save")
                .hint(HintText.save)

                Button(action: { showingMeasurements = true }) {
                    Image(systemName: "list.bullet.clipboard")
                }
                .buttonStyle(.tinted(.accent))
                .accessibilityLabel("Measurements")
                .hint(HintText.measurements)

                Spacer()
            }
            #else
            // macOS layout (unchanged)
            macosHeaderButtons
            #endif

            // Tap sequence controls (always visible, not just when running)
            #if os(iOS)
            compactTapControls
            #else
            // macOS uses regular controls
            regularTapControls
            #endif
        }
        .padding()
    }

    #if os(macOS)
    /// macOS button layout - adapts to narrow windows using ViewThatFits.
    @ViewBuilder
    var macosHeaderButtons: some View {
        ViewThatFits(in: .horizontal) {
            macosHeaderButtonRow(iconOnly: false, spacing: nil)       // Wide: single row, labeled
            macosHeaderButtonGrid(iconOnly: false, spacing: 8)        // Medium: two rows, labeled
            macosHeaderButtonGrid(iconOnly: true, spacing: 6)         // Narrow: two rows, icon-only
        }
    }

    /// Single-row macOS header button layout (wide window).
    @ViewBuilder
    private func macosHeaderButtonRow(iconOnly: Bool, spacing: CGFloat?) -> some View {
        HStack(spacing: spacing) {
            Spacer()
            macosPlayFileButton(iconOnly: iconOnly)
            macosAutoDBButton(iconOnly: iconOnly)
            macosAnnotationsButton(iconOnly: iconOnly)
            macosSaveButton(iconOnly: iconOnly)
            macosMeasurementsButton(iconOnly: iconOnly)
            macosMetricsButton(iconOnly: iconOnly)
            macosSettingsButton(iconOnly: iconOnly)
        }
    }

    /// Two-row macOS header button layout (medium/narrow window).
    @ViewBuilder
    private func macosHeaderButtonGrid(iconOnly: Bool, spacing: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: spacing) {
                Spacer()
                macosPlayFileButton(iconOnly: iconOnly)
                macosAutoDBButton(iconOnly: iconOnly)
                macosAnnotationsButton(iconOnly: iconOnly)
                macosSaveButton(iconOnly: iconOnly)
            }
            HStack(spacing: spacing) {
                macosMeasurementsButton(iconOnly: iconOnly)
                macosMetricsButton(iconOnly: iconOnly)
                macosSettingsButton(iconOnly: iconOnly)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func macosAutoDBButton(iconOnly: Bool) -> some View {
        let icon = isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle"
        Toggle(isOn: autoScaleBinding) {
            if iconOnly { Image(systemName: icon) } else { Label("Auto dB", systemImage: icon) }
        }
        .toggleStyle(.tinted(.accent))
        .hint(HintText.autoScale(isEnabled: isAutoScaleEnabled))
    }

    @ViewBuilder
    private func macosAnnotationsButton(iconOnly: Bool) -> some View {
        Button(action: { tap.cycleAnnotationVisibility() }) {
            if iconOnly {
                Image(systemName: tap.annotationVisibilityMode.iconName)
            } else {
                Label("Annotations", systemImage: tap.annotationVisibilityMode.iconName)
            }
        }
        .buttonStyle(.tinted(.accent))
        .disabled((TapDisplaySettings.measurementType.isGuitar ? tap.peaksAbovePeakMin : tap.materialIdentifiedPeaks).isEmpty || tap.displayMode == .comparison)
        .help("Annotation visibility: \(tap.annotationVisibilityMode.label)")
    }

    @ViewBuilder
    private func macosSaveButton(iconOnly: Bool) -> some View {
        Button(action: { showingSaveSheet = true }) {
            if iconOnly { Image(systemName: "square.and.arrow.down") } else { Label("Save", systemImage: "square.and.arrow.down") }
        }
        .buttonStyle(.tinted(.accent))
        .disabled(!tap.isMeasurementComplete && tap.displayMode != .comparison)
        .hint(HintText.save)
    }

    @ViewBuilder
    private func macosMeasurementsButton(iconOnly: Bool) -> some View {
        Button(action: { showingMeasurements = true }) {
            if iconOnly {
                Image(systemName: "list.bullet.clipboard")
            } else {
                Label("Measurements", systemImage: "list.bullet.clipboard")
            }
        }
        .buttonStyle(.tinted(.accent))
        .hint(HintText.measurements)
    }

    @ViewBuilder
    private func macosMetricsButton(iconOnly: Bool) -> some View {
        Button(action: { showingMetrics = true }) {
            if iconOnly { Image(systemName: "chart.bar") } else { Label("Metrics", systemImage: "chart.bar") }
        }
        .buttonStyle(.tinted(.accent))
        .hint(HintText.showMetrics)
    }

    @ViewBuilder
    private func macosSettingsButton(iconOnly: Bool) -> some View {
        Button(action: { showingSettings = true }) {
            if iconOnly { Image(systemName: "gearshape") } else { Label("Settings", systemImage: "gearshape") }
        }
        .buttonStyle(.tinted(.accent))
        .hint(HintText.settings)
    }

    @ViewBuilder
    private func macosPlayFileButton(iconOnly: Bool) -> some View {
        Button(action: { showingPlayFileSheet = true }) {
            if iconOnly {
                Image(systemName: "waveform.badge.plus")
            } else {
                Label("Play File\u{2026}", systemImage: "waveform.badge.plus")
            }
        }
        .buttonStyle(.tinted(fft.isPlayingFile ? .statusPlayingFile : .accent))
        // A file plays while the audio engine runs, as every edition's.
        .disabled(!fft.isRunning)
        .help("Feed an audio file through the analysis pipeline (for cross-platform comparison)")
    }
    #endif

    /// The status bar's level: the frame's peak magnitude for a guitar, its readout level for a plate or brace.
    func frameLevelText(_ frame: LiveFrame) -> Text {
        Text("\(FieldPrecision.string(TapDisplaySettings.measurementType.isGuitar ? frame.peakMagnitude : frame.displayLevelDB, FieldPrecision.peakMagnitudeDB)) dB")
    }

    /// The status bar's peak readout: the frame's loudest bin.
    func framePeakText(_ frame: LiveFrame) -> Text {
        Text("Peak: \(FieldPrecision.string(frame.peakMagnitude, FieldPrecision.peakMagnitudeDB)) dB @ \(FieldPrecision.string(frame.peakFrequency, FieldPrecision.peakFrequencyHz)) Hz")
    }

    /// Fixed status bar at bottom of screen
    @ViewBuilder
    var statusBarView: some View {
        #if os(iOS)
        if useCompactLayout {
            // Compact iPhone status bar - fixed height, essential info only
            compactStatusBar
        } else {
            fullStatusBar
        }
        #else
        fullStatusBar
        #endif
    }

    /// Compact status bar for iPhone - fixed height
    @ViewBuilder
    var compactStatusBar: some View {
        HStack(spacing: 8) {
            if tap.displayMode == .comparison {
                // Comparison mode: show count and clear affordance.
                // Warning (if active) is shown in fullStatusBar above this row.
                Image(systemName: "waveform.path")
                    .foregroundColor(Palette.color(.accentText))
                    .font(.caption)
                Text(tap.showingMultiTapComparison
                     ? "Tap comparison — \(tap.tapEntries.count) taps + averaged"
                     : "Comparing \(tap.comparisonSpectra.count) measurements")
                    .font(.caption)
                    .foregroundColor(Palette.color(.textPrimary))
                    .lineLimit(1)
                Spacer()
                Text(tap.showingMultiTapComparison ? "Tap \u{2018}Taps\u{2019} to exit" : "\u{2018}New Tap\u{2019} for new measurement")
                    .font(.caption)
                    .foregroundColor(Palette.color(.textSecondary))
            } else if tap.showLoadedSettingsWarning {
                // Warn that threshold and tap count came from a loaded measurement.
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Palette.color(.statusWarning))
                    .font(.caption)
                    .opacity(warningIconOpacity)
                Text("Loaded settings — Threshold: \(Int(tap.tapDetectionThreshold)) dB · Taps: \(tap.numberOfTaps)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(Palette.color(.statusWarning))
                    .lineLimit(1)
                Spacer()
            } else {
                // Normal tap detection state
                Circle()
                    .fill(Palette.color(tap.isMeasurementComplete ? .statusComplete : .statusInactiveDot))
                    .frame(width: 10, height: 10)

                Text(tap.isMeasurementComplete ? "Tap Detected!" : "Waiting for tap...")
                    .font(.caption)
                    .foregroundColor(Palette.color(tap.isMeasurementComplete ? .statusTapDetected : .textSecondary))
                    .lineLimit(1)

                FrameReader(frame: fft.frame) { frame in frameLevelText(frame) }
                    .font(.caption)
                    .foregroundColor(Palette.color(.textSecondary))
                    .lineLimit(1)

                // For plate/brace: show step from phase 1 (consistent with all phases).
                // For guitar: keep existing currentTapCount > 0 guard (no phase concept).
                let isPlate = TapDisplaySettings.measurementType == .plate || TapDisplaySettings.measurementType == .brace
                if tap.isDetecting && (isPlate || tap.currentTapCount > 0) {
                    let totalPhases = TapDisplaySettings.measureFlc ? 3 : 2
                    let phaseLabel = TapDisplaySettings.measurementType == .plate
                        ? (tap.numberOfTaps > 1
                            ? "Phase \(materialPhaseStep)/\(totalPhases) · Tap \(max(0, tap.currentTapCount - (materialPhaseStep - 1) * tap.numberOfTaps))/\(tap.numberOfTaps)"
                            : "Phase \(materialPhaseStep)/\(totalPhases)")
                        : "Tap \(tap.currentTapCount)/\(tap.numberOfTaps)"
                    Text(phaseLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Palette.color(.statusTapCount))
                        .lineLimit(1)
                }

                // The BAR is gated on the tap COUNT ONLY — deliberately NOT on isDetecting, and so
                // deliberately NOT inside the label's `if` above. isDetecting drops for the 0.5 s
                // per-tap cooldown (scheduleGuitarReEnable), so sharing the label's gate made the bar
                // blink out after every tap. Keyed on the count, it appears on the first tap and stays
                // up for the whole measurement; New Tap / Cancel reset the count and clear it.
                // This matches `fullStatusBar`, which already gates its bar on `currentTapCount > 0`.
                if tap.currentTapCount > 0 {
                    ProgressView(value: tap.tapProgress)
                        .progressViewStyle(.linear)
                        .tint(Palette.color(.statusProgress)) // see the note on the fullStatusBar bar
                        .frame(width: 50)
                }

                Spacer()

                if fft.isRunning {
                    FrameReader(frame: fft.frame) { frame in framePeakText(frame) }
                        .font(.caption)
                        .foregroundColor(Palette.color(.statusPeakReadout))
                        .lineLimit(1)
                }

                if tap.isMeasurementComplete {
                    Image(systemName: "pause.circle.fill")
                        .foregroundColor(Palette.color(.statusWarning))
                        .font(.caption)
                }

                Circle()
                    .fill(Palette.color(fft.isRunning ? .statusRunning : .statusError))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .frame(height: 28) // Fixed height
        .background {
            Palette.color(.backgroundSubtle)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Full status bar for iPad and macOS
    @ViewBuilder
    var fullStatusBar: some View {
        VStack(spacing: 6) {
            // Warn that threshold and tap count came from a loaded measurement.
            // Suppressed during saved-measurement comparison (the comparison panel replaces
            // this context entirely). Shown during multi-tap comparison because the loaded
            // settings still apply to any new tap the user might take.
            let isSavedComparison = tap.displayMode == .comparison && !tap.showingMultiTapComparison
            if tap.showLoadedSettingsWarning && !isSavedComparison {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Palette.color(.statusWarning))
                        .font(.subheadline)
                        .opacity(warningIconOpacity)
                    Text("Settings from loaded measurement — Threshold: \(Int(tap.tapDetectionThreshold)) dB · Taps: \(tap.numberOfTaps)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Palette.color(.statusWarning))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Palette.color(.statusWarning, opacity: .statusMessageBackground))
                .cornerRadius(6)
            }
            // Dump Capture Audio wrote this measurement's WAV — shown so a setting left on is noticed.
            if let saved = tap.captureAudioSaved {
                HStack(spacing: 8) {
                    Text("Capture audio saved: \(saved) (\(WavDumpFolder.currentFolder.lastPathComponent))")
                        .font(.subheadline)
                        .foregroundColor(Palette.color(.statusSaved))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button { tap.dismissCaptureAudioSaved() } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.icon())
                    .help("Dismiss")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Palette.color(.statusSaved, opacity: .statusMessageBackground))
                .cornerRadius(6)
            }
            if tap.displayMode == .comparison {
                // Comparison mode: show comparison info below the warning (if any)
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path")
                        .foregroundColor(Palette.color(.accentText))
                    Text(tap.showingMultiTapComparison
                         ? "Tap comparison — \(tap.tapEntries.count) taps + averaged"
                         : "Comparing \(tap.comparisonSpectra.count) measurements")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(tap.showingMultiTapComparison
                         ? "Press \u{2018}Taps\u{2019} to return to averaged view, or \u{2018}New Tap\u{2019} for a new measurement"
                         : "Press \u{2018}New Tap\u{2019} for a new measurement")
                        .font(.caption)
                        .foregroundColor(Palette.color(.textSecondary))
                }
            } else {
                // Normal tap detection state
                if tap.currentTapCount > 0 {
                    // Tinted EXPLICITLY rather than left to inherit the accent colour: untinted, a
                    // The bar and its labels take the status.progress role, as Python and the web do.
                    ProgressView(value: tap.tapProgress)
                        .progressViewStyle(.linear)
                        .tint(Palette.color(.statusProgress))
                }

                HStack(spacing: 12) {
                    Circle()
                        .fill(Palette.color(tap.isMeasurementComplete ? .statusComplete : .statusInactiveDot))
                        .frame(width: 10, height: 10)

                    Text(tap.isMeasurementComplete ? "Tap Detected!" : "Waiting for tap...")
                        .font(.subheadline)
                        .foregroundColor(Palette.color(tap.isMeasurementComplete ? .statusTapDetected : .textSecondary))

                    Text("•")
                        .foregroundColor(Palette.color(.textSecondary))

                    FrameReader(frame: fft.frame) { frame in frameLevelText(frame) }
                        .font(.subheadline)
                        .foregroundColor(Palette.color(.textSecondary))

                    Spacer()

                    if tap.isMeasurementComplete {
                        HStack(spacing: 4) {
                            Image(systemName: "pause.circle.fill")
                                .foregroundColor(Palette.color(.statusWarning))
                            Text("Complete")
                                .font(.caption)
                                .foregroundColor(Palette.color(.statusWarning))
                        }
                        Text("•")
                            .font(.caption)
                            .foregroundColor(Palette.color(.textSecondary))
                    }

                    if fft.isRunning {
                        FrameReader(frame: fft.frame) { frame in framePeakText(frame) }
                            .font(.caption)
                            .foregroundColor(Palette.color(.statusPeakReadout))
                    } else {
                        Text(fft.notRunningMessage)
                            .font(.caption)
                            .foregroundColor(Palette.color(.textSecondary))
                    }

                    Circle()
                        .fill(Palette.color(tap.isDetecting ? .statusRunning : .statusPaused))
                        .frame(width: 8, height: 8)

                    Text(tap.statusMessage)
                        .font(.caption)
                        .foregroundColor(Palette.color(tap.isDetecting ? .textPrimary : .statusWarning))

                    // For plate/brace: show step from phase 1 (consistent with all phases).
                    // For guitar: keep existing currentTapCount > 0 guard (no phase concept).
                    let isPlateOrBrace = TapDisplaySettings.measurementType == .plate || TapDisplaySettings.measurementType == .brace
                    if tap.isDetecting && (isPlateOrBrace || tap.currentTapCount > 0) {
                        let totalPhases = TapDisplaySettings.measureFlc ? 3 : 2
                        let phaseLabel = TapDisplaySettings.measurementType == .plate
                            ? (tap.numberOfTaps > 1
                                ? "Phase \(materialPhaseStep)/\(totalPhases) · Tap \(max(0, tap.currentTapCount - (materialPhaseStep - 1) * tap.numberOfTaps))/\(tap.numberOfTaps)"
                                : "Phase \(materialPhaseStep)/\(totalPhases)")
                            : "Tap \(tap.currentTapCount)/\(tap.numberOfTaps)"
                        Text(phaseLabel)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(Palette.color(.statusTapCount))
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Palette.color(.backgroundSubtle))
    }

    /// The tap count, drawn before its stepper in every layout.
    var tapCountText: some View {
        Text("\(tap.numberOfTaps)")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(Palette.color(.textPrimary))
            .frame(minWidth: 16)
    }

    /// Reset button for the tap-detection threshold slider.
    @ViewBuilder
    var thresholdResetButton: some View {
        Button(action: {
            tapToneAnalyzer.tapDetectionThreshold = TapDisplaySettings.defaultTapDetectionThreshold
            TapDisplaySettings.tapDetectionThreshold = TapDisplaySettings.defaultTapDetectionThreshold
        }) {
            Image(systemName: "arrow.counterclockwise")
                .font(.caption2)
                .foregroundColor(Palette.color(.textSecondary))
        }
        .buttonStyle(.plain)
        .help("Reset to default")
    }

    /// Reset button for the peak-minimum threshold slider.
    @ViewBuilder
    var peakMinResetButton: some View {
        Button(action: {
            tapToneAnalyzer.peakMinThreshold = TapDisplaySettings.defaultPeakMinThreshold
            TapDisplaySettings.peakMinThreshold = TapDisplaySettings.defaultPeakMinThreshold
        }) {
            Image(systemName: "arrow.counterclockwise")
                .font(.caption2)
                .foregroundColor(Palette.color(.textSecondary))
        }
        .buttonStyle(.plain)
        .help("Reset to default")
    }

    /// Compact tap controls for iPhone
    @ViewBuilder
    var compactTapControls: some View {
        VStack(spacing: 8) {
            // Row 1: Taps and threshold
            VStack(spacing: 8) {
                HStack {
                    Text("Taps:")
                        .font(.caption)
                        .foregroundColor(Palette.color(.textSecondary))

                    HStack(spacing: 4) {
                        tapCountText
                        Stepper("",
                                value: $tapToneAnalyzer.numberOfTaps,
                                in: 1...10)
                            .tint(Palette.color(.accent))
                            .labelsHidden()
                            .accessibilityLabel("Number of taps: \(tap.numberOfTaps)")
                    }
                    .disabledDimmed(tapCountLocked)
                    .hint(HintText.taps)

                    Spacer()
                }

                // Tap detection threshold slider — controls the RMS rising-edge
                // trigger level used to detect taps in all measurement modes.
                HStack(spacing: 6) {
                    Text("Threshold:")
                        .font(.caption)
                        .foregroundColor(Palette.color(.textSecondary))
                        .fixedSize()
                    ThresholdSlider(
                        value: $tapToneAnalyzer.tapDetectionThreshold,
                        inputLevel: tap.fftAnalyzer.level,
                        range: -80...(-20)
                    )
                        .frame(minWidth: 160)
                        .accessibilityLabel("Tap detection threshold")
                        .hint(HintText.threshold)

                    Text("\(Int(tap.tapDetectionThreshold)) dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Palette.color(.accentText))
                        .fixedSize()
                    thresholdResetButton
                }

                HStack(spacing: 6) {
                    Text("Peak Min:")
                        .font(.caption)
                        .foregroundColor(Palette.color(.textSecondary))
                        .fixedSize()
                    Slider(value: $tapToneAnalyzer.peakMinThreshold, in: -100...(-20), step: 1)
                        .tint(Palette.color(.accent))
                        .accessibilityLabel("Peak detection minimum threshold")
                        .hint(HintText.peakMin)

                    Text("\(Int(tap.peakMinThreshold)) dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Palette.color(.chartPeakMin))
                        .fixedSize()
                    peakMinResetButton
                }
                .notApplicableDimmed(!TapDisplaySettings.measurementType.isGuitar || tap.displayMode == .comparison)
            }

            // Row 2: Action buttons - all buttons always visible to prevent layout shifts
            HStack(spacing: 8) {
                // New Tap button — also available mid-sequence to start over
                Button(action: {
                    tap.requestStartTapSequence()
                }) {
                    Label("New Tap", systemImage: "hand.tap")
                        .font(.subheadline)
                }
                .buttonStyle(.prominent())
                .disabled(newTapButtonDisabled)
                .hint(HintText.newTap)

                // Pause/Resume button — becomes "Accept" during plate/brace review phases
                Button(action: {
                    if isInReviewPhase {
                        tapToneAnalyzer.acceptCurrentPhase()
                    } else if tap.isDetectionPaused {
                        tapToneAnalyzer.resumeTapDetection()
                    } else {
                        tapToneAnalyzer.pauseTapDetection()
                    }
                }) {
                    if isInReviewPhase {
                        Label("Accept", systemImage: "checkmark.circle")
                            .font(.subheadline)
                    } else {
                        Label(
                            tap.isDetectionPaused ? "Resume" : "Pause",
                            systemImage: tap.isDetectionPaused ? "play.circle" : "pause.circle"
                        )
                        .font(.subheadline)
                    }
                }
                .buttonStyle(.tinted(isInReviewPhase ? .statusComplete : .accent))
                .disabled(!pauseResumeButtonEnabled)
                .hint(isInReviewPhase ? "Accept this tap and continue" :
                      tap.isDetectionPaused ? HintText.resumeDetection : HintText.pauseDetection)

                // Cancel button — becomes "Redo" during plate/brace review phases
                Button(action: {
                    if isInReviewPhase {
                        tapToneAnalyzer.redoCurrentPhase()
                    } else {
                        tap.cancelTapSequence()
                    }
                }) {
                    let (label, icon) = redoOrCancelLabel
                    Label(label, systemImage: icon)
                        .font(.subheadline)
                }
                .buttonStyle(.tinted(cancelButtonEnabled ? .statusWarning : .toolbarInactive))
                .disabled(!cancelButtonEnabled)
                .hint(isInReviewPhase ? "Redo this tap phase" : HintText.cancel)
            }
        }
        .padding(12)
        .background(Palette.color(.backgroundSubtle))
        .cornerRadius(8)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Returns the (label, systemImage) for the Cancel/Redo button based on current phase.
    var redoOrCancelLabel: (String, String) {
        switch tap.materialTapPhase {
        case .reviewingLongitudinal: return ("Redo L", "arrow.counterclockwise")
        case .reviewingCross:        return ("Redo C", "arrow.counterclockwise")
        case .reviewingFlc:          return ("Redo FLC", "arrow.counterclockwise")
        default:                     return ("Cancel", "xmark.circle")
        }
    }

    /// Regular tap controls for iPad and macOS.
    /// Uses vertical size class to distinguish landscape (compact) from portrait (regular) on iPad.
    @ViewBuilder
    var regularTapControls: some View {
        Group {
            #if os(iOS)
            // Wide single-row layout in landscape; narrow two-row in portrait.
            // isLandscape is kept current via a GeometryReader at the call site.
            if isLandscape || verticalSizeClass == .compact {
                regularTapControlsWide
            } else {
                regularTapControlsNarrow
            }
            #else
            regularTapControlsWide
            #endif
        }
        .padding(12)
        .background(Palette.color(.backgroundSubtle))
        .cornerRadius(8)
    }

    /// Wide layout for regular tap controls - all in one row
    @ViewBuilder
    var regularTapControlsWide: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("Taps:")
                    .font(.caption)
                    .foregroundColor(Palette.color(.textSecondary))

                tapCountText

                Stepper("",
                        value: $tapToneAnalyzer.numberOfTaps,
                        in: 1...10)
                    .tint(Palette.color(.accent))
                    .labelsHidden()
            }
            .disabledDimmed(tapCountLocked)
            .hint(HintText.taps)

            PaletteDivider()
                .frame(height: 20)

            // Tap detection threshold slider — controls the RMS rising-edge
            // trigger level used to detect taps in all measurement modes.
            HStack(spacing: 4) {
                Text("Threshold:")
                    .font(.caption)
                    .foregroundColor(Palette.color(.textSecondary))
                    .fixedSize()
                ThresholdSlider(
                    value: $tapToneAnalyzer.tapDetectionThreshold,
                    inputLevel: tap.fftAnalyzer.level,
                    range: -80...(-20)
                )
                    .frame(width: 160)
                    .accessibilityLabel("Tap detection threshold")

                Text("\(Int(tap.tapDetectionThreshold)) dB")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(Palette.color(.accentText))
                    .fixedSize()
                thresholdResetButton
            }
            .hint(HintText.threshold)

            PaletteDivider()
                .frame(height: 20)

            HStack(spacing: 4) {
                Text("Peak Min:")
                    .font(.caption)
                    .foregroundColor(Palette.color(.textSecondary))
                    .fixedSize()
                Slider(value: $tapToneAnalyzer.peakMinThreshold, in: -100...(-20), step: 1)
                    .tint(Palette.color(.accent))
                    .frame(width: 80)
                    .accessibilityLabel("Peak detection minimum threshold")
                    .hint(HintText.peakMin)

                Text("\(Int(tap.peakMinThreshold)) dB")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(Palette.color(.chartPeakMin))
                    .fixedSize()
                peakMinResetButton
            }
            .notApplicableDimmed(!TapDisplaySettings.measurementType.isGuitar || tap.displayMode == .comparison)

            Spacer()

            // Tap sequence buttons — also available mid-sequence (plate/brace) to start over
            Button(action: {
                tap.requestStartTapSequence()
            }) {
                Label("New Tap", systemImage: "hand.tap")
            }
            .buttonStyle(.prominent())
            .disabled(newTapButtonDisabled)
            .hint(HintText.newTap)

            // Pause/Resume button — becomes "Accept" during plate/brace review phases
            Button(action: {
                if isInReviewPhase {
                    tapToneAnalyzer.acceptCurrentPhase()
                } else if tap.isDetectionPaused {
                    tapToneAnalyzer.resumeTapDetection()
                } else {
                    tapToneAnalyzer.pauseTapDetection()
                }
            }) {
                if isInReviewPhase {
                    Label("Accept", systemImage: "checkmark.circle")
                } else {
                    Label(
                        tap.isDetectionPaused ? "Resume" : "Pause",
                        systemImage: tap.isDetectionPaused ? "play.circle" : "pause.circle"
                    )
                }
            }
            .buttonStyle(.tinted(isInReviewPhase ? .statusComplete : .accent))
            .disabled(!pauseResumeButtonEnabled)
            .hint(isInReviewPhase ? "Accept this tap and continue" :
                  tap.isDetectionPaused ? HintText.resumeDetection : HintText.pauseDetection)

            // Cancel/Redo button — becomes "Redo [phase]" during plate/brace review phases
            Button(action: {
                if isInReviewPhase {
                    tapToneAnalyzer.redoCurrentPhase()
                } else {
                    tap.cancelTapSequence()
                }
            }) {
                let (label, icon) = redoOrCancelLabel
                Label(label, systemImage: icon)
            }
            .buttonStyle(.tinted(cancelButtonEnabled ? .statusWarning : .toolbarInactive))
            .disabled(!cancelButtonEnabled)
            .hint(isInReviewPhase ? "Redo this tap phase" : HintText.cancel)
        }
    }

    /// Narrow layout for regular tap controls - two rows
    @ViewBuilder
    var regularTapControlsNarrow: some View {
        VStack(spacing: 8) {
            // Row 1: Sliders and settings
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Taps:")
                        .font(.caption)
                        .foregroundColor(Palette.color(.textSecondary))

                    tapCountText

                    Stepper("",
                            value: $tapToneAnalyzer.numberOfTaps,
                            in: 1...10)
                        .tint(Palette.color(.accent))
                        .labelsHidden()
                }
                .disabledDimmed(tapCountLocked)
                .hint(HintText.taps)

                PaletteDivider()
                    .frame(height: 20)

                // Tap detection threshold slider — controls the RMS rising-edge
                // trigger level used to detect taps in all measurement modes.
                HStack(spacing: 4) {
                    Text("Threshold:")
                        .font(.caption)
                        .foregroundColor(Palette.color(.textSecondary))
                        .fixedSize()
                    ThresholdSlider(
                        value: $tapToneAnalyzer.tapDetectionThreshold,
                        inputLevel: tap.fftAnalyzer.level,
                        range: -80...(-20)
                    )
                        .frame(width: 160)
                        .accessibilityLabel("Tap detection threshold")

                    Text("\(Int(tap.tapDetectionThreshold)) dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Palette.color(.accentText))
                        .fixedSize()
                    thresholdResetButton
                }
                .hint(HintText.threshold)

                PaletteDivider()
                    .frame(height: 20)

                // Peak Min slider — minimum spectral magnitude for peak annotation.
                HStack(spacing: 4) {
                    Text("Peak Min:")
                        .font(.caption)
                        .foregroundColor(Palette.color(.textSecondary))
                        .fixedSize()
                    Slider(value: $tapToneAnalyzer.peakMinThreshold, in: -100...(-20), step: 1)
                        .tint(Palette.color(.accent))
                        .frame(width: 80)
                        .accessibilityLabel("Peak detection minimum threshold")

                    Text("\(Int(tap.peakMinThreshold)) dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Palette.color(.chartPeakMin))
                        .fixedSize()
                    peakMinResetButton
                }
                .notApplicableDimmed(!TapDisplaySettings.measurementType.isGuitar || tap.displayMode == .comparison)

                Spacer()
            }

            // Row 2: Action buttons (right-justified)
            HStack(spacing: 8) {
                Spacer()

                // Tap sequence buttons — also available mid-sequence (plate/brace) to start over
                Button(action: {
                    tap.requestStartTapSequence()
                }) {
                    Label("New Tap", systemImage: "hand.tap")
                }
                .buttonStyle(.prominent())
                .disabled(newTapButtonDisabled)
                .hint(HintText.newTap)

                // Pause/Resume button — becomes "Accept" during plate/brace review phases
                Button(action: {
                    if isInReviewPhase {
                        tapToneAnalyzer.acceptCurrentPhase()
                    } else if tap.isDetectionPaused {
                        tapToneAnalyzer.resumeTapDetection()
                    } else {
                        tapToneAnalyzer.pauseTapDetection()
                    }
                }) {
                    if isInReviewPhase {
                        Label("Accept", systemImage: "checkmark.circle")
                    } else {
                        Label(
                            tap.isDetectionPaused ? "Resume" : "Pause",
                            systemImage: tap.isDetectionPaused ? "play.circle" : "pause.circle"
                        )
                    }
                }
                .buttonStyle(.tinted(isInReviewPhase ? .statusComplete : .accent))
                .disabled(!pauseResumeButtonEnabled)
                .hint(isInReviewPhase ? "Accept this tap and continue" :
                      tap.isDetectionPaused ? HintText.resumeDetection : HintText.pauseDetection)

                // Cancel/Redo button — becomes "Redo [phase]" during plate/brace review phases
                Button(action: {
                    if isInReviewPhase {
                        tapToneAnalyzer.redoCurrentPhase()
                    } else {
                        tap.cancelTapSequence()
                    }
                }) {
                    let (label, icon) = redoOrCancelLabel
                    Label(label, systemImage: icon)
                }
                .buttonStyle(.tinted(cancelButtonEnabled ? .statusWarning : .toolbarInactive))
                .disabled(!cancelButtonEnabled)
                .hint(isInReviewPhase ? "Redo this tap phase" : HintText.cancel)
            }
        }
    }
}
