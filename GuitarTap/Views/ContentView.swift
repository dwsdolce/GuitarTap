//
//  ContentView.swift
//  GuitarTap
//
//  Created by David Smith on 12/31/25.
//

import SwiftUI
import Charts
import AVFoundation

#if os(macOS)
import AppKit
#endif

// MARK: - Constants

let freqRangeMin: Float = 75
let freqRangeMinStr: String = freqRangeMin.formatted(.number.precision(.fractionLength(0)))
let freqRangeMax: Float = 350
let freqRangeMaxStr: String = freqRangeMax.formatted(.number.precision(.fractionLength(0)))
let magRangeMin: Float = -100
let magRangeMinStr: String = magRangeMin.formatted(.number.precision(.fractionLength(0)))
let magRangeMax: Float = 0
let MagRangeMaxStr: String = magRangeMax.formatted(.number.precision(.fractionLength(0)))

// MARK: - Main View

/// The main content view for the Real-Time FFT Analyzer application.
///
/// This view provides:
/// - Start/Stop controls for the audio analyzer
/// - Peak frequency and magnitude display
/// - Interactive frequency spectrum visualization
/// - Manual frequency range controls with text input
/// - Logarithmic/linear scale toggle
/// - Zoom controls
///
/// ## Architecture
/// The view uses the MVVM pattern with `RealtimeFFTAnalyzer` as the view model.
/// The analyzer publishes FFT results via Combine's `@Published` properties, which
/// automatically update the SwiftUI view.
struct ContentView: View {
    // MARK: - State Properties
    
    /// The FFT analyzer instance that processes microphone input
    /// Configured with 65,536 FFT size and 48000 Hz sample rate for high resolution
    @StateObject private var analyzer = RealtimeFFTAnalyzer(fftSize: 65536, targetSampleRate: 48000)

    /// Current visible frequency range in Hz
    @State private var minFreq: Float = freqRangeMin
    @State private var maxFreq: Float = 300
    
    /// Current visible magnitude range in dB
    @State private var minDB: Float = -100
    @State private var maxDB: Float = 0
    
    /// Error message to display if audio engine fails to start
    @State private var errorMessage: String?
    
    /// Whether to use logarithmic frequency scale (default) or linear
    @State private var isLogarithmic: Bool = false
    
    /// Text field inputs for manual frequency range entry
    @State private var minFreqInput: String = freqRangeMinStr
    @State private var maxFreqInput: String = freqRangeMaxStr
    
    /// Text field inputs for manual magnitude range entry
    @State private var minDBInput: String = magRangeMinStr
    @State private var maxDBInput: String = MagRangeMaxStr
    
    /// Controls whether the metrics panel is visible (for compact layouts)
    @State private var showMetricsPanel: Bool = false
    
    // MARK: - Environment
    
    /// Horizontal size class for adaptive layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // MARK: - Body
    
    var body: some View {
        #if os(macOS)
        macOSLayout
        #elseif os(iOS)
        iOSLayout
        #else
        defaultLayout
        #endif
    }
    
    // MARK: - Platform-Specific Layouts
    
    #if os(macOS)
    /// macOS layout with side-by-side panels and optional metrics
    @ViewBuilder
    private var macOSLayout: some View {
        HSplitView {
            // Main content
            mainContentView
                .frame(minWidth: 600, idealWidth: 800)
            
            // Metrics panel (resizable)
            ScrollView {
                FFTAnalysisMetricsView(analyzer: analyzer)
                    .padding()
            }
            .frame(minWidth: 300, idealWidth: 350, maxWidth: 450)
        }
        .onDisappear {
            cleanup()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            cleanup()
        }
    }
    #endif
    
    /// iOS layout that adapts based on size class (iPhone vs iPad)
    @ViewBuilder
    private var iOSLayout: some View {
        if horizontalSizeClass == .regular {
            // iPad: Side-by-side layout
            HStack(spacing: 0) {
                mainContentView
                    .frame(maxWidth: .infinity)
                
                Divider()
                
                ScrollView {
                    FFTAnalysisMetricsView(analyzer: analyzer)
                        .padding()
                }
                .frame(width: 350)
            }
            .onDisappear {
                cleanup()
            }
        } else {
            // iPhone: Tabs or overlay
            TabView {
                // Main spectrum tab with compact overlay
                ZStack(alignment: .topTrailing) {
                    mainContentView
                    
                    CompactFFTMetricsOverlay(analyzer: analyzer)
                        .padding(12)
                }
                .tabItem {
                    Label("Spectrum", systemImage: "waveform.path")
                }
                
                // Full metrics tab
                ScrollView {
                    FFTAnalysisMetricsView(analyzer: analyzer)
                        .padding()
                }
                .tabItem {
                    Label("Metrics", systemImage: "chart.bar.fill")
                }
            }
            .onDisappear {
                cleanup()
            }
        }
    }
    
    /// Default layout for other platforms
    @ViewBuilder
    private var defaultLayout: some View {
        mainContentView
            .onDisappear {
                cleanup()
            }
    }
    
    // MARK: - Main Content View (Shared)
    
    /// The main content view shared across all platforms
    @ViewBuilder
    private var mainContentView: some View {
        VStack(spacing: 20) {
            // MARK: - Title and Peak Frequency Display
            VStack(spacing: 12) {
                Text("Guitar Tap")
                    .font(.title)
                    .fontWeight(.bold)
            }
            
            // MARK: - Spectrum Visualization Section
            VStack(alignment: .leading, spacing: 8) {
                // Toolbar: title, scale toggle, and reset button
                HStack {
                    Text("Frequency Spectrum")
                        .font(.headline)
                    
                    Spacer()
                    
                    Toggle(isOn: $isLogarithmic) {
                        Text("Logarithmic")
                    }
                    .toggleStyle(.switch)
                    .font(.caption)
                    
                    Button(action: resetZoom) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset Zoom")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                
                // MARK: - Combined Range Controls
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
                                    .onSubmit {
                                        applyFrequencyRange()
                                    }
                                Text("–")
                                    .foregroundColor(.secondary)
                                TextField("Max", text: $maxFreqInput)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                    .onSubmit {
                                        applyFrequencyRange()
                                    }
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
                                    .onSubmit {
                                        applyMagnitudeRange()
                                    }
                                Text("–")
                                    .foregroundColor(.secondary)
                                TextField("Max", text: $maxDBInput)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                    .onSubmit {
                                        applyMagnitudeRange()
                                    }
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
                
                // MARK: - Chart Display
                SpectrumView(
                    frequencies: analyzer.frequencies,
                    magnitudes: analyzer.magnitudes,
                    minFreq: $minFreq,
                    maxFreq: $maxFreq,
                    minDB: $minDB,
                    maxDB: $maxDB,
                    isLogarithmic: $isLogarithmic,
                    onFrequencyRangeChanged: updateFrequencyInputFields
                )
                .frame(minWidth:200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity,  alignment: .center)
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(10)
                
                // MARK: - Range Display
                HStack {
                    Text("Range: \(formatFrequency(minFreq)) - \(formatFrequency(maxFreq))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(minDB)) to \(Int(maxDB)) dB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            
            // MARK: - Start/Stop Controls
            VStack(spacing: 8) {
                Button(action: toggleAnalyzer) {
                    HStack(spacing: 6) {
                        Image(systemName: analyzer.isRunning ? "stop.circle.fill" : "play.circle.fill")
                        Text(analyzer.isRunning ? "Stop" : "Start")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(analyzer.isRunning ? Color.red : Color.green)
                    .cornerRadius(8)
                }
                
                // Display error message if audio engine fails
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Cleanup
    
    /// Performs cleanup when the window is closed or app is terminating.
    ///
    /// This method ensures that:
    /// - The audio analyzer is properly stopped
    /// - Audio engine resources are released
    /// - Audio session is deactivated (on iOS)
    private func cleanup() {
        // Stop the analyzer if it's running
        if analyzer.isRunning {
            analyzer.stop()
        }
        
        #if os(iOS)
        // Deactivate audio session on iOS
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Error deactivating audio session: \(error)")
        }
        #endif
    }
    
    // MARK: - Helper Methods
    
    /// Toggles the analyzer between running and stopped states.
    ///
    /// When starting, attempts to initialize the audio engine and begin capturing.
    /// On iOS, this will request microphone permissions if not already granted.
    /// Any errors are caught and displayed in the UI.
    private func toggleAnalyzer() {
        if analyzer.isRunning {
            analyzer.stop()
            errorMessage = nil
        } else {
            #if os(iOS)
            // Request microphone permission on iOS
            let session = AVAudioSession.sharedInstance()
            do {
                // Category .record minimizes output routing and is ideal for analysis
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetoothA2DP])
                try session.setActive(true)
                if #available(iOS 17.0, *) {
                    AVAudioApplication.requestRecordPermission { granted in
                        if granted {
                            self.startAnalyzer()
                        } else {
                            print("Microphone permission not granted")
                        }
                    }
                } else {
                    session.requestRecordPermission { granted in
                        if !granted {
                            print("Microphone permission not granted")
                        }
                    }
                }
            } catch {
                print("Audio session error: \(error)")
            }
            #else
            // On macOS and other platforms, start directly
            startAnalyzer()
            #endif
        }
    }
    
    /// Starts the analyzer after permissions have been granted.
    ///
    /// This helper method handles the actual analyzer startup and error handling.
    private func startAnalyzer() {
        do {
            try analyzer.start()
            errorMessage = nil
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
    }
    
    /// Resets the zoom level to show the full frequency and magnitude ranges.
    ///
    /// Sets frequency range to 20 Hz - 20 kHz (full audible spectrum)
    /// and magnitude range to -80 dB to 0 dB (typical audio levels).
    /// Also updates the text input fields to reflect the reset values.
    private func resetZoom() {
        minFreq = freqRangeMin
        maxFreq = freqRangeMax
        minDB = magRangeMin
        maxDB = magRangeMax
        
        // Update text fields to match
        minFreqInput = freqRangeMinStr
        maxFreqInput = freqRangeMaxStr
        minDBInput = magRangeMinStr
        maxDBInput = MagRangeMaxStr
    }
    
    /// Applies the frequency range from the text input fields to the chart.
    ///
    /// Validates and clamps the input values to ensure they're within valid ranges:
    /// - Frequencies must be between 20 Hz and 20,000 Hz
    /// - Min must be less than max with at least 10 Hz difference
    ///
    /// Invalid inputs are automatically corrected and the text fields updated.
    private func applyFrequencyRange() {
        // Parse the input strings to Float values
        guard let newMinFreq = Float(minFreqInput),
              let newMaxFreq = Float(maxFreqInput) else {
            // Invalid input (non-numeric), reset to current values
            minFreqInput = String(format: "%.0f", minFreq)
            maxFreqInput = String(format: "%.0f", maxFreq)
            return
        }
        
        // Validate and clamp the range to audio spectrum limits
        let clampedMin = max(20, min(newMinFreq, 20000))
        let clampedMax = max(20, min(newMaxFreq, 20000))
        
        // Ensure min < max with at least a small range for meaningful display
        if clampedMin < clampedMax && (clampedMax - clampedMin) >= 10 {
            minFreq = clampedMin
            maxFreq = clampedMax
            
            // Update text fields with validated and clamped values
            minFreqInput = String(format: "%.0f", clampedMin)
            maxFreqInput = String(format: "%.0f", clampedMax)
        } else {
            // Invalid range (min >= max or too narrow), reset to current values
            minFreqInput = String(format: "%.0f", minFreq)
            maxFreqInput = String(format: "%.0f", maxFreq)
        }
    }
    
    /// Updates the text input fields to reflect the current frequency range.
    ///
    /// This is called automatically when the user zooms or pans via gestures,
    /// keeping the text fields in sync with the visible range.
    private func updateFrequencyInputFields() {
        // Update text fields to reflect current frequency range after zoom/pan
        minFreqInput = String(format: "%.0f", minFreq)
        maxFreqInput = String(format: "%.0f", maxFreq)
    }
    
    /// Applies the magnitude range from the text input fields to the chart.
    ///
    /// Validates and clamps the input values to ensure they're within valid ranges:
    /// - Magnitudes must be between -120 dB and +20 dB
    /// - Min must be less than max with at least 10 dB difference
    ///
    /// Invalid inputs are automatically corrected and the text fields updated.
    private func applyMagnitudeRange() {
        // Parse the input strings to Float values
        guard let newMinDB = Float(minDBInput),
              let newMaxDB = Float(maxDBInput) else {
            // Invalid input (non-numeric), reset to current values
            minDBInput = String(format: "%.0f", minDB)
            maxDBInput = String(format: "%.0f", maxDB)
            return
        }
        
        // Validate and clamp the range to reasonable dB limits
        let clampedMin = max(-120, min(newMinDB, 20))
        let clampedMax = max(-120, min(newMaxDB, 20))
        
        // Ensure min < max with at least 10 dB range for meaningful display
        if clampedMin < clampedMax && (clampedMax - clampedMin) >= 10 {
            minDB = clampedMin
            maxDB = clampedMax
            
            // Update text fields with validated and clamped values
            minDBInput = String(format: "%.0f", clampedMin)
            maxDBInput = String(format: "%.0f", clampedMax)
        } else {
            // Invalid range (min >= max or too narrow), reset to current values
            minDBInput = String(format: "%.0f", minDB)
            maxDBInput = String(format: "%.0f", maxDB)
        }
    }
    
    /// Formats a frequency value for display with appropriate units.
    ///
    /// - Parameter freq: Frequency in Hz
    /// - Returns: Formatted string with "Hz" or "k Hz" suffix
    ///
    /// Values >= 1000 Hz are displayed in kHz for brevity (e.g., "1.5k Hz")
    private func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.1fk Hz", freq / 1000)
        } else {
            return String(format: "%.0f Hz", freq)
        }
    }
}
