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
    
    /// Optional per-phase spectra to overlay (material/brace measurements: L, C, FLC)
    /// Each entry has its own colour and label for the legend
    var materialSpectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)] = []
    
    /// Optional threshold lines to display (for tap detection visualization)
    var thresholdLines: [(value: Float, label: String, color: Color, lineWidth: CGFloat, dash: [CGFloat])]?
    
    /// Optional callback to reset all peak annotation label positions
    var onResetLabels: (() -> Void)?
    
    /// Whether there are annotation offsets that need resetting (controls enabled state of menu item)
    var hasLabelsToReset: Bool = false
    
    /// The current measurement type (guitar vs material) - affects which annotations are shown
    var measurementType: MeasurementType = .acoustic
    
    /// ID of the peak selected as longitudinal mode (for material measurements)
    var selectedLongitudinalPeakID: UUID?
    
    /// ID of the peak selected as cross-grain mode (for material measurements)
    var selectedCrossPeakID: UUID?
    
    /// ID of the peak selected as FLC (diagonal/shear) mode (for material measurements)
    var selectedFlcPeakID: UUID?
    
    // MARK: - Gesture State
    
    /// Tracks drag offset during pan gestures
    @State private var dragOffset: CGSize = .zero
    
    /// Tracks magnification scale during pinch gestures
    @GestureState private var magnificationScale: CGFloat = 1.0
    
    /// Tracks whether an annotation is currently being dragged
    @State private var isAnnotationDragging: Bool = false
    
    #if os(macOS)
    /// Current cursor position in data coordinates (frequency Hz, magnitude dB), nil when not hovering
    @State private var cursorPosition: (frequency: Double, magnitude: Double)? = nil
    
    /// Whether the cursor readout is currently visible
    @State private var isCursorVisible: Bool = false
    
    /// Whether the zoom/pan controls help popover is showing
    @State private var showingControlsHelp: Bool = false
    
    #else
    /// Whether the iOS axis-reset confirmation dialog is showing
    @State private var showingResetDialog: Bool = false
    
    /// Whether crosshair tracking mode is active (iOS only). Defaults to false when not provided.
    var crosshairMode: Binding<Bool> = .constant(false)
    
    /// Current crosshair position in data coordinates, nil when not active
    @State private var crosshairPosition: (frequency: Double, magnitude: Double)? = nil
    #endif
    
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
        let allModes: [GuitarMode] = [.air, .top, .back, .dipole, .ringMode, .upperModes]
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
    /// Optionally filters out unknown modes based on user setting (guitar mode only)
    private var visiblePeaks: [ResonantPeak] {
        let filtered = peaks?.filter { $0.frequency >= minFreq && $0.frequency <= maxFreq } ?? []
        
        // In material mode, show all peaks (no guitar mode filtering)
        if !measurementType.isGuitar {
            return filtered
        }
        
        // Filter out unknown modes if setting is disabled (guitar mode only)
        if TapDisplaySettings.showUnknownModes {
            return filtered
        } else {
            return filtered.filter { GuitarMode.classify(frequency: $0.frequency).normalized != .unknown }
        }
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
    
    /// Mode boundary markers chart content (guitar mode only)
    @ChartContentBuilder
    private var modeBoundaryContent: some ChartContent {
        // Only show guitar mode boundaries when in guitar measurement mode
        if showModeBoundaries && measurementType.isGuitar {
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
            // Peak marker - color depends on measurement type
            PointMark(
                x: .value("Frequency", peak.frequency),
                y: .value("Magnitude", peak.magnitude)
            )
            .foregroundStyle(peakColor(for: peak))
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
    
    /// Returns the appropriate color for a peak based on measurement type and selection
    private func peakColor(for peak: ResonantPeak) -> Color {
        if measurementType.isGuitar {
            // Guitar mode: color by guitar mode classification
            return modeColor(for: GuitarMode.classify(frequency: peak.frequency))
        } else {
            // Material mode: color by L/C selection
            if peak.id == selectedLongitudinalPeakID {
                return .blue      // Longitudinal = blue
            } else if peak.id == selectedCrossPeakID {
                return .orange    // Cross-grain = orange
            } else if peak.id == selectedFlcPeakID {
                return .purple    // FLC = purple
            } else {
                return .secondary // Unselected = gray
            }
        }
    }
    
    /// Per-phase spectrum overlay chart content (material/brace measurements)
    @ChartContentBuilder
    private var materialSpectraContent: some ChartContent {
        ForEach(Array(materialSpectra.enumerated()), id: \.offset) { seriesIndex, series in
            ForEach(
                zip(series.frequencies, series.magnitudes)
                    .filter { $0.0 >= minFreq && $0.0 <= maxFreq }
                    .map { SpectrumDataPoint(frequency: $0.0, magnitude: $0.1) }
            ) { dataPoint in
                let clampedMagnitude = max(minDB, min(maxDB, dataPoint.magnitude))
                LineMark(
                    x: .value("Frequency", dataPoint.frequency),
                    y: .value("Magnitude", clampedMagnitude)
                )
                .foregroundStyle(by: .value("Series", series.label))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
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
                            position: index == 1 ? .bottom : .top,
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
                Button {
                    showingControlsHelp.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                }
                .buttonStyle(.plain)
                .help("""
                    Zoom & Pan Controls:
                    • Scroll: Pan vertically (magnitude)
                    • ⇧ + Scroll: Pan horizontally (frequency)
                    • ⌘ + Scroll: Zoom both axes
                    • ⌥ + Scroll: Zoom frequency (horizontal)
                    • ⌃ + Scroll: Zoom magnitude (vertical)
                    • Pinch: Zoom (trackpad)
                    • Drag: Pan view (both axes)
                    • Right-click: Reset axes
                    """)
                .popover(isPresented: $showingControlsHelp, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Zoom & Pan Controls")
                            .font(.headline)
                            .padding(.bottom, 2)
                        Group {
                            Text("Scroll") + Text(": Pan vertically (magnitude)").foregroundColor(.secondary)
                            Text("⇧ + Scroll") + Text(": Pan horizontally (frequency)").foregroundColor(.secondary)
                            Text("⌘ + Scroll") + Text(": Zoom both axes").foregroundColor(.secondary)
                            Text("⌥ + Scroll") + Text(": Zoom frequency (horizontal)").foregroundColor(.secondary)
                            Text("⌃ + Scroll") + Text(": Zoom magnitude (vertical)").foregroundColor(.secondary)
                            Text("Pinch") + Text(": Zoom (trackpad)").foregroundColor(.secondary)
                            Text("Drag") + Text(": Pan view (both axes)").foregroundColor(.secondary)
                            Text("Right-click") + Text(": Reset axes").foregroundColor(.secondary)
                        }
                        .font(.callout)
                    }
                    .padding()
                    .frame(minWidth: 280)
                }
                #endif
            }
            .padding(.bottom, 8)
            
            ZStack(alignment: .topTrailing) {
                chartView
                materialSpectraLegend
                    .padding(.top, 8)
                    .padding(.trailing, 12)
            }
        }
    }
    
    /// Legend overlay for per-phase material spectra
    @ViewBuilder
    private var materialSpectraLegend: some View {
        if !materialSpectra.isEmpty {
            HStack(spacing: 12) {
                ForEach(Array(materialSpectra.enumerated()), id: \.offset) { _, series in
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(series.color)
                            .frame(width: 16, height: 2)
                        Text(series.label)
                            .font(.caption2)
                            .foregroundColor(series.color)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
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
            // Only allow chart gestures when not dragging annotations and not in crosshair mode
            #if os(macOS)
            .simultaneousGesture(isAnnotationDragging ? nil : zoomGesture)
            .simultaneousGesture(isAnnotationDragging ? nil : panGesture)
            #else
            .simultaneousGesture(isAnnotationDragging || crosshairMode.wrappedValue ? nil : zoomGesture)
            .simultaneousGesture(isAnnotationDragging || crosshairMode.wrappedValue ? nil : panGesture)
            #endif
            #if !os(macOS)
            .highPriorityGesture(TapGesture(count: 2).onEnded {
                showingResetDialog = true
            })
            .confirmationDialog("Reset Axes", isPresented: $showingResetDialog) {
                Button("Reset Both Axes") { resetBothAxes() }
                Button("Reset Frequency Axis") { resetFrequencyAxis() }
                Button("Reset Magnitude Axis") { resetMagnitudeAxis() }
                if let onResetLabels = onResetLabels {
                    Button("Reset Labels", action: onResetLabels)
                        .disabled(!hasLabelsToReset)
                }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: crosshairMode.wrappedValue) { _, newValue in
                if !newValue { crosshairPosition = nil }
            }
            #endif
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
                    isAnnotationDragging: $isAnnotationDragging,
                    measurementType: measurementType,
                    selectedLongitudinalPeakID: selectedLongitudinalPeakID,
                    selectedCrossPeakID: selectedCrossPeakID,
                    selectedFlcPeakID: selectedFlcPeakID
                )
            }
        }
    }
    
    #if os(macOS)
    /// Overlay that tracks mouse position and displays frequency+dB readout (macOS only)
    @ViewBuilder
    private func cursorOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            let plotFrame = proxy.plotFrame.map { geometry[$0] } ?? .zero
            
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: plotFrame.width, height: plotFrame.height)
                    .offset(x: plotFrame.minX, y: plotFrame.minY)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard plotFrame.contains(location) else {
                                isCursorVisible = false
                                cursorPosition = nil
                                break
                            }
                            let plotLocal = CGPoint(
                                x: location.x - plotFrame.minX,
                                y: location.y - plotFrame.minY
                            )
                            if let freq = proxy.value(atX: plotLocal.x, as: Double.self),
                               let db = proxy.value(atY: plotLocal.y, as: Double.self) {
                                cursorPosition = (frequency: freq, magnitude: db)
                                isCursorVisible = true
                            }
                        case .ended:
                            isCursorVisible = false
                            cursorPosition = nil
                        }
                    }
                    // Context menu on the overlay rectangle so right-click isn't silently consumed
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
                        if let onResetLabels = onResetLabels {
                            Divider()
                            Button(action: onResetLabels) {
                                Label("Reset Labels", systemImage: "arrow.uturn.backward")
                            }
                            .disabled(!hasLabelsToReset)
                        }
                    }
                
                if isCursorVisible, let pos = cursorPosition {
                    cursorReadout(pos: pos, plotFrame: plotFrame, proxy: proxy)
                }
            }
        }
    }
    
    /// Formats a frequency value for the cursor readout
    private func formatCursorFrequency(_ hz: Double) -> String {
        if hz >= 1000 {
            return String(format: "%.2f kHz", hz / 1000)
        } else {
            return String(format: "%.1f Hz", hz)
        }
    }
    
    /// Cursor readout label + crosshair lines showing frequency and dB values at the current position
    @ViewBuilder
    private func cursorReadout(pos: (frequency: Double, magnitude: Double), plotFrame: CGRect, proxy: ChartProxy) -> some View {
        let labelWidth: CGFloat = 130
        let labelHeight: CGFloat = 40
        let margin: CGFloat = 8
        
        let cursorX = plotFrame.minX + (proxy.position(forX: pos.frequency) ?? 0)
        let cursorY = plotFrame.minY + (proxy.position(forY: pos.magnitude) ?? 0)
        
        // Vertical crosshair line
        Path { path in
            path.move(to: CGPoint(x: cursorX, y: plotFrame.minY))
            path.addLine(to: CGPoint(x: cursorX, y: plotFrame.maxY))
        }
        .stroke(Color.primary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        .allowsHitTesting(false)
        
        // Horizontal crosshair line
        Path { path in
            path.move(to: CGPoint(x: plotFrame.minX, y: cursorY))
            path.addLine(to: CGPoint(x: plotFrame.maxX, y: cursorY))
        }
        .stroke(Color.primary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        .allowsHitTesting(false)
        
        let labelX: CGFloat = {
            let right = cursorX + margin
            if right + labelWidth > plotFrame.maxX {
                return cursorX - labelWidth - margin
            }
            return right
        }()
        
        let labelY: CGFloat = {
            let above = cursorY - labelHeight - margin
            if above < plotFrame.minY {
                return cursorY + margin
            }
            return above
        }()
        
        VStack(alignment: .leading, spacing: 2) {
            Text(formatCursorFrequency(pos.frequency))
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Text(String(format: "%.1f dB", pos.magnitude))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 2)
        .frame(width: labelWidth, height: labelHeight)
        .offset(x: labelX, y: labelY)
        .allowsHitTesting(false)
    }
    #endif
    
    #if !os(macOS)
    /// Overlay that tracks finger drag and displays frequency+dB crosshair readout (iOS only, active when crosshairMode is on)
    @ViewBuilder
    private func crosshairOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            let plotFrame = proxy.plotFrame.map { geometry[$0] } ?? .zero
            
            ZStack(alignment: .topLeading) {
                // Invisible hit-testing rect covering the plot area
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: plotFrame.width, height: plotFrame.height)
                    .offset(x: plotFrame.minX, y: plotFrame.minY)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard crosshairMode.wrappedValue else { return }
                                let plotLocal = CGPoint(
                                    x: value.location.x - plotFrame.minX,
                                    y: value.location.y - plotFrame.minY
                                )
                                guard plotFrame.contains(value.location) else { return }
                                if let freq = proxy.value(atX: plotLocal.x, as: Double.self),
                                   let db = proxy.value(atY: plotLocal.y, as: Double.self) {
                                    crosshairPosition = (frequency: freq, magnitude: db)
                                }
                            }
                            .onEnded { _ in
                                if !crosshairMode.wrappedValue {
                                    crosshairPosition = nil
                                }
                            }
                    )
                
                if crosshairMode.wrappedValue, let pos = crosshairPosition {
                    crosshairReadout(pos: pos, plotFrame: plotFrame, proxy: proxy)
                }
            }
        }
    }
    
    /// Formats a frequency value for the crosshair readout
    private func formatCrosshairFrequency(_ hz: Double) -> String {
        if hz >= 1000 {
            return String(format: "%.2f kHz", hz / 1000)
        } else {
            return String(format: "%.1f Hz", hz)
        }
    }
    
    /// Crosshair readout label + crosshair lines showing frequency and dB at the tracked position
    @ViewBuilder
    private func crosshairReadout(pos: (frequency: Double, magnitude: Double), plotFrame: CGRect, proxy: ChartProxy) -> some View {
        let labelWidth: CGFloat = 130
        let labelHeight: CGFloat = 40
        let margin: CGFloat = 8
        
        let cursorX = (proxy.position(forX: pos.frequency) ?? 0) + plotFrame.minX
        let cursorY = (proxy.position(forY: pos.magnitude) ?? 0) + plotFrame.minY
        
        // Vertical crosshair line
        Path { path in
            path.move(to: CGPoint(x: cursorX, y: plotFrame.minY))
            path.addLine(to: CGPoint(x: cursorX, y: plotFrame.maxY))
        }
        .stroke(Color.primary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        .allowsHitTesting(false)
        
        // Horizontal crosshair line
        Path { path in
            path.move(to: CGPoint(x: plotFrame.minX, y: cursorY))
            path.addLine(to: CGPoint(x: plotFrame.maxX, y: cursorY))
        }
        .stroke(Color.primary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        .allowsHitTesting(false)
        
        // Readout label — positioned to stay inside the plot
        let labelX: CGFloat = {
            let right = cursorX + margin
            if right + labelWidth > plotFrame.maxX {
                return cursorX - labelWidth - margin
            }
            return right
        }()
        
        let labelY: CGFloat = {
            let above = cursorY - labelHeight - margin
            if above < plotFrame.minY {
                return cursorY + margin
            }
            return above
        }()
        
        VStack(alignment: .leading, spacing: 2) {
            Text(formatCrosshairFrequency(pos.frequency))
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Text(String(format: "%.1f dB", pos.magnitude))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 2)
        .frame(width: labelWidth, height: labelHeight)
        .offset(x: labelX, y: labelY)
        .allowsHitTesting(false)
    }
    #endif
    
    /// The base chart with plot style and scales
    private var baseChart: some View {
        Chart {
            // Show per-phase spectra overlay when available, otherwise show the single spectrum
            if !materialSpectra.isEmpty {
                materialSpectraContent
            } else {
                spectrumLineContent
            }
            modeBoundaryContent
            peakAnnotationContent
            thresholdLinesContent
        }
        .chartForegroundStyleScale(
            domain: materialSpectra.map { $0.label },
            range: materialSpectra.map { $0.color }
        )
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea
                .border(Color.gray, width: 1)
                .contentShape(Rectangle())
                #if os(macOS)
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
                    
                    if let onResetLabels = onResetLabels {
                        Divider()
                        
                        Button(action: onResetLabels) {
                            Label("Reset Labels", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(!hasLabelsToReset)
                    }
                }
                #endif
        }
        .chartOverlay { proxy in
            annotationGeometryWrapper(proxy: proxy)
        }
        #if os(macOS)
        .chartOverlay { proxy in
            cursorOverlay(proxy: proxy)
        }
        #else
        .chartOverlay { proxy in
            crosshairOverlay(proxy: proxy)
        }
        #endif
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
        minFreq = TapDisplaySettings.minFrequency
        maxFreq = TapDisplaySettings.maxFrequency
        minDB = TapDisplaySettings.minMagnitude
        maxDB = TapDisplaySettings.maxMagnitude
        onFrequencyRangeChanged?()
    }
    
    /// Resets the frequency axis to its default range
    private func resetFrequencyAxis() {
        minFreq = TapDisplaySettings.minFrequency
        maxFreq = TapDisplaySettings.maxFrequency
        onFrequencyRangeChanged?()
    }
    
    /// Resets the magnitude axis to its default range
    private func resetMagnitudeAxis() {
        minDB = TapDisplaySettings.minMagnitude
        maxDB = TapDisplaySettings.maxMagnitude
    }
    
    /// Returns the color associated with a guitar mode
    private func modeColor(for mode: GuitarMode) -> Color {
        switch mode.normalized {
        case .air: return .cyan
        case .top: return .green
        case .back: return .orange
        case .dipole: return .red
        case .ringMode: return .purple
        case .upperModes: return .gray
        case .unknown: return .secondary
        default: return .secondary
        }
    }
    
    /// Returns abbreviated mode name for boundary labels
    private func modeAbbreviation(for mode: GuitarMode) -> String {
        switch mode.normalized {
        case .air: return "Air"
        case .top: return "Top"
        case .back: return "Back"
        case .dipole: return "DP"
        case .ringMode: return "Ring"
        case .upperModes: return "Upper"
        case .unknown: return "?"
        default: return "?"
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
    /// - No modifiers: Pan view vertically (magnitude axis)
    /// - Shift key: Pan view horizontally (frequency axis)
    /// - Command key: Zoom both axes
    /// - Option key: Zoom frequency axis only (horizontal)
    /// - Control key: Zoom magnitude axis only (vertical)
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
        
        // When Control is pressed, use whichever delta is larger for zooming
        // (Some systems may convert scroll directions with modifiers)
        let effectiveDelta = abs(scrollDeltaY) > abs(scrollDeltaX) ? scrollDeltaY : scrollDeltaX
        
        // Determine zoom factor from scroll delta (smaller changes for smoother zoom)
        let zoomSensitivity: CGFloat = 0.02
        let zoomFactor = 1.0 + (effectiveDelta * zoomSensitivity)
        
        // Check in order of priority
        if hasCommand && !hasShift && !hasOption && !hasControl {
            // Command only: Zoom both axes
            #if DEBUG
            print("→ Zooming both axes")
            #endif
            withAnimation(.easeOut(duration: 0.1)) {
                handleZoom(scale: zoomFactor)
            }
        } else if hasControl && !hasCommand && !hasOption && !hasShift {
            // Control only: Zoom magnitude axis only
            #if DEBUG
            print("→ Zooming magnitude axis (zoom factor: \(zoomFactor))")
            #endif
            withAnimation(.easeOut(duration: 0.1)) {
                handleMagnitudeZoom(scale: zoomFactor)
            }
        } else if hasOption && !hasCommand && !hasShift && !hasControl {
            // Option only: Zoom frequency axis only
            #if DEBUG
            print("→ Zooming frequency axis")
            #endif
            withAnimation(.easeOut(duration: 0.1)) {
                handleFrequencyZoom(scale: zoomFactor)
            }
        } else if hasShift && !hasCommand && !hasOption && !hasControl {
            // Shift only: Pan horizontally (frequency axis)
            // Shift often converts vertical scroll to horizontal, so check both deltas
            #if DEBUG
            print("→ Panning horizontally")
            #endif
            let effectiveScroll = abs(scrollDeltaX) > abs(scrollDeltaY) ? scrollDeltaX : scrollDeltaY
            let translation = CGSize(width: effectiveScroll, height: 0)
            withAnimation(.easeOut(duration: 0.1)) {
                handlePan(translation: translation)
            }
        } else if !hasCommand && !hasShift && !hasOption && !hasControl {
            // No modifiers: Pan vertically (magnitude axis)
            #if DEBUG
            print("→ Panning vertically")
            #endif
            let translation = CGSize(width: 0, height: scrollDeltaY)  // Pan only vertically
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
    
    // Material measurement mode support
    let measurementType: MeasurementType
    let selectedLongitudinalPeakID: UUID?
    let selectedCrossPeakID: UUID?
    let selectedFlcPeakID: UUID?
    
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
                    measurementType: measurementType,
                    selectedLongitudinalPeakID: selectedLongitudinalPeakID,
                    selectedCrossPeakID: selectedCrossPeakID,
                    selectedFlcPeakID: selectedFlcPeakID,
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
    
    // Material measurement mode support
    let measurementType: MeasurementType
    let selectedLongitudinalPeakID: UUID?
    let selectedCrossPeakID: UUID?
    let selectedFlcPeakID: UUID?
    
    let onOffsetChange: (CGPoint) -> Void
    let onReset: () -> Void
    
    @State private var dragOffset: CGSize = .zero
    @State private var isHovering: Bool = false
    @State private var isDragging: Bool = false
    
    // Cache computed positions to reduce calculation overhead
    @State private var cachedChartPosition: CGPoint = .zero
    @State private var cachedPeakPosition: CGPoint = .zero
    
    private var modeColor: Color {
        if measurementType.isGuitar {
            // Guitar mode: color by guitar mode classification
            let mode = GuitarMode.classify(frequency: peak.frequency).normalized
            switch mode {
            case .air: return .cyan
            case .top: return .green
            case .back: return .orange
            case .dipole: return .red
            case .ringMode: return .purple
            case .upperModes: return .gray
            case .unknown: return .secondary
            default: return .secondary
            }
        } else {
            // Material mode: color by L/C selection
            if peak.id == selectedLongitudinalPeakID {
                return .blue      // Longitudinal = blue
            } else if peak.id == selectedCrossPeakID {
                return .orange    // Cross-grain = orange
            } else if peak.id == selectedFlcPeakID {
                return .purple    // FLC = purple
            } else {
                return .secondary // Unselected = gray
            }
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
        guard chartWidth > 0, chartHeight > 0 else { return .zero }
        
        // Calculate X position (frequency)
        let freqRange = maxFreq - minFreq
        let freqNormalized: CGFloat
        if isLogarithmic {
            let logMin = log10(Double(minFreq))
            let logMax = log10(Double(maxFreq))
            let logRange = logMax - logMin
            guard logRange > 0, minFreq > 0, maxFreq > 0 else { return .zero }
            let logFreq = log10(Double(peak.frequency))
            freqNormalized = CGFloat((logFreq - logMin) / logRange)
        } else {
            guard freqRange > 0 else { return .zero }
            freqNormalized = CGFloat((peak.frequency - minFreq) / freqRange)
        }
        let x = plotFrame.minX + freqNormalized * chartWidth
        
        // Calculate Y position (magnitude)
        let dbRange = maxDB - minDB
        guard dbRange > 0 else { return .zero }
        let clampedMag = max(minDB, min(maxDB, peak.magnitude))
        let dbNormalized = CGFloat((clampedMag - minDB) / dbRange)
        let y = plotFrame.minY + (1.0 - dbNormalized) * chartHeight
        
        return CGPoint(x: x, y: y - 70) // Offset up by 70 to place above peak
    }
    
    /// Position of the actual peak marker (without the label offset)
    private func calculatePeakPosition() -> CGPoint {
        let chartWidth = plotFrame.width
        let chartHeight = plotFrame.height
        guard chartWidth > 0, chartHeight > 0 else { return .zero }
        
        // Calculate X position (frequency)
        let freqRange = maxFreq - minFreq
        let freqNormalized: CGFloat
        if isLogarithmic {
            let logMin = log10(Double(minFreq))
            let logMax = log10(Double(maxFreq))
            let logRange = logMax - logMin
            guard logRange > 0, minFreq > 0, maxFreq > 0 else { return .zero }
            let logFreq = log10(Double(peak.frequency))
            freqNormalized = CGFloat((logFreq - logMin) / logRange)
        } else {
            guard freqRange > 0 else { return .zero }
            freqNormalized = CGFloat((peak.frequency - minFreq) / freqRange)
        }
        let x = plotFrame.minX + freqNormalized * chartWidth
        
        // Calculate Y position (magnitude)
        let dbRange = maxDB - minDB
        guard dbRange > 0 else { return .zero }
        let clampedMag = max(minDB, min(maxDB, peak.magnitude))
        let dbNormalized = CGFloat((clampedMag - minDB) / dbRange)
        let y = plotFrame.minY + (1.0 - dbNormalized) * chartHeight
        
        return CGPoint(x: x, y: y)
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
            if cachedPeakPosition.x.isFinite && cachedPeakPosition.y.isFinite &&
               cachedChartPosition.x.isFinite && cachedChartPosition.y.isFinite &&
               cachedChartPosition != .zero {
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
                isMoved: isMoved,
                measurementType: measurementType,
                isLongitudinal: peak.id == selectedLongitudinalPeakID,
                isCross: peak.id == selectedCrossPeakID,
                isFlc: peak.id == selectedFlcPeakID
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
        .onChange(of: plotFrame) { _, _ in
            // Update cached positions when the chart geometry changes (e.g., during device rotation)
            if !isDragging {
                Task { @MainActor in
                    cachedChartPosition = calculateChartPosition()
                    cachedPeakPosition = calculatePeakPosition()
                }
            }
        }
        .onChange(of: peak.id) { _, _ in
            // Update cached positions when the peak itself changes (e.g., after a new measurement)
            if !isDragging {
                cachedChartPosition = calculateChartPosition()
                cachedPeakPosition = calculatePeakPosition()
            }
        }
        .onChange(of: peak.magnitude) { _, _ in
            // Update Y position when peak magnitude changes
            if !isDragging {
                cachedChartPosition = calculateChartPosition()
                cachedPeakPosition = calculatePeakPosition()
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
        if from.x.isFinite && from.y.isFinite && to.x.isFinite && to.y.isFinite {
            Path { path in
                path.move(to: from)
                path.addLine(to: to)
            }
            .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
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
    
    // Material measurement mode support
    let measurementType: MeasurementType
    let isLongitudinal: Bool
    let isCross: Bool
    var isFlc: Bool = false
    
    /// The mode label to display - guitar mode name or material mode (L/C/FLC)
    private var modeLabel: String {
        if measurementType.isGuitar {
            return GuitarMode.classify(frequency: peak.frequency).displayName
        } else {
            // Material mode labels
            if isLongitudinal {
                return "Longitudinal"
            } else if isCross {
                return "Cross-grain"
            } else if isFlc {
                return "FLC"
            } else {
                return "Peak"  // Unselected peak
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 2) {
            // Mode label (guitar mode or material L/C)
            Text(modeLabel)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(modeColor)
            
            // Pitch information if available (only show for guitar mode)
            if measurementType.isGuitar, let pitchNote = peak.pitchNote, let pitchCents = peak.pitchCents {
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
            
            Text(peak.frequency.formattedAsFrequency())
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
/// A view modifier that captures scroll wheel events using event monitoring
private struct ScrollWheelModifier: ViewModifier {
    let onScrollWheel: (NSEvent) -> Void
    
    func body(content: Content) -> some View {
        content.background(
            ScrollWheelMonitorView(onScrollWheel: onScrollWheel)
        )
    }
}

/// NSView that uses local event monitoring to capture scroll wheel events
private struct ScrollWheelMonitorView: NSViewRepresentable {
    let onScrollWheel: (NSEvent) -> Void
    
    func makeNSView(context: Context) -> ScrollWheelHostView {
        let view = ScrollWheelHostView()
        view.scrollHandler = onScrollWheel
        return view
    }
    
    func updateNSView(_ nsView: ScrollWheelHostView, context: Context) {
        nsView.scrollHandler = onScrollWheel
    }
}

/// Host view that monitors scroll events when mouse is within its bounds
private class ScrollWheelHostView: NSView {
    var scrollHandler: ((NSEvent) -> Void)?
    private var eventMonitor: Any?
    private var isMouseInside = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupEventMonitor()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupEventMonitor() {
        // Monitor scroll wheel events at the application level
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, self.isMouseInside else {
                return event  // Pass through if mouse not in our view
            }
            
            // Check if the event's window is our window
            guard event.window == self.window else {
                return event
            }
            
            // Handle the scroll event
            self.scrollHandler?(event)
            
            // Return nil to prevent further propagation (consume the event)
            return nil
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        // Remove old tracking areas
        trackingAreas.forEach { removeTrackingArea($0) }
        
        // Add new tracking area
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
    }
    
    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
    }
    
    // Return nil to be transparent to hit testing (allows SwiftUI gestures to work)
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
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
// MARK: - Connection Line Shape for Export

/// A simple Shape that draws a line between two points
/// Used in ExportableSpectrumChart where Path views don't render correctly in ZStack
private struct ConnectionLineShape: Shape {
    let from: CGPoint
    let to: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

// MARK: - Static Export Spectrum View

/// A simplified, static version of SpectrumView designed for ImageRenderer export.
/// This view removes all interactive elements (gestures, hover effects, context menus)
/// that can cause ImageRenderer to fail.
struct ExportableSpectrumChart: View {
    let frequencies: [Float]
    let magnitudes: [Float]
    let minFreq: Float
    let maxFreq: Float
    let minDB: Float
    let maxDB: Float
    let isLogarithmic: Bool
    var peaks: [ResonantPeak]?
    var showModeBoundaries: Bool = true
    var annotationOffsets: [UUID: CGPoint] = [:]
    var showUnknownModes: Bool? = nil  // If nil, uses global setting
    
    // Material measurement mode support
    var measurementType: MeasurementType = .acoustic
    var selectedLongitudinalPeakID: UUID?
    var selectedCrossPeakID: UUID?
    var selectedFlcPeakID: UUID?
    
    /// Per-phase spectra overlay for material/brace measurements
    var materialSpectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)] = []
    
    private var chartData: [SpectrumDataPoint] {
        zip(frequencies, magnitudes)
            .filter { $0.0 >= minFreq && $0.0 <= maxFreq }
            .map { SpectrumDataPoint(frequency: $0.0, magnitude: $0.1) }
    }
    
    private var visibleModeBoundaries: [(frequency: Float, mode: GuitarMode)] {
        // Don't show guitar mode boundaries when in material mode
        guard measurementType.isGuitar else { return [] }
        
        let allModes: [GuitarMode] = [.air, .top, .back, .dipole, .ringMode, .upperModes]
        var boundaries: [(Float, GuitarMode)] = []
        
        for mode in allModes {
            let range = mode.idealRange
            if range.lowerBound >= minFreq && range.lowerBound <= maxFreq {
                boundaries.append((range.lowerBound, mode))
            }
            if range.upperBound >= minFreq && range.upperBound <= maxFreq {
                boundaries.append((range.upperBound, mode))
            }
        }
        
        return boundaries
    }
    
    private var visiblePeaks: [ResonantPeak] {
        let filtered = peaks?.filter { $0.frequency >= minFreq && $0.frequency <= maxFreq } ?? []
        
        // In material mode, show all peaks (no guitar mode filtering)
        if !measurementType.isGuitar {
            return filtered
        }
        
        // Use explicit parameter if provided, otherwise fall back to global setting
        let shouldShowUnknown = showUnknownModes ?? TapDisplaySettings.showUnknownModes
        if shouldShowUnknown {
            return filtered
        } else {
            return filtered.filter { GuitarMode.classify(frequency: $0.frequency).normalized != .unknown }
        }
    }
    
    private var frequencyAxisValues: [Double] {
        if isLogarithmic {
            return AxisTickGenerator.generateTicks(min: Double(minFreq), max: Double(maxFreq), maxTicks: 8, scale: AxisScale.logarithmic())
        } else {
            return AxisTickGenerator.generateTicks(min: Double(minFreq), max: Double(maxFreq), maxTicks: 8, scale: AxisScale.linear)
        }
    }
    
    private func modeColor(for mode: GuitarMode) -> Color {
        switch mode.normalized {
        case .air: return .cyan
        case .top: return .green
        case .back: return .orange
        case .dipole: return .red
        case .ringMode: return .purple
        case .upperModes: return .gray
        case .unknown: return .secondary
        default: return .secondary
        }
    }
    
    /// Returns the appropriate color for a peak based on measurement type and selection
    private func peakColor(for peak: ResonantPeak) -> Color {
        if measurementType.isGuitar {
            return modeColor(for: GuitarMode.classify(frequency: peak.frequency))
        } else {
            // Material mode: color by L/C/FLC selection
            if peak.id == selectedLongitudinalPeakID {
                return .blue
            } else if peak.id == selectedCrossPeakID {
                return .orange
            } else if peak.id == selectedFlcPeakID {
                return .purple
            } else {
                return .secondary
            }
        }
    }
    
    /// Returns the mode label for a peak based on measurement type
    private func peakModeLabel(for peak: ResonantPeak) -> String {
        if measurementType.isGuitar {
            return GuitarMode.classify(frequency: peak.frequency).displayName
        } else {
            if peak.id == selectedLongitudinalPeakID {
                return "Longitudinal"
            } else if peak.id == selectedCrossPeakID {
                return "Cross-grain"
            } else if peak.id == selectedFlcPeakID {
                return "FLC"
            } else {
                return "Peak"
            }
        }
    }
    
    private func modeAbbreviation(for mode: GuitarMode) -> String {
        switch mode.normalized {
        case .air: return "Air"
        case .top: return "Top"
        case .back: return "Back"
        case .dipole: return "DP"
        case .ringMode: return "Ring"
        case .upperModes: return "Upper"
        case .unknown: return "?"
        default: return "?"
        }
    }
    
    private func isStartOfModeRange(_ frequency: Float, for mode: GuitarMode) -> Bool {
        return abs(frequency - mode.idealRange.lowerBound) < 0.1
    }
    
    /// Build filtered chart data for a single material spectrum series
    private func seriesData(frequencies: [Float], magnitudes: [Float]) -> [SpectrumDataPoint] {
        zip(frequencies, magnitudes)
            .filter { $0.0 >= minFreq && $0.0 <= maxFreq }
            .map { SpectrumDataPoint(frequency: $0.0, magnitude: $0.1) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("FFT Peaks")
                    .font(.system(size: 24, weight: .semibold))
                Spacer()
            }
            .padding(.bottom, 16)
            
            ZStack(alignment: .topLeading) {
                // The chart
                Chart {
                    // Per-phase spectra overlay (material/brace) or single spectrum (guitar)
                    if !materialSpectra.isEmpty {
                        ForEach(Array(materialSpectra.enumerated()), id: \.offset) { index, series in
                            let data = seriesData(frequencies: series.frequencies, magnitudes: series.magnitudes)
                            ForEach(data) { dataPoint in
                                let clamped = max(minDB, min(maxDB, dataPoint.magnitude))
                                LineMark(
                                    x: .value("Frequency", dataPoint.frequency),
                                    y: .value("Magnitude", clamped)
                                )
                                .foregroundStyle(by: .value("Series", series.label))
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            }
                        }
                    } else {
                        // Spectrum line
                        ForEach(chartData) { dataPoint in
                            let clampedMagnitude = max(minDB, min(maxDB, dataPoint.magnitude))
                            LineMark(
                                x: .value("Frequency", dataPoint.frequency),
                                y: .value("Magnitude", clampedMagnitude)
                            )
                            .foregroundStyle(.red)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                    
                    // Mode boundaries
                    if showModeBoundaries {
                        ForEach(visibleModeBoundaries, id: \.frequency) { boundary in
                            RuleMark(x: .value("Boundary", boundary.frequency))
                                .foregroundStyle(modeColor(for: boundary.mode).opacity(0.3))
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [8, 8]))
                                .annotation(position: .top, alignment: .center) {
                                    if isStartOfModeRange(boundary.frequency, for: boundary.mode) {
                                        Text(modeAbbreviation(for: boundary.mode))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(modeColor(for: boundary.mode))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(modeColor(for: boundary.mode).opacity(0.15))
                                            .cornerRadius(6)
                                    }
                                }
                        }
                    }
                    
                    // Peak markers only (no inline annotations)
                    ForEach(visiblePeaks) { peak in
                        PointMark(
                            x: .value("Frequency", peak.frequency),
                            y: .value("Magnitude", peak.magnitude)
                        )
                        .foregroundStyle(peakColor(for: peak))
                        .symbolSize(200)
                    }
                }
                .chartForegroundStyleScale(
                    domain: materialSpectra.map { $0.label },
                    range: materialSpectra.map { $0.color }
                )
                .chartLegend(.hidden)
                .chartPlotStyle { plotArea in
                    plotArea.border(Color.gray, width: 1)
                }
                .chartXScale(domain: Double(minFreq)...Double(maxFreq), type: isLogarithmic ? .log : .linear)
                .chartYScale(domain: Double(minDB)...Double(maxDB))
                .chartXAxis {
                    AxisMarks(values: frequencyAxisValues) { value in
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(AxisTickGenerator.formatTickLabel(doubleValue))
                                    .font(.system(size: 12))
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartXAxisLabel(alignment: .center) {
                    Text("Frequency (Hz)")
                        .font(.system(size: 16, weight: .medium))
                        .padding(8)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .stride(by: 20)) { _ in
                        AxisValueLabel()
                            .font(.system(size: 12))
                        AxisGridLine()
                    }
                }
                .chartYAxisLabel(position: .leading, alignment: .center) {
                    Text("FFT Magnitude (dB)")
                        .font(.system(size: 16, weight: .medium))
                        .rotationEffect(.degrees(180))
                        .padding(8)
                }
                .chartOverlay { proxy in
                    // Use ChartProxy for accurate positioning
                    GeometryReader { geometry in
                        if let plotFrame = proxy.plotFrame {
                            let frame = geometry[plotFrame]
                            
                            // Connection lines layer
                            ForEach(visiblePeaks) { peak in
                                if let peakX = proxy.position(forX: peak.frequency),
                                   let peakY = proxy.position(forY: Double(peak.magnitude)) {
                                    let peakPosition = CGPoint(
                                        x: frame.minX + peakX,
                                        y: frame.minY + peakY
                                    )
                                    let offset = annotationOffsets[peak.id] ?? .zero
                                    let annotationX = peakPosition.x + offset.x
                                    let annotationY = peakPosition.y - 70 + offset.y
                                    
                                    ConnectionLineShape(
                                        from: CGPoint(x: annotationX, y: annotationY + 50),
                                        to: peakPosition
                                    )
                                    .stroke(peakColor(for: peak).opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                                }
                            }
                            
                            // Annotations layer
                            ForEach(visiblePeaks) { peak in
                                if let peakX = proxy.position(forX: peak.frequency),
                                   let peakY = proxy.position(forY: Double(peak.magnitude)) {
                                    let peakPosition = CGPoint(
                                        x: frame.minX + peakX,
                                        y: frame.minY + peakY
                                    )
                                    let offset = annotationOffsets[peak.id] ?? .zero
                                    let annotationX = peakPosition.x + offset.x
                                    let annotationY = peakPosition.y - 70 + offset.y
                                    
                                    VStack(spacing: 6) {
                                        Text(peakModeLabel(for: peak))
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(peakColor(for: peak))
                                        
                                        // Only show pitch info for guitar mode
                                        if measurementType.isGuitar, let pitchNote = peak.pitchNote {
                                            HStack(spacing: 4) {
                                                Image(systemName: "music.note")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.purple)
                                                Text(pitchNote)
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundColor(.purple)
                                            }
                                        }
                                        
                                        Text(peak.frequency.formattedAsFrequency())
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.primary)
                                        
                                        Text("\(peak.magnitude, specifier: "%.1f") dB")
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(10)
                                    .background(Color.white.opacity(0.95))
                                    .cornerRadius(10)
                                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                                    .position(x: annotationX, y: annotationY)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

