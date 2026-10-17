//
//  TapToneAnalyzer+AnnotationManagement.swift
//  GuitarTap
//
//  Created on 1/25/26.
//
// @parity state/annotation-management tests=test/annotation-state,test/frozen-peak-recalc

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

    /// Stores an absolute label position for the annotation callout of the given peak.
    ///
    /// - Parameters:
    ///   - peakID: The ``ResonantPeak/id`` of the peak whose label is being
    ///     repositioned.
    ///   - offset: The absolute label-center position in **data-space**:
    ///     `x` = frequency in Hz, `y` = magnitude in dB.
    ///     `.zero` represents "no saved position" — the default (70pt above peak)
    ///     will be used at render time.
    ///     Stored values are converted to pixels at render time using the current
    ///     chart axis ranges, making positions valid across platforms and screen sizes.
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

    // MARK: - Plate Peak Selection — REMOVED 2026-09-20
    //
    // `selectLongitudinalPeak/Cross/Flc(_:)` let the user re-assign which detected peak was the
    // fL / fC / fFLC, from L / C / FLC buttons on each peak row in the material Results panel.
    // Those buttons were removed on 2026-04-17 (`c88e5e1`, "Make the phase detected labels
    // inactive") and the correction path became: REDO the phase (plate) or the measurement (brace).
    // That decision stands. The model layer outlived the UI by five months, reachable only from its
    // own tests, and is deleted here along with the `userSelected*PeakID` tier it wrote to.
    //
    // Do not reintroduce it without the UI: a setter nothing can call is indistinguishable from a
    // feature, and it was the only reason material peaks had to sit in the shared `allPeaks`.
}
