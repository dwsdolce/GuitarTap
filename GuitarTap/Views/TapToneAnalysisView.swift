//
//  TapToneAnalysisView.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import SwiftUI
import Charts
import AVFoundation

#if os(macOS)
import AppKit
#endif

#if os(iOS)
import UIKit
#endif

// MARK: - Main Tap Tone Analysis View

struct TapToneAnalysisView: View {
    @StateObject private var fftAnalyzer: RealtimeFFTAnalyzer
    @StateObject private var tapToneAnalyzer: TapToneAnalyzer
    
    @State private var tapLocation: String = ""
    @State private var notes: String = ""
    @State private var showingSaveSheet = false
    @State private var showingMeasurements = false
    @State private var showingMetrics = false
    @State private var showingResults = false
    @State private var showingSettings = false
    @State private var isExportingSpectrum = false
    @State private var isSavingMeasurement = false
    @State private var isGeneratingReport = false
    
    // Spectrum display state (loaded from persisted settings)
    @State private var minFreq: Float = SpectrumDisplaySettings.minFrequency
    @State private var maxFreq: Float = SpectrumDisplaySettings.maxFrequency
    @State private var minDB: Float = SpectrumDisplaySettings.minMagnitude
    @State private var maxDB: Float = SpectrumDisplaySettings.maxMagnitude
    @State private var minFreqInput: String = String(format: "%.0f", SpectrumDisplaySettings.minFrequency)
    @State private var maxFreqInput: String = String(format: "%.0f", SpectrumDisplaySettings.maxFrequency)
    @State private var minDBInput: String = String(format: "%.0f", SpectrumDisplaySettings.minMagnitude)
    @State private var maxDBInput: String = String(format: "%.0f", SpectrumDisplaySettings.maxMagnitude)
    
    // Auto-scale dB state
    @State private var isAutoScaleEnabled = false
    
    // Material measurement mode state
    @State private var selectedLongitudinalPeakID: UUID?
    @State private var selectedCrossPeakID: UUID?
    @State private var selectedFlcPeakID: UUID?
    
    // Environment
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.displayScale) var displayScale
    
    /// Returns true if running on iPhone (not iPad)
    private var isPhone: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }
    
    /// Returns true if we should use compact layout (iPhone in any orientation)
    private var useCompactLayout: Bool {
        #if os(iOS)
        return isPhone
        #else
        return false
        #endif
    }
    
    /// Returns true if iPhone is in landscape orientation (very limited vertical space)
    private var isPhoneLandscape: Bool {
        #if os(iOS)
        return isPhone && verticalSizeClass == .compact
        #else
        return false
        #endif
    }
    
    /// Cancel button should only be enabled during active multi-tap detection
    private var cancelButtonEnabled: Bool {
        // Must be multi-tap mode
        guard tapToneAnalyzer.numberOfTaps > 1 else { return false }
        // Must be actively detecting
        guard tapToneAnalyzer.isDetecting else { return false }
        // Must not have completed all taps
        guard tapToneAnalyzer.currentTapCount < tapToneAnalyzer.numberOfTaps else { return false }
        return true
    }
    
    /// Pause/Resume button is enabled during any active multi-tap, material, or brace sequence
    private var pauseResumeButtonEnabled: Bool {
        // In material/brace mode, detection management is always relevant
        if !SpectrumDisplaySettings.measurementType.isGuitar {
            return tapToneAnalyzer.isDetecting || tapToneAnalyzer.isDetectionPaused
        }
        // In guitar mode, only enabled for multi-tap sequences
        guard tapToneAnalyzer.numberOfTaps > 1 else { return false }
        return tapToneAnalyzer.isDetecting || tapToneAnalyzer.isDetectionPaused
    }
    
    init() {
        // Create a single FFT analyzer instance
        // Using 65,536 FFT size for maximum frequency resolution (0.67 Hz/bin @ 44.1kHz)
        // With 25% overlap, this gives ~1.8 Hz frame rate
        let fft = RealtimeFFTAnalyzer(fftSize: 65536, targetSampleRate: 48000)
        
        // Use the SAME instance for both state objects
        _fftAnalyzer = StateObject(wrappedValue: fft)
        _tapToneAnalyzer = StateObject(wrappedValue: TapToneAnalyzer(fftAnalyzer: fft))
    }
    
    var body: some View {
        Group {
            #if os(macOS)
            macOSLayout
            #else
            iOSLayout
            #endif
        }
        .onReceive(tapToneAnalyzer.$loadedMinFreq) { minFreq in
            if let minFreq = minFreq {
                print("  ⬇️ View received loadedMinFreq: \(minFreq)")
                self.minFreq = minFreq
                self.minFreqInput = String(format: "%.0f", minFreq)
                // Clear the loaded value after applying (with small delay to ensure UI updates)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedMinFreq = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedMaxFreq) { maxFreq in
            if let maxFreq = maxFreq {
                print("  ⬇️ View received loadedMaxFreq: \(maxFreq)")
                self.maxFreq = maxFreq
                self.maxFreqInput = String(format: "%.0f", maxFreq)
                // Clear the loaded value after applying (with small delay to ensure UI updates)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedMaxFreq = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedMinDB) { minDB in
            if let minDB = minDB {
                print("  ⬇️ View received loadedMinDB: \(minDB)")
                self.minDB = minDB
                self.minDBInput = String(format: "%.0f", minDB)
                // Clear the loaded value after applying (with small delay to ensure UI updates)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedMinDB = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedMaxDB) { maxDB in
            if let maxDB = maxDB {
                print("  ⬇️ View received loadedMaxDB: \(maxDB)")
                self.maxDB = maxDB
                self.maxDBInput = String(format: "%.0f", maxDB)
                // Clear the loaded value after applying (with small delay to ensure UI updates)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedMaxDB = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedTapDetectionThreshold) { threshold in
            if threshold != nil {
                print("  ⬇️ View received loadedTapDetectionThreshold: \(threshold!)")
                // Settings are already updated in the analyzer via bindings
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedTapDetectionThreshold = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedHysteresisMargin) { hysteresis in
            if hysteresis != nil {
                print("  ⬇️ View received loadedHysteresisMargin: \(hysteresis!)")
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedHysteresisMargin = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedNumberOfTaps) { taps in
            if taps != nil {
                print("  ⬇️ View received loadedNumberOfTaps: \(taps!)")
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedNumberOfTaps = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedShowUnknownModes) { showUnknown in
            if let showUnknown = showUnknown {
                print("  ⬇️ View received loadedShowUnknownModes: \(showUnknown)")
                SpectrumDisplaySettings.showUnknownModes = showUnknown
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedShowUnknownModes = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedGuitarType) { guitarType in
            if let guitarType = guitarType {
                print("  ⬇️ View received loadedGuitarType: \(guitarType.rawValue)")
                SpectrumDisplaySettings.guitarType = guitarType
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedGuitarType = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedMeasurementType) { measurementType in
            if let measurementType = measurementType {
                print("  ⬇️ View received loadedMeasurementType: \(measurementType.shortName)")
                SpectrumDisplaySettings.measurementType = measurementType
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedMeasurementType = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedSelectedLongitudinalPeakID) { peakID in
            if let peakID = peakID {
                print("  ⬇️ View received loadedSelectedLongitudinalPeakID: \(peakID)")
                self.selectedLongitudinalPeakID = peakID
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedSelectedLongitudinalPeakID = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedSelectedCrossPeakID) { peakID in
            if let peakID = peakID {
                print("  ⬇️ View received loadedSelectedCrossPeakID: \(peakID)")
                self.selectedCrossPeakID = peakID
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedSelectedCrossPeakID = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedSelectedFlcPeakID) { peakID in
            if let peakID = peakID {
                print("  ⬇️ View received loadedSelectedFlcPeakID: \(peakID)")
                self.selectedFlcPeakID = peakID
                // Clear the loaded value after a small delay to ensure UI updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedSelectedFlcPeakID = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedMaterialLength) { length in
            if let length = length {
                print("  ⬇️ View received loadedMaterialLength: \(length)mm")
                if SpectrumDisplaySettings.measurementType.isBrace {
                    SpectrumDisplaySettings.braceLength = length
                } else {
                    SpectrumDisplaySettings.materialLength = length
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedMaterialLength = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedMaterialWidth) { width in
            if let width = width {
                if SpectrumDisplaySettings.measurementType.isBrace {
                    SpectrumDisplaySettings.braceWidth = width
                } else {
                    SpectrumDisplaySettings.materialWidth = width
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedMaterialWidth = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedMaterialThickness) { thickness in
            if let thickness = thickness {
                if SpectrumDisplaySettings.measurementType.isBrace {
                    SpectrumDisplaySettings.braceThickness = thickness
                } else {
                    SpectrumDisplaySettings.materialThickness = thickness
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedMaterialThickness = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$loadedMaterialMass) { mass in
            if let mass = mass {
                if SpectrumDisplaySettings.measurementType.isBrace {
                    SpectrumDisplaySettings.braceMass = mass
                } else {
                    SpectrumDisplaySettings.materialMass = mass
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tapToneAnalyzer.loadedMaterialMass = nil
                }
            }
        }
        .onReceive(tapToneAnalyzer.$autoSelectedLongitudinalPeakID) { peakID in
            // When material measurement auto-selects a longitudinal peak, update the view state
            if let peakID = peakID {
                self.selectedLongitudinalPeakID = peakID
                // Expand display range to include this peak
                if let peak = tapToneAnalyzer.longitudinalPeaks.first(where: { $0.id == peakID }) {
                    expandFreqRangeToInclude(peak.frequency)
                }
            }
        }
        .onReceive(tapToneAnalyzer.$autoSelectedCrossPeakID) { peakID in
            // When material measurement auto-selects a cross-grain peak, update the view state
            if let peakID = peakID {
                self.selectedCrossPeakID = peakID
                // Expand display range to include this peak
                if let peak = tapToneAnalyzer.crossPeaks.first(where: { $0.id == peakID }) {
                    expandFreqRangeToInclude(peak.frequency)
                }
            }
        }
        .onReceive(tapToneAnalyzer.$autoSelectedFlcPeakID) { peakID in
            // When material measurement auto-selects an FLC peak, update the view state
            if let peakID = peakID {
                self.selectedFlcPeakID = peakID
                // Expand display range to include this peak
                if let peak = tapToneAnalyzer.flcPeaks.first(where: { $0.id == peakID }) {
                    expandFreqRangeToInclude(peak.frequency)
                }
            }
        }
        .onReceive(fftAnalyzer.$magnitudes) { newMagnitudes in
            // Auto-scale dB when enabled and spectrum updates
            // Note: Check for non-empty magnitudes that aren't all -100 (initialization value)
            let hasValidData = !newMagnitudes.isEmpty && newMagnitudes.contains { $0 > -99 }
            if isAutoScaleEnabled && hasValidData && fftAnalyzer.isRunning {
                autoScaleDB()
            }
        }
        .onChange(of: fftAnalyzer.isRunning) { _, isNowRunning in
            // When analyzer starts running, perform initial auto-scale if enabled
            if isNowRunning && isAutoScaleEnabled {
                // Wait a moment for first valid data to arrive
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if self.isAutoScaleEnabled && self.fftAnalyzer.isRunning {
                        print("🔄 Auto-scale: Performing initial scale on analyzer start")
                        self.autoScaleDB()
                    }
                }
            }
        }
        .onChange(of: tapToneAnalyzer.isSpectrumFrozen) { _, isFrozen in
            // Disable auto-scale when spectrum is frozen (tap detected)
            if isFrozen && isAutoScaleEnabled {
                isAutoScaleEnabled = false
                print("🔄 Auto-scale dB disabled - tap detected, spectrum frozen")
            }
        }
    }
    
    // MARK: - Platform-Specific Layouts
    
    #if os(macOS)
    /// macOS layout - always uses sheets for Results and Metrics
    @ViewBuilder
    private var macOSLayout: some View {
        mainContentView
        .sheet(isPresented: $showingMeasurements) {
            MeasurementsListView(analyzer: tapToneAnalyzer)
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
            SpectrumSettingsView(
                minFreq: $minFreq,
                maxFreq: $maxFreq,
                minDB: $minDB,
                maxDB: $maxDB,
                analysisMinFreq: $tapToneAnalyzer.minFrequency,
                analysisMaxFreq: $tapToneAnalyzer.maxFrequency,
                peakThreshold: $tapToneAnalyzer.peakThreshold,
                maxPeaks: $tapToneAnalyzer.maxPeaks,
                fftAnalyzer: fftAnalyzer
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingResults) {
            NavigationStack {
                TapAnalysisResultsView(
                    analyzer: tapToneAnalyzer,
                    fftAnalyzer: fftAnalyzer,
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
                    FFTAnalysisMetricsView(analyzer: fftAnalyzer)
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
    private var iOSLayout: some View {
        NavigationView {
            mainContentView
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingMeasurements) {
            MeasurementsListView(analyzer: tapToneAnalyzer)
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
                    analyzer: tapToneAnalyzer,
                    fftAnalyzer: fftAnalyzer,
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
                    FFTAnalysisMetricsView(analyzer: fftAnalyzer)
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
            SpectrumSettingsView(
                minFreq: $minFreq,
                maxFreq: $maxFreq,
                minDB: $minDB,
                maxDB: $maxDB,
                analysisMinFreq: $tapToneAnalyzer.minFrequency,
                analysisMaxFreq: $tapToneAnalyzer.maxFrequency,
                peakThreshold: $tapToneAnalyzer.peakThreshold,
                maxPeaks: $tapToneAnalyzer.maxPeaks,
                fftAnalyzer: fftAnalyzer
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
    private var mainContentView: some View {
        if SpectrumDisplaySettings.measurementType.isMPM {
            mpmContentView
        } else {
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
    }

    /// Content view for MPM (frequency meter) measurement types.
    /// Reuses the same header/status-bar structure as standardVerticalLayout so
    /// Start/Stop, Save, Settings, Results, and Measurements all work identically.
    @ViewBuilder
    private var mpmContentView: some View {
        VStack(spacing: 0) {
            // Header with controls — same as spectrum layout
            headerView

            Divider()

            // Frequency meter fills available space
            FrequencyMeterView(
                tapToneAnalyzer: tapToneAnalyzer,
                fftAnalyzer: fftAnalyzer
            )

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
                    Button(action: toggleAnalyzer) {
                        Image(systemName: fftAnalyzer.isRunning ? "stop.circle.fill" : "play.circle.fill")
                            .foregroundColor(fftAnalyzer.isRunning ? .red : .green)
                    }
                    .accessibilityLabel(fftAnalyzer.isRunning ? "Stop" : "Start")

                    Button(action: { showingSaveSheet = true }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(tapToneAnalyzer.mpmLongitudinalFrequency == nil)
                    .accessibilityLabel("Save")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: { showingResults = true }) {
                        Image(systemName: "doc.text")
                    }
                    .accessibilityLabel("Results")

                    Button(action: { showingMeasurements = true }) {
                        Image(systemName: "list.bullet.clipboard")
                    }
                    .accessibilityLabel("Measurements")

                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        #endif
    }
    
    #if os(iOS)
    /// iPhone landscape layout - controls on left, spectrum on right
    @ViewBuilder
    private var phoneLandscapeLayout: some View {
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
                    .padding(8)
                
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
                    Image(systemName: fftAnalyzer.isRunning ? "stop.circle.fill" : "play.circle.fill")
                        .foregroundColor(fftAnalyzer.isRunning ? .red : .green)
                }
                .accessibilityLabel(fftAnalyzer.isRunning ? "Stop" : "Start")
                .hint(HintText.start(isRunning: fftAnalyzer.isRunning))
                
                Button(action: { showingSaveSheet = true }) {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(tapToneAnalyzer.currentPeaks.isEmpty)
                .accessibilityLabel("Save")
                .hint(HintText.save)
                
                // Export Spectrum button
                Button(action: { exportCurrentSpectrum() }) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
                .disabled(!fftAnalyzer.isRunning || fftAnalyzer.frequencies.isEmpty)
                .accessibilityLabel("Export Spectrum")
                .hint(HintText.exportSpectrum)
                
                // Auto-scale dB toggle button
                Button(action: { toggleAutoScale() }) {
                    Image(systemName: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                }
                .disabled(!fftAnalyzer.isRunning || displayMagnitudes.isEmpty)
                .accessibilityLabel("Auto dB")
                .hint(HintText.autoScale(isEnabled: isAutoScaleEnabled))
            }
            
            ToolbarItemGroup(placement: .topBarTrailing) {
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
    private var landscapeTapControls: some View {
        VStack(spacing: 10) {
            // Taps stepper
            HStack {
                Text("Taps:")
                    .font(.caption)
                Spacer()
                Stepper("\(tapToneAnalyzer.numberOfTaps)", 
                        value: $tapToneAnalyzer.numberOfTaps, 
                        in: 1...10)
                    .labelsHidden()
                    .accessibilityLabel("Number of taps: \(tapToneAnalyzer.numberOfTaps)")
                    .hint(HintText.taps)
                Text("\(tapToneAnalyzer.numberOfTaps)")
                    .font(.caption)
                    .frame(width: 20)
            }
            
            // Threshold
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Threshold: \(Int(tapToneAnalyzer.tapDetectionThreshold)) dB")
                        .font(.caption)
                    Button(action: {
                        tapToneAnalyzer.tapDetectionThreshold = SpectrumDisplaySettings.defaultTapDetectionThreshold
                        SpectrumDisplaySettings.tapDetectionThreshold = SpectrumDisplaySettings.defaultTapDetectionThreshold
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
                    .onChange(of: tapToneAnalyzer.tapDetectionThreshold) { _, newValue in
                        SpectrumDisplaySettings.tapDetectionThreshold = newValue
                    }
            }
            
            // Hysteresis
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Hysteresis: \(tapToneAnalyzer.hysteresisMargin, specifier: "%.1f") dB")
                        .font(.caption)
                    Button(action: {
                        tapToneAnalyzer.hysteresisMargin = SpectrumDisplaySettings.defaultHysteresisMargin
                        SpectrumDisplaySettings.hysteresisMargin = SpectrumDisplaySettings.defaultHysteresisMargin
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
                    .onChange(of: tapToneAnalyzer.hysteresisMargin) { _, newValue in
                        SpectrumDisplaySettings.hysteresisMargin = newValue
                    }
            }
            
            // Peak detection threshold
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Peak Min: \(Int(tapToneAnalyzer.peakThreshold)) dB")
                        .font(.caption)
                    Button(action: {
                        tapToneAnalyzer.peakThreshold = SpectrumDisplaySettings.defaultPeakThreshold
                        SpectrumDisplaySettings.peakThreshold = SpectrumDisplaySettings.defaultPeakThreshold
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Slider(value: $tapToneAnalyzer.peakThreshold, in: -100...(-20), step: 1)
                    .accessibilityLabel("Peak detection minimum threshold")
                    .onChange(of: tapToneAnalyzer.peakThreshold) { _, newValue in
                        SpectrumDisplaySettings.peakThreshold = newValue
                    }
            }
            
            Divider()
            
            // Action buttons - vertical stack
            VStack(spacing: 6) {
                Button(action: { tapToneAnalyzer.startTapSequence() }) {
                    Label("New Tap", systemImage: "hand.tap")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!fftAnalyzer.isRunning ||
                          !tapToneAnalyzer.isReadyForDetection ||
                          tapToneAnalyzer.isDetecting)
                .hint(HintText.newTap)
                
                Button(action: {
                    if tapToneAnalyzer.isDetectionPaused {
                        tapToneAnalyzer.resumeTapDetection()
                    } else {
                        tapToneAnalyzer.pauseTapDetection()
                    }
                }) {
                    Label(
                        tapToneAnalyzer.isDetectionPaused ? "Resume" : "Pause",
                        systemImage: tapToneAnalyzer.isDetectionPaused ? "play.circle" : "pause.circle"
                    )
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!pauseResumeButtonEnabled)
                .hint(tapToneAnalyzer.isDetectionPaused ? HintText.resumeDetection : HintText.pauseDetection)
                
                Button(action: { tapToneAnalyzer.cancelTapSequence() }) {
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
            if tapToneAnalyzer.currentTapCount > 0 {
                VStack(spacing: 4) {
                    Text("\(tapToneAnalyzer.currentTapCount)/\(tapToneAnalyzer.numberOfTaps)")
                        .font(.caption)
                        .fontWeight(.semibold)
                    ProgressView(value: tapToneAnalyzer.tapProgress)
                        .progressViewStyle(.linear)
                }
            }
        }
    }
    #endif
    
    /// Standard vertical layout for portrait and larger screens
    @ViewBuilder
    private var standardVerticalLayout: some View {
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
                        Image(systemName: fftAnalyzer.isRunning ? "stop.circle.fill" : "play.circle.fill")
                            .foregroundColor(fftAnalyzer.isRunning ? .red : .green)
                    }
                    .accessibilityLabel(fftAnalyzer.isRunning ? "Stop" : "Start")
                    .hint(HintText.start(isRunning: fftAnalyzer.isRunning))
                    
                    // Save button
                    Button(action: { showingSaveSheet = true }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(tapToneAnalyzer.currentPeaks.isEmpty)
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
    
    // MARK: - Subviews
    
    private var headerView: some View {
        VStack(spacing: 12) {
            // Top row: Main controls - adaptive for iOS
            #if os(iOS)
            if useCompactLayout {
                // Compact layout for iPhone - secondary buttons only (primary buttons are in toolbar)
                HStack(spacing: 8) {
                    // Results button
                    Button(action: { showingResults.toggle() }) {
                        Label("Results", systemImage: showingResults ? "doc.text.fill" : "doc.text")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .hint(HintText.showResults)
                    
                    // Metrics button
                    Button(action: { showingMetrics.toggle() }) {
                        Label("Metrics", systemImage: showingMetrics ? "chart.bar.fill" : "chart.bar")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .hint(HintText.showMetrics)
                    
                    // Export Spectrum button
                    Button(action: { exportCurrentSpectrum() }) {
                        Label("Export", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!fftAnalyzer.isRunning || fftAnalyzer.frequencies.isEmpty)
                    .hint(HintText.exportSpectrum)
                    
                    // Auto-scale dB toggle button
                    Button(action: { toggleAutoScale() }) {
                        Label("Auto dB", systemImage: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(isAutoScaleEnabled ? .blue : .gray)
                    .disabled(!fftAnalyzer.isRunning || displayMagnitudes.isEmpty)
                    .hint(HintText.autoScale(isEnabled: isAutoScaleEnabled))
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
    private var ipadHeaderButtons: some View {
        VStack(spacing: 8) {
            // Row 1: Primary controls
            HStack(spacing: 8) {
                // Start/Stop button
                Button(action: toggleAnalyzer) {
                    Label(
                        fftAnalyzer.isRunning ? "Stop" : "Start",
                        systemImage: fftAnalyzer.isRunning ? "stop.circle.fill" : "play.circle.fill"
                    )
                    .foregroundColor(fftAnalyzer.isRunning ? .red : .green)
                }
                .buttonStyle(.bordered)
                .hint(HintText.start(isRunning: fftAnalyzer.isRunning))
                
                Spacer()
                
                // Results button
                Button(action: { showingResults = true }) {
                    Label("Results", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .hint(HintText.showResults)
                
                // Metrics button
                Button(action: { showingMetrics = true }) {
                    Label("Metrics", systemImage: "chart.bar")
                }
                .buttonStyle(.bordered)
                .hint(HintText.showMetrics)
                
                // Save button
                Button(action: { showingSaveSheet = true }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(tapToneAnalyzer.currentPeaks.isEmpty)
                .hint(HintText.save)
                
                // Measurements button
                Button(action: { showingMeasurements = true }) {
                    Label("Measurements", systemImage: "list.bullet.clipboard")
                    if !tapToneAnalyzer.savedMeasurements.isEmpty {
                        Text("(\(tapToneAnalyzer.savedMeasurements.count))")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .hint(HintText.measurements)
                
                // Settings button
                Button(action: { showingSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .hint(HintText.settings)
            }
            
            // Row 2: Secondary controls
            HStack(spacing: 8) {
                // Export Spectrum button
                Button(action: { exportCurrentSpectrum() }) {
                    Label("Export Spectrum", systemImage: "chart.line.uptrend.xyaxis")
                }
                .buttonStyle(.bordered)
                .disabled(!fftAnalyzer.isRunning || fftAnalyzer.frequencies.isEmpty)
                .hint(HintText.exportSpectrum)
                
                // Auto-scale dB toggle button (iPad)
                Button(action: { toggleAutoScale() }) {
                    Label("Auto dB", systemImage: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .tint(isAutoScaleEnabled ? .blue : .gray)
                .disabled(!fftAnalyzer.isRunning || displayMagnitudes.isEmpty)
                .hint(HintText.autoScale(isEnabled: isAutoScaleEnabled))
                
                Spacer()
            }
        }
    }
    #endif
    
    #if os(macOS)
    /// macOS button layout - adapts to narrow windows using ViewThatFits
    @ViewBuilder
    private var macosHeaderButtons: some View {
        ViewThatFits(in: .horizontal) {
            // Wide layout - all buttons in one row
            macosWideHeaderButtons
            
            // Medium layout - two rows
            macosMediumHeaderButtons
            
            // Narrow layout - icon-only buttons
            macosNarrowHeaderButtons
        }
    }
    
    /// Wide macOS layout - all buttons in one row with full labels
    @ViewBuilder
    private var macosWideHeaderButtons: some View {
        HStack {
            // Start/Stop button
            Button(action: toggleAnalyzer) {
                Label(
                    fftAnalyzer.isRunning ? "Stop" : "Start",
                    systemImage: fftAnalyzer.isRunning ? "stop.circle.fill" : "play.circle.fill"
                )
                .foregroundColor(fftAnalyzer.isRunning ? .red : .green)
            }
            .buttonStyle(.bordered)
            .hint(HintText.start(isRunning: fftAnalyzer.isRunning))
            
            Spacer()
            
            // Results button
            Button(action: { showingResults = true }) {
                Label("Results", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
            .hint(HintText.showResults)
            
            // Metrics button
            Button(action: { showingMetrics = true }) {
                Label("Metrics", systemImage: "chart.bar")
            }
            .buttonStyle(.bordered)
            .hint(HintText.showMetrics)
            
            // Save button
            Button(action: { showingSaveSheet = true }) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(tapToneAnalyzer.currentPeaks.isEmpty)
            .hint(HintText.save)
            
            // Export Spectrum button
            Button(action: { exportCurrentSpectrum() }) {
                Label("Export Spectrum", systemImage: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.bordered)
            .disabled(!fftAnalyzer.isRunning || fftAnalyzer.frequencies.isEmpty)
            .hint(HintText.exportSpectrum)
            
            // Auto-scale dB toggle button (macOS)
            Button(action: { toggleAutoScale() }) {
                Label("Auto dB", systemImage: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .tint(isAutoScaleEnabled ? .blue : .gray)
            .disabled(!fftAnalyzer.isRunning || displayMagnitudes.isEmpty)
            .hint(HintText.autoScale(isEnabled: isAutoScaleEnabled))
            
            // Measurements button
            Button(action: { showingMeasurements = true }) {
                Label("Measurements", systemImage: "list.bullet.clipboard")
                if !tapToneAnalyzer.savedMeasurements.isEmpty {
                    Text("(\(tapToneAnalyzer.savedMeasurements.count))")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .hint(HintText.measurements)
            
            // Settings button
            Button(action: { showingSettings = true }) {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .hint(HintText.settings)
        }
    }
    
    /// Medium macOS layout - two rows with labels
    @ViewBuilder
    private var macosMediumHeaderButtons: some View {
        VStack(spacing: 8) {
            // Row 1: Primary controls
            HStack(spacing: 8) {
                // Start/Stop button
                Button(action: toggleAnalyzer) {
                    Label(
                        fftAnalyzer.isRunning ? "Stop" : "Start",
                        systemImage: fftAnalyzer.isRunning ? "stop.circle.fill" : "play.circle.fill"
                    )
                    .foregroundColor(fftAnalyzer.isRunning ? .red : .green)
                }
                .buttonStyle(.bordered)
                .hint(HintText.start(isRunning: fftAnalyzer.isRunning))
                
                Spacer()
                
                // Results button
                Button(action: { showingResults = true }) {
                    Label("Results", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .hint(HintText.showResults)
                
                // Metrics button
                Button(action: { showingMetrics = true }) {
                    Label("Metrics", systemImage: "chart.bar")
                }
                .buttonStyle(.bordered)
                .hint(HintText.showMetrics)
                
                // Save button
                Button(action: { showingSaveSheet = true }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(tapToneAnalyzer.currentPeaks.isEmpty)
                .hint(HintText.save)
                
                // Settings button
                Button(action: { showingSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .hint(HintText.settings)
            }
            
            // Row 2: Secondary controls
            HStack(spacing: 8) {
                // Export Spectrum button
                Button(action: { exportCurrentSpectrum() }) {
                    Label("Export Spectrum", systemImage: "chart.line.uptrend.xyaxis")
                }
                .buttonStyle(.bordered)
                .disabled(!fftAnalyzer.isRunning || fftAnalyzer.frequencies.isEmpty)
                .hint(HintText.exportSpectrum)
                
                // Auto-scale dB toggle button
                Button(action: { toggleAutoScale() }) {
                    Label("Auto dB", systemImage: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .tint(isAutoScaleEnabled ? .blue : .gray)
                .disabled(!fftAnalyzer.isRunning || displayMagnitudes.isEmpty)
                .hint(HintText.autoScale(isEnabled: isAutoScaleEnabled))
                
                // Measurements button
                Button(action: { showingMeasurements = true }) {
                    Label("Measurements", systemImage: "list.bullet.clipboard")
                    if !tapToneAnalyzer.savedMeasurements.isEmpty {
                        Text("(\(tapToneAnalyzer.savedMeasurements.count))")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .hint(HintText.measurements)
                
                Spacer()
            }
        }
    }
    
    /// Narrow macOS layout - icon-only buttons in two rows
    @ViewBuilder
    private var macosNarrowHeaderButtons: some View {
        VStack(spacing: 8) {
            // Row 1: Primary controls - icon only
            HStack(spacing: 6) {
                // Start/Stop button
                Button(action: toggleAnalyzer) {
                    Image(systemName: fftAnalyzer.isRunning ? "stop.circle.fill" : "play.circle.fill")
                        .foregroundColor(fftAnalyzer.isRunning ? .red : .green)
                }
                .buttonStyle(.bordered)
                .hint(HintText.start(isRunning: fftAnalyzer.isRunning))
                
                Spacer()
                
                // Results button
                Button(action: { showingResults = true }) {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.bordered)
                .hint(HintText.showResults)
                
                // Metrics button
                Button(action: { showingMetrics = true }) {
                    Image(systemName: "chart.bar")
                }
                .buttonStyle(.bordered)
                .hint(HintText.showMetrics)
                
                // Save button
                Button(action: { showingSaveSheet = true }) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(tapToneAnalyzer.currentPeaks.isEmpty)
                .hint(HintText.save)
                
                // Measurements button
                Button(action: { showingMeasurements = true }) {
                    HStack(spacing: 2) {
                        Image(systemName: "list.bullet.clipboard")
                        if !tapToneAnalyzer.savedMeasurements.isEmpty {
                            Text("\(tapToneAnalyzer.savedMeasurements.count)")
                                .font(.caption2)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .hint(HintText.measurements)
                
                // Settings button
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)
                .hint(HintText.settings)
            }
            
            // Row 2: Secondary controls - icon only
            HStack(spacing: 6) {
                // Export Spectrum button
                Button(action: { exportCurrentSpectrum() }) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
                .buttonStyle(.bordered)
                .disabled(!fftAnalyzer.isRunning || fftAnalyzer.frequencies.isEmpty)
                .hint(HintText.exportSpectrum)
                
                // Auto-scale dB toggle button
                Button(action: { toggleAutoScale() }) {
                    Image(systemName: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .tint(isAutoScaleEnabled ? .blue : .gray)
                .disabled(!fftAnalyzer.isRunning || displayMagnitudes.isEmpty)
                .hint(HintText.autoScale(isEnabled: isAutoScaleEnabled))
                
                Spacer()
            }
        }
    }
    #endif
    
    /// Fixed status bar at bottom of screen
    @ViewBuilder
    private var statusBarView: some View {
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
    private var compactStatusBar: some View {
        HStack(spacing: 8) {
            // Tap detection indicator
            Circle()
                .fill(tapToneAnalyzer.tapDetected ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 10, height: 10)
            
            // Status text - truncated if needed
            Text(tapToneAnalyzer.tapDetected ? "Tap!" : "Waiting...")
                .font(.caption)
                .foregroundColor(tapToneAnalyzer.tapDetected ? .green : .secondary)
                .lineLimit(1)
            
            // Magnitude
            Text("\(tapToneAnalyzer.averageMagnitude, specifier: "%.0f")dB")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            // Progress indicator (inline)
            if tapToneAnalyzer.currentTapCount > 0 {
                Text("\(tapToneAnalyzer.currentTapCount)/\(tapToneAnalyzer.numberOfTaps)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                    .lineLimit(1)
                
                ProgressView(value: tapToneAnalyzer.tapProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 50)
            }
            
            Spacer()
            
            // Frozen indicator
            if tapToneAnalyzer.isSpectrumFrozen {
                Image(systemName: "pause.circle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
            
            // Running indicator
            Circle()
                .fill(fftAnalyzer.isRunning ? .green : .red)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(height: 36) // Fixed height
        .background(Color.secondary.opacity(0.1))
    }
    
    /// Full status bar for iPad and macOS
    @ViewBuilder
    private var fullStatusBar: some View {
        VStack(spacing: 6) {
            // Progress bar (when tapping)
            if tapToneAnalyzer.currentTapCount > 0 {
                ProgressView(value: tapToneAnalyzer.tapProgress)
                    .progressViewStyle(.linear)
            }
            
            HStack(spacing: 12) {
                // Tap detection status
                Circle()
                    .fill(tapToneAnalyzer.tapDetected ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 10, height: 10)
                
                Text(tapToneAnalyzer.tapDetected ? "Tap Detected!" : "Waiting for tap...")
                    .font(.subheadline)
                    .foregroundColor(tapToneAnalyzer.tapDetected ? .green : .secondary)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                // Current magnitude
                Text("\(tapToneAnalyzer.averageMagnitude, specifier: "%.1f") dB")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Frozen indicator
                if tapToneAnalyzer.isSpectrumFrozen {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.circle.fill")
                            .foregroundColor(.orange)
                        Text("Frozen")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // FFT Status info
                if fftAnalyzer.isRunning {
                    Text("\(fftAnalyzer.frequencies.count) bins")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Peak: \(fftAnalyzer.peakMagnitude, specifier: "%.1f") dB @ \(fftAnalyzer.peakFrequency, specifier: "%.1f") Hz")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else {
                    Text("Analyzer stopped")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                // Sequence status
                Circle()
                    .fill(tapToneAnalyzer.isDetecting ? .green : .orange)
                    .frame(width: 8, height: 8)
                
                Text(tapToneAnalyzer.statusMessage)
                    .font(.caption)
                    .foregroundColor(tapToneAnalyzer.isDetecting ? .primary : .orange)
                
                if tapToneAnalyzer.currentTapCount > 0 {
                    Text("\(tapToneAnalyzer.currentTapCount)/\(tapToneAnalyzer.numberOfTaps)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
    }
    
    /// Compact tap controls for iPhone
    @ViewBuilder
    private var compactTapControls: some View {
        VStack(spacing: 8) {
            // Row 1: Taps and threshold
            VStack(spacing: 8) {
                HStack {
                    Text("Taps:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Stepper("\(tapToneAnalyzer.numberOfTaps)", 
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
                        .onChange(of: tapToneAnalyzer.tapDetectionThreshold) { _, newValue in
                            SpectrumDisplaySettings.tapDetectionThreshold = newValue
                        }
                    Text("\(Int(tapToneAnalyzer.tapDetectionThreshold)) dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .fixedSize()
                    Button(action: {
                        tapToneAnalyzer.tapDetectionThreshold = SpectrumDisplaySettings.defaultTapDetectionThreshold
                        SpectrumDisplaySettings.tapDetectionThreshold = SpectrumDisplaySettings.defaultTapDetectionThreshold
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                // Hysteresis slider
                HStack(spacing: 6) {
                    Text("Hysteresis:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize()
                    Slider(value: $tapToneAnalyzer.hysteresisMargin, in: 1...10, step: 0.5)
                        .accessibilityLabel("Hysteresis margin")
                        .hint(HintText.hysteresis)
                        .onChange(of: tapToneAnalyzer.hysteresisMargin) { _, newValue in
                            SpectrumDisplaySettings.hysteresisMargin = newValue
                        }
                    Text("\(tapToneAnalyzer.hysteresisMargin, specifier: "%.1f") dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.purple)
                        .fixedSize()
                    Button(action: {
                        tapToneAnalyzer.hysteresisMargin = SpectrumDisplaySettings.defaultHysteresisMargin
                        SpectrumDisplaySettings.hysteresisMargin = SpectrumDisplaySettings.defaultHysteresisMargin
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                // Peak detection threshold slider — not used by MPM modes
                if !SpectrumDisplaySettings.measurementType.isMPM {
                    HStack(spacing: 6) {
                        Text("Peak Min:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize()
                        Slider(value: $tapToneAnalyzer.peakThreshold, in: -100...(-20), step: 1)
                            .accessibilityLabel("Peak detection minimum threshold")
                            .onChange(of: tapToneAnalyzer.peakThreshold) { _, newValue in
                                SpectrumDisplaySettings.peakThreshold = newValue
                            }
                        Text("\(Int(tapToneAnalyzer.peakThreshold)) dB")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                            .fixedSize()
                        Button(action: {
                            tapToneAnalyzer.peakThreshold = SpectrumDisplaySettings.defaultPeakThreshold
                            SpectrumDisplaySettings.peakThreshold = SpectrumDisplaySettings.defaultPeakThreshold
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Row 2: Action buttons - all buttons always visible to prevent layout shifts
            HStack(spacing: 8) {
                // New Tap button
                Button(action: {
                    tapToneAnalyzer.startTapSequence()
                }) {
                    Label("New Tap", systemImage: "hand.tap")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!fftAnalyzer.isRunning ||
                          !tapToneAnalyzer.isReadyForDetection ||
                          tapToneAnalyzer.isDetecting)
                .hint(HintText.newTap)
                
                // Pause/Resume button - for multi-tap and material sequences
                Button(action: {
                    if tapToneAnalyzer.isDetectionPaused {
                        tapToneAnalyzer.resumeTapDetection()
                    } else {
                        tapToneAnalyzer.pauseTapDetection()
                    }
                }) {
                    Label(
                        tapToneAnalyzer.isDetectionPaused ? "Resume" : "Pause",
                        systemImage: tapToneAnalyzer.isDetectionPaused ? "play.circle" : "pause.circle"
                    )
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(!pauseResumeButtonEnabled)
                .hint(tapToneAnalyzer.isDetectionPaused ? HintText.resumeDetection : HintText.pauseDetection)
                
                // Cancel button - only enabled during active multi-tap detection
                Button(action: {
                    tapToneAnalyzer.cancelTapSequence()
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
    
    /// Regular tap controls for iPad and macOS
    @ViewBuilder
    private var regularTapControls: some View {
        ViewThatFits(in: .horizontal) {
            // Wide layout - all controls in one row
            regularTapControlsWide
            
            // Narrow layout - two rows
            regularTapControlsNarrow
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
    
    /// Wide layout for regular tap controls - all in one row
    @ViewBuilder
    private var regularTapControlsWide: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("Taps:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(tapToneAnalyzer.numberOfTaps)")
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
                    .onChange(of: tapToneAnalyzer.tapDetectionThreshold) { _, newValue in
                        SpectrumDisplaySettings.tapDetectionThreshold = newValue
                    }
                Text("\(Int(tapToneAnalyzer.tapDetectionThreshold)) dB")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                    .fixedSize()
                Button(action: {
                    tapToneAnalyzer.tapDetectionThreshold = SpectrumDisplaySettings.defaultTapDetectionThreshold
                    SpectrumDisplaySettings.tapDetectionThreshold = SpectrumDisplaySettings.defaultTapDetectionThreshold
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset to default")
            }
            .hint(HintText.threshold)
            
            Divider()
                .frame(height: 20)
            
            // Hysteresis margin slider
            HStack(spacing: 4) {
                Text("Hysteresis:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize()
                Slider(value: $tapToneAnalyzer.hysteresisMargin, in: 1...10, step: 0.5)
                    .frame(width: 60)
                    .accessibilityLabel("Hysteresis margin")
                    .onChange(of: tapToneAnalyzer.hysteresisMargin) { _, newValue in
                        SpectrumDisplaySettings.hysteresisMargin = newValue
                    }
                Text("\(tapToneAnalyzer.hysteresisMargin, specifier: "%.1f") dB")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.purple)
                    .fixedSize()
                Button(action: {
                    tapToneAnalyzer.hysteresisMargin = SpectrumDisplaySettings.defaultHysteresisMargin
                    SpectrumDisplaySettings.hysteresisMargin = SpectrumDisplaySettings.defaultHysteresisMargin
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset to default")
            }
            .hint(HintText.hysteresis)
            
            // Peak detection threshold slider — not used by MPM modes
            if !SpectrumDisplaySettings.measurementType.isMPM {
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
                        .onChange(of: tapToneAnalyzer.peakThreshold) { _, newValue in
                            SpectrumDisplaySettings.peakThreshold = newValue
                        }
                    Text("\(Int(tapToneAnalyzer.peakThreshold)) dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                        .fixedSize()
                    Button(action: {
                        tapToneAnalyzer.peakThreshold = SpectrumDisplaySettings.defaultPeakThreshold
                        SpectrumDisplaySettings.peakThreshold = SpectrumDisplaySettings.defaultPeakThreshold
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reset to default")
                }
            }

            Spacer()

            // Tap sequence buttons
            Button(action: {
                tapToneAnalyzer.startTapSequence()
            }) {
                Label("New Tap", systemImage: "hand.tap")
            }
            .buttonStyle(.bordered)
            .disabled(!fftAnalyzer.isRunning ||
                      !tapToneAnalyzer.isReadyForDetection ||
                      tapToneAnalyzer.isDetecting)
            .hint(HintText.newTap)
            
            // Pause/Resume button - for multi-tap and material sequences
            Button(action: {
                if tapToneAnalyzer.isDetectionPaused {
                    tapToneAnalyzer.resumeTapDetection()
                } else {
                    tapToneAnalyzer.pauseTapDetection()
                }
            }) {
                Label(
                    tapToneAnalyzer.isDetectionPaused ? "Resume" : "Pause",
                    systemImage: tapToneAnalyzer.isDetectionPaused ? "play.circle" : "pause.circle"
                )
            }
            .buttonStyle(.bordered)
            .disabled(!pauseResumeButtonEnabled)
            .hint(tapToneAnalyzer.isDetectionPaused ? HintText.resumeDetection : HintText.pauseDetection)
            
            // Cancel button - only enabled during active multi-tap detection
            Button(action: {
                tapToneAnalyzer.cancelTapSequence()
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
    private var regularTapControlsNarrow: some View {
        VStack(spacing: 8) {
            // Row 1: Sliders and settings
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Taps:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(tapToneAnalyzer.numberOfTaps)")
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
                        .onChange(of: tapToneAnalyzer.tapDetectionThreshold) { _, newValue in
                            SpectrumDisplaySettings.tapDetectionThreshold = newValue
                        }
                    Text("\(Int(tapToneAnalyzer.tapDetectionThreshold)) dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .fixedSize()
                    Button(action: {
                        tapToneAnalyzer.tapDetectionThreshold = SpectrumDisplaySettings.defaultTapDetectionThreshold
                        SpectrumDisplaySettings.tapDetectionThreshold = SpectrumDisplaySettings.defaultTapDetectionThreshold
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reset to default")
                }
                .hint(HintText.threshold)
                
                Divider()
                    .frame(height: 20)
                
                // Hysteresis margin slider
                HStack(spacing: 4) {
                    Text("Hysteresis:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize()
                    Slider(value: $tapToneAnalyzer.hysteresisMargin, in: 1...10, step: 0.5)
                        .frame(width: 60)
                        .accessibilityLabel("Hysteresis margin")
                        .onChange(of: tapToneAnalyzer.hysteresisMargin) { _, newValue in
                            SpectrumDisplaySettings.hysteresisMargin = newValue
                        }
                    Text("\(tapToneAnalyzer.hysteresisMargin, specifier: "%.1f") dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.purple)
                        .fixedSize()
                    Button(action: {
                        tapToneAnalyzer.hysteresisMargin = SpectrumDisplaySettings.defaultHysteresisMargin
                        SpectrumDisplaySettings.hysteresisMargin = SpectrumDisplaySettings.defaultHysteresisMargin
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reset to default")
                }
                .hint(HintText.hysteresis)
                
                // Peak detection threshold slider — not used by MPM modes
                if !SpectrumDisplaySettings.measurementType.isMPM {
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
                            .onChange(of: tapToneAnalyzer.peakThreshold) { _, newValue in
                                SpectrumDisplaySettings.peakThreshold = newValue
                            }
                        Text("\(Int(tapToneAnalyzer.peakThreshold)) dB")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                            .fixedSize()
                        Button(action: {
                            tapToneAnalyzer.peakThreshold = SpectrumDisplaySettings.defaultPeakThreshold
                            SpectrumDisplaySettings.peakThreshold = SpectrumDisplaySettings.defaultPeakThreshold
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Reset to default")
                    }
                }

                Spacer()
            }
            
            // Row 2: Action buttons
            HStack(spacing: 8) {
                // Tap sequence buttons
                Button(action: {
                    tapToneAnalyzer.startTapSequence()
                }) {
                    Label("New Tap", systemImage: "hand.tap")
                }
                .buttonStyle(.bordered)
                .disabled(!fftAnalyzer.isRunning ||
                          !tapToneAnalyzer.isReadyForDetection ||
                          tapToneAnalyzer.isDetecting)
                .hint(HintText.newTap)
                
                // Pause/Resume button - for multi-tap and material sequences
                Button(action: {
                    if tapToneAnalyzer.isDetectionPaused {
                        tapToneAnalyzer.resumeTapDetection()
                    } else {
                        tapToneAnalyzer.pauseTapDetection()
                    }
                }) {
                    Label(
                        tapToneAnalyzer.isDetectionPaused ? "Resume" : "Pause",
                        systemImage: tapToneAnalyzer.isDetectionPaused ? "play.circle" : "pause.circle"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(!pauseResumeButtonEnabled)
                .hint(tapToneAnalyzer.isDetectionPaused ? HintText.resumeDetection : HintText.pauseDetection)
                
                // Cancel button - only enabled during active multi-tap detection
                Button(action: {
                    tapToneAnalyzer.cancelTapSequence()
                }) {
                    Label("Cancel", systemImage: "xmark.circle")
                        .foregroundStyle(cancelButtonEnabled ? Color.orange : Color.gray)
                }
                .buttonStyle(.bordered)
                .disabled(!cancelButtonEnabled)
                .hint(HintText.cancel)
                
                Spacer()
            }
        }
    }
    
    // Computed properties to explicitly depend on @Published properties
    private var displayFrequencies: [Float] {
        tapToneAnalyzer.isSpectrumFrozen ? tapToneAnalyzer.frozenFrequencies : fftAnalyzer.frequencies
    }
    
    private var displayMagnitudes: [Float] {
        tapToneAnalyzer.isSpectrumFrozen ? tapToneAnalyzer.frozenMagnitudes : fftAnalyzer.magnitudes
    }
    
    /// Per-phase spectra for material/brace measurements, formatted for SpectrumView overlay
    private var materialSpectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)] {
        let measurementType = SpectrumDisplaySettings.measurementType
        guard !measurementType.isGuitar else { return [] }
        var result: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)] = []
        if let spec = tapToneAnalyzer.longitudinalSpectrum {
            result.append((magnitudes: spec.magnitudes, frequencies: spec.frequencies, color: .blue, label: "Longitudinal (L)"))
        }
        if measurementType == .material, let spec = tapToneAnalyzer.crossSpectrum {
            result.append((magnitudes: spec.magnitudes, frequencies: spec.frequencies, color: .orange, label: "Cross-grain (C)"))
        }
        if measurementType == .material, let spec = tapToneAnalyzer.flcSpectrum {
            result.append((magnitudes: spec.magnitudes, frequencies: spec.frequencies, color: .purple, label: "FLC"))
        }
        return result
    }
    
    private var realTimeSpectrumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Prepare threshold lines for the chart
            let thresholds: [(value: Float, label: String, color: Color, lineWidth: CGFloat, dash: [CGFloat])] = {
                var lines: [(Float, String, Color, CGFloat, [CGFloat])] = []
                
                // Rising threshold (main threshold line)
                let risingThreshold = tapToneAnalyzer.tapDetectionThreshold
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
                if tapToneAnalyzer.hysteresisMargin > 0.5 {
                    let fallingThreshold = risingThreshold - tapToneAnalyzer.hysteresisMargin
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
                let peakThreshold = tapToneAnalyzer.peakThreshold
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
            SpectrumView(
                frequencies: displayFrequencies,
                magnitudes: displayMagnitudes,
                minFreq: $minFreq,
                maxFreq: $maxFreq,
                minDB: $minDB,
                maxDB: $maxDB,
                isLogarithmic: .constant(false),
                peaks: tapToneAnalyzer.visiblePeaks,
                showModeBoundaries: true,
                onFrequencyRangeChanged: updateFrequencyInputFields,
                annotationOffsets: $tapToneAnalyzer.peakAnnotationOffsets,
                materialSpectra: materialSpectra,
                thresholdLines: thresholds,
                onResetLabels: {
                    tapToneAnalyzer.resetAllAnnotationOffsets()
                },
                hasLabelsToReset: !tapToneAnalyzer.peakAnnotationOffsets.isEmpty,
                measurementType: SpectrumDisplaySettings.measurementType,
                selectedLongitudinalPeakID: tapToneAnalyzer.effectiveLongitudinalPeakID,
                selectedCrossPeakID: tapToneAnalyzer.effectiveCrossPeakID,
                selectedFlcPeakID: tapToneAnalyzer.effectiveFlcPeakID
            )
            // Force view to update when any relevant state changes
            .id("\(tapToneAnalyzer.isSpectrumFrozen)-\(fftAnalyzer.isRunning)-\(displayFrequencies.count)-\(displayMagnitudes.count)")
            .frame(minHeight: 250, maxHeight: .infinity)  // Allow to expand vertically
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(10)
            .overlay(
                Group {
                    if !fftAnalyzer.isRunning {
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
                    } else if fftAnalyzer.frequencies.isEmpty {
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
                                print("✅ Overlay: CHART VISIBLE (running=\(fftAnalyzer.isRunning), freq count=\(fftAnalyzer.frequencies.count), mag count=\(fftAnalyzer.magnitudes.count))")
                            }
                    }
                }
            )
        }
    }
    
    private var decayTimeView: some View {
        Group {
            if !SpectrumDisplaySettings.measurementType.isGuitar {
                // Material/brace measurement instructions
                materialInstructionsView
            } else {
                // Guitar mode: Ring-Out Time and Tap Tone Ratio
                guitarMetricsView
            }
        }
    }
    
    /// Material measurement instructions panel
    private var materialInstructionsView: some View {
        GroupBox("Material Measurement") {
            VStack(alignment: .leading, spacing: 8) {
                // Current phase indicator
                HStack {
                    Circle()
                        .fill(materialPhaseColor)
                        .frame(width: 10, height: 10)
                    Text(tapToneAnalyzer.materialTapPhase.shortStatus)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(materialPhaseColor)
                    Spacer()
                    Text("Step \(materialPhaseStep)/\(SpectrumDisplaySettings.measurementType == .brace ? 1 : (SpectrumDisplaySettings.measureFlc ? 3 : 2))")
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
    private var materialPhaseColor: Color {
        switch tapToneAnalyzer.materialTapPhase {
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
    private var materialPhaseStep: Int {
        switch tapToneAnalyzer.materialTapPhase {
        case .notStarted, .capturingLongitudinal: return 1
        case .waitingForCrossTap, .capturingCross: return 2
        case .waitingForFlcTap, .capturingFlc: return 3
        case .complete: return SpectrumDisplaySettings.measureFlc ? 3 : 2
        }
    }
    
    /// Icon for current material measurement phase
    private var materialPhaseIcon: String {
        switch tapToneAnalyzer.materialTapPhase {
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
    private var materialPhaseTitle: String {
        let isBrace = SpectrumDisplaySettings.measurementType == .brace
        switch tapToneAnalyzer.materialTapPhase {
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
    private var materialPhaseDescription: String {
        let isBrace = SpectrumDisplaySettings.measurementType == .brace
        switch tapToneAnalyzer.materialTapPhase {
        case .notStarted:
            if isBrace {
                return "Press 'New Tap' to begin the brace fL measurement."
            }
            let tapWord = SpectrumDisplaySettings.measureFlc ? "three-tap" : "two-tap"
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
            let flcPart = SpectrumDisplaySettings.measureFlc ? ", and FLC (purple)" : ""
            return "All modes captured! Review the L (blue), C (orange)\(flcPart) peak selections in the Results panel. Adjust if the auto-selection isn't correct."
        }
    }
    
    /// Guitar mode metrics view (Ring-Out Time and Tap Tone Ratio)
    private var guitarMetricsView: some View {
        HStack(spacing: 12) {
            // Ring-Out Time
            GroupBox("Ring-Out Time") {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundColor(.blue)
                    
                    if let decay = tapToneAnalyzer.currentDecayTime {
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
                    
                    if let ratio = tapToneAnalyzer.calculateTapToneRatio() {
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
    
    // MARK: - Actions
    
    private func toggleAnalyzer() {
        if fftAnalyzer.isRunning {
            tapToneAnalyzer.stop()
        } else {
            #if os(iOS)
            // On iOS, request microphone permission first
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.startAnalyzer()
                        } else {
                            print("❌ Microphone permission denied")
                        }
                    }
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.startAnalyzer()
                        } else {
                            print("❌ Microphone permission denied")
                        }
                    }
                }
            }
            #else
            // On macOS, start directly
            startAnalyzer()
            #endif
        }
    }
    
    private func startAnalyzer() {
        // AVAudioEngine.start() is safe to call from the main thread
        // Don't dispatch to background - this can cause deadlocks when the engine
        // tries to update @Published properties on main thread
        do {
            #if os(iOS)
            // Configure audio session for iOS
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
            #endif
            
            try self.tapToneAnalyzer.start()
        } catch {
            print("❌ Failed to start analyzer: \(error)")
        }
    }
    
    private func saveMeasurement() {
        // MPM measurements have no spectrum to capture — save directly
        if SpectrumDisplaySettings.measurementType.isMPM {
            tapToneAnalyzer.saveMeasurement(
                tapLocation: tapLocation.isEmpty ? nil : tapLocation,
                notes: notes.isEmpty ? nil : notes,
                includeSpectrum: false,
                microphoneName: fftAnalyzer.selectedInputDevice?.name,
                microphoneUID: fftAnalyzer.selectedInputDevice?.uid,
                calibrationName: fftAnalyzer.activeCalibration?.name
            )
            tapLocation = ""
            notes = ""
            showingSaveSheet = false
            return
        }

        isSavingMeasurement = true
        
        // Capture the spectrum image
        DispatchQueue.main.async {
            let spectrumView = self.createExportableSpectrumView()
            let renderer = ImageRenderer(content: spectrumView)
            
            // Use display scale from environment
            renderer.scale = self.displayScale
            
            var imageData: Data?
            
            #if os(iOS)
            if let uiImage = renderer.uiImage,
               let pngData = uiImage.pngData() {
                imageData = pngData
            }
            #elseif os(macOS)
            if let nsImage = renderer.nsImage,
               let tiffData = nsImage.tiffRepresentation,
               let bitmapImage = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                imageData = pngData
            }
            #endif
            
            let measurementType = SpectrumDisplaySettings.measurementType
            
            // Build a helper to create a SpectrumSnapshot from a phase spectrum
            func makePhaseSnapshot(magnitudes: [Float], frequencies: [Float]) -> SpectrumSnapshot {
                SpectrumSnapshot(
                    frequencies: frequencies,
                    magnitudes: magnitudes,
                    minFreq: self.minFreq,
                    maxFreq: self.maxFreq,
                    minDB: self.minDB,
                    maxDB: self.maxDB,
                    isLogarithmic: false,
                    showUnknownModes: SpectrumDisplaySettings.showUnknownModes,
                    guitarType: SpectrumDisplaySettings.guitarType,
                    measurementType: measurementType,
                    maxPeaks: self.tapToneAnalyzer.maxPeaks,
                    materialLength: measurementType == .material ? SpectrumDisplaySettings.materialLength
                                  : measurementType == .brace   ? SpectrumDisplaySettings.braceLength : nil,
                    materialWidth: measurementType == .material ? SpectrumDisplaySettings.materialWidth
                                 : measurementType == .brace   ? SpectrumDisplaySettings.braceWidth : nil,
                    materialThickness: measurementType == .material ? SpectrumDisplaySettings.materialThickness
                                     : measurementType == .brace   ? SpectrumDisplaySettings.braceThickness : nil,
                    materialMass: measurementType == .material ? SpectrumDisplaySettings.materialMass
                                : measurementType == .brace   ? SpectrumDisplaySettings.braceMass : nil
                )
            }
            
            // For material/brace: build per-phase snapshots. For guitar: build a single snapshot.
            let longSnap: SpectrumSnapshot? = {
                guard !measurementType.isGuitar,
                      let spec = self.tapToneAnalyzer.longitudinalSpectrum else { return nil }
                return makePhaseSnapshot(magnitudes: spec.magnitudes, frequencies: spec.frequencies)
            }()
            let crossSnap: SpectrumSnapshot? = {
                guard measurementType == .material,
                      let spec = self.tapToneAnalyzer.crossSpectrum else { return nil }
                return makePhaseSnapshot(magnitudes: spec.magnitudes, frequencies: spec.frequencies)
            }()
            let flcSnap: SpectrumSnapshot? = {
                guard measurementType == .material,
                      let spec = self.tapToneAnalyzer.flcSpectrum else { return nil }
                return makePhaseSnapshot(magnitudes: spec.magnitudes, frequencies: spec.frequencies)
            }()
            
            // Save with all data
            self.tapToneAnalyzer.saveMeasurement(
                tapLocation: self.tapLocation.isEmpty ? nil : self.tapLocation,
                notes: self.notes.isEmpty ? nil : self.notes,
                includeSpectrum: true,
                chartImageData: imageData,
                longitudinalSnapshot: longSnap,
                crossSnapshot: crossSnap,
                flcSnapshot: flcSnap,
                annotationOffsets: self.tapToneAnalyzer.peakAnnotationOffsets,
                selectedLongitudinalPeakID: self.tapToneAnalyzer.effectiveLongitudinalPeakID,
                selectedCrossPeakID: self.tapToneAnalyzer.effectiveCrossPeakID,
                selectedFlcPeakID: self.tapToneAnalyzer.effectiveFlcPeakID,
                microphoneName: self.fftAnalyzer.selectedInputDevice?.name,
                microphoneUID: self.fftAnalyzer.selectedInputDevice?.uid,
                calibrationName: self.fftAnalyzer.activeCalibration?.name
            )
            
            self.tapLocation = ""
            self.notes = ""
            self.showingSaveSheet = false
            self.isSavingMeasurement = false
        }
    }
    
    // MARK: - Spectrum Display Helpers
    
    private func updateFrequencyInputFields() {
        minFreqInput = String(format: "%.0f", minFreq)
        maxFreqInput = String(format: "%.0f", maxFreq)
    }
    
    /// Expand the frequency display range to ensure the given frequency is visible.
    /// Adds 10% padding above/below. Used when material/brace peaks are auto-selected
    /// to ensure they're always in view even if outside the persisted default range.
    private func expandFreqRangeToInclude(_ frequency: Float) {
        guard !SpectrumDisplaySettings.measurementType.isGuitar else { return }
        let padding = frequency * 0.10
        if frequency > maxFreq {
            maxFreq = frequency + padding
            maxFreqInput = String(format: "%.0f", maxFreq)
        }
        if frequency < minFreq {
            minFreq = max(1, frequency - padding)
            minFreqInput = String(format: "%.0f", minFreq)
        }
    }
    
    private func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.1fk Hz", freq / 1000)
        } else {
            return String(format: "%.0f Hz", freq)
        }
    }
    
    /// Auto-scale the dB range to fit the current signal
    private func autoScaleDB() {
        let mags = displayMagnitudes.filter { $0 > -100 && $0 < 20 }
        guard !mags.isEmpty else {
            print("⚠️ No valid magnitudes to auto-scale")
            return
        }
        
        let minMag = mags.min() ?? -100
        let maxMag = mags.max() ?? 0
        
        // Add 10% padding above and below
        let range = maxMag - minMag
        let padding = max(10, range * 0.1)  // At least 10 dB padding
        
        let newMinDB = max(-120, minMag - padding)
        let newMaxDB = min(20, maxMag + padding)
        
        // Ensure minimum 20 dB range
        if newMaxDB - newMinDB < 20 {
            let center = (newMinDB + newMaxDB) / 2
            minDB = center - 10
            maxDB = center + 10
        } else {
            minDB = newMinDB
            maxDB = newMaxDB
        }
        
        // Update input fields
        minDBInput = String(format: "%.0f", minDB)
        maxDBInput = String(format: "%.0f", maxDB)
        
        print("📏 Auto-scaled dB range: \(String(format: "%.1f", minDB)) to \(String(format: "%.1f", maxDB)) dB (signal range: \(String(format: "%.1f", minMag)) to \(String(format: "%.1f", maxMag)) dB)")
    }
    
    /// Toggles auto-scale mode on/off
    private func toggleAutoScale() {
        isAutoScaleEnabled.toggle()
        
        if isAutoScaleEnabled {
            print("🔄 Auto-scale dB enabled - will scale on each update")
            // Perform initial auto-scale
            autoScaleDB()
        } else {
            print("🔄 Auto-scale dB disabled - resetting to default range")
            // Reset to default values
            resetDBToDefaults()
        }
    }
    
    /// Resets the dB range to default settings
    private func resetDBToDefaults() {
        minDB = SpectrumDisplaySettings.minMagnitude
        maxDB = SpectrumDisplaySettings.maxMagnitude
        minDBInput = String(format: "%.0f", minDB)
        maxDBInput = String(format: "%.0f", maxDB)
        print("↩️ Reset dB range to defaults: \(minDB) to \(maxDB) dB")
    }

    
    // MARK: - Spectrum Export
    
    private func exportCurrentSpectrum() {
        isExportingSpectrum = true
        
        DispatchQueue.main.async {
            let spectrumView = self.createExportableSpectrumView()
            let renderer = ImageRenderer(content: spectrumView)
            
            // Use display scale from environment
            renderer.scale = self.displayScale
            
            // Get PNG data using helper
            #if os(iOS)
            guard let uiImage = renderer.uiImage,
                  let pngData = uiImage.pngData() else {
                self.isExportingSpectrum = false
                return
            }
            #elseif os(macOS)
            guard let nsImage = renderer.nsImage,
                  let tiffData = nsImage.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
                self.isExportingSpectrum = false
                return
            }
            #endif
            
            // Export using platform-appropriate method
            let filename = "spectrum-\(Int(Date().timeIntervalSince1970)).png"
            FileExportHelper.exportFile(data: pngData, filename: filename, contentType: .png) { success in
                self.isExportingSpectrum = false
                if !success {
                    print("❌ Failed to export spectrum")
                }
            }
        }
    }
    
    // MARK: - PDF Report Export

    /// Renders the current spectrum as PNG, builds report data, generates a PDF, and exports it.
    @MainActor
    private func exportPDFReport() {
        isGeneratingReport = true

        // Render current spectrum to PNG data (same technique as save/exportSpectrum)
        let spectrumView = createExportableSpectrumView()
        let imageRenderer = ImageRenderer(content: spectrumView)
        imageRenderer.scale = displayScale

        var spectrumImageData: Data?
        #if os(iOS)
        if let uiImage = imageRenderer.uiImage {
            spectrumImageData = uiImage.pngData()
        }
        #elseif os(macOS)
        if let nsImage = imageRenderer.nsImage,
           let tiffData = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData) {
            spectrumImageData = bitmap.representation(using: .png, properties: [:])
        }
        #endif

        // Compute material properties if applicable
        let measurementType = SpectrumDisplaySettings.measurementType
        var materialProps: MaterialProperties? = nil
        if measurementType == .material || measurementType == .plateMPM {
            let effLong = tapToneAnalyzer.effectiveLongitudinalPeakID
            let effCross = tapToneAnalyzer.effectiveCrossPeakID
            let effFlc = tapToneAnalyzer.effectiveFlcPeakID
            let allMaterialPeaks = tapToneAnalyzer.longitudinalPeaks + tapToneAnalyzer.crossPeaks + tapToneAnalyzer.flcPeaks + tapToneAnalyzer.currentPeaks
            if let longPeak = allMaterialPeaks.first(where: { $0.id == effLong }),
               let crossPeak = allMaterialPeaks.first(where: { $0.id == effCross }) {
                let flcFreq: Float? = allMaterialPeaks.first(where: { $0.id == effFlc })?.frequency
                let dims = MaterialDimensions(
                    lengthMM: SpectrumDisplaySettings.materialLength,
                    widthMM: SpectrumDisplaySettings.materialWidth,
                    thicknessMM: SpectrumDisplaySettings.materialThickness,
                    massGrams: SpectrumDisplaySettings.materialMass
                )
                if dims.length > 0 && dims.mass > 0 {
                    materialProps = MaterialProperties(
                        dimensions: dims,
                        fundamentalFrequencyLong: longPeak.frequency,
                        fundamentalFrequencyCross: crossPeak.frequency,
                        fundamentalFrequencyFlc: flcFreq
                    )
                }
            }
        } else if measurementType == .brace || measurementType == .braceMPM {
            let effLong = tapToneAnalyzer.effectiveLongitudinalPeakID
            let allBracePeaks = tapToneAnalyzer.longitudinalPeaks + tapToneAnalyzer.currentPeaks
            if let longPeak = allBracePeaks.first(where: { $0.id == effLong }) {
                let dims = MaterialDimensions(
                    lengthMM: SpectrumDisplaySettings.braceLength,
                    widthMM: SpectrumDisplaySettings.braceWidth,
                    thicknessMM: SpectrumDisplaySettings.braceThickness,
                    massGrams: SpectrumDisplaySettings.braceMass
                )
                if dims.length > 0 && dims.mass > 0 {
                    materialProps = MaterialProperties(
                        dimensions: dims,
                        fundamentalFrequencyLong: longPeak.frequency,
                        fundamentalFrequencyCross: longPeak.frequency,
                        fundamentalFrequencyFlc: nil
                    )
                }
            }
        }

        // Only include peaks within the currently displayed frequency range
        let rangeFilteredPeaks = tapToneAnalyzer.currentPeaks.filter {
            $0.frequency >= minFreq && $0.frequency <= maxFreq
        }

        let reportData = PDFReportData(
            timestamp: Date(),
            tapLocation: tapLocation.isEmpty ? nil : tapLocation,
            notes: notes.isEmpty ? nil : notes,
            measurementType: measurementType,
            guitarType: SpectrumDisplaySettings.guitarType,
            peaks: rangeFilteredPeaks,
            hiddenPeakIDs: tapToneAnalyzer.hiddenPeakIDs,
            decayTime: tapToneAnalyzer.currentDecayTime,
            tapToneRatio: tapToneAnalyzer.calculateTapToneRatio(),
            spectrumImageData: spectrumImageData,
            minFreq: minFreq,
            maxFreq: maxFreq,
            materialProperties: materialProps,
            selectedLongitudinalPeakID: tapToneAnalyzer.effectiveLongitudinalPeakID,
            selectedCrossPeakID: tapToneAnalyzer.effectiveCrossPeakID,
            selectedFlcPeakID: tapToneAnalyzer.effectiveFlcPeakID,
            microphoneName: fftAnalyzer.selectedInputDevice?.name,
            calibrationName: fftAnalyzer.activeCalibration?.name,
            guitarBodyLength: SpectrumDisplaySettings.guitarBodyLength,
            guitarBodyWidth: SpectrumDisplaySettings.guitarBodyWidth,
            plateStiffness: SpectrumDisplaySettings.plateStiffness,
            plateStiffnessPreset: SpectrumDisplaySettings.plateStiffnessPreset
        )

        guard let pdfData = PDFReportGenerator.generate(data: reportData) else {
            print("❌ Failed to generate PDF report")
            isGeneratingReport = false
            return
        }

        MeasurementFileExporter.exportPDF(data: pdfData, basename: reportData.baseFilename) {
            self.isGeneratingReport = false
        }
    }

    @ViewBuilder
    private func createExportableSpectrumView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Guitar Tap Tone Analysis - Frequency Response")
                    .font(.title)
                    .fontWeight(.bold)
                
                HStack {
                    Text("Date: \(Date().formatted())")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("Range: \(formatFrequency(minFreq)) - \(formatFrequency(maxFreq))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text("\(Int(minDB)) to \(Int(maxDB)) dB")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                if !tapToneAnalyzer.currentPeaks.isEmpty {
                    Text("Detected Peaks: \(tapToneAnalyzer.currentPeaks.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            
            // Chart - use static export version to avoid ImageRenderer issues
            ExportableSpectrumChart(
                frequencies: tapToneAnalyzer.isSpectrumFrozen ? 
                    tapToneAnalyzer.frozenFrequencies : fftAnalyzer.frequencies,
                magnitudes: tapToneAnalyzer.isSpectrumFrozen ? 
                    tapToneAnalyzer.frozenMagnitudes : fftAnalyzer.magnitudes,
                minFreq: minFreq,
                maxFreq: maxFreq,
                minDB: minDB,
                maxDB: maxDB,
                isLogarithmic: false,
                peaks: tapToneAnalyzer.visiblePeaks,
                showModeBoundaries: true,
                annotationOffsets: tapToneAnalyzer.peakAnnotationOffsets,
                showUnknownModes: SpectrumDisplaySettings.showUnknownModes,
                measurementType: SpectrumDisplaySettings.measurementType,
                selectedLongitudinalPeakID: tapToneAnalyzer.effectiveLongitudinalPeakID,
                selectedCrossPeakID: tapToneAnalyzer.effectiveCrossPeakID,
                selectedFlcPeakID: tapToneAnalyzer.effectiveFlcPeakID,
                materialSpectra: materialSpectra
            )
            .frame(width: 1400, height: 800)
            .padding()
            
            // Peak Summary
            if !tapToneAnalyzer.currentPeaks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Detected Peaks Summary")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    HStack(spacing: 20) {
                        ForEach(tapToneAnalyzer.currentPeaks.prefix(8).sorted(by: { $0.frequency < $1.frequency })) { peak in
                            let mode = GuitarMode.classify(frequency: peak.frequency)
                            VStack(spacing: 4) {
                                Text("\(peak.frequency, specifier: "%.1f") Hz")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                Text(mode.displayName)
                                    .font(.caption2)
                                    .foregroundColor(mode.color)
                                Text("\(peak.magnitude, specifier: "%.1f") dB")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(mode.color.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
            }
            
            // Legend
            HStack(spacing: 20) {
                Text("Guitar Modes:")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                ForEach([GuitarMode.air, .top, .back, .dipole, .ringMode], id: \.self) { mode in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(mode.color)
                            .frame(width: 12, height: 12)
                        Text(mode.displayName)
                            .font(.caption)
                    }
                }
            }
            .padding()
        }
        .background(Color.white)
        .padding()
    }
}

// MARK: - Preview

#Preview {
    TapToneAnalysisView()
}
