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
                defaultName: tap.loadedMeasurementName ?? "",
                defaultNotes: tap.loadedNotes ?? "",
                onSave: { name, noteText in saveMeasurement(name: name, noteText: noteText) }
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingSettings) {
            TapSettingsView(
                minFreq: $minFreq,
                maxFreq: $maxFreq,
                minDB: $minDB,
                maxDB: $maxDB,
                peakMinThreshold: $tapToneAnalyzer.peakMinThreshold,
                fftAnalyzer: fft,
                onApply: { measurementChanged, guitarTypeChanged in
                    tapToneAnalyzer.applyDumpCaptureAudioSetting()
                    if measurementChanged {
                        tapToneAnalyzer.requestStartTapSequence()
                    } else if guitarTypeChanged {
                        // Guitar type changed: clean-slate re-derivation for the new type.
                        tapToneAnalyzer.reclassifyForGuitarTypeChange()
                    }
                    // else: display-only Apply (Peak Min/dB/range) — leave peaks, modes and selection alone.
                }
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
                    // Done only closes: a plain button (.cancellationAction), as every closing Done.
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            showingMetrics = false
                        }
                    }
                }
            }
            .frame(minWidth: 400, minHeight: 500)
        }
        .overlay { loadingOverlay }
        // Arm-time guard: New Tap was pressed with Dump Capture Audio on but its
        // folder unreachable. Prompt before capturing rather than losing the write at completion.
        .alert("Capture Audio Folder Unavailable", isPresented: $tapToneAnalyzer.dumpFolderUnreachable) {
            Button("Change Location…") {
                if WavDumpFolder.chooseFolder() {
                    tapToneAnalyzer.requestStartTapSequence()   // retry — arms if now reachable
                }
            }
            Button("Turn Off Saving") {
                TapDisplaySettings.dumpCaptureAudio = false
                tapToneAnalyzer.applyDumpCaptureAudioSetting()
                tapToneAnalyzer.startTapSequence()              // dump now off → arm directly
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The folder you chose for saving captured audio isn't there:\n\(WavDumpFolder.currentFolder.path)\n\nIt may have been renamed, moved, or removed. Choose the folder again, or turn off audio saving, before starting the measurement.")
        }
        // Write-time guard: a measurement finished but its captured audio couldn't be written. The
        // recording is held; choosing a folder saves it, the other choices let it go.
        .alert("Capture Audio Folder Unavailable", isPresented: $tapToneAnalyzer.captureRecordingHeld) {
            Button("Change Location…") {
                _ = WavDumpFolder.chooseFolder()
                tapToneAnalyzer.saveHeldCaptureRecordings()     // asks again if still not written
            }
            Button("Turn Off Saving") {
                TapDisplaySettings.dumpCaptureAudio = false
                tapToneAnalyzer.applyDumpCaptureAudioSetting()
                tapToneAnalyzer.discardHeldCaptureRecordings()
            }
            Button("Cancel", role: .cancel) {
                tapToneAnalyzer.discardHeldCaptureRecordings()
            }
        } message: {
            Text("The captured audio of this measurement couldn't be saved to:\n\(WavDumpFolder.currentFolder.path)\n\nThe folder may have been renamed, moved, or removed. Choose a folder to save it, or turn off audio saving.")
        }
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
                defaultName: tap.loadedMeasurementName ?? "",
                defaultNotes: tap.loadedNotes ?? "",
                onSave: { name, noteText in saveMeasurement(name: name, noteText: noteText) }
            )
            .interactiveDismissDisabled()
        }
        // Results sheet is only used on non-iPad-horizontal layouts
        .sheet(isPresented: Binding(
            get: { showingResults && !isPhoneLandscape },
            set: { showingResults = $0 }
        )) {
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
                peakMinThreshold: $tapToneAnalyzer.peakMinThreshold,
                fftAnalyzer: fft,
                onApply: { measurementChanged, guitarTypeChanged in
                    tapToneAnalyzer.applyDumpCaptureAudioSetting()
                    if measurementChanged {
                        tapToneAnalyzer.requestStartTapSequence()
                    } else if guitarTypeChanged {
                        // Guitar type changed: clean-slate re-derivation for the new type.
                        tapToneAnalyzer.reclassifyForGuitarTypeChange()
                    }
                    // else: display-only Apply (Peak Min/dB/range) — leave peaks, modes and selection alone.
                }
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingHelp) {
            NavigationStack {
                HelpView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
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

                // Right pane: scrollable analysis results, capped width so the
                // FFT chart on the left always gets a usable share.
                TapAnalysisResultsView(
                    analyzer: tap,
                    fftAnalyzer: fft,
                    minFreq: minFreq,
                    maxFreq: maxFreq,
                    onExportSpectrum: { exportCurrentSpectrum() },
                    onExportPDFReport: { exportPDFReport() }
                )
                .frame(idealWidth: 360, maxWidth: 480)
            }

            Divider()

            statusBarView
        }
        .navigationTitle(appTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Left: Play File, Auto dB, Crosshair, Annotations
            ToolbarItemGroup(placement: .topBarLeading) {
                Button(action: { showingPlayFileSheet = true }) {
                    Image(systemName: "waveform.badge.plus")
                }
                .tint(Palette.color(fft.isPlayingFile ? .statusPlayingFile : .accent))
                .accessibilityLabel("Play File")
                .help("Feed an audio file through the analysis pipeline")

                Button(action: { toggleAutoScale() }) {
                    Image(systemName: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                }
                .tint(Palette.color(.accent))
                .accessibilityLabel("Auto dB")
                .hint(HintText.autoScale(isEnabled: isAutoScaleEnabled))

                Button(action: { crosshairMode.toggle() }) {
                    Image(systemName: crosshairMode ? "plus.viewfinder" : "dot.viewfinder")
                }
                .tint(crosshairMode ? Palette.color(.accent) : nil)
                .accessibilityLabel("Crosshair")

                Button(action: { tap.cycleAnnotationVisibility() }) {
                    Image(systemName: tap.annotationVisibilityMode.iconName)
                }
                .tint(Palette.color(.accent))
                .disabled((TapDisplaySettings.measurementType.isGuitar ? tap.peaksAbovePeakMin : tap.materialIdentifiedPeaks).isEmpty || tap.displayMode == .comparison)
                .accessibilityLabel("Annotation visibility: \(tap.annotationVisibilityMode.label)")
            }

            // Right: Save, Measurements, Metrics, Settings, Help — mirrors iPhone landscape
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: { showingSaveSheet = true }) {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(!tap.isMeasurementComplete && tap.displayMode != .comparison)
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

                Button(action: { showingHelpMenu = true }) {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
                .popover(isPresented: $showingHelpMenu, arrowEdge: .top) {
                    helpMenuPopover
                }
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
            .background(Palette.color(.backgroundSubtle))

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
        // Results slides in as an overlay on top of the spectrum — the graph does NOT resize.
        // On iPhone landscape we intentionally do not show graph + results together (mirrors
        // the web); portrait uses a bottom sheet instead.
        .overlay {
            if showingResults {
                ZStack(alignment: .trailing) {
                    // Dimming backdrop — tap anywhere off the panel to dismiss.
                    Palette.color(.scrim)
                        .ignoresSafeArea()
                        .onTapGesture { showingResults = false }
                        .transition(.opacity)

                    TapAnalysisResultsView(
                        analyzer: tap,
                        fftAnalyzer: fft,
                        minFreq: minFreq,
                        maxFreq: maxFreq,
                        onExportSpectrum: { exportCurrentSpectrum() },
                        onExportPDFReport: { exportPDFReport() },
                        compactLandscape: true
                    )
                    .frame(width: 420)
                    .frame(maxHeight: .infinity)
                    .background(Palette.color(.backgroundPanel))
                    .overlay(alignment: .leading) { Divider() }
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showingResults)
        .navigationTitle(appTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Left: Results, Play File, Auto dB, Crosshair, Annotations
            ToolbarItemGroup(placement: .topBarLeading) {
                Button(action: { showingResults.toggle() }) {
                    Image(systemName: "doc.text")
                }
                .accessibilityLabel("Results")
                .hint(HintText.showResults)

                Button(action: { showingPlayFileSheet = true }) {
                    Image(systemName: "waveform.badge.plus")
                }
                .tint(Palette.color(fft.isPlayingFile ? .statusPlayingFile : .accent))
                .accessibilityLabel("Play File")

                Button(action: { toggleAutoScale() }) {
                    Image(systemName: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                }
                .tint(Palette.color(.accent))
                .accessibilityLabel("Auto dB")
                .hint(HintText.autoScale(isEnabled: isAutoScaleEnabled))

                Button(action: { crosshairMode.toggle() }) {
                    Image(systemName: crosshairMode ? "plus.viewfinder" : "dot.viewfinder")
                }
                .tint(crosshairMode ? Palette.color(.accent) : nil)
                .accessibilityLabel("Crosshair")

                Button(action: { tap.cycleAnnotationVisibility() }) {
                    Image(systemName: tap.annotationVisibilityMode.iconName)
                }
                .tint(Palette.color(.accent))
                .disabled((TapDisplaySettings.measurementType.isGuitar ? tap.peaksAbovePeakMin : tap.materialIdentifiedPeaks).isEmpty)
                .accessibilityLabel("Annotation visibility: \(tap.annotationVisibilityMode.label)")
            }

            // Right: Save, Measurements, Metrics, Settings, Help
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: { showingSaveSheet = true }) {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(!tap.isMeasurementComplete && tap.displayMode != .comparison)
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

                Button(action: { showingHelpMenu = true }) {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
                .popover(isPresented: $showingHelpMenu, arrowEdge: .top) {
                    helpMenuPopover
                }
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
            .disabledDimmed(tapCountLocked)

            // Threshold — level meter with draggable marker (mirrors other layouts)
            // Disabled for brace mode — brace taps bypass the spectral
            // magnitude gate (the rising-edge trigger is sufficient).
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Threshold:")
                        .font(.caption)
                        .foregroundColor(Palette.color(.textSecondary))
                    Text("\(Int(tap.tapDetectionThreshold)) dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Palette.color(.accentText))
                    Spacer()
                    thresholdResetButton
                }
                ThresholdSlider(
                    value: $tapToneAnalyzer.tapDetectionThreshold,
                    inputLevel: tap.fftAnalyzer.level,
                    range: -80...(-20)
                )
                    .accessibilityLabel("Tap detection threshold")
                    .hint(HintText.threshold)
            }
            .disabled(TapDisplaySettings.measurementType.isBrace)
            .opacity(TapDisplaySettings.measurementType.isBrace ? 0.4 : 1)

            // Peak detection threshold (guitar only — not used for plate/brace)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Peak Min:")
                        .font(.caption)
                        .foregroundColor(Palette.color(.textSecondary))
                    Text("\(Int(tap.peakMinThreshold)) dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Palette.color(.chartPeakMin))
                    Spacer()
                    peakMinResetButton
                }
                Slider(value: $tapToneAnalyzer.peakMinThreshold, in: -100...(-20), step: 1)
                    .accessibilityLabel("Peak detection minimum threshold")
                    .hint(HintText.peakMin)
            }
            .disabled(!TapDisplaySettings.measurementType.isGuitar || tap.displayMode == .comparison)
            .opacity(TapDisplaySettings.measurementType.isGuitar && tap.displayMode != .comparison ? 1 : 0.4)

            Divider()

            // Action buttons - vertical stack
            VStack(spacing: 6) {
                Button(action: { tap.requestStartTapSequence() }) {
                    Label("New Tap", systemImage: "hand.tap")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTapButtonDisabled)
                .hint(HintText.newTap)

                // Pause/Resume — becomes "Accept" during plate/brace review phases
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
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(
                            tap.isDetectionPaused ? "Resume" : "Pause",
                            systemImage: tap.isDetectionPaused ? "play.circle" : "pause.circle"
                        )
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.tintedBordered)
                .tint(isInReviewPhase ? Palette.color(.statusComplete) : nil)
                .disabled(!pauseResumeButtonEnabled)
                .hint(isInReviewPhase ? "Accept this tap and continue" :
                      tap.isDetectionPaused ? HintText.resumeDetection : HintText.pauseDetection)

                // Cancel — becomes "Redo [phase]" during plate/brace review phases
                Button(action: {
                    if isInReviewPhase {
                        tapToneAnalyzer.redoCurrentPhase()
                    } else {
                        tap.cancelTapSequence()
                    }
                }) {
                    let (label, icon) = redoOrCancelLabel
                    Label(label, systemImage: icon)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(Palette.color(cancelButtonEnabled ? .statusWarning : .toolbarInactive))
                }
                .buttonStyle(.tintedBordered)
                .disabled(!cancelButtonEnabled)
                .hint(isInReviewPhase ? "Redo this tap phase" : HintText.cancel)
            }

            // Progress — for plate/brace show from phase 1; for guitar keep currentTapCount > 0 guard
            let isPlateOrBrace = TapDisplaySettings.measurementType == .plate || TapDisplaySettings.measurementType == .brace
            if isPlateOrBrace || tap.currentTapCount > 0 {
                VStack(spacing: 4) {
                    let totalPhases = TapDisplaySettings.measureFlc ? 3 : 2
                    let phaseLabel = TapDisplaySettings.measurementType == .plate
                        ? (tap.numberOfTaps > 1
                            ? "Phase \(materialPhaseStep)/\(totalPhases) · Tap \(max(0, tap.currentTapCount - (materialPhaseStep - 1) * tap.numberOfTaps))/\(tap.numberOfTaps)"
                            : "Phase \(materialPhaseStep)/\(totalPhases)")
                        : "Tap \(tap.currentTapCount)/\(tap.numberOfTaps)"
                    Text(phaseLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                    ProgressView(value: tap.tapProgress)
                        .progressViewStyle(.linear)
                        .tint(Palette.color(.statusProgress))
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
                // iPhone — Left: Results, Play File, Auto dB
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: { showingResults.toggle() }) {
                        Image(systemName: "doc.text")
                    }
                    .accessibilityLabel("Results")
                    .hint(HintText.showResults)

                    Button(action: { showingPlayFileSheet = true }) {
                        Image(systemName: "waveform.badge.plus")
                    }
                    .tint(Palette.color(fft.isPlayingFile ? .statusPlayingFile : .accent))
                    .accessibilityLabel("Play File")

                    Button(action: { toggleAutoScale() }) {
                        Image(systemName: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                    }
                    .tint(Palette.color(.accent))
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
                // iPad — Left: Results, Play File, Auto dB, Crosshair, Annotations
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: { showResults() }) {
                        Image(systemName: "doc.text")
                    }
                    .accessibilityLabel("Results")
                    .hint(HintText.showResults)

                    Button(action: { showingPlayFileSheet = true }) {
                        Image(systemName: "waveform.badge.plus")
                    }
                    .tint(Palette.color(fft.isPlayingFile ? .statusPlayingFile : .accent))
                    .accessibilityLabel("Play File")
                    .help("Feed an audio file through the analysis pipeline")

                    Button(action: { toggleAutoScale() }) {
                        Image(systemName: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                    }
                    .tint(Palette.color(.accent))
                    .accessibilityLabel("Auto dB")
                    .hint(HintText.autoScale(isEnabled: isAutoScaleEnabled))

                    Button(action: { crosshairMode.toggle() }) {
                        Image(systemName: crosshairMode ? "plus.viewfinder" : "dot.viewfinder")
                    }
                    .tint(crosshairMode ? Palette.color(.accent) : nil)
                    .accessibilityLabel("Crosshair")

                    Button(action: { tap.cycleAnnotationVisibility() }) {
                        Image(systemName: tap.annotationVisibilityMode.iconName)
                    }
                    .tint(Palette.color(.accent))
                    .disabled((TapDisplaySettings.measurementType.isGuitar ? tap.peaksAbovePeakMin : tap.materialIdentifiedPeaks).isEmpty || tap.displayMode == .comparison)
                    .accessibilityLabel("Annotation visibility: \(tap.annotationVisibilityMode.label)")
                }

                // iPad — Right: Save, Measurements, Metrics, Settings, Help
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: { showingSaveSheet = true }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(!tap.isMeasurementComplete && tap.displayMode != .comparison)
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

                    Button(action: { showingHelpMenu = true }) {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                    .popover(isPresented: $showingHelpMenu, arrowEdge: .top) {
                        helpMenuPopover
                    }
                }
            }
        }
        #endif
    }

    #if os(iOS)
    /// Popover content for the iOS / iPadOS Help button.
    ///
    /// Replaces the previous `Menu` which had flaky hit-testing for any item
    /// whose action set `@State` driving a sheet (Menu dismissal raced with
    /// sheet presentation). Custom popover controls dismissal timing
    /// explicitly so both items behave the same way.
    @ViewBuilder
    var helpMenuPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                showingHelpMenu = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showingHelp = true
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "questionmark.bubble")
                        .frame(width: 22)
                    Text("Quick Start Guide")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            Button(action: {
                showingHelpMenu = false
                if let url = DocumentationLinks.userManual {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "book.closed")
                        .frame(width: 22)
                    Text("User Manual")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 260)
        .presentationCompactAdaptation(.popover)
    }
    #endif
}
