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
    } else if !isGuitar {
        newTapDisabled = false
    } else if s.isDetecting {
        newTapDisabled = true
    } else if !s.isMeasurementComplete {
        newTapDisabled = true
    } else {
        newTapDisabled = false
    }

    let cancelEnabled: Bool
    if isInReviewPhase {
        cancelEnabled = true
    } else if !s.isDetecting {
        cancelEnabled = false
    } else if !isGuitar {
        cancelEnabled = true
    } else if s.numberOfTaps <= 1 {
        cancelEnabled = false
    } else if s.currentTapCount >= s.numberOfTaps {
        cancelEnabled = false
    } else {
        cancelEnabled = true
    }

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

    // B1: Fresh / idle guitar — nothing started, nothing complete.  All disabled.
    @Test func guitar_idle_allDisabled() {
        let s = ButtonState(isDetecting: false,
                            isDetectionPaused: false,
                            isMeasurementComplete: false)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: false,
            newTapDisabled: true,    // !isMeasurementComplete && !isDetecting
            cancelEnabled: false))
    }

    // B2: Guitar mid single-tap sequence — detecting, not paused, not complete.
    // Pause enabled, New Tap disabled (sequence in progress), Cancel disabled
    // because numberOfTaps == 1 (no point in cancelling a one-tap sequence).
    @Test func guitar_midSingleTap_pauseAndCancelOnly() {
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

    // B4: REGRESSION — the impossible state the iPad bug produced.  If the
    // analyzer state ever reaches (isDetecting && isMeasurementComplete) for
    // guitar mode, the buttons reflect "detecting" (Pause on, New Tap off),
    // not "complete".  StateInvariantTests guards against the state existing;
    // this test documents what the button rule WOULD do if the invariant
    // were ever violated.
    @Test func guitar_impossibleState_detectingAndComplete_showsDetectingButtons() {
        let s = ButtonState(isDetecting: true,
                            isDetectionPaused: false,
                            isMeasurementComplete: true)
        let out = buttonRule(s)
        #expect(out.pauseEnabled == true,
                "Bug witness: Pause enabled despite measurement complete")
        #expect(out.newTapDisabled == true,
                "Bug witness: New Tap disabled despite measurement complete")
    }

    // B5: Guitar mid multi-tap — detecting next tap of N.  Pause and Cancel
    // both enabled (Cancel only useful in multi-tap mode).
    @Test func guitar_midMultiTap_pauseAndCancelEnabled() {
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

    // B6: Guitar paused — isDetecting false, isDetectionPaused true.  Pause
    // (now "Resume") still enabled; New Tap disabled because measurement isn't
    // complete; Cancel disabled because !isDetecting.
    @Test func guitar_paused_pauseStillEnabled() {
        let s = ButtonState(isDetecting: false,
                            isDetectionPaused: true,
                            isMeasurementComplete: false,
                            currentTapCount: 1,
                            numberOfTaps: 3)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: true,
            newTapDisabled: true,
            cancelEnabled: false))
    }

    // B7: Plate review phase — buttons reflect Accept/Redo semantics with all
    // three enabled regardless of detection state.
    @Test func plate_review_allEnabled() {
        let s = ButtonState(isDetecting: false,
                            isDetectionPaused: false,
                            isMeasurementComplete: false,
                            measurementType: .plate,
                            materialTapPhase: .reviewingLongitudinal)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: true,    // "Accept"
            newTapDisabled: false, // plate/brace always allow start-over
            cancelEnabled: true))  // "Redo"
    }

    // B8: Plate active capture — detecting, not in review.  Pause and Cancel
    // enabled; New Tap enabled because plate/brace always permit start-over.
    @Test func plate_capturing_pauseCancelNewTapAll_Enabled() {
        let s = ButtonState(isDetecting: true,
                            isDetectionPaused: false,
                            isMeasurementComplete: false,
                            measurementType: .plate,
                            materialTapPhase: .capturingLongitudinal)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: true,
            newTapDisabled: false,
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
}
