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
    
    // Spectrum display state
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
    
    // Environment
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.displayScale) var displayScale
    
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
    /// macOS layout with optional side panel for metrics
    @ViewBuilder
    private var macOSLayout: some View {
        Group {
            if showingMetrics && showingResults {
                // Both panels visible - three column layout
                HSplitView {
                    // Main content
                    mainContentView
                        .frame(minWidth: 600)
                    
                    // Results panel (middle)
                    TapAnalysisResultsView(
                        analyzer: tapToneAnalyzer,
                        fftAnalyzer: fftAnalyzer,
                        minFreq: minFreq,
                        maxFreq: maxFreq
                    )
                    .frame(minWidth: 300, idealWidth: 350, maxWidth: 450)
                    
                    // Metrics panel (right)
                    ScrollView {
                        FFTAnalysisMetricsView(analyzer: fftAnalyzer)
                            .padding()
                    }
                    .frame(minWidth: 300, idealWidth: 350, maxWidth: 450)
                }
            } else if showingMetrics {
                // Only metrics panel
                HSplitView {
                    // Main content
                    mainContentView
                        .frame(minWidth: 600)
                    
                    // Metrics panel (resizable)
                    ScrollView {
                        FFTAnalysisMetricsView(analyzer: fftAnalyzer)
                            .padding()
                    }
                    .frame(minWidth: 300, idealWidth: 350, maxWidth: 450)
                }
            } else if showingResults {
                // Only results panel
                HSplitView {
                    // Main content
                    mainContentView
                        .frame(minWidth: 600)
                    
                    // Results panel (resizable)
                    TapAnalysisResultsView(
                        analyzer: tapToneAnalyzer,
                        fftAnalyzer: fftAnalyzer,
                        minFreq: minFreq,
                        maxFreq: maxFreq
                    )
                    .frame(minWidth: 300, idealWidth: 350, maxWidth: 450)
                }
            } else {
                // No panels
                mainContentView
            }
        }
        .sheet(isPresented: $showingMeasurements) {
            MeasurementsListView(analyzer: tapToneAnalyzer)
        }
        .sheet(isPresented: $showingSaveSheet) {
            SaveMeasurementSheet(
                tapLocation: $tapLocation,
                notes: $notes,
                onSave: saveMeasurement
            )
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
                fftAnalyzer: fftAnalyzer
            )
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
            }
        }
    }
    #endif
    
    #if os(iOS)
    /// iOS layout with adaptive metrics display
    @ViewBuilder
    private var iOSLayout: some View {
        NavigationView {
            // Only show side panels on iPad (regular width), never on iPhone even in landscape
            if UIDevice.current.userInterfaceIdiom == .pad && 
               horizontalSizeClass == .regular && 
               (showingMetrics || showingResults) {
                // iPad: Side-by-side layout with optional panels
                HStack(spacing: 0) {
                    mainContentView
                        .frame(maxWidth: .infinity)
                    
                    if showingResults {
                        Divider()
                        
                        TapAnalysisResultsView(
                            analyzer: tapToneAnalyzer,
                            fftAnalyzer: fftAnalyzer,
                            minFreq: minFreq,
                            maxFreq: maxFreq
                        )
                        .frame(width: 350)
                    }
                    
                    if showingMetrics {
                        Divider()
                        
                        ScrollView {
                            FFTAnalysisMetricsView(analyzer: fftAnalyzer)
                                .padding()
                        }
                        .frame(width: 350)
                    }
                }
            } else {
                // iPhone (all orientations) - always use full screen with sheets
                mainContentView
            }
        }
        .navigationViewStyle(.stack) // Prevents iPad split view on iPhone landscape
        .sheet(isPresented: $showingMeasurements) {
            MeasurementsListView(analyzer: tapToneAnalyzer)
        }
        .sheet(isPresented: $showingSaveSheet) {
            SaveMeasurementSheet(
                tapLocation: $tapLocation,
                notes: $notes,
                onSave: saveMeasurement
            )
        }
        // Results sheet - show on iPhone or when not in iPad side-by-side mode
        .sheet(isPresented: Binding(
            get: { 
                showingResults && (
                    UIDevice.current.userInterfaceIdiom != .pad || 
                    horizontalSizeClass != .regular
                )
            },
            set: { if !$0 { showingResults = false } }
        )) {
            NavigationView {
                TapAnalysisResultsView(
                    analyzer: tapToneAnalyzer,
                    fftAnalyzer: fftAnalyzer,
                    minFreq: minFreq,
                    maxFreq: maxFreq
                )
                .navigationTitle("Analysis Results")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingResults = false
                        }
                    }
                    #else
                    ToolbarItem(placement: .automatic) {
                        Button("Done") {
                            showingResults = false
                        }
                    }
                    #endif
                }
            }
        }
        // Metrics sheet - show on iPhone or when not in iPad side-by-side mode
        .sheet(isPresented: Binding(
            get: { 
                showingMetrics && (
                    UIDevice.current.userInterfaceIdiom != .pad || 
                    horizontalSizeClass != .regular
                )
            },
            set: { if !$0 { showingMetrics = false } }
        )) {
            NavigationView {
                ScrollView {
                    FFTAnalysisMetricsView(analyzer: fftAnalyzer)
                        .padding()
                }
                .navigationTitle("FFT Metrics")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingMetrics = false
                        }
                    }
                    #else
                    ToolbarItem(placement: .automatic) {
                        Button("Done") {
                            showingMetrics = false
                        }
                    }
                    #endif
                }
            }
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
                fftAnalyzer: fftAnalyzer
            )
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
            }
        }
    }
    #endif
    
    /// Main content view shared across platforms
    @ViewBuilder
    private var mainContentView: some View {
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
        .navigationTitle("Tap Tone Analysis")
        #endif
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        VStack(spacing: 12) {
            // Top row: Main controls - adaptive for iOS
            #if os(iOS)
            if horizontalSizeClass == .compact {
                // Compact layout for iPhone - icon-only buttons in rows
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
                        .buttonStyle(.borderedProminent)
                        
                        // Save button
                        Button(action: { showingSaveSheet = true }) {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(tapToneAnalyzer.currentPeaks.isEmpty)
                        
                        // Measurements button
                        Button(action: { showingMeasurements = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "list.bullet.clipboard")
                                if !tapToneAnalyzer.savedMeasurements.isEmpty {
                                    Text("\(tapToneAnalyzer.savedMeasurements.count)")
                                        .font(.caption)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        // Results button
                        Button(action: { showingResults.toggle() }) {
                            Image(systemName: showingResults ? "doc.text.fill" : "doc.text")
                        }
                        .buttonStyle(.bordered)
                        
                        // Metrics button
                        Button(action: { showingMetrics.toggle() }) {
                            Image(systemName: showingMetrics ? "chart.bar.fill" : "chart.bar")
                        }
                        .buttonStyle(.bordered)
                        
                        // Reset button
                        Button(action: tapToneAnalyzer.reset) {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        
                        // Settings button
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // Row 2: Secondary controls
                    HStack(spacing: 8) {
                        // Export Spectrum button
                        Button(action: { exportCurrentSpectrum() }) {
                            Label("Export Chart", systemImage: "chart.line.uptrend.xyaxis")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!fftAnalyzer.isRunning || fftAnalyzer.frequencies.isEmpty)
                        
                        // Auto-scale dB toggle button
                        Button(action: { toggleAutoScale() }) {
                            Label("Auto dB", systemImage: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(isAutoScaleEnabled ? .blue : .gray)
                        .disabled(!fftAnalyzer.isRunning || displayMagnitudes.isEmpty)
                        #if os(macOS)
                        .help(isAutoScaleEnabled ? "Auto-scale dB enabled - tap to disable and reset" : "Enable auto-scale dB - will scale on each update")
                        #endif
                        
                        Spacer()
                    }
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
            if horizontalSizeClass == .compact {
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
                
                Spacer()
                
                // Results button
                Button(action: { showingResults.toggle() }) {
                    Label(
                        showingResults ? "Hide Results" : "Show Results",
                        systemImage: showingResults ? "doc.text.fill" : "doc.text"
                    )
                }
                .buttonStyle(.bordered)
                
                // Metrics button
                Button(action: { showingMetrics.toggle() }) {
                    Label(
                        showingMetrics ? "Hide Metrics" : "Show Metrics",
                        systemImage: showingMetrics ? "chart.bar.fill" : "chart.bar"
                    )
                }
                .buttonStyle(.bordered)
                
                // Save button
                Button(action: { showingSaveSheet = true }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(tapToneAnalyzer.currentPeaks.isEmpty)
                
                // Measurements button
                Button(action: { showingMeasurements = true }) {
                    Label("Measurements", systemImage: "list.bullet.clipboard")
                    if !tapToneAnalyzer.savedMeasurements.isEmpty {
                        Text("(\(tapToneAnalyzer.savedMeasurements.count))")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                
                // Settings button
                Button(action: { showingSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }
            
            // Row 2: Secondary controls
            HStack(spacing: 8) {
                // Export Spectrum button
                Button(action: { exportCurrentSpectrum() }) {
                    Label("Export Spectrum", systemImage: "chart.line.uptrend.xyaxis")
                }
                .buttonStyle(.bordered)
                .disabled(!fftAnalyzer.isRunning || fftAnalyzer.frequencies.isEmpty)
                
                // Auto-scale dB toggle button (iPad)
                Button(action: { toggleAutoScale() }) {
                    Label("Auto dB", systemImage: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .tint(isAutoScaleEnabled ? .blue : .gray)
                .disabled(!fftAnalyzer.isRunning || displayMagnitudes.isEmpty)
                #if os(macOS)
                .help(isAutoScaleEnabled ? "Auto-scale dB enabled - tap to disable and reset" : "Enable auto-scale dB - will scale on each update")
                #endif
                
                // Reset button
                Button(action: tapToneAnalyzer.reset) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
        }
    }
    #endif
    
    #if os(macOS)
    /// macOS button layout - full labels with spacing
    @ViewBuilder
    private var macosHeaderButtons: some View {
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
            
            Spacer()
            
            // Results button
            Button(action: { showingResults.toggle() }) {
                Label(
                    showingResults ? "Hide Results" : "Show Results",
                    systemImage: showingResults ? "doc.text.fill" : "doc.text"
                )
            }
            .buttonStyle(.bordered)
            
            // Metrics button
            Button(action: { showingMetrics.toggle() }) {
                Label(
                    showingMetrics ? "Hide Metrics" : "Show Metrics",
                    systemImage: showingMetrics ? "chart.bar.fill" : "chart.bar"
                )
            }
            .buttonStyle(.bordered)
            
            // Save button
            Button(action: { showingSaveSheet = true }) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(tapToneAnalyzer.currentPeaks.isEmpty)
            
            // Export Spectrum button
            Button(action: { exportCurrentSpectrum() }) {
                Label("Export Spectrum", systemImage: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.bordered)
            .disabled(!fftAnalyzer.isRunning || fftAnalyzer.frequencies.isEmpty)
            
            // Auto-scale dB toggle button (macOS)
            Button(action: { toggleAutoScale() }) {
                Label("Auto dB", systemImage: isAutoScaleEnabled ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .tint(isAutoScaleEnabled ? .blue : .gray)
            .disabled(!fftAnalyzer.isRunning || displayMagnitudes.isEmpty)
            #if os(macOS)
            .help(isAutoScaleEnabled ? "Auto-scale dB enabled - click to disable and reset" : "Enable auto-scale dB - will scale on each update")
            #endif
            
            // Measurements button
            Button(action: { showingMeasurements = true }) {
                Label("Measurements", systemImage: "list.bullet.clipboard")
                if !tapToneAnalyzer.savedMeasurements.isEmpty {
                    Text("(\(tapToneAnalyzer.savedMeasurements.count))")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            
            // Reset button
            Button(action: tapToneAnalyzer.reset) {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            
            // Settings button
            Button(action: { showingSettings = true }) {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
        }
    }
    #endif
    
    /// Fixed status bar at bottom of screen
    @ViewBuilder
    private var statusBarView: some View {
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
                    
                    Spacer()
                }
                
                // Tap threshold slider - full width
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Threshold: \(Int(tapToneAnalyzer.tapDetectionThreshold)) dB")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                        Spacer()
                    }
                    Slider(value: $tapToneAnalyzer.tapDetectionThreshold, in: -80...(-20), step: 1)
                    HStack {
                        Text("-80 dB")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("-20 dB")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Hysteresis slider - full width
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hysteresis: \(tapToneAnalyzer.hysteresisMargin, specifier: "%.1f") dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.purple)
                    Slider(value: $tapToneAnalyzer.hysteresisMargin, in: 1...10, step: 0.5)
                }
            }
            
            // Row 2: Action buttons
            HStack(spacing: 8) {
                // New Tap button
                Button(action: {
                    tapToneAnalyzer.startTapSequence()
                }) {
                    Label("New Tap", systemImage: "hand.tap")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
                .disabled(tapToneAnalyzer.currentTapCount > 0 && 
                          tapToneAnalyzer.currentTapCount < tapToneAnalyzer.numberOfTaps)
                
                // Cancel button (during active sequence)
                if tapToneAnalyzer.currentTapCount > 0 && 
                   tapToneAnalyzer.currentTapCount < tapToneAnalyzer.numberOfTaps {
                    Button(action: {
                        tapToneAnalyzer.cancelTapSequence()
                    }) {
                        Label("Cancel", systemImage: "xmark.circle")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.orange)
                }
                
                // Resume button (always visible, disabled when not applicable)
                Button(action: {
                    tapToneAnalyzer.resumeDetection()
                }) {
                    Label("Resume", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.blue)
                .disabled(tapToneAnalyzer.tapProgress < 1.0)
                
                // Reset annotation positions button (always visible)
                Button(action: {
                    tapToneAnalyzer.resetAllAnnotationOffsets()
                }) {
                    Label("Reset Labels", systemImage: "arrow.uturn.backward")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(tapToneAnalyzer.peakAnnotationOffsets.count == 0)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
    
    /// Regular tap controls for iPad and macOS
    @ViewBuilder
    private var regularTapControls: some View {
        HStack {
            Text("Taps to average:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Stepper("\(tapToneAnalyzer.numberOfTaps)", 
                    value: $tapToneAnalyzer.numberOfTaps, 
                    in: 1...10)
                .frame(maxWidth: 150)
            
            Spacer()
            
            // Tap detection threshold slider (absolute dB level)
            VStack(alignment: .leading, spacing: 4) {
                Text("Tap threshold:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Text("-80 dB")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Slider(value: $tapToneAnalyzer.tapDetectionThreshold, in: -80...(-20), step: 1)
                        .frame(width: 120)
                    Text("-20 dB")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(Int(tapToneAnalyzer.tapDetectionThreshold)) dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .frame(width: 50, alignment: .trailing)
                }
            }
            
            // Hysteresis margin slider
            VStack(alignment: .leading, spacing: 4) {
                Text("Hysteresis:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Slider(value: $tapToneAnalyzer.hysteresisMargin, in: 1...10, step: 0.5)
                        .frame(width: 100)
                    Text("\(tapToneAnalyzer.hysteresisMargin, specifier: "%.1f") dB")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.purple)
                        .frame(width: 50, alignment: .trailing)
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
            .disabled(tapToneAnalyzer.currentTapCount > 0 && 
                      tapToneAnalyzer.currentTapCount < tapToneAnalyzer.numberOfTaps)
            
            // Cancel button (during active sequence)
            if tapToneAnalyzer.currentTapCount > 0 && 
               tapToneAnalyzer.currentTapCount < tapToneAnalyzer.numberOfTaps {
                Button(action: {
                    tapToneAnalyzer.cancelTapSequence()
                }) {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .foregroundColor(.orange)
            }
            
            // Resume button (always visible, disabled when not applicable)
            Button(action: {
                tapToneAnalyzer.resumeDetection()
            }) {
                Label("Resume", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .foregroundColor(.blue)
            .disabled(tapToneAnalyzer.tapProgress < 1.0)
            
            // Reset annotation positions button (always visible, next to Resume)
            Button(action: {
                tapToneAnalyzer.resetAllAnnotationOffsets()
            }) {
                Label("Reset Labels", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .disabled(tapToneAnalyzer.peakAnnotationOffsets.count == 0)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
    
    // Computed properties to explicitly depend on @Published properties
    private var displayFrequencies: [Float] {
        tapToneAnalyzer.isSpectrumFrozen ? tapToneAnalyzer.frozenFrequencies : fftAnalyzer.frequencies
    }
    
    private var displayMagnitudes: [Float] {
        tapToneAnalyzer.isSpectrumFrozen ? tapToneAnalyzer.frozenMagnitudes : fftAnalyzer.magnitudes
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
                peaks: tapToneAnalyzer.currentPeaks,
                showModeBoundaries: true,
                onFrequencyRangeChanged: updateFrequencyInputFields,
                annotationOffsets: $tapToneAnalyzer.peakAnnotationOffsets,
                thresholdLines: thresholds
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
            
            // Create spectrum snapshot
            let snapshot = SpectrumSnapshot(
                frequencies: self.tapToneAnalyzer.isSpectrumFrozen ? 
                    self.tapToneAnalyzer.frozenFrequencies : self.fftAnalyzer.frequencies,
                magnitudes: self.tapToneAnalyzer.isSpectrumFrozen ? 
                    self.tapToneAnalyzer.frozenMagnitudes : self.fftAnalyzer.magnitudes,
                minFreq: self.minFreq,
                maxFreq: self.maxFreq,
                minDB: self.minDB,
                maxDB: self.maxDB,
                isLogarithmic: false
            )
            
            // Save with all data
            self.tapToneAnalyzer.saveMeasurement(
                tapLocation: self.tapLocation.isEmpty ? nil : self.tapLocation,
                notes: self.notes.isEmpty ? nil : self.notes,
                includeSpectrum: true,
                chartImageData: imageData,
                spectrumSnapshot: snapshot,
                annotationOffsets: self.tapToneAnalyzer.peakAnnotationOffsets
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
                peaks: tapToneAnalyzer.currentPeaks,
                showModeBoundaries: true,
                annotationOffsets: tapToneAnalyzer.peakAnnotationOffsets
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

// MARK: - Analysis Results View


// MARK: - Preview

#Preview {
    TapToneAnalysisView()
}
