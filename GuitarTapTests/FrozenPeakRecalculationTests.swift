//
//  FrozenPeakRecalculationTests.swift
//  GuitarTapTests
//
//  recalculateFrozenPeaksIfNeeded() — the single entry point that refreshes the peak display
//  after a threshold or analysis-range change. It has two branches:
//
//    loaded      — loadedMeasurementPeaks is set. The saved peaks are authoritative and are
//                  NEVER re-derived from the frozen spectrum; Peak Min only projects them.
//    live/frozen — detection re-runs over the frozen spectrum at the −100 dB floor.
//
//  Either way applyFrozenPeakState() carries per-peak state (annotation offsets, mode
//  overrides, selection) onto the new peak ids by ±5 Hz frequency proximity.
//
//  Swift is canonical here, so these tests are the reference the Python and web suites mirror.
//
//  The suite names below still carry the original PR1–PR7 grouping. That numbering collided
//  across editions and is being replaced by the flat per-behaviour ids in that document.
//
//  All tests manipulate TapToneAnalyzer state directly — no audio hardware or async dispatch.
//
// @parity test/frozen-peak-recalc

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

private func makeSUT() -> TapToneAnalyzer {
    TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
}

private func makePeak(frequency: Float, magnitude: Float = -20) -> ResonantPeak {
    ResonantPeak(frequency: frequency, magnitude: magnitude)
}

/// A per-tap entry carrying an explicit peak set and selection, for the per-tap durability tests.
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

/// Re-detect on a new spectrum, as a re-analyze would: fresh ids, same analyzer.
/// The peaks that come back are genuinely new objects, so per-peak state keyed to the old
/// ids can only survive via the production carry-forward.
@MainActor
private func remint(_ sut: TapToneAnalyzer, bumps: [(freq: Float, mag: Float)]) {
    let spectrum = gaussianSpectrum(bumps)
    sut.frozenFrequencies = spectrum.frequencies
    sut.frozenMagnitudes = spectrum.magnitudes
    sut.recalculateFrozenPeaksIfNeeded()
}

/// The peak nearest `hz` in the durable set, within `tolerance`.
@MainActor
private func peakNear(_ sut: TapToneAnalyzer, _ hz: Float, tolerance: Float = 5) -> ResonantPeak? {
    sut.allPeaks.first { abs($0.frequency - hz) <= tolerance }
}

// ---------------------------------------------------------------------------
// MARK: - PR1: isLoadingMeasurement guard
// ---------------------------------------------------------------------------

@Suite("FrozenPeakRecalculation_LoadingGuard", .serialized)
struct FrozenPeakRecalculation_LoadingGuardTests {
    // PR1: While isLoadingMeasurement is true, changing peakMinThreshold must NOT
    // overwrite peaksAbovePeakMin with a fresh findPeaks() pass.
    @Test func PR10_isLoadingMeasurement_suppressesRecalculation() {
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
    @Test func PR11_afterLoadingCompletes_recalculationRuns() {
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
    @Test func PR07_loadedPeaks_aboveThreshold_areKept() {
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
    @Test func PR08_loadedPeaks_allBelowThreshold_clearsDisplayButKeepsClassification() {
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
    @Test func PR09_loadedPeaks_material_areNeverFilteredByPeakMin() {
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
    @Test func PR06_loadedPath_usesSavedPeaks_notFrozenSpectrum() {
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
    @Test func PR13_peakMinSweep_preservesIdentitySelectionOverrideAndOffset() {
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
        sut.setModeOverride("Wolf note", for: quiet.id)
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

    // ── Per-tap entries are computed once, at capture ───────────────────────────────────────
    //
    // Nothing re-runs findPeaks over a TapEntry snapshot at the CURRENT Peak Min — not the recalc
    // branches, not loadMeasurement. Doing so would overwrite each entry's durable −100 dB set with a
    // filtered one, mint fresh UUIDs and rebuild selectedPeakIDs — and since `tapEntries` is
    // persisted, saving afterwards would truncate the saved set.

    /// The real user path: move the slider and assert the per-tap record does not budge.
    @Test func PR15_peakMinSweep_leavesTapEntriesUntouched() {
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

    /// Direct guard: the recalc itself must not touch `tapEntries`, on either branch. Load and
    /// Re-analyze call it; Peak Min does not.
    @Test func PR16_recalculateFrozenPeaks_leavesTapEntriesUntouched() {
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

    /// Re-analyze snapshots the dragged label positions and custom mode names, keyed by frequency,
    /// so it can carry them across the re-detection. That snapshot resolves its UUIDs against the
    /// durable set, not the Peak Min projection — otherwise a peak hidden by the slider would be
    /// absent, and its label position and custom name dropped and never restored.
    ///
    /// Driven on a real spectrum: the flat fixture used elsewhere makes the recalc early-return,
    /// which would make this pass without testing anything.
    @Test func PR19_reanalyzePreservesStateOfPeaksHiddenByPeakMin() {
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
        sut.setModeOverride("Wolf note", for: quiet.id)

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
    /// Resolving it over `peaksAbovePeakMin` would silently drop a selected peak — from the multi-tap
    /// averaged row on screen and in the PDF — once Peak Min rises above it.
    @Test func PR18_selectedPeaks_resolveOverDurableSet_notTheDisplayProjection() {
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

    /// PR14: the negative half of `peakMinSweep_preservesIdentitySelectionOverrideAndOffset`.
    /// A DESELECTION is a user decision too, and it must survive the sweep: a slider move must not
    /// silently re-select a deselected peak by running auto-selection again instead of honouring the
    /// edit. Going through `togglePeakSelection` is the point: it is what sets
    /// `userHasModifiedPeakSelection`.
    @Test func PR14_peakMinSweep_doesNotResurrectADeselectedPeak() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        let kept    = makePeak(frequency: 200, magnitude: -20)
        let dropped = makePeak(frequency: 300, magnitude: -25)
        freeze(sut, peaks: [kept, dropped])
        sut.peakMinThreshold = -60
        sut.selectedPeakIDs = [kept.id, dropped.id]

        sut.togglePeakSelection(dropped.id)
        #expect(!sut.selectedPeakIDs.contains(dropped.id), "precondition: just deselected")

        sut.peakMinThreshold = -30   // hides both
        sut.peakMinThreshold = -60   // and back

        #expect(!sut.selectedPeakIDs.contains(dropped.id),
                "a deselected peak must NOT re-select on a Peak Min sweep")
        #expect(sut.selectedPeakIDs.contains(kept.id),
                "the still-selected peak stays selected")
    }

    /// PR17: the third face of the per-tap durability rule. `peakMinSweep_leavesTapEntriesUntouched` and
    /// `recalculateFrozenPeaks_leavesTapEntriesUntouched` pin it against a DISPLAY recalc; this
    /// pins it against the LOAD. The saved entry carries a peak at 777 Hz, a frequency absent
    /// from its own snapshot, so re-detection could not mint it — if it comes back, it was
    /// restored. `tapEntries` is persisted, so re-deriving here would truncate the saved per-tap
    /// set permanently on the next save.
    @Test func PR17_loadMeasurement_restoresSavedTapEntryPeaks_neverReDetects() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        let undetectable = makePeak(frequency: 777, magnitude: -30)
        let entry = makeTapEntry(tapIndex: 1, peaks: [undetectable], selected: [undetectable.id])
        let measurement = TapToneMeasurement(
            peaks: [undetectable],
            spectrum: entry.snapshot,
            tapEntries: [entry]
        )

        sut.loadMeasurement(measurement)

        #expect(sut.tapEntries.count == 1, "the saved per-tap entry must be restored")
        #expect(sut.tapEntries.first?.peaks.map(\.id) == [undetectable.id],
                "per-tap peaks are restored by identity, never re-detected from the saved spectrum")
        #expect(sut.tapEntries.first?.peaks.map(\.frequency) == [777],
                "a peak absent from the snapshot proves the saved set was used")
    }

    /// PR38: a tap's modes resolve over its SELECTED peaks only. At capture a tap's selection is the
    /// strongest peak per mode, so resolving over all of its peaks gives the same answer and no other
    /// case tells the two apart. Here the selected Top is the weaker of two Top-band peaks.
    @Test func PR38_tapEntryResolvedModePeaks_resolvesOverSelectedPeaksOnly() {
        let air = makePeak(frequency: 100, magnitude: -25)
        let strongerTop = makePeak(frequency: 200, magnitude: -20)
        let selectedTop = makePeak(frequency: 220, magnitude: -30)
        let entry = makeTapEntry(tapIndex: 1, peaks: [air, strongerTop, selectedTop],
                                 selected: [air.id, selectedTop.id])

        let modes = entry.resolvedModePeaks(guitarType: .generic)

        #expect(modes[.top]?.id == selectedTop.id, "the selected Top, not the stronger unselected one")
        #expect(modes[.air]?.id == air.id)
    }

    /// PR39: a live FFT frame never overwrites a complete result — the durable peaks of a finished or
    /// loaded measurement are not replaced by live audio. The same frame DOES set the peaks while the
    /// sequence is running, so the guard is what the first expectation pins.
    @Test func PR39_liveFrame_neverOverwritesACompleteResult() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        sut.fftAnalyzer.isRunning = true
        sut.detectionState = .listening
        let result = makePeak(frequency: 777, magnitude: -30)
        sut.allPeaks = [result]
        sut.isMeasurementComplete = true
        let live = gaussianSpectrum([(200, -20)])

        sut.analyzeMagnitudes(live.magnitudes, frequencies: live.frequencies, peakMagnitude: -20)
        #expect(sut.allPeaks.map(\.id) == [result.id], "a complete result's peaks are not replaced by a live frame")

        sut.isMeasurementComplete = false
        sut.analyzeMagnitudes(live.magnitudes, frequencies: live.frequencies, peakMagnitude: -20)
        #expect(sut.allPeaks.contains { abs($0.frequency - 200) < 5 }, "while running, the frame sets the peaks")
    }

    /// PR40: a load puts the saved peaks in place — the durable set IS the file's peaks, by identity.
    @Test func PR40_loadMeasurement_setsTheSavedPeaks() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        let saved = [makePeak(frequency: 100, magnitude: -25), makePeak(frequency: 777, magnitude: -30)]
        let snap = makeTapEntry(tapIndex: 1, peaks: [], selected: []).snapshot
        sut.loadMeasurement(TapToneMeasurement(peaks: saved, spectrum: snap))

        #expect(sut.allPeaks.map(\.id) == saved.map(\.id), "the loaded peaks are the saved ones, by identity")
    }

    /// PR46: a load classifies the saved peaks under the measurement's own guitar type, not the app's.
    /// 88 Hz is Air for Generic (70–135 Hz) but outside Acoustic's Air band (90–120 Hz).
    @Test func PR46_loadMeasurement_classifiesUnderTheMeasurementsOwnType() {
        let savedType = TapDisplaySettings.measurementType
        let savedGuitar = TapDisplaySettings.guitarType
        TapDisplaySettings.measurementType = .acoustic
        TapDisplaySettings.guitarType = .acoustic
        defer { TapDisplaySettings.measurementType = savedType; TapDisplaySettings.guitarType = savedGuitar }

        let sut = makeSUT()
        let air = makePeak(frequency: 88, magnitude: -25)
        let snap = SpectrumSnapshot(frequencies: [100, 200, 300, 400], magnitudes: [-40, -20, -50, -60],
                                    minFreq: 80, maxFreq: 1200, minDB: -90, maxDB: 0, isLogarithmic: false,
                                    guitarType: .generic, measurementType: .generic)
        sut.loadMeasurement(TapToneMeasurement(peaks: [air], spectrum: snap))

        #expect(sut.peakMode(for: air) == .air, "classified under the measurement's Generic bands")
    }

    /// PR41: Re-analyze drops a loaded measurement's peaks and re-detects the frozen spectrum. The saved
    /// 777 Hz peak is absent from the spectrum, so it can only survive if the loaded peaks were kept.
    @Test func PR41_reanalyze_dropsTheLoadedPeaksAndReDetects() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        freezeOnRealSpectrum(sut, bumps: [(200, -20)])
        let saved = makePeak(frequency: 777, magnitude: -30)
        sut.allPeaks = [saved]
        sut.loadedMeasurementPeaks = [saved]

        sut.reanalyzePeaks()

        #expect(sut.loadedMeasurementPeaks == nil, "Re-analyze drops the loaded peaks")
        #expect(!sut.allPeaks.contains { $0.id == saved.id }, "the saved peak is gone")
        #expect(sut.allPeaks.contains { abs($0.frequency - 200) < 5 }, "the spectrum's peak is re-detected")
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
    @Test func PR20_loadedPath_annotationOffset_remappedByFrequency() {
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
    // Peak Min is a display filter: hiding a peak must not destroy the label the user dragged onto
    // it, or lowering the slider again returns a peak whose label has silently snapped back to the
    // default. Re-analyze reaches this code.
    @Test func PR21_loadedPath_offsetForFilteredOutPeak_survives() {
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

    /// PR22: an offset whose peak VANISHES is dropped — never re-homed onto an unrelated peak.
    ///
    /// The other half of `loadedPath_offsetForFilteredOutPeak_survives` (PR21), and a genuinely
    /// different input: there the peak is HIDDEN by Peak Min but still in the durable set, so its
    /// label position must survive; here the peak is ABSENT after a re-mint, so there is nothing
    /// for the position to belong to. They are two behaviours, not one.
    ///
    /// Asserts the map is EMPTY, not merely that the old id is missing: a negative-only assertion
    /// passes just as happily on a leak under a stale id.
    @Test func PR22_remint_offsetWithNoNearbyPeak_isDropped() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        freezeOnRealSpectrum(sut, bumps: [(freq: 200, mag: -20)])
        guard let old = peakNear(sut, 200) else {
            Issue.record("precondition: no peak detected at 200 Hz")
            return
        }
        sut.peakAnnotationOffsets = [old.id: CGPoint(x: 12, y: -8)]

        remint(sut, bumps: [(freq: 300, mag: -20)])   // far outside the ±5 Hz tolerance

        #expect(peakNear(sut, 300) != nil, "precondition: the re-mint produced a peak at 300 Hz")
        #expect(!sut.allPeaks.contains { $0.id == old.id }, "precondition: the old peak is gone")
        #expect(sut.peakAnnotationOffsets.isEmpty,
                "an orphaned offset must be dropped, not re-homed or left under a stale id")
    }
}

// ---------------------------------------------------------------------------
// MARK: - PR4: Mode override remapping by frequency proximity
// ---------------------------------------------------------------------------

@Suite("FrozenPeakRecalculation_OverrideRemapping", .serialized)
struct FrozenPeakRecalculation_OverrideRemappingTests {
    // PR4: A user-assigned mode override stored against a saved peak UUID is
    // remapped to the corresponding peak in peaksAbovePeakMin after a threshold change.
    @Test func PR23_loadedPath_modeOverride_remappedByFrequency() {
        let sut = makeSUT()
        let savedPeak = makePeak(frequency: 200, magnitude: -30)
        freeze(sut, peaks: [savedPeak])
        sut.loadedMeasurementPeaks = [savedPeak]
        sut.peakModeOverrides = [savedPeak.id: "Custom Label"]
        sut.peakMinThreshold = -80

        sut.recalculateFrozenPeaksIfNeeded()

        let newPeak = sut.peaksAbovePeakMin.first
        #expect(newPeak != nil)
        let override = sut.peakModeOverrides[newPeak!.id]
        if let label = override {
            #expect(label == "Custom Label",
                    "Mode override should be remapped to the surviving peak")
        } else {
            Issue.record("Expected the \"Custom Label\" override, got \(String(describing: override))")
        }
    }

    /// PR31: on the loaded branch the peak ids are stable, so remapping is a no-op — an override
    /// restored against a saved peak must still be keyed to THAT id afterwards.
    ///
    /// The remap exists for the re-mint case, where detection produces fresh ids and state has to be
    /// carried across by frequency. On the loaded branch `allPeaks = savedPeaks` keeps the original
    /// ids, so the same code path must leave the override exactly where it was rather than
    /// re-homing it onto a different peak.
    @Test func PR31_loadedPath_stableIDs_leaveRestoredOverridesInPlace() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        let a = makePeak(frequency: 200, magnitude: -20)
        let b = makePeak(frequency: 400, magnitude: -25)
        freeze(sut, peaks: [a, b])
        sut.loadedMeasurementPeaks = [a, b]
        sut.peakModeOverrides = [a.id: "Air", b.id: "Top"]
        sut.peakMinThreshold = -80          // nothing hidden; isolate the id question

        sut.recalculateFrozenPeaksIfNeeded()

        #expect(sut.peakModeOverrides.count == 2, "both overrides survive the loaded branch")
        if let label = sut.peakModeOverrides[a.id] {
            #expect(label == "Air", "the 200 Hz override stays on the 200 Hz peak's own id")
        } else {
            Issue.record("Expected the 200 Hz peak to keep its .assigned override under its ORIGINAL id")
        }
        if let label = sut.peakModeOverrides[b.id] {
            #expect(label == "Top", "the 400 Hz override stays on the 400 Hz peak's own id")
        } else {
            Issue.record("Expected the 400 Hz peak to keep its .assigned override under its ORIGINAL id")
        }
    }

    @Test func PR24_loadedPath_overrideForFilteredOutPeak_survives() {
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
            strongPeak.id: "Keep",
            weakPeak.id:   "Drop"
        ]
        sut.peakMinThreshold = -40   // drops weakPeak

        sut.recalculateFrozenPeaksIfNeeded()

        #expect(sut.peakModeOverrides.count == 2,
                "Both overrides survive — hiding a peak must not erase its name; got \(sut.peakModeOverrides.count)")
        if let label = sut.peakModeOverrides[weakPeak.id] {
            #expect(label == "Drop", "the hidden peak keeps its exact custom name")
        } else {
            Issue.record("Expected the hidden peak to keep its .assigned override")
        }
    }

    /// PR30: remapping with nothing to remap yields nothing. The carry-forward builds a FRESH
    /// dictionary each pass, so the failure this guards against is it inventing entries —
    /// every new peak matching a phantom, or a stale map surviving the rebuild.
    @Test func PR30_remapWithNoPriorOverrides_yieldsNoOverrides() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        freezeOnRealSpectrum(sut, bumps: [(freq: 200, mag: -20)])
        sut.peakModeOverrides = [:]

        remint(sut, bumps: [(freq: 203, mag: -20)])

        #expect(peakNear(sut, 203) != nil, "precondition: the re-mint produced a peak at 203 Hz")
        #expect(sut.peakModeOverrides.isEmpty, "no overrides in, none out")
    }

    /// PR25: an override whose peak VANISHES is orphaned — dropped, not re-homed.
    ///
    /// The other half of `loadedPath_overrideForFilteredOutPeak_survives` (PR24). There the peak is
    /// HIDDEN by Peak Min but still present, so it keeps its custom name; here it is ABSENT after a
    /// re-mint, so the name has nothing to attach to. Re-homing it would silently rename a peak the
    /// user never labelled — and that label then travels into the saved measurement.
    @Test func PR25_remint_overrideWithNoNearbyPeak_isOrphaned() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        freezeOnRealSpectrum(sut, bumps: [(freq: 200, mag: -20)])
        guard let old = peakNear(sut, 200) else {
            Issue.record("precondition: no peak detected at 200 Hz")
            return
        }
        sut.peakModeOverrides = [old.id: "Wolf note"]

        remint(sut, bumps: [(freq: 300, mag: -20)])   // far outside the ±5 Hz tolerance

        #expect(peakNear(sut, 300) != nil, "precondition: the re-mint produced a peak at 300 Hz")
        #expect(!sut.allPeaks.contains { $0.id == old.id }, "precondition: the old peak is gone")
        // Assert the LABEL is gone from the whole map — "absent from the new id" would also pass
        // on a leak under the stale id, which is the failure worth catching.
        let labels: [String] = Array(sut.peakModeOverrides.values)
        #expect(!labels.contains("Wolf note"),
                "an orphaned override must be dropped, not re-homed or left under a stale id")
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
    @Test func PR26_loadedPath_manualSelection_carriedForwardByFrequency() {
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
    @Test func PR28_loadedPath_autoSelection_reRunsWhenNotModified() {
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

    // PR27: the mirror of PR5a. When nothing lands within the ±5 Hz tolerance the selection is
    // NOT re-homed onto whatever peak happens to be nearest — a selection the user never made
    // would silently appear, and it would carry that peak's mode label with it. The frequency
    // cache still keeps the old value so lowering Peak Min can restore the real one.
    @Test func PR27_selection_isNotCarried_whenThePeakMovedFar() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        freezeOnRealSpectrum(sut, bumps: [(freq: 200, mag: -20)])
        guard let chosen = peakNear(sut, 200) else {
            Issue.record("precondition: no peak detected at 200 Hz")
            return
        }
        sut.selectedPeakIDs = [chosen.id]
        sut.userHasModifiedPeakSelection = true

        remint(sut, bumps: [(freq: 300, mag: -20)])

        guard let moved = peakNear(sut, 300) else {
            Issue.record("precondition: the re-mint produced no peak at 300 Hz")
            return
        }
        #expect(!sut.allPeaks.contains { $0.id == chosen.id },
                "precondition: the old peak is gone")
        #expect(!sut.selectedPeakIDs.contains(moved.id),
                "selection must not jump to a peak the user never chose")
        #expect(sut.selectedPeakFrequencies.contains(200),
                "the frequency cache keeps the old value, so lowering Peak Min can restore it")
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
    @Test func PR29_liveTapPath_emptyPeaks_preservesSelectedPeakIDs() {
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
    @Test func PR01_frozenSpectrum_detectsKnownPeak() {
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
    @Test func PR02_frozenSpectrum_raisedThreshold_removesWeakPeak() {
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

    // PR03: the loaded path applies Peak Min to the PROJECTION and never to the durable set.
    //
    // Asserts BOTH surfaces deliberately. This test was called
    // `loadedMeasurement_filtersAboveThresholdOnly` and checked only `peaksAbovePeakMin`, so its
    // name said "filters" while the thing it measured was the display. Read against web's PR-A3
    // ("the loaded path keeps the FULL authoritative set") it looked like a direct contradiction;
    // both were correct and the name was the whole disagreement. The durable half is the assertion
    // with teeth: assigning `allPeaks` a filtered view would shrink it as Peak Min rises, and the
    // save path writes `allPeaks` — so the shrunken set would be persisted. Silent data loss.
    @Test func PR03_loadedMeasurement_peakMinProjects_andNeverShrinksTheDurableSet() {
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

        #expect(sut.allPeaks.map(\.frequency).sorted() == [200, 400],
                "the durable set keeps every saved peak — it is what gets saved again")
        let freqs = sut.peaksAbovePeakMin.map(\.frequency)
        #expect(freqs.count == 1, "the projection shows only the above-Peak-Min peak; got \(freqs)")
        #expect(freqs.contains(where: { abs($0 - 200) < 1 }),
                "Surviving peak should be at 200 Hz; got \(freqs)")
    }

    // PR04: every loaded peak below Peak Min → the PROJECTION is empty. Named for the surface it
    // asserts; the durable set and the classification surviving that are PR08's job.
    @Test func PR04_loadedMeasurement_allBelowPeakMin_yieldsEmptyProjection() {
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
    @Test func PR05_emptyFrozenMagnitudes_yieldsNoPeaks() {
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
    @Test func PR12_liveTapPath_annotationOffset_remappedByFrequency() {
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
    @Test func PR33_liveFrozenCapture_canReanalyze() {
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
    @Test func PR34_loadedMeasurement_canReanalyze() {
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
    @Test func PR35_reanalyze_isNotAOneShot_buttonStaysAvailable() {
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
    @Test func PR36_material_canNeverReanalyze() {
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
    @Test func PR37_incompleteOrNoFrozenSpectrum_cannotReanalyze() {
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

// ---------------------------------------------------------------------------
// MARK: - PR32: a captured material peak carries ordinary peak identity
// ---------------------------------------------------------------------------

@Suite("FrozenPeakRecalculation_MaterialPeakIdentity", .serialized)
@MainActor
struct FrozenPeakRecalculation_MaterialPeakIdentityTests {
    /// PR32: a brace capture mints a real peak id, that peak reaches the set the save path
    /// persists, and its dragged label lives in the ONE annotation store — there is no separate
    /// material store.
    ///
    /// Material peaks arrive by a different route (the gated per-phase handlers, not `findPeaks`
    /// over a frozen spectrum), so the risk is that they land as second-class objects the
    /// per-peak state cannot key on, or that they never reach `guitarFullSavePeaks()` and the
    /// offset is written against an id no longer in the file.
    ///
    /// The assertion with teeth here is the SAVE side: Swift's `loadMeasurement` restores the
    /// offsets dictionary wholesale, so a reload proves less than it does in Python, whose load
    /// path rebuilds the map from `measurement.peaks`.
    @Test func PR32_capturedMaterialPeak_isSavedAndOwnsItsAnnotationOffset() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .brace
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = makeSUT()
        sut.minFrequency = 100
        sut.maxFrequency = 1200
        sut.numberOfTaps = 1

        let spectrum = gaussianSpectrum([(freq: 300, mag: -30)], from: 100, to: 1200)
        guard let dominant = sut.findDominantPeak(magnitudes: spectrum.magnitudes,
                                                  frequencies: spectrum.frequencies,
                                                  minHz: 100, maxHz: 1200,
                                                  preferLowestSignificant: false) else {
            Issue.record("precondition: the synthetic brace tap has no dominant peak")
            return
        }
        sut.materialCapturedTaps = [(magnitudes: spectrum.magnitudes,
                                     frequencies: spectrum.frequencies,
                                     captureTime: Date())]

        sut.handleLongitudinalGatedProgress(magnitudes: spectrum.magnitudes,
                                            frequencies: spectrum.frequencies,
                                            dominantPeak: dominant,
                                            minHz: 100, maxHz: 1200,
                                            preferLowest: false)

        guard let captured = sut.selectedLongitudinalPeak else {
            Issue.record("the brace capture must produce an fL peak")
            return
        }

        sut.updateAnnotationOffset(for: captured.id, offset: CGPoint(x: 12, y: -3))
        #expect(sut.peakAnnotationOffsets[captured.id] == CGPoint(x: 12, y: -3),
                "a material peak's offset lives in peakAnnotationOffsets — the same one store")

        // What the save writes for material: the identified peaks.
        let measurement = TapToneMeasurement(
            peaks: sut.materialIdentifiedPeaks,
            annotationOffsets: sut.peakAnnotationOffsets
        )
        #expect(measurement.peaks.contains { $0.id == captured.id },
                "the captured fL peak must reach the saved set, or its offset keys nothing")

        let reloaded = makeSUT()
        reloaded.loadMeasurement(measurement)
        #expect(reloaded.peakAnnotationOffsets[captured.id] == CGPoint(x: 12, y: -3),
                "the offset comes back keyed to the same material peak id")
    }

    // ── A material measurement's peaks are its identified L/C/FLC, and nothing else ──────────────

    /// Capture one material phase through the real gated handler (a synthetic tap at `hz`), on `sut`
    /// already set to a material type. Returns the identified peak.
    private func captureLongitudinal(_ sut: TapToneAnalyzer, hz: Float = 300) -> ResonantPeak? {
        sut.minFrequency = 20
        sut.maxFrequency = 1200
        sut.numberOfTaps = 1
        let spectrum = gaussianSpectrum([(freq: hz, mag: -30)], from: 20, to: 1200)
        guard let dominant = sut.findDominantPeak(magnitudes: spectrum.magnitudes,
                                                  frequencies: spectrum.frequencies,
                                                  minHz: 20, maxHz: 1200,
                                                  preferLowestSignificant: false) else { return nil }
        sut.materialCapturedTaps = [(magnitudes: spectrum.magnitudes,
                                     frequencies: spectrum.frequencies,
                                     captureTime: Date())]
        sut.handleLongitudinalGatedProgress(magnitudes: spectrum.magnitudes,
                                            frequencies: spectrum.frequencies,
                                            dominantPeak: dominant,
                                            minHz: 20, maxHz: 1200,
                                            preferLowest: false)
        return sut.selectedLongitudinalPeak
    }

    /// Capture the cross-grain phase the same way (a synthetic tap at `hz`). Returns the identified fC.
    private func captureCross(_ sut: TapToneAnalyzer, hz: Float) -> ResonantPeak? {
        let spectrum = gaussianSpectrum([(freq: hz, mag: -30)], from: 20, to: 1200)
        guard let dominant = sut.findDominantPeak(magnitudes: spectrum.magnitudes,
                                                  frequencies: spectrum.frequencies,
                                                  minHz: 20, maxHz: 1200,
                                                  preferLowestSignificant: false) else { return nil }
        sut.materialCapturedTaps = [(magnitudes: spectrum.magnitudes,
                                     frequencies: spectrum.frequencies,
                                     captureTime: Date())]
        sut.handleCrossGatedProgress(magnitudes: spectrum.magnitudes,
                                     frequencies: spectrum.frequencies,
                                     dominantPeak: dominant,
                                     minHz: 20, maxHz: 1200,
                                     preferLowest: false)
        return sut.selectedCrossPeak
    }

    /// PR42: saving a material measurement writes its identified peaks — all selected — not the
    /// guitar peak set, which is empty for material.
    @Test func PR42_materialSave_writesTheIdentifiedPeaks() throws {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .brace
        defer { TapDisplaySettings.measurementType = savedType }
        let sut = makeSUT()
        let fL = try #require(captureLongitudinal(sut), "precondition: the brace capture identifies fL")

        sut.saveMeasurement()
        let saved = try #require(sut.savedMeasurements.last)

        #expect(saved.peaks.map(\.id) == [fL.id], "the file's peaks are the identified fL")
        #expect(saved.selectedPeakIDs == [fL.id], "and it is marked selected")
    }

    /// PR43: loading a material measurement restores its identified peaks by id from the file, and
    /// leaves the guitar peak state (`allPeaks`, `selectedPeakIDs`) empty. A plate (fL + fC), so each role
    /// is restored separately.
    @Test func PR43_materialLoad_restoresTheIdentifiedPeaksOnly() throws {
        let savedType = TapDisplaySettings.measurementType
        let savedFlc = TapDisplaySettings.measureFlc
        TapDisplaySettings.measurementType = .plate
        TapDisplaySettings.measureFlc = false
        defer {
            TapDisplaySettings.measurementType = savedType
            TapDisplaySettings.measureFlc = savedFlc
        }
        let source = makeSUT()
        let fL = try #require(captureLongitudinal(source, hz: 60), "precondition: the plate capture identifies fL")
        source.acceptCurrentPhase()
        let fC = try #require(captureCross(source, hz: 150), "precondition: the plate capture identifies fC")
        source.acceptCurrentPhase() // no FLC: the measurement completes, as it must before a save
        #expect(source.isMeasurementComplete, "precondition: the plate is complete")
        // The save reads the identified peaks itself.
        source.saveMeasurement()
        let saved = try #require(source.savedMeasurements.last)

        let sut = makeSUT()
        sut.loadMeasurement(saved)

        #expect(sut.selectedLongitudinalPeak?.id == fL.id, "fL restored by id from the file")
        #expect(sut.selectedCrossPeak?.id == fC.id, "fC restored by id from the file")
        #expect(sut.allPeaks.isEmpty, "the guitar peak set stays empty for material")
        #expect(sut.selectedPeakIDs.isEmpty, "and so does the guitar selection")
    }

    /// PR44: a live FFT frame during a material sequence leaves no peaks — material has no live peaks,
    /// and any guitar peaks left from before are cleared.
    @Test func PR44_materialLiveFrame_leavesNoPeaks() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .plate
        defer { TapDisplaySettings.measurementType = savedType }
        let sut = makeSUT()
        sut.fftAnalyzer.isRunning = true
        sut.detectionState = .listening
        sut.allPeaks = [makePeak(frequency: 200, magnitude: -20)] // guitar peaks left from before
        let live = gaussianSpectrum([(200, -20)])

        sut.analyzeMagnitudes(live.magnitudes, frequencies: live.frequencies, peakMagnitude: -20)

        #expect(sut.allPeaks.isEmpty, "a material frame leaves no peaks")
    }

    /// PR45: Redo clears the redone phase's identified peak and spectrum, so the rejected fL is gone
    /// while the user re-taps.
    @Test func PR45_redo_clearsThePhasesIdentifiedPeak() throws {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .plate
        defer { TapDisplaySettings.measurementType = savedType }
        let sut = makeSUT()
        _ = try #require(captureLongitudinal(sut, hz: 60), "precondition: the plate L capture identifies fL")
        #expect(sut.materialTapPhase == .reviewingLongitudinal, "precondition: live capture stops at review")

        sut.redoCurrentPhase()

        #expect(sut.selectedLongitudinalPeak == nil, "the rejected fL is gone")
        #expect(sut.longitudinalSpectrum == nil, "and so is its spectrum")
        #expect(sut.materialIdentifiedPeaks.isEmpty)
    }
}
