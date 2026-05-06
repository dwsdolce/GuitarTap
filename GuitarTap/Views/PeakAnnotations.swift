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
/// ## Position Calculation
///
/// Label positions are computed from chart coordinates using the current axis
/// ranges. Both linear and logarithmic frequency scales are supported:
///
/// - **Linear X**: `freqNormalized = (freq - minFreq) / (maxFreq - minFreq)`
/// - **Log X**: `freqNormalized = (log10(freq) - log10(min)) / (log10(max) - log10(min))`
/// - **Y**: `dbNormalized = (clampedMag - minDB) / (maxDB - minDB)` — inverted
///   because SwiftUI's coordinate system has y=0 at the top.
///
/// The default label position is 70 pt above the peak marker. Users can drag
/// labels anywhere; accumulated offsets are stored as `[UUID: CGPoint]` and
/// passed back via `onOffsetChange`. Positions are cached in `@State` to avoid
/// redundant recalculation during drag.
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
/// User-assigned mode overrides are shown in italic with a pencil badge.
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
    /// When `true`, the frequency axis is logarithmic.
    let isLogarithmic: Bool
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
    var modeOverrides: [UUID: UserAssignedMode] = [:]

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
    }
}

// MARK: - Draggable Peak Annotation

/// Per-peak label that the user can drag to any position on the chart.
///
/// Position state is managed as a two-part sum:
/// 1. A persisted `offset: CGPoint` stored in `TapToneAnalyzer.peakAnnotationOffsets`
///    (survives view re-creation and measurement loads).
/// 2. A transient `dragOffset: CGSize` accumulated live during an active drag
///    gesture and merged into `offset` on `.onEnded`.
///
/// Label and peak positions are pure computed properties derived from the current
/// axis ranges and plot frame, so they stay correct automatically on every render.
/// During a drag they are frozen (`frozenChartPosition`/`frozenPeakPosition`) so
/// that axis-range changes mid-gesture don't shift the label under the finger/cursor.
struct DraggablePeakAnnotation: View {
    /// The peak this annotation describes.
    let peak: ResonantPeak
    /// Pre-computed context-aware mode (from ``GuitarMode/classifyAll(_:guitarType:)``).
    /// When provided, used instead of the per-frequency ``GuitarMode/classify(frequency:)``
    /// so that peaks in overlapping mode ranges display distinct labels.
    var classifiedMode: GuitarMode? = nil
    /// Persisted label position in absolute data-space (x = Hz, y = dB).
    /// `.zero` means no saved position; the default (70pt above peak) is used instead.
    let offset: CGPoint
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
    /// When `true`, frequency-to-X mapping uses a log10 transform.
    let isLogarithmic: Bool
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
    var modeOverrides: [UUID: UserAssignedMode] = [:]

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

    /// Label origin frozen at drag-start so positions don't jump mid-gesture. `nil` when not dragging.
    @State private var frozenChartPosition: CGPoint? = nil
    /// Peak marker position frozen at drag-start. `nil` when not dragging.
    @State private var frozenPeakPosition: CGPoint? = nil

    private var modeColor: Color {
        if measurementType.isGuitar {
            // Freeform user-defined label → teal.
            if case .assigned(let label) = modeOverrides[peak.id],
               GuitarMode.fromDisplayName(label) == nil {
                return GuitarMode.userDefinedColor
            }
            // Use context-aware classification if provided; fall back to per-frequency lookup.
            let mode = (classifiedMode ?? .unknown).normalized
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
            // Plate/brace mode: color by L/C selection
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

    /// Current label origin in view coordinates (the default 70pt-above-peak position, ignoring any stored offset).
    /// Returns the drag-frozen value while a drag is active; otherwise computes fresh from current axis ranges.
    /// No `@State` writes needed — positions update automatically on every render when props change.
    private var chartPosition: CGPoint {
        frozenChartPosition ?? calculateChartPosition()
    }

    /// Current peak marker position in view coordinates.
    /// Returns the drag-frozen value while a drag is active; otherwise computes fresh.
    private var peakPosition: CGPoint {
        frozenPeakPosition ?? calculatePeakPosition()
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

    /// Final position including user offset and drag.
    ///
    /// `offset` is stored in **absolute** data-space (x = Hz, y = dB); convert to
    /// pixels using the current axis ranges and plot frame.
    /// When `offset == .zero` (no stored position), falls back to `chartPosition`
    /// (the 70pt-above-peak default).
    /// `dragOffset` is a transient live-drag value already in pixels.
    private var finalPosition: CGPoint {
        let freqRange = CGFloat(maxFreq - minFreq)
        let dbRange   = CGFloat(maxDB   - minDB)
        guard plotFrame.width > 0, plotFrame.height > 0, freqRange > 0, dbRange > 0 else {
            return CGPoint(x: chartPosition.x + dragOffset.width,
                           y: chartPosition.y + dragOffset.height)
        }
        if offset == .zero {
            // No saved position — use default (70pt above peak) plus any live drag.
            return CGPoint(
                x: chartPosition.x + dragOffset.width,
                y: chartPosition.y + dragOffset.height
            )
        }
        // Convert absolute data-space position to pixels.
        let absX = plotFrame.minX + ((CGFloat(offset.x) - CGFloat(minFreq)) / freqRange) * plotFrame.width
        let absY = plotFrame.minY + (1.0 - (CGFloat(offset.y) - CGFloat(minDB)) / dbRange) * plotFrame.height
        return CGPoint(x: absX + dragOffset.width, y: absY + dragOffset.height)
    }

    var body: some View {
        // Separate the connection line and label into distinct layers
        ZStack(alignment: .topLeading) {
            // Connection line layer - never hittable (visual only)
            if peakPosition.x.isFinite && peakPosition.y.isFinite &&
               chartPosition.x.isFinite && chartPosition.y.isFinite &&
               chartPosition != .zero {
                ConnectionLine(
                    from: peakPosition,
                    to: CGPoint(
                        x: finalPosition.x,
                        y: finalPosition.y + 30
                    ),
                    color: modeColor
                )
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
            .position(finalPosition)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            isAnnotationDragging = true
                            // Freeze positions at drag start so they don't shift mid-gesture
                            frozenChartPosition = calculateChartPosition()
                            frozenPeakPosition = calculatePeakPosition()
                            #if os(macOS)
                            NSCursor.closedHand.set()
                            #endif
                        }
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        // Store the absolute data-space position of the label center.
                        // Take the current finalPosition (which incorporates the live
                        // dragOffset), then convert from pixels back to data-space (Hz, dB).
                        let freqRange = CGFloat(maxFreq - minFreq)
                        let dbRange   = CGFloat(maxDB   - minDB)
                        let dataOffset: CGPoint
                        if plotFrame.width > 0, plotFrame.height > 0, freqRange > 0, dbRange > 0 {
                            // finalPosition before dragOffset is cleared gives the pixel
                            // position of the label center at drag-end.
                            let endPixelX = finalPosition.x
                            let endPixelY = finalPosition.y
                            // Convert pixels → absolute data-space.
                            let absHz = CGFloat(minFreq) + ((endPixelX - plotFrame.minX) / plotFrame.width)  * freqRange
                            let absDB = CGFloat(minDB)   + (1.0 - (endPixelY - plotFrame.minY) / plotFrame.height) * dbRange
                            dataOffset = CGPoint(x: absHz, y: absDB)
                        } else {
                            dataOffset = .zero
                        }

                        // Disable animation for smoother dragging
                        #if os(macOS)
                        // Restore open-hand cursor after drag ends (pointer is still over the label)
                        NSCursor.openHand.set()
                        #endif
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            onOffsetChange(dataOffset)
                            isDragging = false
                            isAnnotationDragging = false
                        }
                        dragOffset = .zero
                        // Release frozen positions — computed properties take over again
                        frozenChartPosition = nil
                        frozenPeakPosition = nil
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
                Button(action: onReset) {
                    Label("Reset Position", systemImage: "arrow.counterclockwise")
                }
                .disabled(!isMoved)
            }
            #if os(macOS)
            .help(isMoved ? "Drag to adjust • Right-click to reset position" : "Drag to reposition label")
            #endif
        }

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
    /// Ending point — the bottom centre of the label badge.
    let to: CGPoint
    /// The mode color used for the stroke.
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

/// The visual badge rendered for each peak: mode name, optional pitch info,
/// frequency (Hz), and magnitude (dBFS).
///
/// The badge border thickens during hover (`1.5 pt` → `2 pt`) and drag
/// (`2.5 pt`), providing clear visual feedback. When the label has a
/// user-assigned mode override the mode name is shown in italic with a
/// pencil-circle badge icon.
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
    var modeOverrides: [UUID: UserAssignedMode] = [:]

    /// Whether this peak has a user-assigned label
    private var isManualOverride: Bool {
        if case .assigned = modeOverrides[peak.id] { return true }
        return false
    }

    /// The mode label to display - user override, guitar mode name, or plate/brace mode (L/C/FLC)
    private var modeLabel: String {
        if measurementType.isGuitar {
            switch modeOverrides[peak.id] ?? .auto {
            case .auto:
                return (classifiedMode ?? .unknown).displayName
            case .assigned(let label):
                return label
            }
        } else {
            // Plate/brace mode labels
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
            // Mode label (guitar mode or plate L/C), italic when manually overridden
            HStack(spacing: 3) {
                Text(modeLabel)
                    .font(isManualOverride ? .caption2.italic() : .caption2)
                    .fontWeight(.bold)
                    .foregroundColor(modeColor)
                if isManualOverride {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 7))
                        .foregroundColor(modeColor.opacity(0.8))
                }
            }

            // Pitch information if available (only show for guitar mode)
            if measurementType.isGuitar, let pitchNote = peak.pitchNote, let pitchCents = peak.pitchCents {
                let sign = pitchCents >= 0 ? "+" : ""
                HStack(spacing: 2) {
                    Image(systemName: "music.note")
                        .font(.system(size: 8))
                        .foregroundColor(.purple)
                    Text(pitchNote)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.purple)
                    Text("\(sign)\(Int(round(pitchCents))) ¢")
                        .font(.caption2)
                        .foregroundColor(.purple.opacity(0.8))
                }
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
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(modeColor, lineWidth: isDragging ? 2.5 : (isHovering ? 2 : 1.5))
        )
        .shadow(color: .black.opacity(0.15), radius: 4)
        .contentShape(Rectangle())
    }
}
