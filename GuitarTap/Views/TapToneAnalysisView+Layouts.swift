//
//  TapToneAnalysisView+Layouts.swift
//  GuitarTap
//

/// # TapToneAnalysisView+Layouts
///
/// Platform-specific top-level layout containers for `TapToneAnalysisView`.
///
/// ## Layout Hierarchy
///
/// ```
/// body
/// └── macOSLayout  /  iOSLayout          (platform switch)
///     └── mainContentView
///         ├── phoneLandscapeLayout       (iPhone landscape only)
///         └── standardVerticalLayout     (all other cases)
///             ├── headerView             (controls)
///             ├── realTimeSpectrumView   (spectrum chart)
///             └── decayTimeView          (ring-out / material metrics)
/// ```
///
/// ## Platform Differences
///
/// - **macOS**: A horizontal `HSplitView` shows the spectrum pane on the left
///   and the results panel on the right (when `showingResults` is true). The
///   status bar spans the full width below the split. All other panels (save,
///   settings, measurements, metrics) present as `.sheet`. Input-field sync
///   `onChange` handlers update the text-field mirrors whenever bound `Double`
///   values change.
/// - **iOS**: Results, metrics, save, and settings all use `.sheet`. The iOS
///   layout wraps `mainContentView` in a `NavigationView` to provide a nav bar
///   for toolbar items on compact devices.
/// - **iPhone landscape**: A horizontal split with a 200 pt scrollable control
///   panel on the left and the spectrum on the right. Results use a sheet.
///
/// A `LoadingOverlay` is shown during spectrum export, measurement save, and
/// PDF report generation on both platforms.
///
/// - SeeAlso: `TapToneAnalysisView+Controls`, `ResultsWindowPresenter`

import SwiftUI

extension TapToneAnalysisView {

    // MARK: - Platform-Specific Layouts

    #if os(macOS)
    /// macOS layout - horizontal split view with graph+info on the left and
    /// results panel on the right.  Status bar sits below the split.
    @ViewBuilder
    var macOSLayout: some View {
        VStack(spacing: 0) {
            // Toolbar buttons span the full window width
            headerView

            Divider()

            // Fixed split: results pane sizes itself to its content minimum width;
            // spectrum pane fills the remaining space.
            HStack(spacing: 0) {
                // Left pane: spectrum chart + decay info — takes all remaining space
                macOSLeftPane
                    .frame(maxWidth: .infinity)

                Divider()

                // Right pane: sizes to its ideal (unwrapped) width at the current font size
                macOSResultsPane
                    .fixedSize(horizontal: true, vertical: false)
            }

            Divider()

            // Status bar spans the full width below the split
            statusBarView
        }
        .sheet(isPresented: $showingMeasurements) {
            MeasurementsListView(analyzer: tap)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingSaveSheet) {
            SaveMeasurementSheet(
                tapLocation: $tapLocation,
                notes: $notes,
                onSave: saveMeasurement
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingSettings) {
            TapSettingsView(
                minFreq: $minFreq,
                maxFreq: $maxFreq,
                minDB: $minDB,
                maxDB: $maxDB,
                analysisMinFreq: $tapToneAnalyzer.minFrequency,
                analysisMaxFreq: $tapToneAnalyzer.maxFrequency,
                peakThreshold: $tapToneAnalyzer.peakThreshold,
                maxPeaks: $tapToneAnalyzer.maxPeaks,
                hysteresisMargin: $tapToneAnalyzer.hysteresisMargin,
                fftAnalyzer: fft,
                onApply: { tapToneAnalyzer.reclassifyPeaks() }
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingMetrics) {
            NavigationStack {
                AlwaysVisibleScrollView {
                    FFTAnalysisMetricsView(analyzer: fft)
                        .padding()
                }
                .navigationTitle("FFT Analysis Metrics")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showingMetrics = false
                        }
                    }
                }
            }
            .frame(minWidth: 400, minHeight: 500)
        }
        .overlay { loadingOverlay }
    }

    /// Left pane of the macOS split view: spectrum chart and decay info.
    @ViewBuilder
    var macOSLeftPane: some View {
        GeometryReader { _ in
            VStack(spacing: 20) {
                realTimeSpectrumView
                decayTimeView
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    /// Right pane of the macOS split view: scrollable analysis results.
    @ViewBuilder
    var macOSResultsPane: some View {
        TapAnalysisResultsView(
            analyzer: tap,
            fftAnalyzer: fft,
            minFreq: minFreq,
            maxFreq: maxFreq,
            onExportSpectrum: { exportCurrentSpectrum() },
            onExportPDFReport: { exportPDFReport() }
        )
    }
    #endif

    #if os(iOS)
    /// iOS layout - uses sheets for Results and Metrics, except on iPad horizontal
    /// where the results panel is shown inline (like macOS).
    @ViewBuilder
    var iOSLayout: some View {
        NavigationView {
            mainContentView
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingMeasurements) {
            MeasurementsListView(analyzer: tap)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingSaveSheet) {
            SaveMeasurementSheet(
                tapLocation: $tapLocation,
                notes: $notes,
                onSave: saveMeasurement
            )
            .interactiveDismissDisabled()
        }
        // Results sheet is only used on non-iPad-horizontal layouts
        .sheet(isPresented: $showingResults) {
            NavigationView {
                TapAnalysisResultsView(
                    analyzer: tap,
                    fftAnalyzer: fft,
                    minFreq: minFreq,
                    maxFreq: maxFreq,
                    onExportSpectrum: { exportCurrentSpectrum() },
                    onExportPDFReport: { exportPDFReport() }
                )
                .navigationTitle("Analysis Results")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingResults = false
                        }
                    }
                }
            }
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingMetrics) {
            NavigationView {
                AlwaysVisibleScrollView {
                    FFTAnalysisMetricsView(analyzer: fft)
                        .padding()
                }
                .navigationTitle("FFT Analysis Metrics")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingMetrics = false
                        }
                    }
                }
            }
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingSettings) {
            TapSettingsView(
                minFreq: $minFreq,
                maxFreq: $maxFreq,
                minDB: $minDB,
                maxDB: $maxDB,
                analysisMinFreq: $tapToneAnalyzer.minFrequency,
                analysisMaxFreq: $tapToneAnalyzer.maxFrequency,
                peakThreshold: $tapToneAnalyzer.peakThreshold,
                maxPeaks: $tapToneAnalyzer.maxPeaks,
                hysteresisMargin: $tapToneAnalyzer.hysteresisMargin,
                fftAnalyzer: fft,
                onApply: { tapToneAnalyzer.reclassifyPeaks() }
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingHelp) {
            NavigationStack {
                HelpView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingHelp = false }
                        }
                    }
            }
        }
        .overlay { loadingOverlay }
    }
    #endif

    /// Overlay shown during long-running export/save operations.
    @ViewBuilder
    var loadingOverlay: some View {
        if isExportingSpectrum {
            LoadingOverlay(message: "Exporting spectrum...")
        } else if isSavingMeasurement {
            LoadingOverlay(message: "Saving measurement with chart image...")
        } else if isGeneratingReport {
            LoadingOverlay(message: "Generating PDF report...")
        }
    }

    /// Main content view shared across platforms
    @ViewBuilder
    var mainContentView: some View {
        #if os(iOS)
        if isPhoneLandscape {
            // iPhone landscape: horizontal layout with controls on left
            phoneLandscapeLayout
        } else if isIPadHorizontal {
            // iPad horizontal: show results panel inline like macOS
            iPadHorizontalLayout
        } else {
            // iPhone portrait and iPad portrait: vertical layout with sheet for results
            standardVerticalLayout
        }
        #else
        standardVerticalLayout
        #endif
    }

    #if os(iOS)
    /// iPad horizontal layout - spectrum on the left, results panel on the right (like macOS).
    /// Toolbar mirrors iPhone landscape: leading has Auto dB/Crosshair/Annotations,
    /// trailing has Save/Measurements/Metrics/Settings. The header shows only tap controls.
    @ViewBuilder
    var iPadHorizontalLayout: some View {
        VStack(spacing: 0) {
            // Tap sequence controls only — action/view buttons are in the toolbar
            regularTapControls
                .padding(.horizontal)
                .padding(.top, 8)

            Divider()

            HStack(spacing: 0) {
                // Left pane: spectrum chart + decay info.
                // minWidth prevents a zero-size layout pass from producing NaN
                // coordinates in the annotations canvas.
                GeometryReader { _ in
                    VStack(spacing: 20) {
                        realTimeSpectrumView
                        decayTimeView
                            .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
                .frame(minWidth: 200, maxWidth: .infinity)

                Divider()

                // Right pane: scrollable analysis results, sized to its content
                TapAnalysisResultsView(
                    analyzer: tap,
                    fftAnalyzer: fft,
                    minFreq: minFreq,
                    maxFreq: maxFreq,
                    onExportSpectrum: { exportCurrentSpectrum() },
                    onExportPDFReport: { exportPDFReport() }
                )
                .fixedSize(horizontal: true, vertical: false)
            }

            Divider()

            statusBarView
        }
        .navigationTitle(appTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Left: Auto dB, Crosshair, Annotations — mirrors iPhone landscape
            ToolbarItemGroup(placement: .topBarLeading) {
                Button(action: { toggleAutoScale() }) {
                    Image(systemName: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                }
                .tint(.blue)
                .accessibilityLabel("Auto dB")
                .hint(HintText.autoScale(isEnabled: isAutoScaleEnabled))

                Button(action: { crosshairMode.toggle() }) {
                    Image(systemName: crosshairMode ? "plus.viewfinder" : "dot.viewfinder")
                }
                .tint(crosshairMode ? .blue : nil)
                .accessibilityLabel("Crosshair")

                Button(action: { tap.cycleAnnotationVisibility() }) {
                    Image(systemName: tap.annotationVisibilityMode.iconName)
                }
                .tint(.blue)
                .disabled(tap.currentPeaks.isEmpty || tap.displayMode == .comparison)
                .accessibilityLabel("Annotation visibility: \(tap.annotationVisibilityMode.label)")
            }

            // Right: Save, Measurements, Metrics, Settings, Help — mirrors iPhone landscape
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: { showingSaveSheet = true }) {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(tap.currentPeaks.isEmpty || tap.displayMode == .comparison)
                .accessibilityLabel("Save")
                .hint(HintText.save)

                Button(action: { showingMeasurements = true }) {
                    Image(systemName: "list.bullet.clipboard")
                }
                .accessibilityLabel("Measurements")
                .hint(HintText.measurements)

                Button(action: { showingMetrics.toggle() }) {
                    Image(systemName: "chart.bar")
                }
                .accessibilityLabel("Metrics")
                .hint(HintText.showMetrics)

                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .hint(HintText.settings)

                Button(action: { showingHelp = true }) {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
    }

    /// iPhone landscape layout - controls on left, spectrum on the right
    @ViewBuilder
    var phoneLandscapeLayout: some View {
        HStack(spacing: 0) {
            // Left side: scrollable controls
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    // Tap controls (simplified for landscape)
                    landscapeTapControls
                }
                .padding(8)
            }
            .frame(width: 200)
            .background(Color.secondary.opacity(0.05))

            Divider()

            // Right: spectrum and status — fills remaining space
            VStack(spacing: 0) {
                // Spectrum view - fills available space
                realTimeSpectrumView
                    .padding(.horizontal, 4)

                // Compact status bar
                Divider()
                compactStatusBar
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(appTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Left: Results, Auto dB, Crosshair, Annotations
            ToolbarItemGroup(placement: .topBarLeading) {
                Button(action: { showResults() }) {
                    Image(systemName: "doc.text")
                }
                .accessibilityLabel("Results")
                .hint(HintText.showResults)

                Button(action: { toggleAutoScale() }) {
                    Image(systemName: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                }
                .tint(.blue)
                .accessibilityLabel("Auto dB")
                .hint(HintText.autoScale(isEnabled: isAutoScaleEnabled))

                Button(action: { crosshairMode.toggle() }) {
                    Image(systemName: crosshairMode ? "plus.viewfinder" : "dot.viewfinder")
                }
                .tint(crosshairMode ? .blue : nil)
                .accessibilityLabel("Crosshair")

                Button(action: { tap.cycleAnnotationVisibility() }) {
                    Image(systemName: tap.annotationVisibilityMode.iconName)
                }
                .tint(.blue)
                .disabled(tap.currentPeaks.isEmpty)
                .accessibilityLabel("Annotation visibility: \(tap.annotationVisibilityMode.label)")
            }

            // Right: Save, Measurements, Metrics, Settings, Help
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: { showingSaveSheet = true }) {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(tap.currentPeaks.isEmpty)
                .accessibilityLabel("Save")
                .hint(HintText.save)

                Button(action: { showingMeasurements = true }) {
                    Image(systemName: "list.bullet.clipboard")
                }
                .accessibilityLabel("Measurements")
                .hint(HintText.measurements)

                Button(action: { showingMetrics.toggle() }) {
                    Image(systemName: "chart.bar")
                }
                .accessibilityLabel("Metrics")
                .hint(HintText.showMetrics)

                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .hint(HintText.settings)

                Button(action: { showingHelp = true }) {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
    }

    /// Simplified tap controls for iPhone landscape
    @ViewBuilder
    var landscapeTapControls: some View {
        VStack(spacing: 10) {
            // Taps stepper
            HStack {
                Text("Taps:")
                    .font(.caption)
                Spacer()
                Stepper("\(tap.numberOfTaps)",
                        value: $tapToneAnalyzer.numberOfTaps,
                        in: 1...10)
                    .labelsHidden()
                    .accessibilityLabel("Number of taps: \(tap.numberOfTaps)")
                    .hint(HintText.taps)
                Text("\(tap.numberOfTaps)")
                    .font(.caption)
                    .frame(width: 20)
            }

            // Threshold
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Threshold: \(Int(tap.tapDetectionThreshold)) dB")
                        .font(.caption)
                    Button(action: {
                        tapToneAnalyzer.tapDetectionThreshold = TapDisplaySettings.defaultTapDetectionThreshold
                        TapDisplaySettings.tapDetectionThreshold = TapDisplaySettings.defaultTapDetectionThreshold
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Slider(value: $tapToneAnalyzer.tapDetectionThreshold, in: -80...(-20), step: 1)
                    .accessibilityLabel("Tap detection threshold")
                    .hint(HintText.threshold)
                    .onChange(of: tap.tapDetectionThreshold) { _, newValue in
                        TapDisplaySettings.tapDetectionThreshold = newValue
                    }
            }

            // Peak detection threshold (guitar only — not used for plate/brace)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Peak Min: \(Int(tap.peakThreshold)) dB")
                        .font(.caption)
                    Button(action: {
                        tapToneAnalyzer.peakThreshold = TapDisplaySettings.defaultPeakThreshold
                        TapDisplaySettings.peakThreshold = TapDisplaySettings.defaultPeakThreshold
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Slider(value: $tapToneAnalyzer.peakThreshold, in: -100...(-20), step: 1)
                    .accessibilityLabel("Peak detection minimum threshold")
                    .hint(HintText.peakMin)
                    .onChange(of: tap.peakThreshold) { _, newValue in
                        TapDisplaySettings.peakThreshold = newValue
                    }
            }
            .disabled(!TapDisplaySettings.measurementType.isGuitar)
            .opacity(TapDisplaySettings.measurementType.isGuitar ? 1 : 0.4)

            Divider()

            // Action buttons - vertical stack
            VStack(spacing: 6) {
                Button(action: { tap.startTapSequence() }) {
                    Label("New Tap", systemImage: "hand.tap")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(tap.displayMode != .comparison && (!fft.isRunning ||
                          !tap.isReadyForDetection ||
                          tap.isDetecting))
                .hint(HintText.newTap)

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
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!pauseResumeButtonEnabled)
                .hint(tap.isDetectionPaused ? HintText.resumeDetection : HintText.pauseDetection)

                Button(action: { tap.cancelTapSequence() }) {
                    Label("Cancel", systemImage: "xmark.circle")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(cancelButtonEnabled ? Color.orange : Color.gray)
                }
                .buttonStyle(.bordered)
                .disabled(!cancelButtonEnabled)
                .hint(HintText.cancel)
            }

            // Progress
            if tap.currentTapCount > 0 {
                VStack(spacing: 4) {
                    Text("\(tap.currentTapCount)/\(tap.numberOfTaps)")
                        .font(.caption)
                        .fontWeight(.semibold)
                    ProgressView(value: tap.tapProgress)
                        .progressViewStyle(.linear)
                }
            }
        }
    }
    #endif

    /// Standard vertical layout for portrait and larger screens
    @ViewBuilder
    var standardVerticalLayout: some View {
        VStack(spacing: 0) {
            // Header: iPad uses toolbar for action buttons, so only tap controls shown here.
            // iPhone uses the full headerView (icon button row + compact tap controls).
            #if os(iOS)
            if useCompactLayout {
                headerView
            } else {
                regularTapControls
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            #else
            headerView
            #endif

            Divider()

            // Main content - spectrum fills remaining space
            #if os(macOS)
            GeometryReader { _ in
                VStack(spacing: 20) {
                    realTimeSpectrumView
                    decayTimeView
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            #else
            VStack(spacing: 20) {
                // Real-time Frequency Response Display - expands to fill space
                realTimeSpectrumView

                // Decay time (keep this in main view for quick reference)
                decayTimeView
                    .padding(.horizontal)
            }
            .padding(.vertical)
            #endif

            // Fixed status bar at bottom
            Divider()

            statusBarView
        }
        #if os(iOS)
        .navigationTitle(appTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if useCompactLayout {
                // iPhone — Left: Results, Auto dB
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: { showingResults.toggle() }) {
                        Image(systemName: "doc.text")
                    }
                    .accessibilityLabel("Results")
                    .hint(HintText.showResults)

                    Button(action: { toggleAutoScale() }) {
                        Image(systemName: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                    }
                    .tint(.blue)
                    .accessibilityLabel("Auto dB")
                    .hint(HintText.autoScale(isEnabled: isAutoScaleEnabled))
                }

                // iPhone — Right: Metrics, Settings
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: { showingMetrics.toggle() }) {
                        Image(systemName: "chart.bar")
                    }
                    .accessibilityLabel("Metrics")
                    .hint(HintText.showMetrics)

                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .hint(HintText.settings)
                }
            } else {
                // iPad — Left: Results, Auto dB, Crosshair, Annotations
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: { showResults() }) {
                        Image(systemName: "doc.text")
                    }
                    .accessibilityLabel("Results")
                    .hint(HintText.showResults)

                    Button(action: { toggleAutoScale() }) {
                        Image(systemName: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                    }
                    .tint(.blue)
                    .accessibilityLabel("Auto dB")
                    .hint(HintText.autoScale(isEnabled: isAutoScaleEnabled))

                    Button(action: { crosshairMode.toggle() }) {
                        Image(systemName: crosshairMode ? "plus.viewfinder" : "dot.viewfinder")
                    }
                    .tint(crosshairMode ? .blue : nil)
                    .accessibilityLabel("Crosshair")

                    Button(action: { tap.cycleAnnotationVisibility() }) {
                        Image(systemName: tap.annotationVisibilityMode.iconName)
                    }
                    .tint(.blue)
                    .disabled(tap.currentPeaks.isEmpty || tap.displayMode == .comparison)
                    .accessibilityLabel("Annotation visibility: \(tap.annotationVisibilityMode.label)")
                }

                // iPad — Right: Save, Measurements, Metrics, Settings, Help
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: { showingSaveSheet = true }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(tap.currentPeaks.isEmpty || tap.displayMode == .comparison)
                    .accessibilityLabel("Save")
                    .hint(HintText.save)

                    Button(action: { showingMeasurements = true }) {
                        Image(systemName: "list.bullet.clipboard")
                    }
                    .accessibilityLabel("Measurements")
                    .hint(HintText.measurements)

                    Button(action: { showingMetrics.toggle() }) {
                        Image(systemName: "chart.bar")
                    }
                    .accessibilityLabel("Metrics")
                    .hint(HintText.showMetrics)

                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .hint(HintText.settings)

                    Button(action: { showingHelp = true }) {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                }
            }
        }
        #endif
    }
}
