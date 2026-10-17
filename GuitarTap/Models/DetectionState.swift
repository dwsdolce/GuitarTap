//
//  DetectionState.swift
//  GuitarTap
//
//  Created on 9/21/26.
//
// @parity state/tap-tone-analyzer

/// # DetectionState
///
/// The tap detector's state, held by ``TapToneAnalyzer`` as a single value.
///
/// ```
/// idle ──────▶ listening ──────▶ idle
///                 │   ▲            (tap captured, sequence cancelled,
///                 ▼   │             measurement loaded, stop)
///              paused ┘
///        (pause/resume, mid-sequence)
/// ```
///
/// This replaced an `isDetecting` / `isDetectionPaused` boolean pair.  Two booleans can
/// express "detecting AND paused" — a state no code path intends, which every site that
/// touched either flag had to avoid by hand, and which the invariant suite existed partly
/// to catch after the fact.  One value makes it unrepresentable.
///
/// The two booleans survive as computed reads on the analyzer, so call sites and tests that
/// only *ask* the question are unchanged; only the writes moved.
import Foundation

/// Whether the analyzer is listening for taps, paused mid-sequence, or neither.
///
/// - SeeAlso: ``TapToneAnalyzer/detectionState`` — the published property, whose `didSet`
///   arms and disarms the audio-queue level-crossing handler on entry to and exit from
///   ``listening``.
enum DetectionState: String {

    // MARK: - Cases

    /// Not listening.  The state before a sequence starts, after a tap is captured, after
    /// the measurement completes, and after a measurement is loaded for review.
    case idle = "idle"

    /// Actively listening for taps.  The audio-queue level-crossing handler is armed.
    case listening = "listening"

    /// The sequence is paused: detection is off but the tap count and captured taps are
    /// preserved, and the spectrum stays live so the user can play freely.
    ///
    /// Distinct from ``idle``, which discards the in-progress sequence.
    case paused = "paused"
}
