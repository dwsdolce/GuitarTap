//
//  InputLevelTests.swift
//  GuitarTapTests
//
//  One contract, three mechanisms: an audio buffer's level is announced on the input level alone.
//
//  The level changes on every buffer, many times a second. Whatever announces it is redrawn that
//  often, so only the threshold meter may hear it: announced on the engine, or by the analyzer, every
//  buffer would rebuild every view that observes them — the whole main window. The values were right
//  all along when that happened; only who was told was wrong, so the value tests could not see it.
//
//  Swift checks `objectWillChange` on each object, Python which signals fire, the web which listeners
//  and callbacks are called.
//
//  Mirrors: tests/test_input_level.py · test/input-level.test.ts
//
// @parity test/input-level

import Testing
import Foundation
import Combine
@testable import GuitarTap

@Suite("InputLevel", .serialized)
@MainActor
struct InputLevelTests {

    /// Drains the main queue, where the engine publishes.
    private func drainMain() async {
        for _ in 0..<10 { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    /// One 0.1 s buffer at 48 kHz — the size CoreAudio hands Swift — of a quiet 1 kHz sine: well below
    /// any detection threshold, and far short of an FFT frame (65 536 samples).
    private func quietBuffer() -> [Float] {
        (0..<4800).map { 0.001 * sin(2 * .pi * 1000 * Float($0) / 48000) }
    }

    // IL1: a buffer, while the analyzer listens for a tap, is announced on the input level and by
    // nothing else.
    @Test func buffer_isAnnouncedOnTheInputLevelAlone() async {
        let fft = RealtimeFFTAnalyzer.forTesting()
        let sut = TapToneAnalyzer(fftAnalyzer: fft)
        TapDisplaySettings.measurementType = .generic
        sut.startTapSequence(skipWarmup: true)
        await drainMain()

        var level = 0, engine = 0, analyzer = 0
        let tokens = [
            fft.level.objectWillChange.sink { _ in level += 1 },
            fft.objectWillChange.sink { _ in engine += 1 },
            sut.objectWillChange.sink { _ in analyzer += 1 },
        ]
        defer { tokens.forEach { $0.cancel() } }

        fft.processRawSamples(quietBuffer())
        await drainMain()

        #expect(level > 0, "the buffer's level must reach the input level, or the meter stands still")
        #expect(engine == 0,
                "REGRESSION: the engine announced a change for one buffer — every view observing it is rebuilt on every buffer")
        #expect(analyzer == 0,
                "REGRESSION: the analyzer announced a change for one buffer — every view observing it is rebuilt on every buffer")
    }
}
