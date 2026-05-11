//
//  FrozenPeakRecalculationTests.swift
//  GuitarTapTests
//
//  Tests for the recalculateFrozenPeaksIfNeeded() logic added in the
//  Peak Analysis rewrite:
//
//  PR1 — isLoadingMeasurement guard
//  PR2 — loadedMeasurementPeaks threshold-filter path
//  PR3 — frequency-proximity remapping of annotation offsets
//  PR4 — frequency-proximity remapping of mode overrides
//  PR5 — frequency-proximity selection carry-forward (manual modifications)
//  PR6 — empty-peaks guard preserves selectedPeakIDs (for re-selection when
//         threshold is later lowered)
//  PR7 — live-tap path (no loaded measurement): re-runs findPeaks and
//         remaps state by frequency proximity
//
//  All tests manipulate TapToneAnalyzer state directly — no audio hardware
//  or async dispatch is required.
//
//  Test plan coverage: PR1–PR7
//

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

private func makeSUT() -> TapToneAnalyzer {
    TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer())
}

private func makePeak(frequency: Float, magnitude: Float = -20) -> ResonantPeak {
    ResonantPeak(frequency: frequency, magnitude: magnitude)
}

/// Freeze the SUT with an already-computed peak set (bypasses live audio).
/// Sets isMeasurementComplete, minimal frozen data, and currentPeaks.
private func freeze(_ sut: TapToneAnalyzer, peaks: [ResonantPeak]) {
    sut.isMeasurementComplete = true
    // Provide non-empty frozen arrays so the guard passes.
    sut.frozenFrequencies = [0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]
    sut.frozenMagnitudes  = [Float](repeating: -100, count: 11)
    sut.currentPeaks = peaks
}

// ---------------------------------------------------------------------------
// MARK: - PR1: isLoadingMeasurement guard
// ---------------------------------------------------------------------------

@Suite("FrozenPeakRecalculation_LoadingGuard", .serialized)
struct FrozenPeakRecalculation_LoadingGuardTests {
    // PR1: While isLoadingMeasurement is true, changing peakMinThreshold must NOT
    // overwrite currentPeaks with a fresh findPeaks() pass.
    @Test func isLoadingMeasurement_suppressesRecalculation() {
        let sut = makeSUT()
        let original = [makePeak(frequency: 200, magnitude: -20)]
        freeze(sut, peaks: original)
        sut.loadedMeasurementPeaks = original

        sut.isLoadingMeasurement = true
        // Directly call the method (simulating what peakMinThreshold.didSet does).
        sut.recalculateFrozenPeaksIfNeeded()

        // currentPeaks must be unchanged — the guard returned early.
        #expect(sut.currentPeaks.map(\.frequency) == [200],
                "Loading guard should have prevented recalculation")
    }

    // PR1b: After isLoadingMeasurement returns to false, recalculation proceeds.
    @Test func afterLoadingCompletes_recalculationRuns() {
        let sut = makeSUT()
        let peak = makePeak(frequency: 200, magnitude: -20)
        freeze(sut, peaks: [peak])
        sut.loadedMeasurementPeaks = [peak]
        sut.peakMinThreshold = -100   // well below peak magnitude so it passes

        sut.isLoadingMeasurement = false
        sut.recalculateFrozenPeaksIfNeeded()

        // With threshold well below -20 dB the peak survives — currentPeaks non-empty.
        #expect(!sut.currentPeaks.isEmpty,
                "Recalculation should run and keep the peak above threshold")
    }
}

// ---------------------------------------------------------------------------
// MARK: - PR2: loadedMeasurementPeaks threshold-filter path
// ---------------------------------------------------------------------------

@Suite("FrozenPeakRecalculation_LoadedMeasurementPath", .serialized)
struct FrozenPeakRecalculation_LoadedMeasurementPathTests {
    // PR2a: Peaks in loadedMeasurementPeaks that are above peakMinThreshold are kept.
    @Test func loadedPeaks_aboveThreshold_areKept() {
        let sut = makeSUT()
        let strongPeak = makePeak(frequency: 200, magnitude: -20)
        let weakPeak   = makePeak(frequency: 400, magnitude: -60)
        freeze(sut, peaks: [strongPeak, weakPeak])
        sut.loadedMeasurementPeaks = [strongPeak, weakPeak]
        sut.peakMinThreshold = -40   // -20 dB passes, -60 dB fails

        sut.recalculateFrozenPeaksIfNeeded()

        let freqs = sut.currentPeaks.map(\.frequency)
        #expect(freqs.contains(200),   "Strong peak should survive the threshold filter")
        #expect(!freqs.contains(400),  "Weak peak should be removed by the threshold filter")
    }

    // PR2b: When all loadedMeasurementPeaks fall below threshold, currentPeaks
    // and identifiedModes are both cleared.
    @Test func loadedPeaks_allBelowThreshold_clearsBothCollections() {
        let sut = makeSUT()
        let peak = makePeak(frequency: 200, magnitude: -60)
        freeze(sut, peaks: [peak])
        sut.loadedMeasurementPeaks = [peak]
        // Pre-populate identifiedModes so we can verify it gets cleared.
        sut.identifiedModes = [(peak: peak, mode: .air)]
        sut.peakMinThreshold = -10   // threshold above every peak

        sut.recalculateFrozenPeaksIfNeeded()

        #expect(sut.currentPeaks.isEmpty,     "currentPeaks should be cleared when all peaks are below threshold")
        #expect(sut.identifiedModes.isEmpty,  "identifiedModes should be cleared when all peaks are below threshold")
    }

    // PR2c: The loaded path uses the saved peaks — it does NOT re-run findPeaks()
    // on the frozen spectrum.  Verify by using a flat frozen spectrum (no detectable
    // peaks) while loadedMeasurementPeaks has a strong peak: currentPeaks should
    // still show that peak.
    @Test func loadedPath_usesSavedPeaks_notFrozenSpectrum() {
        let sut = makeSUT()
        let savedPeak = makePeak(frequency: 300, magnitude: -25)
        freeze(sut, peaks: [savedPeak])
        sut.loadedMeasurementPeaks = [savedPeak]
        sut.peakMinThreshold = -80   // low enough to keep the -25 dB saved peak

        sut.recalculateFrozenPeaksIfNeeded()

        let freqs = sut.currentPeaks.map(\.frequency)
        #expect(freqs.contains(300),
                "Loaded path must return the saved peak, not re-analyse the flat frozen spectrum")
    }
}

// ---------------------------------------------------------------------------
// MARK: - PR3: Annotation offset remapping by frequency proximity
// ---------------------------------------------------------------------------

@Suite("FrozenPeakRecalculation_OffsetRemapping", .serialized)
struct FrozenPeakRecalculation_OffsetRemappingTests {
    // PR3a: When loadedMeasurementPeaks has a peak at 200 Hz with a stored
    // annotation offset, and the threshold is lowered to reveal it, the offset
    // is remapped to the new UUID of that peak in currentPeaks.
    @Test func loadedPath_annotationOffset_remappedByFrequency() {
        let sut = makeSUT()
        let savedPeak = makePeak(frequency: 200, magnitude: -30)
        freeze(sut, peaks: [savedPeak])
        sut.loadedMeasurementPeaks = [savedPeak]
        // Store an offset against the saved peak's UUID
        sut.peakAnnotationOffsets = [savedPeak.id: CGPoint(x: 5, y: 10)]
        sut.peakMinThreshold = -80   // threshold keeps the peak

        sut.recalculateFrozenPeaksIfNeeded()

        // The saved peak IS currentPeaks (same UUID), so the offset must still be there.
        let newPeak = sut.currentPeaks.first
        #expect(newPeak != nil)
        let remapped = sut.peakAnnotationOffsets[newPeak!.id]
        #expect(remapped == CGPoint(x: 5, y: 10),
                "Annotation offset should be remapped to the peak at ~200 Hz, got \(String(describing: remapped))")
    }

    // PR3b: An offset for a peak that disappears below the threshold is dropped.
    @Test func loadedPath_offsetForFilteredOutPeak_isDropped() {
        let sut = makeSUT()
        let strongPeak = makePeak(frequency: 200, magnitude: -20)
        let weakPeak   = makePeak(frequency: 400, magnitude: -60)
        freeze(sut, peaks: [strongPeak, weakPeak])
        sut.loadedMeasurementPeaks = [strongPeak, weakPeak]
        sut.peakAnnotationOffsets = [
            strongPeak.id: CGPoint(x: 1, y: 2),
            weakPeak.id:   CGPoint(x: 9, y: 9)
        ]
        sut.peakMinThreshold = -40   // drops weakPeak

        sut.recalculateFrozenPeaksIfNeeded()

        // Only the strong peak remains; the weak peak's offset should be gone.
        #expect(sut.peakAnnotationOffsets.count == 1,
                "Only offsets for visible peaks should survive; got \(sut.peakAnnotationOffsets.count)")
    }
}

// ---------------------------------------------------------------------------
// MARK: - PR4: Mode override remapping by frequency proximity
// ---------------------------------------------------------------------------

@Suite("FrozenPeakRecalculation_OverrideRemapping", .serialized)
struct FrozenPeakRecalculation_OverrideRemappingTests {
    // PR4: A user-assigned mode override stored against a saved peak UUID is
    // remapped to the corresponding peak in currentPeaks after a threshold change.
    @Test func loadedPath_modeOverride_remappedByFrequency() {
        let sut = makeSUT()
        let savedPeak = makePeak(frequency: 200, magnitude: -30)
        freeze(sut, peaks: [savedPeak])
        sut.loadedMeasurementPeaks = [savedPeak]
        sut.peakModeOverrides = [savedPeak.id: .assigned("Custom Label")]
        sut.peakMinThreshold = -80

        sut.recalculateFrozenPeaksIfNeeded()

        let newPeak = sut.currentPeaks.first
        #expect(newPeak != nil)
        let override = sut.peakModeOverrides[newPeak!.id]
        if case .assigned(let label) = override {
            #expect(label == "Custom Label",
                    "Mode override should be remapped to the surviving peak")
        } else {
            Issue.record("Expected .assigned(\"Custom Label\") override, got \(String(describing: override))")
        }
    }

    // PR4b: Override for a peak that drops below threshold is removed.
    @Test func loadedPath_overrideForFilteredOutPeak_isDropped() {
        let sut = makeSUT()
        let strongPeak = makePeak(frequency: 200, magnitude: -20)
        let weakPeak   = makePeak(frequency: 400, magnitude: -60)
        freeze(sut, peaks: [strongPeak, weakPeak])
        sut.loadedMeasurementPeaks = [strongPeak, weakPeak]
        sut.peakModeOverrides = [
            strongPeak.id: .assigned("Keep"),
            weakPeak.id:   .assigned("Drop")
        ]
        sut.peakMinThreshold = -40   // drops weakPeak

        sut.recalculateFrozenPeaksIfNeeded()

        #expect(sut.peakModeOverrides.count == 1,
                "Override for the filtered-out peak should be removed; got \(sut.peakModeOverrides.count) overrides")
    }
}

// ---------------------------------------------------------------------------
// MARK: - PR5: Selection carry-forward by frequency proximity (manual mode)
// ---------------------------------------------------------------------------

@Suite("FrozenPeakRecalculation_SelectionCarryForward", .serialized)
struct FrozenPeakRecalculation_SelectionCarryForwardTests {
    // PR5a: When userHasModifiedPeakSelection is true and the threshold is
    // lowered to show more peaks, the previously-selected frequencies are
    // re-selected in the new peak set by proximity (±5 Hz).
    @Test func loadedPath_manualSelection_carriedForwardByFrequency() {
        let sut = makeSUT()
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .acoustic
        defer { TapDisplaySettings.measurementType = savedType }

        let selectedPeak   = makePeak(frequency: 200, magnitude: -20)
        let unselectedPeak = makePeak(frequency: 500, magnitude: -20)

        freeze(sut, peaks: [selectedPeak, unselectedPeak])
        sut.loadedMeasurementPeaks = [selectedPeak, unselectedPeak]

        // Simulate user having selected only the 200 Hz peak.
        sut.userHasModifiedPeakSelection = true
        sut.selectedPeakIDs = [selectedPeak.id]
        sut.selectedPeakFrequencies = [200]
        sut.peakMinThreshold = -80

        sut.recalculateFrozenPeaksIfNeeded()

        // The 200 Hz peak should still be selected; 500 Hz should not.
        let selectedFreqs = sut.currentPeaks
            .filter { sut.selectedPeakIDs.contains($0.id) }
            .map(\.frequency)
        #expect(selectedFreqs.contains(200),
                "200 Hz peak should be carried forward as selected, got \(selectedFreqs)")
        #expect(!selectedFreqs.contains(500),
                "500 Hz peak should remain unselected, got \(selectedFreqs)")
    }

    // PR5b: When userHasModifiedPeakSelection is false, auto-selection is
    // re-run rather than carrying forward the previous selection.
    @Test func loadedPath_autoSelection_reRunsWhenNotModified() {
        let sut = makeSUT()
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .acoustic
        defer { TapDisplaySettings.measurementType = savedType }

        // Two peaks in the acoustic Air range; loudest should win auto-selection.
        let quietAir = makePeak(frequency: 98,  magnitude: -50)
        let loudAir  = makePeak(frequency: 105, magnitude: -25)
        freeze(sut, peaks: [quietAir, loudAir])
        sut.loadedMeasurementPeaks = [quietAir, loudAir]

        sut.userHasModifiedPeakSelection = false
        sut.peakMinThreshold = -80

        sut.recalculateFrozenPeaksIfNeeded()

        #expect(sut.selectedPeakIDs.contains(loudAir.id),
                "Auto-selection should pick the loudest Air peak")
        #expect(!sut.selectedPeakIDs.contains(quietAir.id),
                "Auto-selection should not pick the quieter Air peak")
    }
}

// ---------------------------------------------------------------------------
// MARK: - PR6: Empty-peaks guard preserves selectedPeakIDs
// ---------------------------------------------------------------------------

@Suite("FrozenPeakRecalculation_EmptyPeaksGuard", .serialized)
struct FrozenPeakRecalculation_EmptyPeaksGuardTests {
    // PR6: When all peaks fall below the threshold on the live-tap path,
    // selectedPeakIDs is intentionally preserved so the selection can be
    // remapped when the threshold is lowered again.
    //
    // This test uses the live-tap path (no loadedMeasurementPeaks), where
    // findPeaks() is re-run on the frozen spectrum.  We provide a flat frozen
    // spectrum (no detectable peaks) so findPeaks returns empty.
    @Test func liveTapPath_emptyPeaks_preservesSelectedPeakIDs() {
        let sut = makeSUT()
        // Do NOT set loadedMeasurementPeaks — this exercises the live-tap path.
        sut.loadedMeasurementPeaks = nil

        // Build a genuinely flat frozen spectrum (all bins at noise floor).
        let binCount = 512
        let binWidth = Float(24000) / Float(binCount - 1)
        sut.isMeasurementComplete = true
        sut.frozenFrequencies = (0..<binCount).map { Float($0) * binWidth }
        sut.frozenMagnitudes  = [Float](repeating: -100, count: binCount)
        sut.minFrequency = 50
        sut.maxFrequency = 2000

        // Set a threshold well above the noise floor so findPeaks returns nothing.
        sut.peakMinThreshold = -10

        // Pre-seed a selection to verify it is preserved.
        let phantomID = UUID()
        sut.selectedPeakIDs = [phantomID]

        sut.recalculateFrozenPeaksIfNeeded()

        // currentPeaks and identifiedModes should be empty…
        #expect(sut.currentPeaks.isEmpty,
                "No peaks should be visible above the threshold")
        #expect(sut.identifiedModes.isEmpty,
                "identifiedModes should be cleared alongside currentPeaks")
        // …but selectedPeakIDs must be preserved for future carry-forward.
        #expect(sut.selectedPeakIDs.contains(phantomID),
                "selectedPeakIDs should be preserved so the selection can be re-applied when the threshold is lowered")
    }
}

// ---------------------------------------------------------------------------
// MARK: - RecalculateFrozenPeaksIntegration: end-to-end entry point tests
//
// Mirrors Python TestRecalculateFrozenPeaksIfNeeded (PR-A1-A5).
// Constructs real spectra with a known peak via a Gaussian magnitude profile,
// calls recalculateFrozenPeaksIfNeeded(), and asserts on currentPeaks.
// ---------------------------------------------------------------------------

/// Build a synthetic frozen spectrum with a single Gaussian peak at `peakHz`.
/// Returns `(frequencies, magnitudes)` each with `binCount` Float elements.
private func makeGaussianSpectrum(
    peakHz: Float,
    peakDb: Float = -20,
    floorDb: Float = -100,
    sampleRate: Float = 48000,
    binCount: Int = 2048
) -> ([Float], [Float]) {
    let binWidth = sampleRate / Float(binCount * 2)
    let sigma: Float = 4.0 / 2.355   // ~4 Hz FWHM
    var freqs = [Float](repeating: 0, count: binCount)
    var mags  = [Float](repeating: floorDb, count: binCount)
    for i in 0..<binCount {
        let f = Float(i) * binWidth
        freqs[i] = f
        let d = f - peakHz
        let g = peakDb + (-d * d / (2 * sigma * sigma))
        mags[i] = max(floorDb, g)
    }
    return (freqs, mags)
}

@Suite("RecalculateFrozenPeaksIntegration", .serialized)
struct RecalculateFrozenPeaksIntegrationTests {
    // PR-A1: The frozen-spectrum path detects a known peak.
    @Test func frozenSpectrum_detectsKnownPeak() {
        let sut = makeSUT()
        sut.loadedMeasurementPeaks = nil
        sut.minFrequency = 80
        sut.maxFrequency = 1200
        sut.peakMinThreshold = -60

        let targetHz: Float = 200
        let (freqs, mags) = makeGaussianSpectrum(peakHz: targetHz, peakDb: -20)
        sut.isMeasurementComplete = true
        sut.frozenFrequencies = freqs
        sut.frozenMagnitudes  = mags

        sut.recalculateFrozenPeaksIfNeeded()

        #expect(!sut.currentPeaks.isEmpty,
                "Frozen-spectrum path should detect the \(targetHz) Hz peak")
        let detected = sut.currentPeaks.map(\.frequency)
        #expect(detected.contains(where: { abs($0 - targetHz) < 20 }),
                "Expected a peak near \(targetHz) Hz; got \(detected)")
    }

    // PR-A2: Raising peak_threshold removes sub-threshold peaks on recalculate.
    @Test func frozenSpectrum_raisedThreshold_removesWeakPeak() {
        let sut = makeSUT()
        sut.loadedMeasurementPeaks = nil
        sut.minFrequency = 80
        sut.maxFrequency = 1200

        let (freqs, mags) = makeGaussianSpectrum(peakHz: 200, peakDb: -50, floorDb: -100)
        sut.isMeasurementComplete = true
        sut.frozenFrequencies = freqs
        sut.frozenMagnitudes  = mags

        // Low threshold: peak should be detected.
        sut.peakMinThreshold = -60
        sut.recalculateFrozenPeaksIfNeeded()
        let detectedLow = sut.currentPeaks.map(\.frequency)
        #expect(detectedLow.contains(where: { abs($0 - 200) < 20 }),
                "Peak should be detected at low threshold")

        // Raise threshold: weak peak should be removed.
        sut.peakMinThreshold = -40
        sut.recalculateFrozenPeaksIfNeeded()
        let detectedHigh = sut.currentPeaks.map(\.frequency)
        #expect(!detectedHigh.contains(where: { abs($0 - 200) < 20 }),
                "Weak peak should be absent after raising threshold")
    }

    // PR-A3: Loaded-measurement path filters by threshold.
    @Test func loadedMeasurement_filtersAboveThresholdOnly() {
        let sut = makeSUT()
        let above = makePeak(frequency: 200, magnitude: -25)
        let below = makePeak(frequency: 400, magnitude: -65)
        freeze(sut, peaks: [above, below])
        sut.loadedMeasurementPeaks = [above, below]
        sut.peakMinThreshold = -60

        sut.recalculateFrozenPeaksIfNeeded()

        let freqs = sut.currentPeaks.map(\.frequency)
        #expect(freqs.count == 1, "Only the above-threshold peak should remain; got \(freqs)")
        #expect(freqs.contains(where: { abs($0 - 200) < 1 }),
                "Surviving peak should be at 200 Hz; got \(freqs)")
    }

    // PR-A4: All loaded peaks below threshold → currentPeaks is empty.
    @Test func loadedMeasurement_allBelowThreshold_yieldsEmpty() {
        let sut = makeSUT()
        let p1 = makePeak(frequency: 200, magnitude: -70)
        let p2 = makePeak(frequency: 400, magnitude: -65)
        freeze(sut, peaks: [p1, p2])
        sut.loadedMeasurementPeaks = [p1, p2]
        sut.peakMinThreshold = -60

        sut.recalculateFrozenPeaksIfNeeded()

        #expect(sut.currentPeaks.isEmpty,
                "No peaks should remain when all are below threshold")
    }

    // PR-A5: Empty frozenMagnitudes yields no peaks and does not crash.
    @Test func emptyFrozenMagnitudes_yieldsNoPeaks() {
        let sut = makeSUT()
        sut.loadedMeasurementPeaks = nil
        sut.isMeasurementComplete = true
        sut.frozenFrequencies = []
        sut.frozenMagnitudes  = []
        sut.peakMinThreshold = -60

        // Must not crash:
        sut.recalculateFrozenPeaksIfNeeded()

        #expect(sut.currentPeaks.isEmpty)
    }
}

// ---------------------------------------------------------------------------
// MARK: - PR7: Live-tap path remaps offsets and overrides by frequency
// ---------------------------------------------------------------------------

@Suite("FrozenPeakRecalculation_LiveTapPath", .serialized)
struct FrozenPeakRecalculation_LiveTapPathTests {
    // PR7: On the live-tap path (no loadedMeasurementPeaks), annotation offsets
    // stored for the previous UUIDs are remapped by frequency proximity to the
    // new UUIDs produced by a fresh findPeaks() pass.
    //
    // Strategy: freeze a spectrum with a single clean Gaussian peak at 1000 Hz,
    // seed an annotation offset for the current peak's UUID, then call
    // recalculateFrozenPeaksIfNeeded().  The new peak found by findPeaks() will
    // be at ~1000 Hz with a NEW UUID; the offset should transfer to it.
    @Test func liveTapPath_annotationOffset_remappedByFrequency() {
        let sut = makeSUT()
        sut.loadedMeasurementPeaks = nil
        sut.minFrequency = 50
        sut.maxFrequency = 2000
        sut.peakMinThreshold = -60

        // Build a frozen spectrum with a single peak near 1000 Hz (upperModes range).
        let binCount  = 2048
        let binWidth  = Float(24000) / Float(binCount - 1)
        let peakHz: Float = 1000
        let sigma: Float  = 5 / 2.355
        var mags  = [Float](repeating: -100, count: binCount)
        var freqs = [Float](repeating: 0,    count: binCount)
        for i in 0..<binCount {
            let f = Float(i) * binWidth
            freqs[i] = f
            let d = f - peakHz
            mags[i] = max(-100, -20 + (-d * d / (2 * sigma * sigma)))
        }
        sut.isMeasurementComplete = true
        sut.frozenFrequencies = freqs
        sut.frozenMagnitudes  = mags

        // Seed currentPeaks with a placeholder and store an offset against it.
        let placeholder = makePeak(frequency: peakHz, magnitude: -20)
        sut.currentPeaks = [placeholder]
        let testOffset = CGPoint(x: 7, y: 13)
        sut.peakAnnotationOffsets = [placeholder.id: testOffset]

        sut.recalculateFrozenPeaksIfNeeded()

        // After recalculation, there should be a peak near 1000 Hz.
        guard let newPeak = sut.currentPeaks.first(where: { abs($0.frequency - peakHz) < 30 }) else {
            Issue.record("Expected a peak near \(peakHz) Hz; currentPeaks = \(sut.currentPeaks.map(\.frequency))")
            return
        }
        // The offset should have been transferred from the old UUID to the new one.
        let remapped = sut.peakAnnotationOffsets[newPeak.id]
        #expect(remapped == testOffset,
                "Annotation offset should be remapped to the new peak UUID at ~\(peakHz) Hz, got \(String(describing: remapped))")
    }
}
