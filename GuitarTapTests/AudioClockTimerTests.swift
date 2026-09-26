//
//  AudioClockTimerTests.swift
//  GuitarTapTests
//
//  The tap lifecycle's delays run on the AUDIO clock, not the wall clock (#19). File playback
//  advances audio at "real time + processing time", so a wall-clock delay covered a different
//  stretch of audio on a slower run and late captures in a sequence moved.
//
//  Each case here advances only audio — through `onChunkLevel`, the path audio takes — and no
//  wall time to speak of, so a delay that went back to the wall clock would not have fired and the
//  case fails. The guitar rest (T1) and the capture window (T5) are pinned by the scenario traces'
//  `midCooldown` / `postReArm` / `postProcess` rows; this file pins what nothing else did.
//
//  Paired with Python tests/test_audio_clock_timers.py and web test/audio-clock-timers.test.ts.
//
// @parity test/audio-clock-timers

import Testing
import Foundation
@testable import GuitarTap

@MainActor
private func makeSUT(_ type: MeasurementType, numberOfTaps: Int, measureFlc: Bool = false) -> TapToneAnalyzer {
    TapDisplaySettings.measurementType = type
    TapDisplaySettings.measureFlc = measureFlc
    let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
    sut.numberOfTaps = numberOfTaps
    sut.cancellables.removeAll()
    // An unstarted analyzer has no frequency bins (all 0 Hz); build them as starting the engine does.
    // They are published asynchronously, so each guitar case waits briefly after arming.
    sut.fftAnalyzer.actualSampleRate = 48000
    sut.fftAnalyzer.updateFrequencyBins()
    return sut
}

/// A decaying tone — a tap's ring-out.
private func tapSamples(_ hz: Float, count: Int) -> [Float] {
    (0..<count).map { i in
        let t = Float(i) / 48000
        return 0.5 * expf(-t * 6) * sinf(2 * .pi * hz * t)
    }
}

/// A material spectrum whose presence is all acceptCurrentPhase needs.
private func spec() -> (magnitudes: [Float], frequencies: [Float]) {
    (magnitudes: [Float](repeating: -60, count: 64), frequencies: (0..<64).map { Float($0) * 30 })
}

@Suite("AudioClockTimers", .serialized)
@MainActor
struct AudioClockTimerTests {

    init() { TapDisplaySettings.measurementType = .generic }

    // T2: between taps of one plate/brace phase, detection rests `tapCooldown` of audio.
    @Test("the plate/brace rest between taps runs on the audio clock")
    func plateRestRunsOnAudioClock() {
        let sut = makeSUT(.plate, numberOfTaps: 2)
        defer { TapDisplaySettings.measurementType = .generic }
        sut.tapDetectionThreshold = -90   // accept the synthetic tap
        sut.startTapSequence()
        // A detected tap, as detection delivers it: detection stops and the gated capture opens...
        sut.handleTapDetection(magnitudes: [], frequencies: [], time: Date(), audioTime: sut.lastAudioTime)
        // ...and the capture completes through the real path.
        sut.finishGatedFFTCapture(samples: tapSamples(60, count: 24_000), sampleRate: 48000,
                                  phase: .capturingLongitudinal)
        #expect(sut.materialTapPhase == .capturingLongitudinal, "1 of 2 taps — the phase is not done")
        #expect(sut.isDetecting == false, "resting after the tap")

        advanceAudio(sut, by: sut.tapCooldown / 2)
        #expect(sut.isDetecting == false, "halfway through the rest, in audio")

        advanceAudio(sut, by: sut.tapCooldown / 2)
        #expect(sut.isDetecting == true, "re-armed once the rest's audio has passed")
    }

    // T3: after C is accepted, the FLC phase arms `tapCooldown` of audio later — anchored on the chunk
    // that made the hold due.
    @Test("the FLC hold runs on the audio clock")
    func flcHoldRunsOnAudioClock() {
        let sut = makeSUT(.plate, numberOfTaps: 1, measureFlc: true)
        defer { TapDisplaySettings.measurementType = .generic; TapDisplaySettings.measureFlc = false }
        sut.longitudinalSpectrum = spec()
        sut.crossSpectrum = spec()
        sut.materialTapPhase = .reviewingCross

        sut.acceptCurrentPhase()
        #expect(sut.materialTapPhase == .waitingForFlcTap)

        advanceAudio(sut, by: sut.tapCooldown / 2)
        #expect(sut.materialTapPhase == .waitingForFlcTap, "halfway through the hold, in audio")
        #expect(sut.isDetecting == false)

        advanceAudio(sut, by: sut.tapCooldown / 2)
        #expect(sut.materialTapPhase == .capturingFlc)
        #expect(sut.isDetecting == true)
        #expect(sut.warmupStartAudioTime == sut.lastAudioTime,
                "the FLC warm-up starts at the audio time of the chunk that ended the hold")
    }

    // File end: the capture window is released at once, so a measurement whose last capture ends
    // with the file still completes — the audio clock stops with the file.
    @Test("file end releases the pending capture window")
    func fileEndReleasesCaptureWindow() async throws {
        let sut = makeSUT(.generic, numberOfTaps: 1)
        sut.startTapSequence()
        try await Task.sleep(for: .milliseconds(50))   // the frequency bins land
        sut.finishGuitarGatedCapture(samples: tapSamples(100, count: sut.fftAnalyzer.fftSize), sampleRate: 48000)
        #expect(sut.isMeasurementComplete == false, "the capture window is pending")

        sut.flushGatedCaptureOnFileEnd()
        #expect(sut.isMeasurementComplete == true, "released at file end, with no further audio")
    }

    // File end does NOT release a rest: with no audio there is nothing to detect, so the re-arm waits
    // for audio like any other.
    @Test("file end does not release a pending rest")
    func fileEndDoesNotReleaseRest() async throws {
        let sut = makeSUT(.generic, numberOfTaps: 2)
        sut.startTapSequence()
        try await Task.sleep(for: .milliseconds(50))
        sut.finishGuitarGatedCapture(samples: tapSamples(100, count: sut.fftAnalyzer.fftSize), sampleRate: 48000)

        sut.flushGatedCaptureOnFileEnd()
        #expect(sut.isDetecting == false, "file end left the rest pending")

        advanceAudio(sut, by: sut.tapCooldown)
        #expect(sut.isDetecting == true, "the rest still ends when its audio has passed")
    }

    // A detected tap turns detection off first, and it stays off through the capture — the rest (T2)
    // then starts from the state the natives have always had. The tap is detected from fed audio.
    @Test("a detected tap turns detection off")
    func detectedTapTurnsDetectionOff() {
        let sut = makeSUT(.plate, numberOfTaps: 2)
        defer { TapDisplaySettings.measurementType = .generic }
        sut.startTapSequence()
        advanceAudio(sut, by: sut.warmupPeriod + 0.1)            // the warm-up, on quiet audio
        #expect(sut.isDetecting == true)
        advanceAudio(sut, by: 2 * audioFeedChunkSeconds, level: -10)   // a tap: two loud chunks
        #expect(sut.isDetecting == false, "detection is off once the tap is detected")
    }

    // T6: a capture the audio stops filling is closed on the WALL clock — it exists for when the audio
    // stops, and then the audio clock stops too. After it, detection rests and re-arms as usual.
    @Test("the safety timeout closes a capture the audio stopped filling")
    func safetyTimeoutClosesAnUnfilledCapture() async throws {
        let sut = makeSUT(.plate, numberOfTaps: 1)
        defer { TapDisplaySettings.measurementType = .generic }
        sut.startTapSequence()
        advanceAudio(sut, by: sut.warmupPeriod + 0.1)
        advanceAudio(sut, by: 2 * audioFeedChunkSeconds, level: -10)   // a tap opens the capture...
        #expect(sut.gatedCaptureActive == true)
        // ...and then no more audio arrives.
        try await Task.sleep(for: .milliseconds(2300))
        #expect(sut.gatedCaptureActive == false, "closed by the wall-clock safety timeout")

        advanceAudio(sut, by: sut.tapCooldown)
        #expect(sut.isDetecting == true, "and detection rests, then re-arms, as after any capture")
    }

    // T6 measures SILENCE, not time since the capture started: while audio keeps arriving — however
    // slowly, as under throttled playback — it does not fire. Measured from the capture's start, it
    // closed captures early whenever playback ran slower than real time (#19).
    @Test("the safety timeout does not fire while audio keeps arriving")
    func safetyTimeoutWaitsForSilence() async throws {
        let sut = makeSUT(.plate, numberOfTaps: 1)
        defer { TapDisplaySettings.measurementType = .generic }
        sut.startTapSequence()
        advanceAudio(sut, by: sut.warmupPeriod + 0.1)
        advanceAudio(sut, by: 2 * audioFeedChunkSeconds, level: -10)   // a tap opens the capture
        #expect(sut.gatedCaptureActive == true)
        // Slow audio: one quiet chunk every 0.4 s of wall time, for 2.8 s — longer than the 2 s timeout.
        for _ in 0..<7 {
            try await Task.sleep(for: .milliseconds(400))
            advanceAudio(sut, by: audioFeedChunkSeconds)
        }
        #expect(sut.gatedCaptureActive == true, "audio kept arriving, so the capture is still open")
    }

    // File playback's auto-advance: when a phase completes while a file plays, the next phase is
    // listening at once, the latch ABOVE so the last tap's ring-out must fall before anything counts;
    // the warm-up is not restarted.
    @Test("file playback's auto-advance arms the next phase at once, latched above")
    func autoAdvanceArmsAtOnceLatchedAbove() {
        let sut = makeSUT(.plate, numberOfTaps: 1)
        defer { TapDisplaySettings.measurementType = .generic }
        sut.fftAnalyzer.isPlayingFile = true
        sut.tapDetectionThreshold = -90   // accept the synthetic tap
        sut.startTapSequence()
        let warmupAnchor = sut.warmupStartAudioTime
        sut.handleTapDetection(magnitudes: [], frequencies: [], time: Date(), audioTime: sut.lastAudioTime)
        sut.finishGatedFFTCapture(samples: tapSamples(60, count: 24_000), sampleRate: 48000,
                                  phase: .capturingLongitudinal)

        #expect(sut.materialTapPhase == .capturingCross, "L done — auto-advanced to C")
        #expect(sut.isDetecting == true, "listening at once")
        #expect(sut.isAboveThreshold == true, "latched above: the ring-out must fall first")
        #expect(sut.warmupStartAudioTime == warmupAnchor, "the warm-up is not restarted")
    }

    // T7: ring-out tracking stops once a chunk arrives `decayTrackingDuration` of audio after the tap,
    // and that chunk is not applied.
    @Test("ring-out tracking stops on the audio clock")
    func ringOutTrackingStopsOnAudioClock() {
        let sut = makeSUT(.generic, numberOfTaps: 1)
        sut.startDecayTracking(tapAudioTime: 10)
        let end = 10 + sut.decayTrackingDuration

        sut.trackDecayFast(inputLevel: -40, audioTime: end - 0.01)
        #expect(sut.isTrackingDecay == true, "still inside the window")
        let samplesBefore = sut.peakMagnitudeHistory.count

        sut.trackDecayFast(inputLevel: -40, audioTime: end)
        #expect(sut.isTrackingDecay == false, "stopped by the audio clock alone")
        #expect(sut.peakMagnitudeHistory.count == samplesBefore, "the stopping chunk is not applied")
    }
}
