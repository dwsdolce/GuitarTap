//
//  DecayTrackingTests.swift
//  GuitarTapTests
//
//  The shared cases in `decay-tracking.json`: ring-out time, ringOutTime on generated audio (DK1–DK8),
//  and on the analyzer, that a new sequence clears the last ring-out (DK9).
//
//  That a tap's ring-out is the same wherever the audio's chunk boundaries fall is
//  GuitarCaptureWindowTests GW3.
//
//  Test plan coverage: DK1–DK9 — the same list, ids and values as Python test_decay_tracking.py and
//  web test/decay-tracking.test.ts.
//
// @parity test/decay-tracking

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

@MainActor
private func makeSUT() -> TapToneAnalyzer {
    let fft = RealtimeFFTAnalyzer.forTesting()
    let sut = TapToneAnalyzer(fftAnalyzer: fft)
    sut.cancellables.removeAll()
    return sut
}

/// A case's audio, from its `signal` (see `decay-tracking.json`'s `about`).
private func signal(_ spec: [String: Any], sampleRate: Double) -> [Float] {
    let length = spec["length"] as! Int
    let onset = spec["onset"] as? Int ?? 0
    let timeConstant = spec["timeConstant"] as! Double
    let amplitude = spec["amplitude"] as? Double ?? 0.5
    let attack = spec["attack"] as? Int ?? 0
    return (0..<length).map { index in
        let n = index - onset
        guard n >= 0 else { return 0 }
        var value = amplitude * exp(-Double(n) / (timeConstant * sampleRate))
        if attack > 0 { value *= min(1.0, Double(n) / Double(attack)) }
        return Float(value)
    }
}

private final class DecayTrackingTestsAnchor {}

@Suite("DecayTracking")
@MainActor
struct DecayTrackingTests {

    // MARK: - ringOutTime — the shared cases in `decay-tracking.json` (DK1–DK8)

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: DecayTrackingTestsAnchor.self).url(forResource: "decay-tracking", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    @Test func defaultThreshold() {
        #expect(makeSUT().decayThreshold == Float(Self.data["defaultThreshold"] as! Double))
    }

    @Test func windowSamples() {
        #expect(TapToneAnalyzer.ringOutWindowSamples == Self.data["windowSamples"] as! Int)
    }

    @Test(arguments: (data["ringOutTime"] as! [[String: Any]]).map { $0["id"] as! String })
    func ringOutTime(_ id: String) {
        let row = (Self.data["ringOutTime"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let sampleRate = Self.data["sampleRate"] as! Double
        let threshold = (row["threshold"] as? Double) ?? (Self.data["defaultThreshold"] as! Double)
        let t = TapToneAnalyzer.ringOutTime(signal(row["signal"] as! [String: Any], sampleRate: sampleRate),
                                            from: row["start"] as! Int, to: row["end"] as! Int,
                                            sampleRate: sampleRate, threshold: Float(threshold))
        if let expected = row["expect"] as? Double {
            #expect(t.map { abs(Double($0) - expected) < (Self.data["tolerance"] as! Double) } == true, "\(id): got \(String(describing: t))")
        } else {
            #expect(t == nil, "\(id): got \(String(describing: t))")
        }
    }

    // MARK: - The analyzer

    nonisolated static func analyzerIDs() -> [String] {
        (data["analyzer"] as! [[String: Any]]).map { $0["id"] as! String }
    }

    /// The analyzer cases of `decay-tracking.json` (DK9), as steps on a fresh analyzer.
    @Test(arguments: analyzerIDs())
    func analyzer(_ id: String) {
        let row = (Self.data["analyzer"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let sut = makeSUT()
        for step in row["steps"] as! [[String: Any]] {
            if let seconds = step["decayTime"] as? Double {
                sut.currentDecayTime = Float(seconds)
            } else if step["newTap"] as? Bool == true {
                sut.startTapSequence()
            }
        }
        for (field, want) in row["expect"] as! [String: Any] {
            switch field {
            case "currentDecayTime":
                #expect(sut.currentDecayTime.map(Double.init) == want as? Double, "\(id) \(field)")
            default:
                Issue.record("\(id): unknown field \(field)")
            }
        }
    }
}
