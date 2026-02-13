//
//  SpectrumView.swift
//  GuitarTap
//
//  Created by David Smith on 12/31/25.
//

import SwiftUI
import Charts

#if os(macOS)
import AppKit
#endif

// MARK: - Spectrum Data Point

/// A data point representing a single frequency bin in the spectrum visualization.
///
/// Each point contains a frequency value (in Hz) and its corresponding magnitude (in dB).
/// The `Identifiable` conformance allows SwiftUI Charts to efficiently track and render each point.
struct SpectrumDataPoint: Identifiable {
    /// Unique identifier for SwiftUI's identity system
    let id = UUID()
    
    /// The frequency of this bin in Hz
    let frequency: Float
    
    /// The magnitude at this frequency in dB (typically -100 to 0 dB)
    let magnitude: Float
}

// MARK: - Spectrum View

/// A SwiftUI view that displays a frequency spectrum chart with interactive zoom and pan capabilities.
///
/// This view renders the FFT magnitude data as an area chart with gradient fill and a line overlay.
/// It supports both linear and logarithmic frequency scales, pinch-to-zoom, and drag-to-pan gestures.
///
/// ## Features
/// - Area chart with gradient fill for visual appeal
/// - Line chart overlay showing the spectrum shape
/// - Automatic axis labels with smart frequency formatting (Hz or kHz)
/// - Logarithmic or linear frequency scale
/// - Interactive zoom and pan gestures
/// - Clamped ranges to prevent invalid zoom levels
/// - Mode boundary markers
/// - Peak annotations
///
/// ## Gesture Controls
/// - **Pinch**: Zoom in/out on both frequency and dB axes
/// - **Drag**: Pan the view horizontally (frequency) and vertically (dB)
struct SpectrumView: View {
    // MARK: - Properties
    
    /// Array of frequency values in Hz for each FFT bin
    let frequencies: [Float]
    
    /// Array of magnitude values in dB for each FFT bin
    let magnitudes: [Float]
    
    /// The minimum frequency to display on the x-axis, in Hz
    @Binding var minFreq: Float
    
    /// The maximum frequency to display on the x-axis, in Hz
    @Binding var maxFreq: Float
    
    /// The minimum magnitude to display on the y-axis, in dB
    @Binding var minDB: Float
    
    /// The maximum magnitude to display on the y-axis, in dB
    @Binding var maxDB: Float
    
    /// Whether to use logarithmic scale for the frequency axis
    @Binding var isLogarithmic: Bool
    
    /// Optional array of peaks to annotate on the chart
    var peaks: [ResonantPeak]?
    
    /// Whether to show mode boundary markers
    var showModeBoundaries: Bool = true
    
    /// Callback invoked when the frequency range changes due to zoom/pan gestures
    var onFrequencyRangeChanged: (() -> Void)?
    
    /// Optional binding to annotation offsets for draggable labels
    var annotationOffsets: Binding<[UUID: CGPoint]>?
    
    /// Optional threshold lines to display (for tap detection visualization)
    var thresholdLines: [(value: Float, label: String, color: Color, lineWidth: CGFloat, dash: [CGFloat])]?
    
    // MARK: - Gesture State
    
    /// Tracks drag offset during pan gestures
    @State private var dragOffset: CGSize = .zero
    
    /// Tracks magnification scale during pinch gestures
    @GestureState private var magnificationScale: CGFloat = 1.0
    
    /// Tracks whether an annotation is currently being dragged
    @State private var isAnnotationDragging: Bool = false
    
    // MARK: - Computed Properties
    
    /// Filters and converts the frequency/magnitude arrays into chart data points.
    ///
    /// Only includes data points within the current visible frequency range.
    /// This improves rendering performance for large FFT sizes.
    private var chartData: [SpectrumDataPoint] {
        zip(frequencies, magnitudes)
            .filter { $0.0 >= minFreq && $0.0 <= maxFreq }
            .map { SpectrumDataPoint(frequency: $0.0, magnitude: $0.1) }
    }
    
    /// Returns the mode boundaries that are visible in the current frequency range
    private var visibleModeBoundaries: [(frequency: Float, mode: GuitarMode)] {
        let allModes: [GuitarMode] = [.helmholtz, .crossGrain, .longGrain, .monopole, .dipole, .ringMode, .upperModes]
        var boundaries: [(Float, GuitarMode)] = []
        
        for mode in allModes {
            let range = mode.idealRange
            // Add lower boundary if visible
            if range.lowerBound >= minFreq && range.lowerBound <= maxFreq {
                boundaries.append((range.lowerBound, mode))
            }
            // Add upper boundary if visible
            if range.upperBound >= minFreq && range.upperBound <= maxFreq {
                boundaries.append((range.upperBound, mode))
            }
        }
        
        return boundaries
    }
    
    /// Returns peaks that are visible in the current frequency range
    private var visiblePeaks: [ResonantPeak] {
        peaks?.filter { $0.frequency >= minFreq && $0.frequency <= maxFreq } ?? []
    }
    
    /// Calculates appropriate frequency values for axis labels based on the current zoom level.
    ///
    /// The values are chosen to provide clear, readable labels that adjust to the visible range:
    /// - In logarithmic mode, uses standard audio frequency markers (20, 100, 1k, 10k, etc.)
    /// - In linear mode, uses evenly spaced values with appropriate step sizes
    ///
    /// - Returns: An array of frequency values (in Hz) where axis labels should be placed
    private var frequencyAxisValues: [Double] {
        if isLogarithmic {
            return AxisTickGenerator.generateTicks(min: Double(minFreq), max: Double(maxFreq), maxTicks: 8, scale: AxisScale.logarithmic())
        } else {
            return AxisTickGenerator.generateTicks(min: Double(minFreq), max: Double(maxFreq), maxTicks: 8, scale: AxisScale.linear)
        }
//        if isLogarithmic {
//            // Use standard logarithmic frequency markers for audio
//            let range = log10(Double(maxFreq)) - log10(Double(minFreq))
//            if range > 3 {
//                // Full range: use major frequency milestones
//                return [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]
//            } else if range > 2 {
//                // Medium zoom: use moderate spacing
//                return stride(from: Int(minFreq), through: Int(maxFreq), by: max(100, Int(minFreq / 5))).map { Double($0) }
//            } else {
//                // High zoom: use fine spacing
//                return stride(from: Int(minFreq), through: Int(maxFreq), by: max(50, Int(minFreq / 10))).map { Double($0) }
//            }
//        } else {
//            // Linear scale: use even spacing based on range
//            let range = Int(maxFreq - minFreq)
//            let step: Int
//            if range > 10000 {
//                step = 2000
//            } else if range > 5000 {
//                step = 1000
//            } else if range > 2000 {
//                step = 500
//            } else if range > 1000 {
//                step = 200
//            } else {
//                step = 100
//            }
//            return stride(from: Int(minFreq), through: Int(maxFreq), by: step).map { Double($0) }
//        }
    }

    // MARK: - Chart Content Builders
    
    /// Spectrum line chart content
    @ChartContentBuilder
    private var spectrumLineContent: some ChartContent {
        ForEach(chartData) { dataPoint in
            // Clamp the magnitude to the currently displayed min and max DB values
            let clampedMagnitude = max(minDB, min(maxDB, dataPoint.magnitude))
            
            // Line mark shows the precise spectrum shape
            LineMark(
                x: .value("Frequency", dataPoint.frequency),
                y: .value("Magnitude", clampedMagnitude)
            )
            .foregroundStyle(.red)
            .lineStyle(StrokeStyle(lineWidth: 1))
        }
    }
    
    /// Mode boundary markers chart content
    @ChartContentBuilder
    private var modeBoundaryContent: some ChartContent {
        if showModeBoundaries {
            ForEach(visibleModeBoundaries, id: \.frequency) { boundary in
                RuleMark(x: .value("Boundary", boundary.frequency))
                    .foregroundStyle(modeColor(for: boundary.mode).opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    .annotation(position: .top, alignment: .center) {
                        // Only show mode name at start of range (lower boundary)
                        if isStartOfModeRange(boundary.frequency, for: boundary.mode) {
                            Text(modeAbbreviation(for: boundary.mode))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(modeColor(for: boundary.mode))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(modeColor(for: boundary.mode).opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
            }
        }
    }
    
    /// Peak annotations chart content
    @ChartContentBuilder
    private var peakAnnotationContent: some ChartContent {
        ForEach(visiblePeaks) { peak in
            // Peak marker
            PointMark(
                x: .value("Frequency", peak.frequency),
                y: .value("Magnitude", peak.magnitude)
            )
            .foregroundStyle(modeColor(for: GuitarMode.classify(frequency: peak.frequency)))
            .symbolSize(100)
            
            // Static annotation (for positioning reference only)
            PointMark(
                x: .value("Frequency", peak.frequency),
                y: .value("Magnitude", peak.magnitude)
            )
            .foregroundStyle(.clear)
            .annotation(position: .top, alignment: .center, spacing: 4) {
                // Non-interactive placeholder
                Color.clear
                    .frame(width: 80, height: 60)
                    .id("placeholder-\(peak.id)")
            }
        }
    }
    
    /// Threshold lines chart content (for tap detection visualization)
    @ChartContentBuilder
    private var thresholdLinesContent: some ChartContent {
        if let thresholds = thresholdLines {
            ForEach(Array(thresholds.enumerated()), id: \.offset) { index, threshold in
                // Only show threshold if it's within the visible dB range
                if threshold.value >= minDB && threshold.value <= maxDB {
                    RuleMark(y: .value("Threshold", threshold.value))
                        .foregroundStyle(threshold.color)
                        .lineStyle(StrokeStyle(lineWidth: threshold.lineWidth, dash: threshold.dash))
                        .annotation(
                            position: index == 0 ? .top : .bottom,
                            alignment: index == 0 ? .trailing : .leading
                        ) {
                            Text(threshold.label)
                                .font(.caption2)
                                .fontWeight(index == 0 ? .medium : .regular)
                                .foregroundColor(threshold.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.9))
                                .cornerRadius(4)
                        }
                }
            }
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("FFT Peaks")
                    .font(.headline)
                
                Spacer()
                
                #if os(macOS)
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .help("""
                    Zoom & Pan Controls:
                    • Scroll: Pan view
                    • ⌘ + Scroll: Zoom both axes
                    • ⌃ + Scroll: Zoom both axes
                    • ⌥ + Scroll: Zoom frequency (horizontal)
                    • ⇧ + Scroll: Zoom magnitude (vertical)
                    • Pinch: Zoom (trackpad)
                    • Drag: Pan view
                    • Right-click: Reset axes
                    """)
                #endif
            }
            .padding(.bottom, 8)
            
            chartView
        }
    }
    
    /// The main chart view with all configurations applied
    private var chartView: some View {
        baseChart
            .chartXAxis { xAxisContent }
            .chartXAxisLabel(alignment: .center) {
                Text("Frequency (Hz)")
                    .padding(4)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button(action: resetFrequencyAxis) {
                            Label("Reset Frequency Axis", systemImage: "arrow.counterclockwise")
                        }
                    }
            }
            .chartYAxis { yAxisContent }
            .chartYAxisLabel(position: .leading, alignment: .center) {
                Text("FFT Magnitude (dB)")
                    .rotationEffect(.degrees(180))
                    .padding(4)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button(action: resetMagnitudeAxis) {
                            Label("Reset Magnitude Axis", systemImage: "arrow.counterclockwise")
                        }
                    }
            }
            // Only allow chart gestures when not dragging annotations
            .simultaneousGesture(isAnnotationDragging ? nil : zoomGesture)
            .simultaneousGesture(isAnnotationDragging ? nil : panGesture)
    }
    
    /// Helper to create GeometryReader wrapper for annotations
    @ViewBuilder
    private func annotationGeometryWrapper(proxy: ChartProxy) -> some View {
        if annotationOffsets != nil, let plotAnchor = proxy.plotFrame {
            GeometryReader { geometry in
                let resolvedPlotFrame = geometry[plotAnchor]
                PeakAnnotationsOverlay(
                    peaks: visiblePeaks,
                    annotationOffsets: annotationOffsets!,
                    geometry: geometry,
                    plotFrame: resolvedPlotFrame,
                    minFreq: minFreq,
                    maxFreq: maxFreq,
                    minDB: minDB,
                    maxDB: maxDB,
                    isLogarithmic: isLogarithmic,
                    isAnnotationDragging: $isAnnotationDragging
                )
            }
        }
    }
    
    /// The base chart with plot style and scales
    private var baseChart: some View {
        Chart {
            spectrumLineContent
            modeBoundaryContent
            peakAnnotationContent
            thresholdLinesContent
        }
        .chartPlotStyle { plotArea in
            plotArea
                .border(Color.gray, width: 1)
                .contentShape(Rectangle())
                .contextMenu {
                    Button(action: resetBothAxes) {
                        Label("Reset Both Axes", systemImage: "arrow.counterclockwise")
                    }
                    
                    Divider()
                    
                    Button(action: resetFrequencyAxis) {
                        Label("Reset Frequency Axis", systemImage: "arrow.clockwise")
                    }
                    
                    Button(action: resetMagnitudeAxis) {
                        Label("Reset Magnitude Axis", systemImage: "arrow.up.and.down")
                    }
                }
        }
        .chartOverlay { proxy in
            annotationGeometryWrapper(proxy: proxy)
        }
        .chartXScale(domain: Double(minFreq)...Double(maxFreq), type: isLogarithmic ? .log : .linear)
        .chartYScale(domain: Double(minDB)...Double(maxDB))
        #if os(macOS)
        .onScrollWheel { event in
            handleScrollWheel(event: event)
        }
        #endif
    }
    
    /// X-axis content builder
    @AxisContentBuilder
    private var xAxisContent: some AxisContent {
        AxisMarks(values: frequencyAxisValues) { value in
            AxisValueLabel {
                if let doubleValue = value.as(Double.self) {
                    Text(AxisTickGenerator.formatTickLabel(doubleValue))
                }
            }
            AxisGridLine()
        }
    }
    
    /// Y-axis content builder
    @AxisContentBuilder
    private var yAxisContent: some AxisContent {
        AxisMarks(position: .leading, values: .stride(by: 20)) { value in
            AxisValueLabel()
            AxisGridLine()
        }
    }
    
    /// Pinch gesture for zooming
    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($magnificationScale) { value, state, _ in
                state = value
            }
            .onEnded { scale in
                handleZoom(scale: scale)
            }
    }
    
    /// Drag gesture for panning
    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                handlePan(translation: value.translation)
                dragOffset = .zero
            }
    }
    
    // MARK: - Helper Functions
    
    /// Resets both frequency and magnitude axes to their default values
    private func resetBothAxes() {
        withAnimation(.easeInOut(duration: 0.3)) {
            minFreq = SpectrumDisplaySettings.minFrequency
            maxFreq = SpectrumDisplaySettings.maxFrequency
            minDB = SpectrumDisplaySettings.minMagnitude
            maxDB = SpectrumDisplaySettings.maxMagnitude
        }
        onFrequencyRangeChanged?()
    }
    
    /// Resets the frequency axis to its default range
    private func resetFrequencyAxis() {
        withAnimation(.easeInOut(duration: 0.3)) {
            minFreq = SpectrumDisplaySettings.minFrequency
            maxFreq = SpectrumDisplaySettings.maxFrequency
        }
        onFrequencyRangeChanged?()
    }
    
    /// Resets the magnitude axis to its default range
    private func resetMagnitudeAxis() {
        withAnimation(.easeInOut(duration: 0.3)) {
            minDB = SpectrumDisplaySettings.minMagnitude
            maxDB = SpectrumDisplaySettings.maxMagnitude
        }
    }
    
    /// Returns the color associated with a guitar mode
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
    
    /// Returns abbreviated mode name for boundary labels
    private func modeAbbreviation(for mode: GuitarMode) -> String {
        switch mode {
        case .helmholtz: return "HH"
        case .crossGrain: return "XG"
        case .longGrain: return "LG"
        case .monopole: return "MP"
        case .dipole: return "DP"
        case .ringMode: return "Ring"
        case .upperModes: return "Upper"
        case .unknown: return "?"
        }
    }
    
    /// Determines if this boundary frequency is the start (lower bound) of a mode range
    private func isStartOfModeRange(_ frequency: Float, for mode: GuitarMode) -> Bool {
        return abs(frequency - mode.idealRange.lowerBound) < 0.1
    }
    
    // MARK: - Gesture Handlers
    
    #if os(macOS)
    /// Handles scroll wheel events for zooming and panning on macOS
    ///
    /// - No modifiers: Pan view (scroll)
    /// - Command key: Zoom both axes
    /// - Option key: Zoom frequency axis only (horizontal)
    /// - Shift key: Zoom magnitude axis only (vertical)
    ///
    /// - Parameter event: The scroll wheel event from AppKit
    private func handleScrollWheel(event: NSEvent) {
        let scrollDeltaY = event.scrollingDeltaY
        let scrollDeltaX = event.scrollingDeltaX
        
        // Check modifiers - be explicit about checking individual flags
        let modifiers = event.modifierFlags
        let hasCommand = modifiers.contains(.command)
        let hasShift = modifiers.contains(.shift)
        let hasOption = modifiers.contains(.option)
        let hasControl = modifiers.contains(.control)
        
        // Debug: Print scroll deltas and modifiers
        #if DEBUG
        if hasCommand || hasShift || hasOption || hasControl {
            print("Scroll - deltaY: \(scrollDeltaY), deltaX: \(scrollDeltaX)")
            print("Modifiers - Command: \(hasCommand), Shift: \(hasShift), Option: \(hasOption), Control: \(hasControl)")
        }
        #endif
        
        // Skip very small deltas (noise from trackpad)
        guard abs(scrollDeltaY) > 0.1 || abs(scrollDeltaX) > 0.1 else { return }
        
        // When Shift is pressed, use whichever delta is larger for zooming
        // (Shift can sometimes convert vertical scroll to horizontal on some systems)
        let effectiveDelta = abs(scrollDeltaY) > abs(scrollDeltaX) ? scrollDeltaY : scrollDeltaX
        
        // Determine zoom factor from scroll delta (smaller changes for smoother zoom)
        let zoomSensitivity: CGFloat = 0.02
        let zoomFactor = 1.0 + (effectiveDelta * zoomSensitivity)
        
        // Check in order of priority
        if hasCommand && !hasShift && !hasOption {
            // Command (with or without Control): Zoom both axes
            #if DEBUG
            print("→ Zooming both axes")
            #endif
            withAnimation(.easeOut(duration: 0.1)) {
                handleZoom(scale: zoomFactor)
            }
        } else if hasShift && !hasCommand && !hasOption {
            // Shift (with or without Control): Zoom magnitude axis only
            #if DEBUG
            print("→ Zooming magnitude axis (zoom factor: \(zoomFactor))")
            #endif
            withAnimation(.easeOut(duration: 0.1)) {
                handleMagnitudeZoom(scale: zoomFactor)
            }
        } else if hasOption && !hasCommand && !hasShift {
            // Option (with or without Control): Zoom frequency axis only
            #if DEBUG
            print("→ Zooming frequency axis")
            #endif
            withAnimation(.easeOut(duration: 0.1)) {
                handleFrequencyZoom(scale: zoomFactor)
            }
        } else if hasControl && !hasCommand && !hasShift && !hasOption {
            // Control only: Also zoom both axes (alternative to Command)
            #if DEBUG
            print("→ Zooming both axes (Control)")
            #endif
            withAnimation(.easeOut(duration: 0.1)) {
                handleZoom(scale: zoomFactor)
            }
        } else if !hasCommand && !hasShift && !hasOption && !hasControl {
            // No modifiers: Pan the view
            let translation = CGSize(width: scrollDeltaX, height: scrollDeltaY)
            withAnimation(.easeOut(duration: 0.1)) {
                handlePan(translation: translation)
            }
        } else {
            #if DEBUG
            print("→ Ignoring modifier combination")
            #endif
        }
        // Ignore any combination of modifiers
    }
    
    /// Zooms only the frequency (X) axis
    private func handleFrequencyZoom(scale: CGFloat) {
        if isLogarithmic {
            let freqLogCenter = (log10(Double(maxFreq)) + log10(Double(minFreq))) / 2
            let freqLogRange = log10(Double(maxFreq)) - log10(Double(minFreq))
            let newFreqLogRange = freqLogRange / Double(scale)
            
            var newMinFreq = Float(pow(10, freqLogCenter - newFreqLogRange / 2))
            var newMaxFreq = Float(pow(10, freqLogCenter + newFreqLogRange / 2))
            
            newMinFreq = max(20, newMinFreq)
            newMaxFreq = min(20000, newMaxFreq)
            
            if newMaxFreq > newMinFreq * 1.1 {
                minFreq = newMinFreq
                maxFreq = newMaxFreq
                onFrequencyRangeChanged?()
            }
        } else {
            let freqCenter = (maxFreq + minFreq) / 2
            let freqRange = maxFreq - minFreq
            let newFreqRange = freqRange / Float(scale)
            
            var newMinFreq = freqCenter - newFreqRange / 2
            var newMaxFreq = freqCenter + newFreqRange / 2
            
            newMinFreq = max(20, newMinFreq)
            newMaxFreq = min(20000, newMaxFreq)
            
            if newMaxFreq > newMinFreq + 100 {
                minFreq = newMinFreq
                maxFreq = newMaxFreq
                onFrequencyRangeChanged?()
            }
        }
    }
    
    /// Zooms only the magnitude (Y) axis
    private func handleMagnitudeZoom(scale: CGFloat) {
        #if DEBUG
        print("  handleMagnitudeZoom called with scale: \(scale)")
        print("  Current dB range: \(minDB) to \(maxDB)")
        #endif
        
        let dbCenter = (maxDB + minDB) / 2
        let dbRange = maxDB - minDB
        let newDBRange = dbRange / Float(scale)
        
        var newMinDB = dbCenter - newDBRange / 2
        var newMaxDB = dbCenter + newDBRange / 2
        
        newMinDB = max(-120, newMinDB)
        newMaxDB = min(20, newMaxDB)
        
        #if DEBUG
        print("  Calculated new dB range: \(newMinDB) to \(newMaxDB)")
        print("  Condition check: \(newMaxDB) > \(newMinDB) + 10 = \(newMaxDB > newMinDB + 10)")
        #endif
        
        if newMaxDB > newMinDB + 10 {
            minDB = newMinDB
            maxDB = newMaxDB
            #if DEBUG
            print("  ✓ Updated dB range to: \(minDB) to \(maxDB)")
            #endif
        } else {
            #if DEBUG
            print("  ✗ Did not update (minimum range not met)")
            #endif
        }
    }
    #endif
    
    /// Handles pinch-to-zoom gestures on both frequency and dB axes.
    ///
    /// The zoom is centered on the midpoint of the current visible range.
    /// Different zoom algorithms are used for logarithmic vs. linear frequency scales.
    ///
    /// - Parameter scale: The magnification factor from the gesture (> 1 = zoom in, < 1 = zoom out)
    ///
    /// - Note: Zoom ranges are clamped to reasonable limits:
    ///   - Frequency: 20 Hz to 20 kHz with minimum visible range
    ///   - dB: -120 dB to +20 dB with minimum 10 dB range
    private func handleZoom(scale: CGFloat) {
        if isLogarithmic {
            // Zoom on frequency axis (logarithmic scale)
            // Work in log space for smooth zooming
            let freqLogCenter = (log10(Double(maxFreq)) + log10(Double(minFreq))) / 2
            let freqLogRange = log10(Double(maxFreq)) - log10(Double(minFreq))
            let newFreqLogRange = freqLogRange / Double(scale)
            
            var newMinFreq = Float(pow(10, freqLogCenter - newFreqLogRange / 2))
            var newMaxFreq = Float(pow(10, freqLogCenter + newFreqLogRange / 2))
            
            // Clamp frequency range to valid audio range
            newMinFreq = max(20, newMinFreq)
            newMaxFreq = min(20000, newMaxFreq)
            
            // Ensure minimum zoom (1.1x ratio between min and max)
            if newMaxFreq > newMinFreq * 1.1 {
                minFreq = newMinFreq
                maxFreq = newMaxFreq
                onFrequencyRangeChanged?()
            }
        } else {
            // Zoom on frequency axis (linear scale)
            let freqCenter = (maxFreq + minFreq) / 2
            let freqRange = maxFreq - minFreq
            let newFreqRange = freqRange / Float(scale)
            
            var newMinFreq = freqCenter - newFreqRange / 2
            var newMaxFreq = freqCenter + newFreqRange / 2
            
            // Clamp frequency range
            newMinFreq = max(20, newMinFreq)
            newMaxFreq = min(20000, newMaxFreq)
            
            // Ensure minimum zoom (100 Hz minimum visible range)
            if newMaxFreq > newMinFreq + 100 {
                minFreq = newMinFreq
                maxFreq = newMaxFreq
                onFrequencyRangeChanged?()
            }
        }
        
        // Zoom on dB axis (always linear)
        let dbCenter = (maxDB + minDB) / 2
        let dbRange = maxDB - minDB
        let newDBRange = dbRange / Float(scale)
        
        var newMinDB = dbCenter - newDBRange / 2
        var newMaxDB = dbCenter + newDBRange / 2
        
        // Clamp dB range to reasonable values
        newMinDB = max(-120, newMinDB)
        newMaxDB = min(20, newMaxDB)
        
        // Ensure minimum zoom (10 dB minimum visible range)
        if newMaxDB > newMinDB + 10 {
            minDB = newMinDB
            maxDB = newMaxDB
        }
    }
    
    /// Handles drag gestures for panning the view.
    ///
    /// Pan sensitivity is adjusted based on the current visible range.
    /// Different panning algorithms are used for logarithmic vs. linear frequency scales.
    ///
    /// - Parameter translation: The drag translation from the gesture
    ///
    /// - Note: Panning is constrained to keep the view within valid bounds
    private func handlePan(translation: CGSize) {
        if isLogarithmic {
            // Pan on frequency axis (logarithmic scale)
            // Work in log space for natural panning behavior
            let freqLogRange = log10(Double(maxFreq)) - log10(Double(minFreq))
            let freqPanFactor = Double(translation.width) / 400.0 // Adjust sensitivity
            let freqLogShift = freqLogRange * freqPanFactor
            
            var newMinFreq = Float(pow(10, log10(Double(minFreq)) - freqLogShift))
            var newMaxFreq = Float(pow(10, log10(Double(maxFreq)) - freqLogShift))
            
            // Clamp to boundaries and adjust both values to maintain range
            if newMinFreq < 20 {
                let shift = 20 - newMinFreq
                newMinFreq = 20
                newMaxFreq += shift
            }
            if newMaxFreq > 20000 {
                let shift = newMaxFreq - 20000
                newMaxFreq = 20000
                newMinFreq -= shift
            }
            
            minFreq = max(20, newMinFreq)
            maxFreq = min(20000, newMaxFreq)
            onFrequencyRangeChanged?()
        } else {
            // Pan on frequency axis (linear scale)
            let freqRange = maxFreq - minFreq
            let freqPanFactor = Float(translation.width) / 400.0 // Adjust sensitivity
            let freqShift = freqRange * freqPanFactor
            
            var newMinFreq = minFreq - freqShift
            var newMaxFreq = maxFreq - freqShift
            
            // Clamp to boundaries
            if newMinFreq < 20 {
                let shift = 20 - newMinFreq
                newMinFreq = 20
                newMaxFreq += shift
            }
            if newMaxFreq > 20000 {
                let shift = newMaxFreq - 20000
                newMaxFreq = 20000
                newMinFreq -= shift
            }
            
            minFreq = max(20, newMinFreq)
            maxFreq = min(20000, newMaxFreq)
            onFrequencyRangeChanged?()
        }
        
        // Pan on dB axis (always linear)
        let dbRange = maxDB - minDB
        let dbPanFactor = Float(translation.height) / 300.0 // Adjust sensitivity
        let dbShift = dbRange * dbPanFactor
        
        var newMinDB = minDB + dbShift
        var newMaxDB = maxDB + dbShift
        
        // Clamp to boundaries
        if newMinDB < -120 {
            let shift = -120 - newMinDB
            newMinDB = -120
            newMaxDB += shift
        }
        if newMaxDB > 20 {
            let shift = newMaxDB - 20
            newMaxDB = 20
            newMinDB -= shift
        }
        
        minDB = max(-120, newMinDB)
        maxDB = min(20, newMaxDB)
    }
}

// MARK: - Peak Annotations Overlay

/// A container view for all peak annotations
private struct PeakAnnotationsOverlay: View {
    let peaks: [ResonantPeak]
    let annotationOffsets: Binding<[UUID: CGPoint]>
    let geometry: GeometryProxy
    let plotFrame: CGRect
    let minFreq: Float
    let maxFreq: Float
    let minDB: Float
    let maxDB: Float
    let isLogarithmic: Bool
    @Binding var isAnnotationDragging: Bool
    
    var body: some View {
        ZStack {
            ForEach(peaks) { peak in
                DraggablePeakAnnotation(
                    peak: peak,
                    offset: annotationOffsets.wrappedValue[peak.id] ?? .zero,
                    chartGeometry: geometry,
                    plotFrame: plotFrame,
                    minFreq: minFreq,
                    maxFreq: maxFreq,
                    minDB: minDB,
                    maxDB: maxDB,
                    isLogarithmic: isLogarithmic,
                    isAnnotationDragging: $isAnnotationDragging,
                    onOffsetChange: { newOffset in
                        annotationOffsets.wrappedValue[peak.id] = newOffset
                    },
                    onReset: {
                        annotationOffsets.wrappedValue.removeValue(forKey: peak.id)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Draggable Peak Annotation

/// A draggable annotation view for peak labels that can be repositioned to prevent overlap
struct DraggablePeakAnnotation: View {
    let peak: ResonantPeak
    let offset: CGPoint
    let chartGeometry: GeometryProxy
    let plotFrame: CGRect
    let minFreq: Float
    let maxFreq: Float
    let minDB: Float
    let maxDB: Float
    let isLogarithmic: Bool
    @Binding var isAnnotationDragging: Bool
    let onOffsetChange: (CGPoint) -> Void
    let onReset: () -> Void
    
    @State private var dragOffset: CGSize = .zero
    @State private var isHovering: Bool = false
    @State private var isDragging: Bool = false
    
    // Cache computed positions to reduce calculation overhead
    @State private var cachedChartPosition: CGPoint = .zero
    @State private var cachedPeakPosition: CGPoint = .zero
    
    private var modeColor: Color {
        let mode = GuitarMode.classify(frequency: peak.frequency)
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
    
    /// Whether the annotation has been moved from its default position
    private var isMoved: Bool {
        offset.x != 0 || offset.y != 0
    }
    
    /// Calculate position in chart coordinates
    private func calculateChartPosition() -> CGPoint {
        // Use the plot frame dimensions for accurate positioning
        let chartWidth = plotFrame.width
        let chartHeight = plotFrame.height
        
        // Calculate X position (frequency)
        let freqRange = maxFreq - minFreq
        let freqNormalized: CGFloat
        if isLogarithmic {
            let logMin = log10(Double(minFreq))
            let logMax = log10(Double(maxFreq))
            let logFreq = log10(Double(peak.frequency))
            freqNormalized = CGFloat((logFreq - logMin) / (logMax - logMin))
        } else {
            freqNormalized = CGFloat((peak.frequency - minFreq) / freqRange)
        }
        let x = plotFrame.minX + freqNormalized * chartWidth
        
        // Calculate Y position (magnitude) - inverted because chart Y goes down
        let dbRange = maxDB - minDB
        let dbNormalized = CGFloat((peak.magnitude - minDB) / dbRange)
        let y = plotFrame.minY + (1.0 - dbNormalized) * chartHeight
        
        return CGPoint(x: x, y: y - 70) // Offset up by 70 to place above peak
    }
    
    /// Position of the actual peak marker (without the label offset)
    private func calculatePeakPosition() -> CGPoint {
        // Use the plot frame dimensions for accurate positioning
        let chartWidth = plotFrame.width
        let chartHeight = plotFrame.height
        
        // Calculate X position (frequency)
        let freqRange = maxFreq - minFreq
        let freqNormalized: CGFloat
        if isLogarithmic {
            let logMin = log10(Double(minFreq))
            let logMax = log10(Double(maxFreq))
            let logFreq = log10(Double(peak.frequency))
            freqNormalized = CGFloat((logFreq - logMin) / (logMax - logMin))
        } else {
            freqNormalized = CGFloat((peak.frequency - minFreq) / freqRange)
        }
        let x = plotFrame.minX + freqNormalized * chartWidth
        
        // Calculate Y position (magnitude) - inverted because chart Y goes down
        let dbRange = maxDB - minDB
        let dbNormalized = CGFloat((peak.magnitude - minDB) / dbRange)
        let y = plotFrame.minY + (1.0 - dbNormalized) * chartHeight
        
        return CGPoint(x: x, y: y) // No offset - this is the actual peak position
    }
    
    /// Final position including user offset and drag
    private var finalPosition: CGPoint {
        CGPoint(
            x: cachedChartPosition.x + offset.x + dragOffset.width,
            y: cachedChartPosition.y + offset.y + dragOffset.height
        )
    }
    
    var body: some View {
        // Separate the connection line and label into distinct layers
        ZStack(alignment: .topLeading) {
            // Connection line layer - always show when we have valid positions
            if cachedPeakPosition != .zero && cachedChartPosition != .zero {
                ConnectionLine(
                    from: cachedPeakPosition,
                    to: CGPoint(
                        x: cachedChartPosition.x + offset.x + dragOffset.width,
                        y: cachedChartPosition.y + offset.y + dragOffset.height + 30
                    ),
                    color: modeColor
                )
            }
            
            // The annotation content - positioned independently
            PeakAnnotationLabel(
                peak: peak,
                modeColor: modeColor,
                isHovering: isHovering,
                isDragging: isDragging,
                isMoved: isMoved
            )
            .position(finalPosition)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            isAnnotationDragging = true
                            // Cache positions at start of drag
                            cachedChartPosition = calculateChartPosition()
                            cachedPeakPosition = calculatePeakPosition()
                        }
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        let newOffset = CGPoint(
                            x: offset.x + value.translation.width,
                            y: offset.y + value.translation.height
                        )
                        // Disable animation for smoother dragging
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            onOffsetChange(newOffset)
                            isDragging = false
                            isAnnotationDragging = false
                        }
                        dragOffset = .zero
                        // Update cache after drag completes
                        cachedChartPosition = calculateChartPosition()
                        cachedPeakPosition = calculatePeakPosition()
                    }
            )
            .onHover { hovering in
                withAnimation(.none) {
                    isHovering = hovering
                }
            }
            #if os(macOS)
            .cursor(NSCursor.openHand)
            #endif
            .contextMenu {
                Button(action: onReset) {
                    Label("Reset Position", systemImage: "arrow.counterclockwise")
                }
                .disabled(!isMoved)
            }
            #if os(macOS)
            .help(isMoved ? "Drag to adjust • Right-click to reset position" : "Drag to reposition label")
            #endif
        }
        .onAppear {
            // Initialize cached positions immediately on appear
            cachedChartPosition = calculateChartPosition()
            cachedPeakPosition = calculatePeakPosition()
        }
        .task {
            // Also calculate on initial render to ensure we have positions ASAP
            if cachedChartPosition == .zero {
                cachedChartPosition = calculateChartPosition()
                cachedPeakPosition = calculatePeakPosition()
            }
        }
        .onChange(of: minFreq) { _, _ in
            if !isDragging {
                Task { @MainActor in
                    cachedChartPosition = calculateChartPosition()
                    cachedPeakPosition = calculatePeakPosition()
                }
            }
        }
        .onChange(of: maxFreq) { _, _ in
            if !isDragging {
                Task { @MainActor in
                    cachedChartPosition = calculateChartPosition()
                    cachedPeakPosition = calculatePeakPosition()
                }
            }
        }
        .onChange(of: minDB) { _, _ in
            if !isDragging {
                Task { @MainActor in
                    cachedChartPosition = calculateChartPosition()
                    cachedPeakPosition = calculatePeakPosition()
                }
            }
        }
        .onChange(of: maxDB) { _, _ in
            if !isDragging {
                Task { @MainActor in
                    cachedChartPosition = calculateChartPosition()
                    cachedPeakPosition = calculatePeakPosition()
                }
            }
        }
        .onChange(of: isLogarithmic) { _, _ in
            if !isDragging {
                Task { @MainActor in
                    cachedChartPosition = calculateChartPosition()
                    cachedPeakPosition = calculatePeakPosition()
                }
            }
        }
    }
}

// MARK: - Connection Line

/// A simple view that draws a connection line between two points
private struct ConnectionLine: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color
    
    var body: some View {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
    }
}

// MARK: - Peak Annotation Label

/// The visual label component for a peak annotation
private struct PeakAnnotationLabel: View {
    let peak: ResonantPeak
    let modeColor: Color
    let isHovering: Bool
    let isDragging: Bool
    let isMoved: Bool
    
    var body: some View {
        VStack(spacing: 2) {
            // Drag handle indicator
//            if isHovering || isMoved || isDragging {
//                HStack(spacing: 2) {
//                    Image(systemName: isDragging ? "hand.point.up.left.fill" : "hand.point.up.left")
//                        .font(.system(size: 8))
//                        .foregroundColor(modeColor.opacity(0.6))
//                    
//                    if isMoved && !isDragging {
//                        Image(systemName: "arrow.uturn.backward.circle.fill")
//                            .font(.system(size: 8))
//                            .foregroundColor(.secondary)
//                            #if os(macOS)
//                            .help("Right-click to reset")
//                            #endif
//                    }
//                }
//            }
            
            Text(GuitarMode.classify(frequency: peak.frequency).rawValue)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(modeColor)
            
            // Pitch information if available
            if let pitchNote = peak.pitchNote, let pitchCents = peak.pitchCents {
                HStack(spacing: 2) {
                    Image(systemName: "music.note")
                        .font(.system(size: 8))
                        .foregroundColor(.purple)
                    Text(pitchNote)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.purple)
                }
                
                let sign = pitchCents >= 0 ? "+" : ""
                Text("\(sign)\(Int(round(pitchCents))) ¢")
                    .font(.caption2)
                    .foregroundColor(.purple.opacity(0.8))
            }
            
            Text("\(peak.frequency, specifier: "%.1f") Hz")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text("\(peak.magnitude, specifier: "%.1f") dB")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(white: 0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(modeColor, lineWidth: isDragging ? 2.5 : (isHovering ? 2 : 1.5))
        )
        .shadow(color: .black.opacity(0.15), radius: 4)
        .contentShape(Rectangle())
    }
}

// MARK: - macOS Scroll Wheel Support

#if os(macOS)
/// A view modifier that captures scroll wheel events on macOS
private struct ScrollWheelModifier: ViewModifier {
    let onScrollWheel: (NSEvent) -> Void
    
    func body(content: Content) -> some View {
        content.overlay(
            ScrollWheelView(onScrollWheel: onScrollWheel)
        )
    }
}

/// A representable view that captures scroll wheel events
private struct ScrollWheelView: NSViewRepresentable {
    let onScrollWheel: (NSEvent) -> Void
    
    func makeNSView(context: Context) -> NSScrollWheelHostView {
        let view = NSScrollWheelHostView()
        view.onScrollWheel = onScrollWheel
        return view
    }
    
    func updateNSView(_ nsView: NSScrollWheelHostView, context: Context) {
        nsView.onScrollWheel = onScrollWheel
    }
}

/// Custom NSView that captures scroll wheel events
private class NSScrollWheelHostView: NSView {
    var onScrollWheel: ((NSEvent) -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func scrollWheel(with event: NSEvent) {
        // Handle scroll wheel events
        onScrollWheel?(event)
        // Don't call super - we consume the event
    }
    
    override var acceptsFirstResponder: Bool { 
        return true 
    }
    
    // Return self only when point is in bounds to receive scroll events
    // But we won't handle any other mouse events
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Check subviews first - they get priority
        for subview in subviews.reversed() {
            let convertedPoint = subview.convert(point, from: self)
            if let hitView = subview.hitTest(convertedPoint) {
                return hitView
            }
        }
        
        // Return self to receive scroll events
        if bounds.contains(point) {
            return self
        }
        
        return nil
    }
    
    // Don't override any mouse event methods - let them fall through
    // SwiftUI will handle them through its own mechanisms
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        // Remove existing tracking areas
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        
        // Add tracking area to receive scroll events
        let options: NSTrackingArea.Options = [
            .activeAlways,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
    
    override var frame: NSRect {
        didSet {
            updateTrackingAreas()
        }
    }
}

extension View {
    /// Adds scroll wheel event handling on macOS
    fileprivate func onScrollWheel(_ handler: @escaping (NSEvent) -> Void) -> some View {
        self.modifier(ScrollWheelModifier(onScrollWheel: handler))
    }
}
#endif

// MARK: - Preview

#Preview {
    @Previewable @State var minFreq: Float = 75
    @Previewable @State var maxFreq: Float = 350
    @Previewable @State var minDB: Float = -100
    @Previewable @State var maxDB: Float = 0
    @Previewable @State var isLogarithmic = false
    @Previewable @State var annotationOffsets: [UUID: CGPoint] = [:]
    
    let sampleFrequencies = stride(from: Float(20), through: Float(20000), by: Float(10)).map { $0 }
    let sampleMagnitudes = sampleFrequencies.map { freq in
        // Simulate a spectrum with peaks at 100 Hz, 440 Hz, and 1000 Hz
        let peak1 = -20.0 * abs(freq - 100) / 100
        let peak2 = -15.0 * abs(freq - 440) / 100
        let peak3 = -25.0 * abs(freq - 1000) / 200
        return max(peak1, peak2, peak3, -80)
    }
    
    // Sample peaks for annotation
    let samplePeaks = [
        ResonantPeak(frequency: 100, magnitude: -20, quality: 15, bandwidth: 6.7),
        ResonantPeak(frequency: 200, magnitude: -35, quality: 12, bandwidth: 16.7),
        ResonantPeak(frequency: 240, magnitude: -40, quality: 10, bandwidth: 24)
    ]
    
    return SpectrumView(
        frequencies: sampleFrequencies,
        magnitudes: sampleMagnitudes,
        minFreq: $minFreq,
        maxFreq: $maxFreq,
        minDB: $minDB,
        maxDB: $maxDB,
        isLogarithmic: $isLogarithmic,
        peaks: samplePeaks,
        showModeBoundaries: true,
        annotationOffsets: $annotationOffsets
    )
    .frame(height: 300)
    .padding()
}
