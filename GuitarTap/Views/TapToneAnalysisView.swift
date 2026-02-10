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
    @State private var isExportingSpectrum = false
    @State private var isSavingMeasurement = false
    
    // Spectrum display state
    @State private var minFreq: Float = 20
    @State private var maxFreq: Float = 300
    @State private var minDB: Float = -100
    @State private var maxDB: Float = 0
    @State private var isLogarithmic: Bool = false
    @State private var minFreqInput: String = "20"
    @State private var maxFreqInput: String = "300"
    @State private var minDBInput: String = "-100"
    @State private var maxDBInput: String = "0"
    
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
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
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
            
            // Main content
            ScrollView {
                VStack(spacing: 20) {
                    // Real-time Frequency Response Display
                    realTimeSpectrumView
                    
                    // Tap detection indicator
                    tapIndicatorView
                    
                    // Decay time (keep this in main view for quick reference)
                    decayTimeView
                }
                .padding()
            }
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
                        
                        Spacer()
                        
                        // Reset annotation positions button
                        if !tapToneAnalyzer.peakAnnotationOffsets.isEmpty {
                            Button(action: {
                                tapToneAnalyzer.resetAllAnnotationOffsets()
                            }) {
                                Label("Reset Labels", systemImage: "arrow.uturn.backward")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
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
    /// iPad button layout - full labels
    @ViewBuilder
    private var ipadHeaderButtons: some View {
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
            
            // Export Spectrum button
            Button(action: { exportCurrentSpectrum() }) {
                Label("Export Spectrum", systemImage: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.bordered)
            .disabled(!fftAnalyzer.isRunning || fftAnalyzer.frequencies.isEmpty)
            
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
            
            // Reset annotation positions button
            if !tapToneAnalyzer.peakAnnotationOffsets.isEmpty {
                Button(action: {
                    tapToneAnalyzer.resetAllAnnotationOffsets()
                }) {
                    Label("Reset Labels", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
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
        }
    }
    #endif
    
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
                
                // Resume button (when sequence is complete)
                if tapToneAnalyzer.tapProgress >= 1.0 {
                    Button(action: {
                        tapToneAnalyzer.resumeDetection()
                    }) {
                        Label("Resume", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.blue)
                }
            }
            
            // Row 3: Status and progress
            VStack(spacing: 6) {
                HStack {
                    Circle()
                        .fill(tapToneAnalyzer.isDetecting ? .green : .orange)
                        .frame(width: 8, height: 8)
                    
                    Text(tapToneAnalyzer.statusMessage)
                        .font(.caption)
                        .foregroundColor(tapToneAnalyzer.isDetecting ? .primary : .orange)
                    
                    Spacer()
                    
                    if tapToneAnalyzer.currentTapCount > 0 {
                        Text("\(tapToneAnalyzer.currentTapCount)/\(tapToneAnalyzer.numberOfTaps)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                }
                
                // Progress bar (when tapping)
                if tapToneAnalyzer.currentTapCount > 0 {
                    ProgressView(value: tapToneAnalyzer.tapProgress)
                        .progressViewStyle(.linear)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
    
    /// Regular tap controls for iPad and macOS
    @ViewBuilder
    private var regularTapControls: some View {
        VStack(spacing: 8) {
            // Configuration row
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
                
                // Resume button (when sequence is complete)
                if tapToneAnalyzer.tapProgress >= 1.0 {
                    Button(action: {
                        tapToneAnalyzer.resumeDetection()
                    }) {
                        Label("Resume", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.blue)
                }
                
                #if os(macOS)
                // Reset annotation positions button (macOS only - iOS has it in header)
                if !tapToneAnalyzer.peakAnnotationOffsets.isEmpty {
                    Button(action: {
                        tapToneAnalyzer.resetAllAnnotationOffsets()
                    }) {
                        Label("Reset Labels", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.secondary)
                    .help("Reset all peak label positions to default")
                }
                #endif
            }
            
            // Status and progress row
            VStack(spacing: 6) {
                HStack {
                    Circle()
                        .fill(tapToneAnalyzer.isDetecting ? .green : .orange)
                        .frame(width: 8, height: 8)
                    
                    Text(tapToneAnalyzer.statusMessage)
                        .font(.subheadline)
                        .foregroundColor(tapToneAnalyzer.isDetecting ? .primary : .orange)
                    
                    Spacer()
                    
                    if tapToneAnalyzer.currentTapCount > 0 {
                        Text("\(tapToneAnalyzer.currentTapCount)/\(tapToneAnalyzer.numberOfTaps)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                }
                
                // Progress bar (when tapping)
                if tapToneAnalyzer.currentTapCount > 0 {
                    ProgressView(value: tapToneAnalyzer.tapProgress)
                        .progressViewStyle(.linear)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var realTimeSpectrumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Toolbar: title, scale toggle, and reset button
            HStack {
                Text("Real-Time Frequency Response")
                    .font(.headline)
                
                // Frozen indicator
                if tapToneAnalyzer.isSpectrumFrozen {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.circle.fill")
                            .foregroundColor(.orange)
                        Text("Frozen")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                Toggle(isOn: $isLogarithmic) {
                    Text("Logarithmic")
                }
                .toggleStyle(.switch)
                .font(.caption)
                
                Button(action: resetZoom) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            
            // Range Controls
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    // Frequency Range Controls
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Frequency Range")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            TextField("Min", text: $minFreqInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                .onSubmit { applyFrequencyRange() }
                            Text("–")
                                .foregroundColor(.secondary)
                            TextField("Max", text: $maxFreqInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                .onSubmit { applyFrequencyRange() }
                            Text("Hz")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(action: applyFrequencyRange) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    Divider()
                        .frame(height: 40)
                    
                    // Magnitude Range Controls
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Magnitude Range")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            TextField("Min", text: $minDBInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                .onSubmit { applyMagnitudeRange() }
                            Text("–")
                                .foregroundColor(.secondary)
                            TextField("Max", text: $maxDBInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                .onSubmit { applyMagnitudeRange() }
                            Text("dB")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(action: applyMagnitudeRange) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            }
            
            Text("Pinch to zoom • Drag to pan • Enter custom range above")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Spectrum Chart
            SpectrumView(
                frequencies: tapToneAnalyzer.isSpectrumFrozen ? 
                    tapToneAnalyzer.frozenFrequencies : fftAnalyzer.frequencies,
                magnitudes: tapToneAnalyzer.isSpectrumFrozen ? 
                    tapToneAnalyzer.frozenMagnitudes : fftAnalyzer.magnitudes,
                minFreq: $minFreq,
                maxFreq: $maxFreq,
                minDB: $minDB,
                maxDB: $maxDB,
                isLogarithmic: $isLogarithmic,
                peaks: tapToneAnalyzer.currentPeaks,
                showModeBoundaries: true,
                onFrequencyRangeChanged: updateFrequencyInputFields,
                annotationOffsets: $tapToneAnalyzer.peakAnnotationOffsets
            )
            .frame(minHeight: 250, maxHeight: 400)
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
                    } else if fftAnalyzer.frequencies.isEmpty {
                        VStack {
                            ProgressView()
                            Text("Loading...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        // Tap detection threshold line overlay with hysteresis visualization
                        GeometryReader { geometry in
                            let chartPadding: CGFloat = 16
                            let chartHeight = geometry.size.height - 2 * chartPadding
                            let dbRange = maxDB - minDB
                            
                            if tapToneAnalyzer.isDetecting {
                                // Rising threshold (main threshold line)
                                let risingThreshold = tapToneAnalyzer.tapDetectionLevel
                                if risingThreshold > minDB && risingThreshold < maxDB {
                                    let normalizedPosition = CGFloat((risingThreshold - minDB) / dbRange)
                                    let yPosition = chartHeight * (1 - normalizedPosition) + chartPadding
                                    
                                    // Rising threshold line (orange)
                                    Path { path in
                                        path.move(to: CGPoint(x: chartPadding, y: yPosition))
                                        path.addLine(to: CGPoint(x: geometry.size.width - chartPadding, y: yPosition))
                                    }
                                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                                    .foregroundColor(.orange.opacity(0.7))
                                    
                                    // Label for rising threshold
                                    Text("Trigger: \(Int(risingThreshold)) dB")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.9))
                                        .cornerRadius(4)
                                        .position(x: geometry.size.width - 80, y: yPosition - 12)
                                }
                                
                                // Falling threshold (hysteresis line) - only show if hysteresis > 0.5 dB
                                if tapToneAnalyzer.hysteresisMargin > 0.5 {
                                    let fallingThreshold = risingThreshold - tapToneAnalyzer.hysteresisMargin
                                    if fallingThreshold > minDB && fallingThreshold < maxDB {
                                        let normalizedFallingPosition = CGFloat((fallingThreshold - minDB) / dbRange)
                                        let yFallingPosition = chartHeight * (1 - normalizedFallingPosition) + chartPadding
                                        
                                        // Falling threshold line (purple, lighter)
                                        Path { path in
                                            path.move(to: CGPoint(x: chartPadding, y: yFallingPosition))
                                            path.addLine(to: CGPoint(x: geometry.size.width - chartPadding, y: yFallingPosition))
                                        }
                                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                        .foregroundColor(.purple.opacity(0.5))
                                        
                                        // Label for falling threshold
                                        Text("Reset: \(Int(fallingThreshold)) dB")
                                            .font(.caption2)
                                            .foregroundColor(.purple.opacity(0.8))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.white.opacity(0.85))
                                            .cornerRadius(4)
                                            .position(x: chartPadding + 70, y: yFallingPosition - 12)
                                    }
                                }
                            }
                        }
                    }
                }
            )
            
            // Range Display
            HStack {
                Text("Range: \(minFreq.formattedAsFrequency()) - \(maxFreq.formattedAsFrequency())")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(minDB)) to \(Int(maxDB)) dB")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Debug Info
            HStack {
                if fftAnalyzer.isRunning {
                    Text("Status: \(fftAnalyzer.frequencies.count) freq bins")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Peak: \(fftAnalyzer.peakMagnitude, specifier: "%.1f") dB")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("@ \(fftAnalyzer.peakFrequency, specifier: "%.1f") Hz")
                        .font(.caption2)
                        .foregroundColor(.blue)
                } else {
                    Text("Analyzer is stopped")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    private var tapIndicatorView: some View {
        HStack {
            Circle()
                .fill(tapToneAnalyzer.tapDetected ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 20, height: 20)
            
            Text(tapToneAnalyzer.tapDetected ? "Tap Detected!" : "Waiting for tap...")
                .font(.headline)
                .foregroundColor(tapToneAnalyzer.tapDetected ? .green : .secondary)
            
            Spacer()
            
            Text("\(tapToneAnalyzer.averageMagnitude, specifier: "%.1f") dB")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
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
        // Use DispatchQueue.global() to FORCE execution off the main thread
        DispatchQueue.global(qos: .userInitiated).async {
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
                isLogarithmic: self.isLogarithmic
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
    
    private func resetZoom() {
        minFreq = 75
        maxFreq = 350
        minDB = -100
        maxDB = 0
        
        minFreqInput = "75"
        maxFreqInput = "350"
        minDBInput = "-100"
        maxDBInput = "0"
    }
    
    private func applyFrequencyRange() {
        guard let newMinFreq = Float(minFreqInput),
              let newMaxFreq = Float(maxFreqInput) else {
            minFreqInput = String(format: "%.0f", minFreq)
            maxFreqInput = String(format: "%.0f", maxFreq)
            return
        }
        
        let clampedMin = max(20, min(newMinFreq, 20000))
        let clampedMax = max(20, min(newMaxFreq, 20000))
        
        if clampedMin < clampedMax && (clampedMax - clampedMin) >= 10 {
            minFreq = clampedMin
            maxFreq = clampedMax
            
            minFreqInput = String(format: "%.0f", clampedMin)
            maxFreqInput = String(format: "%.0f", clampedMax)
        } else {
            minFreqInput = String(format: "%.0f", minFreq)
            maxFreqInput = String(format: "%.0f", maxFreq)
        }
    }
    
    private func updateFrequencyInputFields() {
        minFreqInput = String(format: "%.0f", minFreq)
        maxFreqInput = String(format: "%.0f", maxFreq)
    }
    
    private func applyMagnitudeRange() {
        guard let newMinDB = Float(minDBInput),
              let newMaxDB = Float(maxDBInput) else {
            minDBInput = String(format: "%.0f", minDB)
            maxDBInput = String(format: "%.0f", maxDB)
            return
        }
        
        let clampedMin = max(-120, min(newMinDB, 20))
        let clampedMax = max(-120, min(newMaxDB, 20))
        
        if clampedMin < clampedMax && (clampedMax - clampedMin) >= 10 {
            minDB = clampedMin
            maxDB = clampedMax
            
            minDBInput = String(format: "%.0f", clampedMin)
            maxDBInput = String(format: "%.0f", clampedMax)
        } else {
            minDBInput = String(format: "%.0f", minDB)
            maxDBInput = String(format: "%.0f", maxDB)
        }
    }
    
    private func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.1fk Hz", freq / 1000)
        } else {
            return String(format: "%.0f Hz", freq)
        }
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
            
            // Chart
            SpectrumView(
                frequencies: tapToneAnalyzer.isSpectrumFrozen ? 
                    tapToneAnalyzer.frozenFrequencies : fftAnalyzer.frequencies,
                magnitudes: tapToneAnalyzer.isSpectrumFrozen ? 
                    tapToneAnalyzer.frozenMagnitudes : fftAnalyzer.magnitudes,
                minFreq: .constant(minFreq),
                maxFreq: .constant(maxFreq),
                minDB: .constant(minDB),
                maxDB: .constant(maxDB),
                isLogarithmic: .constant(isLogarithmic),
                peaks: tapToneAnalyzer.currentPeaks,
                showModeBoundaries: true,
                onFrequencyRangeChanged: {},
                annotationOffsets: .constant([:])
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
                                Text(mode.rawValue)
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
                
                ForEach([GuitarMode.helmholtz, .crossGrain, .longGrain, .monopole, .dipole, .ringMode], id: \.self) { mode in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(mode.color)
                            .frame(width: 12, height: 12)
                        Text(mode.rawValue)
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


// MARK: - Document Picker for Import

#if os(iOS)
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onDocumentPicked: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onDocumentPicked(url)
            parent.isPresented = false
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}
#endif

// MARK: - Preview

#Preview {
    TapToneAnalysisView()
}
