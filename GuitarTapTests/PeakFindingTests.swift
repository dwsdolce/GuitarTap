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
    let fft = RealtimeFFTAnalyzer.forTesting()
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

    // F17: a found peak carries its pitch — the nearest note, its cents offset and the note's exact
    // frequency are filled in when the peak is made, as `makePeak` does.
    @Test func foundPeak_carriesItsPitch() throws {
        let sut = makeSUT()
        sut.peakMinThreshold = -60
        sut.minFrequency = 50
        sut.maxFrequency = 2000

        let (mags, freqs) = makeSpectrum(peakHz: 440, peakDB: -20, halfWidthHz: 20)
        let peaks = sut.findPeaks(magnitudes: mags, frequencies: freqs)
        let a4 = try #require(peaks.min(by: { abs($0.frequency - 440) < abs($1.frequency - 440) }))

        #expect(a4.pitchNote == "A4")
        #expect(abs(a4.pitchCents ?? 99) < 5)
        #expect(abs((a4.pitchFrequency ?? 0) - 440) < 0.01)
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
    /// Two tones of UNEQUAL amplitude: a threshold between them keeps only the stronger.
    ///
    /// `multipleTones_detectsAll` uses near-equal amplitudes and one threshold, so it cannot show
    /// the threshold discriminating between peaks. Filed with detection, not recalculation, because
    /// that is what it tests.
    @Test func raisedThreshold_dropsTheWeakerOfTwoTones() {
        let sut = makeSUT()
        sut.minFrequency = 50
        sut.maxFrequency = 2000

        let strong = makeSpectrum(peakHz: 400, peakDB: -20, halfWidthHz: 15)
        let weak   = makeSpectrum(peakHz: 900, peakDB: -55, halfWidthHz: 15)
        let (mags, freqs) = combineSpectra(strong, weak)

        sut.peakMinThreshold = -60
        let low = sut.findPeaks(magnitudes: mags, frequencies: freqs)
        #expect(low.contains { abs($0.frequency - 400) < 20 }, "strong tone missing at the low threshold")
        #expect(low.contains { abs($0.frequency - 900) < 20 }, "weak tone missing at the low threshold")

        sut.peakMinThreshold = -40
        let high = sut.findPeaks(magnitudes: mags, frequencies: freqs)
        #expect(high.contains { abs($0.frequency - 400) < 20 }, "strong tone should survive the raised threshold")
        #expect(!high.contains { abs($0.frequency - 900) < 20 }, "weak tone should be dropped by the raised threshold")
    }

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

// ---------------------------------------------------------------------------
// MARK: - Duplicate-peak regression
//
// findPeaks must never return two peaks for one spectral feature. It did: the
// per-mode scan visited a bin once per overlapping mode range, minting a fresh
// UUID each time, and the final assembly reconciled two independently
// deduplicated lists **by UUID** — so the twin survived.
//
// These are authored against the UNFIXED code and are expected to fail until
// detection stops being interleaved with classification.
// ---------------------------------------------------------------------------

/// D1 — the uniqueness invariant. No two returned peaks may describe the same
/// spectral feature, i.e. sit closer together than the dedup proximity window.
private func expectNoDuplicatePeaks(
    _ peaks: [ResonantPeak],
    _ label: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for i in peaks.indices {
        for j in peaks.indices where j > i {
            let delta = abs(peaks[i].frequency - peaks[j].frequency)
            #expect(
                delta >= TapToneAnalyzer.peakProximityHz,
                """
                \(label): duplicate peaks \(delta) Hz apart \
                (\(peaks[i].frequency) Hz @ \(peaks[i].magnitude) dB and \
                \(peaks[j].frequency) Hz @ \(peaks[j].magnitude) dB). \
                findPeaks must return one peak per spectral feature.
                """,
                sourceLocation: sourceLocation
            )
        }
    }
}

@Suite("FindPeaks — duplicate regression")
struct FindPeaksDuplicateTests {

    /// Builds the minimal reproduction: a Generic-type spectrum with a strong
    /// Top peak and two weaker maxima inside the Top/Back overlap band.
    ///
    /// Generic ranges: Top 140–260 Hz, Back 180–300 Hz — overlapping at 180–260.
    /// Every duplicate observed in the field sits in that band.
    ///
    /// Resolution matters here. The suite's default 2048-bin spectrum has a
    /// ~11.7 Hz bin width, so the ±5-bin local-max window spans ±58 Hz and two
    /// peaks 7 Hz apart can never both be detected. Real captures use 32768 bins
    /// (±3.7 Hz), which is why the field data shows adjacent overlap peaks the
    /// synthetic suite could not produce — and why this defect went unseen.
    ///
    /// The weak peak must be far enough from the Back winner to survive as its own local
    /// maximum. An earlier version placed it at 232 Hz with halfWidthHz 8, where the
    /// 240 Hz peak's tail reaches −52.8 dB and buries a −56 dB peak entirely — so the
    /// spectrum only ever held TWO features, and `count == 3` passed only because the
    /// duplicate made up the number. That assertion would have masked the fix.
    private func overlapSpectrum() -> ([Float], [Float]) {
        let bins = 32768
        let top = makeSpectrum(binCount: bins, peakHz: 195, peakDB: -40, halfWidthHz: 4)   // Top winner
        let weak = makeSpectrum(binCount: bins, peakHz: 210, peakDB: -56, halfWidthHz: 4)  // overlap, loser
        let back = makeSpectrum(binCount: bins, peakHz: 240, peakDB: -50, halfWidthHz: 4)  // overlap, Back winner
        return combineSpectra(combineSpectra(top, weak), back)
    }

    private func overlapSUT() -> TapToneAnalyzer {
        TapDisplaySettings.guitarType = .generic
        let sut = makeSUT()
        sut.peakMinThreshold = -60
        sut.minFrequency = 30
        sut.maxFrequency = 2000
        return sut
    }

    // D2 — the minimal reproduction. Three spectral features must yield three
    // peaks. Under the unfixed code the Top scan and the Back scan both mint the
    // 240 Hz maximum, and step 3 reconciles by UUID, so four are returned.
    @Test func overlapZone_returnsOnePeakPerFeature() {
        let sut = overlapSUT()
        let (mags, freqs) = overlapSpectrum()

        let peaks = sut.findPeaks(magnitudes: mags, frequencies: freqs)

        expectNoDuplicatePeaks(peaks, "Top/Back overlap")
        #expect(peaks.count == 3,
                "Expected 3 peaks for 3 spectral features, got \(peaks.count): \(peaks.map(\.frequency))")
    }

    // D2b — the overlap peaks must still classify correctly once deduplicated:
    // the strongest in the overlap above the claimed Top becomes Back.
    @Test func overlapZone_classifiesTopAndBack() {
        let sut = overlapSUT()
        let (mags, freqs) = overlapSpectrum()

        let peaks = sut.findPeaks(magnitudes: mags, frequencies: freqs)
        let modeMap = GuitarMode.classifyAll(peaks)

        let topPeak = peaks.first { modeMap[$0.id]?.normalized == .top }
        let backPeak = peaks.first { modeMap[$0.id]?.normalized == .back }

        #expect(topPeak != nil, "no Top peak identified")
        #expect(backPeak != nil, "no Back peak identified")
        if let t = topPeak { #expect(abs(t.frequency - 195) < 5, "Top at \(t.frequency), expected ≈195") }
        if let b = backPeak { #expect(abs(b.frequency - 240) < 5, "Back at \(b.frequency), expected ≈240") }
    }

    // D1 applied to the existing multi-tone case — a spectrum with no overlap
    // involvement must also be duplicate-free (guards against a fix that only
    // special-cases Top/Back).
    @Test func multipleTones_containNoDuplicates() {
        let sut = makeSUT()
        sut.peakMinThreshold = -60
        sut.minFrequency = 50
        sut.maxFrequency = 2000

        let p1 = makeSpectrum(peakHz: 400, peakDB: -20, halfWidthHz: 15)
        let p2 = makeSpectrum(peakHz: 700, peakDB: -22, halfWidthHz: 15)
        let p3 = makeSpectrum(peakHz: 1000, peakDB: -25, halfWidthHz: 15)
        let (mags, freqs) = combineSpectra(combineSpectra(p1, p2), p3)

        expectNoDuplicatePeaks(sut.findPeaks(magnitudes: mags, frequencies: freqs), "three distinct tones")
    }

    // D4 — winner invariants. These pin the algorithm the user specified:
    // strongest peak per mode, Back constrained above Top, and every selected
    // peak present in the returned set.
    @Test func winnerInvariants_holdOnOverlapSpectrum() {
        let sut = overlapSUT()
        let (mags, freqs) = overlapSpectrum()

        let peaks = sut.findPeaks(magnitudes: mags, frequencies: freqs)
        let modeMap = GuitarMode.classifyAll(peaks)
        let selected = sut.guitarModeSelectedPeakIDs(from: peaks)

        // At most one peak per named mode is SELECTED.
        //
        // Note this counts *selected* peaks, not *labelled* ones. classifyAll deliberately
        // labels additional peaks: an unclaimed peak above the claimed Top and inside the
        // Back range resolves to `.back` too, so several peaks can carry the same label
        // while only one is claimed as that mode's winner. An earlier version of this test
        // asserted at most one *labelled* peak per mode, which is not an invariant of the
        // algorithm — it only appeared to hold because the overlap spectrum had a swamped
        // third peak that was never detected.
        var selectedPerMode: [GuitarMode: Int] = [:]
        for p in peaks where selected.contains(p.id) {
            guard let m = modeMap[p.id]?.normalized, m != .unknown else { continue }
            selectedPerMode[m, default: 0] += 1
        }
        for (mode, count) in selectedPerMode {
            #expect(count <= 1, "\(mode.rawValue) selected \(count) peaks; at most 1 expected")
        }

        // Back must be strictly above Top.
        let topFreq = peaks.first { modeMap[$0.id]?.normalized == .top }?.frequency
        let backFreq = peaks.first { modeMap[$0.id]?.normalized == .back }?.frequency
        if let t = topFreq, let b = backFreq {
            #expect(b > t, "Back (\(b) Hz) must be above Top (\(t) Hz)")
        }

        // Selection must be a subset of the returned peaks.
        let ids = Set(peaks.map(\.id))
        #expect(selected.isSubset(of: ids), "selectedPeakIDs contains ids absent from the peak list")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Full-set save
//
// A freshly captured guitar measurement persists every peak down to the −100 dB
// floor, not just those above the current Peak Min, so a reloaded measurement can
// reveal peaks below the capture-time Peak Min exactly as the live one can.
// ---------------------------------------------------------------------------

@Suite("Full-set save")
struct GuitarFullSavePeaksTests {

    // The real swift-mac capture: its Air resonance is at 97.26 Hz / −64.21 dB, so a Peak Min of
    // −60 reproduces the exact original defect (Air excluded from what was saved). The full set
    // must recover it. Fixture lives in the test bundle (shared with the fixture-regression tests).
    private static let stem = "dws-2024-umik-1-swift-mac-1784225155"

    private func fixtureSpectrum() throws -> (mags: [Float], freqs: [Float]) {
        let url = try #require(Bundle(for: FSAnchor.self).url(forResource: Self.stem, withExtension: "guitartap"))
        let arr = try #require(try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [[String: Any]])
        let sn = try #require(arr.first?["spectrumSnapshot"] as? [String: Any])
        func floats(_ b64: String) -> [Float] {
            Data(base64Encoded: b64)!.withUnsafeBytes { Array($0.bindMemory(to: Float32.self)) }
        }
        return (floats(sn["magnitudesData"] as! String), floats(sn["frequenciesData"] as! String))
    }

    /// Simulates what a real capture now does: detect the FULL set at the −100 dB detection floor
    /// and store it as `allPeaks`. The displayed set is then simply the Peak Min projection of it.
    ///
    /// (Before the peak-lifecycle work this seeded `allPeaks` with a Peak-Min-*filtered* detection
    /// and relied on the save path re-detecting at −100 to back-fill the remainder. Capture now
    /// always detects the full set, so that back-fill — and the throwaway UUIDs it minted — is gone.)
    private func prep() throws -> (sut: TapToneAnalyzer, displayed: [ResonantPeak]) {
        TapDisplaySettings.measurementType = .generic
        let sut = makeSUT()
        let (mags, freqs) = try fixtureSpectrum()
        sut.setFrozenSpectrum(frequencies: freqs, magnitudes: mags)
        sut.isMeasurementComplete = true
        sut.minFrequency = 30
        sut.maxFrequency = 2000
        sut.peakMinThreshold = -60   // above the real Air peak (−64.21 dB)
        sut.allPeaks = sut.findPeaks(magnitudes: mags, frequencies: freqs,
                                     peakMinOverride: TapToneAnalyzer.peakDetectionFloor)
        return (sut, sut.peaksAbovePeakMin)
    }

    private func isAir(_ p: ResonantPeak) -> Bool { abs(p.frequency - 97.26) < 1 }

    @Test func freshCaptureSavesFullSet_recoveringSubPeakMinAir() throws {
        let (sut, displayed) = try prep()
        sut.loadedMeasurementPeaks = nil
        #expect(!displayed.contains(where: isAir),
                "the real Air peak (−64.21 dB) should be excluded from the displayed set at Peak Min −60")

        let saved = sut.guitarFullSavePeaks()
        #expect(saved.contains(where: isAir), "saved full set must recover the sub-Peak-Min Air peak")
        #expect(saved.count > displayed.count, "saved full set has more peaks than the displayed set")
        #expect(displayed.allSatisfy { d in saved.contains { $0.id == d.id } },
                "displayed peaks are kept verbatim (same UUIDs)")
    }

    @Test func loadedMeasurementIsNotUpgraded() throws {
        let (sut, _) = try prep()

        // Simulate a LOADED measurement properly: loading sets the durable set to the file's peaks,
        // so `allPeaks` IS the loaded set — there is no richer set lurking behind it to "upgrade"
        // from. (Previously this only had to set `loadedMeasurementPeaks`, because the upgrade was
        // done at save time by re-detecting; capture now stores the full set up front instead.)
        let loaded = Array(sut.allPeaks.prefix(5))
        sut.allPeaks = loaded
        sut.loadedMeasurementPeaks = loaded

        let saved = sut.guitarFullSavePeaks()
        #expect(saved.count == loaded.count, "a loaded measurement is saved as-is (Re-analyze regenerates)")
        #expect(saved.allSatisfy { s in loaded.contains { $0.id == s.id } },
                "saved peaks are the loaded peaks verbatim — no re-detection, no new UUIDs")
    }
}

private final class FSAnchor {}

