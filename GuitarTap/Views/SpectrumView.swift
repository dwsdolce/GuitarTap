/// # SpectrumView
///
/// An interactive frequency-spectrum chart built on Swift Charts.
///
/// `SpectrumView` is the central visualization component of GuitarTap.  It
/// renders an FFT magnitude spectrum, overlaid with peak annotations, guitar
/// mode boundary markers, material-analysis phase spectra, and tap-detection
/// threshold lines.
///
/// ## Extensions
///
/// | File | Contents |
/// |------|----------|
/// | `SpectrumView+ChartContent.swift` | `@ChartContentBuilder` properties for each visual layer |
/// | `SpectrumView+GestureHandlers.swift` | Zoom, pan, and scroll-wheel handlers |
/// | `SpectrumView+SnapInterpolation.swift` | Binary-search snap + gravity-based curve locking |
/// | `SpectrumScrollWheel.swift` | AppKit scroll wheel event bridge (macOS only) |
///
/// ## Interaction model
///
/// | Gesture / Input               | Platform | Action |
/// |-------------------------------|----------|--------|
/// | Pinch over plot               | Both     | Zoom both axes, anchored to gesture start point |
/// | Pinch over frequency axis     | Both     | Zoom frequency axis only |
/// | Pinch over magnitude axis     | Both     | Zoom magnitude axis only |
/// | Drag over plot                | Both     | Pan both axes |
/// | Drag over frequency axis      | macOS    | Pan frequency axis only |
/// | Drag over magnitude axis      | macOS    | Pan magnitude axis only |
/// | Scroll wheel over plot        | macOS    | Zoom both axes around cursor |
/// | Scroll wheel over freq axis   | macOS    | Zoom frequency axis around cursor |
/// | Scroll wheel over mag axis    | macOS    | Zoom magnitude axis around cursor |
/// | Scroll + Shift                | macOS    | Pan frequency axis |
/// | Scroll + Option               | macOS    | Pan magnitude axis |
/// | Scroll + Command              | macOS    | Zoom both axes around cursor |
/// | Scroll + Control              | macOS    | Zoom both axes around cursor |
/// | Hover                         | macOS    | Show snap-to-waveform cursor readout |
/// | Long press / tap              | iOS      | Show crosshair readout |
///
/// ## Axis ranges
///
/// Both axes are expressed as `@Binding<Float>` so parent views can persist the
/// visible range across taps.  The legal ranges are:
/// - Frequency: 20 Hz – 20 kHz
/// - Magnitude: −120 dB – +20 dB
///
/// - SeeAlso: `TapToneAnalysisView`, `PeakAnnotations`, `AxisTickGenerator`
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

/// A single frequency-domain data point for chart rendering.
///
/// Each `SpectrumDataPoint` corresponds to one FFT bin.  The `Identifiable`
/// conformance lets SwiftUI Charts efficiently track insertions and removals
/// when the spectrum is refreshed.
struct SpectrumDataPoint: Identifiable {
    /// Unique identifier for SwiftUI's identity system
    let id = UUID()

    /// The frequency of this bin in Hz
    let frequency: Float

    /// The magnitude at this frequency in dB (typically -100 to 0 dB)
    let magnitude: Float
}

// MARK: - Cursor Snap State

/// The result of snapping the cursor or crosshair to the nearest waveform point.
///
/// `CursorSnapState` is computed in `SpectrumView+SnapInterpolation` and stored
/// in `@State` by `SpectrumView` so the cursor overlay can read the snapped
/// coordinates without re-running the interpolation on every render pass.
struct CursorSnapState {
    /// Interpolated frequency at the snapped position, in Hz.
    let frequency: Double
    /// Interpolated magnitude at the snapped position, in dB.
    let magnitude: Double
    /// Index into `materialSpectra` identifying the locked curve, or `nil`
    /// when tracking the primary (single) spectrum.
    let seriesIndex: Int?
    /// Display color matching the tracked curve; used to tint the readout label
    /// so it visually corresponds to the waveform being tracked.
    let curveColor: Color
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

    /// Optional per-phase spectra to overlay (plate/brace measurements: L, C, FLC)
    /// Each entry has its own colour and label for the legend
    var materialSpectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)] = []

    /// Optional threshold lines to display (for tap detection visualization)
    var thresholdLines: [(value: Float, label: String, color: Color, lineWidth: CGFloat, dash: [CGFloat])]?

    /// Optional callback to reset all peak annotation label positions
    var onResetLabels: (() -> Void)?

    /// Whether there are annotation offsets that need resetting (controls enabled state of menu item)
    var hasLabelsToReset: Bool = false

    /// When true the cursor/crosshair snaps to the nearest waveform point instead of floating freely.
    /// Should be set to true when the spectrum is frozen (post-tap capture).
    var isSpectrumFrozen: Bool = false

    /// Color of the primary (single) spectrum line. Used to tint the cursor readout label
    /// so it matches the waveform. Only relevant when `materialSpectra` is empty.
    var primaryCurveColor: Color = .red

    /// The current measurement type (guitar vs plate/brace) - affects which annotations are shown
    var measurementType: MeasurementType = .acoustic

    /// ID of the peak selected as longitudinal mode (for plate/brace measurements)
    var selectedLongitudinalPeakID: UUID?

    /// ID of the peak selected as cross-grain mode (for plate measurements)
    var selectedCrossPeakID: UUID?

    /// ID of the peak selected as FLC (diagonal/shear) mode (for plate measurements)
    var selectedFlcPeakID: UUID?

    /// Per-peak user mode overrides — passed through to annotation labels (guitar mode only)
    var modeOverrides: [UUID: UserAssignedMode] = [:]

    // MARK: - Gesture State

    /// Tracks drag offset during pan gestures (for live preview only)
    @State private var dragOffset: CGSize = .zero

    /// Tracks the previous frame's drag translation so incremental deltas can be computed
    @State private var lastDragTranslation: CGSize = .zero

    /// Tracks the previous frame's pinch scale so incremental deltas can be computed
    @State private var lastMagnificationScale: CGFloat = 1.0

    /// Tracks whether an annotation is currently being dragged
    @State private var isAnnotationDragging: Bool = false

    /// The most-recently resolved chart plot frame, stored so the pinch zoom gesture can convert
    /// its UnitPoint anchor to data coordinates without needing a ChartProxy reference.
    @State var lastPlotFrame: CGRect = .zero

    /// Index of the waveform series the cursor is currently locked to.
    /// -1 = primary spectrum, 0+ = index into materialSpectra. Reset to -1 on cursor exit/drag end.
    @State private var lockedSeriesIndex: Int = -1

    /// Which chart region the drag started in. Captured on the first drag `.onChanged` event
    /// and held for the duration of the gesture so the axis constraint doesn't change mid-drag.
    /// Used on both macOS and iOS.
    @State private var dragRegion: PointerRegion = .plot

    #if os(macOS)
    /// Snapped cursor position in data coordinates, including series identity. Nil when not hovering.
    @State private var cursorSnapState: CursorSnapState? = nil

    /// Whether the cursor readout is currently visible
    @State private var isCursorVisible: Bool = false

    /// Whether the zoom/pan controls help popover is showing
    @State private var showingControlsHelp: Bool = false

    /// Raw screen-local position of the mouse within the chart overlay, updated on every hover tick.
    /// Used by the scroll-wheel zoom handler to zoom around the cursor rather than the range midpoint.
    @State var lastCursorPosition: CGPoint? = nil

    /// Which chart region the pointer is currently over. Updated on every hover tick.
    /// Used by the scroll-wheel handler to decide which axis to operate on.
    @State private var currentPointerRegion: PointerRegion = .outside

    #else
    /// Whether the iOS chart options sheet is showing
    @State private var showingChartOptions: Bool = false

    /// Whether crosshair tracking mode is active (iOS only). Defaults to false when not provided.
    var crosshairMode: Binding<Bool> = .constant(false)

    /// Snapped crosshair position in data coordinates, including series identity. Nil when not active.
    @State private var crosshairSnapState: CursorSnapState? = nil
    #endif

    // MARK: - Computed Properties

    /// Filters and converts the frequency/magnitude arrays into chart data points.
    ///
    /// Only includes data points within the current visible frequency range.
    /// This improves rendering performance for large FFT sizes.
    var chartData: [SpectrumDataPoint] {
        zip(frequencies, magnitudes)
            .filter { $0.0 >= minFreq && $0.0 <= maxFreq }
            .map { SpectrumDataPoint(frequency: $0.0, magnitude: $0.1) }
    }

    /// Returns the mode boundaries that are visible in the current frequency range
    var visibleModeBoundaries: [(frequency: Float, mode: GuitarMode)] {
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
    var visiblePeaks: [ResonantPeak] {
        let filtered = peaks?.filter { $0.frequency >= minFreq && $0.frequency <= maxFreq } ?? []

        // In plate/brace mode, show all peaks (no guitar mode filtering)
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
        let lo = Double(minFreq)
        let hi = Double(maxFreq)
        let scale: AxisScale = isLogarithmic ? AxisScale.logarithmic() : .linear
        // Filter to the visible domain so ticks produced by the "nice number" rounding
        // that fall outside [minFreq, maxFreq] (e.g. a 0 Hz tick when minFreq is 20)
        // are not passed to AxisMarks, which would place them in the axis-label gutter.
        return AxisTickGenerator.generateTicks(min: lo, max: hi, maxTicks: 8, scale: scale)
            .filter { $0 >= lo && $0 <= hi }
    }

    /// Labels for frequency axis ticks, with precision automatically increased
    /// when the default formatting would produce duplicate labels.
    private var frequencyAxisLabels: [Double: String] {
        AxisTickGenerator.formatTickLabels(frequencyAxisValues)
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
                    • Scroll over plot: Zoom both axes around cursor
                    • Scroll over frequency axis: Zoom frequency only
                    • Scroll over magnitude axis: Zoom magnitude only
                    • ⇧ + Scroll: Pan frequency axis
                    • ⌥ + Scroll: Pan magnitude axis
                    • ⌘/⌃ + Scroll: Zoom both axes
                    • Pinch over plot: Zoom both axes (trackpad)
                    • Pinch over frequency axis: Zoom frequency only
                    • Pinch over magnitude axis: Zoom magnitude only
                    • Drag over plot: Pan both axes
                    • Drag over frequency axis: Pan frequency only
                    • Drag over magnitude axis: Pan magnitude only
                    • Right-click: Reset axes & labels
                    """)
                .popover(isPresented: $showingControlsHelp, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Zoom & Pan Controls")
                            .font(.headline)
                            .padding(.bottom, 2)
                        Group {
                            Text("Scroll over plot") + Text(": Zoom both axes around cursor").foregroundColor(.secondary)
                            Text("Scroll over freq axis") + Text(": Zoom frequency only").foregroundColor(.secondary)
                            Text("Scroll over mag axis") + Text(": Zoom magnitude only").foregroundColor(.secondary)
                            Text("⇧ + Scroll") + Text(": Pan frequency axis").foregroundColor(.secondary)
                            Text("⌥ + Scroll") + Text(": Pan magnitude axis").foregroundColor(.secondary)
                            Text("⌘/⌃ + Scroll") + Text(": Zoom both axes").foregroundColor(.secondary)
                        }
                        .font(.callout)
                        Divider()
                        Group {
                            Text("Pinch over plot") + Text(": Zoom both axes").foregroundColor(.secondary)
                            Text("Pinch over freq axis") + Text(": Zoom frequency only").foregroundColor(.secondary)
                            Text("Pinch over mag axis") + Text(": Zoom magnitude only").foregroundColor(.secondary)
                        }
                        .font(.callout)
                        Divider()
                        Group {
                            Text("Drag over plot") + Text(": Pan both axes").foregroundColor(.secondary)
                            Text("Drag over freq axis") + Text(": Pan frequency only").foregroundColor(.secondary)
                            Text("Drag over mag axis") + Text(": Pan magnitude only").foregroundColor(.secondary)
                            Text("Right-click") + Text(": Reset axes & labels").foregroundColor(.secondary)
                        }
                        .font(.callout)
                    }
                    .padding()
                    .frame(minWidth: 300)
                }
                #else
                // iOS: plain button opens a sheet — avoids UIContextMenuInteraction conflicts
                // with the chart's gesture recognizers that a Menu would cause.
                Button {
                    showingChartOptions = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingChartOptions) {
                    ChartOptionsSheet(
                        hasLabelsToReset: hasLabelsToReset,
                        onResetBothToSaved: { resetBothAxesToSaved(); showingChartOptions = false },
                        onResetFreqToSaved: { resetFrequencyAxisToSaved(); showingChartOptions = false },
                        onResetMagToSaved: { resetMagnitudeAxisToSaved(); showingChartOptions = false },
                        onResetBothToDefaults: { resetBothAxesToDefaults(); showingChartOptions = false },
                        onResetFreqToDefaults: { resetFrequencyAxisToDefaults(); showingChartOptions = false },
                        onResetMagToDefaults: { resetMagnitudeAxisToDefaults(); showingChartOptions = false },
                        onResetLabels: onResetLabels.map { action in { action(); showingChartOptions = false } }
                    )
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

    /// Legend overlay for per-phase plate/brace spectra
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
            }
            .chartYAxis { yAxisContent }
            .chartYAxisLabel(position: .leading, alignment: .center) {
                Text("FFT Magnitude (dB)")
                    .rotationEffect(.degrees(180))
            }
            // Only allow chart gestures when not dragging annotations and not in crosshair mode
            #if os(macOS)
            .simultaneousGesture(isAnnotationDragging ? nil : zoomGesture)
            .simultaneousGesture(isAnnotationDragging ? nil : panGesture)
            // Outer hover covers the full chart frame (plot + axis label areas) so the cursor
            // shape changes over the axes too — not just over the plot overlay.
            // Outer hover: cursor shape only. Does NOT update lastCursorPosition because
            // the outer hover fires in chartView-local coordinates, which differ from the
            // overlay-local coordinates that plotFrame is expressed in. lastCursorPosition
            // is kept in overlay-local space by the inner overlay hover.
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard lastPlotFrame != .zero else { return }
                    let region = pointerRegion(at: location, plotFrame: lastPlotFrame)
                    if region != currentPointerRegion {
                        NSCursor.pop()
                        switch region {
                        case .plot:
                            NSCursor.crosshair.push()
                        case .xAxis:
                            NSCursor.resizeLeftRight.push()
                        case .yAxis:
                            NSCursor.resizeUpDown.push()
                        case .outside:
                            break
                        }
                        currentPointerRegion = region
                    }
                case .ended:
                    NSCursor.pop()
                    currentPointerRegion = .outside
                }
            }
            #else
            // On iOS, zoom uses simultaneousGesture (MagnifyGesture doesn't conflict with
            // annotation DragGestures). Pan/crosshair DragGesture lives in annotationGeometryWrapper
            // so annotation labels' highPriorityGesture can pre-empt it as a child-beats-parent.
            .simultaneousGesture(isAnnotationDragging ? nil : zoomGesture)
            #endif
            #if !os(macOS)
            .onChange(of: crosshairMode.wrappedValue) { _, newValue in
                if !newValue {
                    crosshairSnapState = nil
                    lockedSeriesIndex = -1
                }
            }
            #endif
    }

    /// Helper to create GeometryReader wrapper for annotations (and cursor/crosshair on each platform).
    /// All interactive gestures live here so annotation labels' highPriorityGesture can pre-empt
    /// the background pan/hover as a child-beats-parent — no sibling overlay conflicts.
    @ViewBuilder
    private func annotationGeometryWrapper(proxy: ChartProxy) -> some View {
        if annotationOffsets != nil, let plotAnchor = proxy.plotFrame {
            GeometryReader { geometry in
                let resolvedPlotFrame = geometry[plotAnchor]
                // Keep lastPlotFrame current so the pinch zoom gesture can convert its
                // UnitPoint anchor to data coordinates without a ChartProxy reference.
                let _ = { DispatchQueue.main.async { lastPlotFrame = resolvedPlotFrame } }()
                ZStack {
                    // Non-hittable background so events reach annotation label children
                    Color.clear
                        .allowsHitTesting(false)

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
                        selectedFlcPeakID: selectedFlcPeakID,
                        modeOverrides: modeOverrides
                    )

                    #if os(macOS)
                    // macOS cursor readout — display only, no hit testing
                    if isCursorVisible, let snap = cursorSnapState {
                        cursorReadout(snap: snap, plotFrame: resolvedPlotFrame, proxy: proxy)
                            .allowsHitTesting(false)
                    }
                    #else
                    // iOS crosshair readout — display only, no hit testing
                    if crosshairMode.wrappedValue, let snap = crosshairSnapState {
                        crosshairReadout(snap: snap, plotFrame: resolvedPlotFrame, proxy: proxy)
                            .allowsHitTesting(false)
                    }
                    #endif
                }
                // contentShape makes the ZStack hittable so gestures below fire on empty areas
                .contentShape(Rectangle())
                #if os(macOS)
                // Inner overlay hover: tracks lastCursorPosition and snap readout.
                // This fires in overlay-local coordinates, which is the same space as
                // resolvedPlotFrame, so the scroll-wheel zoom anchor is correct.
                // Cursor shape is handled by the outer chartView hover.
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        // Always track position for scroll-wheel zoom anchor (overlay-local coords).
                        lastCursorPosition = location
                        guard resolvedPlotFrame.contains(location) else {
                            isCursorVisible = false
                            cursorSnapState = nil
                            lockedSeriesIndex = -1
                            break
                        }
                        cursorSnapState = resolveSnapState(
                            location: location,
                            plotFrame: resolvedPlotFrame,
                            proxy: proxy,
                            lockedSeriesIndex: &lockedSeriesIndex)
                        isCursorVisible = cursorSnapState != nil
                    case .ended:
                        lastCursorPosition = nil
                        isCursorVisible = false
                        cursorSnapState = nil
                        lockedSeriesIndex = -1
                    }
                }
                .contextMenu {
                    Button(action: resetBothAxesToSaved) {
                        Label("Reset Both Axes to Saved", systemImage: "arrow.counterclockwise")
                    }
                    Button(action: resetFrequencyAxisToSaved) {
                        Label("Reset Frequency Axis to Saved", systemImage: "arrow.counterclockwise")
                    }
                    Button(action: resetMagnitudeAxisToSaved) {
                        Label("Reset Magnitude Axis to Saved", systemImage: "arrow.counterclockwise")
                    }
                    Divider()
                    Button(action: resetBothAxesToDefaults) {
                        Label("Reset Both Axes to Defaults", systemImage: "arrow.counterclockwise.circle")
                    }
                    Button(action: resetFrequencyAxisToDefaults) {
                        Label("Reset Frequency Axis to Defaults", systemImage: "arrow.counterclockwise.circle")
                    }
                    Button(action: resetMagnitudeAxisToDefaults) {
                        Label("Reset Magnitude Axis to Defaults", systemImage: "arrow.counterclockwise.circle")
                    }
                    if let onResetLabels = onResetLabels {
                        Divider()
                        Button(action: onResetLabels) {
                            Label("Reset Labels", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(!hasLabelsToReset)
                    }
                }
                #else
                // Pan/crosshair DragGesture: annotation highPriorityGestures pre-empt this as children
                .gesture(
                    DragGesture(minimumDistance: crosshairMode.wrappedValue ? 0 : 10)
                        .onChanged { value in
                            if crosshairMode.wrappedValue {
                                // Crosshair only tracks within the plot area
                                guard resolvedPlotFrame.contains(value.location) else { return }
                                crosshairSnapState = resolveSnapState(
                                    location: value.location,
                                    plotFrame: resolvedPlotFrame,
                                    proxy: proxy,
                                    lockedSeriesIndex: &lockedSeriesIndex)
                            } else {
                                guard !isAnnotationDragging else {
                                    lastDragTranslation = .zero
                                    return
                                }
                                // Capture the start region once so axis constraint is stable
                                // for the entire gesture (finger may wander off the axis).
                                if lastDragTranslation == .zero {
                                    dragRegion = pointerRegion(at: value.startLocation, plotFrame: resolvedPlotFrame)
                                }
                                let delta = CGSize(
                                    width:  value.translation.width  - lastDragTranslation.width,
                                    height: value.translation.height - lastDragTranslation.height
                                )
                                lastDragTranslation = value.translation
                                // Constrain pan to the axis the drag started on
                                let constrainedDelta: CGSize
                                switch dragRegion {
                                case .xAxis:
                                    constrainedDelta = CGSize(width: delta.width, height: 0)
                                case .yAxis:
                                    constrainedDelta = CGSize(width: 0, height: delta.height)
                                default:
                                    constrainedDelta = delta
                                }
                                handlePan(translation: constrainedDelta)
                            }
                        }
                        .onEnded { _ in
                            if crosshairMode.wrappedValue {
                                crosshairSnapState = nil
                                lockedSeriesIndex = -1
                            } else {
                                lastDragTranslation = .zero
                                dragRegion = .plot
                            }
                        }
                )
                #endif
                #if os(macOS)
                // Scroll-wheel zoom/pan — placed here so proxy and resolvedPlotFrame are in scope,
                // allowing anchor-aware zoom around the cursor position.
                .onScrollWheel { event in
                    handleScrollWheel(event: event, plotFrame: resolvedPlotFrame, proxy: proxy)
                }
                #endif
            }
        }
    }

    #if os(macOS)
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
    private func cursorReadout(snap: CursorSnapState, plotFrame: CGRect, proxy: ChartProxy) -> some View {
        let labelWidth: CGFloat = 130
        let labelHeight: CGFloat = 40
        let margin: CGFloat = 8

        let cursorX = plotFrame.minX + (proxy.position(forX: snap.frequency) ?? 0)
        // Clamp Y so the horizontal crosshair stays inside the plot when the curve
        // is clipped at the top or bottom of the visible magnitude range.
        let cursorY = (plotFrame.minY + (proxy.position(forY: snap.magnitude) ?? 0))
            .clamped(to: plotFrame.minY...plotFrame.maxY)

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
            Text(formatCursorFrequency(snap.frequency))
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(snap.curveColor)  // Colored to match the tracked curve
            Text(String(format: "%.1f dB", snap.magnitude))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 2)
        .frame(width: labelWidth, height: labelHeight)
        .position(x: labelX + labelWidth / 2, y: labelY + labelHeight / 2)
        .allowsHitTesting(false)
    }
    #endif

    #if !os(macOS)
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
    private func crosshairReadout(snap: CursorSnapState, plotFrame: CGRect, proxy: ChartProxy) -> some View {
        let labelWidth: CGFloat = 130
        let labelHeight: CGFloat = 40
        let margin: CGFloat = 8

        let cursorX = (proxy.position(forX: snap.frequency) ?? 0) + plotFrame.minX
        // Clamp Y so the horizontal crosshair stays inside the plot when the curve
        // is clipped at the top or bottom of the visible magnitude range.
        let cursorY = ((proxy.position(forY: snap.magnitude) ?? 0) + plotFrame.minY)
            .clamped(to: plotFrame.minY...plotFrame.maxY)

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
            Text(formatCrosshairFrequency(snap.frequency))
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(snap.curveColor)  // Colored to match the tracked curve
            Text(String(format: "%.1f dB", snap.magnitude))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 2)
        .frame(width: labelWidth, height: labelHeight)
        .position(x: labelX + labelWidth / 2, y: labelY + labelHeight / 2)
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

        }
        // Single chartOverlay on both platforms: annotations, cursor/crosshair readout, and
        // background gestures all share one view tree so highPriorityGesture on annotation
        // labels correctly pre-empts the parent pan/hover gesture.
        .chartOverlay { proxy in
            annotationGeometryWrapper(proxy: proxy)
        }
        .chartXScale(domain: Double(minFreq)...Double(maxFreq), type: isLogarithmic ? .log : .linear)
        .chartYScale(domain: Double(minDB)...Double(maxDB))
    }

    /// X-axis content builder
    @AxisContentBuilder
    private var xAxisContent: some AxisContent {
        let labels = frequencyAxisLabels
        AxisMarks(values: frequencyAxisValues) { value in
            AxisValueLabel {
                if let doubleValue = value.as(Double.self) {
                    Text(labels[doubleValue] ?? AxisTickGenerator.formatTickLabel(doubleValue))
                }
            }
            AxisGridLine()
        }
    }

    /// Y-axis content builder
    @AxisContentBuilder
    private var yAxisContent: some AxisContent {
        AxisMarks(position: .leading, values: .stride(by: yAxisStride)) { value in
            AxisValueLabel()
            AxisGridLine()
        }
    }

    /// Computes a "nice" dB stride that yields roughly 4–6 ticks for the current visible range.
    private var yAxisStride: Double {
        let range = Double(maxDB - minDB)
        // Pick the smallest stride from this set that produces no more than ~8 ticks.
        for stride in [1.0, 2.0, 5.0, 10.0, 20.0, 50.0] {
            if range / stride <= 8 {
                return stride
            }
        }
        return 50.0
    }

    /// Pinch gesture for zooming, anchored to the pinch midpoint.
    ///
    /// Uses `MagnifyGesture` (iOS 17+ / macOS 14+) which provides `startAnchor`
    /// — the unit-space centroid of the pinch within the view — so the chart zooms
    /// around the pinch location rather than the center of the visible range.
    ///
    /// The zoom is axis-constrained based on where the pinch starts:
    /// - Over the plot area → zoom both axes
    /// - Over the x-axis area → zoom frequency axis only
    /// - Over the y-axis area → zoom magnitude axis only
    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // Compute the per-frame delta so zoom accumulates incrementally.
                let delta = value.magnification / lastMagnificationScale
                lastMagnificationScale = value.magnification

                // Classify where the pinch started to decide which axis to zoom.
                // Convert startAnchor (unit point relative to the full view) to screen coords.
                guard lastPlotFrame != .zero else {
                    handleZoom(scale: delta, pinchAnchor: value.startAnchor)
                    return
                }
                let viewWidth  = lastPlotFrame.minX + lastPlotFrame.width
                let viewHeight = lastPlotFrame.minY + lastPlotFrame.height
                let startPoint = CGPoint(
                    x: value.startAnchor.x * viewWidth,
                    y: value.startAnchor.y * viewHeight
                )
                // Classify the region inline (mirrors pointerRegion on macOS).
                let pinchRegion: PointerRegion
                if lastPlotFrame.contains(startPoint) {
                    pinchRegion = .plot
                } else if startPoint.x < lastPlotFrame.minX &&
                          startPoint.y >= lastPlotFrame.minY &&
                          startPoint.y <= lastPlotFrame.maxY {
                    pinchRegion = .yAxis
                } else if startPoint.y > lastPlotFrame.maxY &&
                          startPoint.x >= lastPlotFrame.minX &&
                          startPoint.x <= lastPlotFrame.maxX {
                    pinchRegion = .xAxis
                } else {
                    pinchRegion = .outside
                }
                switch pinchRegion {
                case .xAxis:
                    handleFrequencyZoom(scale: delta)
                case .yAxis:
                    applyMagnitudeZoom(scale: delta, anchorDB: (maxDB + minDB) / 2)
                default:
                    handleZoom(scale: delta, pinchAnchor: value.startAnchor)
                }
            }
            .onEnded { _ in
                lastMagnificationScale = 1.0
            }
    }

    /// Drag gesture for panning (macOS).
    ///
    /// Captures the drag start region from `lastPlotFrame` on the first `.onChanged`
    /// call and holds it for the duration of the drag so axis constraint stays stable
    /// even if the pointer wanders into a different region mid-drag.
    ///
    /// - `.plot` start → pan both axes
    /// - `.xAxis` start → pan frequency axis only
    /// - `.yAxis` start → pan magnitude axis only
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = value.translation
                guard !isAnnotationDragging else {
                    lastDragTranslation = .zero
                    return
                }
#if os(macOS)
                // On the first event of a new drag, capture the start region so the
                // axis constraint is stable for the entire gesture.
                if lastDragTranslation == .zero {
                    dragRegion = pointerRegion(at: value.startLocation, plotFrame: lastPlotFrame)
                }
#endif
                // Compute the per-frame delta so pan accumulates incrementally.
                let rawDelta = CGSize(
                    width:  value.translation.width  - lastDragTranslation.width,
                    height: value.translation.height - lastDragTranslation.height
                )
                lastDragTranslation = value.translation
#if os(macOS)
                // Constrain pan axis based on where the drag started.
                let constrainedDelta: CGSize
                switch dragRegion {
                case .xAxis:
                    constrainedDelta = CGSize(width: rawDelta.width, height: 0)
                case .yAxis:
                    constrainedDelta = CGSize(width: 0, height: rawDelta.height)
                default:
                    constrainedDelta = rawDelta
                }
                handlePan(translation: constrainedDelta)
#else
                handlePan(translation: rawDelta)
#endif
            }
            .onEnded { _ in
                dragOffset = .zero
                lastDragTranslation = .zero
#if os(macOS)
                dragRegion = .plot
#endif
            }
    }
}

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

// MARK: - iOS Chart Options Sheet

#if !os(macOS)
/// A sheet presenting axis-reset and label-reset options for the spectrum chart on iOS.
/// Using a sheet instead of a Menu avoids UIContextMenuInteraction conflicts with
/// the chart's gesture recognizers.
private struct ChartOptionsSheet: View {
    let hasLabelsToReset: Bool
    let onResetBothToSaved: () -> Void
    let onResetFreqToSaved: () -> Void
    let onResetMagToSaved: () -> Void
    let onResetBothToDefaults: () -> Void
    let onResetFreqToDefaults: () -> Void
    let onResetMagToDefaults: () -> Void
    let onResetLabels: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chart Options")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            Group {
                sectionHeader("Reset to Saved")
                optionButton("Reset Both Axes", icon: "arrow.uturn.backward", action: onResetBothToSaved)
                optionButton("Reset Frequency Axis", icon: "arrow.uturn.backward", action: onResetFreqToSaved)
                optionButton("Reset Magnitude Axis", icon: "arrow.uturn.backward", action: onResetMagToSaved)
            }

            Divider().padding(.vertical, 4)

            Group {
                sectionHeader("Reset to Defaults")
                optionButton("Reset Both Axes", icon: "arrow.counterclockwise.circle", action: onResetBothToDefaults)
                optionButton("Reset Frequency Axis", icon: "arrow.counterclockwise.circle", action: onResetFreqToDefaults)
                optionButton("Reset Magnitude Axis", icon: "arrow.counterclockwise.circle", action: onResetMagToDefaults)
            }

            if let onResetLabels {
                Divider().padding(.vertical, 4)
                optionButton("Reset Labels", icon: "arrow.uturn.backward.circle", action: onResetLabels)
                    .disabled(!hasLabelsToReset)
            }
        }
        .padding(.bottom, 8)
        .frame(minWidth: 280)
        .presentationDetents([.height(460), .large])
        .presentationDragIndicator(.visible)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    private func optionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
