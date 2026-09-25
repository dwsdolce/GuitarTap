//
//  TapProgressTests.swift
//  GuitarTapTests
//
//  Pins `totalPlateTaps` + `tapProgress` + the CUMULATIVE material `currentTapCount` — the values
//  the status-bar tap/phase progress bar renders (`ProgressView(value: tap.tapProgress)`,
//  TapToneAnalysisView+Controls:420).
//
//  Why this suite exists: the web port's material `currentTapCount` used to RESET at every phase
//  advance, while Swift/Python count CUMULATIVELY across L → C → FLC.  The status TEXT agreed by
//  coincidence (the web printed its per-phase count directly; Swift subtracts the completed phases
//  from its cumulative one — Controls:411), so nothing caught it.  Adding the progress bar to the
//  other two platforms exposed it: the web's bar would have refilled 0→100% on EVERY phase, and
//  Python's view recomputed the percentage from `numberOfTaps` instead of rendering `tapProgress`,
//  pinning its bar at 100% from the end of phase L onward.
//
//  Swift was correct on all counts — these tests lock that in as the 3-way contract:
//
//      totalPlateTaps = numberOfTaps × (brace ? 1 : measureFlc ? 3 : 2)   [TapDetection:360]
//      tapProgress    = min(1, currentTapCount / (guitar ? numberOfTaps : totalPlateTaps))
//      currentTapCount (material) is CUMULATIVE, and rebases to the PRIOR phases' taps on redo
//                                                                         [Control:465-487]
//
// @parity test/tap-progress

import Testing
import Foundation
@testable import GuitarTap

@MainActor
private func makeSUT(numberOfTaps: Int,
                     measurementType: MeasurementType,
                     measureFlc: Bool = false) -> TapToneAnalyzer {
    TapDisplaySettings.measurementType = measurementType
    TapDisplaySettings.measureFlc = measureFlc
    let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
    sut.numberOfTaps = numberOfTaps
    return sut
}

/// A minimal material spectrum — only its PRESENCE matters to the redo rebasing guards.
private func spec() -> (magnitudes: [Float], frequencies: [Float]) {
    (magnitudes: [Float](repeating: -60, count: 64),
     frequencies: (0..<64).map { Float($0) * 30 })
}

// MARK: - totalPlateTaps — taps expected across ALL phases

@MainActor
@Suite("totalPlateTaps")
struct TotalPlateTapsTests {

    @Test("brace = numberOfTaps (longitudinal phase only)")
    func braceIsNumberOfTaps() {
        #expect(makeSUT(numberOfTaps: 3, measurementType: .brace).totalPlateTaps == 3)
    }

    @Test("plate without FLC = numberOfTaps × 2 (L + C)")
    func plateWithoutFlcIsDouble() {
        #expect(makeSUT(numberOfTaps: 3, measurementType: .plate, measureFlc: false)
                    .totalPlateTaps == 6)
    }

    @Test("plate with FLC = numberOfTaps × 3 (L + C + FLC)")
    func plateWithFlcIsTriple() {
        #expect(makeSUT(numberOfTaps: 3, measurementType: .plate, measureFlc: true)
                    .totalPlateTaps == 9)
    }
}

// MARK: - tapProgress — the fraction the bar renders

@MainActor
@Suite("tapProgress")
struct TapProgressValueTests {

    @Test("guitar divides by numberOfTaps")
    func guitarDividesByNumberOfTaps() {
        let sut = makeSUT(numberOfTaps: 4, measurementType: .generic)
        sut.currentTapCount = 1
        sut.tapProgress = min(1.0, Float(sut.currentTapCount) / Float(sut.numberOfTaps))
        #expect(abs(sut.tapProgress - 0.25) < 0.0001)
    }

    /// The assertion the web violated: with `numberOfTaps` as the denominator, a cumulative count
    /// of 2 in a 2-tap plate reads 100% at the END OF PHASE L, not one third.
    @Test("material divides by totalPlateTaps, NOT numberOfTaps")
    func materialDividesByTotalPlateTaps() {
        let sut = makeSUT(numberOfTaps: 2, measurementType: .plate, measureFlc: true)
        #expect(sut.totalPlateTaps == 6)

        sut.currentTapCount = 2 // end of phase L: 2 of 6 taps done
        #expect(abs(Float(sut.currentTapCount) / Float(sut.totalPlateTaps) - 2.0 / 6.0) < 0.0001)
        // The WRONG denominator would read a full bar here:
        #expect(Float(sut.currentTapCount) / Float(sut.numberOfTaps) == 1.0)
    }

    @Test("progress is clamped to 1")
    func progressIsClamped() {
        let sut = makeSUT(numberOfTaps: 2, measurementType: .brace)
        sut.currentTapCount = 5 // over-count
        #expect(min(1.0, Float(sut.currentTapCount) / Float(sut.totalPlateTaps)) == 1.0)
    }
}

// MARK: - The counter must SURVIVE a phase advance (drives the real gated-capture path)

/// A decaying sinusoid — a synthetic tap with a single resonance at `freqHz`.
private func tapSamples(_ freqHz: Float, sampleRate: Float = 48000, dur: Float = 0.5,
                        amp: Float = 0.5) -> [Float] {
    let n = Int(sampleRate * dur)
    return (0..<n).map { i in
        let t = Float(i) / sampleRate
        return amp * expf(-t * 6.0) * sinf(2 * .pi * freqHz * t)
    }
}

@MainActor
@Suite("Cumulative count survives a phase advance")
struct CountSurvivesPhaseAdvanceTests {

    /// The regression this whole suite exists for. `currentTapCount` is CUMULATIVE across
    /// L → C → FLC. Swift gets this right by keeping the counter (`currentTapCount += 1`)
    /// SEPARATE from the within-phase buffer (`materialCapturedTaps`, cleared each phase).
    /// The Python port derived the counter from the buffer's length and the web port reset it
    /// per phase — both restarted the count at every phase boundary, resetting the progress bar
    /// and clamping the plate label to "Tap 0/N". Asserting the equations alone does NOT catch
    /// this; only driving the real capture path across an Accept does.
    @Test("count accumulates across L → C — it must not restart at the phase boundary")
    func countAccumulatesAcrossPhaseAdvance() {
        let sut = makeSUT(numberOfTaps: 2, measurementType: .plate, measureFlc: true) // total = 6
        sut.tapDetectionThreshold = -90 // accept the synthetic taps
        let sr: Double = 48000

        // Phase L — two taps at 60 Hz (plate L band = 20–100 Hz).
        sut.materialTapPhase = .capturingLongitudinal
        sut.finishGatedFFTCapture(samples: tapSamples(60), sampleRate: sr,
                                  phase: .capturingLongitudinal)
        #expect(sut.currentTapCount == 1)
        #expect(abs(sut.tapProgress - 1.0 / 6.0) < 0.0001)

        sut.finishGatedFFTCapture(samples: tapSamples(60), sampleRate: sr,
                                  phase: .capturingLongitudinal)
        #expect(sut.currentTapCount == 2) // L complete
        #expect(abs(sut.tapProgress - 2.0 / 6.0) < 0.0001)

        // Accept L → C: the count must NOT reset.
        sut.acceptCurrentPhase()
        #expect(sut.currentTapCount == 2)

        // Phase C — the first C tap is the 3rd tap of the SEQUENCE, not the 1st of the phase.
        sut.finishGatedFFTCapture(samples: tapSamples(150), sampleRate: sr,
                                  phase: .capturingCross)
        #expect(sut.currentTapCount == 3)
        #expect(abs(sut.tapProgress - 3.0 / 6.0) < 0.0001)

        sut.finishGatedFFTCapture(samples: tapSamples(150), sampleRate: sr,
                                  phase: .capturingCross)
        #expect(sut.currentTapCount == 4)
        #expect(abs(sut.tapProgress - 4.0 / 6.0) < 0.0001)
    }
}

// MARK: - Redo rebases the cumulative count to the PRIOR phases

@MainActor
@Suite("Redo rebases the cumulative material count")
struct RedoRebasesCumulativeCountTests {

    @Test("redo C keeps L's taps counted (currentTapCount = lCount, not 0)")
    func redoCrossKeepsLongitudinal() {
        let sut = makeSUT(numberOfTaps: 2, measurementType: .plate, measureFlc: true) // total = 6
        sut.longitudinalSpectrum = spec() // L was captured
        sut.currentTapCount = 4           // L (2) + C (2)
        sut.materialTapPhase = .reviewingCross

        sut.redoCurrentPhase()

        #expect(sut.currentTapCount == 2) // L's taps stay counted
        #expect(abs(sut.tapProgress - 2.0 / 6.0) < 0.0001)
    }

    @Test("redo FLC keeps L+C counted (currentTapCount = lcCount = numberOfTaps × 2)")
    func redoFlcKeepsLongitudinalAndCross() {
        let sut = makeSUT(numberOfTaps: 2, measurementType: .plate, measureFlc: true) // total = 6
        sut.longitudinalSpectrum = spec()
        sut.crossSpectrum = spec()
        sut.currentTapCount = 6
        sut.materialTapPhase = .reviewingFlc

        sut.redoCurrentPhase()

        #expect(sut.currentTapCount == 4) // L + C stay counted
        #expect(abs(sut.tapProgress - 4.0 / 6.0) < 0.0001)
    }

    @Test("redo L resets to 0 (nothing precedes it)")
    func redoLongitudinalResetsToZero() {
        let sut = makeSUT(numberOfTaps: 2, measurementType: .plate, measureFlc: true)
        sut.longitudinalSpectrum = spec()
        sut.currentTapCount = 2
        sut.materialTapPhase = .reviewingLongitudinal

        sut.redoCurrentPhase()

        #expect(sut.currentTapCount == 0)
        #expect(sut.tapProgress == 0.0)
    }
}

// MARK: - FLC cooldown cancellation (#17)

@Suite("The FLC cooldown must not re-arm a cancelled sequence")
struct FlcCooldownCancellationTests {

    /// Accepting fC schedules a 0.5 s hold, after which detection re-arms for the FLC tap. The
    /// closure runs on the audio clock (`afterAudio`, #19), which cannot be cancelled, and
    /// `cancelTapSequence()`'s `captureTimer.invalidate()` does not reach it — so without a phase
    /// guard it fires into whatever sequence happens to be running half a second later, forcing
    /// `.capturingFlc` and `detectionState = .listening` onto a measurement the user already restarted.
    ///
    /// Both ports have always guarded this; Swift was the outlier. Mirrors Python
    /// `_do_start_flc`'s WAITING_FOR_FLC_TAP guard and the web's FLC cooldown timer.
    @Test("Cancel during the cooldown leaves the fresh sequence alone")
    @MainActor
    func cancelDuringFlcCooldownDoesNotReArm() async throws {
        let sut = makeSUT(numberOfTaps: 1, measurementType: .plate, measureFlc: true)
        sut.longitudinalSpectrum = spec()
        sut.crossSpectrum = spec()
        sut.materialTapPhase = .reviewingCross

        sut.acceptCurrentPhase()                       // → .waitingForFlcTap, schedules the re-arm
        #expect(sut.materialTapPhase == .waitingForFlcTap)

        sut.cancelTapSequence()                        // the user restarts before the cooldown elapses
        let phaseAfterCancel = sut.materialTapPhase
        #expect(phaseAfterCancel != .waitingForFlcTap) // the restart really did leave the FLC wait

        advanceAudio(sut, by: 0.8)                     // outlast the 0.5 s hold, in audio (#19)

        #expect(sut.materialTapPhase == phaseAfterCancel,
                "the cooldown closure dragged a cancelled sequence back into the FLC phase")
        #expect(sut.materialTapPhase != .capturingFlc)
    }
}
// ---------------------------------------------------------------------------
// MARK: - A later count change must not rewrite a finished measurement (#17 F34)
// ---------------------------------------------------------------------------

/// `tapProgress` is STORED, written at each capture site and pinned to 1.0 at completion — so a
/// completed measurement's bar records what was actually measured. Raising the tap count afterwards
/// configures the NEXT measurement and must leave the finished one alone. Web derived it at render
/// time instead, so a complete 1-tap measurement's full bar dropped to a third when Taps went to 3.
@Suite("TapProgressAfterCountChange", .serialized)
@MainActor
struct TapProgressAfterCountChangeTests {

    @Test func completeMeasurement_keepsFullBar_whenTapCountRaised() {
        let sut = makeSUT(numberOfTaps: 1, measurementType: .generic)
        sut.currentTapCount = 1
        sut.tapProgress = 1.0
        sut.isMeasurementComplete = true

        sut.numberOfTaps = 3   // configures the next measurement

        #expect(sut.tapProgress == 1.0,
                "REGRESSION: tapProgress must be stored, not derived — a later count change cannot rewrite a finished measurement's bar")
    }
}
