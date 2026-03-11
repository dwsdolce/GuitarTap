//
//  PeakAnnotations.swift
//  GuitarTap
//
//  Draggable peak annotation views used in the spectrum chart overlay.
//

import SwiftUI

// MARK: - Peak Annotations Overlay

/// A container view for all peak annotations
struct PeakAnnotationsOverlay: View {
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

    // Plate/brace measurement mode support
    let measurementType: MeasurementType
    let selectedLongitudinalPeakID: UUID?
    let selectedCrossPeakID: UUID?
    let selectedFlcPeakID: UUID?

    // Per-peak user mode overrides (empty = all peaks use auto-classification)
    var modeOverrides: [UUID: UserAssignedMode] = [:]

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

    // Plate/brace measurement mode support
    let measurementType: MeasurementType
    let selectedLongitudinalPeakID: UUID?
    let selectedCrossPeakID: UUID?
    let selectedFlcPeakID: UUID?

    // Per-peak user mode overrides (empty = all peaks use auto-classification)
    var modeOverrides: [UUID: UserAssignedMode] = [:]

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
            #if os(iOS)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    onReset()
                }
            )
            #endif
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

    // Plate/brace measurement mode support
    let measurementType: MeasurementType
    let isLongitudinal: Bool
    let isCross: Bool
    var isFlc: Bool = false

    // Per-peak user mode overrides (empty = auto-classification)
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
                return GuitarMode.classify(frequency: peak.frequency).displayName
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
