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
    
    // Spectrum display state
    @State private var minFreq: Float = 20
    @State private var maxFreq: Float = 1000
    @State private var minDB: Float = -100
    @State private var maxDB: Float = 0
    @State private var isLogarithmic: Bool = false
    @State private var minFreqInput: String = "20"
    @State private var maxFreqInput: String = "1000"
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
        NavigationView {
            if showingMetrics {
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
            } else {
                mainContentView
            }
        }
    }
    #endif
    
    /// iOS layout with adaptive metrics display
    @ViewBuilder
    private var iOSLayout: some View {
        NavigationView {
            if horizontalSizeClass == .regular && showingMetrics {
                // iPad: Side-by-side layout
                HStack(spacing: 0) {
                    mainContentView
                        .frame(maxWidth: .infinity)
                    
                    Divider()
                    
                    ScrollView {
                        FFTAnalysisMetricsView(analyzer: fftAnalyzer)
                            .padding()
                    }
                    .frame(width: 350)
                }
            } else {
                // iPhone or iPad without metrics panel
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
                    
                    // Current peaks display
                    currentPeaksView
                    
                    // Mode identification
                    modeIdentificationView
                    
                    // Decay time
                    decayTimeView
                    
                    // Tap tone ratio
                    tapToneRatioView
                    
                    // Peak history chart
                    peakHistoryChart
                }
                .padding()
            }
        }
        .navigationTitle("Tap Tone Analysis")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Button(action: { showingMetrics.toggle() }) {
                        Label(
                            showingMetrics ? "Hide Metrics" : "Show Metrics",
                            systemImage: showingMetrics ? "chart.bar.fill" : "chart.bar"
                        )
                    }
                    
                    Button(action: { showingMeasurements = true }) {
                        Label("Measurements", systemImage: "list.bullet")
                    }
                }
            }
        }
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
                onFrequencyRangeChanged: updateFrequencyInputFields
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
    
    private var currentPeaksView: some View {
        GroupBox("Detected Peaks") {
            if tapToneAnalyzer.currentPeaks.isEmpty {
                Text("No peaks detected")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(tapToneAnalyzer.currentPeaks.prefix(5)) { peak in
                        PeakRowView(peak: peak)
                    }
                }
            }
        }
    }
    
    private var modeIdentificationView: some View {
        GroupBox("Identified Modes") {
            if tapToneAnalyzer.identifiedModes.isEmpty {
                Text("No modes identified")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(tapToneAnalyzer.identifiedModes.prefix(8), id: \.peak.id) { item in
                        ModeRowView(peak: item.peak, mode: item.mode)
                    }
                }
            }
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
    
    private var tapToneRatioView: some View {
        GroupBox("Tap Tone Ratio") {
            if let ratio = tapToneAnalyzer.calculateTapToneRatio() {
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
                        Text(ratioQuality(ratio))
                            .font(.headline)
                            .foregroundColor(ratioQualityColor(ratio))
                        
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
    
    private var peakHistoryChart: some View {
        GroupBox("Peak Tracking") {
            if tapToneAnalyzer.peakHistory.isEmpty {
                Text("No history available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart {
                    ForEach(Array(tapToneAnalyzer.peakHistory.enumerated()), id: \.offset) { index, peaks in
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
        tapToneAnalyzer.saveMeasurement(
            tapLocation: tapLocation.isEmpty ? nil : tapLocation,
            notes: notes.isEmpty ? nil : notes,
            includeSpectrum: true
        )
        tapLocation = ""
        notes = ""
        showingSaveSheet = false
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
}

// MARK: - Supporting Views

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
        NavigationView {
            Form {
                Section("Tap Location") {
                    TextField("e.g., Bridge, Soundhole, Upper Bout", text: $tapLocation)
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
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
    }
}

struct MeasurementsListView: View {
    @ObservedObject var analyzer: TapToneAnalyzer
    @Environment(\.dismiss) var dismiss
    @State private var showingExport = false
    @State private var exportText = ""
    
    var body: some View {
        NavigationView {
            List {
                ForEach(analyzer.savedMeasurements) { measurement in
                    MeasurementRowView(measurement: measurement)
                }
                .onDelete { indexSet in
                    indexSet.forEach { index in
                        analyzer.deleteMeasurement(analyzer.savedMeasurements[index])
                    }
                }
            }
            .navigationTitle("Saved Measurements")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: exportMeasurements) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showingExport) {
                ExportView(text: exportText)
            }
        }
    }
    
    private func exportMeasurements() {
        if let json = analyzer.exportMeasurements() {
            exportText = json
            showingExport = true
        }
    }
}

struct MeasurementRowView: View {
    let measurement: TapToneMeasurement
    
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
                
                Text(measurement.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("\(measurement.peaks.count) peaks")
                
                if let ratio = measurement.tapToneRatio {
                    Text("•")
                    Text("Ratio: \(ratio, specifier: "%.2f")")
                }
                
                if let decay = measurement.decayTime {
                    Text("•")
                    Text("Decay: \(decay, specifier: "%.2f")s")
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

struct ExportView: View {
    let text: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
            }
            .navigationTitle("Export Data")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: text)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    TapToneAnalysisView()
}
