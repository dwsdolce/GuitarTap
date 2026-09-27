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
    /// `isMeasurementComplete` is set. Those two are NOT distinguished here: whether a result is
    /// displayed is what `isMeasurementComplete` says, and a second field for the same fact could
    /// disagree with it.
    case live

    /// Two or more saved guitar measurements are overlaid for comparison.
    case comparison
}
