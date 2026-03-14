/// # SpectrumView+GestureHandlers
///
/// Zoom, pan, and scroll-wheel gesture handlers for `SpectrumView`.
///
/// ## Scroll wheel modifier key bindings (macOS)
///
/// | Modifier key(s)     | Action                                     |
/// |---------------------|--------------------------------------------|
/// | None                | Pan vertically (dB axis)                   |
/// | Shift               | Pan horizontally (frequency axis)          |
/// | Command             | Zoom both axes around cursor               |
/// | Option              | Zoom frequency axis only around cursor     |
/// | Control             | Zoom magnitude (dB) axis only around cursor |
///
/// All zoom operations anchor to the data-space coordinate under the cursor
/// so the frequency/dB value at the cursor position remains fixed as the
/// range expands or contracts.
///
/// ## Axis bounds
///
/// Both axes are clamped to prevent invalid states:
/// - Frequency: 20 Hz – 20 kHz; minimum visible span 50 Hz (linear) / 1.1× ratio (log)
/// - Magnitude: −120 dB – +20 dB; minimum visible span 10 dB
///
/// ## Logarithmic zoom
///
/// Frequency zoom in log mode works in log₁₀ space: the log-distance from the
/// anchor to each edge is divided by the zoom scale, then the result is
/// exponentiated.  This keeps the perceived zoom speed constant regardless
/// of where in the frequency range the anchor falls.
///
/// - SeeAlso: `SpectrumScrollWheel`, `SpectrumView+SnapInterpolation`
//
//  SpectrumView+GestureHandlers.swift
//  GuitarTap
//
//  Zoom, pan, and scroll-wheel gesture handlers for SpectrumView.
//

import SwiftUI
import Charts

#if os(macOS)
import AppKit
#endif

extension SpectrumView {

    // MARK: - Gesture Handlers

#if os(macOS)
    /// Handles scroll wheel events for zooming and panning on macOS.
    ///
    /// Zoom operations anchor to the current cursor position so the point under the
    /// cursor stays fixed as the range expands or contracts.
    ///
    /// - No modifiers: Pan view vertically (magnitude axis)
    /// - Shift key: Pan view horizontally (frequency axis)
    /// - Command key: Zoom both axes around cursor
    /// - Option key: Zoom frequency axis only (horizontal) around cursor
    /// - Control key: Zoom magnitude axis only (vertical) around cursor
    ///
    /// - Parameters:
    ///   - event: The scroll wheel event from AppKit
    ///   - plotFrame: The resolved chart plot frame in overlay-local coordinates
    ///   - proxy: The chart proxy for coordinate conversion
    func handleScrollWheel(event: NSEvent, plotFrame: CGRect, proxy: ChartProxy) {
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

        // Resolve the cursor's data-space position for anchor-aware zoom.
        // lastCursorPosition is kept current by the hover handler.
        let anchor = lastCursorPosition

        // Check in order of priority
        if hasCommand && !hasShift && !hasOption && !hasControl {
            // Command only: Zoom both axes around cursor
            #if DEBUG
            print("→ Zooming both axes")
            #endif
            withAnimation(.easeOut(duration: 0.1)) {
                handleZoom(scale: zoomFactor, cursorPosition: anchor, plotFrame: plotFrame, proxy: proxy)
            }
        } else if hasControl && !hasCommand && !hasOption && !hasShift {
            // Control only: Zoom magnitude axis only around cursor
            #if DEBUG
            print("→ Zooming magnitude axis (zoom factor: \(zoomFactor))")
            #endif
            withAnimation(.easeOut(duration: 0.1)) {
                handleMagnitudeZoom(scale: zoomFactor, cursorPosition: anchor, plotFrame: plotFrame, proxy: proxy)
            }
        } else if hasOption && !hasCommand && !hasShift && !hasControl {
            // Option only: Zoom frequency axis only around cursor
            #if DEBUG
            print("→ Zooming frequency axis")
            #endif
            withAnimation(.easeOut(duration: 0.1)) {
                handleFrequencyZoom(scale: zoomFactor, cursorPosition: anchor, plotFrame: plotFrame, proxy: proxy)
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
#endif

    /// Zooms only the frequency (X) axis, anchoring to the cursor position when available.
    ///
    /// When `cursorPosition`, `plotFrame`, and `proxy` are all provided (macOS), the frequency
    /// value under the cursor stays fixed. Falls back to range midpoint otherwise.
#if os(macOS)
    func handleFrequencyZoom(scale: CGFloat, cursorPosition: CGPoint? = nil, plotFrame: CGRect? = nil, proxy: ChartProxy? = nil) {
        let anchorFreq: Float = {
            if let pos = cursorPosition, let frame = plotFrame, let p = proxy {
                let plotLocal = CGPoint(x: pos.x - frame.minX, y: pos.y - frame.minY)
                if let hz = p.value(atX: plotLocal.x, as: Double.self) {
                    return Float(hz).clamped(to: minFreq...maxFreq)
                }
            }
            return (maxFreq + minFreq) / 2
        }()
        applyFrequencyZoom(scale: scale, anchorFreq: anchorFreq)
    }
#else
    func handleFrequencyZoom(scale: CGFloat) {
        applyFrequencyZoom(scale: scale, anchorFreq: (maxFreq + minFreq) / 2)
    }
#endif

    func applyFrequencyZoom(scale: CGFloat, anchorFreq: Float) {
        if isLogarithmic {
            let logAnchor = log10(Double(anchorFreq))
            let logMin = log10(Double(minFreq))
            let logMax = log10(Double(maxFreq))
            let newLogMin = logAnchor - (logAnchor - logMin) / Double(scale)
            let newLogMax = logAnchor + (logMax - logAnchor) / Double(scale)
            var newMinFreq = Float(pow(10, newLogMin))
            var newMaxFreq = Float(pow(10, newLogMax))
            newMinFreq = max(20, newMinFreq)
            newMaxFreq = min(20000, newMaxFreq)
            if newMaxFreq > newMinFreq * 1.1 {
                minFreq = newMinFreq
                maxFreq = newMaxFreq
                onFrequencyRangeChanged?()
            }
        } else {
            var newMinFreq = anchorFreq - (anchorFreq - minFreq) / Float(scale)
            var newMaxFreq = anchorFreq + (maxFreq - anchorFreq) / Float(scale)
            newMinFreq = max(20, newMinFreq)
            newMaxFreq = min(20000, newMaxFreq)
            if newMaxFreq > newMinFreq + 50 {
                minFreq = newMinFreq
                maxFreq = newMaxFreq
                onFrequencyRangeChanged?()
            }
        }
    }

    /// Zooms only the magnitude (Y) axis, anchoring to the cursor position when available.
    ///
    /// When `cursorPosition`, `plotFrame`, and `proxy` are all provided (macOS), the dB value
    /// under the cursor stays fixed. Falls back to range midpoint otherwise.
#if os(macOS)
    func handleMagnitudeZoom(scale: CGFloat, cursorPosition: CGPoint? = nil, plotFrame: CGRect? = nil, proxy: ChartProxy? = nil) {
        let anchorDB: Float = {
            if let pos = cursorPosition, let frame = plotFrame, let p = proxy {
                let plotLocal = CGPoint(x: pos.x - frame.minX, y: pos.y - frame.minY)
                if let db = p.value(atY: plotLocal.y, as: Double.self) {
                    return Float(db).clamped(to: minDB...maxDB)
                }
            }
            return (maxDB + minDB) / 2
        }()
        applyMagnitudeZoom(scale: scale, anchorDB: anchorDB)
    }
#endif

    func applyMagnitudeZoom(scale: CGFloat, anchorDB: Float) {
        #if DEBUG
        print("  handleMagnitudeZoom called with scale: \(scale)")
        print("  Current dB range: \(minDB) to \(maxDB)")
        #endif

        var newMinDB = anchorDB - (anchorDB - minDB) / Float(scale)
        var newMaxDB = anchorDB + (maxDB - anchorDB) / Float(scale)
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

    /// Zooms both axes simultaneously, anchoring to the gesture/cursor location.
    ///
    /// On macOS, `cursorPosition`/`plotFrame`/`proxy` provide the exact data-space anchor
    /// via ChartProxy. On both platforms, `pinchAnchor` (from `MagnifyGesture.startAnchor`)
    /// is converted to data coordinates using `lastPlotFrame`.
    ///
    /// Falls back to range-midpoint zoom when no anchor is resolvable.
    ///
    /// - Note: Zoom ranges are clamped to reasonable limits:
    ///   - Frequency: 20 Hz to 20 kHz with minimum visible range
    ///   - dB: -120 dB to +20 dB with minimum 10 dB range
    func handleZoom(scale: CGFloat,
                    pinchAnchor: UnitPoint? = nil,
                    cursorPosition: CGPoint? = nil,
                    plotFrame: CGRect? = nil,
                    proxy: ChartProxy? = nil) {
        // --- Frequency axis anchor ---
        let anchorFreq: Float = {
            #if os(macOS)
            // Scroll-wheel path: use ChartProxy for exact data coordinates.
            if let pos = cursorPosition, let frame = plotFrame, let p = proxy {
                let plotLocal = CGPoint(x: pos.x - frame.minX, y: pos.y - frame.minY)
                if let hz = p.value(atX: plotLocal.x, as: Double.self) {
                    return Float(hz).clamped(to: minFreq...maxFreq)
                }
            }
            #endif
            // Pinch path: convert UnitPoint (relative to the whole overlay view) into
            // a plot-area fraction, then interpolate in the data domain.
            if let anchor = pinchAnchor, lastPlotFrame != .zero {
                let viewWidth = lastPlotFrame.minX + lastPlotFrame.width
                let screenX = anchor.x * viewWidth
                let plotFraction = (screenX - lastPlotFrame.minX) / lastPlotFrame.width
                let fraction = plotFraction.clamped(to: 0...1)
                if isLogarithmic {
                    let logMin = log10(Double(minFreq))
                    let logMax = log10(Double(maxFreq))
                    return Float(pow(10, logMin + fraction * (logMax - logMin)))
                } else {
                    return minFreq + Float(fraction) * (maxFreq - minFreq)
                }
            }
            return (maxFreq + minFreq) / 2
        }()

        applyFrequencyZoom(scale: scale, anchorFreq: anchorFreq)

        // --- dB axis anchor ---
        let anchorDB: Float = {
            #if os(macOS)
            if let pos = cursorPosition, let frame = plotFrame, let p = proxy {
                let plotLocal = CGPoint(x: pos.x - frame.minX, y: pos.y - frame.minY)
                if let db = p.value(atY: plotLocal.y, as: Double.self) {
                    return Float(db).clamped(to: minDB...maxDB)
                }
            }
            #endif
            if let anchor = pinchAnchor, lastPlotFrame != .zero {
                // UnitPoint.y = 0 is the view top (= maxDB), 1 is the bottom (= minDB).
                let viewHeight = lastPlotFrame.minY + lastPlotFrame.height
                let screenY = anchor.y * viewHeight
                let plotFraction = (screenY - lastPlotFrame.minY) / lastPlotFrame.height
                let fraction = plotFraction.clamped(to: 0...1)
                return maxDB - Float(fraction) * (maxDB - minDB)
            }
            return (maxDB + minDB) / 2
        }()

        applyMagnitudeZoom(scale: scale, anchorDB: anchorDB)
    }

    /// Handles drag gestures for panning the view.
    ///
    /// Pan sensitivity is adjusted based on the current visible range.
    /// Different panning algorithms are used for logarithmic vs. linear frequency scales.
    ///
    /// - Parameter translation: The drag translation from the gesture
    ///
    /// - Note: Panning is constrained to keep the view within valid bounds
    func handlePan(translation: CGSize) {
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

    // MARK: - Axis Reset Helpers

    /// Resets both axes to the saved (persisted) display settings
    func resetBothAxesToSaved() {
        minFreq = TapDisplaySettings.minFrequency
        maxFreq = TapDisplaySettings.maxFrequency
        minDB = TapDisplaySettings.minMagnitude
        maxDB = TapDisplaySettings.maxMagnitude
        onFrequencyRangeChanged?()
    }

    /// Resets the frequency axis to the saved (persisted) display settings
    func resetFrequencyAxisToSaved() {
        minFreq = TapDisplaySettings.minFrequency
        maxFreq = TapDisplaySettings.maxFrequency
        onFrequencyRangeChanged?()
    }

    /// Resets the magnitude axis to the saved (persisted) display settings
    func resetMagnitudeAxisToSaved() {
        minDB = TapDisplaySettings.minMagnitude
        maxDB = TapDisplaySettings.maxMagnitude
    }

    /// Resets both axes to factory default values
    func resetBothAxesToDefaults() {
        let type = TapDisplaySettings.measurementType
        minFreq = TapDisplaySettings.defaultMinFrequency(for: type)
        maxFreq = TapDisplaySettings.defaultMaxFrequency(for: type)
        minDB = TapDisplaySettings.defaultMinMagnitude
        maxDB = TapDisplaySettings.defaultMaxMagnitude
        onFrequencyRangeChanged?()
    }

    /// Resets the frequency axis to factory default values
    func resetFrequencyAxisToDefaults() {
        let type = TapDisplaySettings.measurementType
        minFreq = TapDisplaySettings.defaultMinFrequency(for: type)
        maxFreq = TapDisplaySettings.defaultMaxFrequency(for: type)
        onFrequencyRangeChanged?()
    }

    /// Resets the magnitude axis to factory default values
    func resetMagnitudeAxisToDefaults() {
        minDB = TapDisplaySettings.defaultMinMagnitude
        maxDB = TapDisplaySettings.defaultMaxMagnitude
    }
}
