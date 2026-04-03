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

    /// Live FFT input is displayed; tap detection is active or waiting.
    case live

    /// A single frozen or loaded measurement is displayed; tap detection is idle.
    case frozen

    /// Two or more saved guitar measurements are overlaid for comparison.
    case comparison
}
