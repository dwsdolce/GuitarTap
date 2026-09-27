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
//  Cases: REG-B2, REG-B1, REG-G1, the REG-G ring-out, REG-G2, REG-P1, the noisy plate, REG-P2,
//  session recording, playback calibration.
//
// @parity test/file-playback

import Testing
import Foundation
import AVFoundation
@testable import GuitarTap

// Used to anchor Bundle(for:) lookups to the GuitarTapTests bundle.
private class TestBundleMarker: NSObject {}
private var testBundle: Bundle { Bundle(for: TestBundleMarker.self) }

// ---------------------------------------------------------------------------
// MARK: - Expected values
// ---------------------------------------------------------------------------

// Every expected value below is read from the shared oracle (parity-oracle.json, vendored
// beside this file by Tooling/sync-oracle.sh). Swift owns them - GenerateParityOracle mints the
// oracle from this very pipeline - in one place that the other editions read.

// REG-B1 - brace bar, UMIK-1 mic, 48 kHz, full-session recording (mono float32). The oracle's
// values originally came from the matching .guitartap reference
// (Tests/Brace/brace-umik-1-swift-mac-1778816093.guitartap).
private let braceCase = ParityOracle.playback("REG-B1")
private let braceExpectedPeak = braceCase.peak("longitudinal")
private let braceExpectedFrequency: Float = braceExpectedPeak.frequency
private let braceExpectedMagnitude: Float = braceExpectedPeak.magnitude
private let braceExpectedQ: Float = braceExpectedPeak.q ?? 0
private let braceTapThreshold: Float = braceCase.settings.tapDetectionThreshold

// REG-B2 — the brace counterpart to REG-P2: three taps, averaged. REG-P2 pins PLATE multi-tap and
// REG-B1 is single-tap brace, so this is the case that exercises brace averaging. Deliberately
// harder than the other material fixtures: the UMIK-1 is on its 18 dB gain path, so the peak sits
// at -65.5 dB against a -63.9 dB threshold.
private let brace3Case = ParityOracle.playback("REG-B2")
private let brace3ExpectedPeak = brace3Case.peak("longitudinal")
private let brace3ExpectedFrequency: Float = brace3ExpectedPeak.frequency
private let brace3ExpectedMagnitude: Float = brace3ExpectedPeak.magnitude
private let brace3ExpectedQ: Float = brace3ExpectedPeak.q ?? 0
private let brace3TapThreshold: Float = brace3Case.settings.tapDetectionThreshold
private let brace3TapCount: Int = brace3Case.settings.numberOfTaps ?? 3
// Swift MINTS the oracle, so these assert at the same-edition bar — zero. The values in
// the file are the exact Floats this code produced, stored as the shortest decimal that
// recovers them, so equality is exact and any movement is a real change in the DSP.
// ParityOracle.shared.tolerances is the cross-edition bar and is for the tracking
// editions; using it here would hide Swift drift four orders of magnitude below it,
// which is precisely what it did until the oracle was first re-minted.
// Every Swift playback case asserts at `selfTolerances` (zero): Swift mints the oracle, so the question
// is whether Swift still reproduces itself exactly. Python and the web assert the same values at the
// cross-edition `tolerances` — whether they agree with Swift.
private let freqTolerance: Float = ParityOracle.selfTolerance(\.freqHz)  // Hz
private let magTolerance: Float  = ParityOracle.selfTolerance(\.magDb)   // dB
private let qTolerance: Float    = ParityOracle.selfTolerance(\.q)       // dimensionless

// REG-P1 - plate, UMIK-1 mic, 48 kHz. Full-session recording covering all three plate phases
// (L -> C -> FLC). Played back end-to-end through the plate pipeline, which auto-advances
// between phases on file playback so the run reaches .complete with all three peaks populated.
private let plateCase = ParityOracle.playback("REG-P1")
private let plateLExpectedFrequency: Float = plateCase.peak("longitudinal").frequency
private let plateLExpectedMagnitude: Float = plateCase.peak("longitudinal").magnitude
private let plateLExpectedQ: Float = plateCase.peak("longitudinal").q ?? 0

private let plateCExpectedFrequency: Float = plateCase.peak("cross").frequency
private let plateCExpectedMagnitude: Float = plateCase.peak("cross").magnitude
private let plateCExpectedQ: Float = plateCase.peak("cross").q ?? 0

private let plateFlcExpectedFrequency: Float = plateCase.peak("flc").frequency
private let plateFlcExpectedMagnitude: Float = plateCase.peak("flc").magnitude
private let plateFlcExpectedQ: Float = plateCase.peak("flc").q ?? 0

private let plateTapThreshold: Float = plateCase.settings.tapDetectionThreshold

// REG-P2 - plate, UMIK-1, 48 kHz, recorded by the WEB app (Chrome) with numberOfTaps = 3
// (3 taps PER PHASE, 9 total). Replaying at numberOfTaps = 3 averages each phase; the peak must
// come off the averaged spectrum, not the last tap.
private let plate3TapCase = ParityOracle.playback("REG-P2")
private let plate3TapLExpectedFrequency: Float = plate3TapCase.peak("longitudinal").frequency
private let plate3TapLExpectedMagnitude: Float = plate3TapCase.peak("longitudinal").magnitude
private let plate3TapLExpectedQ: Float = plate3TapCase.peak("longitudinal").q ?? 0
private let plate3TapCExpectedFrequency: Float = plate3TapCase.peak("cross").frequency
private let plate3TapCExpectedMagnitude: Float = plate3TapCase.peak("cross").magnitude
private let plate3TapCExpectedQ: Float = plate3TapCase.peak("cross").q ?? 0
private let plate3TapFlcExpectedFrequency: Float = plate3TapCase.peak("flc").frequency
// peak read off the AVERAGED spectrum, not the last tap - see the oracle's _note
private let plate3TapFlcExpectedMagnitude: Float = plate3TapCase.peak("flc").magnitude
private let plate3TapFlcExpectedQ: Float = plate3TapCase.peak("flc").q ?? 0
private let plate3TapThreshold: Float = plate3TapCase.settings.tapDetectionThreshold

// ---------------------------------------------------------------------------
// MARK: - Tests
// ---------------------------------------------------------------------------

@Suite("FilePlaybackRegression")
struct FilePlaybackRegressionTests {

    // REG-B2: Brace, three taps averaged — the brace counterpart to REG-P2 (see its expected values
    // above). Verifies that the pipeline completes and that the peak read off the AVERAGED spectrum
    // matches the oracle's frequency, magnitude and Q (at zero).
    @Test func REG_B2_braceThreeTaps_averagesToExpectedPeak() async throws {
        let stem = "brace-3-tap-umik-1-mac-algo-test-1789854214"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }
        let calURL = testBundle.url(forResource: "7108913", withExtension: "txt")

        let sut = TapToneAnalyzer.forTesting()
        sut.tapDetectionThreshold = brace3TapThreshold
        try await sut.playFileAndWait(url: url, measurementType: .brace,
                                         numberOfTaps: brace3TapCount, calibrationURL: calURL)

        #expect(sut.materialTapPhase == .complete,
                "materialTapPhase should be .complete, got \(sut.materialTapPhase)")
        #expect(sut.isMeasurementComplete, "isMeasurementComplete should be true")
        #expect(sut.selectedLongitudinalPeak != nil, "the fL peak should be identified")

        // The peak must come off the AVERAGED spectrum, not the last tap — the same rule REG-P2
        // pins for plate. The three taps here differ by ~6 dB, so a regression to last-tap
        // selection moves this well outside the bar.
        guard let dominant = sut.selectedLongitudinalPeak else { return }

        let freqDelta = abs(dominant.frequency - brace3ExpectedFrequency)
        #expect(freqDelta <= freqTolerance,
                "Peak frequency: expected \(brace3ExpectedFrequency) Hz ±\(freqTolerance), got \(dominant.frequency) Hz (delta \(freqDelta))")

        let magDelta = abs(dominant.magnitude - brace3ExpectedMagnitude)
        #expect(magDelta <= magTolerance,
                "Peak magnitude: expected \(brace3ExpectedMagnitude) dB ±\(magTolerance), got \(dominant.magnitude) dB (delta \(magDelta))")

        let qDelta = abs(dominant.quality - brace3ExpectedQ)
        #expect(qDelta <= qTolerance,
                "Peak Q factor: expected \(brace3ExpectedQ) ±\(qTolerance), got \(dominant.quality) (delta \(qDelta))")
    }

    // REG-B1: Brace single-tap — known WAV produces expected fL peak.
    //
    // Loads a full-session brace recording WAV (~12.6 s, 48 kHz) and plays it
    // through the full pipeline with measurementType = .brace.  Verifies that:
    //   1. The pipeline completes (materialTapPhase == .complete)
    //   2. At least one longitudinal peak is detected
    //   3. The dominant peak's frequency, magnitude and Q match the oracle (at zero — see above)
    @Test func REG_B1_braceSingleTap_producesExpectedPeak() async throws {
        let stem = "brace-umik-1-swift-mac-1778816093"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }
        let calURL = testBundle.url(forResource: "7108913", withExtension: "txt")

        let sut = TapToneAnalyzer.forTesting()
        sut.tapDetectionThreshold = braceTapThreshold
        try await sut.playFileAndWait(url: url, measurementType: .brace, calibrationURL: calURL)

        // 1. Pipeline should reach .complete for brace (single-tap mode).
        #expect(sut.materialTapPhase == .complete,
                "materialTapPhase should be .complete, got \(sut.materialTapPhase)")

        #expect(sut.isMeasurementComplete,
                "isMeasurementComplete should be true")

        // 2. The fL peak should be identified.
        #expect(sut.selectedLongitudinalPeak != nil, "the fL peak should be identified")

        // 3. Verify the fL peak's frequency.
        guard let dominant = sut.selectedLongitudinalPeak else { return }
        let freqDelta = abs(dominant.frequency - braceExpectedFrequency)
        #expect(freqDelta <= freqTolerance,
                "Peak frequency: expected \(braceExpectedFrequency) Hz ±\(freqTolerance), got \(dominant.frequency) Hz (delta \(freqDelta))")

        // 4. Verify dominant peak magnitude.
        let magDelta = abs(dominant.magnitude - braceExpectedMagnitude)
        #expect(magDelta <= magTolerance,
                "Peak magnitude: expected \(braceExpectedMagnitude) dB ±\(magTolerance), got \(dominant.magnitude) dB (delta \(magDelta))")

        // 5. Verify dominant peak Q factor.
        let qDelta = abs(dominant.quality - braceExpectedQ)
        #expect(qDelta <= qTolerance,
                "Peak Q factor: expected \(braceExpectedQ) ±\(qTolerance), got \(dominant.quality) (delta \(qDelta))")
    }

    // MARK: - REG-G1: O'Brien single-tap generic guitar

    // Recording 5.wav — Generic guitar, single-tap, 48 kHz.
    // The oracle's values originally came from the Recording 5.guitartap file (Tests/O'Brien/).
    // Settings: peakMinThreshold = -76, tapDetectionThreshold = -40,
    //           measurementType = .generic, numberOfTaps = 1.
    //           FFT size is a constant (65536) inside RealtimeFFTAnalyzer.
    private static let g1Case = ParityOracle.playback("REG-G1")
    private static let g1AirFreq: Float = g1Case.peak("air").frequency
    private static let g1AirMag: Float  = g1Case.peak("air").magnitude
    private static let g1TopFreq: Float = g1Case.peak("top").frequency
    private static let g1TopMag: Float  = g1Case.peak("top").magnitude
    private static let g1BackFreq: Float = g1Case.peak("back").frequency
    private static let g1BackMag: Float  = g1Case.peak("back").magnitude

    /// REG-G1: Generic guitar single-tap — validates Air/Top/Back peaks.
    ///
    /// Loads a single-tap generic guitar recording and plays it through the
    /// full pipeline.  Verifies that:
    ///   1. The pipeline completes with 1 tap entry
    ///   2. Air, Top, Back frequencies and magnitudes match the oracle
    @Test func REG_G1_genericGuitarSingleTap_producesExpectedPeaks() async throws {
        let stem = "Recording 5"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }

        let sut = TapToneAnalyzer.forTesting()
        sut.peakMinThreshold = -76
        sut.tapDetectionThreshold = -40
        try await sut.playFileAndWait(url: url, measurementType: .generic, numberOfTaps: 1)

        // 1. Pipeline should complete with 1 captured tap.
        //    (tapEntries is only populated for multi-tap sessions; single-tap
        //     uses capturedTaps directly.)
        #expect(sut.isMeasurementComplete, "isMeasurementComplete should be true")
        #expect(sut.capturedTaps.count == 1,
                "Expected 1 captured tap, got \(sut.capturedTaps.count)")

        // 2. Peaks — use getPeak(for:), the same API the Results panel uses.
        guard let airPeak = sut.getPeak(for: .air) else {
            Issue.record("No Air peak found")
            return
        }
        #expect(abs(airPeak.frequency - Self.g1AirFreq) <= freqTolerance,
                "Air freq: expected \(Self.g1AirFreq) ±\(freqTolerance), got \(airPeak.frequency)")
        #expect(abs(airPeak.magnitude - Self.g1AirMag) <= magTolerance,
                "Air mag: expected \(Self.g1AirMag) ±\(magTolerance), got \(airPeak.magnitude)")

        guard let topPeak = sut.getPeak(for: .top) else {
            Issue.record("No Top peak found")
            return
        }
        #expect(abs(topPeak.frequency - Self.g1TopFreq) <= freqTolerance,
                "Top freq: expected \(Self.g1TopFreq) ±\(freqTolerance), got \(topPeak.frequency)")
        #expect(abs(topPeak.magnitude - Self.g1TopMag) <= magTolerance,
                "Top mag: expected \(Self.g1TopMag) ±\(magTolerance), got \(topPeak.magnitude)")

        guard let backPeak = sut.getPeak(for: .back) else {
            Issue.record("No Back peak found")
            return
        }
        #expect(abs(backPeak.frequency - Self.g1BackFreq) <= freqTolerance,
                "Back freq: expected \(Self.g1BackFreq) ±\(freqTolerance), got \(backPeak.frequency)")
        #expect(abs(backPeak.magnitude - Self.g1BackMag) <= magTolerance,
                "Back mag: expected \(Self.g1BackMag) ±\(magTolerance), got \(backPeak.magnitude)")
    }

    // MARK: - REG-G: ring-out (decay) time

    /// REG-G ring-out — the post-tap level for Recording 5.wav decays to peak−15 dB, measured on the audio
    /// clock. The value is the oracle's, shared by all three editions.
    @Test func REG_G_genericGuitarRingOut_matchesGolden() async throws {
        let stem = "Recording 5"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }

        let sut = TapToneAnalyzer.forTesting()
        sut.peakMinThreshold = -76
        sut.tapDetectionThreshold = -40
        try await sut.playFileAndWait(url: url, measurementType: .generic, numberOfTaps: 1)

        guard let decay = sut.currentDecayTime else {
            Issue.record("No ring-out measured")
            return
        }
        let golden: Float = ParityOracle.playback("REG-G1").ringOutSec ?? 0
        let tol: Float = ParityOracle.selfTolerance(\.ringOutSec)
        #expect(abs(decay - golden) <= tol,
                "Ring-out: expected \(golden) ±\(tol), got \(decay)")
    }

    // MARK: - REG-G2: O'Brien 8-tap generic guitar

    // Recording.wav — Generic guitar, 8-tap multi-tap, 48 kHz.
    // The oracle's values originally came from the Recording.guitartap file (Tests/O'Brien/).
    // Settings: peakMinThreshold = -76, tapDetectionThreshold = -40,
    //           measurementType = .generic, numberOfTaps = 8.
    //           FFT size is a constant (65536) inside RealtimeFFTAnalyzer.

    // Average peaks
    private static let g2Case = ParityOracle.playback("REG-G2")
    private static let guitarAvgAirFreq: Float = g2Case.peak("air", averaged: true).frequency
    private static let guitarAvgAirMag: Float  = g2Case.peak("air", averaged: true).magnitude
    private static let guitarAvgTopFreq: Float = g2Case.peak("top", averaged: true).frequency
    private static let guitarAvgTopMag: Float  = g2Case.peak("top", averaged: true).magnitude
    private static let guitarAvgBackFreq: Float = g2Case.peak("back", averaged: true).frequency
    private static let guitarAvgBackMag: Float  = g2Case.peak("back", averaged: true).magnitude

    // Per-tap expected values: (airFreq, airMag, topFreq, topMag, backFreq, backMag)
    // Taps 1 and 7 pin Back at ~296.5 Hz rather than ~240.6 - real behaviour of the shared
    // selection path on this fixture, pinned deliberately (see _perTapNote in the oracle).
    private typealias PerTapRow = (airFreq: Float, airMag: Float,
                                   topFreq: Float, topMag: Float,
                                   backFreq: Float, backMag: Float)

    /// One oracle `perTap` row, as the tuple the assertions below expect.
    ///
    /// Written out in annotated steps rather than as a single tuple literal: six optional
    /// chains with `??` defaults in one expression is more than the type checker will solve
    /// in reasonable time (it was the literal that produced "unable to type-check this
    /// expression in reasonable time").
    private static func perTapRow(_ row: ParityOracle.TapRow) -> PerTapRow {
        func peak(_ role: String) -> ParityOracle.Peak? {
            row.peaks.first(where: { $0.role == role })
        }
        let air: ParityOracle.Peak? = peak("air")
        let top: ParityOracle.Peak? = peak("top")
        let back: ParityOracle.Peak? = peak("back")

        let airFreq: Float = air?.frequency ?? 0
        let airMag: Float = air?.magnitude ?? 0
        let topFreq: Float = top?.frequency ?? 0
        let topMag: Float = top?.magnitude ?? 0
        let backFreq: Float = back?.frequency ?? 0
        let backMag: Float = back?.magnitude ?? 0

        return (airFreq: airFreq, airMag: airMag,
                topFreq: topFreq, topMag: topMag,
                backFreq: backFreq, backMag: backMag)
    }

    private static let guitarPerTap: [PerTapRow] = (g2Case.perTap ?? []).map(perTapRow)

    /// REG-G2: Generic guitar 8-tap — validates averaged and per-tap Air/Top/Back.
    ///
    /// Loads a live 8-tap generic guitar recording and plays it through the full
    /// pipeline.  Verifies that:
    ///   1. The pipeline completes with 8 tap entries
    ///   2. Averaged Air, Top, Back frequencies and magnitudes match the oracle
    ///   3. All 8 individual taps' Air, Top, Back frequencies and magnitudes match
    @Test func REG_G2_genericGuitar8Tap_producesExpectedPeaks() async throws {
        let stem = "Recording"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }

        let sut = TapToneAnalyzer.forTesting()
        sut.peakMinThreshold = -76
        sut.tapDetectionThreshold = -40
        try await sut.playFileAndWait(url: url, measurementType: .generic, numberOfTaps: 8)

        // 1. Pipeline should complete with 8 tap entries.
        #expect(sut.isMeasurementComplete, "isMeasurementComplete should be true")
        #expect(sut.tapEntries.count == 8,
                "Expected 8 tap entries, got \(sut.tapEntries.count)")

        // 2. Averaged peaks — use getPeak(for:), the same API the Results panel uses.
        guard let airPeak = sut.getPeak(for: .air) else {
            Issue.record("No averaged Air peak found")
            return
        }
        #expect(abs(airPeak.frequency - Self.guitarAvgAirFreq) <= freqTolerance,
                "Avg Air freq: expected \(Self.guitarAvgAirFreq) ±\(freqTolerance), got \(airPeak.frequency)")
        #expect(abs(airPeak.magnitude - Self.guitarAvgAirMag) <= magTolerance,
                "Avg Air mag: expected \(Self.guitarAvgAirMag) ±\(magTolerance), got \(airPeak.magnitude)")

        guard let topPeak = sut.getPeak(for: .top) else {
            Issue.record("No averaged Top peak found")
            return
        }
        #expect(abs(topPeak.frequency - Self.guitarAvgTopFreq) <= freqTolerance,
                "Avg Top freq: expected \(Self.guitarAvgTopFreq) ±\(freqTolerance), got \(topPeak.frequency)")
        #expect(abs(topPeak.magnitude - Self.guitarAvgTopMag) <= magTolerance,
                "Avg Top mag: expected \(Self.guitarAvgTopMag) ±\(magTolerance), got \(topPeak.magnitude)")

        guard let backPeak = sut.getPeak(for: .back) else {
            Issue.record("No averaged Back peak found")
            return
        }
        #expect(abs(backPeak.frequency - Self.guitarAvgBackFreq) <= freqTolerance,
                "Avg Back freq: expected \(Self.guitarAvgBackFreq) ±\(freqTolerance), got \(backPeak.frequency)")
        #expect(abs(backPeak.magnitude - Self.guitarAvgBackMag) <= magTolerance,
                "Avg Back mag: expected \(Self.guitarAvgBackMag) ±\(magTolerance), got \(backPeak.magnitude)")

        // 3. Per-tap peaks — uses TapEntry.resolvedModePeaks(), the same
        //    code path as MultiTapComparisonResultsView and PDF export.
        for (index, entry) in sut.tapEntries.enumerated() {
            let expected = Self.guitarPerTap[index]
            let tapLabel = "Tap \(index + 1)"

            let modePeaks = entry.resolvedModePeaks()

            // Air
            if let air = modePeaks[.air] {
                #expect(abs(air.frequency - expected.airFreq) <= freqTolerance,
                        "\(tapLabel) Air freq: expected \(expected.airFreq) ±\(freqTolerance), got \(air.frequency)")
                #expect(abs(air.magnitude - expected.airMag) <= magTolerance,
                        "\(tapLabel) Air mag: expected \(expected.airMag) ±\(magTolerance), got \(air.magnitude)")
            } else {
                Issue.record("\(tapLabel): no Air peak found in selected peaks")
            }

            // Top
            if let top = modePeaks[.top] {
                #expect(abs(top.frequency - expected.topFreq) <= freqTolerance,
                        "\(tapLabel) Top freq: expected \(expected.topFreq) ±\(freqTolerance), got \(top.frequency)")
                #expect(abs(top.magnitude - expected.topMag) <= magTolerance,
                        "\(tapLabel) Top mag: expected \(expected.topMag) ±\(magTolerance), got \(top.magnitude)")
            } else {
                Issue.record("\(tapLabel): no Top peak found in selected peaks")
            }

            // Back
            if let back = modePeaks[.back] {
                #expect(abs(back.frequency - expected.backFreq) <= freqTolerance,
                        "\(tapLabel) Back freq: expected \(expected.backFreq) ±\(freqTolerance), got \(back.frequency)")
                #expect(abs(back.magnitude - expected.backMag) <= magTolerance,
                        "\(tapLabel) Back mag: expected \(expected.backMag) ±\(magTolerance), got \(back.magnitude)")
            } else {
                Issue.record("\(tapLabel): no Back peak found in selected peaks")
            }
        }
    }

    // MARK: - REG-P1: Plate full-session (L + C + FLC)

    // plate-umik-1-swift-mac-1778816330.wav — Plate, UMIK-1, 48 kHz, full session.
    // The oracle's values originally came from the matching .guitartap file in Tests/Plate/.
    // The pipeline runs end-to-end with auto-advance between phases on file
    // playback, so all three peaks are populated and the phase reaches .complete.

    /// REG-P1: Plate full-session — single WAV exercises all three phases.
    ///
    /// Loads a full-session plate recording and plays it through the
    /// pipeline with measurementType = .plate.  Verifies that:
    ///   1. The pipeline reaches .complete (all three phases captured)
    ///   2. fL / fC / fLC peaks are each populated
    ///   3. Each auto-selected peak's frequency, magnitude, and Q factor
    ///      matches the oracle (at zero)
    @Test func REG_P1_plateFullSession_producesExpectedPeaks() async throws {
        let stem = "plate-umik-1-swift-mac-1778816330"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }
        let calURL = testBundle.url(forResource: "7108913", withExtension: "txt")

        // FLC must be enabled — the saved measurement was captured with all
        // three phases, and the playback pipeline reads this flag to decide
        // whether to advance past C → FLC or finish after C.  Save/restore
        // so the test doesn't bleed state into other tests in the suite.
        let originalMeasureFlc = TapDisplaySettings.measureFlc
        TapDisplaySettings.measureFlc = true
        defer { TapDisplaySettings.measureFlc = originalMeasureFlc }

        let sut = TapToneAnalyzer.forTesting()
        sut.tapDetectionThreshold = plateTapThreshold
        try await sut.playFileAndWait(url: url, measurementType: .plate, calibrationURL: calURL)

        // 1. Pipeline should reach .complete after all three phases.
        #expect(sut.materialTapPhase == .complete,
                "materialTapPhase should be .complete, got \(sut.materialTapPhase)")
        #expect(sut.isMeasurementComplete,
                "isMeasurementComplete should be true")

        // 2. All three peak arrays populated.
        #expect(sut.selectedLongitudinalPeak != nil, "the fL peak should be identified")
        #expect(sut.selectedCrossPeak != nil, "the fC peak should be identified")
        #expect(sut.selectedFlcPeak != nil, "the fLC peak should be identified")

        // 3a. fL peak.
        guard let lPeak = sut.selectedLongitudinalPeak else {
            Issue.record("selectedLongitudinalPeak is nil")
            return
        }
        let lFreqDelta = abs(lPeak.frequency - plateLExpectedFrequency)
        #expect(lFreqDelta <= freqTolerance,
                "fL frequency: expected \(plateLExpectedFrequency) Hz ±\(freqTolerance), got \(lPeak.frequency) Hz (delta \(lFreqDelta))")
        let lMagDelta = abs(lPeak.magnitude - plateLExpectedMagnitude)
        #expect(lMagDelta <= magTolerance,
                "fL magnitude: expected \(plateLExpectedMagnitude) dB ±\(magTolerance), got \(lPeak.magnitude) dB (delta \(lMagDelta))")
        let lQDelta = abs(lPeak.quality - plateLExpectedQ)
        #expect(lQDelta <= qTolerance,
                "fL Q factor: expected \(plateLExpectedQ) ±\(qTolerance), got \(lPeak.quality) (delta \(lQDelta))")

        // 3b. fC peak.
        guard let cPeak = sut.selectedCrossPeak else {
            Issue.record("selectedCrossPeak is nil")
            return
        }
        let cFreqDelta = abs(cPeak.frequency - plateCExpectedFrequency)
        #expect(cFreqDelta <= freqTolerance,
                "fC frequency: expected \(plateCExpectedFrequency) Hz ±\(freqTolerance), got \(cPeak.frequency) Hz (delta \(cFreqDelta))")
        let cMagDelta = abs(cPeak.magnitude - plateCExpectedMagnitude)
        #expect(cMagDelta <= magTolerance,
                "fC magnitude: expected \(plateCExpectedMagnitude) dB ±\(magTolerance), got \(cPeak.magnitude) dB (delta \(cMagDelta))")
        let cQDelta = abs(cPeak.quality - plateCExpectedQ)
        #expect(cQDelta <= qTolerance,
                "fC Q factor: expected \(plateCExpectedQ) ±\(qTolerance), got \(cPeak.quality) (delta \(cQDelta))")

        // 3c. fLC peak.
        guard let flcPeak = sut.selectedFlcPeak else {
            Issue.record("selectedFlcPeak is nil")
            return
        }
        let flcFreqDelta = abs(flcPeak.frequency - plateFlcExpectedFrequency)
        #expect(flcFreqDelta <= freqTolerance,
                "fLC frequency: expected \(plateFlcExpectedFrequency) Hz ±\(freqTolerance), got \(flcPeak.frequency) Hz (delta \(flcFreqDelta))")
        let flcMagDelta = abs(flcPeak.magnitude - plateFlcExpectedMagnitude)
        #expect(flcMagDelta <= magTolerance,
                "fLC magnitude: expected \(plateFlcExpectedMagnitude) dB ±\(magTolerance), got \(flcPeak.magnitude) dB (delta \(flcMagDelta))")
        let flcQDelta = abs(flcPeak.quality - plateFlcExpectedQ)
        #expect(flcQDelta <= qTolerance,
                "fLC Q factor: expected \(plateFlcExpectedQ) ±\(qTolerance), got \(flcPeak.quality) (delta \(flcQDelta))")
    }

    // ── Noisy plate: the one test that can tell the two detection models apart ──────────────────
    //
    // plate-umik-1-noisy-52.wav is the SAME plate session with broadband noise mixed in to raise its
    // noise floor from -77 dBFS to -52 dBFS — i.e. ABOVE the -53.34 dB tap threshold.
    //
    // All three editions detect material taps against an EMA-tracked noise floor, not a fixed absolute
    // dBFS threshold. The relative rule reduces to
    //     rising = max(tapDetectionThreshold, noiseFloor + 10 dB)
    // so the two are the SAME FUNCTION until the floor climbs within 10 dB of the threshold. Every
    // other fixture sits at -64…-69 dBFS, far below that, so no other test separates them.
    //
    // At a -52 floor an ABSOLUTE detector SATURATES: the level never drops below the threshold, so no
    // rising edge can be confirmed and it captures NOTHING. The RELATIVE detector floats its threshold
    // to floor+10 = -42 dB and still finds every tap (they peak at -24…-27 dBFS chunk-RMS). That is
    // precisely the failure the relative model exists to prevent: "keeps detection working when
    // ambient noise is elevated".
    //
    // Material file playback does not skip the warm-up, so noiseFloorEstimate is not pinned at -100
    // (which would collapse `rising` onto the absolute threshold).
    //
    // Asserts the PHASE COUNT, not peak values: the added noise sums into the gated FFT, so fL/fC/fLC
    // shift slightly. A tight peak assertion here would be measuring the noise, not the detector.
    //
    // Regenerate: python3 GuitarTapWeb/tooling/make-noisy-fixture.py (deterministic, seeded).
    @Test func OUT4_noisyPlate_relativeNoiseFloor_stillCapturesAllPhases() async throws {
        let stem = "plate-umik-1-noisy-52"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }
        let calURL = testBundle.url(forResource: "7108913", withExtension: "txt")

        let originalMeasureFlc = TapDisplaySettings.measureFlc
        TapDisplaySettings.measureFlc = true
        defer { TapDisplaySettings.measureFlc = originalMeasureFlc }

        let sut = TapToneAnalyzer.forTesting()
        sut.tapDetectionThreshold = plateTapThreshold
        try await sut.playFileAndWait(url: url, measurementType: .plate, calibrationURL: calURL)

        let captured = [
            ("L", sut.longitudinalSpectrum != nil),
            ("C", sut.crossSpectrum != nil),
            ("FLC", sut.flcSpectrum != nil),
        ].filter { $0.1 }.map { $0.0 }

        #expect(captured.count == 3,
                """
                absolute-threshold detection saturates on an elevated noise floor and captures nothing; \
                the noise-floor-relative detector must still find all three taps. \
                Captured: \(captured), noiseFloorEstimate=\(sut.noiseFloorEstimate) dBFS
                """)

        // The floor must have actually CONVERGED to the noisy ambient. If it is still pinned near -100,
        // the relative model has silently degraded to the absolute one and this test would be passing
        // for the wrong reason.
        #expect(sut.noiseFloorEstimate > -60 && sut.noiseFloorEstimate < -40,
                "noiseFloorEstimate should have converged to the fixture's ~-52 dBFS floor; got \(sut.noiseFloorEstimate) (pinned at -100 means relative detection is OFF)")
    }


    // MARK: - REG-P2: Plate, 3 taps per phase (multi-tap averaging)

    /// REG-P2: Plate at numberOfTaps = 3 — each phase (L/C/FLC) averages 3 taps.
    ///
    /// Replays a 3-taps-per-phase plate session (recorded by the web app) at
    /// numberOfTaps = 3, exercising the multi-tap-per-phase averaging path
    /// (handleLongitudinalGatedProgress collecting numberOfTaps before
    /// averageSpectra). The expected values are the oracle's, as for every case.
    @Test func REG_P2_plateThreeTapsPerPhase_averagesEachPhase() async throws {
        let stem = "plate-umik-1-web-mac-3-taps"
        guard let url = testBundle.url(forResource: stem, withExtension: "wav") else {
            Issue.record("\(stem).wav not found in test bundle")
            return
        }
        let calURL = testBundle.url(forResource: "7108913", withExtension: "txt")

        let originalMeasureFlc = TapDisplaySettings.measureFlc
        TapDisplaySettings.measureFlc = true
        defer { TapDisplaySettings.measureFlc = originalMeasureFlc }

        let sut = TapToneAnalyzer.forTesting()
        sut.tapDetectionThreshold = plate3TapThreshold
        try await sut.playFileAndWait(url: url, measurementType: .plate, numberOfTaps: 3, calibrationURL: calURL)

        #expect(sut.materialTapPhase == .complete,
                "materialTapPhase should be .complete, got \(sut.materialTapPhase)")
        #expect(sut.isMeasurementComplete, "isMeasurementComplete should be true")

        guard let lPeak = sut.selectedLongitudinalPeak else { Issue.record("selectedLongitudinalPeak is nil"); return }
        #expect(abs(lPeak.frequency - plate3TapLExpectedFrequency) <= freqTolerance,
                "fL frequency: expected \(plate3TapLExpectedFrequency) Hz, got \(lPeak.frequency) Hz")
        #expect(abs(lPeak.magnitude - plate3TapLExpectedMagnitude) <= magTolerance,
                "fL magnitude: expected \(plate3TapLExpectedMagnitude) dB, got \(lPeak.magnitude) dB")
        #expect(abs(lPeak.quality - plate3TapLExpectedQ) <= qTolerance,
                "fL Q: expected \(plate3TapLExpectedQ), got \(lPeak.quality)")

        guard let cPeak = sut.selectedCrossPeak else { Issue.record("selectedCrossPeak is nil"); return }
        #expect(abs(cPeak.frequency - plate3TapCExpectedFrequency) <= freqTolerance,
                "fC frequency: expected \(plate3TapCExpectedFrequency) Hz, got \(cPeak.frequency) Hz")
        #expect(abs(cPeak.magnitude - plate3TapCExpectedMagnitude) <= magTolerance,
                "fC magnitude: expected \(plate3TapCExpectedMagnitude) dB, got \(cPeak.magnitude) dB")
        #expect(abs(cPeak.quality - plate3TapCExpectedQ) <= qTolerance,
                "fC Q: expected \(plate3TapCExpectedQ), got \(cPeak.quality)")

        guard let flcPeak = sut.selectedFlcPeak else { Issue.record("selectedFlcPeak is nil"); return }
        #expect(abs(flcPeak.frequency - plate3TapFlcExpectedFrequency) <= freqTolerance,
                "fLC frequency: expected \(plate3TapFlcExpectedFrequency) Hz, got \(flcPeak.frequency) Hz")
        #expect(abs(flcPeak.magnitude - plate3TapFlcExpectedMagnitude) <= magTolerance,
                "fLC magnitude: expected \(plate3TapFlcExpectedMagnitude) dB, got \(flcPeak.magnitude) dB")
        #expect(abs(flcPeak.quality - plate3TapFlcExpectedQ) <= qTolerance,
                "fLC Q: expected \(plate3TapFlcExpectedQ), got \(flcPeak.quality)")
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
