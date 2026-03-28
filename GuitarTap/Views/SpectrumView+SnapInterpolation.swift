/// # SpectrumView+SnapInterpolation
///
/// Cursor/crosshair snap-to-waveform interpolation for `SpectrumView`.
///
/// When the spectrum is frozen (post-tap capture) or when plate/brace
/// multi-phase spectra are displayed, moving the mouse or crosshair over the
/// chart should lock the readout to the nearest waveform rather than showing
/// the raw pointer position.  This file provides the two core algorithms:
///
/// ## Binary search + linear interpolation (`snapToWaveform`)
///
/// The FFT bin array is sorted by frequency (ascending), so a binary search
/// finds the bin index bracketing `targetHz` in O(log n).  The magnitude is
/// then linearly interpolated between the left and right bins:
///
/// ```
/// t = (targetHz - freq[l]) / (freq[r] - freq[l])
/// snappedMag = mag[l] + t * (mag[r] - mag[l])
/// ```
///
/// This produces sub-bin precision without the computational cost of a full
/// parabolic peak finder.
///
/// ## Gravity-based series locking (`nearestSeriesIndex`)
///
/// When multiple spectra are visible (plate/brace phases), the cursor locks to
/// the nearest curve.  To prevent rapid switching when two curves are close,
/// a gravity threshold (`curveGravityThreshold` = 12 pt) applies hysteresis:
/// the currently locked curve is only abandoned when a competitor curve is at
/// least 12 pt closer on screen.
///
/// - SeeAlso: `SpectrumView`, `CursorSnapState`
//
//  SpectrumView+SnapInterpolation.swift
//  GuitarTap
//
//  Spectral interpolation utilities for cursor/crosshair snapping in SpectrumView.
//

import SwiftUI
import Charts

extension SpectrumView {

    // MARK: - Spectral Interpolation Utilities

    /// Snaps a raw cursor frequency to the nearest point on a spectrum waveform
    /// using binary search and linear interpolation.
    ///
    /// ## Algorithm
    /// 1. Binary search the `frequencies` array for the index whose value is
    ///    closest to `targetHz`.
    /// 2. Find the two bracketing bins `[l, r]` such that
    ///    `frequencies[l] ≤ targetHz ≤ frequencies[r]`.
    /// 3. Linearly interpolate both frequency and magnitude between bins `l` and `r`.
    ///
    /// - Parameters:
    ///   - targetHz: The cursor frequency to snap from, in Hz.
    ///   - magnitudes: FFT magnitudes array, in dB, parallel to `frequencies`.
    ///   - frequencies: FFT frequency array, in Hz, in ascending order.
    /// - Returns: The interpolated `(frequency, magnitude)` pair on the waveform,
    ///   or `nil` if the arrays are empty or mismatched.
    static func snapToWaveform(
        targetHz: Float,
        magnitudes: [Float],
        frequencies: [Float]
    ) -> (frequency: Float, magnitude: Float)? {
        guard magnitudes.count == frequencies.count, !frequencies.isEmpty else { return nil }

        // Binary search for the bin closest to targetHz
        var lo = 0
        var hi = frequencies.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if frequencies[mid] < targetHz { lo = mid + 1 } else { hi = mid }
        }
        let nearIdx: Int
        if lo > 0 && abs(frequencies[lo - 1] - targetHz) < abs(frequencies[lo] - targetHz) {
            nearIdx = lo - 1
        } else {
            nearIdx = lo
        }

        // Find the true bracketing pair: l <= targetHz <= r
        let l: Int
        let r: Int
        if nearIdx < frequencies.count - 1 && frequencies[nearIdx] <= targetHz {
            l = nearIdx
            r = nearIdx + 1
        } else if nearIdx > 0 {
            l = nearIdx - 1
            r = nearIdx
        } else {
            return (frequencies[nearIdx], magnitudes[nearIdx])
        }
        let denom = frequencies[r] - frequencies[l]
        guard denom > 0 else { return (frequencies[nearIdx], magnitudes[nearIdx]) }
        let t = (targetHz - frequencies[l]) / denom
        return (frequencies[l] + t * (frequencies[r] - frequencies[l]),
                magnitudes[l]  + t * (magnitudes[r]  - magnitudes[l]))
    }

    /// Screen-distance gravity threshold, in points.
    ///
    /// The currently locked curve is only abandoned in favour of a closer
    /// competitor when the competitor is at least this many screen points
    /// closer.  This prevents the cursor from flickering between two nearly
    /// overlapping curves.
    static let curveGravityThreshold: CGFloat = 12.0

    /// Returns the `materialSpectra` index the cursor should lock to.
    ///
    /// The algorithm computes the on-screen Y distance from the cursor to each
    /// series' snapped magnitude, then applies `curveGravityThreshold` hysteresis:
    /// the current `lockedIndex` is retained unless a different series is at
    /// least `curveGravityThreshold` points closer.
    ///
    /// - Parameters:
    ///   - targetHz: Current cursor frequency, in Hz.
    ///   - cursorScreenY: Current cursor Y position in overlay-local coordinates.
    ///   - proxy: The chart proxy for magnitude → screen-Y conversion.
    ///   - plotFrame: The resolved chart plot frame in overlay-local coordinates.
    ///   - materialSpectra: The per-phase spectra currently displayed.
    ///   - lockedIndex: The index currently locked (`-1` = primary spectrum).
    /// - Returns: The series index to lock to (`-1` = primary spectrum).
    static func nearestSeriesIndex(
        targetHz: Float,
        cursorScreenY: CGFloat,
        proxy: ChartProxy,
        plotFrame: CGRect,
        materialSpectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)],
        lockedIndex: Int
    ) -> Int {
        guard !materialSpectra.isEmpty else { return -1 }
        var candidates: [(index: Int, dist: CGFloat)] = []
        for (i, series) in materialSpectra.enumerated() {
            guard let snapped = snapToWaveform(targetHz: targetHz,
                                               magnitudes: series.magnitudes,
                                               frequencies: series.frequencies),
                  let screenY = proxy.position(forY: Double(snapped.magnitude))
            else { continue }
            let absoluteY = plotFrame.minY + screenY
            candidates.append((index: i, dist: abs(absoluteY - cursorScreenY)))
        }
        guard !candidates.isEmpty else { return lockedIndex }
        let best = candidates.min(by: { $0.dist < $1.dist })!
        guard best.index != lockedIndex else { return lockedIndex }
        let lockedDist = candidates.first(where: { $0.index == lockedIndex })?.dist
        if let ld = lockedDist, ld - best.dist < curveGravityThreshold { return lockedIndex }
        return best.index
    }

    /// Converts a raw screen location into a `CursorSnapState`.
    ///
    /// Behaviour depends on `isMeasurementComplete` and `materialSpectra`:
    ///
    /// - **Live spectrum** (`isMeasurementComplete == false` and no material spectra):
    ///   Returns the raw data-coordinate position with no series lock
    ///   (free-floating cursor readout).
    /// - **Measurement complete** or **plate/brace multi-phase** display:
    ///   Runs `nearestSeriesIndex` to select the nearest curve, then
    ///   calls `snapToWaveform` on that series to obtain an interpolated
    ///   `(frequency, magnitude)` pair.  Updates `lockedSeriesIndex` in place.
    ///
    /// - Parameters:
    ///   - location: Cursor position in overlay-local coordinates (screen points).
    ///   - plotFrame: The resolved chart plot area frame.
    ///   - proxy: The chart proxy for coordinate conversion.
    ///   - lockedSeriesIndex: Inout index tracking which series the cursor is
    ///     locked to; updated by this call.
    /// - Returns: A `CursorSnapState` ready for display, or `nil` if the proxy
    ///   cannot convert the coordinates (e.g. before the chart is laid out).
    func resolveSnapState(
        location: CGPoint,
        plotFrame: CGRect,
        proxy: ChartProxy,
        lockedSeriesIndex: inout Int
    ) -> CursorSnapState? {
        let plotLocal = CGPoint(x: location.x - plotFrame.minX,
                                y: location.y - plotFrame.minY)
        guard let rawFreq = proxy.value(atX: plotLocal.x, as: Double.self),
              let rawDB   = proxy.value(atY: plotLocal.y, as: Double.self) else { return nil }

        // Snap when measurement is complete (guitar or plate/brace) or when phase spectra are loaded
        guard isMeasurementComplete || !materialSpectra.isEmpty else {
            return CursorSnapState(frequency: rawFreq, magnitude: rawDB,
                                   seriesIndex: nil, curveColor: primaryCurveColor)
        }

        let targetHz = Float(rawFreq)
        let newLock = Self.nearestSeriesIndex(
            targetHz: targetHz,
            cursorScreenY: location.y,
            proxy: proxy,
            plotFrame: plotFrame,
            materialSpectra: materialSpectra,
            lockedIndex: lockedSeriesIndex)
        lockedSeriesIndex = newLock

        let snapMags: [Float]
        let snapFreqs: [Float]
        let curveColor: Color
        let seriesIdx: Int?

        if !materialSpectra.isEmpty, newLock >= 0, newLock < materialSpectra.count {
            let s = materialSpectra[newLock]
            snapMags  = s.magnitudes
            snapFreqs = s.frequencies
            curveColor = s.color
            seriesIdx  = newLock
        } else {
            snapMags   = magnitudes
            snapFreqs  = frequencies
            curveColor = primaryCurveColor
            seriesIdx  = nil
        }

        guard let snapped = Self.snapToWaveform(targetHz: targetHz,
                                                magnitudes: snapMags,
                                                frequencies: snapFreqs)
        else {
            return CursorSnapState(frequency: rawFreq, magnitude: rawDB,
                                   seriesIndex: seriesIdx, curveColor: curveColor)
        }
        return CursorSnapState(frequency: Double(snapped.frequency),
                               magnitude: Double(snapped.magnitude),
                               seriesIndex: seriesIdx,
                               curveColor: curveColor)
    }
}
