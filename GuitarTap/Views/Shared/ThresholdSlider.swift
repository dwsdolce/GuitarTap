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
/// - The level fill (cyan→blue gradient) spans from ``range.lowerBound``
///   to the current ``level`` (dB).
/// - A bright amber dot tracks the recent peak; it snaps up immediately to
///   any new high, holds for ``peakHoldSeconds``, then decays at
///   ``peakDecayDBPerSec``.
/// - When ``isClipping`` is `true`, the rightmost ``clipZoneFraction`` of
///   the groove is overlaid with red.
/// - The threshold handle (red vertical bar) is draggable along the dB axis.
struct ThresholdSlider: View {

    // MARK: - Bindings & inputs

    /// The threshold value in dB.  Two-way bound to the analyzer's
    /// `tapDetectionThreshold`.
    @Binding var value: Float

    /// Current input RMS level in dB (e.g. -80…0).  Updates at ~43 Hz from
    /// `RealtimeFFTAnalyzer.inputLevelDB`.
    var level: Float

    /// True while the input is clipping (any chunk in the last ~1.5 s
    /// reached full scale).  Drives the red clipping zone at the right
    /// edge of the groove.
    var isClipping: Bool

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
    @State private var peakSetTime: Date = .distantPast
    @State private var lastUpdateTime: Date = Date()

    // MARK: - View

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                // ── Background groove ──────────────────────────────
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.gray.opacity(0.6), lineWidth: 1)
                    )
                    .frame(height: grooveHeight)

                // ── Level fill ────────────────────────────────────
                let fillW = max(0, dbToX(level, width: width))
                if fillW > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.4, green: 0.8, blue: 1.0),
                                    Color(red: 0.0, green: 0.4, blue: 0.8),
                                    Color(red: 0.0, green: 0.12, blue: 0.31),
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
                        .fill(Color.red.opacity(0.85))
                        .frame(width: clipW, height: grooveHeight - 2)
                        .padding(.vertical, 1)
                        .offset(x: width - clipW)
                }

                // ── Tick marks every 10 dB ────────────────────────
                ForEach(tickValues, id: \.self) { tick in
                    Rectangle()
                        .fill(Color(red: 0.24, green: 0.55, blue: 0.24).opacity(0.7))
                        .frame(width: 1, height: grooveHeight - 4)
                        .offset(x: dbToX(Float(tick), width: width) - 0.5)
                }

                // ── Peak-hold dot ─────────────────────────────────
                if peakHoldDB > range.lowerBound {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.78, blue: 0.0))
                        .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1))
                        .frame(width: peakDotRadius * 2, height: peakDotRadius * 2)
                        .offset(
                            x: dbToX(peakHoldDB, width: width) - peakDotRadius,
                            y: (grooveHeight / 2) - peakDotRadius
                        )
                }

                // ── Threshold handle (draggable red bar) ──────────
                Rectangle()
                    .fill(Color.red)
                    .overlay(Rectangle().stroke(Color(red: 0.5, green: 0, blue: 0), lineWidth: 1))
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
        // Drive peak-hold decay on every level update.  Mirrors Python's
        // ThresholdSlider.set_level_db where decay is incremental over wall
        // clock so the rate is independent of update frequency.
        .onChange(of: level) {
            updatePeakHold(newLevel: level)
        }
        // Also tick a periodic timer so the peak dot continues to decay
        // even when the level signal is steady (no onChange fires).
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            updatePeakHold(newLevel: level)
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
        if now.timeIntervalSince(peakSetTime) > peakHoldSeconds {
            let dt = max(0, now.timeIntervalSince(lastUpdateTime))
            peakHoldDB -= peakDecayDBPerSec * Float(dt)
        }
        if newLevel > peakHoldDB {
            peakHoldDB = newLevel
            peakSetTime = now
        }
        if peakHoldDB < newLevel {
            peakHoldDB = newLevel
        }
        lastUpdateTime = now
    }
}
