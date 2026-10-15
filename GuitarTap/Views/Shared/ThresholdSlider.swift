//
//  ThresholdSlider.swift
//  GuitarTap
//
//  SwiftUI view that displays a horizontal level meter inside a slider
//  groove with a draggable threshold handle, peak-hold dot, and clipping
//  indicator.  Mirrors Python `ThresholdSlider` (PySide6 QSlider subclass)
//  in `views/shared/threshold_slider.py`.
//
//  Used for the tap-detection threshold control across all measurement
//  types (guitar, plate, brace), since detection now compares the audio
//  RMS magnitude (not the FFT-peak magnitude) — making a level meter the
//  natural way to show the user what the threshold is being compared
//  against.
//
// @parity view/threshold-slider

import Combine
import SwiftUI

/// Horizontal slider with an integrated input-level meter, peak-hold dot,
/// and clipping indicator.
///
/// - The level fill (cyan→blue gradient) spans from `range.lowerBound`
///   to the current input level (dB).
/// - A bright amber dot tracks the recent peak; it snaps up immediately to
///   any new high, holds for `peakHoldSeconds`, then decays at
///   `peakDecayDBPerSec`.
/// - While the input is clipping, the rightmost `clipZoneFraction` of
///   the groove is overlaid with red.
/// - The threshold handle (red vertical bar) is draggable along the dB axis.
struct ThresholdSlider: View {

    // MARK: - Bindings & inputs

    /// The threshold value in dB.  Two-way bound to the analyzer's
    /// `tapDetectionThreshold`.
    @Binding var value: Float

    /// The engine's input level, observed here alone: it is published on every audio buffer, so
    /// only the slider is redrawn for it, not the view around it.
    @ObservedObject var inputLevel: InputLevel

    /// Current input RMS level in dB (e.g. -80…0).
    private var level: Float { inputLevel.inputLevelDB }

    /// True while the input is clipping (any chunk in the last ~1.5 s
    /// reached full scale).  Drives the red clipping zone at the right
    /// edge of the groove.
    private var isClipping: Bool { inputLevel.isClipping }

    /// dB range mapped onto the slider's pixel width.  Typically `-80...(-20)`.
    var range: ClosedRange<Float>

    // MARK: - Visual / behaviour constants (mirror Python defaults)

    private let peakHoldSeconds: TimeInterval = 0.5
    private let peakDecayDBPerSec: Float = 20.0
    private let clipZoneFraction: CGFloat = 0.10
    private let grooveHeight: CGFloat = 14
    private let handleWidth: CGFloat = 4
    private let handleHeight: CGFloat = 22
    private let peakDotRadius: CGFloat = 3.5
    private let totalHeight: CGFloat = 24

    // MARK: - Internal peak-hold state

    @State private var peakHoldDB: Float = -120
    /// When the peak was set and when it was last updated. Held by reference so that updating them
    /// does not redraw the slider — only a change of the dot (`peakHoldDB`) does.
    @State private var peakTiming = PeakTiming()

    private final class PeakTiming {
        var setTime: Date = .distantPast
        var lastUpdate: Date = Date()
    }

    // MARK: - View

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                // ── Background groove ──────────────────────────────
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.color(.meterGroove))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Palette.color(.meterGrooveBorder), lineWidth: 1)
                    )
                    .frame(height: grooveHeight)

                // ── Level fill ────────────────────────────────────
                let fillW = max(0, dbToX(level, width: width))
                if fillW > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Palette.color(.meterLevelTop),
                                    Palette.color(.meterLevelMiddle),
                                    Palette.color(.meterLevelBottom),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: fillW, height: grooveHeight - 2)
                        .padding(.vertical, 1)
                }

                // ── Clipping zone (rightmost N%) ──────────────────
                if isClipping {
                    let clipW = max(2, width * clipZoneFraction)
                    Rectangle()
                        .fill(Palette.color(.meterClip))
                        .frame(width: clipW, height: grooveHeight - 2)
                        .padding(.vertical, 1)
                        .offset(x: width - clipW)
                }

                // ── Tick marks every 10 dB ────────────────────────
                ForEach(tickValues, id: \.self) { tick in
                    Rectangle()
                        .fill(Palette.color(.meterTicks))
                        .frame(width: 1, height: grooveHeight - 4)
                        .offset(x: dbToX(Float(tick), width: width) - 0.5)
                }

                // ── Peak-hold dot ─────────────────────────────────
                if peakHoldDB > range.lowerBound {
                    Circle()
                        .fill(Palette.color(.meterPeakHold))
                        .overlay(Circle().stroke(Palette.color(.meterPeakHoldBorder), lineWidth: 1))
                        .frame(width: peakDotRadius * 2, height: peakDotRadius * 2)
                        .offset(
                            x: dbToX(peakHoldDB, width: width) - peakDotRadius,
                            y: (grooveHeight / 2) - peakDotRadius
                        )
                }

                // ── Threshold handle (draggable red bar) ──────────
                Rectangle()
                    .fill(Palette.color(.meterThresholdHandle))
                    .overlay(Rectangle().stroke(Palette.color(.meterThresholdHandleBorder), lineWidth: 1))
                    .frame(width: handleWidth, height: handleHeight)
                    .offset(
                        x: dbToX(value, width: width) - handleWidth / 2,
                        y: (grooveHeight - handleHeight) / 2
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let newDB = xToDB(Float(drag.location.x), width: Float(width))
                                value = max(range.lowerBound, min(range.upperBound, newDB))
                            }
                    )
            }
            // Click anywhere in the groove to jump the handle there.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let newDB = xToDB(Float(drag.location.x), width: Float(width))
                        value = max(range.lowerBound, min(range.upperBound, newDB))
                    }
            )
        }
        .frame(height: totalHeight)
        // Drive the peak-hold decay from every level the engine publishes — one per audio buffer,
        // whether or not the value changed — as Python's set_level_db and the web's meter do. The
        // decay is incremental over the wall clock, so its rate does not depend on how often levels
        // arrive.
        .onReceive(inputLevel.$inputLevelDB) { newLevel in
            updatePeakHold(newLevel: newLevel)
        }
    }

    // MARK: - Helpers

    /// Map a dB value to a pixel x-coordinate within the groove width.
    private func dbToX(_ db: Float, width: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let frac = max(0, min(1, (db - range.lowerBound) / span))
        return CGFloat(frac) * width
    }

    /// Map a pixel x-coordinate (within groove width) back to a dB value.
    private func xToDB(_ x: Float, width: Float) -> Float {
        guard width > 0 else { return range.lowerBound }
        let frac = max(0, min(1, x / width))
        let span = range.upperBound - range.lowerBound
        return range.lowerBound + frac * span
    }

    /// 10-dB tick mark positions strictly between the slider min and max.
    private var tickValues: [Int] {
        let lo = Int(range.lowerBound)
        let hi = Int(range.upperBound)
        return stride(from: lo + 10, to: hi, by: 10).map { $0 }
    }

    /// Updates `peakHoldDB` based on `newLevel` and elapsed wall-clock time.
    /// Snaps up immediately to a new high, holds for `peakHoldSeconds`,
    /// then decays at `peakDecayDBPerSec` toward `newLevel`.
    private func updatePeakHold(newLevel: Float) {
        let now = Date()
        var peak = peakHoldDB
        if now.timeIntervalSince(peakTiming.setTime) > peakHoldSeconds {
            let dt = max(0, now.timeIntervalSince(peakTiming.lastUpdate))
            peak -= peakDecayDBPerSec * Float(dt)
        }
        if newLevel > peak {
            peak = newLevel
            peakTiming.setTime = now
        }
        if peak < newLevel {
            peak = newLevel
        }
        peakTiming.lastUpdate = now
        if peak != peakHoldDB { peakHoldDB = peak }
    }
}
