//
//  ButtonEnablementTests.swift
//  GuitarTapTests
//
//  Truth-table tests for the Pause / New Tap / Cancel button enablement rule.
//
//  The rule is a small pure function of (detectionState, isMeasurementComplete,
//  materialTapPhase, measurementType, numberOfTaps, isReadyForDetection,
//  fftIsRunning, displayMode).  We exercise it across the state combinations that actually
//  occur in the app and assert the resulting (pauseEnabled, newTapDisabled, cancelEnabled)
//  triple.
//
//  It is the PRODUCTION rule — `buttonRule` in `GuitarTap/Models/ButtonEnablement.swift`,
//  the same function `TapToneAnalysisView` calls.  It used to be retyped here, with the
//  file header explaining that the duplication was deliberate so drift in the view "would
//  make one side give".  It could not: the test asserted against the copy, so the view was
//  free to drift and this suite would stay green.  Mirrors web, where `App.tsx` and
//  `button-enablement.test.ts` both import `buttonRule`, and Python
//  `models/button_enablement.py`.
//
//  Mirror in Python: tests/test_button_enablement.py.
//
// @parity test/button-enablement

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Truth table
// ---------------------------------------------------------------------------

@Suite("ButtonEnablement", .serialized)
@MainActor
struct ButtonEnablementTests {

    // B1: Disarmed-idle guitar — nothing complete, nothing in flight (the Dump Capture
    // Audio folder guard declined to arm or the sub-frame before launch auto-arm).
    // New Tap is ENABLED so the user can re-arm — re-pressing re-runs the folder check.
    // Pause and Cancel stay disabled (no sequence to pause or restart).
    @Test func guitar_disarmedIdle_newTapEnabled() {
        let s = ButtonState(detectionState: .idle,
                            isMeasurementComplete: false,
                            displayMode: .live)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: false,
            newTapDisabled: false,   // idle (no sequence in flight) → New Tap enabled to re-arm
            cancelEnabled: false))
    }

    // B2: Guitar single-tap listening — mid-capture, so New Tap is disabled (it only makes
    // sense once complete).  Pause enabled; Cancel disabled (nothing multi-step to restart).
    @Test func guitar_singleTapListening_pauseOnly() {
        let s = ButtonState(detectionState: .listening,
                            isMeasurementComplete: false,
                            displayMode: .live,
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
        let s = ButtonState(detectionState: .idle,
                            isMeasurementComplete: true,
                            displayMode: .live,
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
        let s = ButtonState(detectionState: .listening,
                            isMeasurementComplete: true,
                            displayMode: .live)
        let out = buttonRule(s)
        #expect(out.newTapDisabled == true)   // in flight (detecting) → New Tap disabled
        #expect(out.pauseEnabled == true)     // detecting → Pause enabled
        #expect(out.cancelEnabled == false)
    }

    // B5: Guitar mid multi-tap — locked in the sequence.  New Tap disabled; Pause and
    // Cancel (restart) enabled.
    @Test func guitar_midMultiTap_newTapDisabled_pauseCancelEnabled() {
        let s = ButtonState(detectionState: .listening,
                            isMeasurementComplete: false,
                            displayMode: .live,
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
        let s = ButtonState(detectionState: .paused,
                            isMeasurementComplete: false,
                            displayMode: .live,
                            numberOfTaps: 3)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: true,
            newTapDisabled: true,
            cancelEnabled: true))
    }

    // B7: Plate review — plate is multi-phase, so the sequence is active: New Tap
    // disabled (Cancel restarts it), Pause = "Accept", Cancel = "Redo".
    @Test func plate_review_newTapDisabled_cancelPauseEnabled() {
        let s = ButtonState(detectionState: .idle,
                            isMeasurementComplete: false,
                            displayMode: .live,
                            measurementType: .plate,
                            materialTapPhase: .reviewingLongitudinal)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: true,    // "Accept"
            newTapDisabled: true,  // locked in the active multi-phase sequence
            cancelEnabled: true))  // "Redo"
    }

    // B8: Plate active capture — multi-phase, active: New Tap disabled, Pause + Cancel enabled.
    @Test func plate_capturing_newTapDisabled_cancelPauseEnabled() {
        let s = ButtonState(detectionState: .listening,
                            isMeasurementComplete: false,
                            displayMode: .live,
                            measurementType: .plate,
                            materialTapPhase: .capturingLongitudinal)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: true,
            newTapDisabled: true,
            cancelEnabled: true))
    }

    // B9: FFT not running — New Tap disabled regardless of other state.
    @Test func fftNotRunning_newTapAlwaysDisabled() {
        let s = ButtonState(detectionState: .idle,
                            isMeasurementComplete: true,
                            fftIsRunning: false,
                            displayMode: .live)
        #expect(buttonRule(s).newTapDisabled == true)
    }

    // B10: Comparison mode overrides — New Tap always enabled.
    @Test func comparisonMode_newTapAlwaysEnabled() {
        let s = ButtonState(detectionState: .idle,
                            isMeasurementComplete: false,
                            displayMode: .comparison)
        #expect(buttonRule(s).newTapDisabled == false)
    }

    // B11: Brace single-tap capturing — single-phase + single-tap (like single-tap guitar):
    // not complete so New Tap disabled; Pause on (threshold-setting); Cancel disabled
    // (nothing multi-step to restart).
    @Test func brace_singleTapCapturing_pauseOnly() {
        let s = ButtonState(detectionState: .listening,
                            isMeasurementComplete: false,
                            displayMode: .live,
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
        let s = ButtonState(detectionState: .listening,
                            isMeasurementComplete: false,
                            displayMode: .live,
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
        let s = ButtonState(detectionState: .idle,
                            isMeasurementComplete: false,
                            displayMode: .live,
                            measurementType: .plate,
                            materialTapPhase: .notStarted)
        #expect(buttonRule(s) == ButtonOutput(
            pauseEnabled: false,
            newTapDisabled: false,
            cancelEnabled: false))
    }
}
