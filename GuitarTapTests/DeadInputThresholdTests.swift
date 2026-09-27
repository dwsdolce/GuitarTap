//
//  DeadInputThresholdTests.swift
//  GuitarTapTests
//
//  Calibration of the dead-input watchdog's "this stream carries no signal"
//  threshold.  Pure numeric checks against the analyzer's constants — no audio
//  hardware, no engine.
//
//  Why these exist: the threshold is a FIELD CALIBRATION, not a derivation.  Set
//  it too low and a genuinely dead stream (measured at ~-100 dBFS, NOT digital
//  zero) is never detected; too high and a quiet room is mistaken for a dead
//  input and the engine restarts mid-measurement.  The UMIK-1 is an unusually
//  quiet microphone and can sit near -90 dBFS in a silent room, which is what
//  makes the upper bound real.
//
//  Source of the numbers: the silent-input incidents of 2026-07-16 and 2026-08-21.
//
// @parity dead-input

import Foundation   // pow(_:_:) — previously came in transitively via XCTest
import Testing
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

/// Amplitude (linear RMS) for a level in dBFS.
private func amp(_ dbfs: Float) -> Float { pow(10, dbfs / 20) }

/// The criterion the audio path applies per buffer.
private func carriesSignal(_ rms: Float) -> Bool { chunkCarriesSignal(rms: rms) }

// ---------------------------------------------------------------------------
// MARK: - Threshold calibration
// ---------------------------------------------------------------------------

@Suite("DeadInputThreshold")
struct DeadInputThresholdTests {

    @Test func digitalSilence_readsAsNoSignal() {
        #expect(carriesSignal(0) == false)
    }

    @Test func farBelowAnythingReal_readsAsNoSignal() {
        #expect(carriesSignal(amp(-120)) == false)
    }

    @Test func measuredDeadDeviceLevel_readsAsNoSignal() {
        // The level a dead-but-present device was actually measured at.
        #expect(carriesSignal(amp(-100)) == false)
    }

    @Test func quietUMIK1InASilentRoom_readsAsAlive() {
        // The regression these tests exist for: -90 dBFS is quiet, not dead.
        #expect(carriesSignal(amp(-90)))
        #expect(carriesSignal(amp(-95)))
    }

    @Test func roomFloorAndTap_readAsAlive() {
        #expect(carriesSignal(amp(-70)))   // room noise floor
        #expect(carriesSignal(amp(-63)))   // UMIK-1 Air peak
        #expect(carriesSignal(amp(-20)))   // a tap
    }

    @Test func keepsAtLeast10dBMarginUnderTheQuietRoomLevel() {
        // Guards against anyone "tightening" the threshold back up toward -90 dBFS.
        #expect(deadInputRMSThreshold <= amp(-100))
        #expect(amp(-90) / deadInputRMSThreshold >= 3.16)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Dwell
// ---------------------------------------------------------------------------

@Suite("DeadInputDwell")
struct DeadInputDwellTests {

    @Test func dwellOutlastsAQuietPassage() {
        // A short dwell would let an ordinary silent moment between taps trip the
        // watchdog. The recorded incidents persisted for minutes, so patience is free.
        #expect(deadInputDwell >= 10.0)
    }

    @Test func dwellIsLongerThanTheDeliveryThreshold() {
        // Content-based inference should always be more patient than the
        // arrival-based check it sits beside.
        #expect(deadInputDwell > bufferDeliveryTimeout)
    }
}


// ---------------------------------------------------------------------------
// MARK: - Watchdog decision truth table
// ---------------------------------------------------------------------------

/// Every branch of the rule a watchdog tick applies. These are the cases that were
/// previously reachable only by making real audio hardware fail.
@Suite("WatchdogDecision")
struct WatchdogDecisionTests {

    /// `now` is fixed; each case positions the two stamps relative to it.
    private let now: CFTimeInterval = 1000

    private func decide(
        buffersAgo: CFTimeInterval,
        signalAgo: CFTimeInterval,
        exhausted: Bool = false
    ) -> WatchdogDecision {
        watchdogDecision(
            now: now,
            lastBufferTime: now - buffersAgo,
            lastSignalTime: now - signalAgo,
            recoveryExhausted: exhausted,
            silenceThreshold: bufferDeliveryTimeout,
            deadInputThreshold: deadInputDwell
        )
    }

    @Test func signalFlowing_isHealthy() {
        #expect(decide(buffersAgo: 0.02, signalAgo: 0.02) == .healthy)
    }

    @Test func quietPassageShorterThanTheDwell_isStillHealthy() {
        // The case that must never restart the engine: a silent moment between taps.
        #expect(decide(buffersAgo: 0.02, signalAgo: deadInputDwell - 1) == .healthy)
    }

    @Test func noBuffersAtAll_isStarved() {
        #expect(decide(buffersAgo: bufferDeliveryTimeout + 1, signalAgo: bufferDeliveryTimeout + 1) == .starved)
    }

    @Test func buffersArrivingWithNoSignal_isDeadInput() {
        // The failure this whole mechanism exists for.
        #expect(decide(buffersAgo: 0.02, signalAgo: deadInputDwell + 1) == .deadInput)
    }

    @Test func starvationOutranksDeadInput() {
        // A starved stream is trivially signal-less too; report the deeper failure.
        #expect(decide(buffersAgo: bufferDeliveryTimeout + 1, signalAgo: deadInputDwell + 1) == .starved)
    }

    @Test func deadAndOutOfAttempts_warnsWithoutRestarting() {
        #expect(decide(buffersAgo: 0.02, signalAgo: deadInputDwell + 1, exhausted: true) == .deadInputExhausted)
    }

    @Test func signalReturningAfterExhaustion_isHealthy() {
        // The regression from 2026-09-01: raising the input volume again must heal the
        // app rather than leave it deaf until relaunch.
        #expect(decide(buffersAgo: 0.02, signalAgo: 0.02, exhausted: true) == .healthy)
    }

    @Test func exhaustedNeverRestarts_evenWhenStarved() {
        // While exhausted, no branch may attempt a restart.
        let d = decide(buffersAgo: bufferDeliveryTimeout + 1, signalAgo: deadInputDwell + 1, exhausted: true)
        #expect(d == .deadInputExhausted)
        #expect(d != .starved)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Permission decision truth table
// ---------------------------------------------------------------------------

/// Only the platform's own answer counts. Silence is never evidence of a denial.
///
/// A silent input — a muted mic, or a virtual device like BlackHole with nothing routed in — is not
/// a permissions problem, even at launch before any audio has arrived. The dead-input watchdog owns
/// it, and its rules are the suite above.
///
/// Python reads PortAudio's stream-open error and the web reads `getUserMedia`'s `NotAllowedError`;
/// none of the three infers denial from silence.
@Suite("PermissionDecision")
struct PermissionDecisionTests {

    @Test func tccDenied_isADenial() {
        #expect(shouldDeclarePermissionDenied(tccDenied: true))
    }

    @Test func authorized_isNotADenial_howeverSilentTheInput() {
        // The regression this replaced: silence on an authorized device is a dead or muted INPUT,
        // which the dead-input watchdog reports accurately and recovers from.
        #expect(shouldDeclarePermissionDenied(tccDenied: false) == false)
    }
}
