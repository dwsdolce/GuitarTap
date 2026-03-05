//
//  TapToneAnalysisView+Layouts.swift
//  GuitarTap
//

import SwiftUI

extension TapToneAnalysisView {

    // MARK: - Platform-Specific Layouts

    #if os(macOS)
    /// macOS layout - always uses sheets for Results and Metrics
    @ViewBuilder
    var macOSLayout: some View {
        mainContentView
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
                fftAnalyzer: fft
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingResults) {
            NavigationStack {
                TapAnalysisResultsView(
                    analyzer: tap,
                    fftAnalyzer: fft,
                    minFreq: minFreq,
                    maxFreq: maxFreq,
                    onExportPDFReport: { exportPDFReport() }
                )
                .navigationTitle("Analysis Results")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showingResults = false
                        }
                    }
                }
            }
            .frame(minWidth: 400, minHeight: 500)
        }
        .sheet(isPresented: $showingMetrics) {
            NavigationStack {
                ScrollView {
                    FFTAnalysisMetricsView(analyzer: fft)
                        .padding()
                }
                .navigationTitle("FFT Metrics")
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
        .onChange(of: minFreq) { _, newValue in
            minFreqInput = String(format: "%.0f", newValue)
        }
        .onChange(of: maxFreq) { _, newValue in
            maxFreqInput = String(format: "%.0f", newValue)
        }
        .onChange(of: minDB) { _, newValue in
            minDBInput = String(format: "%.0f", newValue)
        }
        .onChange(of: maxDB) { _, newValue in
            maxDBInput = String(format: "%.0f", newValue)
        }
        .overlay {
            if isExportingSpectrum {
                LoadingOverlay(message: "Exporting spectrum...")
            } else if isSavingMeasurement {
                LoadingOverlay(message: "Saving measurement with chart image...")
            } else if isGeneratingReport {
                LoadingOverlay(message: "Generating PDF report...")
            }
        }
    }
    #endif

    #if os(iOS)
    /// iOS layout - always uses sheets for Results and Metrics
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
        .sheet(isPresented: $showingResults) {
            NavigationView {
                TapAnalysisResultsView(
                    analyzer: tap,
                    fftAnalyzer: fft,
                    minFreq: minFreq,
                    maxFreq: maxFreq,
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
                ScrollView {
                    FFTAnalysisMetricsView(analyzer: fft)
                        .padding()
                }
                .navigationTitle("FFT Metrics")
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
                fftAnalyzer: fft
            )
            .interactiveDismissDisabled()
        }
        .onChange(of: minFreq) { _, newValue in
            minFreqInput = String(format: "%.0f", newValue)
        }
        .onChange(of: maxFreq) { _, newValue in
            maxFreqInput = String(format: "%.0f", newValue)
        }
        .onChange(of: minDB) { _, newValue in
            minDBInput = String(format: "%.0f", newValue)
        }
        .onChange(of: maxDB) { _, newValue in
            maxDBInput = String(format: "%.0f", newValue)
        }
        .overlay {
            if isExportingSpectrum {
                LoadingOverlay(message: "Exporting spectrum...")
            } else if isSavingMeasurement {
                LoadingOverlay(message: "Saving measurement with chart image...")
            } else if isGeneratingReport {
                LoadingOverlay(message: "Generating PDF report...")
            }
        }
    }
    #endif

    /// Main content view shared across platforms
    @ViewBuilder
    var mainContentView: some View {
        #if os(iOS)
        if isPhoneLandscape {
            // iPhone landscape: horizontal layout with controls on left
            phoneLandscapeLayout
        } else {
            // iPhone portrait, iPad, and macOS: vertical layout
            standardVerticalLayout
        }
        #else
        standardVerticalLayout
        #endif
    }

    #if os(iOS)
    /// iPhone landscape layout - controls on left, spectrum on right
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

            // Right side: spectrum and status
            VStack(spacing: 0) {
                // Spectrum view - fills available space
                realTimeSpectrumView
                    .padding(.horizontal, 4)

                // Compact status bar
                Divider()
                compactStatusBar
            }
        }
        .navigationTitle(appTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button(action: toggleAnalyzer) {
                    Image(systemName: fft.isRunning ? "stop.circle.fill" : "play.circle.fill")
                        .foregroundColor(fft.isRunning ? .red : .green)
                }
                .accessibilityLabel(fft.isRunning ? "Stop" : "Start")
                .hint(HintText.start(isRunning: fft.isRunning))

                Button(action: { showingSaveSheet = true }) {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(tap.currentPeaks.isEmpty)
                .accessibilityLabel("Save")
                .hint(HintText.save)

                // Export Spectrum button
                Button(action: { exportCurrentSpectrum() }) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
                .disabled(!fft.isRunning || fft.frequencies.isEmpty)
                .accessibilityLabel("Export Spectrum")
                .hint(HintText.exportSpectrum)

                // Auto-scale dB toggle button
                Button(action: { toggleAutoScale() }) {
                    Image(systemName: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                }
                .disabled(!fft.isRunning || displayMagnitudes.isEmpty)
                .accessibilityLabel("Auto dB")
                .hint(HintText.autoScale(isEnabled: isAutoScaleEnabled))
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: { crosshairMode.toggle() }) {
                    Image(systemName: crosshairMode ? "plus.viewfinder" : "dot.viewfinder")
                }
                .tint(crosshairMode ? .blue : nil)
                .accessibilityLabel("Crosshair")

                // Annotation visibility cycling button
                Button(action: { tap.cycleAnnotationVisibility() }) {
                    Image(systemName: tap.annotationVisibilityMode.iconName)
                }
                .tint(tap.annotationVisibilityMode == .none ? nil : .blue)
                .disabled(tap.currentPeaks.isEmpty)
                .accessibilityLabel("Annotation visibility: \(tap.annotationVisibilityMode.label)")

                Button(action: { showingResults.toggle() }) {
                    Image(systemName: "doc.text")
                }
                .accessibilityLabel("Results")
                .hint(HintText.showResults)

                Button(action: { showingMetrics.toggle() }) {
                    Image(systemName: "chart.bar")
                }
                .accessibilityLabel("Metrics")
                .hint(HintText.showMetrics)

                Button(action: { showingMeasurements = true }) {
                    Image(systemName: "list.bullet.clipboard")
                }
                .accessibilityLabel("Measurements")
                .hint(HintText.measurements)

                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .hint(HintText.settings)
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

            // Hysteresis
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Hysteresis: \(tap.hysteresisMargin, specifier: "%.1f") dB")
                        .font(.caption)
                    Button(action: {
                        tapToneAnalyzer.hysteresisMargin = TapDisplaySettings.defaultHysteresisMargin
                        TapDisplaySettings.hysteresisMargin = TapDisplaySettings.defaultHysteresisMargin
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Slider(value: $tapToneAnalyzer.hysteresisMargin, in: 1...10, step: 0.5)
                    .accessibilityLabel("Hysteresis margin")
                    .hint(HintText.hysteresis)
                    .onChange(of: tap.hysteresisMargin) { _, newValue in
                        TapDisplaySettings.hysteresisMargin = newValue
                    }
            }

            // Peak detection threshold
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
                    .onChange(of: tap.peakThreshold) { _, newValue in
                        TapDisplaySettings.peakThreshold = newValue
                    }
            }

            Divider()

            // Action buttons - vertical stack
            VStack(spacing: 6) {
                Button(action: { tap.startTapSequence() }) {
                    Label("New Tap", systemImage: "hand.tap")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!fft.isRunning ||
                          !tap.isReadyForDetection ||
                          tap.isDetecting)
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
            // Header with controls
            headerView

            Divider()

            // Main content - allow spectrum to fill available space
            VStack(spacing: 20) {
                // Real-time Frequency Response Display - expands to fill space
                realTimeSpectrumView

                // Decay time (keep this in main view for quick reference)
                decayTimeView
                    .padding(.horizontal)
            }
            .padding(.vertical)

            // Fixed status bar at bottom
            Divider()

            statusBarView
        }
        #if os(iOS)
        .navigationTitle(appTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if useCompactLayout {
                ToolbarItemGroup(placement: .topBarLeading) {
                    // Start/Stop button
                    Button(action: toggleAnalyzer) {
                        Image(systemName: fft.isRunning ? "stop.circle.fill" : "play.circle.fill")
                            .foregroundColor(fft.isRunning ? .red : .green)
                    }
                    .accessibilityLabel(fft.isRunning ? "Stop" : "Start")
                    .hint(HintText.start(isRunning: fft.isRunning))

                    // Save button
                    Button(action: { showingSaveSheet = true }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(tap.currentPeaks.isEmpty)
                    .accessibilityLabel("Save")
                    .hint(HintText.save)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Measurements button
                    Button(action: { showingMeasurements = true }) {
                        Image(systemName: "list.bullet.clipboard")
                    }
                    .accessibilityLabel("Measurements")
                    .hint(HintText.measurements)

                    // Settings button
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .hint(HintText.settings)
                }
            }
        }
        #endif
    }
}
