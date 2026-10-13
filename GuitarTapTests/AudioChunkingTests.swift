//
//  AudioChunkingTests.swift
//  GuitarTapTests
//
//  The pipeline processes fixed-size chunks, whatever size of buffer the microphone delivers.
//
//  CoreAudio chooses the size of the buffers it delivers; the size the tap asks for is only a hint.
//  The level meter, the tap detector, ring-out tracking and the session recording all advance once
//  per chunk, so a delivered buffer of 4800 frames must reach them as chunks of 1024 — the size
//  Python and the web process — with every sample kept, in order.
//
//  File playback cuts its own chunks, so no test that plays a file can see the size of a delivered
//  buffer; these feed delivered buffers directly.
//
// @parity none — Python and the web are handed chunks of this size by their audio layers.

import Testing
import Foundation
import Combine
@testable import GuitarTap

@Suite("AudioChunking", .serialized)
@MainActor
struct AudioChunkingTests {

    /// A ramp — every sample distinct, so a dropped, repeated or reordered sample shows.
    private func ramp(_ count: Int, from start: Int = 0) -> [Float] {
        (start..<(start + count)).map { Float($0) }
    }

    /// Feeds `total` samples of a ramp in delivered buffers of `size` and returns the chunks processed.
    private func chunks(deliveredIn size: Int, total: Int) -> [[Float]] {
        let fft = RealtimeFFTAnalyzer.forTesting()
        fft.actualSampleRate = 48000
        var seen: [[Float]] = []
        fft.rawSampleHandler = { samples, _ in seen.append(samples) }
        var sent = 0
        while sent < total {
            let n = min(size, total - sent)
            fft.processDeliveredSamples(ramp(n, from: sent))
            sent += n
        }
        return seen
    }

    // AC1: delivered buffers larger than, smaller than, and not a multiple of a chunk all reach the
    // pipeline as whole chunks, every sample kept in order.
    @Test(arguments: [4800, 777, 512, 1024])
    func deliveredBuffers_areProcessedAsWholeChunks(size: Int) {
        let total = 48000
        let seen = chunks(deliveredIn: size, total: total)
        let chunk = RealtimeFFTAnalyzer.chunkSize

        #expect(seen.allSatisfy { $0.count == chunk },
                "every processed chunk must be \(chunk) samples; sizes seen: \(Set(seen.map(\.count)).sorted())")
        #expect(seen.count == total / chunk, "only a remainder shorter than a chunk may be waiting")
        #expect(seen.flatMap { $0 } == ramp(seen.count * chunk),
                "REGRESSION: samples dropped, repeated or reordered between delivered buffers")
    }

    // AC2: the audio clock advances one chunk at a time, so what is timed against it — the warm-up,
    // ring-out — has the chunk's resolution, not the delivered buffer's.
    @Test func audioClock_advancesByWholeChunks() {
        let fft = RealtimeFFTAnalyzer.forTesting()
        fft.actualSampleRate = 48000
        var times: [Double] = []
        fft.rmsLevelHandler = { _, audioTime in times.append(audioTime) }

        fft.processDeliveredSamples(ramp(4800))

        let step = Double(RealtimeFFTAnalyzer.chunkSize) / 48000
        #expect(times.count == 4, "a 4800-frame buffer holds four whole chunks")
        for (i, t) in times.enumerated() {
            #expect(abs(t - Double(i + 1) * step) < 1e-9, "chunk \(i + 1) stamped \(t), expected \(Double(i + 1) * step)")
        }
    }

    // AC3: a delivered buffer's chunks are processed in the same instant, so the level meter is told
    // once per delivered buffer — the loudest of its chunks — not once per chunk.
    @Test func deliveredBuffer_announcesItsLevelOnce() async {
        let fft = RealtimeFFTAnalyzer.forTesting()
        fft.actualSampleRate = 48000
        var levels: [Float] = []
        let token = fft.level.$inputLevelDB.dropFirst().sink { levels.append($0) }
        defer { token.cancel() }

        // Four chunks: the second loud, the others quiet.
        let quiet = [Float](repeating: 0.001, count: 1024), loud = [Float](repeating: 0.1, count: 1024)
        fft.processDeliveredSamples(quiet + loud + quiet + quiet + [Float](repeating: 0, count: 704))
        for _ in 0..<10 { try? await Task.sleep(nanoseconds: 5_000_000) }

        #expect(levels.count == 1,
                "REGRESSION: one delivered buffer told the meter \(levels.count) times — it is redrawn that often in one frame")
        #expect(abs((levels.first ?? 0) - (-20)) < 0.01, "the level told is the loudest chunk's (-20 dB), got \(levels)")
    }
}
