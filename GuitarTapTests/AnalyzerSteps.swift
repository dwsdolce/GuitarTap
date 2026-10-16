//
//  AnalyzerSteps.swift
//  GuitarTapTests
//
//  The steps the shared scenario case files drive the analyzer with, each through the app's own path:
//  the settings Settings writes, the Taps control, New Tap, Pause, Resume, Cancel, a capture finished
//  on a synthetic tap, Accept, Redo, and audio fed through the analyzer's clock. A case file names its
//  steps; this runs one. Mirrors Python tests/analyzer_steps.py and web test/analyzerSteps.ts.
//
// @parity tooling/analyzer-steps

import Foundation
@testable import GuitarTap

private let materialPhases: [String: MaterialTapPhase] = [
    "L": .capturingLongitudinal, "C": .capturingCross, "FLC": .capturingFlc,
]

/// Runs `step` on `sut` if it is one of the shared steps, and says whether it was.
///
/// - `{"settings": {"type": saved name, "measureFlc": Bool}}` — as Settings writes them
/// - `{"setTaps": n}` — the Taps control
/// - `{"setThreshold": dB}` — the Threshold control
/// - `{"setPeakMin": dB}` — the Peak Min control
/// - `{"newTap": true}`, `{"pause": true}`, `{"resume": true}`, `{"cancel": true}`
/// - `{"newTapSkippingWarmUp": true}` — the start a guitar file's playback makes
/// - `{"guitarTap": hz}` — a guitar capture finished on a synthetic tap one capture long
/// - `{"materialTap": {"phase": "L" | "C" | "FLC", "hz": hz}}` — a material capture on a 0.5 s tap
/// - `{"accept": true}`, `{"redo": true}` — the phase under review
/// - `{"advance": "tapCooldown" | "captureWindow" | "warmupPeriod" | seconds, "fraction"?: f, "extra"?: s,
///   "level"?: dB}` — that much audio (quiet unless `level` is given)
/// - `{"audioChunks": n, "level": dB}` — exactly n chunks of audio at that level, each one chunk after the
///   last (two loud ones are a tap)
@MainActor
func runAnalyzerStep(_ step: [String: Any], on sut: TapToneAnalyzer) -> Bool {
    if let settings = step["settings"] as? [String: Any] {
        if let type = settings["type"] as? String {
            TapDisplaySettings.measurementType = MeasurementType(rawValue: type)!
        }
        if let flc = settings["measureFlc"] as? Bool { TapDisplaySettings.measureFlc = flc }
    } else if let n = step["setTaps"] as? Int {
        sut.numberOfTaps = n
    } else if let dB = step["setThreshold"] as? Double {
        sut.tapDetectionThreshold = Float(dB)
    } else if let dB = step["setPeakMin"] as? Double {
        sut.peakMinThreshold = Float(dB)
    } else if step["newTap"] as? Bool == true {
        sut.startTapSequence()
    } else if step["newTapSkippingWarmUp"] as? Bool == true {
        sut.startTapSequence(skipWarmup: true)
    } else if step["pause"] as? Bool == true {
        sut.pauseTapDetection()
    } else if step["resume"] as? Bool == true {
        sut.resumeTapDetection()
    } else if step["cancel"] as? Bool == true {
        sut.cancelTapSequence()
    } else if let hz = step["guitarTap"] as? Double {
        sut.finishGuitarGatedCapture(
            samples: syntheticTap(hz: Float(hz), seconds: Double(sut.fftAnalyzer.fftSize) / 48000),
            sampleRate: 48000)
    } else if let tap = step["materialTap"] as? [String: Any] {
        sut.finishGatedFFTCapture(samples: syntheticTap(hz: Float(tap["hz"] as! Double), seconds: 0.5),
                                  sampleRate: 48000, phase: materialPhases[tap["phase"] as! String]!)
    } else if step["accept"] as? Bool == true {
        sut.acceptCurrentPhase()
    } else if step["redo"] as? Bool == true {
        sut.redoCurrentPhase()
    } else if let advance = step["advance"] {
        let seconds: Double
        switch advance as? String {
        case "tapCooldown": seconds = sut.tapCooldown
        case "captureWindow": seconds = sut.captureWindow
        case "warmupPeriod": seconds = sut.warmupPeriod
        default: seconds = advance as! Double
        }
        let level = Float((step["level"] as? Double) ?? -90)
        advanceAudio(sut, by: seconds * ((step["fraction"] as? Double) ?? 1) + ((step["extra"] as? Double) ?? 0), level: level)
    } else if let n = step["audioChunks"] as? Int {
        let level = Float(step["level"] as! Double)
        for _ in 0..<n { sut.onChunkLevel(level, audioTime: sut.lastAudioTime + audioFeedChunkSeconds) }
    } else {
        return false
    }
    return true
}

/// A fresh analyzer as the shared scenario cases start one: threshold −40, Taps 1, and the frequency
/// bins starting the engine builds.
@MainActor
func makeStepsAnalyzer() -> TapToneAnalyzer {
    let sut = TapToneAnalyzer.forTesting()
    sut.numberOfTaps = 1
    sut.tapDetectionThreshold = -40
    sut.fftAnalyzer.actualSampleRate = 48000
    sut.fftAnalyzer.updateFrequencyBins()
    return sut
}
