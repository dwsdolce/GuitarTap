//
//  TapProgressTests.swift
//  GuitarTapTests
//
//  Pins `totalPlateTaps` + `tapProgress` + the CUMULATIVE material `currentTapCount` — the values
//  the status-bar tap/phase progress bar renders (`ProgressView(value: tap.tapProgress)`,
//  TapToneAnalysisView+Controls).
//
//  Why this suite exists: the web port's material `currentTapCount` used to RESET at every phase
//  advance, while Swift/Python count CUMULATIVELY across L → C → FLC.  The status TEXT agreed by
//  coincidence (the web printed its per-phase count directly; Swift subtracts the completed phases
//  from its cumulative one in the status-bar label), so nothing caught it.  Adding the progress bar to the
//  other two platforms exposed it: the web's bar would have refilled 0→100% on EVERY phase, and
//  Python's view recomputed the percentage from `numberOfTaps` instead of rendering `tapProgress`,
//  pinning its bar at 100% from the end of phase L onward.
//
//  Swift was correct on all counts — these tests lock that in as the 3-way contract:
//
//      totalPlateTaps = numberOfTaps × (brace ? 1 : measureFlc ? 3 : 2)   [`totalPlateTaps`]
//      tapProgress    = min(1, currentTapCount / (guitar ? numberOfTaps : totalPlateTaps))
//      currentTapCount (material) is CUMULATIVE, and rebases to the PRIOR phases' taps on redo
//                                                                         [`redoCurrentPhase`]
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

    /// A guitar measurement's bar advances by `numberOfTaps`, through the real capture finish — the
    /// place progress is decided. The material denominator is asserted by the count-across-phases case
    /// below.
    @Test("guitar progress advances by numberOfTaps as taps are captured")
    func guitarProgressAdvancesByNumberOfTaps() async throws {
        let sut = makeSUT(numberOfTaps: 4, measurementType: .generic)
        // An unstarted analyzer has no frequency bins (all 0 Hz); set them up as starting the engine or
        // file playback does, and let the main queue publish them (as StateInvariantTests does).
        sut.fftAnalyzer.actualSampleRate = 48000
        sut.fftAnalyzer.updateFrequencyBins()
        try await Task.sleep(for: .milliseconds(50))
        sut.startTapSequence()
        #expect(sut.tapProgress == 0)

        let tap = tapSamples(100, dur: Float(sut.fftAnalyzer.fftSize) / 48000)
        sut.finishGuitarGatedCapture(samples: tap, sampleRate: 48000)
        #expect(abs(sut.tapProgress - 0.25) < 0.0001)
        sut.finishGuitarGatedCapture(samples: tap, sampleRate: 48000)
        #expect(abs(sut.tapProgress - 0.5) < 0.0001)
        sut.finishGuitarGatedCapture(samples: tap, sampleRate: 48000)
        #expect(abs(sut.tapProgress - 0.75) < 0.0001)
    }

    /// A new sequence starts its bar at 0 — a finished measurement's full bar does not carry into it.
    @Test("a new sequence resets the bar")
    func newSequenceResetsTheBar() async throws {
        let sut = makeSUT(numberOfTaps: 1, measurementType: .generic)
        sut.fftAnalyzer.actualSampleRate = 48000
        sut.fftAnalyzer.updateFrequencyBins()
        try await Task.sleep(for: .milliseconds(50))
        sut.startTapSequence()
        sut.finishGuitarGatedCapture(samples: tapSamples(100, dur: Float(sut.fftAnalyzer.fftSize) / 48000),
                                     sampleRate: 48000)
        advanceAudio(sut, by: sut.captureWindow)       // complete
        #expect(sut.isMeasurementComplete)
        #expect(sut.tapProgress == 1.0)

        sut.startTapSequence()                         // New Tap

        #expect(sut.tapProgress == 0)
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

/// A plate sequence driven to its first review, through real taps at the capture finish: L tapped
/// `numberOfTaps` times. The phase and count are the app's, not the test's.
@MainActor
private func plateReviewingL(_ sut: TapToneAnalyzer) {
    sut.startTapSequence()
    for _ in 0..<sut.numberOfTaps {
        sut.finishGatedFFTCapture(samples: tapSamples(60), sampleRate: 48000, phase: .capturingLongitudinal)
    }
}

/// On to C's review: Accept L, then C tapped `numberOfTaps` times.
@MainActor
private func plateReviewingC(_ sut: TapToneAnalyzer) {
    plateReviewingL(sut)
    sut.acceptCurrentPhase()
    for _ in 0..<sut.numberOfTaps {
        sut.finishGatedFFTCapture(samples: tapSamples(150), sampleRate: 48000, phase: .capturingCross)
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
        sut.startTapSequence()                           // capturing L, as the app arms it
        #expect(sut.materialTapPhase == .capturingLongitudinal)

        // Phase L — two taps at 60 Hz (plate L band = 20–100 Hz).
        sut.finishGatedFFTCapture(samples: tapSamples(60), sampleRate: 48000, phase: .capturingLongitudinal)
        #expect(sut.currentTapCount == 1)
        #expect(abs(sut.tapProgress - 1.0 / 6.0) < 0.0001)

        sut.finishGatedFFTCapture(samples: tapSamples(60), sampleRate: 48000, phase: .capturingLongitudinal)
        #expect(sut.currentTapCount == 2) // L complete
        #expect(abs(sut.tapProgress - 2.0 / 6.0) < 0.0001)

        // Accept L → C: the count must NOT reset.
        sut.acceptCurrentPhase()
        #expect(sut.currentTapCount == 2)

        // Phase C — the first C tap is the 3rd tap of the SEQUENCE, not the 1st of the phase.
        sut.finishGatedFFTCapture(samples: tapSamples(150), sampleRate: 48000, phase: .capturingCross)
        #expect(sut.currentTapCount == 3)
        #expect(abs(sut.tapProgress - 3.0 / 6.0) < 0.0001)

        sut.finishGatedFFTCapture(samples: tapSamples(150), sampleRate: 48000, phase: .capturingCross)
        #expect(sut.currentTapCount == 4)
        #expect(abs(sut.tapProgress - 4.0 / 6.0) < 0.0001)

        // Accept C → waiting for the FLC tap: L + C stay counted through the hold.
        sut.acceptCurrentPhase()
        #expect(sut.materialTapPhase == .waitingForFlcTap)
        #expect(sut.currentTapCount == 4)
        #expect(abs(sut.tapProgress - 4.0 / 6.0) < 0.0001)
    }

    /// Brace has one phase: its count and bar fill over its taps, and the last tap completes it.
    @Test("brace (single phase): the bar fills 0 → 1 over its taps")
    func braceBarFillsOverItsTaps() {
        let sut = makeSUT(numberOfTaps: 2, measurementType: .brace)   // total = 2
        sut.startTapSequence()
        sut.finishGatedFFTCapture(samples: tapSamples(150), sampleRate: 48000, phase: .capturingLongitudinal)
        #expect(sut.currentTapCount == 1)
        #expect(abs(sut.tapProgress - 0.5) < 0.0001)

        sut.finishGatedFFTCapture(samples: tapSamples(150), sampleRate: 48000, phase: .capturingLongitudinal)
        #expect(sut.currentTapCount == 2)
        #expect(sut.tapProgress == 1.0)
        #expect(sut.isMeasurementComplete)
    }
}

// MARK: - Redo rebases the cumulative count to the PRIOR phases

/// Each case reaches its review through real taps, real Accepts and — for FLC — the real hold, fed in
/// audio; none sets a spectrum, a count or a phase by hand.
@MainActor
@Suite("Redo rebases the cumulative material count")
struct RedoRebasesCumulativeCountTests {

    @Test("redo C keeps L's taps counted (currentTapCount = lCount, not 0)")
    func redoCrossKeepsLongitudinal() {
        let sut = makeSUT(numberOfTaps: 2, measurementType: .plate, measureFlc: true) // total = 6
        plateReviewingC(sut)
        #expect(sut.materialTapPhase == .reviewingCross)
        #expect(sut.currentTapCount == 4)                // L (2) + C (2)

        sut.redoCurrentPhase()

        #expect(sut.materialTapPhase == .capturingCross)
        #expect(sut.currentTapCount == 2) // L's taps stay counted
        #expect(abs(sut.tapProgress - 2.0 / 6.0) < 0.0001)
    }

    @Test("redo FLC keeps L+C counted (currentTapCount = lcCount = numberOfTaps × 2)")
    func redoFlcKeepsLongitudinalAndCross() {
        let sut = makeSUT(numberOfTaps: 2, measurementType: .plate, measureFlc: true) // total = 6
        plateReviewingC(sut)
        sut.acceptCurrentPhase()                          // → waiting for the FLC tap
        advanceAudio(sut, by: sut.tapCooldown)            // the hold, in audio → capturing FLC
        #expect(sut.materialTapPhase == .capturingFlc)
        for _ in 0..<2 {
            sut.finishGatedFFTCapture(samples: tapSamples(60), sampleRate: 48000, phase: .capturingFlc)
        }
        #expect(sut.materialTapPhase == .reviewingFlc)
        #expect(sut.currentTapCount == 6)

        sut.redoCurrentPhase()

        #expect(sut.materialTapPhase == .capturingFlc)
        #expect(sut.currentTapCount == 4) // L + C stay counted
        #expect(abs(sut.tapProgress - 4.0 / 6.0) < 0.0001)
    }

    @Test("redo L resets to 0 (nothing precedes it)")
    func redoLongitudinalResetsToZero() {
        let sut = makeSUT(numberOfTaps: 2, measurementType: .plate, measureFlc: true)
        plateReviewingL(sut)
        #expect(sut.materialTapPhase == .reviewingLongitudinal)
        #expect(sut.currentTapCount == 2)

        sut.redoCurrentPhase()

        #expect(sut.materialTapPhase == .capturingLongitudinal)
        #expect(sut.currentTapCount == 0)
        #expect(sut.tapProgress == 0.0)
    }
}

// MARK: - FLC cooldown cancellation

@Suite("The FLC cooldown must not re-arm a cancelled sequence")
struct FlcCooldownCancellationTests {

    /// Accepting fC schedules a 0.5 s hold, after which detection re-arms for the FLC tap. The
    /// closure runs on the audio clock (`afterAudio`), which cannot be cancelled, and
    /// `cancelTapSequence()`'s `captureTimer.invalidate()` does not reach it — so without a phase
    /// guard it would fire into whatever sequence happens to be running half a second later, forcing
    /// `.capturingFlc` and `detectionState = .listening` onto a measurement the user already restarted.
    ///
    /// Mirrors Python
    /// `_do_start_flc`'s WAITING_FOR_FLC_TAP guard and the web's FLC cooldown timer.
    @Test("Cancel during the cooldown leaves the fresh sequence alone")
    @MainActor
    func cancelDuringFlcCooldownDoesNotReArm() {
        let sut = makeSUT(numberOfTaps: 1, measurementType: .plate, measureFlc: true)
        plateReviewingC(sut)                           // real taps and Accepts to C's review

        sut.acceptCurrentPhase()                       // → .waitingForFlcTap, schedules the re-arm
        #expect(sut.materialTapPhase == .waitingForFlcTap)

        sut.cancelTapSequence()                        // the user restarts before the cooldown elapses
        let phaseAfterCancel = sut.materialTapPhase
        #expect(phaseAfterCancel != .waitingForFlcTap) // the restart really did leave the FLC wait

        advanceAudio(sut, by: 0.8)                     // outlast the 0.5 s hold, in audio

        #expect(sut.materialTapPhase == phaseAfterCancel,
                "the cooldown closure dragged a cancelled sequence back into the FLC phase")
        #expect(sut.materialTapPhase != .capturingFlc)
    }
}
// MARK: - Loading a measurement tears down an interrupted capture

/// A saved classical measurement to load — built as MeasurementCompleteTransitionTests' MC7 builds one.
private func savedMeasurement() -> TapToneMeasurement {
    let freqs = (0..<64).map { Float($0) * 31.25 }
    var mags = [Float](repeating: -80, count: 64)
    mags[16] = -30
    let snap = SpectrumSnapshot(frequencies: freqs, magnitudes: mags, minFreq: 0, maxFreq: 2000,
                                minDB: -90, maxDB: -20, isLogarithmic: false, measurementType: .classical)
    return TapToneMeasurement(peaks: [], spectrum: snap, numberOfTaps: 1)
}

/// Loading a measurement while a capture is unfinished tears it down, so the status-bar progress bar
/// (shown while currentTapCount > 0) and the Analyzing indicator (isDetecting) do not linger over the
/// loaded measurement. The sequence is driven for real; the load is the real `loadMeasurement`.
/// Paired with Python TestLoadTearsDownInterruptedCapture and the web's "loadMeasurement tears down…".
@MainActor
@Suite("Loading a measurement tears down an interrupted capture")
struct LoadTearsDownInterruptedCaptureTests {

    @Test("a plate sequence abandoned after L+C (FLC pending) resets on load")
    func abandonedPlateSequenceResetsOnLoad() {
        let sut = makeSUT(numberOfTaps: 2, measurementType: .plate, measureFlc: true)
        plateReviewingC(sut)
        sut.acceptCurrentPhase()                          // → waiting for the FLC tap
        #expect(sut.currentTapCount == 4)
        #expect(sut.materialTapPhase == .waitingForFlcTap)

        sut.loadMeasurement(savedMeasurement())

        #expect(sut.currentTapCount == 0)
        #expect(sut.tapProgress == 0)
        #expect(sut.materialTapPhase == .complete)
        #expect(!sut.isDetecting)
        #expect(sut.isMeasurementComplete)
    }

    @Test("a load while detecting stops detection")
    func loadWhileDetectingStopsDetection() {
        let sut = makeSUT(numberOfTaps: 2, measurementType: .plate, measureFlc: true)
        sut.startTapSequence()
        sut.finishGatedFFTCapture(samples: tapSamples(60), sampleRate: 48000, phase: .capturingLongitudinal)
        advanceAudio(sut, by: sut.tapCooldown)            // the rest ends: listening for tap 2
        #expect(sut.isDetecting)
        #expect(sut.currentTapCount == 1)

        sut.loadMeasurement(savedMeasurement())

        #expect(!sut.isDetecting)
        #expect(sut.currentTapCount == 0)
        #expect(sut.materialTapPhase == .complete)
    }
}

// ---------------------------------------------------------------------------
// MARK: - A later count change must not rewrite a finished measurement
// ---------------------------------------------------------------------------

/// `tapProgress` is STORED, written at each capture site (the last tap leaves it at 1) — so a
/// completed measurement's bar records what was actually measured. Raising the tap count afterwards
/// configures the NEXT measurement and must leave the finished one alone: a complete 1-tap
/// measurement's full bar must not drop to a third when Taps goes to 3.
/// The measurement is completed for real: one tap through the finish, then the capture window's audio.
@Suite("TapProgressAfterCountChange", .serialized)
@MainActor
struct TapProgressAfterCountChangeTests {

    @Test func completeMeasurement_keepsFullBar_whenTapCountRaised() async throws {
        let sut = makeSUT(numberOfTaps: 1, measurementType: .generic)
        // An unstarted analyzer has no frequency bins (all 0 Hz); set them up as starting the engine or
        // file playback does, and let the main queue publish them (as StateInvariantTests does).
        sut.fftAnalyzer.actualSampleRate = 48000
        sut.fftAnalyzer.updateFrequencyBins()
        try await Task.sleep(for: .milliseconds(50))
        sut.startTapSequence()
        sut.finishGuitarGatedCapture(samples: tapSamples(100, dur: Float(sut.fftAnalyzer.fftSize) / 48000),
                                     sampleRate: 48000)
        advanceAudio(sut, by: sut.captureWindow)       // "All taps captured. Processing..." → complete
        #expect(sut.isMeasurementComplete)
        #expect(sut.tapProgress == 1.0)

        sut.numberOfTaps = 3   // configures the next measurement

        #expect(sut.tapProgress == 1.0,
                "REGRESSION: tapProgress must be stored, not derived — a later count change cannot rewrite a finished measurement's bar")
    }
}
