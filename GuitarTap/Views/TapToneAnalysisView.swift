//
//  TapToneAnalysisView.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import SwiftUI
import Charts
import AVFoundation

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
    @State private var showingSpectrumExport = false
    @State private var isExportingSpectrum = false
    @State private var isSavingMeasurement = false
    @State private var showingImportPicker = false
    
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
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Exporting spectrum...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(30)
                    .background(Color.secondary.opacity(0.8))
                    .cornerRadius(12)
                }
            } else if isSavingMeasurement {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Saving measurement with chart image...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(30)
                    .background(Color.secondary.opacity(0.8))
                    .cornerRadius(12)
                }
            }
        }
    }
    #endif
    
    /// iOS layout with adaptive metrics display
    @ViewBuilder
    private var iOSLayout: some View {
        NavigationView {
            if horizontalSizeClass == .regular && (showingMetrics || showingResults) {
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
                // iPhone or iPad without panels
                ZStack(alignment: .topTrailing) {
                    mainContentView
                    
                    // Show compact overlay on iPhone when metrics are enabled
                    if showingMetrics && horizontalSizeClass != .regular {
                        CompactFFTMetricsOverlay(analyzer: fftAnalyzer)
                            .padding(12)
                    }
                }
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
        .sheet(isPresented: Binding(
            get: { showingResults && horizontalSizeClass != .regular },
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
        .overlay {
            if isExportingSpectrum {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Exporting spectrum...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(30)
                    .background(Color.secondary.opacity(0.8))
                    .cornerRadius(12)
                }
            } else if isSavingMeasurement {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Saving measurement with chart image...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(30)
                    .background(Color.secondary.opacity(0.8))
                    .cornerRadius(12)
                }
            }
        }
    }
    
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
            // Top row: Main controls
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
            
            // Tap sequence controls (only when analyzer is running)
            if fftAnalyzer.isRunning {
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
                                Text("High")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Slider(value: $tapToneAnalyzer.tapDetectionThreshold, in: -80...(-20), step: 1)
                                    .frame(width: 120)
                                Text("Low")
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
                        
                        // Reset annotation positions button
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
        }
        .padding()
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
                Text("Range: \(formatFrequency(minFreq)) - \(formatFrequency(maxFreq))")
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
                        Text(decayQuality(decay))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(decayQualityColor(decay))
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
                
                // Start the analyzer on a detached background thread
//                print("🚀 Starting analyzer on thread: \(Thread.isMainThread ? "MAIN ⚠️" : "BACKGROUND ✅")")
                try self.tapToneAnalyzer.start()
//                print("✅ Analyzer started successfully")
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
            
            #if os(iOS)
            renderer.scale = UIScreen.main.scale
            #elseif os(macOS)
            renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
            #endif
            
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
    
    // MARK: - Helpers
    
    private func decayQuality(_ time: Float) -> String {
        switch time {
        case 0..<0.5: return "Very Short"
        case 0.5..<1.0: return "Short"
        case 1.0..<2.0: return "Good"
        case 2.0..<3.0: return "Excellent"
        default: return "Very Long"
        }
    }
    
    private func decayQualityColor(_ time: Float) -> Color {
        switch time {
        case 0..<0.5: return .red
        case 0.5..<1.0: return .orange
        case 1.0..<2.0: return .green
        case 2.0..<3.0: return .blue
        default: return .purple
        }
    }
    
    private func ratioQuality(_ ratio: Float) -> String {
        let difference = abs(ratio - 2.0)
        switch difference {
        case 0..<0.1: return "Excellent"
        case 0.1..<0.2: return "Good"
        case 0.2..<0.3: return "Fair"
        default: return "Needs Work"
        }
    }
    
    private func ratioQualityColor(_ ratio: Float) -> Color {
        let difference = abs(ratio - 2.0)
        switch difference {
        case 0..<0.1: return .green
        case 0.1..<0.2: return .blue
        case 0.2..<0.3: return .orange
        default: return .red
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
            
            #if os(iOS)
            renderer.scale = UIScreen.main.scale
            
            if let uiImage = renderer.uiImage {
                let activityVC = UIActivityViewController(
                    activityItems: [uiImage],
                    applicationActivities: nil
                )
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    rootViewController.present(activityVC, animated: true)
                }
            }
            self.isExportingSpectrum = false
            #elseif os(macOS)
            renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
            
            if let nsImage = renderer.nsImage {
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.png]
                savePanel.nameFieldStringValue = "spectrum-\(Int(Date().timeIntervalSince1970)).png"
                savePanel.canCreateDirectories = true
                
                savePanel.begin { response in
                    if response == .OK, let url = savePanel.url {
                        if let tiffData = nsImage.tiffRepresentation,
                           let bitmapImage = NSBitmapImageRep(data: tiffData),
                           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                            try? pngData.write(to: url)
                        }
                    }
                    self.isExportingSpectrum = false
                }
            } else {
                self.isExportingSpectrum = false
            }
            #endif
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
                                    .foregroundColor(modeColorForExport(for: mode))
                                Text("\(peak.magnitude, specifier: "%.1f") dB")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(modeColorForExport(for: mode).opacity(0.1))
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
                            .fill(modeColorForExport(for: mode))
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
    
    private func modeColorForExport(for mode: GuitarMode) -> Color {
        switch mode {
        case .helmholtz: return .cyan
        case .crossGrain: return .blue
        case .longGrain: return .green
        case .monopole: return .orange
        case .dipole: return .red
        case .ringMode: return .purple
        case .upperModes: return .gray
        case .unknown: return .secondary
        }
    }
}

// MARK: - Analysis Results View

/// A view that displays tap tone analysis results in a dedicated panel.
struct TapAnalysisResultsView: View {
    @ObservedObject var analyzer: TapToneAnalyzer
    @ObservedObject var fftAnalyzer: RealtimeFFTAnalyzer
    
    // Frequency range for filtering
    var minFreq: Float
    var maxFreq: Float
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Analysis Results")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("Showing \(formatFrequency(minFreq)) - \(formatFrequency(maxFreq))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Current peaks display
                peaksAndModesSection
                
                Divider()
                
                // Tap tone ratio
                ratioSection
                
                Divider()
                
                // Peak history chart
                historySection
                
                // Status indicator
                statusIndicator
            }
            .padding()
        }
    }
    
    // MARK: - Computed Properties
    
    /// Combined peaks with mode classifications, filtered to the current frequency range and sorted by frequency
    private var sortedPeaksWithModes: [(peak: ResonantPeak, mode: GuitarMode)] {
        analyzer.currentPeaks
            .filter { peak in
                peak.frequency >= minFreq && peak.frequency <= maxFreq
            }
            .map { peak in
                (peak: peak, mode: GuitarMode.classify(frequency: peak.frequency))
            }
            .sorted { $0.peak.frequency < $1.peak.frequency }
    }
    
    // MARK: - Subviews
    
    private var peaksAndModesSection: some View {
        GroupBox("Detected Peaks & Modes") {
            if sortedPeaksWithModes.isEmpty {
                Text("No peaks detected in visible range")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sortedPeaksWithModes, id: \.peak.id) { item in
                        CombinedPeakModeRowView(peak: item.peak, mode: item.mode)
                    }
                }
            }
        }
    }
    
    private var ratioSection: some View {
        GroupBox("Tap Tone Ratio") {
            if let ratio = analyzer.calculateTapToneRatio() {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(ratio, specifier: "%.2f") : 1")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Long-grain / Cross-grain")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text(ratioQualityHelper(ratio))
                            .font(.headline)
                            .foregroundColor(ratioQualityColorHelper(ratio))
                        
                        Text("Ideal: 1.9 - 2.1")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("Need both cross-grain and long-grain modes")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }
    
    private var historySection: some View {
        GroupBox("Peak Tracking") {
            if analyzer.peakHistory.isEmpty {
                Text("No history available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart {
                    ForEach(Array(analyzer.peakHistory.enumerated()), id: \.offset) { index, peaks in
                        ForEach(peaks.prefix(5)) { peak in
                            LineMark(
                                x: .value("Time", index),
                                y: .value("Frequency", peak.frequency)
                            )
                            .foregroundStyle(by: .value("Mode", GuitarMode.classify(frequency: peak.frequency).rawValue))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                    }
                }
                .frame(height: 250)
            }
        }
    }
    
    private var statusIndicator: some View {
        HStack {
            Circle()
                .fill(fftAnalyzer.isRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            Text(fftAnalyzer.isRunning ? "Analyzing" : "Stopped")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Helper functions
    
    private func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.1fk Hz", freq / 1000)
        } else {
            return String(format: "%.0f Hz", freq)
        }
    }
    
    private func ratioQualityHelper(_ ratio: Float) -> String {
        switch ratio {
        case 1.9...2.1:
            return "Excellent"
        case 1.7...1.9, 2.1...2.3:
            return "Good"
        case 1.5...1.7, 2.3...2.5:
            return "Fair"
        default:
            return "Needs Adjustment"
        }
    }
    
    private func ratioQualityColorHelper(_ ratio: Float) -> Color {
        switch ratio {
        case 1.9...2.1:
            return .green
        case 1.7...1.9, 2.1...2.3:
            return .blue
        case 1.5...1.7, 2.3...2.5:
            return .orange
        default:
            return .red
        }
    }
}

// MARK: - Supporting Views

struct CombinedPeakModeRowView: View {
    let peak: ResonantPeak
    let mode: GuitarMode
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Mode icon and color
            VStack(spacing: 4) {
                Image(systemName: modeIcon)
                    .foregroundColor(modeColor)
                    .font(.title3)
                    .frame(width: 30, height: 30)
                
                // Mode range indicator
                if mode != .unknown && mode != .upperModes {
                    let inRange = mode.idealRange.contains(peak.frequency)
                    Image(systemName: inRange ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(inRange ? .green : .orange)
                        .font(.caption2)
                }
            }
            
            // Peak and mode information
            VStack(alignment: .leading, spacing: 6) {
                // Mode name and frequency
                HStack {
                    Text(mode.rawValue)
                        .font(.headline)
                        .foregroundColor(modeColor)
                    
                    Spacer()
                    
                    Text("\(peak.frequency, specifier: "%.2f") Hz")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                // Peak details
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("Q:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(peak.quality, specifier: "%.1f")")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    HStack(spacing: 4) {
                        Text("BW:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(peak.bandwidth, specifier: "%.1f") Hz")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    // Magnitude with color coding
                    Text("\(peak.magnitude, specifier: "%.1f") dB")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(magnitudeColor(peak.magnitude))
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(modeColor.opacity(0.05))
        .cornerRadius(8)
    }
    
    private var modeIcon: String {
        switch mode {
        case .helmholtz: return "wind"
        case .crossGrain: return "arrow.left.and.right"
        case .longGrain: return "arrow.up.and.down"
        case .monopole: return "circle.fill"
        case .dipole: return "circle.lefthalf.filled"
        case .ringMode: return "circle.dashed"
        case .upperModes: return "waveform"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private var modeColor: Color {
        switch mode {
        case .helmholtz: return .cyan
        case .crossGrain: return .blue
        case .longGrain: return .green
        case .monopole: return .orange
        case .dipole: return .red
        case .ringMode: return .purple
        case .upperModes: return .gray
        case .unknown: return .secondary
        }
    }
    
    private func magnitudeColor(_ mag: Float) -> Color {
        if mag >= -40.0 {
            return .green
        } else if mag >= -60.0 {
            return .blue
        } else if mag >= -80.0 {
            return .orange
        } else {
            return .red
        }
    }
}

struct PeakRowView: View {
    let peak: ResonantPeak
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(peak.frequency, specifier: "%.2f") Hz")
                    .font(.headline)
                
                HStack {
                    Text("Q: \(peak.quality, specifier: "%.1f")")
                    Text("•")
                    Text("BW: \(peak.bandwidth, specifier: "%.1f") Hz")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(peak.magnitude, specifier: "%.1f") dB")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(magnitudeColor(peak.magnitude))
        }
        .padding(.vertical, 4)
    }
    
    private func magnitudeColor(_ mag: Float) -> Color {
        if mag >= -40.0 {
            return .green
        } else if mag >= -60.0 {
            return .blue
        } else if mag >= -80.0 {
            return .orange
        } else {
            return .red
        }
    }
}

struct ModeRowView: View {
    let peak: ResonantPeak
    let mode: GuitarMode
    
    var body: some View {
        HStack {
            Image(systemName: modeIcon)
                .foregroundColor(modeColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.rawValue)
                    .font(.headline)
                
                Text("\(peak.frequency, specifier: "%.2f") Hz")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if mode != .unknown && mode != .upperModes {
                let inRange = mode.idealRange.contains(peak.frequency)
                Image(systemName: inRange ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(inRange ? .green : .orange)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var modeIcon: String {
        switch mode {
        case .helmholtz: return "wind"
        case .crossGrain: return "arrow.left.and.right"
        case .longGrain: return "arrow.up.and.down"
        case .monopole: return "circle.fill"
        case .dipole: return "circle.lefthalf.filled"
        case .ringMode: return "circle.dashed"
        case .upperModes: return "waveform"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private var modeColor: Color {
        switch mode {
        case .helmholtz: return .cyan
        case .crossGrain: return .blue
        case .longGrain: return .green
        case .monopole: return .orange
        case .dipole: return .red
        case .ringMode: return .purple
        case .upperModes: return .gray
        case .unknown: return .secondary
        }
    }
}

struct SaveMeasurementSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var tapLocation: String
    @Binding var notes: String
    let onSave: () -> Void
    
    var body: some View {
        #if os(macOS)
        // macOS layout without NavigationView wrapper
        formContent
            .frame(minWidth: 450, idealWidth: 500, minHeight: 250, idealHeight: 350)
            .navigationTitle("Save Measurement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        #else
        // iOS layout with NavigationView
        NavigationView {
            formContent
                .navigationTitle("Save Measurement")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave()
                            dismiss()
                        }
                    }
                }
        }
        #endif
    }
    
    @ViewBuilder
    private var formContent: some View {
        Form {
            Section {
                TextField("Tap Location", text: $tapLocation, prompt: Text("Bridge, Soundhole, Upper Bout..."))
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Tap Location (Optional)")
                    .font(.headline)
            }
            
            Section {
                TextEditor(text: $notes)
                    .frame(minHeight: 80, idealHeight: 120)
                    .font(.body)
                    #if os(macOS)
                    .background(Color(NSColor.textBackgroundColor))
                    #endif
            } header: {
                Text("Notes (Optional)")
                    .font(.headline)
            } footer: {
                Text("Add any observations about this measurement")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct MeasurementsListView: View {
    @ObservedObject var analyzer: TapToneAnalyzer
    @Environment(\.dismiss) var dismiss
    @State private var showingExport = false
    @State private var exportText = ""
    @State private var isExporting = false  // Track export progress
    @State private var exportMode: ExportMode = .json  // Track what we're exporting
    @State private var showingImportPicker = false
    @State private var importError: String?
    @State private var importSuccess: String?
    @State private var selectedMeasurement: TapToneMeasurement?
    @State private var showingDetailSheet = false
    
    enum ExportMode {
        case json
        case file
    }
    
    var body: some View {
        #if os(macOS)
        // macOS layout without NavigationView wrapper (sheet handles its own window)
        contentView
            .frame(minWidth: 600, minHeight: 400)
            .sheet(isPresented: $showingExport) {
                ExportView(text: exportText)
            }
            .sheet(isPresented: $showingDetailSheet) {
                if let measurement = selectedMeasurement {
                    MeasurementDetailView(measurement: measurement, analyzer: analyzer)
                }
            }
            .background(importSheet)
            .overlay {
                if isExporting {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Exporting measurements...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(30)
                        .background(Color.secondary.opacity(0.8))
                        .cornerRadius(12)
                    }
                }
            }
        #else
        // iOS layout with NavigationView
        NavigationView {
            contentView
                .sheet(isPresented: $showingExport) {
                    ExportView(text: exportText)
                }
                .background(importSheet)
                .overlay {
                    if isExporting {
                        ZStack {
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()
                            
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text("Exporting measurements...")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .padding(30)
                            .background(Color.secondary.opacity(0.8))
                            .cornerRadius(12)
                        }
                    }
                }
        }
        #endif
    }
    
    @ViewBuilder
    private var contentView: some View {
        Group {
            if analyzer.savedMeasurements.isEmpty {
                // Empty state
                VStack(spacing: 20) {
                    Image(systemName: "tray")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("No Saved Measurements")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Tap the guitar and click Save to store measurements for comparison.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Measurements list
                List {
                    Section {
                        Text("Total: \(analyzer.savedMeasurements.count) measurement\(analyzer.savedMeasurements.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    ForEach(analyzer.savedMeasurements) { measurement in
                        #if os(macOS)
                        // On macOS, use Button with sheet since NavigationLink doesn't work in sheets
                        Button(action: {
                            showDetail(for: measurement)
                        }) {
                            MeasurementRowView(measurement: measurement)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(action: {
                                showDetail(for: measurement)
                            }) {
                                Label("View Details", systemImage: "eye")
                            }
                            
                            Button(action: {
                                exportSingleMeasurement(measurement)
                            }) {
                                Label("Export as JSON", systemImage: "square.and.arrow.up")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive, action: {
                                analyzer.deleteMeasurement(measurement)
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        #else
                        // On iOS, use NavigationLink which works better in NavigationView
                        NavigationLink(destination: MeasurementDetailView(measurement: measurement, analyzer: analyzer)) {
                            MeasurementRowView(measurement: measurement)
                        }
                        .contextMenu {
                            NavigationLink(destination: MeasurementDetailView(measurement: measurement, analyzer: analyzer)) {
                                Label("View Details", systemImage: "eye")
                            }
                            
                            Button(action: {
                                exportSingleMeasurement(measurement)
                            }) {
                                Label("Export as JSON", systemImage: "square.and.arrow.up")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive, action: {
                                analyzer.deleteMeasurement(measurement)
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        #endif
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { index in
                            analyzer.deleteMeasurement(analyzer.savedMeasurements[index])
                        }
                    }
                }
            }
        }
        .navigationTitle("Saved Measurements")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingImportPicker = true }) {
                        Label("Import from JSON", systemImage: "square.and.arrow.down")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: deleteAll) {
                        Label("Delete All", systemImage: "trash")
                    }
                    .disabled(analyzer.savedMeasurements.isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingImportPicker = true }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive, action: deleteAll) {
                    Label("Delete All", systemImage: "trash")
                }
                .disabled(analyzer.savedMeasurements.isEmpty)
            }
            #endif
        }
    }
    
    private func exportSingleMeasurement(_ measurement: TapToneMeasurement) {
        exportMode = .file
        isExporting = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            if let data = try? encoder.encode([measurement]),
               let json = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.saveJSONAndImagesToFiles(json: json, measurement: measurement)
                }
            } else {
                DispatchQueue.main.async {
                    self.isExporting = false
                }
            }
        }
    }
    
    private func saveJSONAndImagesToFiles(json: String, measurement: TapToneMeasurement) {
        #if os(iOS)
        // On iOS, create temp directory with JSON and image
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("GuitarTap-Export-\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // Use measurement's baseFilename for both JSON and image
            let basename = measurement.baseFilename
            
            // Save JSON
            let jsonURL = tempDir.appendingPathComponent("\(basename).json")
            try json.write(to: jsonURL, atomically: true, encoding: .utf8)
            
            // Save image if exists (use same basename)
            if let imageData = measurement.chartImageData {
                let imageURL = tempDir.appendingPathComponent("\(basename).png")
                try imageData.write(to: imageURL)
            }
            
            // Present document picker for the directory
            let documentPicker = UIDocumentPickerViewController(forExporting: [tempDir], asCopy: true)
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(documentPicker, animated: true)
            }
        } catch {
            print("Failed to export: \(error)")
        }
        
        self.isExporting = false
        
        #elseif os(macOS)
        // On macOS, use panel to select directory first
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Select a folder to save measurement and image"
        panel.prompt = "Export Here"
        
        panel.begin { response in
            if response == .OK, let directoryURL = panel.url {
                do {
                    // Use measurement's baseFilename for both JSON and image
                    let basename = measurement.baseFilename
                    
                    // Save JSON
                    let jsonURL = directoryURL.appendingPathComponent("\(basename).json")
                    try json.write(to: jsonURL, atomically: true, encoding: .utf8)
                    
                    // Save image if exists (use same basename)
                    if let imageData = measurement.chartImageData {
                        let imageURL = directoryURL.appendingPathComponent("\(basename).png")
                        try imageData.write(to: imageURL)
                    }
                    
                    print("✅ Exported measurement to: \(directoryURL.path)")
                } catch {
                    print("Failed to save files: \(error)")
                }
            }
            self.isExporting = false
        }
        #endif
    }
    
    private func deleteAll() {
        analyzer.savedMeasurements.removeAll()
    }
    
    private func showDetail(for measurement: TapToneMeasurement) {
        selectedMeasurement = measurement
        // Use async to decouple sheet presentation from button action
        DispatchQueue.main.async {
            self.showingDetailSheet = true
        }
    }
}

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

// MARK: - Measurements List View Extension

extension MeasurementsListView {
    var importSheet: some View {
        Group {
            #if os(iOS)
            if showingImportPicker {
                DocumentPicker(isPresented: $showingImportPicker) { url in
                    importFromFile(url: url)
                }
            }
            #endif
        }
        .alert("Import Error", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            if let error = importError {
                Text(error)
            }
        }
        .alert("Import Successful", isPresented: .constant(importSuccess != nil)) {
            Button("OK") { importSuccess = nil }
        } message: {
            if let success = importSuccess {
                Text(success)
            }
        }
        #if os(macOS)
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importFromFile(url: url)
                }
            case .failure(let error):
                importError = "Failed to open file: \(error.localizedDescription)"
            }
        }
        #endif
    }
    
    private func importFromFile(url: URL) {
        do {
            let data: Data
            
            // Handle security-scoped resource for sandboxed apps
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            data = try Data(contentsOf: url)
            let count = try analyzer.importMeasurements(from: data, baseURL: url)
            importSuccess = "Successfully imported \(count) measurement\(count == 1 ? "" : "s")"
        } catch {
            importError = "Failed to import: \(error.localizedDescription)"
        }
    }
}

struct MeasurementRowView: View {
    let measurement: TapToneMeasurement
    
    // Break down complex expressions for better compilation
    private var peaksText: String {
        "\(measurement.peaks.count) peaks"
    }
    
    private var ratioText: String? {
        if let ratio = measurement.tapToneRatio {
            return "Ratio: \(String(format: "%.2f", ratio))"
        }
        return nil
    }
    
    private var decayText: String? {
        if let decay = measurement.decayTime {
            return "Decay: \(String(format: "%.2f", decay))s"
        }
        return nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let location = measurement.tapLocation {
                    Text(location)
                        .font(.headline)
                } else {
                    Text("Measurement")
                        .font(.headline)
                }
                
                Spacer()
                
                // Show indicators for attached data
                HStack(spacing: 6) {
                    if measurement.chartImageFilename != nil || measurement.chartImageData != nil {
                        Image(systemName: "photo.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    if measurement.spectrumSnapshot != nil {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    Text(measurement.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Simplified metadata row
            HStack {
                Text(peaksText)
                
                if let ratio = ratioText {
                    Text("•")
                    Text(ratio)
                }
                
                if let decay = decayText {
                    Text("•")
                    Text(decay)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            if let notes = measurement.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MeasurementDetailView: View {
    let measurement: TapToneMeasurement
    @ObservedObject var analyzer: TapToneAnalyzer
    @Environment(\.dismiss) var dismiss
    @State private var showingExport = false
    @State private var exportText = ""
    @State private var isExporting = false
    @State private var chartImage: Image?
    @State private var showingLoadConfirmation = false
    
    var body: some View {
        #if os(macOS)
        // On macOS, sheets need their own NavigationView
        NavigationView {
            contentView
                .navigationTitle("Measurement Details")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: loadMeasurement) {
                            Label("Load", systemImage: "arrow.down.doc")
                        }
                    }
                    
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { exportJSONFile() }) {
                            Label("Export JSON", systemImage: "doc.text")
                        }
                    }
                    
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { exportChartImage() }) {
                            Label("Export Chart", systemImage: "chart.xyaxis.line")
                        }
                    }
                    
                    if measurement.chartImageFilename != nil || measurement.chartImageData != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button(action: { shareChartImage() }) {
                                Label("Saved Image", systemImage: "photo")
                            }
                        }
                    }
                }
        }
        .frame(minWidth: 600, minHeight: 500)
        .sheet(isPresented: $showingExport) {
            ExportView(text: exportText)
        }
        .alert("Load Measurement", isPresented: $showingLoadConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Load") {
                analyzer.loadMeasurement(measurement)
                dismiss()
            }
        } message: {
            Text("This will replace the current analysis view with this measurement's data, including peaks and spectrum. Continue?")
        }
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Exporting...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(30)
                    .background(Color.secondary.opacity(0.8))
                    .cornerRadius(12)
                }
            }
        }
        #else
        // On iOS, NavigationLink provides the navigation context
        contentView
            .navigationTitle("Measurement Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: loadMeasurement) {
                        Label("Load", systemImage: "arrow.down.doc")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { exportJSONFile() }) {
                            Label("Export JSON", systemImage: "doc.text")
                        }
                        
                        Button(action: { exportChartImage() }) {
                            Label("Export Chart Image", systemImage: "chart.xyaxis.line")
                        }
                        
                        if measurement.chartImageFilename != nil || measurement.chartImageData != nil {
                            Button(action: { shareChartImage() }) {
                                Label("Share Saved Image", systemImage: "photo")
                            }
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showingExport) {
                ExportView(text: exportText)
            }
            .alert("Load Measurement", isPresented: $showingLoadConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Load") {
                    analyzer.loadMeasurement(measurement)
                    dismiss()
                }
            } message: {
                Text("This will replace the current analysis view with this measurement's data, including peaks and spectrum. Continue?")
            }
            .overlay {
                if isExporting {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Exporting...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(30)
                        .background(Color.secondary.opacity(0.8))
                        .cornerRadius(12)
                    }
                }
            }
        #endif
    }
    
    @ViewBuilder
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Info
                GroupBox("Measurement Info") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let location = measurement.tapLocation {
                                HStack {
                                    Text("Location:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(location)
                                        .font(.body)
                                        .fontWeight(.medium)
                                }
                            }
                            
                            HStack {
                                Text("Date:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(measurement.timestamp, style: .date)
                                    .font(.body)
                                Text("at")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(measurement.timestamp, style: .time)
                                    .font(.body)
                            }
                            
                            if let decay = measurement.decayTime {
                                HStack {
                                    Text("Ring-Out:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(decay, specifier: "%.2f") seconds")
                                        .font(.body)
                                        .fontWeight(.medium)
                                }
                            }
                            
                            if let ratio = measurement.tapToneRatio {
                                HStack {
                                    Text("Tap Tone Ratio:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(ratio, specifier: "%.2f") : 1")
                                        .font(.body)
                                        .fontWeight(.medium)
                                }
                            }
                            
                            if let notes = measurement.notes, !notes.isEmpty {
                                Divider()
                                Text("Notes:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(notes)
                                    .font(.body)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Peaks
                    GroupBox("Detected Peaks (\(measurement.peaks.count))") {
                        if measurement.peaks.isEmpty {
                            Text("No peaks detected")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(measurement.peaks.sorted(by: { $0.frequency < $1.frequency })) { peak in
                                    let mode = GuitarMode.classify(frequency: peak.frequency)
                                    CombinedPeakModeRowView(peak: peak, mode: mode)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
    }
    
    private func loadMeasurement() {
        showingLoadConfirmation = true
    }
    
    private func shareChartImage() {
        guard let imageData = measurement.chartImageData else { return }
        
        #if os(iOS)
        if let uiImage = UIImage(data: imageData) {
            let activityVC = UIActivityViewController(
                activityItems: [uiImage],
                applicationActivities: nil
            )
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(activityVC, animated: true)
            }
        }
        #elseif os(macOS)
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        let locationName = measurement.tapLocation ?? "chart"
        savePanel.nameFieldStringValue = "\(locationName)-saved-\(Int(measurement.timestamp.timeIntervalSince1970)).png"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? imageData.write(to: url)
            }
        }
        #endif
    }
    
    private func exportJSONFile() {
        isExporting = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            if let data = try? encoder.encode([self.measurement]),
               let json = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.saveJSONAndImageToFiles(json: json, measurement: self.measurement)
                }
            } else {
                DispatchQueue.main.async {
                    self.isExporting = false
                }
            }
        }
    }
    
    private func saveJSONAndImageToFiles(json: String, measurement: TapToneMeasurement) {
        #if os(iOS)
        // Create temp directory with JSON and image
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("GuitarTap-Export-\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // Use consistent basename for both files
            let basename = measurement.baseFilename
            
            // Save JSON
            let jsonURL = tempDir.appendingPathComponent("\(basename).json")
            try json.write(to: jsonURL, atomically: true, encoding: .utf8)
            
            // Save image if exists (use same basename)
            if let imageData = measurement.chartImageData {
                let imageURL = tempDir.appendingPathComponent("\(basename).png")
                try imageData.write(to: imageURL)
            }
            
            let documentPicker = UIDocumentPickerViewController(forExporting: [tempDir], asCopy: true)
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(documentPicker, animated: true)
            }
        } catch {
            print("Failed to export: \(error)")
        }
        
        self.isExporting = false
        
        #elseif os(macOS)
        // On macOS, use panel to select directory
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Select a folder to save measurement and image"
        panel.prompt = "Export Here"
        
        panel.begin { response in
            if response == .OK, let directoryURL = panel.url {
                do {
                    // Use consistent basename for both files
                    let basename = measurement.baseFilename
                    
                    // Save JSON
                    let jsonURL = directoryURL.appendingPathComponent("\(basename).json")
                    try json.write(to: jsonURL, atomically: true, encoding: .utf8)
                    
                    // Save image if exists (use same basename)
                    if let imageData = measurement.chartImageData {
                        let imageURL = directoryURL.appendingPathComponent("\(basename).png")
                        try imageData.write(to: imageURL)
                    }
                    
                    print("✅ Exported measurement to: \(directoryURL.path)")
                } catch {
                    print("Failed to save files: \(error)")
                }
            }
            self.isExporting = false
        }
        #endif
    }
    
    private func exportChartImage() {
        isExporting = true
        
        DispatchQueue.main.async {
            let chartView = self.createExportableChartView()
            let renderer = ImageRenderer(content: chartView)
            
            #if os(iOS)
            renderer.scale = UIScreen.main.scale
            
            if let uiImage = renderer.uiImage {
                let activityVC = UIActivityViewController(
                    activityItems: [uiImage],
                    applicationActivities: nil
                )
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    rootViewController.present(activityVC, animated: true)
                }
            }
            self.isExporting = false
            #elseif os(macOS)
            renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
            
            if let nsImage = renderer.nsImage {
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.png]
                let locationName = measurement.tapLocation ?? "chart"
                savePanel.nameFieldStringValue = "\(locationName)-\(Int(measurement.timestamp.timeIntervalSince1970)).png"
                
                savePanel.begin { response in
                    if response == .OK, let url = savePanel.url {
                        if let tiffData = nsImage.tiffRepresentation,
                           let bitmapImage = NSBitmapImageRep(data: tiffData),
                           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                            try? pngData.write(to: url)
                        }
                    }
                    self.isExporting = false
                }
            } else {
                self.isExporting = false
            }
            #endif
        }
    }
    
    @ViewBuilder
    private func createExportableChartView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Guitar Tap Tone Analysis")
                    .font(.title)
                    .fontWeight(.bold)
                
                if let location = measurement.tapLocation {
                    Text("Location: \(location)")
                        .font(.headline)
                }
                
                HStack {
                    Text("Date: \(measurement.timestamp.formatted())")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let ratio = measurement.tapToneRatio {
                        Text("Tap Tone Ratio: \(ratio, specifier: "%.2f"):1")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            }
            .padding()
            
            // Chart
            Chart {
                ForEach(measurement.peaks) { peak in
                    let mode = GuitarMode.classify(frequency: peak.frequency)
                    
                    PointMark(
                        x: .value("Frequency", peak.frequency),
                        y: .value("Magnitude", peak.magnitude)
                    )
                    .foregroundStyle(modeColor(for: mode))
                    .symbol(.circle)
                    .symbolSize(200)
                    
                    RuleMark(
                        x: .value("Frequency", peak.frequency)
                    )
                    .foregroundStyle(modeColor(for: mode).opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    .annotation(position: .top, alignment: .center) {
                        VStack(spacing: 2) {
                            Text("\(peak.frequency, specifier: "%.1f") Hz")
                                .font(.caption)
                                .fontWeight(.bold)
                            Text(mode.rawValue)
                                .font(.caption2)
                                .foregroundColor(modeColor(for: mode))
                            Text("\(peak.magnitude, specifier: "%.1f") dB")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(6)
                        .background(Color.white)
                        .cornerRadius(6)
                        .shadow(radius: 2)
                    }
                }
            }
            .chartXAxisLabel("Frequency (Hz)", alignment: .center)
            .chartYAxisLabel("Magnitude (dB)", alignment: .center)
            .frame(width: 1200, height: 700)
            .padding()
            
            // Legend
            HStack(spacing: 20) {
                ForEach([GuitarMode.helmholtz, .crossGrain, .longGrain, .monopole, .dipole, .ringMode], id: \.self) { mode in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(modeColor(for: mode))
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
    
    private func modeColor(for mode: GuitarMode) -> Color {
        switch mode {
        case .helmholtz: return .cyan
        case .crossGrain: return .blue
        case .longGrain: return .green
        case .monopole: return .orange
        case .dipole: return .red
        case .ringMode: return .purple
        case .upperModes: return .gray
        case .unknown: return .secondary
        }
    }
}

struct ExportView: View {
    let text: String
    @Environment(\.dismiss) var dismiss
    @State private var showingCopyConfirmation = false
    @State private var showingSaveConfirmation = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Info banner
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Measurement Data (JSON)")
                            .font(.headline)
                    }
                    
                    Text("This data can be imported into analysis tools, spreadsheets, or shared with other users.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                
                Divider()
                
                // JSON content
                ScrollView {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Confirmation overlays
                if showingCopyConfirmation {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                            Text("Copied to clipboard")
                                .foregroundColor(.white)
                                .font(.subheadline)
                        }
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                        .padding()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                if showingSaveConfirmation {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                            Text("File saved successfully")
                                .foregroundColor(.white)
                                .font(.subheadline)
                        }
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                        .padding()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Export Data")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: saveToFile) {
                            Label("Save to Files", systemImage: "folder")
                        }
                        
                        Button(action: copyToClipboard) {
                            Label("Copy to Clipboard", systemImage: "doc.on.doc")
                        }
                        
                        ShareLink(item: createTemporaryFile(), preview: SharePreview("measurements.json")) {
                            Label("Share File", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button(action: saveToFile) {
                        Label("Save File", systemImage: "square.and.arrow.down")
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: copyToClipboard) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
                #endif
            }
        }
        .animation(.easeInOut, value: showingCopyConfirmation)
        .animation(.easeInOut, value: showingSaveConfirmation)
    }
    
    private func saveToFile() {
        #if os(iOS)
        // On iOS, use UIDocumentPickerViewController to let user choose save location
        let tempURL = createTemporaryFile()
        let documentPicker = UIDocumentPickerViewController(forExporting: [tempURL], asCopy: true)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(documentPicker, animated: true) {
                self.showingSaveConfirmation = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.showingSaveConfirmation = false
                }
            }
        }
        #elseif os(macOS)
        // On macOS, use NSSavePanel
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "measurements-\(Date().timeIntervalSince1970).json"
        savePanel.canCreateDirectories = true
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try self.text.write(to: url, atomically: true, encoding: .utf8)
                    self.showingSaveConfirmation = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.showingSaveConfirmation = false
                    }
                } catch {
                    print("Failed to save file: \(error)")
                }
            }
        }
        #endif
    }
    
    private func createTemporaryFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "measurements-\(Date().timeIntervalSince1970).json"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
        
        return fileURL
    }
    
    private func copyToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        
        showingCopyConfirmation = true
        
        // Hide confirmation after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showingCopyConfirmation = false
        }
    }
}

// MARK: - Preview

#Preview {
    TapToneAnalysisView()
}
