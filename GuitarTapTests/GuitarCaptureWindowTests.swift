//
//  GuitarCaptureWindowTests.swift
//  GuitarTapTests
//
//  A guitar tap reaches the transform as the same samples wherever the audio's chunk boundaries
//  fall.
//
//  The tap trigger fires on a chunk boundary, so the capture begins at a different sample from one
//  run to the next (and from one edition to the next) for the same tap. The window is aligned to
//  the tap's onset, which takes that out of its start — but the capture is exactly as long as the
//  window, so it runs out before the window's end, by an amount that depends on the boundary. The
//  window's audio therefore ends at a fixed length, short of the window's end by the most that
//  amount can be, and zeros follow: the same tap, the same window — and, measured from that window,
//  the same ring-out.
//
//  Mirrors: tests/test_guitar_capture_window.py · test/guitar-capture-window.test.ts
//
// @parity test/guitar-capture-window

import Testing
import Foundation
@testable import GuitarTap

private final class WindowAnchor {}

@Suite("GuitarCaptureWindow", .serialized)
@MainActor
struct GuitarCaptureWindowTests {

    static let sampleRate = 48000

    /// One second of quiet noise, then a tap — two decaying tones that start at full amplitude, so
    /// the onset is one unmistakable sample — ringing for longer than a capture.
    static func recording() -> [Float] {
        var state: UInt32 = 12345
        func noise() -> Float {
            state = state &* 1664525 &+ 1013904223
            return (Float(state >> 8) / Float(1 << 24) - 0.5) * 0.0005
        }
        let lead = sampleRate, tail = 80_000
        var samples = [Float](repeating: 0, count: lead + tail)
        for i in 0..<samples.count { samples[i] = noise() }
        for n in 0..<tail {
            let t = Double(n) / Double(sampleRate)
            let tone = 0.25 * cos(2 * .pi * 110 * t) * exp(-t * 4) + 0.1 * cos(2 * .pi * 237 * t) * exp(-t * 6)
            samples[lead + n] += Float(tone)
        }
        return samples
    }

    /// Writes mono 32-bit-float samples as a WAV in the test's temporary directory.
    static func writeWAV(_ samples: [Float], name: String) throws -> URL {
        var data = Data()
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
        let dataSize = UInt32(samples.count * 4)
        data.append(contentsOf: "RIFF".utf8); append((36 + dataSize).littleEndian)
        data.append(contentsOf: "WAVE".utf8); data.append(contentsOf: "fmt ".utf8)
        append(UInt32(16).littleEndian); append(UInt16(3).littleEndian); append(UInt16(1).littleEndian)
        append(UInt32(sampleRate).littleEndian); append(UInt32(sampleRate * 4).littleEndian)
        append(UInt16(4).littleEndian); append(UInt16(32).littleEndian)
        data.append(contentsOf: "data".utf8); append(dataSize.littleEndian)
        samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    /// Plays the recording with its first `dropped` samples removed — the same tap, its chunk
    /// boundaries `dropped` samples elsewhere — and returns the fingerprint of the window the
    /// capture handed to the transform, and the ring-out measured.
    private func capture(dropping dropped: Int) async throws -> (window: String?, ringOut: Float?) {
        let url = try Self.writeWAV(Array(Self.recording().dropFirst(dropped)), name: "guitar-window-\(dropped).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        CaptureProbe.reset()
        CaptureProbe.enabled = true
        defer { CaptureProbe.enabled = false }

        let sut = TapToneAnalyzer.forTesting()
        sut.tapDetectionThreshold = -40
        try await sut.playFileAndWait(url: url, measurementType: .generic, numberOfTaps: 1)

        let mine = String(UInt(bitPattern: ObjectIdentifier(sut).hashValue) % 10000)
        return (CaptureProbe.records.first { $0.instance == mine }?.windowHash, sut.currentDecayTime)
    }

    // GW1: the same tap, with its chunk boundaries at four different places, reaches the transform
    // as the same window.
    @Test func sameTap_sameWindow_whereverTheChunkBoundariesFall() async throws {
        var seen: [Int: String] = [:]
        for dropped in [0, 300, 700, 1000] {
            let fingerprint = try await capture(dropping: dropped).window
            #expect(fingerprint != nil, "no capture with the recording's first \(dropped) samples dropped")
            seen[dropped] = fingerprint
        }
        #expect(Set(seen.values).count == 1,
                "REGRESSION: the window differs with the chunk boundary — \(seen.sorted { $0.key < $1.key })")
    }

    // GW3: the same tap, with its chunk boundaries at four different places, measures the same
    // ring-out.
    @Test func sameTap_sameRingOut_whereverTheChunkBoundariesFall() async throws {
        var seen: [Int: Float] = [:]
        for dropped in [0, 300, 700, 1000] {
            let ringOut = try await capture(dropping: dropped).ringOut
            #expect(ringOut != nil, "no ring-out with the recording's first \(dropped) samples dropped")
            seen[dropped] = ringOut
        }
        #expect(Set(seen.values).count == 1,
                "REGRESSION: the ring-out differs with the chunk boundary — \(seen.sorted { $0.key < $1.key })")
    }

    /// Noise whose level rises and falls, then a tap that grows from nothing: the noise measured at
    /// one place gives a different threshold from the noise at another, and the tap's first sample
    /// above a threshold depends on the threshold.
    static func onsetTestSignal(length: Int = 40_000, tap: Int = 12_000) -> [Float] {
        var x = [Float](repeating: 0, count: length)
        var state: UInt32 = 24680
        for i in 0..<length {
            state = state &* 1664525 &+ 1013904223
            let u = Double(state >> 8) / Double(1 << 24) - 0.5
            x[i] = Float(u * 0.0008 * (1.0 + 0.6 * sin(2 * .pi * Double(i) / 3000.0)))
        }
        for m in 0..<(length - tap) {
            let t = Double(m)
            x[tap + m] += Float(0.3 * (1 - exp(-t / 300.0)) * sin(2 * .pi * 110 * t / 48000.0))
        }
        return x
    }

    // GW2: the same tap captured from seven different starting samples — as the trigger's chunk
    // boundary moves the capture's start — aligns to the same window.
    @Test func alignedWindow_isTheSame_whereverTheCaptureStarted() {
        let sut = TapToneAnalyzer.forTesting()
        let x = Self.onsetTestSignal()
        let starts = [0, 300, 700, 1000, 1500, 2200, 3000]
        let windows = starts.map { sut.alignCaptureToOnset(Array(x[$0...]), windowSize: 19_200, preOnsetSamples: 4_800) }
        let differing = zip(starts, windows).filter { $0.1 != windows[0] }.map(\.0)
        #expect(differing.isEmpty,
                "REGRESSION: the window depends on where the capture started — differs at \(differing)")
    }
}
