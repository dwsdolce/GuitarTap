//
//  PeakFindingTests.swift
//  GuitarTapTests
//
//  Tests for findPeaks, removeDuplicatePeaks, and spectrum averaging.
//  All methods are pure data-in/data-out and require no audio hardware.
//
//  Test plan coverage: F10–F16, A1–A5
//
// @parity test/peaks

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

private func makeSUT() -> TapToneAnalyzer {
    let fft = RealtimeFFTAnalyzer()
    return TapToneAnalyzer(fftAnalyzer: fft)
}

/// Build a spectrum with a single Gaussian peak and a noise floor.
private func makeSpectrum(
    binCount: Int = 2048,
    sampleRate: Double = 48000,
    peakHz: Float,
    peakDB: Float = -20,
    halfWidthHz: Float = 5,
    noiseFloor: Float = -100
) -> (magnitudes: [Float], frequencies: [Float]) {
    let binWidth = Float(sampleRate / 2) / Float(binCount - 1)
    var magnitudes = [Float](repeating: noiseFloor, count: binCount)
    var frequencies = [Float](repeating: 0, count: binCount)
    let sigma = halfWidthHz / 2.355
    for i in 0..<binCount {
        let f = Float(i) * binWidth
        frequencies[i] = f
        let d = f - peakHz
        magnitudes[i] = max(noiseFloor, peakDB + (-d * d / (2 * sigma * sigma)))
    }
    return (magnitudes, frequencies)
}

/// Merge two spectra by taking the element-wise maximum (combines two peaks).
private func combineSpectra(_ a: ([Float], [Float]), _ b: ([Float], [Float])) -> ([Float], [Float]) {
    let mags = zip(a.0, b.0).map { max($0, $1) }
    return (mags, a.1)
}

// ---------------------------------------------------------------------------
// MARK: - Peak Finding Tests  (F10–F14)
// ---------------------------------------------------------------------------

@Suite("FindPeaks")
struct FindPeaksTests {

    // F10: A single pure tone in the upperModes range (900–2000 Hz) is detected.
    // The modeRange width (1100 Hz) covers ~94 bins at 11.7 Hz/bin, so the
    // ±5-bin local-max window can always find peaks in this range.
    @Test func singlePureTone_returnsOnePeak() throws {
        let sut = makeSUT()
        sut.peakMinThreshold = -60
        sut.minFrequency = 50
        sut.maxFrequency = 2000

        let targetHz: Float = 1000   // upperModes range (900–2000 Hz)
        let (mags, freqs) = makeSpectrum(peakHz: targetHz, peakDB: -20, halfWidthHz: 20)
        let peaks = sut.findPeaks(magnitudes: mags, frequencies: freqs)

        #expect(!peaks.isEmpty, "Should detect at least one peak")
        let closest = peaks.min(by: { abs($0.frequency - targetHz) < abs($1.frequency - targetHz) })!
        let binWidth = Float(48000 / 2) / Float(2048 - 1)
        #expect(abs(closest.frequency - targetHz) <= binWidth * 2,
                "Detected freq \(closest.frequency) should be within 2 bins of \(targetHz) Hz")
    }

    // F11: An all-silence spectrum (every bin at -100 dB, i.e. below any reasonable
    // threshold) produces no peaks.
    @Test func silenceSpectrum_returnsEmpty() {
        let sut = makeSUT()
        sut.peakMinThreshold = -80   // Threshold well above the noise floor value
        sut.minFrequency = 50
        sut.maxFrequency = 1000

        let binCount = 1024
        let mags = [Float](repeating: -100, count: binCount)
        let freqs = (0..<binCount).map { Float($0) * 23.4375 }
        let peaks = sut.findPeaks(magnitudes: mags, frequencies: freqs)
        #expect(peaks.isEmpty, "Silence spectrum should return no peaks, got \(peaks.count)")
    }

    // F12: A fully clipped spectrum (all bins at 0 dB) has no local maxima, so
    // the sliding-window maximum check finds nothing and returns empty.
    @Test func clippedSpectrum_returnsEmpty() {
        let sut = makeSUT()
        sut.peakMinThreshold = -80
        sut.minFrequency = 50
        sut.maxFrequency = 1000

        let binCount = 1024
        let mags = [Float](repeating: 0, count: binCount)
        let freqs = (0..<binCount).map { Float($0) * 23.4375 }
        let peaks = sut.findPeaks(magnitudes: mags, frequencies: freqs)
        // With all bins equal there are no strict local maxima
        #expect(peaks.isEmpty, "Clipped flat spectrum should have no local maxima")
    }

    // F13: A spectrum with three distinct peaks in wide mode ranges returns all three.
    // Uses upperModes (1000 Hz), ringMode (700 Hz), and dipole (400 Hz) — all in
    // ideal ranges with sufficient bin density for the ±5-bin window check.
    @Test func multipleTones_detectsAll() {
        let sut = makeSUT()
        sut.peakMinThreshold = -60
        sut.minFrequency = 50
        sut.maxFrequency = 2000

        // Three peaks in dipole / ringMode / upperModes ranges for acoustic guitar
        let p1 = makeSpectrum(peakHz: 400, peakDB: -20, halfWidthHz: 15)   // dipole (390–430 Hz)
        let p2 = makeSpectrum(peakHz: 700, peakDB: -22, halfWidthHz: 15)   // ringMode (680–780 Hz)
        let combined12 = combineSpectra(p1, p2)

        let p3 = makeSpectrum(peakHz: 1000, peakDB: -25, halfWidthHz: 15)  // upperModes (900–2000 Hz)
        let (mags, freqs) = combineSpectra(combined12, p3)

        let peaks = sut.findPeaks(magnitudes: mags, frequencies: freqs)
        #expect(peaks.count >= 3,
                "Expected ≥ 3 peaks for 3 distinct tones, got \(peaks.count)")

        // Each target frequency should be represented within ±2 bins (≈ 24 Hz)
        let binWidth: Float = Float(48000 / 2) / Float(2048 - 1)
        for target: Float in [400, 700, 1000] {
            let found = peaks.contains { abs($0.frequency - target) < binWidth * 2 }
            #expect(found, "No peak near \(target) Hz in detected peaks: \(peaks.map(\.frequency))")
        }
    }

    // F14: When all peaks in the spectrum are below the configured peakMinThreshold,
    // findPeaks returns empty.
    @Test func allBelowThreshold_returnsEmpty() {
        let sut = makeSUT()
        // Peak at -30 dB but threshold set above that
        sut.peakMinThreshold = -10
        sut.minFrequency = 50
        sut.maxFrequency = 500

        let (mags, freqs) = makeSpectrum(peakHz: 200, peakDB: -30, halfWidthHz: 5)
        let peaks = sut.findPeaks(magnitudes: mags, frequencies: freqs)
        #expect(peaks.isEmpty,
                "Spectrum fully below threshold should return no peaks, got \(peaks.count)")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Duplicate Removal Tests  (F15–F16)
// ---------------------------------------------------------------------------

@Suite("RemoveDuplicatePeaks")
struct RemoveDuplicatePeaksTests {

    // F15: Two peaks within the 2 Hz tolerance → only the higher-magnitude one survives.
    @Test func closePeaks_keepsHigherMagnitude() {
        let sut = makeSUT()
        let lower = ResonantPeak(frequency: 200.0, magnitude: -25)
        let higher = ResonantPeak(frequency: 200.5, magnitude: -20)  // 0.5 Hz apart
        let result = sut.removeDuplicatePeaks([lower, higher])
        #expect(result.count == 1, "Expected 1 peak after deduplication, got \(result.count)")
        #expect(result[0].magnitude == -20, "Should keep the higher-magnitude peak (-20 dB)")
    }

    // F16: Two peaks separated by more than 2 Hz tolerance → both are kept.
    @Test func wellSeparatedPeaks_keepsBoth() {
        let sut = makeSUT()
        let p1 = ResonantPeak(frequency: 200.0, magnitude: -25)
        let p2 = ResonantPeak(frequency: 205.0, magnitude: -28)  // 5 Hz apart
        let result = sut.removeDuplicatePeaks([p1, p2])
        #expect(result.count == 2, "Expected 2 peaks for well-separated peaks, got \(result.count)")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Spectrum Averaging Tests  (A1–A5)
// ---------------------------------------------------------------------------

@Suite("SpectrumAveraging")
@MainActor
struct SpectrumAveragingTests {

    // The `averageSpectra` method lives in TapToneAnalyzer+SpectrumCapture (or similar)
    // and operates on the internal type alias `(magnitudes: [Float], frequencies: [Float], captureTime: Date)`.
    // We build the inputs using the same tuple structure.

    typealias CapturedTap = (magnitudes: [Float], frequencies: [Float], captureTime: Date)

    // A1: Averaging two identical spectra returns the same spectrum.
    @Test func twoIdenticalSpectra_returnsIdentical() {
        let sut = makeSUT()
        let freqs: [Float] = [100, 200, 300]
        let mags: [Float] = [-20, -30, -40]
        let taps: [CapturedTap] = [
            (mags, freqs, Date()),
            (mags, freqs, Date())
        ]
        let (avgMags, avgFreqs) = sut.averageSpectra(from: taps)
        #expect(avgFreqs == freqs)
        for (avg, orig) in zip(avgMags, mags) {
            #expect(abs(avg - orig) < 0.01, "Average of two identical spectra should equal the original")
        }
    }

    // A2: Power-domain averaging of -10 dB and -30 dB should yield ≈ -10.4 dB,
    // not the arithmetic mean of -20 dB.
    //
    //   Power(-10 dB) = 10^(-1)  = 0.1
    //   Power(-30 dB) = 10^(-3)  = 0.001
    //   Mean power    = 0.0505
    //   dB(0.0505)    = 10·log10(0.0505) ≈ -12.97 dB
    //
    // Note: the formula uses power = 10^(dB/10) and converts back the same way.
    @Test func powerDomainAveraging_correctResult() {
        let sut = makeSUT()
        let freqs: [Float] = [200]
        let taps: [CapturedTap] = [
            ([-10], freqs, Date()),
            ([-30], freqs, Date())
        ]
        let (avgMags, _) = sut.averageSpectra(from: taps)
        #expect(avgMags.count == 1)
        let expected: Float = 10 * log10((pow(10, -10.0/10.0) + pow(10, -30.0/10.0)) / 2)
        #expect(abs(avgMags[0] - expected) < 0.1,
                "Power-domain average expected ≈\(expected) dB, got \(avgMags[0]) dB")
    }

    // A3: Averaging an empty input returns empty arrays.
    @Test func emptyInput_returnsEmpty() {
        let sut = makeSUT()
        let taps: [CapturedTap] = []
        let (avgMags, avgFreqs) = sut.averageSpectra(from: taps)
        #expect(avgMags.isEmpty)
        #expect(avgFreqs.isEmpty)
    }

    // A4: Averaging a single tap returns the same spectrum.
    @Test func singleTap_returnsItself() {
        let sut = makeSUT()
        let freqs: [Float] = [100, 200, 300, 400]
        let mags: [Float] = [-15, -25, -35, -45]
        let taps: [CapturedTap] = [(mags, freqs, Date())]
        let (avgMags, avgFreqs) = sut.averageSpectra(from: taps)
        #expect(avgFreqs == freqs)
        for (avg, orig) in zip(avgMags, mags) {
            #expect(abs(avg - orig) < 0.01)
        }
    }

}
