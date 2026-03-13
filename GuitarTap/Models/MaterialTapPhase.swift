//
//  MaterialTapPhase.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

/// # MaterialTapPhase
///
/// Tracks the current phase of a multi-tap material measurement sequence.
///
/// Accurate wood-property calculations from tap tones require separate impulse-response
/// captures in specific orientations.  The phases progress linearly through a state machine
/// managed by ``TapToneAnalyzer``:
///
/// ## Plate Measurement State Machine (2 or 3 taps)
///
/// ```
/// notStarted
///   └─▶ capturingLongitudinal   (tap along grain)
///         └─▶ waitingForCrossTap
///               └─▶ capturingCross          (tap across grain, plate rotated 90°)
///                     ├─▶ waitingForFlcTap  (if measureFlc == true)
///                     │     └─▶ capturingFlc   (diagonal corner tap)
///                     │           └─▶ complete
///                     └─▶ complete           (if measureFlc == false)
/// ```
///
/// ## Brace Measurement State Machine (1 tap)
///
/// ```
/// notStarted
///   └─▶ capturingLongitudinal
///         └─▶ complete
/// ```
///
/// The ``instruction`` and ``shortStatus`` computed properties supply UI strings for each state
/// so that views remain decoupled from the state logic.
import Foundation

/// The current phase of a multi-tap material measurement sequence (plate or brace).
///
/// The analyzer drives transitions through these phases in response to detected tap events
/// and gated-FFT capture completions.
///
/// - SeeAlso: ``TapToneAnalyzer`` for the state-machine transitions.
/// - SeeAlso: `MaterialProperties` for the acoustic calculations that consume data from each phase.
enum MaterialTapPhase: String {

    // MARK: - Cases

    /// No tap sequence has been started yet.
    ///
    /// The initial state after app launch, after a measurement is saved, or after a reset.
    case notStarted = "Not Started"

    /// A longitudinal (along-grain) gated FFT capture is actively accumulating samples.
    case capturingLongitudinal = "Capturing Longitudinal"

    /// The longitudinal capture is complete; the app is waiting for the user to
    /// rotate the plate 90° and perform the cross-grain tap.
    case waitingForCrossTap = "Waiting for Cross-grain Tap"

    /// A cross-grain gated FFT capture is actively accumulating samples.
    case capturingCross = "Capturing Cross-grain"

    /// Both longitudinal and cross captures are complete; the app is waiting for the
    /// optional FLC (diagonal / shear) tap.
    ///
    /// - Note: This state is only entered when `measureFlc` is `true` in
    ///   ``TapDisplaySettings``.
    case waitingForFlcTap = "Waiting for FLC Tap"

    /// An FLC (diagonal) gated FFT capture is actively accumulating samples.
    case capturingFlc = "Capturing FLC"

    /// All required taps have been captured and processed.
    ///
    /// Acoustic properties (Young's modulus, specific modulus, etc.) can now be computed
    /// from the captured phase data.
    case complete = "Complete"

    // MARK: - UI Strings

    /// Full instructional text appropriate for the current phase.
    ///
    /// Suitable for display in a full-size instructions area or tooltip.
    var instruction: String {
        switch self {
        case .notStarted:
            return "Press New Tap to begin measurement"
        case .capturingLongitudinal:
            return "Processing longitudinal tap..."
        case .waitingForCrossTap:
            return "Now rotate plate 90° and tap again for cross-grain"
        case .capturingCross:
            return "Processing cross-grain tap..."
        case .waitingForFlcTap:
            // FLC technique: hold at the midpoint of one long edge, tap near the opposite corner
            // at approximately 22% from both the end and the side (node of the shear mode).
            return "Hold plate at the midpoint of one long edge. Tap near the opposite corner (~22% from both the end and the side)"
        case .capturingFlc:
            return "Processing FLC tap..."
        case .complete:
            return "Measurement complete"
        }
    }

    /// Abbreviated status string for display in compact UI elements such as the status bar.
    var shortStatus: String {
        switch self {
        case .notStarted:           return "Ready"
        case .capturingLongitudinal: return "L tap..."
        case .waitingForCrossTap:   return "Tap for C"
        case .capturingCross:       return "C tap..."
        case .waitingForFlcTap:     return "Tap for FLC"
        case .capturingFlc:         return "FLC tap..."
        case .complete:             return "Done"
        }
    }
}
