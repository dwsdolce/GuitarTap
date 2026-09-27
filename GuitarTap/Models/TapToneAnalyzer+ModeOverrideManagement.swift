//
//  TapToneAnalyzer+ModeOverrideManagement.swift
//  GuitarTap
//
//  Bulk management methods for per-peak user mode overrides.
//  Pattern mirrors TapToneAnalyzer+AnnotationManagement.swift.
//

/// # TapToneAnalyzer+ModeOverrideManagement
///
/// Provides bulk read/write access to the `peakModeOverrides` dictionary, which
/// maps each detected peak's `UUID` to a user-supplied ``UserAssignedMode``.
///
/// ## Three-Layer Peak Selection
/// Mode overrides are the *first* layer in the three-layer peak selection
/// system used throughout the analyser:
///
/// 1. **User override** — a ``UserAssignedMode/assigned(_:)`` entry in
///    `peakModeOverrides` set by the user tapping a peak and choosing a label.
/// 2. **Phase-stored peak** — a remembered peak ID persisted across the
///    multi-tap capture phases (e.g. longitudinal vs cross-grain for plates).
/// 3. **Auto-selected peak** — the highest-magnitude peak in the expected
///    frequency range for a given ``GuitarMode``.
///
/// When a user override is present it takes precedence over the other two
/// layers, regardless of magnitude or frequency.
///
/// ## Thread Safety
/// All mutations mirror the pattern in
/// `TapToneAnalyzer+AnnotationManagement.swift`: if the caller is already on
/// the main thread the update is applied synchronously (to avoid deadlock on
/// re-entrant calls); otherwise it is dispatched asynchronously via
/// `DispatchQueue.main.async`.
///
/// ## Persistence
/// Overrides are serialised inside saved ``TapToneMeasurement`` snapshots.
/// Restore them by calling ``applyModeOverrides(_:)`` when loading a
/// measurement.

import Foundation

extension TapToneAnalyzer {

    // MARK: - Mode Override Management

    /// Replaces the entire mode-override dictionary with the supplied mapping.
    ///
    /// Use this when loading a saved ``TapToneMeasurement`` to restore the
    /// user's previously assigned peak labels.
    ///
    /// - Parameter overrides: A dictionary mapping each ``ResonantPeak/id`` to the label the user
    ///   last assigned to that peak. Every entry is an override; absence means auto.
    ///
    /// - Note: Safe to call from any thread.
    func applyModeOverrides(_ overrides: [UUID: String]) {
        if Thread.isMainThread {
            peakModeOverrides = overrides
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakModeOverrides = overrides
            }
        }
    }

    /// Removes all per-peak mode overrides, returning every peak to
    /// auto-classification.
    ///
    /// After this call the analyser's mode assignment falls back to the
    /// frequency-range heuristic for every peak displayed on the spectrum.
    ///
    /// - Note: Safe to call from any thread.
    func resetAllModeOverrides() {
        if Thread.isMainThread {
            peakModeOverrides = [:]
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakModeOverrides = [:]
            }
        }
    }

    /// Removes the mode override for a single peak, reverting that peak to
    /// auto-classification while preserving overrides on all other peaks.
    ///
    /// - Parameter peakID: The ``ResonantPeak/id`` of the peak whose override
    ///   should be cleared.
    ///
    /// - Note: Safe to call from any thread.
    func resetModeOverride(for peakID: UUID) {
        if Thread.isMainThread {
            peakModeOverrides.removeValue(forKey: peakID)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakModeOverrides.removeValue(forKey: peakID)
            }
        }
    }
}
