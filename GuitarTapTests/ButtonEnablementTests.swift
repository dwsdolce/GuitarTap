//
//  ButtonEnablementTests.swift
//  GuitarTapTests
//
//  Truth-table tests for the Pause / New Tap / Cancel button enablement rules
//  defined in TapToneAnalysisView (pauseResumeButtonEnabled,
//  newTapButtonDisabled, cancelButtonEnabled).
//
//  The button logic is a small pure function of (isDetecting, isDetectionPaused,
//  isMeasurementComplete, materialTapPhase, measurementType, currentTapCount,
//  numberOfTaps, isReadyForDetection, fft.isRunning, displayMode).  We exercise
//  it across the state combinations that actually occur in the app and assert
//  the resulting (pauseEnabled, newTapDisabled, cancelEnabled) triple.
//
//  The rule is duplicated here on purpose: if the view drifts from this table,
//  one side has to give.  Mirror in Python: tests/test_button_enablement.py.
//
// @parity test/button-enablement

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Rule mirror
// ---------------------------------------------------------------------------

/// Input state for the button rule.  Mirrors the fields the view reads.
struct ButtonState {
    var isDetecting: Bool
    var isDetectionPaused: Bool
    var isMeasurementComplete: Bool
    var isReadyForDetection: Bool = true
    var fftIsRunning: Bool = true
    var displayModeIsComparison: Bool = false
    var measurementType: MeasurementType = .generic
    var materialTapPhase: MaterialTapPhase = .notStarted
    var currentTapCount: Int = 0
    var numberOfTaps: Int = 1
}

/// Computed result of the button rule.
struct ButtonOutput: Equatable {
    var pauseEnabled: Bool
    var newTapDisabled: Bool
    var cancelEnabled: Bool
}

/// Pure-function mirror of the rule in TapToneAnalysisView.swift:
///   - isInReviewPhase, pauseResumeButtonEnabled, newTapButtonDisabled,
///     cancelButtonEnabled
///
/// If the view's rule changes, change this function — and the truth table —
/// together with it.  The duplication is deliberate: the test exists to catch
/// silent drift in either direction.
func buttonRule(_ s: ButtonState) -> ButtonOutput {
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
    // Tap in the disarmed-idle state the Dump Capture Audio folder guard can produce (§4b).
    // Cancel restarts, offered during a review phase (as "Redo") or an active multi-step
    // sequence (multi-tap or multi-phase = plate).
    let sequenceActive: Bool = isGuitar
        ? (s.isDetecting || s.isDetectionPaused)
        : (s.materialTapPhase != .notStarted && !s.isMeasurementComplete)
    let multiStep = s.numberOfTaps > 1 || s.measurementType == .plate
    let inActiveMultiStep = sequenceActive && multiStep

    let pauseEnabled: Bool
    if isInReviewPhase {
        pauseEnabled = true
    } else {
        pauseEnabled = s.isDetecting || s.isDetectionPaused
    }

    let newTapDisabled: Bool
    if s.displayModeIsComparison {
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

// ---------------------------------------------------------------------------
// MARK: - Truth table
// ---------------------------------------------------------------------------

@Suite("ButtonEnablement", .serialized)
@MainActor
struct ButtonEnablementTests {

    // B1: Disarmed-idle guitar — nothing complete, nothing in flight (the Dump Capture
    // Audio folder guard declined to arm, §4b, or the sub-frame before launch auto-arm).
    // New Tap is ENABLED so the user can re-arm — re-pressing re-runs the folder check.
    // Pause and Cancel stay disabled (no sequence to pause or restart).
    @Test func guitar_disarmedIdle_newTapEnabled() {
        let s = ButtonState(isDetecting: false,
                            isDetectionPaused: false,
                            isMeasurementComplete: false)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: false,
            newTapDisabled: false,   // idle (no sequence in flight) → New Tap enabled to re-arm
            cancelEnabled: false))
    }

    // B2: Guitar single-tap listening — mid-capture, so New Tap is disabled (it only makes
    // sense once complete).  Pause enabled; Cancel disabled (nothing multi-step to restart).
    @Test func guitar_singleTapListening_pauseOnly() {
        let s = ButtonState(isDetecting: true,
                            isDetectionPaused: false,
                            isMeasurementComplete: false,
                            numberOfTaps: 1)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: true,
            newTapDisabled: true,
            cancelEnabled: false))
    }

    // B3: Guitar single-tap complete — measurement done.  New Tap enabled,
    // Pause disabled, Cancel disabled.  This is the post-fix expected state
    // for the iPad bug repro.
    @Test func guitar_singleTapComplete_newTapOnly() {
        let s = ButtonState(isDetecting: false,
                            isDetectionPaused: false,
                            isMeasurementComplete: true,
                            numberOfTaps: 1)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: false,
            newTapDisabled: false,
            cancelEnabled: false))
    }

    // B4: The impossible (isDetecting && isMeasurementComplete) state — StateInvariantTests
    // forbids it.  New Tap now keys off "sequence in flight" (detecting||paused) rather
    // than "complete", so this contradictory state disables New Tap (detecting) while Pause
    // is on — no longer lighting up both.  Still a witness that the state must never occur.
    @Test func guitar_impossibleState_newTapDisabledPauseOn() {
        let s = ButtonState(isDetecting: true,
                            isDetectionPaused: false,
                            isMeasurementComplete: true)
        let out = buttonRule(s)
        #expect(out.newTapDisabled == true)   // in flight (detecting) → New Tap disabled
        #expect(out.pauseEnabled == true)     // detecting → Pause enabled
        #expect(out.cancelEnabled == false)
    }

    // B5: Guitar mid multi-tap — locked in the sequence.  New Tap disabled; Pause and
    // Cancel (restart) enabled.
    @Test func guitar_midMultiTap_newTapDisabled_pauseCancelEnabled() {
        let s = ButtonState(isDetecting: true,
                            isDetectionPaused: false,
                            isMeasurementComplete: false,
                            currentTapCount: 1,
                            numberOfTaps: 3)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: true,
            newTapDisabled: true,
            cancelEnabled: true))
    }

    // B6: Guitar multi-tap paused — still an active multi-step sequence.  Pause (now
    // "Resume") enabled; New Tap disabled; Cancel (restart) enabled (paused counts as
    // active, unlike the old rule which gated Cancel on isDetecting).
    @Test func guitar_multiTapPaused_cancelStillEnabled() {
        let s = ButtonState(isDetecting: false,
                            isDetectionPaused: true,
                            isMeasurementComplete: false,
                            currentTapCount: 1,
                            numberOfTaps: 3)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: true,
            newTapDisabled: true,
            cancelEnabled: true))
    }

    // B7: Plate review — plate is multi-phase, so the sequence is active: New Tap
    // disabled (Cancel restarts it), Pause = "Accept", Cancel = "Redo".
    @Test func plate_review_newTapDisabled_cancelPauseEnabled() {
        let s = ButtonState(isDetecting: false,
                            isDetectionPaused: false,
                            isMeasurementComplete: false,
                            measurementType: .plate,
                            materialTapPhase: .reviewingLongitudinal)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: true,    // "Accept"
            newTapDisabled: true,  // locked in the active multi-phase sequence
            cancelEnabled: true))  // "Redo"
    }

    // B8: Plate active capture — multi-phase, active: New Tap disabled, Pause + Cancel enabled.
    @Test func plate_capturing_newTapDisabled_cancelPauseEnabled() {
        let s = ButtonState(isDetecting: true,
                            isDetectionPaused: false,
                            isMeasurementComplete: false,
                            measurementType: .plate,
                            materialTapPhase: .capturingLongitudinal)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: true,
            newTapDisabled: true,
            cancelEnabled: true))
    }

    // B9: FFT not running — New Tap disabled regardless of other state.
    @Test func fftNotRunning_newTapAlwaysDisabled() {
        let s = ButtonState(isDetecting: false,
                            isDetectionPaused: false,
                            isMeasurementComplete: true,
                            fftIsRunning: false)
        #expect(buttonRule(s).newTapDisabled == true)
    }

    // B10: Comparison mode overrides — New Tap always enabled.
    @Test func comparisonMode_newTapAlwaysEnabled() {
        let s = ButtonState(isDetecting: false,
                            isDetectionPaused: false,
                            isMeasurementComplete: false,
                            displayModeIsComparison: true)
        #expect(buttonRule(s).newTapDisabled == false)
    }

    // B11: Brace single-tap capturing — single-phase + single-tap (like single-tap guitar):
    // not complete so New Tap disabled; Pause on (threshold-setting); Cancel disabled
    // (nothing multi-step to restart).
    @Test func brace_singleTapCapturing_pauseOnly() {
        let s = ButtonState(isDetecting: true,
                            isDetectionPaused: false,
                            isMeasurementComplete: false,
                            measurementType: .brace,
                            materialTapPhase: .capturingLongitudinal,
                            numberOfTaps: 1)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: true,
            newTapDisabled: true,
            cancelEnabled: false))
    }

    // B12: Brace multi-tap capturing — multi-tap makes it multi-step: New Tap disabled,
    // Cancel (restart) enabled.
    @Test func brace_multiTapCapturing_newTapDisabled_cancelEnabled() {
        let s = ButtonState(isDetecting: true,
                            isDetectionPaused: false,
                            isMeasurementComplete: false,
                            measurementType: .brace,
                            materialTapPhase: .capturingLongitudinal,
                            numberOfTaps: 3)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: true,
            newTapDisabled: true,
            cancelEnabled: true))
    }

    // B13: Disarmed-idle material (plate at launch, folder guard declined to arm) — phase
    // notStarted, nothing complete, nothing in flight.  New Tap ENABLED to re-arm;
    // Pause/Cancel disabled.  The material counterpart of B1.
    @Test func plate_disarmedIdle_newTapEnabled() {
        let s = ButtonState(isDetecting: false,
                            isDetectionPaused: false,
                            isMeasurementComplete: false,
                            measurementType: .plate,
                            materialTapPhase: .notStarted)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: false,
            newTapDisabled: false,
            cancelEnabled: false))
    }
}
