// @parity view/peak-annotations
//
//  PeakAnnotations.swift
//  GuitarTap
//

/// # PeakAnnotations
///
/// Draggable peak annotation labels and connection-line views overlaid on the
/// live spectrum chart.
///
/// ## Component Hierarchy
///
/// ```
/// PeakAnnotationsOverlay          (container — iterates all visible peaks)
/// └── DraggablePeakAnnotation     (per-peak drag/hover/context-menu handler)
///     ├── ConnectionLine          (dashed line from peak to label)
///     └── PeakAnnotationLabel     (badge: mode name, pitch, frequency, dBFS)
/// ```
///
/// ## Position
///
/// A label is a point in chart units: its centre is where it was dragged, else its peak plus
/// ``TapToneAnalyzer/defaultAnnotationOffset`` (``TapToneAnalyzer/annotationCentre(for:offsets:)``),
/// placed on screen by the current axis ranges (``PlotMapping``). Every label the annotation mode shows
/// is drawn, wherever its peak is; the overlay is cut at the plot's edges (``PlotArea``), and a label is
/// never moved to stay inside. Its line runs from the peak's dot to the label's centre, under the label.
///
/// ## Gesture Handling
///
/// - **Drag**: moves the label; offset is committed on `.onEnded`.
/// - **Double-tap (iOS)**: resets the label to its default position.
/// - **Right-click (macOS)**: presents a context menu with "Reset Position".
/// - **Hover (macOS)**: highlights the border and changes cursor to open-hand.
///
/// ## Peak Coloring
///
/// Color is determined by `modeColor` in `DraggablePeakAnnotation`:
/// - Guitar measurements: Air=cyan, Top=green, Back=orange, Dipole=red, etc.
/// - Plate/brace measurements: L=blue, C=orange, FLC=purple, unselected=secondary.
///
/// User-assigned mode overrides are shown in italic with a trailing " *".
///
/// - SeeAlso: `SpectrumView`, `TapToneAnalyzer.peakAnnotationOffsets`

import SwiftUI

// MARK: - Peak Annotations Overlay

/// A `ZStack` container that renders a `DraggablePeakAnnotation` for every
/// visible peak. It forwards the shared axis-range parameters and annotation
/// offset bindings to each child.
struct PeakAnnotationsOverlay: View {
    /// The peaks to annotate.
    let peaks: [ResonantPeak]
    /// Two-way binding to the persisted label positions dictionary (absolute data-space: x = Hz, y = dB).
    let annotationOffsets: Binding<[UUID: CGPoint]>
    /// Full view geometry used to resolve chart-relative coordinates.
    let geometry: GeometryProxy
    /// The rendered plot area within the containing view.
    let plotFrame: CGRect
    /// Minimum displayed frequency (Hz).
    let minFreq: Float
    /// Maximum displayed frequency (Hz).
    let maxFreq: Float
    /// Minimum displayed magnitude (dBFS).
    let minDB: Float
    /// Maximum displayed magnitude (dBFS).
    let maxDB: Float
    /// Set to `true` while any annotation is being dragged; used to suppress
    /// chart interactions during a drag gesture.
    @Binding var isAnnotationDragging: Bool

    // Plate/brace measurement mode support
    /// Active measurement type (guitar, plate, or brace).
    let measurementType: MeasurementType
    /// ID of the peak assigned as the longitudinal (L) mode.
    let selectedLongitudinalPeakID: UUID?
    /// ID of the peak assigned as the cross-grain (C) mode.
    let selectedCrossPeakID: UUID?
    /// ID of the peak assigned as the FLC (diagonal) mode.
    let selectedFlcPeakID: UUID?

    /// Per-peak user-assigned mode overrides. Empty = auto-classification.
    var modeOverrides: [UUID: String] = [:]

    /// Pre-computed mode assignments from the analyzer (keyed by peak UUID).
    ///
    /// When non-empty this map is used directly, ensuring annotations show the
    /// same mode labels as the Results panel (both derived from the same
    /// ``GuitarMode/classifyAll(_:guitarType:)`` call on the full peak set).
    /// Falls back to a local `classifyAll(peaks)` call only when empty
    /// (e.g. in standalone Previews or legacy call sites).
    var peakModes: [UUID: GuitarMode] = [:]

    /// Context-aware mode map: uses the pre-computed `peakModes` when available,
    /// otherwise falls back to classifying the visible subset locally.
    private var peakModeMap: [UUID: GuitarMode] {
        guard measurementType.isGuitar else { return [:] }
        return peakModes.isEmpty ? GuitarMode.classifyAll(peaks) : peakModes
    }

    var body: some View {
        ZStack {
            ForEach(peaks) { peak in
                DraggablePeakAnnotation(

                    peak: peak,
                    classifiedMode: peakModeMap[peak.id],
                    centre: TapToneAnalyzer.annotationCentre(for: peak, offsets: annotationOffsets.wrappedValue),
                    isMoved: annotationOffsets.wrappedValue[peak.id] != nil,
                    chartGeometry: geometry,
                    plotFrame: plotFrame,
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
        // Cut at the plot's edges, the labels and their lines alike.
        .clipShape(PlotArea(rect: plotFrame))
    }
}

/// The plot area as a shape, for cutting what is drawn over the chart at the plot's edges.
struct PlotArea: Shape {
    let rect: CGRect
    func path(in _: CGRect) -> Path { Path(rect) }
}

/// Between chart units (Hz, dB) and points in the view, for a plot area and its axis ranges.
struct PlotMapping {
    let plot: CGRect
    let minFreq: Float
    let maxFreq: Float
    let minDB: Float
    let maxDB: Float

    private var valid: Bool {
        plot.width > 0 && plot.height > 0 && maxFreq > minFreq && maxDB > minDB
    }

    /// The view point of (`hz`, `db`) — outside the plot when the point is outside the ranges; nil
    /// while the plot or a range is empty.
    func point(hz: CGFloat, db: CGFloat) -> CGPoint? {
        guard valid else { return nil }
        return CGPoint(x: plot.minX + (hz - CGFloat(minFreq)) / CGFloat(maxFreq - minFreq) * plot.width,
                       y: plot.minY + (1 - (db - CGFloat(minDB)) / CGFloat(maxDB - minDB)) * plot.height)
    }

    /// The chart units (x Hz, y dB) of a view point; nil while the plot or a range is empty.
    func data(at point: CGPoint) -> CGPoint? {
        guard valid else { return nil }
        return CGPoint(x: CGFloat(minFreq) + (point.x - plot.minX) / plot.width * CGFloat(maxFreq - minFreq),
                       y: CGFloat(minDB) + (1 - (point.y - plot.minY) / plot.height) * CGFloat(maxDB - minDB))
    }
}

// MARK: - Draggable Peak Annotation

/// Per-peak label that the user can drag to any position on the chart.
///
/// Its position is the sum of:
/// 1. `centre`, in chart units (``TapToneAnalyzer/annotationCentre(for:offsets:)``) — where it was
///    dragged, else its peak plus the default offset.
/// 2. A transient `dragOffset: CGSize` accumulated live during an active drag gesture; on `.onEnded`
///    the label's centre, in chart units, is stored as its dragged position.
///
/// During a drag the label's centre on screen is frozen (`frozenCentre`) so axis-range changes
/// mid-gesture don't shift the label under the finger/cursor. The PEAK position is deliberately
/// NOT frozen — the dot doesn't move while you drag its label, so the connecting line must keep
/// tracking it live or it visibly detaches and snaps back on release.
struct DraggablePeakAnnotation: View {
    /// The peak this annotation describes.
    let peak: ResonantPeak
    /// Pre-computed context-aware mode (from ``GuitarMode/classifyAll(_:guitarType:)``).
    /// When provided, used instead of the per-frequency `GuitarMode.classify(frequency:guitarType:)`
    /// so that peaks in overlapping mode ranges display distinct labels.
    var classifiedMode: GuitarMode? = nil
    /// The label's centre in chart units (x = Hz, y = dB).
    let centre: CGPoint
    /// Whether the label has been dragged: it has a stored position.
    let isMoved: Bool
    /// Full view geometry, used to resolve `plotFrame` origin.
    let chartGeometry: GeometryProxy
    /// The chart's rendered plot area within the containing view.
    let plotFrame: CGRect
    /// Minimum displayed frequency (Hz).
    let minFreq: Float
    /// Maximum displayed frequency (Hz).
    let maxFreq: Float
    /// Minimum displayed magnitude (dBFS).
    let minDB: Float
    /// Maximum displayed magnitude (dBFS).
    let maxDB: Float
    /// Propagated to the parent so it can suppress chart interactions.
    @Binding var isAnnotationDragging: Bool

    // Plate/brace measurement mode support
    /// Active measurement type.
    let measurementType: MeasurementType
    /// ID of the longitudinal (L) peak, if assigned.
    let selectedLongitudinalPeakID: UUID?
    /// ID of the cross-grain (C) peak, if assigned.
    let selectedCrossPeakID: UUID?
    /// ID of the FLC peak, if assigned.
    let selectedFlcPeakID: UUID?

    /// Per-peak user-assigned mode overrides. Empty = auto-classification.
    var modeOverrides: [UUID: String] = [:]

    /// Called when the drag ends with the new cumulative offset.
    let onOffsetChange: (CGPoint) -> Void
    /// Called to remove this peak's stored offset, returning it to default.
    let onReset: () -> Void

    /// In-flight drag translation (not yet committed to `offset`).
    @State private var dragOffset: CGSize = .zero
    /// `true` while the pointer hovers over this label (macOS).
    @State private var isHovering: Bool = false
    /// `true` during an active drag gesture.
    @State private var isDragging: Bool = false

    /// The label's centre on screen, frozen at drag-start so it doesn't jump mid-gesture. `nil` when not dragging.
    @State private var frozenCentre: CGPoint? = nil

    private var modeColor: Color {
        if measurementType.isGuitar {
            // Freeform user-defined label → teal.
            if let label = modeOverrides[peak.id],
               GuitarMode.fromDisplayName(label) == nil {
                return Palette.userDefined
            }
            // Use context-aware classification if provided; fall back to per-frequency lookup.
            return Palette.color(classifiedMode ?? .unknown)
        } else {
            // Plate/brace mode: color by L/C selection
            if peak.id == selectedLongitudinalPeakID {
                return Palette.color(.materialLongitudinal)
            } else if peak.id == selectedCrossPeakID {
                return Palette.color(.materialCross)
            } else if peak.id == selectedFlcPeakID {
                return Palette.color(.materialFlc)
            } else {
                return Palette.color(.materialUnselected)
            }
        }
    }

    private var mapping: PlotMapping {
        PlotMapping(plot: plotFrame, minFreq: minFreq, maxFreq: maxFreq, minDB: minDB, maxDB: maxDB)
    }

    /// The peak's dot on screen — outside the plot when the peak is outside the ranges, where the
    /// plot's edge cuts the line. NOT frozen during a drag: the dot does not move while you drag its
    /// label, so the line's start must keep tracking it live.
    private var peakPosition: CGPoint? {
        mapping.point(hz: CGFloat(peak.frequency), db: CGFloat(peak.magnitude))
    }

    /// The label's centre on screen, including any live drag.
    private var finalPosition: CGPoint? {
        guard let centrePoint = frozenCentre ?? mapping.point(hz: centre.x, db: centre.y) else { return nil }
        return CGPoint(x: centrePoint.x + dragOffset.width, y: centrePoint.y + dragOffset.height)
    }

    var body: some View {
        // Separate the connection line and label into distinct layers
        ZStack(alignment: .topLeading) {
            // The line from the peak's dot to the label's centre, drawn first so the label covers its
            // end — never hittable (visual only).
            if let peakPosition, let finalPosition {
                ConnectionLine(from: peakPosition, to: finalPosition, color: modeColor)
                    .allowsHitTesting(false)
            }

            // The annotation content - positioned independently.
            // The GeometryReader background is applied BEFORE .position() so it measures
            // the label's natural size (not the full parent frame).
            PeakAnnotationLabel(
                peak: peak,
                modeColor: modeColor,
                classifiedMode: classifiedMode,
                isHovering: isHovering,
                isDragging: isDragging,
                isMoved: isMoved,
                measurementType: measurementType,
                isLongitudinal: peak.id == selectedLongitudinalPeakID,
                isCross: peak.id == selectedCrossPeakID,
                isFlc: peak.id == selectedFlcPeakID,
                modeOverrides: modeOverrides
            )
            // Where the label is on screen, for whatever on the chart must tell a label from the plot.
            .background(GeometryReader { label in
                Color.clear.preference(key: PeakLabelFramesKey.self,
                                       value: [peak.id: label.frame(in: .named(PeakLabelFramesKey.space))])
            })
            .position(finalPosition ?? .zero)
            .opacity(finalPosition == nil ? 0 : 1)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            isAnnotationDragging = true
                            // Freeze the label's centre at drag start so it doesn't shift mid-gesture
                            frozenCentre = mapping.point(hz: centre.x, db: centre.y)
                            #if os(macOS)
                            NSCursor.closedHand.set()
                            #endif
                        }
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        // Store the label's centre at drag-end (finalPosition, before dragOffset is
                        // cleared, includes the live drag) in chart units (Hz, dB).
                        let dataCentre = finalPosition.flatMap { mapping.data(at: $0) }

                        // Disable animation for smoother dragging
                        #if os(macOS)
                        // Restore open-hand cursor after drag ends (pointer is still over the label)
                        NSCursor.openHand.set()
                        #endif
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            if let dataCentre { onOffsetChange(dataCentre) }
                            isDragging = false
                            isAnnotationDragging = false
                        }
                        dragOffset = .zero
                        // Release the frozen centre — the computed position takes over again
                        frozenCentre = nil
                    }
            )
            #if os(iOS)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    onReset()
                }
            )
            #endif
            .onHover { hovering in
                withAnimation(.none) { isHovering = hovering }
            }
            .contextMenu {
                ForEach(ChartMenu.labelMenu, id: \.title) { entry in
                    Button(action: onReset) {
                        Label(entry.title, systemImage: entry.symbol)
                    }
                    .disabled(!isMoved)
                }
                .menuIcons()
            }
            #if os(macOS)
            .help(isMoved ? "Drag to adjust • Right-click to reset position" : "Drag to reposition label")
            #endif
        }

    }
}

/// Each peak label's frame in the chart's coordinate space (``PeakLabelFramesKey/space``).
struct PeakLabelFramesKey: PreferenceKey {
    static let space = "peakLabelChart"
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Connection Line

/// A dashed `Path`-based line connecting a peak marker to its floating label.
///
/// Rendered as a `1.5 pt` stroke with a `[4, 3]` dash pattern in the peak's
/// mode color at 40% opacity. Both endpoints are validated for finite values
/// before drawing to avoid rendering artifacts at zero-size frames.
private struct ConnectionLine: View {
    /// Starting point — the peak marker position.
    let from: CGPoint
    /// Ending point — the centre of the label, which covers the line's end.
    let to: CGPoint
    /// The mode color used for the stroke.
    let color: Color

    var body: some View {
        if from.x.isFinite && from.y.isFinite && to.x.isFinite && to.y.isFinite {
            Path { path in
                path.move(to: from)
                path.addLine(to: to)
            }
            .stroke(color.opacity(ChartStyle.screen.leaderOpacity),
                    style: StrokeStyle(lineWidth: ChartStyle.screen.leaderWidth, dash: ChartStyle.screen.leaderDash))
        }
    }
}

// MARK: - Peak Annotation Label

/// The visual badge rendered for each peak: mode name, optional pitch info,
/// frequency (Hz), and magnitude (dBFS).
///
/// The badge border thickens during hover (`1.5 pt` → `2 pt`) and drag
/// (`2.5 pt`), providing clear visual feedback. When the label has a
/// user-assigned mode override the mode name is shown in italic with a
/// trailing " *".
private struct PeakAnnotationLabel: View {
    /// The peak whose data this label displays.
    let peak: ResonantPeak
    /// The mode color used for the border and mode-name text.
    let modeColor: Color
    /// Pre-computed context-aware mode (from ``GuitarMode/classifyAll(_:guitarType:)``).
    /// Passed through from `DraggablePeakAnnotation` so the label uses the same mode
    /// as the dot color, avoiding the duplicate-Top issue in overlapping ranges.
    var classifiedMode: GuitarMode? = nil
    /// `true` while the pointer hovers over this label (macOS).
    let isHovering: Bool
    /// `true` during an active drag gesture.
    let isDragging: Bool
    /// `true` when the label has been moved from its default position.
    let isMoved: Bool

    // Plate/brace measurement mode support
    /// Active measurement type (guitar, plate, or brace).
    let measurementType: MeasurementType
    /// `true` when this peak is the selected longitudinal (L) mode.
    let isLongitudinal: Bool
    /// `true` when this peak is the selected cross-grain (C) mode.
    let isCross: Bool
    /// `true` when this peak is the selected FLC (diagonal) mode.
    var isFlc: Bool = false

    /// Per-peak user-assigned mode overrides. Empty = auto-classification.
    var modeOverrides: [UUID: String] = [:]

    /// Whether this peak has a user-assigned label
    private var isManualOverride: Bool {
        modeOverrides[peak.id] != nil
    }

    /// The mode label to display - user override, guitar mode name, or plate/brace mode (L/C/FLC)
    private var modeLabel: String {
        if measurementType.isGuitar {
            return modeOverrides[peak.id] ?? (classifiedMode ?? .unknown).displayName
        } else {
            // Plate/brace mode labels
            if isLongitudinal {
                return "Longitudinal"
            } else if isCross {
                return "Cross-grain"
            } else if isFlc {
                return "Diagonal"
            } else {
                return "Peak"  // Unselected peak
            }
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            // Mode label (guitar mode or plate L/C). A manual override is shown italic with a
            // trailing " *" — the one convention used everywhere (list, annotation, PDF, tables).
            // No glyph: at annotation size a small icon was unreadable.
            Text(modeLabel + (isManualOverride ? " *" : ""))
                .font(isManualOverride ? .caption2.italic() : .caption2)
                .fontWeight(.bold)
                .foregroundColor(modeColor)

            // Pitch information if available (only show for guitar mode)
            if measurementType.isGuitar, let pitchNote = peak.pitchNote, let pitchCents = peak.pitchCents {
                let sign = pitchCents >= 0 ? "+" : ""
                HStack(spacing: 2) {
                    Image(systemName: "music.note")
                        .font(.system(size: 8))
                        .foregroundColor(Palette.color(.peakPitch))
                    Text(pitchNote)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(Palette.color(.peakPitch))
                    Text("\(sign)\(Int(round(pitchCents))) ¢")
                        .font(.caption2)
                        .foregroundColor(Palette.color(.peakPitch).opacity(Palette.opacity(.peakPitchCents)))
                }
            }

            Text(peak.frequency.formattedAsFrequency())
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(Palette.color(.chartTitle))

            Text("\(FieldPrecision.string(peak.magnitude, FieldPrecision.peakMagnitudeDB)) dB")
                .font(.caption2)
                .foregroundColor(Palette.color(.chartAxis))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Palette.color(.chartReadoutBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(modeColor, lineWidth: isDragging ? 2.5 : (isHovering ? 2 : ChartStyle.screen.labelBorderWidth))
        )
        .contentShape(Rectangle())
    }
}
