//
//  DSPTests.swift
//  GuitarTapTests
//
//  Tests for the DSP layer: parabolic interpolation and Q-factor calculation.
//  These methods live in TapToneAnalyzer+PeakAnalysis.swift and are pure data-in/
//  data-out functions that require no audio hardware.
//
//  Test plan coverage: F1–F9
//
// @parity test/dsp

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

/// Build a minimal TapToneAnalyzer whose underlying RealtimeFFTAnalyzer is
/// never started.  We only exercise the pure-math extension methods.
private func makeSUT() -> TapToneAnalyzer {
    let fft = RealtimeFFTAnalyzer.forTesting()
    return TapToneAnalyzer(fftAnalyzer: fft)
}

/// Construct a synthetic spectrum (magnitudes + linear frequencies) with a
/// Gaussian-shaped peak centred at `peakHz`.
///
/// - Parameters:
///   - binCount:   Number of FFT bins.
///   - sampleRate: Sample rate in Hz; determines the Nyquist limit.
///   - peakHz:     Centre frequency of the synthetic peak.
///   - peakDB:     Peak magnitude in dB.
///   - halfWidth:  Width of the Gaussian envelope in Hz at the -3 dB point.
///   - noiseFloor: Background level for all other bins (dB).
private func makeSpectrum(
    binCount: Int = 1024,
    sampleRate: Double = 48000,
    peakHz: Float,
    peakDB: Float = -20,
    halfWidth: Float = 10,
    noiseFloor: Float = -80
) -> (magnitudes: [Float], frequencies: [Float]) {
    let binWidth = Float(sampleRate / 2) / Float(binCount - 1)
    var magnitudes = [Float](repeating: noiseFloor, count: binCount)
    var frequencies = [Float](repeating: 0, count: binCount)

    for i in 0..<binCount {
        let f = Float(i) * binWidth
        frequencies[i] = f
        let dist = f - peakHz
        // Gaussian envelope: σ derived from half-width at -3 dB
        let sigma = halfWidth / 2.355
        let gauss = peakDB + (-dist * dist / (2 * sigma * sigma))
        magnitudes[i] = max(gauss, noiseFloor)
    }
    return (magnitudes, frequencies)
}

// ---------------------------------------------------------------------------
// MARK: - Parabolic Interpolation Tests  (F1–F6)
// ---------------------------------------------------------------------------

@Suite("ParabolicInterpolation")
struct ParabolicInterpolationTests {

    // F1: A flat-top peak where the two neighbours are equal returns δ = 0
    // and the centre bin frequency exactly.
    @Test func symmetricPeak_returnsExactCentreBin() {
        let sut = makeSUT()
        // Craft magnitudes: left = right = val-1, so δ = 0
        let mags: [Float] = [-80, -80, -30, -30, -30, -80, -80]
        let freqs: [Float] = [0, 10, 20, 30, 40, 50, 60]
        // When both neighbours equal the peak there is no tilt → denom is non-zero
        // but numerator (lval - rval) = 0, so δ = 0.
        let (freq, _) = sut.parabolicInterpolate(magnitudes: mags, frequencies: freqs, peakIndex: 3)
        // Allow a tiny floating-point rounding tolerance
        #expect(abs(freq - 30) < 0.01, "Expected freq ≈ 30 Hz, got \(freq)")
    }

    // F2: Left neighbour higher than right → interpolated peak shifts left (negative δ).
    @Test func leftLeaningPeak_shiftedLeft() {
        let sut = makeSUT()
        // magnitudes: peak at index 3, left neighbour (idx 2) > right (idx 4)
        let mags: [Float] = [-80, -80, -25, -20, -35, -80, -80]
        let freqs: [Float] = [0, 10, 20, 30, 40, 50, 60]
        let (freq, _) = sut.parabolicInterpolate(magnitudes: mags, frequencies: freqs, peakIndex: 3)
        #expect(freq < 30, "Expected interpolated freq < 30 Hz (left shift), got \(freq)")
    }

    // F3: Right neighbour higher than left → interpolated peak shifts right.
    @Test func rightLeaningPeak_shiftedRight() {
        let sut = makeSUT()
        let mags: [Float] = [-80, -80, -35, -20, -25, -80, -80]
        let freqs: [Float] = [0, 10, 20, 30, 40, 50, 60]
        let (freq, _) = sut.parabolicInterpolate(magnitudes: mags, frequencies: freqs, peakIndex: 3)
        #expect(freq > 30, "Expected interpolated freq > 30 Hz (right shift), got \(freq)")
    }

    // F4: Edge-bin (index 0) falls back to raw bin values without crash.
    @Test func edgeBinIndex0_returnsRawValues() {
        let sut = makeSUT()
        let mags: [Float] = [-20, -30, -40, -50]
        let freqs: [Float] = [0, 10, 20, 30]
        let (freq, mag) = sut.parabolicInterpolate(magnitudes: mags, frequencies: freqs, peakIndex: 0)
        #expect(freq == 0)
        #expect(mag == -20)
    }

    // F4b: Edge-bin (last index) falls back to raw bin values without crash.
    @Test func edgeBinLastIndex_returnsRawValues() {
        let sut = makeSUT()
        let mags: [Float] = [-50, -40, -30, -20]
        let freqs: [Float] = [0, 10, 20, 30]
        let lastIdx = mags.count - 1
        let (freq, mag) = sut.parabolicInterpolate(magnitudes: mags, frequencies: freqs, peakIndex: lastIdx)
        #expect(freq == 30)
        #expect(mag == -20)
    }

    // F5: When the three bins are colinear (denominator ≈ 0), no division by zero
    // occurs and the raw bin values are returned instead of NaN/Inf.
    @Test func flatTopDenomNearZero_noNaNorInf() {
        let sut = makeSUT()
        // lval = rval = val → denom = lval - 2*val + rval = 0
        let mags: [Float] = [-80, -80, -20, -20, -20, -80, -80]
        let freqs: [Float] = [0, 10, 20, 30, 40, 50, 60]
        let (freq, mag) = sut.parabolicInterpolate(magnitudes: mags, frequencies: freqs, peakIndex: 3)
        #expect(!freq.isNaN && !freq.isInfinite, "freq must not be NaN/Inf")
        #expect(!mag.isNaN && !mag.isInfinite, "mag must not be NaN/Inf")
    }

    // F6: Interpolated magnitude should be ≥ the peak bin value (the parabola
    // apex is always at or above the sampled bins when the peak bin is a local max).
    @Test func interpolatedMagnitude_atLeastBinValue() {
        let sut = makeSUT()
        let (mags, freqs) = makeSpectrum(peakHz: 200, peakDB: -15, halfWidth: 8)
        // Find the index of the highest bin
        guard let peakIdx = mags.enumerated().max(by: { $0.element < $1.element })?.offset else {
            return
        }
        let (_, interpMag) = sut.parabolicInterpolate(magnitudes: mags, frequencies: freqs, peakIndex: peakIdx)
        let binMag = mags[peakIdx]
        // Allow 0.5 dB tolerance for floating-point precision
        #expect(interpMag >= binMag - 0.5, "Interpolated mag \(interpMag) should be ≥ bin mag \(binMag)")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Q-Factor Calculation Tests  (F7–F9)
// ---------------------------------------------------------------------------

@Suite("QFactorCalculation")
struct QFactorTests {

    // F7: A narrow, sharp peak should yield a higher Q factor than a broad peak.
    //
    // Bin width with 2048 bins at 48kHz ≈ 11.7 Hz, so halfWidth must exceed ~12 Hz
    // for the Gaussian to resolve across multiple bins.
    // sharp: halfWidth = 20 Hz at 200 Hz → Q ≈ 200/40 ≈ 5
    // broad: halfWidth = 80 Hz at 200 Hz → Q ≈ 200/160 ≈ 1.25
    // Test: sharpQ > broadQ (relative ordering is well-defined regardless of algorithm details).
    @Test func sharpPeak_returnsHighQ() {
        let sut = makeSUT()
        let (sharpMags, sharpFreqs) = makeSpectrum(
            binCount: 2048, sampleRate: 48000,
            peakHz: 200, peakDB: -20, halfWidth: 20, noiseFloor: -100
        )
        let (broadMags, broadFreqs) = makeSpectrum(
            binCount: 2048, sampleRate: 48000,
            peakHz: 200, peakDB: -20, halfWidth: 80, noiseFloor: -100
        )
        guard let sharpIdx = sharpMags.enumerated().max(by: { $0.element < $1.element })?.offset,
              let broadIdx  = broadMags.enumerated().max(by: { $0.element < $1.element })?.offset
        else { return }
        let (sharpQ, sharpBW) = sut.calculateQFactor(
            magnitudes: sharpMags, frequencies: sharpFreqs,
            peakIndex: sharpIdx, peakMagnitude: sharpMags[sharpIdx]
        )
        let (broadQ, _) = sut.calculateQFactor(
            magnitudes: broadMags, frequencies: broadFreqs,
            peakIndex: broadIdx, peakMagnitude: broadMags[broadIdx]
        )
        #expect(sharpQ > broadQ,
                "Sharp peak (Q=\(sharpQ)) should have higher Q than broad (Q=\(broadQ))")
        #expect(sharpBW > 0, "Expected positive bandwidth, got \(sharpBW)")
        #expect(sharpQ > 0, "Q must be positive, got \(sharpQ)")
    }

    // F8: A broad peak (halfWidth = 80 Hz at 200 Hz → Q ≈ 1.25) should yield
    // Q < 10, confirming the calculator produces plausible values.
    @Test func broadPeak_returnsLowQ() {
        let sut = makeSUT()
        let (mags, freqs) = makeSpectrum(
            binCount: 2048,
            sampleRate: 48000,
            peakHz: 200,
            peakDB: -20,
            halfWidth: 80,     // 80 Hz half-width → Q ≈ 200/160 ≈ 1.25
            noiseFloor: -100
        )
        guard let peakIdx = mags.enumerated().max(by: { $0.element < $1.element })?.offset else {
            return
        }
        let (q, _) = sut.calculateQFactor(
            magnitudes: mags, frequencies: freqs, peakIndex: peakIdx, peakMagnitude: mags[peakIdx]
        )
        #expect(q > 0 && q < 15, "Expected 0 < Q < 15 for broad peak (Q ≈ 1.25), got \(q)")
    }

    // F9: When no bin ever drops 3 dB below the peak, the walk runs to both edges and the
    // bandwidth becomes the whole spectrum span. Q is then centre / span — small, but defined.
    //
    // This test was called `allBinsAboveThreshold_returnsZeroQ` until the #17 sweep and asserted
    // only that Q was neither NaN nor infinite, with a comment conceding the value was "not
    // meaningful". Q is 0.505 here, not 0: the name promised a behaviour the body never checked
    // and that does not hold. A test name is a comment, and the same rule applies to it — see
    // SLUG-SWEEP.md F14.
    @Test func noBinDropsBelowThreshold_bandwidthSpansTheSpectrum() {
        let sut = makeSUT()
        // Flat spectrum — every bin at the same level, so there is no -3 dB crossing.
        let mags = [Float](repeating: -20, count: 100)
        let freqs = (0..<100).map { Float($0) * 10 }
        let (q, bw) = sut.calculateQFactor(
            magnitudes: mags, frequencies: freqs, peakIndex: 50, peakMagnitude: -20
        )
        // The walk reaches bin 0 and bin 99, so the bandwidth is the full span: 990 - 0.
        #expect(abs(bw - 990) < 1e-3, "bandwidth should span the spectrum, got \(bw)")
        // Q = centre / span = 500 / 990.
        #expect(abs(q - 0.50505) < 1e-4, "Q should be centre/span ≈ 0.505, got \(q)")
        #expect(!q.isInfinite && !q.isNaN, "Q must not be infinite/NaN")
    }
}

// ---------------------------------------------------------------------------
// MARK: - A silent buffer reads -inf, not a finite floor
// ---------------------------------------------------------------------------

/// A bin with no energy must read `-inf`, and this edition is the reference for it.
///
/// All three convert magnitude with 20·log10, so an empty bin is -inf, and `vDSP_vdbcon` returns
/// exactly that. Python and web had each clamped the magnitude up to float64 epsilon first — the
/// SAME literal, 2.220446049250313e-16, Python's since 2026-05-09 and web's transcribed from it —
/// which put "-313.0 dB" on screen for the absence of a signal. Both carried it TWICE, on the live
/// path and the gated one.
///
/// It matters because -100 dB is a REAL reading: a live UMIK-1 in a quiet room sits near there, and
/// it is the dead-input watchdog's own threshold. A finite floor makes "no microphone at all" look
/// like "a very quiet microphone", which is the one distinction the Peak readout has to keep.
/// Owner's call during the #17 run-review, having seen -inf here and -313 on Python.
///
/// Only the GATED path is exercised. `computeFFT` — the live per-frame path — cannot be called on
/// an analyzer that was never started: it multiplies by `window`, which is empty until `start()`
/// builds it, so any call reads off the end of an empty buffer. `computeGatedFFT` creates its own
/// DFT setup and sizes from the input, so it needs no engine. The ports' live paths ARE reachable
/// and are pinned there (Python `dft_anal`, web `dftAnalRect`); this asymmetry is in the harness,
/// not the coverage of the rule.
@Suite("DSP — silence is -inf")
struct SilentBufferTests {

    @Test("the gated path returns -inf for an all-zero buffer")
    func gatedFFT_silentBuffer_isNegativeInfinity() {
        let fft = RealtimeFFTAnalyzer.forTesting()
        let (mags, _) = fft.computeGatedFFT(samples: [Float](repeating: 0, count: 4096),
                                            sampleRate: 48000)

        #expect(!mags.isEmpty, "precondition: the gated FFT produced a spectrum")
        #expect(mags.allSatisfy { $0 == -.infinity },
                "an all-zero buffer must be -inf in every bin, not a clamped floor")
    }

    @Test("a real signal is unaffected — the clamp never applied to it")
    func gatedFFT_realSignal_isFinite() {
        let fft = RealtimeFFTAnalyzer.forTesting()
        let n = 4096
        let sig = (0..<n).map { i in 0.5 * sin(2 * Float.pi * 1000 * Float(i) / 48000) }
        let (mags, _) = fft.computeGatedFFT(samples: sig, sampleRate: 48000)

        let peak = mags.max() ?? -.infinity
        #expect(peak.isFinite, "a half-scale tone must report a finite level")
        #expect(peak > -60, "expected well above -60 dB, got \(peak)")
    }

    /// Drains the main queue, where processRawSamples publishes its levels.
    private func drainMain() async {
        for _ in 0..<5 { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    /// True digital silence: the READOUT is -∞, and detection's level is unchanged at -100.
    /// -100 dB is a real level (a quiet UMIK-1 reaches it), so the material level readout must not
    /// show it for no signal at all — but detection keeps its -100, so its behaviour is unchanged.
    @Test("a silent chunk reads -∞ on the readout; detection still sees -100")
    func silentChunk_readoutIsNegativeInfinity_detectionIsMinus100() async {
        let fft = RealtimeFFTAnalyzer.forTesting()
        fft.processRawSamples([Float](repeating: 0, count: 1024))
        await drainMain()
        #expect(fft.inputLevelDB == -100, "detection's level on silence is unchanged")
        #expect(fft.readoutLevelDB == -.infinity, "the readout shows no signal as -∞")
    }

    @Test("a real chunk reads the same level on the readout and for detection")
    func realChunk_readoutEqualsDetectionLevel() async {
        let fft = RealtimeFFTAnalyzer.forTesting()
        let chunk = (0..<1024).map { i in 0.01 * sin(2 * Float.pi * 1000 * Float(i) / 48000) }
        fft.processRawSamples(chunk)
        await drainMain()
        #expect(fft.inputLevelDB.isFinite && fft.inputLevelDB > -100)
        #expect(fft.readoutLevelDB == fft.inputLevelDB)
    }
}
