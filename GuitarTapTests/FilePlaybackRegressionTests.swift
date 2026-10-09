//
//  FilePlaybackRegressionTests.swift
//  GuitarTapTests
//
//  End-to-end regression tests for the full file-playback pipeline:
//    WAV read → chunk pacing → RMS → tap detection → gated capture →
//    FFT (rectangular window for the guitar capture, Hann for the material one) →
//    peak selection → mode identification (guitar) / L→C→FLC phases (material)
//
//  The analyzer is created via `TapToneAnalyzer.forTesting()` (no audio
//  hardware) and fed via `playFileAndWait` (the app's own `playFile` path).
//
//  The expected values are the shared oracle's (parity-oracle.json): Swift mints them from this
//  pipeline and asserts them at zero; Python and the web read the same file.
//
//  The regression cases — REG-B1, REG-B2, REG-G1, the REG-G ring-out, REG-G2, REG-P1, REG-P2 and the noisy
//  plate (OUT-4) — and what each checks are the shared case file `file-playback.json`, run by one test here
//  and by the Python and web suites. Then the playback rules, which stay as code: session recording,
//  stopping a playback, provenance, playback calibration.
//
// @parity test/file-playback

import Testing
import Foundation
import AVFoundation
@testable import GuitarTap

// Used to anchor Bundle(for:) lookups to the GuitarTapTests bundle.
private class TestBundleMarker: NSObject {}
nonisolated private var testBundle: Bundle { Bundle(for: TestBundleMarker.self) }

/// REG-B1's tap threshold, for the provenance cases below.
private let braceTapThreshold: Float = ParityOracle.playback("REG-B1").settings.tapDetectionThreshold

// ---------------------------------------------------------------------------
// MARK: - The shared cases
// ---------------------------------------------------------------------------

/// One case of `file-playback.json`: the oracle entry it plays (or a fixture of its own) and what it checks.
nonisolated private struct PlaybackCheckCase: Decodable, CustomTestStringConvertible {
    struct Check: Decodable {
        let kind: String
        let count: Int?
        let expected: String?
        let roles: [String]?
        let fields: [String]?
        let min: Float?
        let max: Float?
    }
    let id: String
    let oracle: String
    let fixture: String?
    let checks: [Check]
    var testDescription: String { id }
}

// nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default.
nonisolated private let playbackCases: [PlaybackCheckCase] = {
    let url = testBundle.url(forResource: "file-playback", withExtension: "json")!
    struct File: Decodable { let cases: [PlaybackCheckCase] }
    return try! JSONDecoder().decode(File.self, from: Data(contentsOf: url)).cases
}()

/// Swift mints the oracle, so it asserts at the same-edition bar — zero. The values in the file are the
/// exact Floats this code produced, stored as the shortest decimal that recovers them, so equality is exact
/// and any movement is a real change in the DSP. Python and the web assert the same values at the
/// cross-edition `tolerances` — whether they agree with Swift.
private func tolerance(_ field: String) -> Float {
    switch field {
    case "frequency": return ParityOracle.selfTolerance(\.freqHz)
    case "magnitude": return ParityOracle.selfTolerance(\.magDb)
    default:          return ParityOracle.selfTolerance(\.q)
    }
}

private func value(_ field: String, of peak: ResonantPeak) -> Float {
    field == "frequency" ? peak.frequency : field == "magnitude" ? peak.magnitude : peak.quality
}

private func value(_ field: String, of peak: ParityOracle.Peak) -> Float {
    field == "frequency" ? peak.frequency : field == "magnitude" ? peak.magnitude : (peak.q ?? 0)
}

/// The identified peak for a role: a material phase's selected peak, or a guitar mode's peak (the same API
/// the Results panel uses).
@MainActor
private func identifiedPeak(_ sut: TapToneAnalyzer, _ role: String) -> ResonantPeak? {
    switch role {
    case "longitudinal": return sut.selectedLongitudinalPeak
    case "cross":        return sut.selectedCrossPeak
    case "flc":          return sut.selectedFlcPeak
    case "air":          return sut.getPeak(for: .air)
    case "top":          return sut.getPeak(for: .top)
    case "back":         return sut.getPeak(for: .back)
    default:             return nil
    }
}

private let guitarModes: [String: GuitarMode] = ["air": .air, "top": .top, "back": .back]

// ---------------------------------------------------------------------------
// MARK: - Tests
// ---------------------------------------------------------------------------

@Suite("FilePlaybackRegression")
struct FilePlaybackRegressionTests {

    /// Every case of `file-playback.json`: play its file through the app's own path
    /// (`TapToneAnalyzer.forTesting()` + `playFileAndWait`) with the oracle entry's calibration and settings,
    /// then run each check it names.
    @Test(arguments: playbackCases)
    fileprivate func playback(_ c: PlaybackCheckCase) async throws {
        let reg = ParityOracle.playback(c.oracle)
        let stem = ((c.fixture ?? reg.fixture) as NSString).deletingPathExtension
        let url = try #require(testBundle.url(forResource: stem, withExtension: "wav"), "\(stem).wav not found in test bundle")
        let calURL = reg.calibration.map { ($0 as NSString).deletingPathExtension }
            .flatMap { testBundle.url(forResource: $0, withExtension: "txt") }
        let type = try #require(MeasurementType(rawValue: reg.settings.measurementType ?? ""))

        let originalMeasureFlc = TapDisplaySettings.measureFlc
        if let flc = reg.settings.measureFlc { TapDisplaySettings.measureFlc = flc }
        defer { TapDisplaySettings.measureFlc = originalMeasureFlc }

        let sut = TapToneAnalyzer.forTesting()
        if let peakMin = reg.settings.peakMinThreshold { sut.peakMinThreshold = peakMin }
        sut.tapDetectionThreshold = reg.settings.tapDetectionThreshold
        try await sut.playFileAndWait(url: url, measurementType: type,
                                      numberOfTaps: reg.settings.numberOfTaps ?? 1, calibrationURL: calURL)

        for check in c.checks {
            switch check.kind {
            case "measurementComplete":
                #expect(sut.isMeasurementComplete, "\(c.id): isMeasurementComplete should be true")
            case "materialPhaseComplete":
                #expect(sut.materialTapPhase == .complete, "\(c.id): materialTapPhase should be .complete, got \(sut.materialTapPhase)")
            case "capturedTaps":
                #expect(sut.capturedTaps.count == check.count, "\(c.id): captured taps \(sut.capturedTaps.count)")
            case "tapEntries":
                #expect(sut.tapEntries.count == check.count, "\(c.id): tap entries \(sut.tapEntries.count)")
            case "peaks":
                let expected = check.expected == "averagedPeaks" ? reg.averagedPeaks : reg.peaks
                for role in check.roles ?? [] {
                    let want = try #require(expected?.first { $0.role == role }, "\(c.id): the oracle has no \(role) peak")
                    guard let got = identifiedPeak(sut, role) else {
                        Issue.record("\(c.id): the \(role) peak should be identified")
                        continue
                    }
                    for field in check.fields ?? [] {
                        #expect(abs(value(field, of: got) - value(field, of: want)) <= tolerance(field),
                                "\(c.id) \(role) \(field): expected \(value(field, of: want)), got \(value(field, of: got))")
                    }
                }
            case "perTapPeaks":
                let rows = reg.perTap ?? []
                #expect(sut.tapEntries.count == rows.count, "\(c.id): \(sut.tapEntries.count) tap entries, the oracle has \(rows.count)")
                // TapEntry.resolvedModePeaks() — the code path of MultiTapComparisonResultsView and the PDF.
                for (index, (entry, row)) in zip(sut.tapEntries, rows).enumerated() {
                    let modePeaks = entry.resolvedModePeaks()
                    for role in check.roles ?? [] {
                        guard let want = row.peaks.first(where: { $0.role == role }) else { continue }
                        guard let got = guitarModes[role].flatMap({ modePeaks[$0] }) else {
                            Issue.record("\(c.id) tap \(index + 1): no \(role) peak")
                            continue
                        }
                        for field in check.fields ?? [] {
                            #expect(abs(value(field, of: got) - value(field, of: want)) <= tolerance(field),
                                    "\(c.id) tap \(index + 1) \(role) \(field): expected \(value(field, of: want)), got \(value(field, of: got))")
                        }
                    }
                }
            case "ringOut":
                let decay = try #require(sut.currentDecayTime, "\(c.id): no ring-out measured")
                let golden = try #require(reg.ringOutSec)
                #expect(abs(decay - golden) <= ParityOracle.selfTolerance(\.ringOutSec), "\(c.id): ring-out expected \(golden), got \(decay)")
            case "phasesCaptured":
                let captured = [sut.longitudinalSpectrum, sut.crossSpectrum, sut.flcSpectrum].compactMap { $0 }.count
                #expect(captured == check.count, "\(c.id): \(captured) phases captured; noiseFloorEstimate=\(sut.noiseFloorEstimate) dBFS")
            case "noiseFloorBetween":
                #expect(sut.noiseFloorEstimate > check.min! && sut.noiseFloorEstimate < check.max!,
                        "\(c.id): noiseFloorEstimate \(sut.noiseFloorEstimate) dBFS (pinned at -100 means relative detection is off)")
            default:
                Issue.record("\(c.id): unknown check \(check.kind)")
            }
        }
    }

    // MARK: - Session recording
    //
    // With "save capture audio" on, a guitar measurement writes ONE session WAV labelled
    // "Guitar_<n>tap" covering the audio that flowed through the pipeline (arm → final tap); off, it
    // writes nothing. The dump folder is test-sandboxed (WavDumpFolder.defaultFolder), so the WAVs are
    // read back from there. Twins of the web's session-recording cases.

    private static let sessionPrefix = "swift_session_"

    /// The session WAVs in the sandboxed dump folder: label ("Guitar_1tap"), sample rate, sample count.
    private func sessionWAVs() -> [(label: String, sampleRate: Int, samples: Int)] {
        let dir = WavDumpFolder.defaultFolder
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasPrefix(Self.sessionPrefix) && $0.hasSuffix(".wav") }.sorted().compactMap { name in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)), data.count >= 44 else { return nil }
            let rate = data.subdata(in: 24..<28).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            let bytes = data.subdata(in: 40..<44).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            // "swift_session_Guitar_1tap_<timestamp>.wav" → "Guitar_1tap"
            let label = name.dropFirst(Self.sessionPrefix.count).split(separator: "_").prefix(2).joined(separator: "_")
            return (label, Int(UInt32(littleEndian: rate)), Int(UInt32(littleEndian: bytes)) / 4)
        }
    }

    /// Play a generic-guitar fixture with "save capture audio" set to `dump`; return the session WAVs.
    private func playGuitarSession(_ stem: String, numberOfTaps: Int, dump: Bool) async throws
        -> [(label: String, sampleRate: Int, samples: Int)] {
        let url = try #require(testBundle.url(forResource: stem, withExtension: "wav"))
        let dir = WavDumpFolder.defaultFolder
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        where name.hasPrefix(Self.sessionPrefix) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
        let savedDump = TapDisplaySettings.dumpCaptureAudio
        TapDisplaySettings.dumpCaptureAudio = dump
        defer { TapDisplaySettings.dumpCaptureAudio = savedDump }
        let sut = TapToneAnalyzer.forTesting()
        sut.peakMinThreshold = -76
        sut.tapDetectionThreshold = -40
        try await sut.playFileAndWait(url: url, measurementType: .generic, numberOfTaps: numberOfTaps)
        return sessionWAVs()
    }

    @Test func REG_G1_sessionRecording_dumpOn_writesOneGuitar1tapWAV() async throws {
        let sessions = try await playGuitarSession("Recording 5", numberOfTaps: 1, dump: true)
        let file = try AVAudioFile(forReading: try #require(testBundle.url(forResource: "Recording 5", withExtension: "wav")))
        #expect(sessions.count == 1, "one session WAV, got \(sessions.map(\.label))")
        guard let session = sessions.first else { return }
        #expect(session.label == "Guitar_1tap")
        #expect(session.sampleRate == Int(file.fileFormat.sampleRate))
        // Covers the arm → tap → capture span: many chunks, and never more than the whole file.
        #expect(session.samples > 8192, "a continuous run of many chunks, got \(session.samples)")
        #expect(session.samples <= Int(file.length), "bounded by the file (\(file.length)), got \(session.samples)")
    }

    @Test func REG_G2_sessionRecording_isLabelledByTheTapCount() async throws {
        let sessions = try await playGuitarSession("Recording", numberOfTaps: 8, dump: true)
        #expect(sessions.count == 1, "one session WAV, got \(sessions.map(\.label))")
        #expect(sessions.first?.label == "Guitar_8tap")
    }

    @Test func sessionRecording_dumpOff_writesNothing() async throws {
        let sessions = try await playGuitarSession("Recording 5", numberOfTaps: 1, dump: false)
        #expect(sessions.isEmpty, "no session WAV with the setting off, got \(sessions.map(\.label))")
    }

    // MARK: - Stopping a playback
    //
    // Cancel during a playback stops the file and restarts the sequence on live input; a measurement-type
    // change stops it before arming the new type. Nothing from the rest of the file reaches the new
    // sequence, and the playback's completion runs (the input's calibration returns).

    /// Start "Recording" (8 guitar taps) with the input calibration set, wait for the first tap, then run
    /// `stop` on the analyzer. Returns the analyzer and whether the playback's completion ran.
    private func stopPlaybackAfterFirstTap(_ stop: (TapToneAnalyzer) -> Void) async throws
        -> (sut: TapToneAnalyzer, completed: Bool, input: MicrophoneCalibration) {
        let url = try #require(testBundle.url(forResource: "Recording", withExtension: "wav"))
        let calURL = try #require(testBundle.url(forResource: "7108913", withExtension: "txt"))
        let input = try CalibrationFileParser.parse(url: calURL)
        let sut = TapToneAnalyzer.forTesting()
        sut.peakMinThreshold = -76
        sut.tapDetectionThreshold = -40
        sut.fftAnalyzer.setTemporaryCalibration(input)
        TapDisplaySettings.measurementType = .generic
        sut.numberOfTaps = 8
        var completed = false
        try sut.playFile(url: url) { completed = true }
        let deadline = Date(timeIntervalSinceNow: 20)
        while sut.currentTapCount < 1 && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(sut.currentTapCount >= 1, "precondition: a tap before the stop")
        stop(sut)
        return (sut, completed, input)
    }

    @Test func cancel_duringPlayback_stopsTheFile_andRestartsOnLiveInput() async throws {
        let (sut, completed, input) = try await stopPlaybackAfterFirstTap { $0.cancelTapSequence() }
        #expect(!sut.fftAnalyzer.isPlayingFile, "the file is stopped")
        #expect(sut.fftAnalyzer.playingFileName == nil, "the chart no longer names the file")
        #expect(completed, "the playback's completion ran")
        #expect(sut.fftAnalyzer.activeCalibration == input, "the input's calibration is back")
        #expect(sut.detectionState == .listening, "a fresh sequence is armed")
        #expect(sut.currentTapCount == 0 && sut.capturedTaps.isEmpty, "the partial result is discarded")
        // The rest of the file must not reach the fresh sequence.
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        #expect(sut.currentTapCount == 0 && sut.capturedTaps.isEmpty && !sut.isMeasurementComplete,
                "no tap from the abandoned file, got \(sut.currentTapCount)")
    }

    @Test func aPlayedFile_isNamedWhileItPlays_andAfterItEnds_andANewSequenceClearsTheName() async throws {
        let stem = (ParityOracle.playback("REG-G1").fixture as NSString).deletingPathExtension
        let url = try #require(testBundle.url(forResource: stem, withExtension: "wav"))
        let sut = TapToneAnalyzer.forTesting()
        TapDisplaySettings.measurementType = .generic
        var ended = false
        try sut.playFile(url: url) { ended = true }
        #expect(sut.fftAnalyzer.playingFileName == stem, "named while it plays")
        let deadline = Date(timeIntervalSinceNow: 20)
        while !ended && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(ended, "precondition: the file ended")
        #expect(sut.fftAnalyzer.playingFileName == stem, "still named when it ends")
        sut.requestStartTapSequence()
        #expect(sut.fftAnalyzer.playingFileName == nil, "a new sequence clears it")
    }

    @Test func measurementTypeChange_duringPlayback_stopsTheFile_beforeArmingTheNewType() async throws {
        let (sut, completed, _) = try await stopPlaybackAfterFirstTap { sut in
            TapDisplaySettings.measurementType = .plate
            sut.requestStartTapSequence()   // what the settings Apply does for a changed type
        }
        defer { TapDisplaySettings.measurementType = .generic }
        #expect(!sut.fftAnalyzer.isPlayingFile, "the file is stopped")
        #expect(completed, "the playback's completion ran")
        #expect(sut.materialTapPhase == .capturingLongitudinal, "the plate sequence is armed")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        #expect(sut.longitudinalSpectrum == nil && sut.materialCapturedTaps.isEmpty,
                "no guitar tap from the abandoned file reaches the plate measurement")
    }

    // MARK: - Provenance of a played file
    //
    // A result made from a played file is saved with the file's provenance: the calibration it was played
    // with (or none), the file's sample rate, and no microphone — the microphone that recorded a file is
    // unknown. A new sequence listens to the input again, and saves the input's.

    @Test func save_afterPlayback_recordsTheFilesProvenance_andAnUnknownMicrophone() async throws {
        let url = try #require(testBundle.url(forResource: "brace-umik-1-swift-mac-1778816093", withExtension: "wav"))
        let calURL = try #require(testBundle.url(forResource: "7108913", withExtension: "txt"))
        let fileCalibration = try CalibrationFileParser.parse(url: calURL)
        let sut = TapToneAnalyzer.forTesting()
        sut.tapDetectionThreshold = braceTapThreshold
        try await sut.playFileAndWait(url: url, measurementType: .brace, calibrationURL: calURL)
        #expect(sut.isMeasurementComplete, "precondition: the brace completed")
        let fileRate = try AVAudioFile(forReading: url).fileFormat.sampleRate

        sut.saveMeasurement()
        let saved = try #require(sut.savedMeasurements.last)
        #expect(saved.microphoneName == nil && saved.microphoneUID == nil, "the microphone is unknown")
        #expect(saved.calibrationName == fileCalibration.name, "the file's calibration")
        #expect(saved.sampleRate == fileRate, "the file's sample rate")
        #expect(saved.selectedLongitudinalPeakID == sut.selectedLongitudinalPeak?.id, "fL's role, read by the save")
    }

    @Test func aNewSequence_afterPlayback_savesTheInputsProvenance() async throws {
        let url = try #require(testBundle.url(forResource: "Recording 5", withExtension: "wav"))
        let calURL = try #require(testBundle.url(forResource: "7108913", withExtension: "txt"))
        let input = try CalibrationFileParser.parse(url: calURL)
        let sut = TapToneAnalyzer.forTesting()
        sut.peakMinThreshold = -76
        sut.tapDetectionThreshold = -40
        sut.fftAnalyzer.setTemporaryCalibration(input)
        try await sut.playFileAndWait(url: url, measurementType: .generic, numberOfTaps: 1)
        #expect(sut.captureCalibrationName == nil, "precondition: the file played uncalibrated")

        sut.startTapSequence()
        #expect(sut.captureCalibrationName == input.name, "the input's calibration again")
    }

    @Test func aLoadedMeasurement_reportsItsRecordedProvenance_andAReSaveKeepsIt() async throws {
        // A played-file result saved with an unknown microphone and the file's calibration and rate.
        let url = try #require(testBundle.url(forResource: "brace-umik-1-swift-mac-1778816093", withExtension: "wav"))
        let calURL = try #require(testBundle.url(forResource: "7108913", withExtension: "txt"))
        let source = TapToneAnalyzer.forTesting()
        source.tapDetectionThreshold = braceTapThreshold
        try await source.playFileAndWait(url: url, measurementType: .brace, calibrationURL: calURL)
        source.saveMeasurement()
        let saved = try #require(source.savedMeasurements.last)

        // Loaded by an analyzer whose input has a different calibration: the loaded result reports the file's.
        let sut = TapToneAnalyzer.forTesting()
        sut.fftAnalyzer.setTemporaryCalibration(nil)
        sut.loadMeasurement(saved)
        #expect(sut.captureMicrophoneName == nil && sut.resultProvenance != nil, "the microphone is unknown")
        #expect(sut.captureCalibrationName == saved.calibrationName, "the recorded calibration")
        #expect(sut.captureSampleRate == saved.sampleRate, "the recorded sample rate")

        sut.saveMeasurement()
        let reSaved = try #require(sut.savedMeasurements.last)
        #expect(reSaved.microphoneName == nil, "a re-save keeps the unknown microphone")
        #expect(reSaved.calibrationName == saved.calibrationName, "and the recorded calibration")
        #expect(reSaved.sampleRate == saved.sampleRate, "and the recorded sample rate")
    }

    // MARK: - Playback calibration
    //
    // A file plays with the calibration given for it, or with none: the microphone it was recorded with
    // is unknown, so the live input's calibration never applies to it. The input's calibration is back
    // once playback ends.

    /// Play "Recording 5" with `calibrationURL`; return the active calibration during and after playback.
    private func playbackCalibrations(input: MicrophoneCalibration?, calibrationURL: URL?) async throws
        -> (during: MicrophoneCalibration?, after: MicrophoneCalibration?) {
        let url = try #require(testBundle.url(forResource: "Recording 5", withExtension: "wav"))
        let sut = TapToneAnalyzer.forTesting()
        sut.fftAnalyzer.setTemporaryCalibration(input)
        TapDisplaySettings.measurementType = .generic
        var ended = false
        try sut.playFile(url: url, calibrationURL: calibrationURL) { ended = true }
        let during = sut.fftAnalyzer.activeCalibration
        while !ended { try? await Task.sleep(nanoseconds: 5_000_000) }
        return (during, sut.fftAnalyzer.activeCalibration)
    }

    @Test func playback_withoutACalibrationFile_isUncalibrated_andTheInputsCalibrationReturns() async throws {
        let calURL = try #require(testBundle.url(forResource: "7108913", withExtension: "txt"))
        let input = try CalibrationFileParser.parse(url: calURL)
        let (during, after) = try await playbackCalibrations(input: input, calibrationURL: nil)
        #expect(during == nil, "no calibration file → uncalibrated, got \(String(describing: during?.name))")
        #expect(after == input, "the input's calibration is restored after playback")
    }

    @Test func playback_withACalibrationFile_usesIt_andTheInputsCalibrationReturns() async throws {
        let calURL = try #require(testBundle.url(forResource: "7108913", withExtension: "txt"))
        let fileCalibration = try CalibrationFileParser.parse(url: calURL)
        let (during, after) = try await playbackCalibrations(input: nil, calibrationURL: calURL)
        #expect(during?.correctionPoints == fileCalibration.correctionPoints, "the file's calibration is applied")
        #expect(after == nil, "the input's (absent) calibration is restored after playback")
    }
}
