/// # Extensions
///
/// General-purpose Swift and SwiftUI extensions used throughout GuitarTap.
///
/// This file contains three groups of extensions:
///
/// 1. **`Comparable.clamped(to:)`** — generic range clamping available on all
///    `Comparable` types (Int, Float, CGFloat, etc.).
///
/// 2. **`Float` extensions** — view-layer utilities for formatting frequency
///    values and computing quality labels and colors for decay time and tap
///    tone ratio.  Decay quality uses guitar-type-specific thresholds from
///    `GuitarType.DecayThresholds`; tap tone ratio quality is hardcoded to
///    the luthier target range of 1.9–2.1.
///
/// 3. **`View.hint(_:)`** and **`HintText`** — a platform-adaptive `.help()`/
///    `.accessibilityHint()` modifier, plus a centralised enum of all UI hint
///    strings used by toolbar buttons and controls.
///
/// - SeeAlso: `TapDisplaySettings`, `GuitarMode`, `TapToneAnalysisView`
import SwiftUI

// MARK: - Comparable Clamping

extension Comparable {
    /// Returns this value clamped to the given closed range.
    ///
    /// Equivalent to `Swift.max(range.lowerBound, Swift.min(self, range.upperBound))`.
    ///
    /// ```swift
    /// let x: Float = 1.5
    /// let clamped = x.clamped(to: 0.0...1.0)  // → 1.0
    /// ```
    ///
    /// - Parameter range: The closed range to clamp to.
    /// - Returns: `range.lowerBound` if `self` is below it; `range.upperBound`
    ///   if above it; otherwise `self` unchanged.
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Float Extensions

extension Float {
    /// Formats a frequency value as a human-readable string.
    ///
    /// Values ≥ 1000 Hz are shown as kHz with one decimal place (e.g.
    /// `"2.5 kHz"`); lower values are shown as Hz with one decimal place
    /// (e.g. `"440.0 Hz"`).
    ///
    /// - Returns: A formatted frequency string with a unit suffix.
    func formattedAsFrequency() -> String {
        if self >= 1000 {
            return String(format: "%.1f kHz", self / 1000)
        } else {
            return String(format: "%.1f Hz", self)
        }
    }
    
    // @parity dsp/analysis-quality — decay/tap-ratio quality labels + colors
    //   (ratio math is on TapToneMeasurement.tapToneRatio; thresholds on GuitarType.decayThresholds)
    /// Qualitative label for this value interpreted as a ring-out time (seconds),
    /// using the currently selected guitar type's decay thresholds.
    ///
    /// Body-only taps (damped strings) typically decay in 0.05–0.3 s; taps
    /// with open strings ringing can decay in 0.3–1.5 s or longer.  Classical
    /// guitars generally have longer sustain than steel-string acoustics.
    ///
    /// - Returns: One of `"Very Short"`, `"Short"`, `"Moderate"`, `"Good"`,
    ///   or `"Excellent"`.
    /// - SeeAlso: `decayQuality(for:)`, `GuitarType.DecayThresholds`
    var decayQuality: String {
        return decayQuality(for: TapDisplaySettings.guitarType)
    }
    
    /// Qualitative label for this value interpreted as a ring-out time (seconds),
    /// for the specified guitar type.
    ///
    /// - Parameter guitarType: The guitar type whose `decayThresholds` are used.
    /// - Returns: One of `"Very Short"`, `"Short"`, `"Moderate"`, `"Good"`,
    ///   or `"Excellent"`.
    func decayQuality(for guitarType: GuitarType) -> String {
        let thresholds = guitarType.decayThresholds
        switch self {
        case 0..<thresholds.veryShort:
            return "Very Short"
        case thresholds.veryShort..<thresholds.short:
            return "Short"
        case thresholds.short..<thresholds.moderate:
            return "Moderate"
        case thresholds.moderate..<thresholds.good:
            return "Good"
        case thresholds.good...:
            return "Excellent"
        default:
            return "Unknown"
        }
    }
    
    /// Color corresponding to `decayQuality` for the currently selected guitar type.
    ///
    /// Colors progress from `.gray` (very short) → `.orange` → `.yellow` →
    /// `.green` → `.blue` (excellent).
    var decayQualityColor: Color {
        return decayQualityColor(for: TapDisplaySettings.guitarType)
    }
    
    /// Color corresponding to `decayQuality(for:)` for the specified guitar type.
    ///
    /// - Parameter guitarType: The guitar type whose thresholds define the ranges.
    /// - Returns: A `Color` ranging from `.gray` (very short) to `.blue` (excellent).
    func decayQualityColor(for guitarType: GuitarType) -> Color {
        let thresholds = guitarType.decayThresholds
        switch self {
        case 0..<thresholds.veryShort:
            return .gray
        case thresholds.veryShort..<thresholds.short:
            return .orange
        case thresholds.short..<thresholds.moderate:
            return .yellow
        case thresholds.moderate..<thresholds.good:
            return .green
        case thresholds.good...:
            return .blue
        default:
            return .gray
        }
    }
    
    /// Qualitative label for this value interpreted as a tap tone ratio
    /// (fTop / fAir).
    ///
    /// The luthier target range is **1.9–2.1**.  Values outside this range
    /// indicate the top plate frequency is too low relative to the air
    /// resonance (Low) or too high (High).
    ///
    /// - Returns: One of `"Low"`, `"Below Target"`, `"Ideal"`,
    ///   `"Above Target"`, or `"High"`.
    var tapToneRatioQuality: String {
        switch self {
        case 0..<1.7:
            return "Low"
        case 1.7..<1.9:
            return "Below Target"
        case 1.9...2.1:
            return "Ideal"
        case 2.1..<2.3:
            return "Above Target"
        case 2.3...:
            return "High"
        default:
            return "Unknown"
        }
    }
    
    /// Color corresponding to `tapToneRatioQuality`.
    ///
    /// `.green` for the ideal range, `.orange` for near-ideal deviations,
    /// `.red` for out-of-range values.
    var tapToneRatioQualityColor: Color {
        switch self {
        case 0..<1.7:
            return .red
        case 1.7..<1.9:
            return .orange
        case 1.9...2.1:
            return .green
        case 2.1..<2.3:
            return .orange
        case 2.3...:
            return .red
        default:
            return .gray
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Applies a platform-appropriate hint to a view.
    ///
    /// On macOS, this calls `.help(_:)` to show a tooltip on hover.
    /// On iOS, it calls `.accessibilityHint(_:)` to provide a VoiceOver hint.
    ///
    /// Use `HintText` constants as the `text` argument for consistent wording
    /// across the app.
    ///
    /// - Parameter text: The hint string to display.
    /// - Returns: The view with the appropriate platform hint applied.
    func hint(_ text: String) -> some View {
        #if os(macOS)
        self.help(text)
        #else
        self
        #endif
    }
}

// MARK: - UI Hint Text Constants

/// Centralised string constants for UI control hints.
///
/// These strings are used by `View.hint(_:)` to provide both macOS hover
/// tooltips and iOS VoiceOver accessibility hints from a single source of truth.
///
/// - SeeAlso: `View.hint(_:)`, `TapToneAnalysisView+Controls`
enum HintText {
    // MARK: - Main Control Buttons

    /// Hint for the start/stop button, reflecting the current running state.
    ///
    /// - Parameter isRunning: `true` if analysis is currently running.
    /// - Returns: An appropriate hint string.
    static func start(isRunning: Bool) -> String {
        isRunning ? "Stop audio analysis" : "Start audio analysis and tap detection"
    }

    /// Hint for the "Show Results" button.
    static let showResults = "View detected peaks with mode assignments and frequencies"

    /// Hint for the "Show Metrics" button.
    static let showMetrics = "View FFT analysis metrics including sample rate and resolution"

    /// Hint for the "Save" button.
    static let save = "Save the current measurement with measurement name and notes"

    /// Hint for the "Export Spectrum" button.
    static let exportSpectrum = "Export spectrum image as PNG file"

    /// Hint for the auto-scale dB button, reflecting its enabled/disabled state.
    ///
    /// - Parameter isEnabled: `true` if auto-scale is currently active.
    /// - Returns: An appropriate hint string.
    static func autoScale(isEnabled: Bool) -> String {
        isEnabled ? "Auto-scale dB enabled - click to disable and reset" : "Automatically scale dB range to fit the current spectrum"
    }

    /// Hint for the "Measurements" navigation button.
    static let measurements = "View and manage saved measurements"

    /// Hint for the "Settings" navigation button.
    static let settings = "Configure spectrum display, analysis parameters, and audio input"
    
    // MARK: - Tap Controls

    /// Hint for the tap count stepper (1–10 taps to average).
    static let taps = "Number of taps to average for peak detection (1-10)"

    /// Hint for the tap detection threshold control.
    ///
    /// In brace/plate mode the threshold is relative to the adaptive noise
    /// floor, not an absolute level.
    static let threshold = "Signal level that triggers tap detection. Lower values detect quieter taps. In brace/plate mode this is used as the headroom above the ambient noise floor, not an absolute level."

    /// Hint for the hysteresis (reset margin) control.
    ///
    /// Prevents a single loud tap from triggering multiple consecutive detections.
    static let hysteresis = "How far the signal must drop below the detection threshold before the detector resets and is ready for the next tap. Prevents a single loud tap from triggering multiple detections."

    /// Hint for the minimum peak magnitude control.
    ///
    /// In guitar mode this gates which peaks are reported as well as displayed.
    static let peakMin = "Minimum peak magnitude shown on the spectrum chart. In guitar mode this also gates which peaks are reported. In brace/plate mode the tap capture uses its own adaptive noise floor, so this only affects chart display."

    /// Hint for the "New Tap" button.
    static let newTap = "Start a new tap sequence to detect and analyze resonance peaks"

    /// Hint for the "Cancel" button.
    static let cancel = "Cancel the current tap sequence and start over"

    /// Hint for the "Reset Labels" button.
    static let resetLabels = "Reset all peak label positions to their default locations"

    /// Hint for the "Pause Detection" button.
    ///
    /// The spectrum display remains live while detection is paused.
    static let pauseDetection = "Pause tap detection to experiment with taps without advancing the sequence; spectrum stays live"

    /// Hint for the "Resume Detection" button.
    static let resumeDetection = "Resume tap detection to continue the in-progress sequence"
}
