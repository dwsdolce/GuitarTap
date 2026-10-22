//
//  StateInvariantTests.swift
//  GuitarTapTests
//
//  State combinations the design forbids, checked after real sequences of steps. They are the rules
//  Pause / New Tap / Cancel enablement and the audio-thread detection guards rest on, so a refactor
//  that broke one would show up as a UI bug even where each function looks right on its own. The
//  checker is below; the shared cases in `state-invariants.json` (V1–V13) run it after their steps
//  and test it on each forbidden state, the same as Python and the web.
//
// @parity test/state-invariants

import Testing
import Foundation
@testable import GuitarTap

private final class StateInvariantsAnchor {}

/// Checks that `analyzer` does not violate any of the documented state-machine
/// invariants.  Returns nil when all invariants hold, or a string describing
/// the first violation found.
///
/// Test files can call this after any operation to enforce that no path leaves
/// the analyzer in an impossible state.
@MainActor
func stateInvariantViolation(_ a: TapToneAnalyzer) -> String? {
    let isGuitar = TapDisplaySettings.measurementType.isGuitar

    // I1: For guitar mode, isDetecting && isMeasurementComplete is illegal.
    // The detector cannot be armed for a sequence that has already concluded.
    // This is the invariant the iPad bug violated.
    if isGuitar && a.isDetecting && a.isMeasurementComplete {
        return "I1: isDetecting && isMeasurementComplete is illegal in guitar mode"
    }

    // I2: isDetectionPaused implies the analyzer was actively detecting when
    // it was paused.  Pausing from a non-detecting state is meaningless.
    // Once paused, a complete measurement should drop the paused flag.
    if a.isDetectionPaused && a.isMeasurementComplete {
        return "I2: isDetectionPaused && isMeasurementComplete is illegal (cannot be paused once measurement is done)"
    }

    // I3: capturedTaps.count must never exceed numberOfTaps.  The gated
    // capture pipeline enforces this; a violation means a stray append.
    if a.capturedTaps.count > a.numberOfTaps {
        return "I3: capturedTaps.count (\(a.capturedTaps.count)) > numberOfTaps (\(a.numberOfTaps))"
    }

    // I4: currentTapCount must match capturedTaps.count for guitar mode.
    // (Plate/brace counts taps across phases differently and is excluded.)
    if isGuitar && a.currentTapCount != a.capturedTaps.count {
        return "I4: currentTapCount (\(a.currentTapCount)) != capturedTaps.count (\(a.capturedTaps.count)) in guitar mode"
    }

    // I5: tapProgress must be in [0, 1].
    if a.tapProgress < 0 || a.tapProgress > 1 {
        return "I5: tapProgress (\(a.tapProgress)) outside [0, 1]"
    }

    // I6: During a plate/brace review phase, isDetecting must be false.
    // Detection checks materialTapPhase.isCapturing; firing a tap during
    // a review phase would corrupt the captured spectrum.
    if !isGuitar {
        switch a.materialTapPhase {
        case .reviewingLongitudinal, .reviewingCross, .reviewingFlc:
            if a.isDetecting {
                return "I6: isDetecting must be false during a plate/brace review phase (phase=\(a.materialTapPhase))"
            }
        default:
            break
        }
    }

    return nil
}

@Suite("StateInvariants", .serialized)
@MainActor
struct StateInvariantTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: StateInvariantsAnchor.self).url(forResource: "state-invariants", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids() -> [String] {
        (data["cases"] as! [[String: Any]]).map { $0["id"] as! String }
    }

    static let detectionStates: [String: DetectionState] = ["idle": .idle, "listening": .listening, "paused": .paused]

    /// A captured tap for a `write` step: 64 bins at 31.25 Hz, −80 dB but bin 16 at −30.
    static func capturedTap() -> (magnitudes: [Float], frequencies: [Float], captureTime: Date) {
        var magnitudes = [Float](repeating: -80, count: 64)
        magnitudes[16] = -30
        return (magnitudes, (0..<64).map { Float($0) * 31.25 }, Date())
    }

    /// Sets the fields a `write` step names directly — only to give the checker a forbidden state.
    static func write(_ fields: [String: Any], on sut: TapToneAnalyzer) {
        for (field, value) in fields {
            switch field {
            case "detectionState": sut.detectionState = detectionStates[value as! String]!
            case "complete": sut.isMeasurementComplete = value as! Bool
            case "capturedTaps": sut.capturedTaps = (0..<(value as! Int)).map { _ in capturedTap() }
            case "tapCount": sut.currentTapCount = value as! Int
            case "tapProgress": sut.tapProgress = Float((value as! NSNumber).doubleValue)
            case "phase": sut.materialTapPhase = MaterialTapPhase(rawValue: value as! String)!
            default: Issue.record("unknown write field \(field)")
            }
        }
    }

    /// Asserts the fields an expectation names.
    static func check(_ fields: [String: Any], _ sut: TapToneAnalyzer, _ id: String) {
        for (field, want) in fields {
            switch field {
            case "violation":
                let rule = stateInvariantViolation(sut).map { String($0.prefix(2)) }
                #expect(rule == want as? String, "\(id) \(field): \(String(describing: stateInvariantViolation(sut)))")
            case "complete":
                #expect(sut.isMeasurementComplete == want as? Bool, "\(id) \(field)")
            case "detecting":
                #expect(sut.isDetecting == want as? Bool, "\(id) \(field)")
            case "capturedTaps":
                #expect(sut.capturedTaps.count == want as? Int, "\(id) \(field)")
            case "phase":
                #expect(sut.materialTapPhase.rawValue == want as? String, "\(id) \(field): \(sut.materialTapPhase)")
            default:
                Issue.record("\(id): unknown field \(field)")
            }
        }
    }

    @Test(arguments: ids())
    func invariants(_ id: String) {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let saved = (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc)
        defer { (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc) = saved }

        let sut = makeStepsAnalyzer()
        for step in row["steps"] as! [[String: Any]] {
            if let fields = step["check"] as? [String: Any] {
                Self.check(fields, sut, id)
            } else if let fields = step["write"] as? [String: Any] {
                Self.write(fields, on: sut)
            } else {
                #expect(runAnalyzerStep(step, on: sut), "\(id): unknown step \(step)")
            }
        }
        Self.check(row["expect"] as! [String: Any], sut, id)
    }
}
