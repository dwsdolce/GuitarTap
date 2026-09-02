//
//  DeadInput.swift
//  GuitarTap
//
//  The audio-liveness DECISIONS, as pure functions: what a watchdog tick should
//  conclude, and whether silence is evidence of a denied microphone permission.
//
//  These live apart from the engine because the engine cannot be driven by a test.
//  The behaviour is gated on a monotonic clock, a main-runloop Timer, real audio
//  hardware, and an async post-start check — so every rule below used to be
//  verifiable only by reproducing a hardware failure by hand. Both defects found on
//  2026-09-01 were single rows of the truth tables here (a dead input reported as a
//  denied permission; a watchdog that stopped watching after giving up), and both
//  would have been caught by a unit test the moment they were written.
//
//  Calibration and incident history: hub docs/AUDIO-WATCHDOG-SILENT-STREAM.md.
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
/// Silence alone is NOT evidence of a denial. macOS can report `.authorized` while the
/// hardware is muted, which is why silence was treated as proof in the first place —
/// but a dead-but-present device produces byte-identical output. Reading every silence
/// as a denial takes a hardware failure, blames the user's permissions, and stops the
/// engine, which also cancels the dead-input watchdog's remaining recovery attempts.
///
/// So silence counts only when the input has never worked this session — permission
/// cannot be silently revoked and re-granted mid-session — and never on a watchdog
/// recovery restart, which is expected to begin silent when the input is genuinely dead.
///
/// Swift-only by design: Python detects denial from PortAudio's stream-open error and
/// the web from `getUserMedia`'s `NotAllowedError`, so neither ever has to infer it.
func shouldDeclarePermissionDenied(
    tccDenied: Bool,
    perfectSilence: Bool,
    hasEverReceivedSignal: Bool,
    startedByWatchdogRecovery: Bool
) -> Bool {
    if tccDenied { return true }
    guard perfectSilence else { return false }
    return !hasEverReceivedSignal && !startedByWatchdogRecovery
}
