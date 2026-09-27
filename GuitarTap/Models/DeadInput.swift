//
//  DeadInput.swift
//  GuitarTap
//
//  The audio-liveness DECISIONS, as pure functions: what a watchdog tick should
//  conclude, and whether silence is evidence of a denied microphone permission.
//
//  These live apart from the engine because the engine cannot be driven by a test.
//  The behaviour is gated on a monotonic clock, a main-runloop Timer, real audio
//  hardware, and an async post-start check. As pure functions, every rule below —
//  each a row of the truth tables here — is verifiable by a unit test rather than by
//  reproducing a hardware failure by hand.
//
// @parity dead-input

import Foundation

// ---------------------------------------------------------------------------
// MARK: - Threshold
// ---------------------------------------------------------------------------

/// RMS below which a buffer counts as carrying no signal: 1e-5 = **-100 dBFS**.
///
/// A field calibration, not a derivation. A dead-but-present device was measured
/// pinned at ≈ -100 dBFS — it does NOT deliver digital zero — while a live room reads
/// ≈ -70 dBFS and a UMIK-1's Air peak ≈ -63 dBFS. Deliberately at the BOTTOM of that
/// range: the UMIK-1 is an unusually quiet microphone and can sit near -90 dBFS in a
/// silent room, so a mid-range threshold would call a quiet workshop a dead input and
/// restart the engine mid-measurement. A missed detection costs one more watchdog
/// cycle; a false positive interrupts real work.
let deadInputRMSThreshold: Float = 1e-5

/// True when a buffer carries enough level to prove the stream is alive.
func chunkCarriesSignal(rms: Float) -> Bool { rms > deadInputRMSThreshold }

/// Seconds with NO buffers arriving before the I/O counts as wedged.
let bufferDeliveryTimeout: CFTimeInterval = 2.5

/// Seconds with buffers but NO signal before the input counts as dead.
///
/// Much longer than the delivery timeout: this one infers from content, a recorded
/// incident persisted for minutes, and there is real cost in fighting a user who has
/// legitimately muted their input.
let deadInputDwell: CFTimeInterval = 15.0

// ---------------------------------------------------------------------------
// MARK: - Watchdog decision
// ---------------------------------------------------------------------------

/// What a single watchdog tick concludes about the input.
enum WatchdogDecision: Equatable {
    /// Signal is flowing: clear any warning, reset the attempt streak and the latch.
    case healthy
    /// Buffers stopped arriving at all — recover.
    case starved
    /// Buffers arriving but carrying nothing — warn and recover.
    case deadInput
    /// Still dead and out of restart attempts: keep warning, attempt nothing. The tick
    /// must keep running so the warning clears the moment signal returns.
    case deadInputExhausted
}

/// Decide what a watchdog tick should do.
///
/// - Parameters:
///   - now: Monotonic now.
///   - lastBufferTime: Monotonic stamp of the last buffer to ARRIVE, whatever it held.
///   - lastSignalTime: Monotonic stamp of the last buffer to carry SIGNAL.
///   - recoveryExhausted: Whether restart attempts have been used up.
///   - silenceThreshold: Seconds with no buffers before the I/O counts as wedged.
///   - deadInputThreshold: Seconds with no signal before the input counts as dead.
func watchdogDecision(
    now: CFTimeInterval,
    lastBufferTime: CFTimeInterval,
    lastSignalTime: CFTimeInterval,
    recoveryExhausted: Bool,
    silenceThreshold: CFTimeInterval,
    deadInputThreshold: CFTimeInterval
) -> WatchdogDecision {
    let dead = (now - lastSignalTime) > deadInputThreshold

    // Out of attempts: never restart, but still report the state so the warning holds
    // while it is true and clears the instant signal returns.
    if recoveryExhausted { return dead ? .deadInputExhausted : .healthy }

    // Starvation first: no buffers at all is the more fundamental failure, and a
    // starved stream is trivially also signal-less.
    if (now - lastBufferTime) > silenceThreshold { return .starved }
    return dead ? .deadInput : .healthy
}

// ---------------------------------------------------------------------------
// MARK: - Permission decision
// ---------------------------------------------------------------------------

/// Whether the post-start check should declare the microphone permission denied.
///
/// **Only the platform's own answer counts.** Silence is never evidence of a denial, so this is
/// `tccDenied` and nothing else.
///
/// A silent input device — a muted mic, or a virtual device like BlackHole with nothing routed into
/// it — is not a permissions problem: "permission denied" would be the wrong message, and stopping
/// the engine the wrong remedy (switching to a working microphone could not recover it). A silent
/// input belongs to the dead-input watchdog, which says "no audio input", keeps watching, and clears
/// itself the moment signal returns.
///
/// Python reads PortAudio's stream-open error and the web reads `getUserMedia`'s `NotAllowedError`;
/// all three report a denial only when the platform says so.
func shouldDeclarePermissionDenied(tccDenied: Bool) -> Bool {
    tccDenied
}
