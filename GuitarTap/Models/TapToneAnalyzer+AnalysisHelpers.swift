//
//  TapToneAnalyzer+AnalysisHelpers.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

/// # TapToneAnalyzer+AnalysisHelpers
///
/// Convenience query methods that operate on the analyser's current peak data.
/// These helpers are thin wrappers around `currentPeaks` and `identifiedModes`
/// and do not mutate any state.
///
/// ## Usage
/// These methods are intended for use by views and unit tests that need to
/// interrogate the live analysis state without coupling to the full
/// ``TapToneAnalyzer`` implementation.  They are all synchronous and safe to
/// call from the main thread.
///
/// ### Tap-Tone Ratio
/// The canonical guitar quality indicator is the *tap-tone ratio*, defined as:
///
/// ```
/// ratio = f_Top / f_Air
/// ```
///
/// An ideal acoustic guitar top has a ratio close to **2.0**. A higher ratio
/// suggests a stiffer, lighter top; a lower ratio may indicate excess mass or
/// compliance.

import Foundation

extension TapToneAnalyzer {

    // MARK: - Analysis Helpers

    /// Returns the context-aware ``GuitarMode`` for a specific peak.
    ///
    /// Looks the peak up in ``identifiedModes``, which is computed via
    /// ``GuitarMode/classifyAll(_:guitarType:)`` so that peaks in overlapping
    /// mode ranges (e.g. classical Top/Back at 190–230 Hz) resolve to distinct
    /// modes rather than both returning `.top`.
    ///
    /// Falls back to ``GuitarMode/classifyAll(_:guitarType:)`` on a single-element
    /// array if the peak is not found in the current set (e.g. a stale reference).
    ///
    /// - Parameter peak: The peak to classify.
    /// - Returns: The ``GuitarMode`` assigned to this peak.
    func peakMode(for peak: ResonantPeak) -> GuitarMode {
        identifiedModes.first(where: { $0.peak.id == peak.id })?.mode
            ?? GuitarMode.classifyAll([peak])[peak.id] ?? .unknown
    }

    /// Returns the highest-magnitude peak that has been auto-classified or
    /// user-assigned to the given ``GuitarMode``.
    ///
    /// Mode comparison uses ``GuitarMode/normalized`` so that legacy case names
    /// (e.g. `.helmholtz`) resolve to their canonical equivalents (e.g. `.air`)
    /// before matching.
    ///
    /// - Parameter mode: The guitar resonance mode to look up (e.g. `.air`,
    ///   `.top`, `.back`).
    /// - Returns: The strongest-magnitude ``ResonantPeak`` classified as
    ///   `mode`, or `nil` if no such peak exists in `identifiedModes`.
    func getPeak(for mode: GuitarMode) -> ResonantPeak? {
        identifiedModes
            .filter { $0.mode.normalized == mode.normalized }
            .max(by: { $0.peak.magnitude < $1.peak.magnitude })?
            .peak
    }

    /// Computes the tap-tone ratio (`f_Top / f_Air`) from the current
    /// identified modes.
    ///
    /// The tap-tone ratio is a quick indicator of top-plate acoustic quality:
    /// - **≈ 2.0** — ideal; the top resonance is approximately one octave above
    ///   the air (Helmholtz) resonance.
    /// - **> 2.0** — stiffer or lighter top.
    /// - **< 2.0** — heavier or more compliant top.
    ///
    /// - Returns: `f_Top / f_Air` as a dimensionless `Float`, or `nil` if
    ///   either the `.air` or `.top` mode peak is not present in
    ///   `identifiedModes`.
    ///
    /// - SeeAlso: ``TapToneMeasurement/tapToneRatio``
    func calculateTapToneRatio() -> Float? {
        guard let airPeak = getPeak(for: .air),
              let topPeak = getPeak(for: .top) else {
            return nil
        }
        return topPeak.frequency / airPeak.frequency
    }

}
