//
//  TapToneAnalyzer+AnalysisHelpers.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

/// # TapToneAnalyzer+AnalysisHelpers
///
/// Convenience query methods that operate on the analyser's current peak data.
/// These helpers are thin wrappers around `peaksAbovePeakMin` and `identifiedModes`
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
    /// A peak with no entry in ``identifiedModes`` resolves to `.unknown`. It is NOT classified
    /// on its own: one peak cannot compete for a band, so that answer was `.top` for anything in
    /// the Top/Back overlap. Mirrors web's `modeByPeak.get(id) ?? 'unknown'`.
    ///
    /// - Parameter peak: The peak to classify.
    /// - Returns: The ``GuitarMode`` assigned to this peak.
    func peakMode(for peak: ResonantPeak) -> GuitarMode {
        // Override-aware, via the one shared resolver so every "which mode is this peak" surface
        // agrees. A freeform override resolves to .unknown; views detect that case separately via
        // hasManualOverride + fromDisplayName == nil.
        //
        // A peak with no entry in identifiedModes has NO mode, and says so. Classifying the peak
        // ALONE (`GuitarMode.classifyAll([peak])`) cannot disambiguate the Top/Back overlap
        // (Generic: Top 140–260 Hz, Back 180–300) and would return .top for anything in it.
        // classifyAll earns its answer by letting peaks compete for a band; handed one peak it has
        // nothing to arbitrate.
        //
        // The miss is not an error case: a completed plate/brace capture leaves identifiedModes
        // empty on purpose, because material peaks have no guitar mode. Mirrors web
        // (`modeByPeak.get(id) ?? 'unknown'`).
        let auto = identifiedModes.first(where: { $0.peak.id == peak.id })?.mode ?? .unknown
        return GuitarMode.effectiveMode(override: peakModeOverrides[peak.id], auto: auto)
    }

    /// The **definitive** peak for a mode: the user's *selected* peak whose *effective* mode is that
    /// mode — i.e. the one the app treats as *the* Air / Top / Back.
    ///
    /// Two facts, one rule:
    /// - **Selected.** Deselecting a peak makes it a mere candidate, so a deselected Top is not the
    ///   Top. If the mode has no selected peak, this is `nil` — and any derived value (the ratio)
    ///   is correctly absent.
    /// - **Effective mode.** Resolved via ``peakMode(for:)``, so a user override wins. Rename the
    ///   Top peak to something else and it stops being the Top *here* exactly as it does on the chart.
    ///
    /// Selection is unique per Air/Top/Back, so there is at most one selected holder and `max` only
    /// guards against a transient double-selection; normally it returns that single holder.
    ///
    /// Mode comparison uses ``GuitarMode/normalized`` so legacy case names resolve first.
    func getPeak(for mode: GuitarMode) -> ResonantPeak? {
        allPeaks
            .filter { selectedPeakIDs.contains($0.id) && peakMode(for: $0) == mode }
            .max(by: { $0.magnitude < $1.magnitude })
    }

    /// The definitive Air / Top / Back, each flagged if it is the user's manual override — the source
    /// for the multi-tap Averaged row. Uses the same definitive rule as ``getPeak(for:)`` and the
    /// ratio, so the Averaged row agrees with the main panel; the flag lets the view mark an
    /// overridden value so it is not confused with the averaged spectrum's auto-detected peak.
    func definitiveModeInfo() -> [GuitarMode: (frequency: Float, isOverride: Bool)] {
        var out: [GuitarMode: (frequency: Float, isOverride: Bool)] = [:]
        for mode in [GuitarMode.air, .top, .back] {
            guard let p = getPeak(for: mode) else { continue }
            out[mode] = (p.frequency, hasManualOverride(for: p.id))
        }
        return out
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
