//
//  AnalysisDisplayMode.swift
//  GuitarTap
//

// MARK: - AnalysisDisplayMode

/// Describes what the main spectrum display is currently showing.
///
/// This is the authoritative mode gate for the comparison overlay feature.
/// `comparisonSpectra` carries the actual overlay data; `displayMode` controls
/// which UI sections and controls are active.
///
/// Mirrors Python `AnalysisDisplayMode` in `models/analysis_display_mode.py`.
/// In Python the enum lives in its own file due to circular-import constraints;
/// this file keeps the Swift structure consistent with that layout.
///
/// - SeeAlso: ``TapToneAnalyzer/displayMode``
enum AnalysisDisplayMode: Equatable {

    /// The main spectrum is shown — live input, or the measurement's own frozen result once
    /// `isMeasurementComplete` is set. Those two are NOT distinguished here: there used to be a
    /// `.frozen` case, but nothing ever branched on it, because whether a result is displayed is
    /// what `isMeasurementComplete` says. Keeping both meant two fields describing one fact, and
    /// no completion path set `.frozen` — so the device-settle guard, which asked
    /// `displayMode == .live`, wiped finished measurements (#17 F35).
    case live

    /// Two or more saved guitar measurements are overlaid for comparison.
    case comparison
}
