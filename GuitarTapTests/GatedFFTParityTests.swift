//
//  GatedFFTParityTests.swift
//  GuitarTapTests
//
//  Parity tests for computeGatedFFT, the transform every plate/brace capture runs. GFFT1–GFFT5 feed
//  the oracle's synthetic signals and assert the oracle's dB, so the Python and web suites feed the
//  same tones and assert the same values — any systematic difference between the implementations
//  shows up as a one-sided failure rather than as three sets of numbers drifting apart. The remaining
//  cases pin rules the oracle cases cannot see: which window is used, that calibration is applied
//  inside the transform, and that too little input is not a spectrum.
//
//  Test plan coverage: GFFT1–GFFT5
//
// @parity test/gated-fft

import Testing
import Foundation
@testable import GuitarTap

/// Anchors Bundle(for:) to the test bundle holding the calibration fixture.
private final class GatedFFTBundleAnchor {}

@Suite("GatedFFTParityTests")
struct GatedFFTParityTests {

    /// Swift minted the oracle, so it asserts at the same-edition bar (`selfTolerances`). See
    /// FilePlaybackRegressionTests for why Swift does not use the cross-edition tolerance.
    private static let tol: Float = ParityOracle.selfTolerance(\.gatedFftDb)
    private static let sampleRate: Double = 48000

    /// A hardware-free analyzer: no device enumeration, so no saved device calibration can be loaded
    /// into it mid-test.
    private func analyzer() -> RealtimeFFTAnalyzer {
        RealtimeFFTAnalyzer.forTesting()
    }

    /// Runs one oracle case and checks each expected tone, and the delta where the case records one.
    private func check(_ name: String) {
        let gfft = ParityOracle.gated(name)
        let signal = makeGatedTestSignal(tones: gfft.toneList, sampleRate: Self.sampleRate)
        let (mags, freqs) = analyzer().computeGatedFFT(samples: signal, sampleRate: Self.sampleRate)

        let got = gfft.toneList.map { gatedMagnitude(at: Float($0.hz), magnitudes: mags, frequencies: freqs)! }
        for (tone, db) in zip(gfft.toneList, got) {
            let expected = gfft.expectedDb(at: tone.hz)
            #expect(abs(db - expected) <= Self.tol,
                    "\(name) \(tone.hz) Hz: Swift=\(db) dB, oracle=\(expected) dB")
        }
        if got.count >= 2 {
            let expDelta = gfft.deltaDb ?? (gfft.expectedDb(at: gfft.toneList[1].hz) - gfft.expectedDb(at: gfft.toneList[0].hz))
            let delta = got[1] - got[0]
            #expect(abs(delta - expDelta) <= Self.tol,
                    "\(name) delta: Swift=\(delta) dB, oracle=\(expDelta) dB")
        }
    }

    // Every oracle case with tones, by its id — the list is the oracle's, shared by the three editions.
    // The oracle's tone cases: GFFT1, a single tone; GFFT2, two tones at the plate-C capture
    // frequencies that once exposed a discrepancy; GFFT3, two tones at exact bin centres (bins 46 and 80 at 32768
    // points) — being bin centres does NOT remove leakage here: the window spans the padded 32768 samples and the
    // signal only the first 19200, so no tone is periodic in the window, and the 67 Hz tone reads differently here
    // from GFFT5, where it is alone; GFFT5, one bin-centred tone, which pins the window's normalisation (Swift's
    // HANN_NORM instead of HANN_DENORM would read about 4.26 dB high).
    nonisolated static let toneCases: [String] = ParityOracle.shared.gatedFft
        .filter { !$0.value.toneList.isEmpty }.keys.sorted()

    @Test("every oracle tone case matches the oracle", arguments: toneCases)
    func toneCase(_ name: String) { check(name) }

    // GFFT4: silence reads exactly the oracle's value — −∞ in every bin. The oracle stores it as the
    // string "-Infinity", which every edition's reader decodes.
    @Test("GFFT4 — silence is −∞ in every bin")
    func gfft4_silenceIsMinusInfinity() {
        let signal = makeGatedTestSignal(tones: [], sampleRate: Self.sampleRate)
        let (mags, _) = analyzer().computeGatedFFT(samples: signal, sampleRate: Self.sampleRate)

        let expected = ParityOracle.gated("GFFT4").maxDb
        let maxMag = mags.max()
        #expect(expected != nil, "the oracle records GFFT4's exact value")
        #expect(maxMag == expected, "silence must read \(String(describing: expected)) dB, got \(String(describing: maxMag))")
    }

    // The window is the PERIODIC Hann, 0.5·(1 − cos 2πn/N). A constant input fills the padded length,
    // so the windowed signal IS the window, and a periodic Hann's spectrum is exactly bins 0 and 1:
    // every bin from 2 up is empty (below −185 dB in float32). The symmetric form, np.hanning's
    // (N−1), leaks into those bins at about −100 dB. The two are otherwise too close for any oracle
    // tolerance to tell apart, which is how the ports drifted to the symmetric one before.
    @Test("the gated window is the periodic Hann")
    func gatedWindowIsPeriodicHann() {
        let n = 32768
        let (mags, _) = analyzer().computeGatedFFT(samples: [Float](repeating: 1, count: n),
                                                   sampleRate: Self.sampleRate)
        #expect(mags.count == n / 2)
        let highest = mags.dropFirst(2).max() ?? .infinity
        #expect(highest < -120, "bins ≥ 2 must be empty for a periodic Hann; highest is \(highest) dB")
    }

    // Fewer than two samples is not a spectrum: the result is empty, which callers treat as a failed
    // capture ("tap again").
    @Test("fewer than two samples gives an empty spectrum")
    func tooFewSamplesGivesEmptySpectrum() {
        for count in [0, 1] {
            let (mags, freqs) = analyzer().computeGatedFFT(samples: [Float](repeating: 0.5, count: count),
                                                           sampleRate: Self.sampleRate)
            #expect(mags.isEmpty && freqs.isEmpty, "\(count) sample(s) gave \(mags.count) bins")
        }
    }

    // Calibration is applied INSIDE the transform, from the analyzer's active calibration at the
    // moment of the call: the calibrated spectrum is the uncalibrated one plus the calibration's
    // correction at every bin. Uses the UMIK-1 calibration fixture the file-playback cases use.
    @Test("calibration is applied inside the gated transform")
    func calibrationAppliedInsideTransform() throws {
        let url = try #require(Bundle(for: GatedFFTBundleAnchor.self).url(forResource: "7108913", withExtension: "txt"))
        let cal = try CalibrationFileParser.parse(url: url)
        let signal = makeGatedTestSignal(tones: ParityOracle.gated("GFFT2").toneList, sampleRate: Self.sampleRate)

        let fft = analyzer()
        let (plain, freqs) = fft.computeGatedFFT(samples: signal, sampleRate: Self.sampleRate)
        fft.setTemporaryCalibration(cal)
        let (calibrated, calFreqs) = fft.computeGatedFFT(samples: signal, sampleRate: Self.sampleRate)

        #expect(calFreqs == freqs)
        let corrections = cal.corrections(for: freqs)
        try #require(corrections.count == plain.count)
        #expect(corrections.contains { abs($0) > 0.5 }, "the fixture must correct by a visible amount")
        // The worst bin, so a failure reports once rather than per bin.
        let worst = plain.indices.filter { plain[$0].isFinite }
            .max { abs(calibrated[$0] - (plain[$0] + corrections[$0])) < abs(calibrated[$1] - (plain[$1] + corrections[$1])) }!
        #expect(abs(calibrated[worst] - (plain[worst] + corrections[worst])) <= 1e-4,
                "bin \(worst) (\(freqs[worst]) Hz): \(calibrated[worst]) ≠ \(plain[worst]) + \(corrections[worst])")
    }
}
