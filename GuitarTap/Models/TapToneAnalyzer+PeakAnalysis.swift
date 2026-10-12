//
//  TapToneAnalyzer+PeakAnalysis.swift
//  GuitarTap
//
//  Created on 1/25/26.
//
// @parity dsp/peak-analysis tests=test/frozen-peak-recalc,test/dsp,test/peaks
/// # TapToneAnalyzer+PeakAnalysis
///
/// Core DSP methods for detecting, refining, and classifying spectral peaks.
///
/// ## Analysis Pipeline
/// Each time `RealtimeFFTAnalyzer` delivers a new magnitude spectrum, the
/// main entry point ``analyzeMagnitudes(_:frequencies:peakMagnitude:)`` runs
/// the following sequence:
///
/// 1. **Tap detection** — for guitar mode only; plate/brace use the fast input
///    level path in `TapToneAnalyzer+TapDetection` to avoid the ~15 dB
///    transient-energy loss in the long-window continuous FFT.
/// 2. **Peak finding** — ``findPeaks(magnitudes:frequencies:minHz:maxHz:)``
///    first guarantees a slot for the strongest peak in each known guitar mode
///    range, then fills remaining slots by magnitude.
/// 3. **Mode classification** — the peaks are mapped to ``GuitarMode``s together by
///    ``GuitarMode/classifyAll(_:guitarType:)``.
///
/// ## Parabolic Interpolation
/// All peak frequencies and magnitudes are refined with sub-bin accuracy using
/// the formula (δ ∈ (−0.5, 0.5)):
///
/// ```
/// δ = 0.5 · (α − γ) / (α − 2β + γ)
/// f_true ≈ f_bin + δ · Δf
/// A_true ≈ β − 0.25 · (α − γ) · δ
/// ```
/// where `α`, `β`, `γ` are the dB magnitudes of the left, centre, and right
/// bins respectively and `Δf` is the bin width in Hz.
///
/// ## Q Factor
/// Q is measured via the −3 dB bandwidth method:
/// ```
/// Q = f_centre / (f_upper − f_lower)
/// ```
/// where `f_upper` and `f_lower` are the frequencies at which the spectrum
/// first crosses the `peakMagnitude − 3 dB` threshold on either side of
/// the peak bin.

import SwiftUI
import Combine

extension TapToneAnalyzer {

    // MARK: - Analysis Methods

    /// Live peaks from one FFT frame (via ``onFftFrame(magnitudes:frequencies:peakMagnitude:)``).
    ///
    /// While a guitar sequence runs (detecting, paused, or a capture window filling) and is not
    /// complete, finds the peaks at the Peak Min threshold, selects them all, and classifies them.
    /// A material sequence has no live peaks. Tap detection and decay tracking run on the RMS-level
    /// path (+TapDetection.swift), not here.
    ///
    /// - Parameters:
    ///   - magnitudes: The current magnitude spectrum in dBFS, one value per
    ///     FFT bin.
    ///   - frequencies: The frequency axis matching `magnitudes`, in Hz.
    ///   - peakMagnitude: The maximum bin magnitude in dBFS.
    ///
    /// - Note: Must be called on the main thread; `fftAnalyzer` publishes on
    ///   the main queue via a Combine `.receive(on: RunLoop.main)` subscription.
    func analyzeMagnitudes(_ magnitudes: [Float], frequencies: [Float], peakMagnitude: Float) {
        // Don't analyze anything if the FFT analyzer isn't actually running
        guard fftAnalyzer.isRunning else {
            // Reset tap detection state to prevent false positives before start
            return
        }
        
        // Analyze peaks if detection is enabled, paused (spectrum stays live), or in capture window.
        // Do not overwrite the peaks once a measurement is complete. Tap detection itself runs on the
        // fast inputLevelDB path (onRmsLevelChanged in +TapDetection.swift), not here.
        if (isDetecting || isDetectionPaused || captureTimer != nil) && !isMeasurementComplete {
            // Material (plate/brace) has no live peaks: its peaks are the identified L/C/FLC
            // (`materialIdentifiedPeaks`), and `allPeaks` is guitar-only.
            guard TapDisplaySettings.measurementType.isGuitar else {
                if !allPeaks.isEmpty {
                    allPeaks = []
                    identifiedModes = []
                }
                return
            }
            // Find peaks in spectrum
            let peaks = findPeaks(magnitudes: magnitudes, frequencies: frequencies)
            allPeaks = peaks
            // Auto-select all newly detected peaks so visibility mode "selected" shows everything by default.
            selectedPeakIDs = Set(peaks.map { $0.id })

            // Classify modes using context-aware algorithm so overlapping ranges resolve correctly
            let modeMap = GuitarMode.classifyAll(peaks)
            identifiedModes = peaks.map { (peak: $0, mode: modeMap[$0.id] ?? .unknown) }
            
        }
        
    }

    /// Re-runs peak finding on the frozen spectrum.
    ///
    /// Reached only through ``reanalyzePeaks()`` (Peak Min is a display projection and does not
    /// re-detect). Has no effect when the spectrum is not frozen or when frozen data is unavailable.
    ///
    /// **Selection strategy (guitar mode):**
    /// - If the user has not manually touched selections since the last freeze
    ///   (`userHasModifiedPeakSelection == false`), auto-selection is re-run from
    ///   scratch via ``guitarModeSelectedPeakIDs(from:)``.
    /// - If the user has made manual changes, selections are carried forward by
    ///   frequency proximity (±5 Hz): previously-selected peaks that still exist in
    ///   the new peak set are kept selected; previously-deselected peaks that still
    ///   exist remain deselected; peaks that disappeared below the new threshold are
    ///   simply dropped.
    func recalculateFrozenPeaksIfNeeded() {
        // Skip during loadMeasurement: saved peaks are already correct, and the
        // guitar type stored in TapDisplaySettings may not match the measurement
        // yet (it's applied asynchronously via the view's onReceive handler).
        // Also handle loaded measurements specially: the saved peaks are the
        // authoritative analysis results and may not be reproducible by re-running
        // findPeaks on the frozen spectrum (which is only stored for display).
        // When loadedMeasurementPeaks is set, filter those peaks by the current
        // threshold instead of re-analyzing the spectrum.
        guard !isLoadingMeasurement else { return }
        guard isMeasurementComplete,
              !frozenFrequencies.isEmpty,
              !frozenMagnitudes.isEmpty else { return }

        let isGuitar = TapDisplaySettings.measurementType.isGuitar
        let tolerance: Float = 5.0

        // --- Snapshot all frequency-keyed state BEFORE findPeaks() replaces UUIDs ---

        // Selected peak frequencies: use the stable cache (survives empty-peak passes).
        // Fall back to deriving from loadedMeasurementPeaks on the very first pass
        // after load (before selectedPeakFrequencies has been populated).
        let previouslySelectedFrequencies: [Float]
        if isGuitar && userHasModifiedPeakSelection {
            if !selectedPeakFrequencies.isEmpty {
                previouslySelectedFrequencies = selectedPeakFrequencies
            } else if let ref = loadedMeasurementPeaks {
                previouslySelectedFrequencies = ref.filter { selectedPeakIDs.contains($0.id) }.map { $0.frequency }
            } else {
                previouslySelectedFrequencies = selectedPeaks.map { $0.frequency }
            }
        } else {
            previouslySelectedFrequencies = []
        }

        // Annotation offsets and mode overrides are keyed by frequency so they can be carried across
        // a re-detection. Resolve the UUIDs against `allPeaks`, NOT the Peak Min projection: a peak
        // hidden by the slider still owns its dragged label and its custom name, and looking it up in
        // the displayed set would silently drop both — permanently, since this snapshot is what the
        // carry-forward restores from. Re-analyze reaches this code; Peak Min does not.
        let offsetsByFrequency: [(frequency: Float, offset: CGPoint)] = peakAnnotationOffsets.compactMap { uuid, offset in
            guard let peak = allPeaks.first(where: { $0.id == uuid }) else { return nil }
            return (peak.frequency, offset)
        }

        let overridesByFrequency: [(frequency: Float, override: String)] = peakModeOverrides.compactMap { uuid, mode in
            guard let peak = allPeaks.first(where: { $0.id == uuid }) else { return nil }
            return (peak.frequency, mode)
        }

        // --- Loaded-measurement path ---
        // When peaks come from a loaded file, the saved peaks are the authoritative
        // analysis record and may not be reproducible by re-running findPeaks on the
        // frozen spectrum (spectrum averaging, FFT windowing, and analysis settings can
        // all differ between sessions). Filter the saved peaks by threshold instead.
        //
        // **Guitar only.** Peak Min is a guitar-mode control: plate/brace capture uses its own
        // adaptive per-phase noise floor, and the identified L / C / FLC peaks ARE the material
        // result — they must never be filtered out from under it. A loaded plate whose fL sits
        // below the saved Peak Min (e.g. fL at -62.4 dB with Peak Min -60) would otherwise lose
        // that peak from both the peak table and the chart annotations.
        //
        // We are immune here today only by ACCIDENT: the guard above requires a non-empty frozen
        // spectrum, and loading a material measurement leaves it empty (MeasurementManagement
        // `setFrozenSpectrum([], [])`), so this branch is never reached for material. Anything
        // that later gives a loaded material measurement a frozen spectrum would re-arm the bug.
        // State the intent instead of relying on that. Python mirrors this guard in
        // `_emit_loaded_peaks_at_threshold`, where the same defect DID reach the user.
        if let savedPeaks = loadedMeasurementPeaks {
            // `allPeaks` is the DURABLE set and must never be assigned a filtered view — doing so
            // would shrink it as Peak Min rises, and the save path would then write the shrunken
            // set (silent data loss). Store the saved peaks whole; `peaksAbovePeakMin` is the Peak Min
            // projection of them. The legacy remapping below still operates on the *displayed*
            // set, exactly as it did before, so behaviour here is unchanged.
            allPeaks = savedPeaks
            // Classification and selection work on the DURABLE set — never the displayed one, or
            // raising Peak Min above every peak would leave nothing to select or classify.
            let peaks = allPeaks

            guard !peaks.isEmpty else {
                identifiedModes = []
                return
            }

            // Restore mode assignments from identifiedModes cache, or reclassify.
            var modesByFrequency: [(frequency: Float, mode: GuitarMode)] = identifiedModes.map {
                ($0.peak.frequency, $0.mode)
            }
            if modesByFrequency.isEmpty {
                let seedMap = GuitarMode.classifyAll(savedPeaks)
                modesByFrequency = savedPeaks.map { ($0.frequency, seedMap[$0.id] ?? .unknown) }
            }
            applyFrozenPeakState(
                peaks: peaks,
                modesByFrequency: modesByFrequency,
                offsetsByFrequency: offsetsByFrequency,
                overridesByFrequency: overridesByFrequency,
                previouslySelectedFrequencies: previouslySelectedFrequencies,
                isGuitar: isGuitar,
                tolerance: tolerance
            )
            return
        }

        // --- Live-tap path (no loaded measurement) ---
        // Mode assignments keyed by frequency. Stable across slider moves; cleared only
        // when peaks go to zero (identifiedModes = []).
        let modesByFrequency: [(frequency: Float, mode: GuitarMode)] = identifiedModes.map {
            ($0.peak.frequency, $0.mode)
        }

        // Detect the FULL set (floor -100) and store it as the durable `allPeaks`; `peaksAbovePeakMin`
        // is its Peak Min projection. Only Re-analyze reaches this re-detection — a display change
        // must not re-analyse.
        allPeaks = findPeaks(magnitudes: frozenMagnitudes, frequencies: frozenFrequencies,
                             peakMinOverride: TapToneAnalyzer.peakDetectionFloor)
        let peaks = allPeaks

        // Nothing detected at all (not merely nothing above Peak Min — that is a display matter).
        guard !peaks.isEmpty else {
            identifiedModes = []
            return
        }

        applyFrozenPeakState(
            peaks: peaks,
            modesByFrequency: modesByFrequency,
            offsetsByFrequency: offsetsByFrequency,
            overridesByFrequency: overridesByFrequency,
            previouslySelectedFrequencies: previouslySelectedFrequencies,
            isGuitar: isGuitar,
            tolerance: tolerance
        )

        // Per-tap entries are deliberately NOT recomputed here. Each `TapEntry` is detected once,
        // at capture, over the full −100 dB set (`+SpectrumCapture.swift` processMultipleTaps) and is
        // then durable: Peak Min is a display control and must not re-detect, re-identify or
        // re-select a tap's peaks. Re-running findPeaks here at the *current* threshold would
        // overwrite each entry's full set with a filtered one, mint fresh UUIDs and rebuild
        // selectedPeakIDs — and because `tapEntries` is persisted, lose saved data silently.
    }

    /// Applies a guitar-subtype change (e.g. Classical → Flamenco) as a **clean slate** for the new
    /// type.
    ///
    /// The guitar type changes what "Top" *means* (the mode bands), so classification and selection
    /// are re-derived for the new type, and manual mode labels — made against the OLD bands' meaning —
    /// are cleared. Peak identities and dragged-label positions are untouched (this does not
    /// re-detect; `reclassifyPeaks` only recomputes modes). Contract: *"Changing the guitar type
    /// re-analyses every peak for the new type; manual labels and selections are cleared."*
    ///
    /// This is deliberately NOT the wand (`resetToAutoSelection`), which preserves the labels — the
    /// wand is the user's "clear my selection, give me pure auto" action and must stay reachable.
    func reclassifyForGuitarTypeChange() {
        peakModeOverrides = [:]
        reclassifyPeaks()
        resetToAutoSelection()
    }

    /// Resets peak selections back to the automatic mode-priority algorithm and
    /// clears the manual-modification flag.
    ///
    /// Call this when the user explicitly requests auto-selection (e.g. via a
    /// "Reset to Auto" button). If the spectrum is frozen the selection is
    /// applied immediately to `peaksAbovePeakMin`; otherwise it will take effect on
    /// the next freeze.
    func resetToAutoSelection() {
        userHasModifiedPeakSelection = false
        // Do not nil loadedMeasurementPeaks: the threshold slider must continue
        // to use the saved peaks as the source of truth rather than re-running
        // findPeaks on the frozen spectrum (which may not reproduce every saved peak).
        selectedPeakFrequencies = []
        // Auto-selection runs over the DURABLE set, never the displayed one. Selection identifies
        // which peak IS each mode — a fact about the measurement, not about the current Peak Min.
        // With `peaksAbovePeakMin` the wand would pick winners from only the visible peaks, and
        // lowering Peak Min afterwards would leave the revealed peaks unselected.
        let peaks = allPeaks
        guard !peaks.isEmpty else { return }
        gtLog("🎯 resetToAutoSelection: guitarType=\(TapDisplaySettings.guitarType.rawValue), \(peaks.count) candidate peaks")
        selectedPeakIDs = guitarModeSelectedPeakIDs(from: peaks)
        gtLog("🎯 resetToAutoSelection: selected \(selectedPeakIDs.count) peak(s)")
    }

    /// Whether the Re-analyze button is offered: **any complete guitar measurement with a frozen
    /// spectrum**, and never a plate/brace one.
    ///
    /// Re-analyze is a **reset**, not a dirty-flag indicator.  It is offered whenever it *could*
    /// do something, not only when we can prove it *will* — deliberately.  The things that can
    /// leave the displayed analysis differing from a clean re-derivation are open-ended: the peaks
    /// came from a file; mode assignments were carried forward across Peak Min moves rather than
    /// re-claimed (``applyFrozenPeakState``); the analysis range moved; selections were hand-edited.
    /// Proving "it will definitely change something" would mean enumerating all of those correctly,
    /// forever, with nothing to tell us when we got it wrong.  The two failure modes are not
    /// symmetric: a wrongly-DISABLED button is a dead end (the user cannot force the recomputation
    /// they want and has no other route to it), while a wrongly-ENABLED one costs a click that
    /// recomputes the same answer.  So it is offered whenever it can apply.
    ///
    /// Never for plate/brace: material peaks come from the per-phase captures, and running
    /// `findPeaks` over them would destroy the saved L / C / FLC peaks.  The measurement-type check
    /// states that directly rather than relying on a loaded material measurement's empty frozen
    /// spectrum.
    var canReanalyze: Bool {
        TapDisplaySettings.measurementType.isGuitar
            && isMeasurementComplete
            && !frozenFrequencies.isEmpty
            && !frozenMagnitudes.isEmpty
    }

    /// Re-runs peak detection on the frozen spectrum using the current analysis
    /// settings (Peak Min, analysis range, guitar type), replacing the peaks that
    /// were stored in the saved measurement.
    ///
    /// Lets the user retune a saved measurement — trying a different Peak Min,
    /// analysis range, or guitar type — without re-tapping.  After re-analysis the
    /// user can re-save the measurement to persist the updated peaks.
    ///
    /// Also re-claims the mode assignments from scratch: `identifiedModes` is cleared, so the
    /// carry-forward in ``applyFrozenPeakState`` has nothing to match and every peak is classified
    /// afresh by ``GuitarMode/classifyAll(_:)``.  This is the only route back to a clean
    /// classification once assignments have drifted across Peak Min moves.
    ///
    /// What survives: user mode **overrides** (remapped onto the new peak UUIDs by ±5 Hz frequency
    /// proximity) and annotation offsets.  What does not: the manual **selection** — auto-selection
    /// re-runs, so a hand-selected peak is deselected (its override is still attached; re-select it
    /// and the custom label returns).
    ///
    /// Does nothing if no frozen spectrum is available.
    func reanalyzePeaks() {
        guard isMeasurementComplete,
              !frozenFrequencies.isEmpty,
              !frozenMagnitudes.isEmpty else { return }

        // Clear loadedMeasurementPeaks so recalculateFrozenPeaksIfNeeded() falls
        // through to the live-tap path, which calls findPeaks() on the frozen spectrum.
        loadedMeasurementPeaks = nil
        userHasModifiedPeakSelection = false
        selectedPeakFrequencies = []
        identifiedModes = []

        // Now re-run the full peak analysis pipeline.
        recalculateFrozenPeaksIfNeeded()
        gtLog("🔬 Re-analyzed peaks from frozen spectrum: \(peaksAbovePeakMin.count) peaks found")
    }

    /// Finds every significant spectral peak within the configured frequency range.
    ///
    /// **Detection only — this function knows nothing about guitar modes.**
    ///
    /// A single sweep over the spectrum in ascending frequency order. Each bin is
    /// visited exactly once and mints at most one ``ResonantPeak``, so two peaks can
    /// never describe the same spectral feature.
    ///
    /// This is deliberate and load-bearing. The previous implementation iterated the
    /// mode ranges as its outer loop and the bins as its inner loop; because Top and
    /// Back overlap on every guitar type, a bin inside the overlap was scanned by two
    /// mode passes and `makePeak` was called on it twice, minting two peaks with two
    /// UUIDs and otherwise identical values. The assembly step then reconciled two
    /// independently deduplicated lists **by UUID** and let the twin survive, so every
    /// guitar capture on every platform saved one duplicated peak.
    ///
    /// Classification and mode claiming belong to ``GuitarMode/classifyAll(_:guitarType:)``,
    /// which operates on the returned peak *list* — where each peak has one identity and
    /// can be claimed exactly once. Do not reintroduce mode-range awareness here.
    ///
    /// Each accepted peak has its frequency and magnitude refined with parabolic
    /// interpolation and its Q factor calculated using the −3 dB bandwidth method.
    ///
    /// - Parameters:
    ///   - magnitudes: dBFS magnitude spectrum array.
    ///   - frequencies: Frequency axis (Hz) matching `magnitudes`.
    ///   - minHz: Lower frequency bound (Hz). Defaults to
    ///     ``TapToneAnalyzer/minFrequency``.
    ///   - maxHz: Upper frequency bound (Hz). Defaults to
    ///     ``TapToneAnalyzer/maxFrequency``.
    ///   - peakMinOverride: Adaptive magnitude floor (dBFS) supplied for plate/brace
    ///     captures; when `nil`, the guitar-mode `peakMinThreshold` is used.
    /// - Returns: Array of ``ResonantPeak`` values sorted by magnitude (descending).
    func findPeaks(magnitudes: [Float], frequencies: [Float], minHz: Float? = nil, maxHz: Float? = nil, peakMinOverride: Float? = nil) -> [ResonantPeak] {
        guard magnitudes.count == frequencies.count else { return [] }

        let windowSize = 5  // Look at ±5 bins around each point

        // Find frequency range indices — caller can override the analysis window
        let loFreq = minHz ?? minFrequency
        let hiFreq = maxHz ?? maxFrequency
        let startIdx = frequencies.firstIndex(where: { $0 >= loFreq }) ?? 0
        let endIdx = frequencies.firstIndex(where: { $0 > hiFreq }) ?? frequencies.count - 1

        // For plate/brace, the caller may supply an adaptive noise-floor threshold
        // (median of the search-range magnitudes) instead of the guitar-mode peakMinThreshold.
        let effectiveThreshold = peakMinOverride ?? peakMinThreshold

        // The ±windowSize local-maximum test needs that many neighbours on each side.
        let scanStart = startIdx + windowSize
        let scanEnd = endIdx - windowSize
        guard scanStart < scanEnd else { return [] }

        var peaks: [ResonantPeak] = []

        for i in scanStart..<scanEnd {
            let magnitude = magnitudes[i]
            guard magnitude > effectiveThreshold else { continue }

            // Local maximum check
            var isLocalMax = true
            for offset in -windowSize...windowSize where offset != 0 {
                if magnitudes[i + offset] >= magnitude {
                    isLocalMax = false
                    break
                }
            }
            guard isLocalMax else { continue }

            peaks.append(makePeak(at: i, magnitudes: magnitudes, frequencies: frequencies))
        }

        // Two adjacent bins can still resolve to interpolated vertices within
        // peakProximityHz of one another; collapse those, keeping the louder.
        return removeDuplicatePeaks(peaks).sorted(by: { $0.magnitude > $1.magnitude })
    }
    
    /// Applies the shared post-analysis state mutations common to both the
    /// loaded-measurement and live-tap paths in ``recalculateFrozenPeaksIfNeeded()``.
    ///
    /// Specifically:
    /// 1. Remaps mode classifications to the new peak UUIDs.
    /// 2. Remaps annotation offsets to the new peak UUIDs by frequency proximity.
    /// 3. Remaps mode overrides to the new peak UUIDs by frequency proximity.
    /// 4. Updates `selectedPeakIDs` / `selectedPeakFrequencies` according to the
    ///    current selection strategy (plate select-all, manual carry-forward, or
    ///    guitar auto-selection).
    ///
    /// - Parameters:
    ///   - peaks: The new peak array (already stored in `peaksAbovePeakMin`).
    ///   - modesByFrequency: Previously-saved `(frequency, mode)` pairs used to
    ///     remap mode labels across UUID changes.
    ///   - offsetsByFrequency: Previously-saved annotation offsets keyed by frequency.
    ///   - overridesByFrequency: Previously-saved mode overrides keyed by frequency.
    ///   - previouslySelectedFrequencies: Frequencies that were selected before
    ///     the threshold change (used for manual carry-forward).
    ///   - isGuitar: Whether the current measurement type is a guitar (vs plate/brace).
    ///   - tolerance: Frequency proximity tolerance in Hz (default 5 Hz).
    private func applyFrozenPeakState(
        peaks: [ResonantPeak],
        modesByFrequency: [(frequency: Float, mode: GuitarMode)],
        offsetsByFrequency: [(frequency: Float, offset: CGPoint)],
        overridesByFrequency: [(frequency: Float, override: String)],
        previouslySelectedFrequencies: [Float],
        isGuitar: Bool,
        tolerance: Float
    ) {
        // Remap mode classifications to new UUIDs.
        let freshModeMap = GuitarMode.classifyAll(peaks)
        identifiedModes = peaks.map { newPeak in
            if let saved = modesByFrequency.first(where: { abs($0.frequency - newPeak.frequency) <= tolerance }) {
                return (peak: newPeak, mode: saved.mode)
            }
            return (peak: newPeak, mode: freshModeMap[newPeak.id] ?? .unknown)
        }

        // Remap annotation offsets to new UUIDs by frequency proximity.
        var newOffsets: [UUID: CGPoint] = [:]
        for newPeak in peaks {
            if let match = offsetsByFrequency.first(where: { abs($0.frequency - newPeak.frequency) <= tolerance }) {
                newOffsets[newPeak.id] = match.offset
            }
        }
        peakAnnotationOffsets = newOffsets

        // Remap mode overrides to new UUIDs by frequency proximity.
        var newOverrides: [UUID: String] = [:]
        for newPeak in peaks {
            if let match = overridesByFrequency.first(where: { abs($0.frequency - newPeak.frequency) <= tolerance }) {
                newOverrides[newPeak.id] = match.override
            }
        }
        peakModeOverrides = newOverrides

        if !isGuitar {
            // Plate/brace: selection is managed exclusively by the phase-completion handlers
            // (only the identified peak is selected). Don't clobber it here.
            selectedPeakFrequencies = peaks.filter { selectedPeakIDs.contains($0.id) }.map { $0.frequency }
        } else if userHasModifiedPeakSelection {
            // Carry forward by frequency proximity: for each previously-selected
            // frequency pick the single closest new peak within tolerance.
            // Peaks currently below the threshold are kept in the frequency cache
            // so they are re-selected when the threshold is lowered again.
            var carriedIDs = Set<UUID>()
            var carriedFreqs: [Float] = []
            for oldFreq in previouslySelectedFrequencies {
                if let closest = peaks
                    .filter({ abs($0.frequency - oldFreq) <= tolerance })
                    .min(by: { abs($0.frequency - oldFreq) < abs($1.frequency - oldFreq) }) {
                    if carriedIDs.insert(closest.id).inserted {
                        carriedFreqs.append(closest.frequency)
                    }
                } else {
                    // Peak is below threshold — preserve its frequency so it
                    // is re-selected when the threshold is lowered again.
                    carriedFreqs.append(oldFreq)
                }
            }
            selectedPeakIDs = carriedIDs
            selectedPeakFrequencies = carriedFreqs
        } else {
            // No user changes yet: re-run the mode-priority auto-selection.
            let autoIDs = guitarModeSelectedPeakIDs(from: peaks)
            selectedPeakIDs = autoIDs
            selectedPeakFrequencies = peaks.filter { autoIDs.contains($0.id) }.map { $0.frequency }
        }
    }

    /// Builds a ``ResonantPeak`` from a single FFT bin, applying parabolic
    /// interpolation for sub-bin accuracy and computing the Q factor.
    ///
    /// - Parameters:
    ///   - index: The bin index of the local maximum.
    ///   - magnitudes: dBFS magnitude spectrum.
    ///   - frequencies: Frequency axis (Hz) matching `magnitudes`.
    /// - Returns: A fully-populated ``ResonantPeak``.
    private func makePeak(at index: Int, magnitudes: [Float], frequencies: [Float]) -> ResonantPeak {
        let (interpFreq, interpMag) = parabolicInterpolate(magnitudes: magnitudes, frequencies: frequencies, peakIndex: index)
        let (quality, bandwidth) = calculateQFactor(magnitudes: magnitudes, frequencies: frequencies, peakIndex: index, peakMagnitude: interpMag)
        let freq = Double(interpFreq)
        return ResonantPeak(
            frequency: interpFreq,
            magnitude: interpMag,
            quality: quality,
            bandwidth: bandwidth,
            pitchNote: pitchCalculator.note(frequency: freq),
            pitchCents: pitchCalculator.cents(frequency: freq),
            pitchFrequency: pitchCalculator.freq0(frequency: freq)
        )
    }

    /// Returns the set of peak IDs auto-selected by guitar mode: one peak per
    /// named mode, chosen as the strongest (highest magnitude) peak that
    /// ``GuitarMode/classifyAll(_:guitarType:)`` assigns to that mode.
    ///
    /// Multiple peaks can share the same mode label (e.g. two peaks in the Air
    /// range); only the loudest representative of each mode is selected.
    /// Peaks classified as `.unknown` are never auto-selected but can be toggled
    /// individually in the results panel.
    ///
    /// - Parameter peaks: The candidate peak array to classify. Defaults to
    ///   ``allPeaks`` — the DURABLE set. Auto-selection is a fact about the measurement, so it must
    ///   never run over the Peak Min projection: raising the slider would otherwise leave nothing to
    ///   select, and lowering it would re-pick different winners.
    /// - Returns: A `Set<UUID>` containing at most one peak ID per named mode.
    func guitarModeSelectedPeakIDs(from peaks: [ResonantPeak]? = nil) -> Set<UUID> {
        let candidates = peaks ?? allPeaks
        let modeMap = GuitarMode.classifyAll(candidates)
        let claimedModes: Set<GuitarMode> = [.air, .top, .back, .dipole, .ringMode, .upperModes]

        gtLog("🎯 guitarModeSelectedPeakIDs: \(candidates.count) candidates, guitarType=\(TapDisplaySettings.guitarType.rawValue)")
        for peak in candidates {
            let mode = modeMap[peak.id] ?? .unknown
            gtLog("  peak \(String(format: "%.1f", peak.frequency)) Hz mag=\(String(format: "%.1f", peak.magnitude)) dB → \(mode.rawValue)")
        }

        // Group peaks by their assigned mode, keeping only named modes.
        var bestPerMode: [GuitarMode: ResonantPeak] = [:]
        for peak in candidates {
            guard let mode = modeMap[peak.id], claimedModes.contains(mode) else { continue }
            if bestPerMode[mode] == nil || peak.magnitude > bestPerMode[mode]!.magnitude {
                bestPerMode[mode] = peak
            }
        }
        gtLog("🎯 guitarModeSelectedPeakIDs: bestPerMode modes = \(bestPerMode.keys.map { $0.rawValue }.sorted())")
        return Set(bestPerMode.values.map { $0.id })
    }

    /// Re-runs mode classification on `peaksAbovePeakMin` using the active guitar
    /// type's frequency ranges.
    ///
    /// Call this after the user changes the guitar type (acoustic ↔ classical)
    /// so that `identifiedModes` stays consistent with the updated
    /// ``GuitarMode/modeRange`` boundaries without requiring a new tap.
    /// Classification runs over the DURABLE set, never the displayed one.
    ///
    /// `classifyAll` claims one peak per mode in ascending frequency order, and the Top and Back
    /// bands overlap. Classifying only the Peak-Min-filtered set therefore mis-assigns: if the true
    /// Top sits below Peak Min it is absent, so Top's claim falls through to a peak in the overlap
    /// that should have been Back — a Back peak silently becomes a Top on reload.
    ///
    /// Which mode a peak is, is a fact about the measurement, not about what is currently on screen.
    func reclassifyPeaks() {
        let modeMap = GuitarMode.classifyAll(allPeaks)
        identifiedModes = allPeaks.map { (peak: $0, mode: modeMap[$0.id] ?? .unknown) }
    }

    /// Returns a map from `GuitarMode` to the strongest `ResonantPeak` for each mode,
    /// using the provided guitar type for classification boundaries.
    ///
    /// Used by comparison views, PDF export, and regression tests to resolve
    /// Air / Top / Back peaks.  When multiple peaks classify to the same mode,
    /// the highest-magnitude one wins.
    ///
    /// - Parameters:
    ///   - peaks: The selected peaks for one comparison entry.
    ///   - guitarType: The guitar type saved with that measurement (nil uses app default).
    /// - Returns: A dictionary mapping each identified `GuitarMode` to its strongest `ResonantPeak`.
    static func resolvedModePeaks(
        peaks: [ResonantPeak],
        overrides: [UUID: String] = [:],
        guitarType: GuitarType?
    ) -> [GuitarMode: ResonantPeak] {
        let modeMap: [UUID: GuitarMode]
        if let guitarType {
            modeMap = GuitarMode.classifyAll(peaks, guitarType: guitarType)
        } else {
            modeMap = GuitarMode.classifyAll(peaks)
        }
        var result: [GuitarMode: ResonantPeak] = [:]
        for peak in peaks {
            // Override-aware, so a relabelled peak resolves to the mode the user assigned — the same
            // rule the analyzer and the ratio use. Callers that already work on a pre-selected set
            // still get one strongest peak per *effective* mode.
            let mode = GuitarMode.effectiveMode(override: overrides[peak.id], auto: modeMap[peak.id] ?? .unknown)
            guard mode != .unknown else { continue }
            if let existing = result[mode], peak.magnitude <= existing.magnitude { continue }
            result[mode] = peak
        }
        return result
    }

    /// Removes peaks that are closer than 2 Hz apart, keeping only the
    /// higher-magnitude peak from each near-duplicate pair.
    ///
    /// Near-duplicate peaks arise when a single physical resonance straddles
    /// two adjacent FFT bins that are each detected as local maxima. The 2 Hz
    /// tolerance is appropriate for the typical bin spacing of the continuous
    /// FFT (≈ 1.4 Hz at 44.1 kHz / 32768 bins).
    ///
    /// - Parameter peaks: Input peak array (any order).
    /// - Returns: Array with near-duplicates removed, preserving insertion
    ///   order of the first-seen instance (updated if a later duplicate has
    ///   higher magnitude).
    func removeDuplicatePeaks(_ peaks: [ResonantPeak]) -> [ResonantPeak] {
        var uniquePeaks: [ResonantPeak] = []
        let frequencyTolerance = TapToneAnalyzer.peakProximityHz
        
        for peak in peaks {
            // Check if we already have a peak at this frequency
            let isDuplicate = uniquePeaks.contains { existingPeak in
                abs(existingPeak.frequency - peak.frequency) < frequencyTolerance
            }
            
            if !isDuplicate {
                uniquePeaks.append(peak)
            } else {
                // If duplicate, keep the one with higher magnitude
                if let existingIndex = uniquePeaks.firstIndex(where: { abs($0.frequency - peak.frequency) < frequencyTolerance }) {
                    if peak.magnitude > uniquePeaks[existingIndex].magnitude {
                        uniquePeaks[existingIndex] = peak
                    }
                }
            }
        }
        
        return uniquePeaks
    }
    
    /// Refine a bin-level peak location using parabolic interpolation.
    ///
    /// Fits a parabola through the peak bin and its two immediate neighbours to
    /// estimate where the true spectral peak lies between bin centres. This
    /// improves frequency accuracy by roughly one order of magnitude over the
    /// raw bin spacing, and corrects the magnitude estimate so it reflects the
    /// true peak rather than the magnitude sampled at the nearest bin centre.
    ///
    /// The sub-bin offset δ is computed as:
    /// ```
    /// δ = 0.5 · (α − γ) / (α − 2β + γ)       [δ ∈ (−0.5, 0.5)]
    /// f_true  = f_bin + δ · Δf
    /// A_true  = β − 0.25 · (α − γ) · δ
    /// ```
    /// where `α = magnitudes[i−1]`, `β = magnitudes[i]`, `γ = magnitudes[i+1]`,
    /// and `Δf` is the bin width in Hz.
    ///
    /// - Parameters:
    ///   - magnitudes: dB magnitude spectrum.
    ///   - frequencies: Frequency axis matching `magnitudes`.
    ///   - i: Index of the local maximum bin.
    /// - Returns: `(frequency, magnitude)` of the interpolated peak in Hz and
    ///   dBFS. Falls back to the raw bin values if the peak is at a boundary or
    ///   if the parabola denominator is near zero (flat top).
    func parabolicInterpolate(magnitudes: [Float], frequencies: [Float], peakIndex i: Int) -> (frequency: Float, magnitude: Float) {
        guard i > 0, i < magnitudes.count - 1 else {
            return (frequencies[i], magnitudes[i])
        }
        let val  = magnitudes[i]
        let lval = magnitudes[i - 1]
        let rval = magnitudes[i + 1]
        let denom = lval - 2 * val + rval
        // Avoid division by near-zero (flat top — bin is already accurate)
        guard abs(denom) > 1e-6 else {
            return (frequencies[i], val)
        }
        // Sub-bin offset δ ∈ (-0.5, 0.5)
        let delta = 0.5 * (lval - rval) / denom
        let binWidth = frequencies[i] - frequencies[i - 1]
        let interpFreq = frequencies[i] + delta * binWidth
        let interpMag  = val - 0.25 * (lval - rval) * delta
        return (interpFreq, interpMag)
    }

    /// Calculate the Q factor and −3 dB bandwidth for a spectral peak.
    ///
    /// Walks outward from `peakIndex` in both directions until the magnitude
    /// first drops below `peakMagnitude − 3 dB`, then computes:
    /// ```
    /// bandwidth = f_upper − f_lower
    /// Q         = f_centre / bandwidth
    /// ```
    ///
    /// - Parameters:
    ///   - magnitudes: dB spectrum array.
    ///   - frequencies: Frequency axis matching `magnitudes`. Use the gated
    ///     FFT frequency array when called on gated-FFT data so the bin spacing
    ///     is correct.
    ///   - peakIndex: Index of the peak bin in both arrays.
    ///   - peakMagnitude: Peak magnitude in dBFS. Use the interpolated value
    ///     from ``parabolicInterpolate(magnitudes:frequencies:peakIndex:)`` for
    ///     best accuracy.
    /// - Returns: `(quality, bandwidth)` where `quality` is dimensionless Q and
    ///   `bandwidth` is in Hz. Both are 0 if index bounds are exceeded.
    func calculateQFactor(magnitudes: [Float], frequencies: [Float], peakIndex: Int, peakMagnitude: Float) -> (quality: Float, bandwidth: Float) {
        let threshold = peakMagnitude - 3.0  // -3 dB points

        // Find lower -3 dB point
        var lowerIdx = peakIndex
        while lowerIdx > 0 && magnitudes[lowerIdx] > threshold {
            lowerIdx -= 1
        }

        // Find upper -3 dB point
        var upperIdx = peakIndex
        while upperIdx < magnitudes.count - 1 && magnitudes[upperIdx] > threshold {
            upperIdx += 1
        }

        guard peakIndex < frequencies.count,
              lowerIdx < frequencies.count,
              upperIdx < frequencies.count else {
            return (quality: 0, bandwidth: 0)
        }

        let lowerFreq = frequencies[lowerIdx]
        let upperFreq = frequencies[upperIdx]
        let centerFreq = frequencies[peakIndex]

        let bandwidth = upperFreq - lowerFreq
        let quality = bandwidth > 0 ? centerFreq / bandwidth : 0

        return (quality: quality, bandwidth: bandwidth)
    }
}
