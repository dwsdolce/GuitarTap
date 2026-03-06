//
//  TapToneAnalyzer+ModeOverrideManagement.swift
//  GuitarTap
//
//  Bulk management methods for per-peak user mode overrides.
//  Pattern mirrors TapToneAnalyzer+AnnotationManagement.swift.
//

import Foundation

extension TapToneAnalyzer {

    // MARK: - Mode Override Management

    /// Apply a complete set of mode overrides (used when loading a saved measurement).
    func applyModeOverrides(_ overrides: [UUID: UserAssignedMode]) {
        if Thread.isMainThread {
            peakModeOverrides = overrides
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakModeOverrides = overrides
            }
        }
    }

    /// Reset all per-peak mode overrides so every peak reverts to auto-classification.
    func resetAllModeOverrides() {
        if Thread.isMainThread {
            peakModeOverrides = [:]
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakModeOverrides = [:]
            }
        }
    }

    /// Reset the mode override for a single peak, reverting it to auto-classification.
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
