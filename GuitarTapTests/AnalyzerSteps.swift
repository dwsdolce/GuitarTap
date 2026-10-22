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
import Testing
@testable import GuitarTap

private final class AnalyzerStepsAnchor {}

/// The sample count `liveAudio` has fed, so its tone runs on across steps.
nonisolated(unsafe) private var liveAudioSample = 0

private let materialPhases: [String: MaterialTapPhase] = [
    "L": .capturingLongitudinal, "C": .capturingCross, "FLC": .capturingFlc,
]

/// Runs `step` on `sut` if it is one of the shared steps, and says whether it was.
///
/// - `{"settings": {"type": saved name, "measureFlc": Bool, "range": [minHz, maxHz, minDB, maxDB]}}` — as
///   Settings writes them (`range`: the measurement type's display range and the dB range)
/// - `{"setTaps": n}` — the Taps control
/// - `{"setThreshold": dB}` — the Threshold control
/// - `{"setPeakMin": dB}` — the Peak Min control
/// - `{"newTap": true}`, `{"pause": true}`, `{"resume": true}`, `{"cancel": true}`
/// - `{"newTapSkippingWarmUp": true}` — the start a guitar file's playback makes
/// - `{"engineStarted": true}` — what the engine coming up does (its guarded auto-start)
/// - `{"loadFixture": file}` — a fixture every edition carries, loaded as the app loads a file
/// - `{"guitarTap": hz}` — a guitar capture finished on a synthetic tap one capture long
/// - `{"materialTap": {"phase": "L" | "C" | "FLC", "hz": hz}}` — a material capture on a 0.5 s tap
/// - `{"accept": true}`, `{"redo": true}` — the phase under review
/// - `{"advance": "tapCooldown" | "captureWindow" | "warmupPeriod" | seconds, "fraction"?: f, "extra"?: s,
///   "level"?: dB}` — that much audio (quiet unless `level` is given)
/// - `{"audioChunks": n, "level": dB}` — exactly n chunks of audio at that level, each one chunk after the
///   last (two loud ones are a tap)
/// - `{"stall": seconds}` — that much wall time with no audio
/// - `{"routeChange": true}` — the engine restarted on a device change
/// - `{"engineRunning": Bool}` — the engine stopped or started again, as a retry after a failed start does
/// - `{"spectrumFrame": spectrum}` — one FFT frame from the running engine, a spectrum as `peaks.json`
///   describes one
/// - `{"liveAudio": seconds, "level": dB}` — that much real audio (a 200 Hz tone at that level) through the
///   microphone's path: each chunk through the engine's per-chunk processing and its hand-over, which on the main
///   thread takes the chunk at once — the FFT's input, then the analyzer's `processAudioFrame`
@MainActor
func runAnalyzerStep(_ step: [String: Any], on sut: TapToneAnalyzer) -> Bool {
    if let settings = step["settings"] as? [String: Any] {
        if let type = settings["type"] as? String {
            TapDisplaySettings.measurementType = MeasurementType(rawValue: type)!
        }
        if let flc = settings["measureFlc"] as? Bool { TapDisplaySettings.measureFlc = flc }
        if let range = settings["range"] as? [Double] {
            let type = TapDisplaySettings.measurementType
            TapDisplaySettings.setMinFrequency(Float(range[0]), for: type)
            TapDisplaySettings.setMaxFrequency(Float(range[1]), for: type)
            TapDisplaySettings.minMagnitude = Float(range[2])
            TapDisplaySettings.maxMagnitude = Float(range[3])
        }
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
    } else if step["engineStarted"] as? Bool == true {
        sut.autoStartTapSequence()
    } else if let name = step["loadFixture"] as? String {
        guard let url = Bundle(for: AnalyzerStepsAnchor.self).url(
                forResource: (name as NSString).deletingPathExtension, withExtension: "guitartap"),
              let data = try? Data(contentsOf: url),
              let measurement = try? TapToneAnalyzer.decodeMeasurements(data).first else {
            Issue.record("fixture \(name) could not be read")
            return true
        }
        sut.loadMeasurement(measurement)
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
    } else if let running = step["engineRunning"] as? Bool {
        sut.fftAnalyzer.isRunning = running
    } else if step["routeChange"] as? Bool == true {
        sut.fftAnalyzer.isRunning = true   // the engine restarted on the new device
        sut.handleRouteChangeRestart()
    } else if let spec = step["spectrumFrame"] as? [String: Any] {
        let (magnitudes, frequencies) = PeakFindingTests.spectrum(spec)
        sut.fftAnalyzer.isRunning = true   // a frame comes only from the running engine
        sut.onFftFrame(magnitudes: magnitudes, frequencies: frequencies, peakMagnitude: magnitudes.max()!)
    } else if let seconds = step["stall"] as? Double {
        (sut.wallClock as! ManualWallClock).advance(by: seconds)
    } else if let n = step["audioChunks"] as? Int {
        let level = Float(step["level"] as! Double)
        for _ in 0..<n { sut.onChunkLevel(level, audioTime: sut.lastAudioTime + audioFeedChunkSeconds) }
    } else if let seconds = step["liveAudio"] as? Double {
        // Real audio through the microphone's path: each chunk's samples to the capture, then its level.
        let level = Float(step["level"] as! Double)
        let amplitude = Float(2).squareRoot() * pow(10, level / 20)
        for _ in 0..<Int((seconds / audioFeedChunkSeconds).rounded()) {
            let chunk = (0..<1024).map { i -> Float in
                amplitude * sin(2 * .pi * 200 * Float(liveAudioSample + i) / 48000)
            }
            liveAudioSample += 1024
            // The engine's audio clock follows the analyzer's, so this audio continues the steps before it.
            sut.fftAnalyzer.audioElapsed = sut.lastAudioTime
            sut.fftAnalyzer.processRawSamples(chunk)
        }
    } else {
        return false
    }
    return true
}

/// A fresh analyzer as the shared scenario cases start one: threshold −40, Taps 1, the frequency bins
/// starting the engine builds, and a wall clock that moves only when a step stalls it.
@MainActor
func makeStepsAnalyzer() -> TapToneAnalyzer {
    let sut = TapToneAnalyzer.forTesting(wallClock: ManualWallClock())
    sut.numberOfTaps = 1
    sut.tapDetectionThreshold = -40
    sut.fftAnalyzer.actualSampleRate = 48000
    sut.fftAnalyzer.updateFrequencyBins()
    return sut
}
