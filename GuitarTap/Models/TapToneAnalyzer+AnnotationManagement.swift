//
//  TapToneAnalyzer+AnnotationManagement.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

/// # TapToneAnalyzer+AnnotationManagement
///
/// Manages the draggable annotation label offsets for peak callouts rendered
/// on the spectrum chart. Each peak is identified by its ``ResonantPeak/id``
/// (`UUID`), and its label may be repositioned by the user via drag gesture.
///
/// ## Thread Safety
/// All mutations to `peakAnnotationOffsets` (a `@Published` dictionary) must
/// occur on the main thread so that SwiftUI observes the change on the correct
/// run-loop iteration. Every mutating method in this extension checks
/// `Thread.isMainThread` and either updates directly (avoiding a potential
/// deadlock on re-entrant calls) or dispatches asynchronously via
/// `DispatchQueue.main.async`.
///
/// ## Persistence
/// Annotation offsets are serialised as part of a saved ``TapToneMeasurement``
/// (via `SpectrumSnapshot.annotationOffsets`). When a measurement is restored,
/// call ``applyAnnotationOffsets(_:)`` to reinstate the user's layout.

import SwiftUI

extension TapToneAnalyzer {

    // MARK: - Annotation Management

    /// Stores a new drag-offset for the annotation callout of the given peak.
    ///
    /// - Parameters:
    ///   - peakID: The ``ResonantPeak/id`` of the peak whose label is being
    ///     repositioned.
    ///   - offset: The desired offset in **data-space** coordinates:
    ///     `x` = frequency delta in Hz, `y` = magnitude delta in dB.
    ///     `.zero` represents the default (no offset) position.
    ///     Stored values are converted to/from pixels at render time using the
    ///     current chart axis ranges, making offsets valid across platforms and
    ///     screen sizes.
    ///
    /// - Note: Safe to call from any thread; dispatches to the main queue when
    ///   needed.
    func updateAnnotationOffset(for peakID: UUID, offset: CGPoint) {
        // If already on main thread, update directly to avoid deadlock
        if Thread.isMainThread {
            peakAnnotationOffsets[peakID] = offset
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakAnnotationOffsets[peakID] = offset
            }
        }
    }

    /// Returns the current drag-offset for the given peak's annotation callout.
    ///
    /// - Parameter peakID: The ``ResonantPeak/id`` of the target peak.
    /// - Returns: The stored `CGPoint` offset, or `.zero` if the label has
    ///   never been dragged or its offset was cleared.
    func getAnnotationOffset(for peakID: UUID) -> CGPoint {
        peakAnnotationOffsets[peakID] ?? .zero
    }

    /// Removes any stored drag-offset for a single peak, returning its
    /// annotation callout to the default anchor position.
    ///
    /// - Parameter peakID: The ``ResonantPeak/id`` of the peak to reset.
    ///
    /// - Note: Safe to call from any thread.
    func resetAnnotationOffset(for peakID: UUID) {
        if Thread.isMainThread {
            peakAnnotationOffsets.removeValue(forKey: peakID)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakAnnotationOffsets.removeValue(forKey: peakID)
            }
        }
    }

    /// Clears all stored annotation offsets, resetting every callout label to
    /// its default anchor position.
    ///
    /// - Note: Safe to call from any thread.
    func resetAllAnnotationOffsets() {
        if Thread.isMainThread {
            peakAnnotationOffsets = [:]
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakAnnotationOffsets = [:]
            }
        }
    }

    /// Replaces the entire annotation-offset dictionary with the supplied
    /// mapping.
    ///
    /// Called when loading a saved ``TapToneMeasurement`` to restore the
    /// user's previously arranged callout positions.
    ///
    /// - Parameter offsets: A dictionary keyed by ``ResonantPeak/id`` values,
    ///   mapping each peak to its stored `CGPoint` label offset in data-space
    ///   (x = Hz delta, y = dB delta).
    ///
    /// - Note: Safe to call from any thread.
    func applyAnnotationOffsets(_ offsets: [UUID: CGPoint]) {
        if Thread.isMainThread {
            peakAnnotationOffsets = offsets
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.peakAnnotationOffsets = offsets
            }
        }
    }

    // MARK: - Plate Peak Selection

    /// Toggles `peakID` as the user-selected longitudinal peak.
    ///
    /// Tapping an already-selected longitudinal peak deselects it. Selecting a
    /// new peak also clears any conflicting cross or Flc user-selection for the
    /// same peak ID, enforcing mutual exclusion across tap-type assignments.
    ///
    /// - Parameter peakID: The ``ResonantPeak/id`` to select or deselect.
    func selectLongitudinalPeak(_ peakID: UUID) {
        if effectiveLongitudinalPeakID == peakID {
            userSelectedLongitudinalPeakID = nil
            selectedLongitudinalPeak = nil
        } else {
            userSelectedLongitudinalPeakID = peakID
            if effectiveCrossPeakID == peakID {
                userSelectedCrossPeakID = nil
                selectedCrossPeak = nil
            }
            if effectiveFlcPeakID == peakID {
                userSelectedFlcPeakID = nil
                selectedFlcPeak = nil
            }
        }
    }

    /// Toggles `peakID` as the user-selected cross peak.
    ///
    /// Mirrors the mutual-exclusion logic of ``selectLongitudinalPeak(_:)``.
    ///
    /// - Parameter peakID: The ``ResonantPeak/id`` to select or deselect.
    func selectCrossPeak(_ peakID: UUID) {
        if effectiveCrossPeakID == peakID {
            userSelectedCrossPeakID = nil
            selectedCrossPeak = nil
        } else {
            userSelectedCrossPeakID = peakID
            if effectiveLongitudinalPeakID == peakID {
                userSelectedLongitudinalPeakID = nil
                selectedLongitudinalPeak = nil
            }
            if effectiveFlcPeakID == peakID {
                userSelectedFlcPeakID = nil
                selectedFlcPeak = nil
            }
        }
    }

    /// Toggles `peakID` as the user-selected Flc peak.
    ///
    /// Mirrors the mutual-exclusion logic of ``selectLongitudinalPeak(_:)``.
    ///
    /// - Parameter peakID: The ``ResonantPeak/id`` to select or deselect.
    func selectFlcPeak(_ peakID: UUID) {
        if effectiveFlcPeakID == peakID {
            userSelectedFlcPeakID = nil
            selectedFlcPeak = nil
        } else {
            userSelectedFlcPeakID = peakID
            if effectiveLongitudinalPeakID == peakID {
                userSelectedLongitudinalPeakID = nil
                selectedLongitudinalPeak = nil
            }
            if effectiveCrossPeakID == peakID {
                userSelectedCrossPeakID = nil
                selectedCrossPeak = nil
            }
        }
    }
}
