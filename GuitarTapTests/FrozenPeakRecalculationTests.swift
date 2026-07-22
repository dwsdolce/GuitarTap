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
// @parity test/frozen-peak-recalc

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

/// A per-tap entry carrying an explicit peak set and selection, for the Phase 3 durability tests.
private func makeTapEntry(
    tapIndex: Int,
    peaks: [ResonantPeak],
    selected: [UUID]
) -> TapEntry {
    let snap = SpectrumSnapshot(
        frequencies: [100, 200, 300, 400],
        magnitudes:  [-40, -20, -50, -60],
        minFreq: 80, maxFreq: 1200,
        minDB: -90, maxDB: 0,
        isLogarithmic: false
    )
    return TapEntry(id: UUID(), tapIndex: tapIndex, snapshot: snap,
                    peaks: peaks, selectedPeakIDs: selected)
}

/// A synthetic spectrum with a Gaussian bump at each requested frequency, on a −100 dB floor.
///
/// The flat spectrum installed by ``freeze(_:peaks:)`` makes `findPeaks` detect nothing, so any test
/// that drives the live/frozen recalc through it passes vacuously — a trap this suite has fallen into
/// before. This fixture gives real detection something to work on.
private func gaussianSpectrum(
    _ bumps: [(freq: Float, mag: Float)],
    from lo: Float = 50,
    to hi: Float = 500,
    floor: Float = -100
) -> (frequencies: [Float], magnitudes: [Float]) {
    let sigma: Float = 3.0
    var freqs: [Float] = []
    var mags: [Float] = []
    var f = lo
    while f <= hi {
        var m = floor
        for bump in bumps {
            let d = f - bump.freq
            m = max(m, floor + (bump.mag - floor) * exp(-(d * d) / (2 * sigma * sigma)))
        }
        freqs.append(f)
        mags.append(m)
        f += 1.0
    }
    return (freqs, mags)
}

/// Freeze the SUT on a real (Gaussian) spectrum so the live/frozen recalc branch actually detects.
@MainActor
private func freezeOnRealSpectrum(_ sut: TapToneAnalyzer, bumps: [(freq: Float, mag: Float)]) {
    let spectrum = gaussianSpectrum(bumps)
    sut.minFrequency = 50
    sut.maxFrequency = 500
    sut.isMeasurementComplete = true
    sut.frozenFrequencies = spectrum.frequencies
    sut.frozenMagnitudes = spectrum.magnitudes
    sut.allPeaks = sut.findPeaks(
        magnitudes: spectrum.magnitudes,
        frequencies: spectrum.frequencies,
        peakMinOverride: TapToneAnalyzer.peakDetectionFloor
    )
}

/// Freeze the SUT with an already-computed peak set (bypasses live audio).
/// Sets isMeasurementComplete, minimal frozen data, and peaksAbovePeakMin.
private func freeze(_ sut: TapToneAnalyzer, peaks: [ResonantPeak]) {
    sut.isMeasurementComplete = true
    // Provide non-empty frozen arrays so the guard passes.
    sut.frozenFrequencies = [0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]
    sut.frozenMagnitudes  = [Float](repeating: -100, count: 11)
    sut.allPeaks = peaks
}

// ---------------------------------------------------------------------------
// MARK: - PR1: isLoadingMeasurement guard
// ---------------------------------------------------------------------------

@Suite("FrozenPeakRecalculation_LoadingGuard", .serialized)
struct FrozenPeakRecalculation_LoadingGuardTests {
    // PR1: While isLoadingMeasurement is true, changing peakMinThreshold must NOT
    // overwrite peaksAbovePeakMin with a fresh findPeaks() pass.
    @Test func isLoadingMeasurement_suppressesRecalculation() {
        let sut = makeSUT()
        let original = [makePeak(frequency: 200, magnitude: -20)]
        freeze(sut, peaks: original)
        sut.loadedMeasurementPeaks = original

        sut.isLoadingMeasurement = true
        // Directly call the method (simulating what peakMinThreshold.didSet does).
        sut.recalculateFrozenPeaksIfNeeded()

        // peaksAbovePeakMin must be unchanged — the guard returned early.
        #expect(sut.peaksAbovePeakMin.map(\.frequency) == [200],
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

        // With threshold well below -20 dB the peak survives — peaksAbovePeakMin non-empty.
        #expect(!sut.peaksAbovePeakMin.isEmpty,
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
        // Peak Min filtering is GUITAR-only, so pin the type instead of inheriting whatever a
        // previous suite left in the global (see the material counterpart below).
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        let strongPeak = makePeak(frequency: 200, magnitude: -20)
        let weakPeak   = makePeak(frequency: 400, magnitude: -60)
        freeze(sut, peaks: [strongPeak, weakPeak])
        sut.loadedMeasurementPeaks = [strongPeak, weakPeak]
        sut.peakMinThreshold = -40   // -20 dB passes, -60 dB fails

        sut.recalculateFrozenPeaksIfNeeded()

        let freqs = sut.peaksAbovePeakMin.map(\.frequency)
        #expect(freqs.contains(200),   "Strong peak should survive the threshold filter")
        #expect(!freqs.contains(400),  "Weak peak should be removed by the threshold filter")
    }

    // PR2b: When all loadedMeasurementPeaks fall below threshold the DISPLAY set empties, but the
    // measurement's own facts do not. Peak Min is a display filter: it may hide a peak, it may not
    // un-detect or un-classify one.
    //
    // Before the peak-lifecycle rework this test asserted the opposite — that identifiedModes cleared
    // too. That WAS the defect: classification followed the visible set, so sliding Peak Min above
    // every peak wiped the modes, and sliding back down reclassified from scratch. Because the Top and
    // Back bands overlap, classifyAll would then hand a Back peak the Top slot (found on reload,
    // 2026-07-21).
    @Test func loadedPeaks_allBelowThreshold_clearsDisplayButKeepsClassification() {
        // Guitar-only rule — pin the type (see loadedPeaks_aboveThreshold_areKept).
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        let peak = makePeak(frequency: 200, magnitude: -60)
        freeze(sut, peaks: [peak])
        sut.loadedMeasurementPeaks = [peak]
        sut.identifiedModes = [(peak: peak, mode: .air)]
        sut.peakMinThreshold = -10   // threshold above every peak

        sut.recalculateFrozenPeaksIfNeeded()

        #expect(sut.peaksAbovePeakMin.isEmpty,
                "peaksAbovePeakMin is the Peak Min projection — nothing here is above the threshold")
        #expect(sut.allPeaks.map(\.frequency) == [200],
                "allPeaks is the durable set — a display filter must never shrink it")
        #expect(sut.identifiedModes.map(\.mode) == [.air],
                "Classification is a fact about the measurement, not about what is on screen")
    }

    // PR2d: Peak Min is a GUITAR-only control. A loaded MATERIAL measurement's identified
    // L / C / FLC peaks ARE the result and must never be filtered out from under it.
    //
    // Regression, found 2026-07-21: a loaded plate whose fL sat at -62.41 dB with Peak Min -60
    // lost that peak from the peak table AND the chart annotations. Python shipped the defect;
    // Swift was immune only BY ACCIDENT, because a loaded material measurement leaves the frozen
    // spectrum empty and the guard returns early. This test calls freeze() deliberately, so the
    // frozen spectrum is NON-empty and the guard is bypassed — it pins the intent, not the accident.
    @Test func loadedPeaks_material_areNeverFilteredByPeakMin() {
        let savedType = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = savedType }

        for type in [MeasurementType.plate, .brace] {
            TapDisplaySettings.measurementType = type

            let sut = makeSUT()
            let fL = makePeak(frequency: 66.88,  magnitude: -62.41)  // BELOW Peak Min — the victim
            let fC = makePeak(frequency: 116.75, magnitude: -57.62)
            freeze(sut, peaks: [fL, fC])
            sut.loadedMeasurementPeaks = [fL, fC]
            sut.peakMinThreshold = -60   // would drop fL if the guitar filter applied

            sut.recalculateFrozenPeaksIfNeeded()

            let freqs = sut.peaksAbovePeakMin.map(\.frequency)
            #expect(freqs.contains(66.88),
                    "\(type.shortName): fL below Peak Min must survive — Peak Min is guitar-only")
            #expect(freqs.contains(116.75), "\(type.shortName): fC must survive")
        }
    }

    // PR2c: The loaded path uses the saved peaks — it does NOT re-run findPeaks()
    // on the frozen spectrum.  Verify by using a flat frozen spectrum (no detectable
    // peaks) while loadedMeasurementPeaks has a strong peak: peaksAbovePeakMin should
    // still show that peak.
    @Test func loadedPath_usesSavedPeaks_notFrozenSpectrum() {
        let sut = makeSUT()
        let savedPeak = makePeak(frequency: 300, magnitude: -25)
        freeze(sut, peaks: [savedPeak])
        sut.loadedMeasurementPeaks = [savedPeak]
        sut.peakMinThreshold = -80   // low enough to keep the -25 dB saved peak

        sut.recalculateFrozenPeaksIfNeeded()

        let freqs = sut.peaksAbovePeakMin.map(\.frequency)
        #expect(freqs.contains(300),
                "Loaded path must return the saved peak, not re-analyse the flat frozen spectrum")
    }
}

// ---------------------------------------------------------------------------
// MARK: - PR9: Peak Min is a DISPLAY control — per-peak state is durable
// ---------------------------------------------------------------------------

@Suite("PeakMinDurability", .serialized)
@MainActor
struct PeakMinDurabilityTests {

    /// THE point of the peak-lifecycle work. Drive the REAL user path — assigning
    /// `peakMinThreshold`, as the slider does — and sweep a peak out of view and back.
    /// Its identity, selection, mode override and dragged annotation position must all be
    /// exactly as they were.
    ///
    /// Note this deliberately does NOT call `recalculateFrozenPeaksIfNeeded()` directly: the
    /// existing PR1–PR7 tests do, which is why they kept passing while the user-visible bugs
    /// (a deselected peak re-selecting on any slider move, dragged labels snapping back) were
    /// real. Going through the property is the whole point.
    @Test func peakMinSweep_preservesIdentitySelectionOverrideAndOffset() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        let loud  = makePeak(frequency: 200, magnitude: -20)
        let quiet = makePeak(frequency: 300, magnitude: -50)   // the one we will hide
        freeze(sut, peaks: [loud, quiet])
        sut.peakMinThreshold = -60                             // both displayed

        // User state, all on the peak that is about to be hidden.
        sut.selectedPeakIDs = [quiet.id]
        sut.setModeOverride(.assigned("Wolf note"), for: quiet.id)
        sut.updateAnnotationOffset(for: quiet.id, offset: CGPoint(x: 12, y: 34))

        // Raise Peak Min above the quiet peak — it should vanish from the DISPLAY only.
        sut.peakMinThreshold = -40
        #expect(!sut.peaksAbovePeakMin.contains { $0.id == quiet.id }, "quiet peak should be hidden")
        #expect(sut.allPeaks.contains { $0.id == quiet.id },
                "…but it must remain in the durable set — hidden, not destroyed")

        // Lower it again.
        sut.peakMinThreshold = -60

        #expect(sut.peaksAbovePeakMin.contains { $0.id == quiet.id },
                "the SAME peak identity must come back, not a new one")
        #expect(sut.selectedPeakIDs.contains(quiet.id),
                "selection must survive a Peak Min sweep")
        #expect(sut.hasManualOverride(for: quiet.id),
                "custom mode label must survive a Peak Min sweep")
        #expect(sut.peakAnnotationOffsets[quiet.id] == CGPoint(x: 12, y: 34),
                "dragged annotation position must survive a Peak Min sweep")
    }

    // ── Phase 3: per-tap entries are computed once, at capture ──────────────────────────────
    //
    // `recalculateTapEntryPeaks()` used to re-run findPeaks over every TapEntry snapshot at the
    // CURRENT Peak Min, from both recalc branches and from loadMeasurement. That overwrote each
    // entry's durable −100 dB set with a filtered one, minted fresh UUIDs and rebuilt
    // selectedPeakIDs — and since `tapEntries` is persisted, saving afterwards truncated the
    // saved set. It was deleted in Phase 3; these two tests are the guard against it returning.

    /// The real user path: move the slider and assert the per-tap record does not budge.
    @Test func peakMinSweep_leavesTapEntriesUntouched() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        let loud  = makePeak(frequency: 200, magnitude: -20)
        let quiet = makePeak(frequency: 300, magnitude: -50)
        freeze(sut, peaks: [loud, quiet])
        sut.peakMinThreshold = -60

        sut.tapEntries = [makeTapEntry(tapIndex: 1, peaks: [loud, quiet], selected: [quiet.id])]
        let before = sut.tapEntries

        sut.peakMinThreshold = -40   // hides `quiet` from the DISPLAY
        sut.peakMinThreshold = -60   // and back

        #expect(sut.tapEntries.map { $0.peaks.map(\.id) } == before.map { $0.peaks.map(\.id) },
                "per-tap peak identities must not change when Peak Min moves")
        #expect(sut.tapEntries.map(\.selectedPeakIDs) == before.map(\.selectedPeakIDs),
                "per-tap selection must not be rebuilt when Peak Min moves")
        #expect(sut.tapEntries.first?.peaks.count == 2,
                "the sub-Peak-Min peak stays in the durable per-tap set — hidden, not destroyed")
    }

    /// Direct guard: the recalc itself must not touch `tapEntries`, on either branch. Peak Min
    /// no longer calls it (Phase 2), but load and Re-analyze still do.
    @Test func recalculateFrozenPeaks_leavesTapEntriesUntouched() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let loud  = makePeak(frequency: 200, magnitude: -20)
        let quiet = makePeak(frequency: 300, magnitude: -50)

        for loaded in [true, false] {   // loaded branch, then live/frozen branch
            let sut = makeSUT()
            freeze(sut, peaks: [loud, quiet])
            if loaded { sut.loadedMeasurementPeaks = [loud, quiet] }
            sut.peakMinThreshold = -40   // above `quiet`, so a re-detect would drop it
            sut.tapEntries = [makeTapEntry(tapIndex: 1, peaks: [loud, quiet], selected: [quiet.id])]
            let before = sut.tapEntries

            sut.recalculateFrozenPeaksIfNeeded()

            #expect(sut.tapEntries.map { $0.peaks.map(\.id) } == before.map { $0.peaks.map(\.id) },
                    "recalc must not re-detect per-tap peaks (loaded: \(loaded))")
            #expect(sut.tapEntries.map(\.selectedPeakIDs) == before.map(\.selectedPeakIDs),
                    "recalc must not rebuild per-tap selection (loaded: \(loaded))")
        }
    }

    /// Phase 4a. Re-analyze snapshots the dragged label positions and custom mode names, keyed by
    /// frequency, so it can carry them across the re-detection. That snapshot resolved its UUIDs
    /// against the Peak Min projection — so a peak hidden by the slider was simply absent, and its
    /// label position and custom name were dropped and never restored.
    ///
    /// Phase 2 removed the *slider* as a trigger for this code; Re-analyze still reaches it, which
    /// is where the loss actually happened. Driven on a real spectrum: the flat fixture used
    /// elsewhere makes the recalc early-return, which would make this pass without testing anything.
    @Test func reanalyzePreservesStateOfPeaksHiddenByPeakMin() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        // 200 Hz loud, 300 Hz quiet — the quiet one is what Peak Min will hide.
        freezeOnRealSpectrum(sut, bumps: [(200, -20), (300, -55)])

        let quiet = sut.allPeaks.min(by: { abs($0.frequency - 300) < abs($1.frequency - 300) })
        #expect(quiet != nil, "fixture must detect a peak near 300 Hz")
        #expect(sut.allPeaks.count >= 2, "fixture must detect both bumps, got \(sut.allPeaks.count)")
        guard let quiet else { return }

        sut.updateAnnotationOffset(for: quiet.id, offset: CGPoint(x: 21, y: 42))
        sut.setModeOverride(.assigned("Wolf note"), for: quiet.id)

        sut.peakMinThreshold = -40          // hides the quiet peak from the DISPLAY
        #expect(!sut.peaksAbovePeakMin.contains { $0.id == quiet.id },
                "precondition: the quiet peak is hidden")

        sut.reanalyzePeaks()                // re-detects; every UUID is new

        let requiz = sut.allPeaks.min(by: { abs($0.frequency - 300) < abs($1.frequency - 300) })
        #expect(requiz != nil, "the 300 Hz peak is still in the spectrum after re-analysis")
        guard let requiz else { return }

        #expect(sut.peakAnnotationOffsets[requiz.id] == CGPoint(x: 21, y: 42),
                "a dragged label on a hidden peak must survive Re-analyze")
        #expect(sut.hasManualOverride(for: requiz.id),
                "a custom mode name on a hidden peak must survive Re-analyze")
    }

    /// Selection is a fact about the measurement, so `selectedPeaks` resolves over `allPeaks`.
    /// Resolving it over `peaksAbovePeakMin` — as the multi-tap averaged row did on screen and in the
    /// PDF before Phase 3 — silently drops a selected peak once Peak Min rises above it.
    @Test func selectedPeaks_resolveOverDurableSet_notTheDisplayProjection() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        let loud  = makePeak(frequency: 200, magnitude: -20)
        let quiet = makePeak(frequency: 300, magnitude: -50)
        freeze(sut, peaks: [loud, quiet])
        sut.peakMinThreshold = -60
        sut.selectedPeakIDs = [loud.id, quiet.id]

        sut.peakMinThreshold = -40   // hides `quiet` from the display

        #expect(!sut.peaksAbovePeakMin.contains { $0.id == quiet.id },
                "precondition: the quiet peak is hidden from the display")
        let resolved: Set<UUID> = Set(sut.selectedPeaks.map(\.id))
        #expect(resolved == Set([loud.id, quiet.id]),
                "a selected peak below Peak Min is still selected — derived values must include it")
    }
}

// ---------------------------------------------------------------------------
// MARK: - PR3: Annotation offset remapping by frequency proximity
// ---------------------------------------------------------------------------

@Suite("FrozenPeakRecalculation_OffsetRemapping", .serialized)
struct FrozenPeakRecalculation_OffsetRemappingTests {
    // PR3a: When loadedMeasurementPeaks has a peak at 200 Hz with a stored
    // annotation offset, and the threshold is lowered to reveal it, the offset
    // is remapped to the new UUID of that peak in peaksAbovePeakMin.
    @Test func loadedPath_annotationOffset_remappedByFrequency() {
        let sut = makeSUT()
        let savedPeak = makePeak(frequency: 200, magnitude: -30)
        freeze(sut, peaks: [savedPeak])
        sut.loadedMeasurementPeaks = [savedPeak]
        // Store an offset against the saved peak's UUID
        sut.peakAnnotationOffsets = [savedPeak.id: CGPoint(x: 5, y: 10)]
        sut.peakMinThreshold = -80   // threshold keeps the peak

        sut.recalculateFrozenPeaksIfNeeded()

        // The saved peak IS peaksAbovePeakMin (same UUID), so the offset must still be there.
        let newPeak = sut.peaksAbovePeakMin.first
        #expect(newPeak != nil)
        let remapped = sut.peakAnnotationOffsets[newPeak!.id]
        #expect(remapped == CGPoint(x: 5, y: 10),
                "Annotation offset should be remapped to the peak at ~200 Hz, got \(String(describing: remapped))")
    }

    // PR3b: An offset for a peak hidden by Peak Min SURVIVES.
    //
    // This test asserted the opposite until Phase 4a — that the offset was dropped — and that was
    // the defect, not the spec. Peak Min is a display filter: hiding a peak must not destroy the
    // label the user dragged onto it, or lowering the slider again returns a peak whose label has
    // silently snapped back to the default. Listed in the Phase 2 plan as "asserts destruction, must
    // assert survival"; it outlived Phase 2 because that phase removed the slider as a *trigger* for
    // this code without changing the code, and Re-analyze still reaches it.
    @Test func loadedPath_offsetForFilteredOutPeak_survives() {
        // Guitar-only rule — pin the type (see loadedPeaks_aboveThreshold_areKept).
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

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

        #expect(sut.peakAnnotationOffsets.count == 2,
                "Both offsets survive — hiding a peak must not destroy its dragged label; got \(sut.peakAnnotationOffsets.count)")
        #expect(sut.peakAnnotationOffsets[weakPeak.id] == CGPoint(x: 9, y: 9),
                "the hidden peak keeps its exact offset")
    }
}

// ---------------------------------------------------------------------------
// MARK: - PR4: Mode override remapping by frequency proximity
// ---------------------------------------------------------------------------

@Suite("FrozenPeakRecalculation_OverrideRemapping", .serialized)
struct FrozenPeakRecalculation_OverrideRemappingTests {
    // PR4: A user-assigned mode override stored against a saved peak UUID is
    // remapped to the corresponding peak in peaksAbovePeakMin after a threshold change.
    @Test func loadedPath_modeOverride_remappedByFrequency() {
        let sut = makeSUT()
        let savedPeak = makePeak(frequency: 200, magnitude: -30)
        freeze(sut, peaks: [savedPeak])
        sut.loadedMeasurementPeaks = [savedPeak]
        sut.peakModeOverrides = [savedPeak.id: .assigned("Custom Label")]
        sut.peakMinThreshold = -80

        sut.recalculateFrozenPeaksIfNeeded()

        let newPeak = sut.peaksAbovePeakMin.first
        #expect(newPeak != nil)
        let override = sut.peakModeOverrides[newPeak!.id]
        if case .assigned(let label) = override {
            #expect(label == "Custom Label",
                    "Mode override should be remapped to the surviving peak")
        } else {
            Issue.record("Expected .assigned(\"Custom Label\") override, got \(String(describing: override))")
        }
    }

    // PR4b: The custom mode name on a peak hidden by Peak Min SURVIVES.
    //
    // The counterpart of PR3b, and inverted for the same reason. Naming a peak is user work; a
    // display filter must not throw it away. Doubly so after Phase 4, where a custom name is what
    // makes a peak *known* — destroying it here would silently reclassify the peak as unknown.
    @Test func loadedPath_overrideForFilteredOutPeak_survives() {
        // Guitar-only rule — pin the type (see loadedPeaks_aboveThreshold_areKept).
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

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

        #expect(sut.peakModeOverrides.count == 2,
                "Both overrides survive — hiding a peak must not erase its name; got \(sut.peakModeOverrides.count)")
        if case .assigned(let label) = sut.peakModeOverrides[weakPeak.id] {
            #expect(label == "Drop", "the hidden peak keeps its exact custom name")
        } else {
            Issue.record("Expected the hidden peak to keep its .assigned override")
        }
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
        let selectedFreqs = sut.peaksAbovePeakMin
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

        // peaksAbovePeakMin and identifiedModes should be empty…
        #expect(sut.peaksAbovePeakMin.isEmpty,
                "No peaks should be visible above the threshold")
        #expect(sut.identifiedModes.isEmpty,
                "identifiedModes should be cleared alongside peaksAbovePeakMin")
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
// calls recalculateFrozenPeaksIfNeeded(), and asserts on peaksAbovePeakMin.
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
        // Peak Min filtering is GUITAR-only — pin the type rather than inheriting whatever a
        // previous suite left in the global.
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

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

        #expect(!sut.peaksAbovePeakMin.isEmpty,
                "Frozen-spectrum path should detect the \(targetHz) Hz peak")
        let detected = sut.peaksAbovePeakMin.map(\.frequency)
        #expect(detected.contains(where: { abs($0 - targetHz) < 20 }),
                "Expected a peak near \(targetHz) Hz; got \(detected)")
    }

    // PR-A2: Raising peak_threshold removes sub-threshold peaks on recalculate.
    @Test func frozenSpectrum_raisedThreshold_removesWeakPeak() {
        // Peak Min filtering is GUITAR-only — pin the type rather than inheriting whatever a
        // previous suite left in the global.
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

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
        let detectedLow = sut.peaksAbovePeakMin.map(\.frequency)
        #expect(detectedLow.contains(where: { abs($0 - 200) < 20 }),
                "Peak should be detected at low threshold")

        // Raise threshold: weak peak should be removed.
        sut.peakMinThreshold = -40
        sut.recalculateFrozenPeaksIfNeeded()
        let detectedHigh = sut.peaksAbovePeakMin.map(\.frequency)
        #expect(!detectedHigh.contains(where: { abs($0 - 200) < 20 }),
                "Weak peak should be absent after raising threshold")
    }

    // PR-A3: Loaded-measurement path filters by threshold.
    @Test func loadedMeasurement_filtersAboveThresholdOnly() {
        // Guitar-only rule — pin the type (see loadedPeaks_aboveThreshold_areKept).
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        let above = makePeak(frequency: 200, magnitude: -25)
        let below = makePeak(frequency: 400, magnitude: -65)
        freeze(sut, peaks: [above, below])
        sut.loadedMeasurementPeaks = [above, below]
        sut.peakMinThreshold = -60

        sut.recalculateFrozenPeaksIfNeeded()

        let freqs = sut.peaksAbovePeakMin.map(\.frequency)
        #expect(freqs.count == 1, "Only the above-threshold peak should remain; got \(freqs)")
        #expect(freqs.contains(where: { abs($0 - 200) < 1 }),
                "Surviving peak should be at 200 Hz; got \(freqs)")
    }

    // PR-A4: All loaded peaks below threshold → peaksAbovePeakMin is empty.
    @Test func loadedMeasurement_allBelowThreshold_yieldsEmpty() {
        // Guitar-only rule — pin the type (see loadedPeaks_aboveThreshold_areKept).
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        let p1 = makePeak(frequency: 200, magnitude: -70)
        let p2 = makePeak(frequency: 400, magnitude: -65)
        freeze(sut, peaks: [p1, p2])
        sut.loadedMeasurementPeaks = [p1, p2]
        sut.peakMinThreshold = -60

        sut.recalculateFrozenPeaksIfNeeded()

        #expect(sut.peaksAbovePeakMin.isEmpty,
                "No peaks should remain when all are below threshold")
    }

    // PR-A5: Empty frozenMagnitudes yields no peaks and does not crash.
    @Test func emptyFrozenMagnitudes_yieldsNoPeaks() {
        // Peak Min filtering is GUITAR-only — pin the type rather than inheriting whatever a
        // previous suite left in the global.
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        sut.loadedMeasurementPeaks = nil
        sut.isMeasurementComplete = true
        sut.frozenFrequencies = []
        sut.frozenMagnitudes  = []
        sut.peakMinThreshold = -60

        // Must not crash:
        sut.recalculateFrozenPeaksIfNeeded()

        #expect(sut.peaksAbovePeakMin.isEmpty)
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

        // Seed peaksAbovePeakMin with a placeholder and store an offset against it.
        let placeholder = makePeak(frequency: peakHz, magnitude: -20)
        sut.allPeaks = [placeholder]
        let testOffset = CGPoint(x: 7, y: 13)
        sut.peakAnnotationOffsets = [placeholder.id: testOffset]

        sut.recalculateFrozenPeaksIfNeeded()

        // After recalculation, there should be a peak near 1000 Hz.
        guard let newPeak = sut.peaksAbovePeakMin.first(where: { abs($0.frequency - peakHz) < 30 }) else {
            Issue.record("Expected a peak near \(peakHz) Hz; peaksAbovePeakMin = \(sut.peaksAbovePeakMin.map(\.frequency))")
            return
        }
        // The offset should have been transferred from the old UUID to the new one.
        let remapped = sut.peakAnnotationOffsets[newPeak.id]
        #expect(remapped == testOffset,
                "Annotation offset should be remapped to the new peak UUID at ~\(peakHz) Hz, got \(String(describing: remapped))")
    }
}

// ---------------------------------------------------------------------------
// MARK: - PR8: canReanalyze — when the Re-analyze button is offered
// ---------------------------------------------------------------------------
//
// Re-analyze is a RESET, not a dirty-flag indicator: it is offered whenever it COULD do
// something, not only when we can prove it WILL.  What can leave the displayed analysis
// differing from a clean re-derivation is open-ended (peaks came from a file; mode
// assignments carried forward across Peak Min moves instead of being re-claimed; the
// analysis range moved; selections were hand-edited), and the two failure modes are not
// symmetric — a wrongly-DISABLED button is a dead end, a wrongly-ENABLED one costs a
// pointless click.  So: any complete guitar measurement with a frozen spectrum; never
// material.
//
// This replaces `loadedMeasurementPeaks != nil`, a proxy for "the peaks are stale" that was
// wrong in both directions — it disabled itself after one press, and never lit up for a live
// capture whose mode assignments had drifted.

@Suite("FrozenPeakRecalculation_CanReanalyze", .serialized)
struct FrozenPeakRecalculation_CanReanalyzeTests {

    // PR8a: a live (never-loaded) frozen capture CAN be re-analyzed. It is the only route back
    // to a clean mode classification once assignments have drifted across Peak Min moves.
    @Test func liveFrozenCapture_canReanalyze() {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        TapDisplaySettings.measurementType = .classical

        let sut = makeSUT()
        freeze(sut, peaks: [makePeak(frequency: 200)])
        sut.loadedMeasurementPeaks = nil     // never loaded — a fresh capture

        #expect(sut.canReanalyze == true,
                "A frozen guitar capture must offer Re-analyze — it can always re-claim the modes")
    }

    // PR8b: a loaded measurement can be re-analyzed (its saved peaks were never derived here).
    @Test func loadedMeasurement_canReanalyze() {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        TapDisplaySettings.measurementType = .classical

        let sut = makeSUT()
        let savedPeaks = [makePeak(frequency: 200)]
        freeze(sut, peaks: savedPeaks)
        sut.loadedMeasurementPeaks = savedPeaks

        #expect(sut.canReanalyze == true)
    }

    // PR8c: THE ONE-SHOT REGRESSION. reanalyzePeaks() clears loadedMeasurementPeaks, which used
    // to be the button's only enabling condition — so a single press disabled it forever.
    @Test func reanalyze_isNotAOneShot_buttonStaysAvailable() {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        TapDisplaySettings.measurementType = .classical

        let sut = makeSUT()
        let savedPeaks = [makePeak(frequency: 200)]
        freeze(sut, peaks: savedPeaks)
        sut.loadedMeasurementPeaks = savedPeaks
        #expect(sut.canReanalyze == true)

        sut.reanalyzePeaks()

        #expect(sut.loadedMeasurementPeaks == nil, "Re-analyze drops the saved peaks (they are now derived)")
        #expect(sut.canReanalyze == true,
                "Re-analyze must remain available after a press — it is a reset, not a one-shot")
    }

    // PR8d: material can never re-analyze. Its peaks come from the per-phase captures; running
    // findPeaks over them would destroy the saved L / C / FLC peaks. This previously held only by
    // accident (a loaded material measurement leaves the frozen spectrum empty), so pin it.
    @Test func material_canNeverReanalyze() {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }

        for type in [MeasurementType.plate, .brace] {
            TapDisplaySettings.measurementType = type
            let sut = makeSUT()
            freeze(sut, peaks: [makePeak(frequency: 200)])          // even WITH a frozen spectrum…
            sut.loadedMeasurementPeaks = [makePeak(frequency: 200)] // …and loaded peaks
            #expect(sut.canReanalyze == false,
                    "Re-analyze is meaningless for \(type.shortName) and must never be offered")
        }
    }

    // PR8e: nothing to re-analyze without a completed measurement and a frozen spectrum.
    @Test func incompleteOrNoFrozenSpectrum_cannotReanalyze() {
        let saved = TapDisplaySettings.measurementType
        defer { TapDisplaySettings.measurementType = saved }
        TapDisplaySettings.measurementType = .classical

        let noSpectrum = makeSUT()
        noSpectrum.isMeasurementComplete = true
        #expect(noSpectrum.canReanalyze == false, "No frozen spectrum — nothing to re-analyze from")

        let incomplete = makeSUT()
        freeze(incomplete, peaks: [makePeak(frequency: 200)])
        incomplete.isMeasurementComplete = false
        #expect(incomplete.canReanalyze == false, "Measurement still in progress — nothing to re-analyze")
    }
}
