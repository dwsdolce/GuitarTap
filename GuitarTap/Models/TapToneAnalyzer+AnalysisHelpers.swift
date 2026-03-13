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

    /// Returns all currently detected peaks whose frequency falls within the
    /// specified range.
    ///
    /// - Parameter range: A closed frequency range in Hz (e.g. `80...200` for
    ///   the Air mode region).
    /// - Returns: The subset of ``currentPeaks`` with
    ///   `frequency ∈ [range.lowerBound, range.upperBound]`, in the same order
    ///   as the source array (descending magnitude).
    func getPeaks(in range: ClosedRange<Float>) -> [ResonantPeak] {
        currentPeaks.filter { range.contains($0.frequency) }
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

    /// Compares the current live peaks against the peaks stored in a saved
    /// measurement, matching each saved peak to the nearest live peak by
    /// frequency.
    ///
    /// For each peak in `measurement.peaks` the method finds the live peak
    /// whose frequency is closest (by absolute difference in Hz) and reports
    /// the signed frequency delta.
    ///
    /// - Parameter measurement: The historical ``TapToneMeasurement`` to
    ///   compare against.
    /// - Returns: An array of tuples — one per saved peak — each containing:
    ///   - `current`: The live ``ResonantPeak`` closest in frequency to the
    ///     saved peak, or `nil` if `currentPeaks` is empty.
    ///   - `saved`: The original ``ResonantPeak`` from the measurement.
    ///   - `difference`: `current.frequency − saved.frequency` in Hz; positive
    ///     means the current peak is higher, negative means it is lower.  Zero
    ///     when no current peak is available.
    func compareTo(_ measurement: TapToneMeasurement) -> [(current: ResonantPeak?, saved: ResonantPeak, difference: Float)] {
        measurement.peaks.map { savedPeak in
            // Find the live peak whose frequency is nearest to the saved peak
            let currentPeak = currentPeaks.min(by: { abs($0.frequency - savedPeak.frequency) < abs($1.frequency - savedPeak.frequency) })
            let difference = currentPeak.map { $0.frequency - savedPeak.frequency } ?? 0
            return (current: currentPeak, saved: savedPeak, difference: difference)
        }
    }
}
