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
/// | iPad | Two-row labeled buttons (`ipadHeaderButtons`) | `regularTapControls` |
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
            if useCompactLayout {
                // iPhone portrait: icon-only button bar (all buttons except Start/Results/AutodB/Metrics/Settings which are in the nav bar)
                HStack(spacing: 8) {
                    Spacer()

                    Toggle(isOn: $crosshairMode) {
                        Image(systemName: crosshairMode ? "plus.viewfinder" : "dot.viewfinder")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .pointerHoverFill()
                    .tint(Palette.color(crosshairMode ? .accent : .toolbarInactive))
                    .accessibilityLabel("Crosshair")

                    Button(action: { tap.cycleAnnotationVisibility() }) {
                        Image(systemName: tap.annotationVisibilityMode.iconName)
                    }
                    .buttonStyle(.tintedBordered)
                    .tint(Palette.color(.accent))
                    .disabled((TapDisplaySettings.measurementType.isGuitar ? tap.peaksAbovePeakMin : tap.materialIdentifiedPeaks).isEmpty || tap.displayMode == .comparison)
                    .help("Annotation visibility: \(tap.annotationVisibilityMode.label)")

                    Button(action: { showingSaveSheet = true }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(.tintedBordered)
                    .disabled(!tap.hasResultToSaveOrExport)
                    .accessibilityLabel("Save")
                    .hint(HintText.save)

                    Button(action: { showingMeasurements = true }) {
                        Image(systemName: "list.bullet.clipboard")
                    }
                    .buttonStyle(.tintedBordered)
                    .accessibilityLabel("Measurements")
                    .hint(HintText.measurements)

                    Spacer()
                }
            } else {
                // Regular layout for iPad
                ipadHeaderButtons
            }
            #else
            // macOS layout (unchanged)
            macosHeaderButtons
            #endif

            // Tap sequence controls (always visible, not just when running)
            #if os(iOS)
            if useCompactLayout {
                // Compact tap controls for iPhone
                compactTapControls
            } else {
                // Regular tap controls for iPad
                regularTapControls
            }
            #else
            // macOS uses regular controls
            regularTapControls
            #endif
        }
        .padding()
    }

    #if os(iOS)
    /// iPad button layout - full labels in two rows
    @ViewBuilder
    var ipadHeaderButtons: some View {
        VStack(spacing: 8) {
            // Row 1: Primary controls
            HStack(spacing: 8) {
                Spacer()

                // Results button - only shown when not in horizontal layout (where results are always visible)
                if !isIPadHorizontal {
                    Button(action: { showResults() }) {
                        Label("Results", systemImage: "doc.text")
                    }
                    .buttonStyle(.tintedBordered)
                    .hint(HintText.showResults)
                }

                // Auto-scale dB toggle button (iPad)
                Toggle(isOn: autoScaleBinding) {
                    Label("Auto dB", systemImage: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .pointerHoverFill()
                .tint(Palette.color(.accent))
                .hint(HintText.autoScale(isEnabled: isAutoScaleEnabled))

                // Crosshair mode toggle button (iPad)
                Toggle(isOn: $crosshairMode) {
                    Label("Crosshair", systemImage: crosshairMode ? "plus.viewfinder" : "dot.viewfinder")
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .pointerHoverFill()
                .tint(Palette.color(crosshairMode ? .accent : .toolbarInactive))

                // Annotation visibility cycling button (iPad)
                Button(action: { tap.cycleAnnotationVisibility() }) {
                    Label("Annotations", systemImage: tap.annotationVisibilityMode.iconName)
                }
                .buttonStyle(.tintedBordered)
                .tint(Palette.color(.accent))
                .disabled((TapDisplaySettings.measurementType.isGuitar ? tap.peaksAbovePeakMin : tap.materialIdentifiedPeaks).isEmpty || tap.displayMode == .comparison)
                .help("Annotation visibility: \(tap.annotationVisibilityMode.label)")

                // Save button
                Button(action: { showingSaveSheet = true }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.tintedBordered)
                .tint(Palette.color(.accent))
                .disabled(!tap.isMeasurementComplete && tap.displayMode != .comparison)
                .hint(HintText.save)
            }

            // Row 2: Secondary controls
            HStack(spacing: 8) {
                // Measurements button
                Button(action: { showingMeasurements = true }) {
                    Label("Measurements", systemImage: "list.bullet.clipboard")
                }
                .buttonStyle(.tintedBordered)
                .tint(Palette.color(.accent))
                .hint(HintText.measurements)

                // Metrics button
                Button(action: { showingMetrics = true }) {
                    Label("Metrics", systemImage: "chart.bar")
                }
                .buttonStyle(.tintedBordered)
                .tint(Palette.color(.accent))
                .hint(HintText.showMetrics)

                // Settings button
                Button(action: { showingSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.tintedBordered)
                .tint(Palette.color(.accent))
                .hint(HintText.settings)

                // Play File button
                Button(action: { showingPlayFileSheet = true }) {
                    Label("Play File\u{2026}", systemImage: "waveform.badge.plus")
                }
                .buttonStyle(.tintedBordered)
                .tint(Palette.color(fft.isPlayingFile ? .statusPlayingFile : .accent))
                // A file plays while the audio engine runs, as every edition's: not before it has
                // started, nor when the microphone is refused or cannot be opened.
                .disabled(!fft.isRunning)
                .help("Feed an audio file through the analysis pipeline")

                Spacer()
            }
        }
    }
    #endif

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
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .pointerHoverFill()
        .tint(Palette.color(.accent))
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
        .buttonStyle(.tintedBordered)
        .tint(Palette.color(.accent))
        .disabled((TapDisplaySettings.measurementType.isGuitar ? tap.peaksAbovePeakMin : tap.materialIdentifiedPeaks).isEmpty || tap.displayMode == .comparison)
        .help("Annotation visibility: \(tap.annotationVisibilityMode.label)")
    }

    @ViewBuilder
    private func macosSaveButton(iconOnly: Bool) -> some View {
        Button(action: { showingSaveSheet = true }) {
            if iconOnly { Image(systemName: "square.and.arrow.down") } else { Label("Save", systemImage: "square.and.arrow.down") }
        }
        .buttonStyle(.tintedBordered)
        .tint(Palette.color(.accent))
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
        .buttonStyle(.tintedBordered)
        .tint(Palette.color(.accent))
        .hint(HintText.measurements)
    }

    @ViewBuilder
    private func macosMetricsButton(iconOnly: Bool) -> some View {
        Button(action: { showingMetrics = true }) {
            if iconOnly { Image(systemName: "chart.bar") } else { Label("Metrics", systemImage: "chart.bar") }
        }
        .buttonStyle(.tintedBordered)
        .tint(Palette.color(.accent))
        .hint(HintText.showMetrics)
    }

    @ViewBuilder
    private func macosSettingsButton(iconOnly: Bool) -> some View {
        Button(action: { showingSettings = true }) {
            if iconOnly { Image(systemName: "gearshape") } else { Label("Settings", systemImage: "gearshape") }
        }
        .buttonStyle(.tintedBordered)
        .tint(Palette.color(.accent))
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
        .buttonStyle(.tintedBordered)
        .tint(Palette.color(fft.isPlayingFile ? .statusPlayingFile : .accent))
        // A file plays while the audio engine runs, as every edition's.
        .disabled(!fft.isRunning)
        .help("Feed an audio file through the analysis pipeline (for cross-platform comparison)")
    }
    #endif

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

                Text("\(FieldPrecision.string(TapDisplaySettings.measurementType.isGuitar ? fft.peakMagnitude : fft.displayLevelDB, FieldPrecision.peakMagnitudeDB)) dB")
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
                    Text("Peak: \(FieldPrecision.string(fft.peakMagnitude, FieldPrecision.peakMagnitudeDB)) dB @ \(FieldPrecision.string(fft.peakFrequency, FieldPrecision.peakFrequencyHz)) Hz")
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
                    .buttonStyle(.borderless)
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

                    Text("\(FieldPrecision.string(TapDisplaySettings.measurementType.isGuitar ? fft.peakMagnitude : fft.displayLevelDB, FieldPrecision.peakMagnitudeDB)) dB")
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
                        Text("Peak: \(FieldPrecision.string(fft.peakMagnitude, FieldPrecision.peakMagnitudeDB)) dB @ \(FieldPrecision.string(fft.peakFrequency, FieldPrecision.peakFrequencyHz)) Hz")
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

                    Stepper("\(tap.numberOfTaps)",
                            value: $tapToneAnalyzer.numberOfTaps,
                            in: 1...10)
                        .disabledDimmed(tapCountLocked)
                        .frame(maxWidth: 120)
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
                .buttonStyle(.borderedProminent)
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
                .buttonStyle(.tintedBordered)
                .tint(isInReviewPhase ? Palette.color(.statusComplete) : nil)
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
                        .foregroundStyle(Palette.color(cancelButtonEnabled ? .statusWarning : .toolbarInactive))
                }
                .buttonStyle(.tintedBordered)
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

                Text("\(tap.numberOfTaps)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(Palette.color(.textPrimary))
                    .frame(minWidth: 16)

                Stepper("",
                        value: $tapToneAnalyzer.numberOfTaps,
                        in: 1...10)
                    .labelsHidden()
            }
            .disabledDimmed(tapCountLocked)
            .hint(HintText.taps)

            Divider()
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

            Divider()
                .frame(height: 20)

            HStack(spacing: 4) {
                Text("Peak Min:")
                    .font(.caption)
                    .foregroundColor(Palette.color(.textSecondary))
                    .fixedSize()
                Slider(value: $tapToneAnalyzer.peakMinThreshold, in: -100...(-20), step: 1)
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
            .buttonStyle(.borderedProminent)
            .tint(Palette.color(.accent))
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
            .buttonStyle(.tintedBordered)
            .tint(isInReviewPhase ? Palette.color(.statusComplete) : nil)
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
                    .foregroundStyle(Palette.color(cancelButtonEnabled ? .statusWarning : .toolbarInactive))
            }
            .buttonStyle(.tintedBordered)
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

                    Text("\(tap.numberOfTaps)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Palette.color(.textPrimary))
                        .frame(minWidth: 16)

                    Stepper("",
                            value: $tapToneAnalyzer.numberOfTaps,
                            in: 1...10)
                        .labelsHidden()
                }
                .disabledDimmed(tapCountLocked)
                .hint(HintText.taps)

                Divider()
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

                Divider()
                    .frame(height: 20)

                // Peak Min slider — minimum spectral magnitude for peak annotation.
                HStack(spacing: 4) {
                    Text("Peak Min:")
                        .font(.caption)
                        .foregroundColor(Palette.color(.textSecondary))
                        .fixedSize()
                    Slider(value: $tapToneAnalyzer.peakMinThreshold, in: -100...(-20), step: 1)
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
                .buttonStyle(.borderedProminent)
                .tint(Palette.color(.accent))
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
                .buttonStyle(.tintedBordered)
                .tint(isInReviewPhase ? Palette.color(.statusComplete) : nil)
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
                        .foregroundStyle(Palette.color(cancelButtonEnabled ? .statusWarning : .toolbarInactive))
                }
                .buttonStyle(.tintedBordered)
                .disabled(!cancelButtonEnabled)
                .hint(isInReviewPhase ? "Redo this tap phase" : HintText.cancel)
            }
        }
    }
}
