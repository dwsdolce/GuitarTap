//
//  StateNotificationTests.swift
//  GuitarTapTests
//
//  One contract, three mechanisms: when the model's readiness changes, the view layer is told.
//
//  Swift satisfies it with `@Published` (this file observes `objectWillChange`), Python with an
//  explicit signal, web by putting the field on the snapshot and calling `notify()`. Every one of
//  those can be broken by an ordinary edit — drop the `@Published`, forget to add the signal, leave
//  the field off the snapshot — and in Python it simply never existed, so the button row went stale
//  for the whole route-change settle and New Tap never greyed out (#17 F32).
//
//  This suite was nearly not written at all: the Python half was first parked in a file tagged
//  `@parity none` on the grounds that signal plumbing is PySide6-specific and has no counterpart.
//  It does have one. The contract is not "does Qt emit" but "does a state change reach the UI",
//  which all three implement and all three can break. That is PARITY-TEST-METHOD rule 4 — an "n/a"
//  that rests on the view layer is a finding, not a difference.
//
//  Mirrors: tests/test_state_notification.py · test/state-notification.test.ts
//
// @parity test/notification

import Testing
import Foundation
import Combine
@testable import GuitarTap

@MainActor
private func makeSUT() -> TapToneAnalyzer {
    let fft = RealtimeFFTAnalyzer()
    let sut = TapToneAnalyzer(fftAnalyzer: fft)
    TapDisplaySettings.measurementType = .generic
    sut.cancellables.removeAll()
    return sut
}

@Suite("StateNotification", .serialized)
@MainActor
struct StateNotificationTests {

    // N1: standing readiness down notifies observers.
    @Test func readinessCleared_notifiesObservers() {
        let sut = makeSUT()
        var fired = 0
        let token = sut.objectWillChange.sink { _ in fired += 1 }
        defer { token.cancel() }

        sut.isReadyForDetection = false

        #expect(fired > 0,
                "REGRESSION: a readiness change must reach the view layer, or New Tap stays clickable while the input is reinitialising")
    }

    // N2: restoring readiness notifies too — the button has to come back, not just go away.
    @Test func readinessRestored_notifiesObservers() {
        let sut = makeSUT()
        sut.isReadyForDetection = false
        var fired = 0
        let token = sut.objectWillChange.sink { _ in fired += 1 }
        defer { token.cancel() }

        sut.isReadyForDetection = true

        #expect(fired > 0, "restoring readiness must notify, or New Tap never re-enables")
    }

    // N3: the production path — a route-change restart stands readiness down and says so.
    @Test func routeChangeRestart_clearsReadinessAndNotifies() {
        let sut = makeSUT()
        var fired = 0
        let token = sut.objectWillChange.sink { _ in fired += 1 }
        defer { token.cancel() }

        sut.handleRouteChangeRestart()

        #expect(sut.isReadyForDetection == false, "a route-change restart must stand readiness down")
        #expect(fired > 0, "and must notify the view layer that it did")
    }

    // N4: the settle must not throw away a result announcement. A completed measurement's status
    // ("Analysis complete! N peaks…") is not re-derivable, so the derivation declines to speak.
    @Test func settle_restoresACompleteMeasurementsStatus() {
        let sut = makeSUT()
        sut.numberOfTaps = 1
        sut.currentTapCount = 1
        sut.isMeasurementComplete = true
        let announced = "Analysis complete! 12 peaks identified (from 1 averaged taps)."

        #expect(sut.statusAfterSettle() == nil, "a completed measurement's status is not derivable")
        #expect(sut.restoredStatus(before: announced) == announced,
                "REGRESSION: the settle must PUT BACK the result announcement. Asserting only that it does not say \"Tap again\" passed while the \"Audio device changed - reinitializing…\" transient stayed up forever.")
    }

    // N5: mid-sequence the settle reports what was captured — not the opening instruction, which is
    // what the old two-branch guess said once a tap was already in hand.
    @Test func settle_midSequence_reportsProgressNotTheOpeningInstruction() {
        let sut = makeSUT()
        sut.numberOfTaps = 3
        sut.detectionState = .listening
        sut.currentTapCount = 1

        #expect(sut.statusAfterSettle() == "Tap 1/3 captured. Tap again...")
    }

    // N6: idle and nothing captured — "Ready".
    @Test func settle_idle_isReady() {
        let sut = makeSUT()
        #expect(sut.statusAfterSettle() == "Ready")
    }

    // N7: a COMPLETED measurement survives a device change. The settle blanks the chart while the
    // new device's audio is not yet valid, but only when a LIVE spectrum is on screen. The old
    // guard asked `displayMode == .live`, which is still true of a finished measurement because no
    // completion path sets `.frozen` — so a device change wiped the result (#17 F35, a regression
    // from a086638 / build 264).
    @Test func routeChange_leavesACompletedMeasurementIntact() {
        let sut = makeSUT()
        sut.setFrozenSpectrum(frequencies: [100, 200], magnitudes: [-40, -50])
        sut.allPeaks = [ResonantPeak(frequency: 100, magnitude: -40)]
        sut.isMeasurementComplete = true

        sut.handleRouteChangeRestart()

        #expect(sut.isSettling == false, "a completed measurement is not a live spectrum — nothing to blank")
        #expect(sut.allPeaks.count == 1, "REGRESSION: the settle wiped a finished measurement's peaks")
        #expect(sut.frozenFrequencies == [100, 200], "and its spectrum")
    }

    // N8: mid-sequence, with a live spectrum on screen, the settle DOES blank — and says so.
    @Test func routeChange_blanksALiveSpectrum() {
        let sut = makeSUT()
        sut.detectionState = .listening

        sut.handleRouteChangeRestart()

        #expect(sut.isSettling == true, "a live spectrum is blanked for the settle")
    }
}
