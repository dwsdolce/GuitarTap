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

                    Button(action: { crosshairMode.toggle() }) {
                        Image(systemName: crosshairMode ? "plus.viewfinder" : "dot.viewfinder")
                    }
                    .buttonStyle(.bordered)
                    .tint(crosshairMode ? .blue : .gray)
                    .accessibilityLabel("Crosshair")

                    Button(action: { tap.cycleAnnotationVisibility() }) {
                        Image(systemName: tap.annotationVisibilityMode.iconName)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .disabled(tap.currentPeaks.isEmpty || tap.displayMode == .comparison)
                    .help("Annotation visibility: \(tap.annotationVisibilityMode.label)")

                    Button(action: { showingSaveSheet = true }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(tap.currentPeaks.isEmpty || tap.displayMode == .comparison)
                    .accessibilityLabel("Save")
                    .hint(HintText.save)

                    Button(action: { showingMeasurements = true }) {
                        Image(systemName: "list.bullet.clipboard")
                    }
                    .buttonStyle(.bordered)
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
                    .buttonStyle(.bordered)
                    .hint(HintText.showResults)
                }

                // Auto-scale dB toggle button (iPad)
                Button(action: { toggleAutoScale() }) {
                    Label("Auto dB", systemImage: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .hint(HintText.autoScale(isEnabled: isAutoScaleEnabled))

                // Crosshair mode toggle button (iPad)
                Button(action: { crosshairMode.toggle() }) {
                    Label("Crosshair", systemImage: crosshairMode ? "plus.viewfinder" : "dot.viewfinder")
                }
                .buttonStyle(.bordered)
                .tint(crosshairMode ? .blue : .gray)

                // Annotation visibility cycling button (iPad)
                Button(action: { tap.cycleAnnotationVisibility() }) {
                    Label("Annotations", systemImage: tap.annotationVisibilityMode.iconName)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .disabled(tap.currentPeaks.isEmpty || tap.displayMode == .comparison)
                .help("Annotation visibility: \(tap.annotationVisibilityMode.label)")

                // Save button
                Button(action: { showingSaveSheet = true }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .disabled(tap.currentPeaks.isEmpty || tap.displayMode == .comparison)
                .hint(HintText.save)
            }

            // Row 2: Secondary controls
            HStack(spacing: 8) {
                // Measurements button
                Button(action: { showingMeasurements = true }) {
                    Label("Measurements", systemImage: "list.bullet.clipboard")
                    if !tap.savedMeasurements.isEmpty {
                        Text("(\(tap.savedMeasurements.count))")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .hint(HintText.measurements)

                // Metrics button
                Button(action: { showingMetrics = true }) {
                    Label("Metrics", systemImage: "chart.bar")
                }
                .buttonStyle(.bordered)
                .hint(HintText.showMetrics)

                // Settings button
                Button(action: { showingSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .hint(HintText.settings)

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
        Button(action: { toggleAutoScale() }) {
            if iconOnly { Image(systemName: icon) } else { Label("Auto dB", systemImage: icon) }
        }
        .buttonStyle(.bordered)
        .tint(.blue)
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
        .buttonStyle(.bordered)
        .tint(.blue)
        .disabled(tap.currentPeaks.isEmpty || tap.displayMode == .comparison)
        .help("Annotation visibility: \(tap.annotationVisibilityMode.label)")
    }

    @ViewBuilder
    private func macosSaveButton(iconOnly: Bool) -> some View {
        Button(action: { showingSaveSheet = true }) {
            if iconOnly { Image(systemName: "square.and.arrow.down") } else { Label("Save", systemImage: "square.and.arrow.down") }
        }
        .buttonStyle(.bordered)
        .tint(.blue)
        .disabled(tap.currentPeaks.isEmpty || tap.displayMode == .comparison)
        .hint(HintText.save)
    }

    @ViewBuilder
    private func macosMeasurementsButton(iconOnly: Bool) -> some View {
        Button(action: { showingMeasurements = true }) {
            HStack(spacing: 2) {
                if iconOnly {
                    Image(systemName: "list.bullet.clipboard")
                } else {
                    Label("Measurements", systemImage: "list.bullet.clipboard")
                }
                if !tap.savedMeasurements.isEmpty {
                    Text(iconOnly ? "\(tap.savedMeasurements.count)" : "(\(tap.savedMeasurements.count))")
                        .font(iconOnly ? .caption2 : .caption)
                }
            }
        }
        .buttonStyle(.bordered)
        .hint(HintText.measurements)
    }

    @ViewBuilder
    private func macosMetricsButton(iconOnly: Bool) -> some View {
        Button(action: { showingMetrics = true }) {
            if iconOnly { Image(systemName: "chart.bar") } else { Label("Metrics", systemImage: "chart.bar") }
        }
        .buttonStyle(.bordered)
        .hint(HintText.showMetrics)
    }

    @ViewBuilder
    private func macosSettingsButton(iconOnly: Bool) -> some View {
        Button(action: { showingSettings = true }) {
            if iconOnly { Image(systemName: "gearshape") } else { Label("Settings", systemImage: "gearshape") }
        }
        .buttonStyle(.bordered)
        .hint(HintText.settings)
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
                // Comparison mode: show count and clear affordance
                Image(systemName: "waveform.path")
                    .foregroundColor(.accentColor)
                    .font(.caption)
                Text("Comparing \(tap.comparisonSpectra.count) measurements")
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                Text("New Tap to exit")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if tap.showLoadedSettingsWarning {
                // Warn that threshold and tap count came from a loaded measurement.
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                    .opacity(warningIconOpacity)
                Text("Loaded settings — Threshold: \(Int(tap.tapDetectionThreshold)) dB · Taps: \(tap.numberOfTaps)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                    .lineLimit(1)
                Spacer()
            } else {
                // Normal tap detection state
                Circle()
                    .fill(tap.isMeasurementComplete ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 10, height: 10)

                Text(tap.isMeasurementComplete ? "Tap Detected!" : "Waiting for tap...")
                    .font(.caption)
                    .foregroundColor(tap.isMeasurementComplete ? .green : .secondary)
                    .lineLimit(1)

                Text("\(TapDisplaySettings.measurementType.isGuitar ? fft.peakMagnitude : fft.displayLevelDB, specifier: "%.0f") dB")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if tap.isDetecting && tap.currentTapCount > 0 {
                    Text("\(tap.currentTapCount)/\(tap.numberOfTaps)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .lineLimit(1)

                    ProgressView(value: tap.tapProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 50)
                }

                Spacer()

                if fft.isRunning {
                    Text("Peak: \(fft.peakMagnitude, specifier: "%.1f") dB @ \(fft.peakFrequency, specifier: "%.1f") Hz")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                }

                if tap.isMeasurementComplete {
                    Image(systemName: "pause.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }

                Circle()
                    .fill(fft.isRunning ? .green : .red)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .frame(height: 28) // Fixed height
        .background {
            Color.secondary.opacity(0.1)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Full status bar for iPad and macOS
    @ViewBuilder
    var fullStatusBar: some View {
        VStack(spacing: 6) {
            if tap.displayMode == .comparison {
                // Comparison mode: replace tap detection state with comparison info
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path")
                        .foregroundColor(.accentColor)
                    Text("Comparing \(tap.comparisonSpectra.count) measurements")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("Press New Tap to exit comparison")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                // Warn that threshold and tap count came from a loaded measurement.
                // Persists through New Tap until a successful capture or manual change.
                if tap.showLoadedSettingsWarning {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.subheadline)
                            .opacity(warningIconOpacity)
                        Text("Settings from loaded measurement — Threshold: \(Int(tap.tapDetectionThreshold)) dB · Taps: \(tap.numberOfTaps)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(6)
                }
                // Normal tap detection state
                if tap.currentTapCount > 0 {
                    ProgressView(value: tap.tapProgress)
                        .progressViewStyle(.linear)
                }

                HStack(spacing: 12) {
                    Circle()
                        .fill(tap.isMeasurementComplete ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)

                    Text(tap.isMeasurementComplete ? "Tap Detected!" : "Waiting for tap...")
                        .font(.subheadline)
                        .foregroundColor(tap.isMeasurementComplete ? .green : .secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text("\(TapDisplaySettings.measurementType.isGuitar ? fft.peakMagnitude : fft.displayLevelDB, specifier: "%.1f") dB")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    if tap.isMeasurementComplete {
                        HStack(spacing: 4) {
                            Image(systemName: "pause.circle.fill")
                                .foregroundColor(.orange)
                            Text("Complete")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if fft.isRunning {
                        Text("Peak: \(fft.peakMagnitude, specifier: "%.1f") dB @ \(fft.peakFrequency, specifier: "%.1f") Hz")
                            .font(.caption)
                            .foregroundColor(.blue)
                    } else {
                        Text("Starting...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Circle()
                        .fill(tap.isDetecting ? .green : .orange)
                        .frame(width: 8, height: 8)

                    Text(tap.statusMessage)
                        .font(.caption)
                        .foregroundColor(tap.isDetecting ? .primary : .orange)

                    if tap.isDetecting && tap.currentTapCount > 0 {
                        Text("\(tap.currentTapCount)/\(tap.numberOfTaps)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
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
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Reset to default")
    }

    /// Reset button for the peak-minimum threshold slider.
    @ViewBuilder
    var peakMinResetButton: some View {
        Button(action: {
            tapToneAnalyzer.peakThreshold = TapDisplaySettings.defaultPeakThreshold
            TapDisplaySettings.peakThreshold = TapDisplaySettings.defaultPeakThreshold
        }) {
            Image(systemName: "arrow.counterclockwise")
                .font(.caption2)
                .foregroundColor(.secondary)
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
                        .foregroundColor(.secondary)

                    Stepper("\(tap.numberOfTaps)",
                            value: $tapToneAnalyzer.numberOfTaps,
                            in: 1...10)
                        .frame(maxWidth: 120)
                        .hint(HintText.taps)

                    Spacer()
                }

                // Tap threshold slider
                HStack(spacing: 6) {
                    Text("Threshold:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize()
                    Slider(value: $tapToneAnalyzer.tapDetectionThreshold, in: -80...(-20), step: 1)
                        .accessibilityLabel("Tap detection threshold")
                        .hint(HintText.threshold)

                    Text("\(Int(tap.tapDetectionThreshold)) dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .fixedSize()
                    thresholdResetButton
                }

                HStack(spacing: 6) {
                    Text("Peak Min:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize()
                    Slider(value: $tapToneAnalyzer.peakThreshold, in: -100...(-20), step: 1)
                        .accessibilityLabel("Peak detection minimum threshold")
                        .hint(HintText.peakMin)

                    Text("\(Int(tap.peakThreshold)) dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                        .fixedSize()
                    peakMinResetButton
                }
                .disabled(!TapDisplaySettings.measurementType.isGuitar)
                .opacity(TapDisplaySettings.measurementType.isGuitar ? 1 : 0.4)
            }

            // Row 2: Action buttons - all buttons always visible to prevent layout shifts
            HStack(spacing: 8) {
                // New Tap button
                Button(action: {
                    tap.startTapSequence()
                }) {
                    Label("New Tap", systemImage: "hand.tap")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
                .disabled(tap.displayMode != .comparison && (!fft.isRunning ||
                          !tap.isReadyForDetection ||
                          tap.isDetecting ||
                          !tap.isMeasurementComplete))
                .hint(HintText.newTap)

                // Pause/Resume button - for multi-tap and plate/brace sequences
                Button(action: {
                    if tap.isDetectionPaused {
                        tapToneAnalyzer.resumeTapDetection()
                    } else {
                        tapToneAnalyzer.pauseTapDetection()
                    }
                }) {
                    Label(
                        tap.isDetectionPaused ? "Resume" : "Pause",
                        systemImage: tap.isDetectionPaused ? "play.circle" : "pause.circle"
                    )
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(!pauseResumeButtonEnabled)
                .hint(tap.isDetectionPaused ? HintText.resumeDetection : HintText.pauseDetection)

                // Cancel button - only enabled during active multi-tap detection
                Button(action: {
                    tap.cancelTapSequence()
                }) {
                    Label("Cancel", systemImage: "xmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(cancelButtonEnabled ? Color.orange : Color.gray)
                }
                .buttonStyle(.bordered)
                .disabled(!cancelButtonEnabled)
                .hint(HintText.cancel)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
        .fixedSize(horizontal: false, vertical: true)
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
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    /// Wide layout for regular tap controls - all in one row
    @ViewBuilder
    var regularTapControlsWide: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("Taps:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("\(tap.numberOfTaps)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .frame(minWidth: 16)

                Stepper("",
                        value: $tapToneAnalyzer.numberOfTaps,
                        in: 1...10)
                    .labelsHidden()
            }
            .hint(HintText.taps)

            Divider()
                .frame(height: 20)

            // Tap detection threshold slider
            HStack(spacing: 4) {
                Text("Threshold:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize()
                Slider(value: $tapToneAnalyzer.tapDetectionThreshold, in: -80...(-20), step: 1)
                    .frame(width: 80)
                    .accessibilityLabel("Tap detection threshold")

                Text("\(Int(tap.tapDetectionThreshold)) dB")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                    .fixedSize()
                thresholdResetButton
            }
            .hint(HintText.threshold)

            Divider()
                .frame(height: 20)

            HStack(spacing: 4) {
                Text("Peak Min:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize()
                Slider(value: $tapToneAnalyzer.peakThreshold, in: -100...(-20), step: 1)
                    .frame(width: 80)
                    .accessibilityLabel("Peak detection minimum threshold")
                    .hint(HintText.peakMin)

                Text("\(Int(tap.peakThreshold)) dB")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                    .fixedSize()
                peakMinResetButton
            }
            .disabled(!TapDisplaySettings.measurementType.isGuitar)
            .opacity(TapDisplaySettings.measurementType.isGuitar ? 1 : 0.4)

            Spacer()

            // Tap sequence buttons
            Button(action: {
                tap.startTapSequence()
            }) {
                Label("New Tap", systemImage: "hand.tap")
            }
            .buttonStyle(.bordered)
            .disabled(tap.displayMode != .comparison && (!fft.isRunning ||
                      !tap.isReadyForDetection ||
                      tap.isDetecting ||
                      !tap.isMeasurementComplete))
            .hint(HintText.newTap)

            // Pause/Resume button - for multi-tap and plate/brace sequences
            Button(action: {
                if tap.isDetectionPaused {
                    tapToneAnalyzer.resumeTapDetection()
                } else {
                    tapToneAnalyzer.pauseTapDetection()
                }
            }) {
                Label(
                    tap.isDetectionPaused ? "Resume" : "Pause",
                    systemImage: tap.isDetectionPaused ? "play.circle" : "pause.circle"
                )
            }
            .buttonStyle(.bordered)
            .disabled(!pauseResumeButtonEnabled)
            .hint(tap.isDetectionPaused ? HintText.resumeDetection : HintText.pauseDetection)

            // Cancel button - only enabled during active multi-tap detection
            Button(action: {
                tap.cancelTapSequence()
            }) {
                Label("Cancel", systemImage: "xmark.circle")
                    .foregroundStyle(cancelButtonEnabled ? Color.orange : Color.gray)
            }
            .buttonStyle(.bordered)
            .disabled(!cancelButtonEnabled)
            .hint(HintText.cancel)
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
                        .foregroundColor(.secondary)

                    Text("\(tap.numberOfTaps)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .frame(minWidth: 16)

                    Stepper("",
                            value: $tapToneAnalyzer.numberOfTaps,
                            in: 1...10)
                        .labelsHidden()
                }
                .hint(HintText.taps)

                Divider()
                    .frame(height: 20)

                // Tap detection threshold slider
                HStack(spacing: 4) {
                    Text("Threshold:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize()
                    Slider(value: $tapToneAnalyzer.tapDetectionThreshold, in: -80...(-20), step: 1)
                        .frame(width: 80)
                        .accessibilityLabel("Tap detection threshold")

                    Text("\(Int(tap.tapDetectionThreshold)) dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .fixedSize()
                    thresholdResetButton
                }
                .hint(HintText.threshold)

                Divider()
                    .frame(height: 20)

                // Peak Min slider
                HStack(spacing: 4) {
                    Text("Peak Min:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize()
                    Slider(value: $tapToneAnalyzer.peakThreshold, in: -100...(-20), step: 1)
                        .frame(width: 80)
                        .accessibilityLabel("Peak detection minimum threshold")

                    Text("\(Int(tap.peakThreshold)) dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                        .fixedSize()
                    peakMinResetButton
                }
                .disabled(!TapDisplaySettings.measurementType.isGuitar)
                .opacity(TapDisplaySettings.measurementType.isGuitar ? 1 : 0.4)

                Spacer()
            }

            // Row 2: Action buttons (right-justified)
            HStack(spacing: 8) {
                Spacer()

                // Tap sequence buttons
                Button(action: {
                    tap.startTapSequence()
                }) {
                    Label("New Tap", systemImage: "hand.tap")
                }
                .buttonStyle(.bordered)
                .disabled(tap.displayMode != .comparison && (!fft.isRunning ||
                          !tap.isReadyForDetection ||
                          tap.isDetecting ||
                          !tap.isMeasurementComplete))
                .hint(HintText.newTap)

                // Pause/Resume button - for multi-tap and plate/brace sequences
                Button(action: {
                    if tap.isDetectionPaused {
                        tapToneAnalyzer.resumeTapDetection()
                    } else {
                        tapToneAnalyzer.pauseTapDetection()
                    }
                }) {
                    Label(
                        tap.isDetectionPaused ? "Resume" : "Pause",
                        systemImage: tap.isDetectionPaused ? "play.circle" : "pause.circle"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(!pauseResumeButtonEnabled)
                .hint(tap.isDetectionPaused ? HintText.resumeDetection : HintText.pauseDetection)

                // Cancel button - only enabled during active multi-tap detection
                Button(action: {
                    tap.cancelTapSequence()
                }) {
                    Label("Cancel", systemImage: "xmark.circle")
                        .foregroundStyle(cancelButtonEnabled ? Color.orange : Color.gray)
                }
                .buttonStyle(.bordered)
                .disabled(!cancelButtonEnabled)
                .hint(HintText.cancel)
            }
        }
    }
}
