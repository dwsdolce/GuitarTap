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

    /// Snaps a raw cursor frequency to the waveform of a single series.
    ///
    /// Algorithm:
    /// 1. Binary search for the bin closest to `targetHz`.
    /// 2. Linearly interpolate between the two bracketing bins for smooth tracking.
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

    /// Screen-distance gravity threshold (points). A locked curve is only abandoned when
    /// a competitor curve is at least this many points closer on screen.
    static let curveGravityThreshold: CGFloat = 12.0

    /// Returns the materialSpectra index to lock to (-1 = primary spectrum).
    /// Switches away from `lockedIndex` only when a competitor is at least
    /// `curveGravityThreshold` screen points closer.
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

    /// Resolves a raw screen location into a `CursorSnapState`.
    ///
    /// When `isSpectrumFrozen` is false, returns the raw data-coordinate position
    /// with no series lock (free-floating cursor). When frozen, snaps the Y position
    /// to the nearest waveform and applies gravity-based curve locking.
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

        // Snap when the spectrum is frozen (guitar) or when plate/brace spectra are loaded
        guard isSpectrumFrozen || !materialSpectra.isEmpty else {
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
