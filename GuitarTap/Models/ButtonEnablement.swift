//
//  ButtonEnablement.swift
//  GuitarTap
//
//  Created on 9/21/26.
//

/// # ButtonEnablement
///
/// The Pause / New Tap / Cancel enablement rule — a pure function of the analyzer state,
/// shared by ``TapToneAnalysisView`` (the view) and the button-enablement test.
///
/// Mirrors web `buttonRule` (`state/buttonEnablement.ts`) and Python `button_rule`
/// (`models/button_enablement.py`).  If this rule changes, update the B1–B16 truth table
/// on all three platforms.
///
/// One implementation, exercised by both the view and the test, so the test cannot pass while
/// the view drifts.
///
// @parity state/button-enablement  tests=test/button-enablement
import Foundation

/// Input state for the button rule — mirrors the fields the view reads.
struct ButtonState {
    /// Whether the detector is listening, paused mid-sequence, or neither.
    ///
    /// One value rather than a detecting/paused boolean pair: the pair could express
    /// "detecting AND paused", which the analyzer cannot represent, so a fixture built
    /// from two booleans would encode a contract the app does not have.
    var detectionState: DetectionState
    var isMeasurementComplete: Bool
    var isReadyForDetection: Bool = true
    var fftIsRunning: Bool = true
    /// What the spectrum is showing.  REQUIRED, and the mode itself rather than a boolean:
    /// the rule reads `tap.displayMode`, so a defaulted boolean would silently answer for a
    /// state the caller never supplied — e.g. New Tap disabled during a comparison, with no
    /// way back to live.
    var displayMode: AnalysisDisplayMode
    var measurementType: MeasurementType = .generic
    var materialTapPhase: MaterialTapPhase = .notStarted
    var numberOfTaps: Int = 1
    /// A file is playing through the pipeline.
    var isPlayingFile: Bool = false
}

/// Computed result of the button rule.
struct ButtonOutput: Equatable {
    var pauseEnabled: Bool
    var newTapDisabled: Bool
    var cancelEnabled: Bool
}

/// Computes the Pause / New Tap / Cancel enablement triple from the analyzer state.
func buttonRule(_ s: ButtonState) -> ButtonOutput {
    // During a file playback Cancel stops the file; Pause and New Tap are disabled. A recording
    // delivers taps back to back, so pausing detection while the file plays on would only let taps
    // go by, and a new sequence would be fed the rest of the file.
    if s.isPlayingFile {
        return ButtonOutput(pauseEnabled: false, newTapDisabled: true, cancelEnabled: true)
    }

    let isGuitar = s.measurementType.isGuitar

    let isInReviewPhase: Bool = {
        switch s.materialTapPhase {
        case .reviewingLongitudinal, .reviewingCross, .reviewingFlc:
            return !isGuitar
        default:
            return false
        }
    }()

    // A sequence is "in flight" when the analyzer is working toward a measurement: for
    // guitar, detecting or paused; for material, past notStarted and not complete. New Tap
    // is disabled while in flight and enabled otherwise (idle OR complete) — the honest
    // predicate, replacing the old `!isMeasurementComplete` proxy that wrongly locked New
    // Tap in the disarmed-idle state the Dump Capture Audio folder guard can produce.
    // Cancel restarts, offered during a review phase (as "Redo") or an active multi-step
    // sequence (multi-tap or multi-phase = plate; brace is single-phase).
    let isDetecting = s.detectionState == .listening
    let isDetectionPaused = s.detectionState == .paused
    let sequenceActive: Bool = isGuitar
        ? (isDetecting || isDetectionPaused)
        : (s.materialTapPhase != .notStarted && !s.isMeasurementComplete)
    let multiStep = s.numberOfTaps > 1 || s.measurementType == .plate
    let inActiveMultiStep = sequenceActive && multiStep

    let pauseEnabled: Bool
    if isInReviewPhase {
        pauseEnabled = true
    } else {
        pauseEnabled = isDetecting || isDetectionPaused
    }

    let newTapDisabled: Bool
    if s.displayMode == .comparison {
        newTapDisabled = false
    } else if !(s.fftIsRunning && s.isReadyForDetection) {
        newTapDisabled = true
    } else {
        newTapDisabled = sequenceActive
    }

    let cancelEnabled = isInReviewPhase || inActiveMultiStep

    return ButtonOutput(pauseEnabled: pauseEnabled,
                        newTapDisabled: newTapDisabled,
                        cancelEnabled: cancelEnabled)
}
