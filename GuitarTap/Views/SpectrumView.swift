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
/// visible range across taps.  The legal ranges are ``DisplayRange``'s chart limits:
/// - Frequency: 1 Hz – 5 kHz; minimum visible span 10 Hz
/// - Magnitude: −120 dB – +20 dB; minimum visible span 10 dB
///
/// - SeeAlso: `TapToneAnalysisView`, `PeakAnnotations`, `AxisTickGenerator`
//
//  SpectrumView.swift
//  GuitarTap
//
//  Created by David Smith on 12/31/25.
//
// @parity view/spectrum-chart

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
///
/// - Important: `id` incorporates both `sourceEpoch` and `frequency`.  The
///   epoch changes whenever the data source switches between live FFT and frozen
///   spectrum (i.e. when `isMeasurementComplete` flips).  This forces Swift
///   Charts to treat all points as entirely new when the source changes, which
///   prevents the transient interleaving artifact where two datasets that share
///   the same frequency bins get connected as one continuous path and produce
///   vertical spikes on the chart.
///
///   A frequency-only ID would allow Charts to reconcile "the same bin" across
///   the source transition, animating magnitudes from one source to another and
///   briefly rendering both datasets as one series.  Adding the epoch breaks
///   that identity so Charts discards old marks and draws fresh ones instead.
struct SpectrumDataPoint: Identifiable {
    /// Stable identifier combining source epoch and frequency.
    ///
    /// The epoch changes whenever the data source (live vs frozen) changes,
    /// ensuring Charts does not try to reconcile points across the boundary.
    var id: String { "\(sourceEpoch)-\(frequency)" }

    /// Source discriminator: 0 = live FFT, 1 = frozen/loaded measurement.
    /// Changing this value causes Charts to treat all existing marks as removed
    /// and new ones as inserted, preventing cross-source interpolation.
    let sourceEpoch: Int

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
/// It supports pinch-to-zoom and drag-to-pan gestures.
///
/// ## Features
/// - Area chart with gradient fill for visual appeal
/// - Line chart overlay showing the spectrum shape
/// - Automatic axis labels with smart frequency formatting (Hz or kHz)
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

    /// All detected peaks — every peak gets a dot on the chart regardless of annotation visibility.
    var peaks: [ResonantPeak]?

    /// The subset of peaks that should show annotation labels.
    ///
    /// When `nil`, `visiblePeaks` falls back to `peaks` with the unknown-mode filter. When
    /// provided, the caller is responsible for applying the annotation visibility filter so that
    /// `SpectrumView` does not need to know about `selectedPeakIDs` or
    /// `annotationVisibilityMode`.
    var annotationPeaks: [ResonantPeak]? = nil

    /// Whether to show mode boundary markers
    var showModeBoundaries: Bool = true

    /// Callback invoked when the frequency range changes due to zoom/pan gestures
    var onFrequencyRangeChanged: (() -> Void)?

    /// Callback invoked when an axis-reset menu item is chosen.
    ///
    /// The parent sets all four axis `@State` vars in one closure so SwiftUI
    /// coalesces them into a single render pass, preventing the transient
    /// `minDB > maxDB` state that causes the clamping artifact.
    /// Signature: `(minFreq, maxFreq, minDB, maxDB) -> Void`
    var onAxisRangeReset: ((Float, Float, Float, Float) -> Void)?

    /// Optional binding to annotation offsets for draggable labels
    var annotationOffsets: Binding<[UUID: CGPoint]>?

    /// Optional per-phase spectra to overlay (plate/brace measurements: L, C, FLC)
    /// Each entry has its own colour and label for the legend
    var materialSpectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)] = []

    /// Optional threshold lines to display (for tap detection visualization)
    var thresholdLines: [(value: Float, label: String, color: Color, lineWidth: CGFloat, dash: [CGFloat])]?

    /// Optional callback to reset all peak annotation label positions
    var onResetLabels: (() -> Void)?

    /// The comparison range while a comparison measurement is shown, else nil: with it, the chart's menu is the
    /// comparison's (`ChartMenu.comparisonGroups`), resetting to it.
    var comparisonRange: DisplayRange.ChartRange? = nil

    /// Whether there are annotation offsets that need resetting (controls enabled state of menu item)
    var hasLabelsToReset: Bool = false

    /// When true the cursor/crosshair snaps to the nearest waveform point instead of floating freely.
    /// Should be set to true when a measurement is complete (post-tap capture).
    var isMeasurementComplete: Bool = false

    /// When true the analyzer is in a material-phase review state (reviewingLongitudinal,
    /// reviewingCross, or reviewingFlc). The live waveform is suppressed so only the frozen
    /// phase overlays and peak annotations are visible.
    var isReviewingMaterialPhase: Bool = false

    /// Color of the primary (single) spectrum line. Used to tint the cursor readout label
    /// so it matches the waveform. Only relevant when `materialSpectra` is empty.
    var primaryCurveColor: Color = Palette.color(.chartSpectrum)

    /// The current measurement type (guitar vs plate/brace) - affects which annotations are shown
    var measurementType: MeasurementType = .acoustic

    /// ID of the peak selected as longitudinal mode (for plate/brace measurements)
    var selectedLongitudinalPeakID: UUID?

    /// ID of the peak selected as cross-grain mode (for plate measurements)
    var selectedCrossPeakID: UUID?

    /// ID of the peak selected as FLC (diagonal/shear) mode (for plate measurements)
    var selectedFlcPeakID: UUID?

    /// Per-peak user mode overrides — passed through to annotation labels (guitar mode only)
    var modeOverrides: [UUID: String] = [:]

    /// Context-aware mode classification for all peaks in this view, keyed by peak UUID.
    ///
    /// Callers should pass `Dictionary(uniqueKeysWithValues: analyzer.identifiedModes.map { ($0.peak.id, $0.mode) })`
    /// so that mode assignments computed via ``GuitarMode/classifyAll(_:guitarType:)`` are reused
    /// rather than recomputed per-view. When empty, ``peakColor(for:)`` falls back to computing
    /// a local mode map from ``allPeaksInRange``.
    var peakModes: [UUID: GuitarMode] = [:]

    /// The currently highlighted peak ID — bidirectional link between chart dots and results rows.
    ///
    /// A non-nil value causes the corresponding dot to render at full size with a white ring.
    /// Tapping the dot (or a results row) toggles this value. Passed as a `Binding` so changes
    /// propagate back to the shared analyzer.
    var highlightedPeakID: Binding<UUID?> = .constant(nil)

    /// Plain (non-binding) copy of ``highlightedPeakID`` for use inside `@ChartContentBuilder`.
    ///
    /// `@ChartContentBuilder` closures do not observe `Binding` changes on their own; reading
    /// `highlightedPeakID.wrappedValue` there would not trigger a re-render. Exposing the
    /// value as a plain stored-equivalent computed property ensures SwiftUI's view diffing
    /// detects the change and re-evaluates `peakAnnotationContent`.
    var currentHighlightedPeakID: UUID? { highlightedPeakID.wrappedValue }

    /// Title shown above the chart. Defaults to "FFT Peaks".
    var chartTitle: String = "FFT Peaks"

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

    /// Whether the chart-options (⋯) menu/sheet is showing. All platforms now show the
    /// ⋯ button in the chart's upper-right, so this is no longer iOS-only.
    /// Whether the zoom/pan controls (?) help popover is showing. All platforms.
    @State private var showingControlsHelp: Bool = false
    /// Raw screen-local position of the pointer within the chart overlay: on macOS updated on every hover tick, on
    /// iOS with each scroll from a mouse or trackpad. The scroll handler zooms around it rather than the range midpoint.
    @State var lastCursorPosition: CGPoint? = nil
    /// Where each peak label is on the chart, as the labels report it.
    @State private var peakLabelFrames: [UUID: CGRect] = [:]

    #if os(macOS)
    /// Snapped cursor position in data coordinates, including series identity. Nil when not hovering.
    @State private var cursorSnapState: CursorSnapState? = nil

    /// Whether the cursor readout is currently visible
    @State private var isCursorVisible: Bool = false


    /// Which chart region the pointer is currently over. Updated on every hover tick.
    /// Used by the scroll-wheel handler to decide which axis to operate on.
    @State var currentPointerRegion: PointerRegion = .outside

    #else

    /// Whether crosshair tracking mode is active (iOS only). Defaults to false when not provided.
    var crosshairMode: Binding<Bool> = .constant(false)

    /// Snapped crosshair position in data coordinates, including series identity. Nil when not active.
    @State private var crosshairSnapState: CursorSnapState? = nil
    #endif

    /// Whether a point is over a peak label: the labels' frames as drawn, cut at the plot's edges.
    func isOverLabel(_ point: CGPoint, plotFrame: CGRect) -> Bool {
        peakLabelFrames.values.contains { $0.intersection(plotFrame).contains(point) }
    }

    // MARK: - Computed Properties

    /// Filters and converts the frequency/magnitude arrays into chart data points.
    ///
    /// Only includes data points within the current visible frequency range.
    /// This improves rendering performance for large FFT sizes.
    ///
    /// The `sourceEpoch` embedded in each point's identity flips between 0 (live)
    /// and 1 (frozen) whenever `isMeasurementComplete` changes.  This prevents
    /// Swift Charts from reconciling points across a live→frozen (or frozen→live)
    /// source transition, which would cause both datasets to be briefly connected
    /// as one continuous path and produce the vertical spike artifact.
    var chartData: [SpectrumDataPoint] {
        let epoch = isMeasurementComplete ? 1 : 0
        let count = Swift.min(frequencies.count, magnitudes.count)
        return DisplayRange.drawnIndices(of: Array(frequencies.prefix(count)), min: minFreq, max: maxFreq)
            .map { SpectrumDataPoint(sourceEpoch: epoch, frequency: frequencies[$0], magnitude: magnitudes[$0]) }
    }

    /// Returns the mode boundaries that are visible in the current frequency range
    var visibleModeBoundaries: [(frequency: Float, mode: GuitarMode)] {
        let allModes: [GuitarMode] = [.air, .top, .back, .dipole, .ringMode, .upperModes]
        var boundaries: [(Float, GuitarMode)] = []

        for mode in allModes {
            let range = mode.modeRange
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

    /// Returns all peaks in the current frequency range, regardless of annotation visibility mode.
    ///
    /// Used for the always-visible dot layer so every detected peak has a dot even when
    /// annotations are hidden. Applies the same unknown-mode filter as ``visiblePeaks``.
    ///
    /// The rule itself lives in ``GuitarMode/peaksInDisplayRange(_:minFreq:maxFreq:isGuitar:showUnknownModes:guitarType:)``
    /// so Python and the web share one testable definition (`@parity view/dot-layer`).
    var allPeaksInRange: [ResonantPeak] {
        GuitarMode.peaksInDisplayRange(
            peaks ?? [],
            minFreq: minFreq,
            maxFreq: maxFreq,
            isGuitar: measurementType.isGuitar,
            showUnknownModes: TapDisplaySettings.showUnknownModes,
            overriddenPeakIDs: overriddenPeakIDs
        )
    }

    /// The peaks carrying a manual mode label, derived from the ``modeOverrides`` this view was
    /// handed. A user-named peak is never filtered out as unknown — see
    /// ``TapToneAnalyzer/isUnknown(_:)`` for the rule and ``GuitarMode/peaksInDisplayRange(_:minFreq:maxFreq:isGuitar:showUnknownModes:overriddenPeakIDs:guitarType:)``
    /// for its static form. Empty for call sites that pass no overrides (comparison overlays), which
    /// leaves the filter purely positional there — correct, since those peaks belong to other
    /// measurements and carry no overrides of their own.
    private var overriddenPeakIDs: Set<UUID> {
        Set(modeOverrides.keys)
    }

    /// Returns the peaks that should show annotation labels — whatever the chart's range: a label
    /// whose peak is off the chart is drawn too, and the plot's edges cut it.
    ///
    /// When an explicit ``annotationPeaks`` list is provided by the caller, that list is returned
    /// as it is — the caller has already applied the annotation visibility mode filter.
    ///
    /// When `annotationPeaks` is `nil`, falls back to ``peaks`` with the dot layer's unknown-mode
    /// filter, over every frequency (call sites that don't need separate dot/label control).
    var visiblePeaks: [ResonantPeak] {
        // If the caller supplied a pre-filtered annotation list, use it
        if let explicit = annotationPeaks {
            return explicit
        }

        return GuitarMode.peaksInDisplayRange(
            peaks ?? [],
            minFreq: -.infinity,
            maxFreq: .infinity,
            isGuitar: measurementType.isGuitar,
            showUnknownModes: TapDisplaySettings.showUnknownModes,
            overriddenPeakIDs: overriddenPeakIDs
        )
    }

    /// Calculates appropriate frequency values for axis labels based on the current zoom level.
    ///
    /// The values are evenly spaced with appropriate step sizes for the visible range.
    ///
    /// - Returns: An array of frequency values (in Hz) where axis labels should be placed
    private var frequencyAxisValues: [Double] {
        let lo = Double(minFreq)
        let hi = Double(maxFreq)
        // Filter to the visible domain so ticks produced by the "nice number" rounding
        // that fall outside [minFreq, maxFreq] (e.g. a 0 Hz tick when minFreq is 20)
        // are not passed to AxisMarks, which would place them in the axis-label gutter.
        return AxisTickGenerator.generateTicks(min: lo, max: hi, maxTicks: 8)
            .filter { $0 >= lo && $0 <= hi }
    }

    /// The frequency labels' size: Swift Charts' own axis label size, stated so a label's width can be measured.
    private static let frequencyLabelSize: CGFloat = 11

    /// Labels for frequency axis ticks, with precision automatically increased
    /// when the default formatting would produce duplicate labels.
    private var frequencyAxisLabels: [Double: String] {
        AxisTickGenerator.formatTickLabels(frequencyAxisValues)
    }

    // MARK: - Body

    /// The chart's menu (`ChartMenu.groups`) with this chart's actions — the same from the ⋯ and from a right-click,
    /// on every device: SwiftUI's menu (`chartMenuItems`) and, for iOS's right-click, UIKit's (`chartUIMenu`).
    private var chartMenuGroups: [[ChartMenuItem]] {
        (comparisonRange == nil ? ChartMenu.groups : ChartMenu.comparisonGroups).compactMap { group in
            let items: [ChartMenuItem] = group.compactMap { entry in
                switch entry.action {
                case .resetBothToSaved: return ChartMenuItem(entry: entry, action: resetBothAxesToSaved)
                case .resetFrequencyToSaved: return ChartMenuItem(entry: entry, action: resetFrequencyAxisToSaved)
                case .resetMagnitudeToSaved: return ChartMenuItem(entry: entry, action: resetMagnitudeAxisToSaved)
                case .resetBothToDefaults: return ChartMenuItem(entry: entry, action: resetBothAxesToDefaults)
                case .resetFrequencyToDefaults: return ChartMenuItem(entry: entry, action: resetFrequencyAxisToDefaults)
                case .resetMagnitudeToDefaults: return ChartMenuItem(entry: entry, action: resetMagnitudeAxisToDefaults)
                case .resetBothToComparison: return ChartMenuItem(entry: entry, action: resetBothAxesToComparison)
                case .resetFrequencyToComparison: return ChartMenuItem(entry: entry, action: resetFrequencyAxisToComparison)
                case .resetMagnitudeToComparison: return ChartMenuItem(entry: entry, action: resetMagnitudeAxisToComparison)
                case .resetLabels:
                    guard let onResetLabels else { return nil }
                    return ChartMenuItem(entry: entry, action: onResetLabels, isEnabled: hasLabelsToReset)
                case .resetPosition: return nil
                }
            }
            return items.isEmpty ? nil : items
        }
    }

    /// The chart's menu as SwiftUI menu items: the macOS right-click.
    private var chartMenuItems: some View { ChartMenuItems(groups: chartMenuGroups) }

    #if os(iOS)
    /// The chart's menu as a UIKit menu, for a secondary click on iOS.
    private func chartUIMenu() -> UIMenu {
        UIMenu(children: chartMenuGroups.map { group in
            UIMenu(options: .displayInline, children: group.map { item in
                let action = UIAction(title: item.title, image: UIImage(systemName: item.symbol)) { _ in item.action() }
                if !item.isEnabled { action.attributes = .disabled }
                return action
            })
        })
    }
    #endif

    /// ⋯ — the chart's menu, on every device.
    private var chartOptionsButton: some View {
        ChartMenuButton(groups: chartMenuGroups).equatable()
    }

    /// ? help button — shown on every platform.
    private var controlsHelpButton: some View {
        Button { showingControlsHelp.toggle() } label: {
            Image(systemName: "info.circle").font(.caption)
        }
        .buttonStyle(.icon())
        .help("Zoom & Pan Controls")
        // Below the ⓘ (iOS places a popover itself), a popover on the iPhone too, as the ⋯ menu.
        .popover(isPresented: $showingControlsHelp, arrowEdge: .top) {
            ChartHelpView()
                .equatable()
                .presentationCompactAdaptation(.popover)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(chartTitle)
                    .font(.headline)
                    .foregroundColor(Palette.color(.chartTitle))
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 14) {
                    Spacer()
                    chartOptionsButton
                    controlsHelpButton
                }
            }
            .padding(.bottom, 8)

            ZStack(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    ChartAxisTitle(text: "FFT Magnitude (dB)", font: .caption, vertical: true)
                    VStack(spacing: 4) {
                        chartView
                        ChartAxisTitle(text: "Frequency (Hz)", font: .caption)
                    }
                }
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
            .background(Palette.color(.chartReadoutBackground), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    /// The main chart view with all configurations applied
    private var chartView: some View {
        baseChart
            .chartXAxis { xAxisContent }
            .chartYAxis { yAxisContent }
            // Only allow chart gestures when not dragging annotations and not in crosshair mode
            #if os(macOS)
            .simultaneousGesture(isAnnotationDragging ? nil : zoomGesture)
            .simultaneousGesture(isAnnotationDragging ? nil : panGesture)
            // Outer hover: tracks when pointer leaves the chart entirely.
            // Cursor restore on exit: NSCursor.arrow is set by the outer .onContinuousHover .ended handler.
            .onContinuousHover { phase in
                if case .ended = phase {
                    currentPointerRegion = .outside
                    lastCursorPosition = nil
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
                    // Transparent fill ensures this ZStack always has a hittable frame,
                    // even when no annotation labels are rendered (visiblePeaks is empty).
                    // Required for onContinuousHover to fire in all annotation-visibility states.
                    Rectangle()
                        .fill(Color.clear)

                    // The mode chips, over the curves and dots, under the peak labels.
                    if showModeBoundaries && measurementType.isGuitar {
                        ModeChipsLayer(mapping: PlotMapping(plot: resolvedPlotFrame, minFreq: minFreq, maxFreq: maxFreq,
                                                            minDB: minDB, maxDB: maxDB))
                    }

                    PeakAnnotationsOverlay(
                        peaks: visiblePeaks,
                        annotationOffsets: annotationOffsets!,
                        geometry: geometry,
                        plotFrame: resolvedPlotFrame,
                        minFreq: minFreq,
                        maxFreq: maxFreq,
                        minDB: minDB,
                        maxDB: maxDB,
                        isAnnotationDragging: $isAnnotationDragging,
                        measurementType: measurementType,
                        selectedLongitudinalPeakID: selectedLongitudinalPeakID,
                        selectedCrossPeakID: selectedCrossPeakID,
                        selectedFlcPeakID: selectedFlcPeakID,
                        modeOverrides: modeOverrides,
                        peakModes: peakModes
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
                // contentShape ensures the ZStack is hittable even when empty (no annotation labels).
                // This is required for onContinuousHover to fire reliably.
                .coordinateSpace(name: PeakLabelFramesKey.space)
                .onPreferenceChange(PeakLabelFramesKey.self) { peakLabelFrames = $0 }
                .contentShape(Rectangle())
                #if os(macOS)
                // Hover handler: sets cursor on mouse move and tracks position/snap state.
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        lastCursorPosition = location
                        let region = pointerRegion(at: location, plotFrame: resolvedPlotFrame)
                        currentPointerRegion = region
                        let overLabel = isOverLabel(location, plotFrame: resolvedPlotFrame)
                        if overLabel {
                            NSCursor.openHand.set()
                        } else {
                            switch region {
                            case .plot:    NSCursor.crosshair.set()
                            case .xAxis:   NSCursor.resizeLeftRight.set()
                            case .yAxis:   NSCursor.resizeUpDown.set()
                            case .outside: NSCursor.arrow.set()
                            }
                        }
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
                .contextMenu { chartMenuItems }
                #else
                // Scrolling with a mouse or trackpad zooms and pans as on macOS; touches pass through.
                .overlay(PointerScroll { event, location in
                    lastCursorPosition = location
                    handleScrollWheel(event: event, plotFrame: resolvedPlotFrame, proxy: proxy)
                })
                // A right-click with a mouse or trackpad opens the chart menu; touches pass through.
                .overlay(SecondaryClickMenu(menu: { chartUIMenu() }, passesThrough: { point in
                    isOverLabel(point, plotFrame: resolvedPlotFrame)
                }))
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
                // Scroll-wheel zoom/pan. The cursorHandler is called on every mouse-moved
                // event while inside bounds, re-asserting the correct cursor after SwiftUI
                // re-renders (triggered by zoom/pan) reset it to the system arrow.
                .onScrollWheel({ event in
                    handleScrollWheel(event: event, plotFrame: resolvedPlotFrame, proxy: proxy)
                }, cursorHandler: { point in
                    let cgPoint = CGPoint(x: point.x, y: point.y)
                    let overLabel = isOverLabel(cgPoint, plotFrame: resolvedPlotFrame)
                    if overLabel {
                        NSCursor.openHand.set()
                    } else {
                        switch pointerRegion(at: cgPoint, plotFrame: resolvedPlotFrame) {
                        case .plot:    NSCursor.crosshair.set()
                        case .xAxis:   NSCursor.resizeLeftRight.set()
                        case .yAxis:   NSCursor.resizeUpDown.set()
                        case .outside: NSCursor.arrow.set()
                        }
                    }
                })
                #endif
                #if os(macOS)
                // Tap gesture to highlight the nearest peak dot (macOS only — on iOS the
                // results panel is modal and cross-highlight has no practical use)
                .onTapGesture { location in
                    guard resolvedPlotFrame.contains(location) else { return }
                    if let peak = nearestPeak(to: location, in: resolvedPlotFrame) {
                        if highlightedPeakID.wrappedValue == peak.id {
                            highlightedPeakID.wrappedValue = nil
                        } else {
                            highlightedPeakID.wrappedValue = peak.id
                        }
                    }
                }
                #endif
            }
        }
    }

    /// Returns the peak whose chart position is closest to the given tap location,
    /// or `nil` if no peak is within 30 points.
    private func nearestPeak(to location: CGPoint, in plotFrame: CGRect) -> ResonantPeak? {
        let hitRadius: CGFloat = 30
        var closest: (peak: ResonantPeak, dist: CGFloat)? = nil
        for peak in allPeaksInRange {
            let px = chartX(frequency: peak.frequency, in: plotFrame)
            let clampedMag = max(minDB, min(maxDB, peak.magnitude))
            let py = chartY(magnitude: clampedMag, in: plotFrame)
            let dist = hypot(location.x - px, location.y - py)
            if dist < hitRadius {
                if closest == nil || dist < closest!.dist {
                    closest = (peak, dist)
                }
            }
        }
        return closest?.peak
    }

    /// Converts a frequency value to an x-coordinate within the given plot frame.
    private func chartX(frequency: Float, in plotFrame: CGRect) -> CGFloat {
        let norm = CGFloat(frequency - minFreq) / CGFloat(maxFreq - minFreq)
        return plotFrame.minX + norm * plotFrame.width
    }

    /// Converts a magnitude (dB) value to a y-coordinate within the given plot frame.
    /// Charts render y from top (maxDB) to bottom (minDB).
    private func chartY(magnitude: Float, in plotFrame: CGRect) -> CGFloat {
        let norm = CGFloat(magnitude - minDB) / CGFloat(maxDB - minDB)
        return plotFrame.minY + (1.0 - norm) * plotFrame.height
    }

    #if os(macOS)
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
        .stroke(Palette.color(.chartCrosshairLine),
                style: StrokeStyle(lineWidth: ChartStyle.screen.crosshairWidth, dash: ChartStyle.screen.crosshairDash))
        .allowsHitTesting(false)

        // Horizontal crosshair line
        Path { path in
            path.move(to: CGPoint(x: plotFrame.minX, y: cursorY))
            path.addLine(to: CGPoint(x: plotFrame.maxX, y: cursorY))
        }
        .stroke(Palette.color(.chartCrosshairLine),
                style: StrokeStyle(lineWidth: ChartStyle.screen.crosshairWidth, dash: ChartStyle.screen.crosshairDash))
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
            Text(Float(snap.frequency).formattedAsFrequency())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(snap.curveColor)  // Colored to match the tracked curve
            Text("\(FieldPrecision.string(Float(snap.magnitude), FieldPrecision.peakMagnitudeDB)) dB")
                .font(.caption2)
                .foregroundColor(Palette.color(.chartAxis))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Palette.color(.chartReadoutBackground), in: RoundedRectangle(cornerRadius: 6))
        .frame(width: labelWidth, height: labelHeight)
        .position(x: labelX + labelWidth / 2, y: labelY + labelHeight / 2)
        .allowsHitTesting(false)
    }
    #endif

    #if !os(macOS)
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
        .stroke(Palette.color(.chartCrosshairLine),
                style: StrokeStyle(lineWidth: ChartStyle.screen.crosshairWidth, dash: ChartStyle.screen.crosshairDash))
        .allowsHitTesting(false)

        // Horizontal crosshair line
        Path { path in
            path.move(to: CGPoint(x: plotFrame.minX, y: cursorY))
            path.addLine(to: CGPoint(x: plotFrame.maxX, y: cursorY))
        }
        .stroke(Palette.color(.chartCrosshairLine),
                style: StrokeStyle(lineWidth: ChartStyle.screen.crosshairWidth, dash: ChartStyle.screen.crosshairDash))
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
            Text(Float(snap.frequency).formattedAsFrequency())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(snap.curveColor)  // Colored to match the tracked curve
            Text("\(FieldPrecision.string(Float(snap.magnitude), FieldPrecision.peakMagnitudeDB)) dB")
                .font(.caption2)
                .foregroundColor(Palette.color(.chartAxis))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Palette.color(.chartReadoutBackground), in: RoundedRectangle(cornerRadius: 6))
        .frame(width: labelWidth, height: labelHeight)
        .position(x: labelX + labelWidth / 2, y: labelY + labelHeight / 2)
        .allowsHitTesting(false)
    }
    #endif

    /// The base chart with plot style and scales
    private var baseChart: some View {
        Chart {
            // Show the live spectrum line during capture phases so the user can see the
            // waveform they need to tap. Suppress it during review phases — only the
            // frozen phase overlays and peak annotations should be visible then.
            if !isReviewingMaterialPhase {
                spectrumLineContent
            }
            if !materialSpectra.isEmpty {
                materialSpectraContent
            }
            modeBoundaryContent
            peakAnnotationContent
            thresholdLinesContent
        }
        // Charts warns and falls back when handed an EMPTY scale, and this chart re-renders once
        // per FFT frame — thousands of warnings in guitar mode, where materialSpectra is always [].
        // The series content above is already guarded by `if !materialSpectra.isEmpty`; this
        // modifier was not. A single placeholder keeps the scale non-empty and shows nothing,
        // because the legend is hidden on the next line.
        .chartForegroundStyleScale(
            domain: materialSpectra.isEmpty ? [""] : materialSpectra.map { $0.label },
            range: materialSpectra.isEmpty ? [Color.clear] : materialSpectra.map { $0.color }
        )
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            // Clipped: the spectrum is drawn through the chart's edges and cut off by them.
            plotArea
                .border(Palette.color(.chartBorder), width: 1)
                .contentShape(Rectangle())
                .clipped()

        }
        // Single chartOverlay on both platforms: annotations, cursor/crosshair readout, and
        // background gestures all share one view tree so highPriorityGesture on annotation
        // labels correctly pre-empts the parent pan/hover gesture.
        .chartOverlay { proxy in
            annotationGeometryWrapper(proxy: proxy)
        }
        // Guard against transient inverted ranges during axis-reset animations.
        // If min >= max (which would produce an invalid ClosedRange and cause
        // SwiftUI Charts to render garbage), fall back to safe sentinel values.
        .chartXScale(domain: minFreq < maxFreq
                        ? Double(minFreq)...Double(maxFreq)
                        : Double(minFreq)...Double(minFreq + 100),
                     type: .linear)
        .chartYScale(domain: minDB < maxDB
                        ? Double(minDB)...Double(maxDB)
                        : Double(minDB)...Double(minDB + 10))
        // Disable SwiftUI Charts' implicit data-change animation.
        // When a new frozen measurement is loaded the chart would otherwise
        // interpolate between the old and new spectrum curves, producing a
        // visible oscillation artifact before settling on the correct shape.
        // The spectrum is a real-time / frozen readout — instant updates are correct.
        .transaction { $0.animation = nil }
    }

    /// X-axis content builder
    @AxisContentBuilder
    private var xAxisContent: some AxisContent {
        let labels = frequencyAxisLabels
        let labelled = AxisTickGenerator.ticksWithLabelRoom(
            labels, min: Double(minFreq), max: Double(maxFreq),
            plotWidth: lastPlotFrame.width, fontSize: Self.frequencyLabelSize)
        // .aligned centres each label under its grid line; the default preset starts the label at the line
        // (and overrides a label's own anchor). A label that would reach past the plot's edge is left out, as in
        // the exported image.
        AxisMarks(preset: .aligned, values: frequencyAxisValues) { value in
            AxisValueLabel(anchor: .top) {
                if let doubleValue = value.as(Double.self), labelled.contains(doubleValue),
                   let label = labels[doubleValue] {
                    Text(label)
                        .font(.system(size: Self.frequencyLabelSize))
                        .foregroundStyle(Palette.color(.chartAxis))
                }
            }
            AxisGridLine(stroke: StrokeStyle(lineWidth: ChartStyle.screen.gridWidth))
                .foregroundStyle(Palette.color(.chartGrid))
        }
    }

    /// Y-axis content builder
    @AxisContentBuilder
    private var yAxisContent: some AxisContent {
        AxisMarks(position: .leading, values: .stride(by: AxisTickGenerator.magnitudeStride(range: Double(maxDB - minDB)))) { value in
            AxisValueLabel().foregroundStyle(Palette.color(.chartAxis))
            AxisGridLine(stroke: StrokeStyle(lineWidth: ChartStyle.screen.gridWidth))
                .foregroundStyle(Palette.color(.chartGrid))
        }
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
        peaks: samplePeaks,
        showModeBoundaries: true,
        annotationOffsets: $annotationOffsets
    )
    .frame(height: 300)
    .padding()
}

// MARK: - The chart's menu

/// One item of the chart's menu, ready to show: its entry, what it does here, and whether it can act now.
private struct ChartMenuItem {
    let entry: ChartMenuEntry
    let action: () -> Void
    var isEnabled = true
    var title: String { entry.title }
    var symbol: String { entry.symbol }
}

/// The chart's menu items, with a separator between groups.
private struct ChartMenuItems: View {
    let groups: [[ChartMenuItem]]

    var body: some View {
        ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
            if index > 0 { Divider() }
            ForEach(group, id: \.title) { item in
                Button(action: item.action) {
                    Label(item.title, systemImage: item.symbol)
                }
                .disabled(!item.isEnabled)
            }
        }
    }
}

/// The chart's ⋯ menu. It compares itself by what it shows — its items' names and whether each can act — not by
/// their actions: a live frame redraws the chart around it many times a second, and a menu redrawn while it is open
/// snaps back to its top on iOS.
private struct ChartMenuButton: View, Equatable {
    let groups: [[ChartMenuItem]]

    static func == (a: Self, b: Self) -> Bool { a.shown == b.shown }

    private var shown: [[String]] { groups.map { $0.map { "\($0.title)|\($0.isEnabled)" } } }

    var body: some View {
        Menu {
            ChartMenuItems(groups: groups)
        } label: {
            Image(systemName: "ellipsis.circle").font(.caption)
        }
        .menuStyle(.button)
        .buttonStyle(.icon())
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Chart options")
    }
}

// MARK: - The chart's help

/// The chart's help: the lines that work on the device in use (`ChartHelp`). It scrolls when the screen is too short
/// to show it whole. It depends on nothing a live frame changes, so it is equal to itself: the frame, which redraws
/// the chart around it, leaves it — and how far it is scrolled — alone.
private struct ChartHelpView: View, Equatable {
    private let groups = ChartHelp.shown(on: ChartHelp.current)

    static func == (a: Self, b: Self) -> Bool { true }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(minWidth: 300)
        .paletteSurface(.backgroundPanel)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ChartHelp.title)
                .font(.headline)
                .padding(.bottom, 2)
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { PaletteDivider() }
                ForEach(group, id: \.gesture) { line in
                    (Text(line.gesture) + Text(": \(line.effect)").foregroundColor(Palette.color(.textSecondary)))
                        .font(.callout)
                }
            }
        }
        .padding()
        .fixedSize(horizontal: false, vertical: true)
    }
}
