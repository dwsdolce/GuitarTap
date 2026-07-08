//
//  TapToneAnalyzer+PeakAnalysis.swift
//  GuitarTap
//
//  Created on 1/25/26.
//
// @parity dsp/peak-analysis

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
/// 3. **Mode classification** — each peak is mapped to a ``GuitarMode`` via
///    ``GuitarMode/classify(frequency:)``.
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

    /// Main entry point called by ``RealtimeFFTAnalyzer`` on every FFT frame.
    ///
    /// Performs tap detection (guitar mode only), peak finding, mode
    /// classification, and decay tracking in sequence.
    ///
    /// - Parameters:
    ///   - magnitudes: The current magnitude spectrum in dBFS, one value per
    ///     FFT bin.
    ///   - frequencies: The frequency axis matching `magnitudes`, in Hz.
    ///   - peakMagnitude: The maximum bin magnitude in dBFS — used for
    ///     hysteresis tap detection and decay tracking.
    ///
    /// - Note: Must be called on the main thread; `fftAnalyzer` publishes on
    ///   the main queue via a Combine `.receive(on: RunLoop.main)` subscription.
    func analyzeMagnitudes(_ magnitudes: [Float], frequencies: [Float], peakMagnitude: Float) {
        // Don't analyze anything if the FFT analyzer isn't actually running
        guard fftAnalyzer.isRunning else {
            // Reset tap detection state to prevent false positives before start
            tapDetected = false
            return
        }
        
        // Calculate average magnitude for tap detection; exclude below-noise-floor bins (-100 dB)
        let validMags = magnitudes.filter { $0 > -100 }
        averageMagnitude = validMags.isEmpty ? -100 : validMags.reduce(0, +) / Float(validMags.count)
        
        // Tap detection runs on the fast inputLevelDB path (see onRmsLevelChanged
        // in +TapDetection.swift) for all measurement types — not from this
        // FFT-rate path.  This block only governs the live-threshold strategy
        // below for plate/brace; mirrors Python tap_tone_analyzer_peak_analysis.py.
        let mType = TapDisplaySettings.measurementType
        let usesFastTapDetection = (mType == .plate || mType == .brace)
        
        // Analyze peaks if detection is enabled, paused (spectrum stays live), or in capture window.
        // Do not overwrite currentPeaks once a measurement is complete — for guitar that means the
        // frozen averaged spectrum peaks; for plate/brace the final L/C/FLC peaks.
        if (isDetecting || isDetectionPaused || captureTimer != nil) && !isMeasurementComplete {
            // For plate/brace, use an adaptive noise-floor threshold (median of the analysis
            // range) instead of the guitar-mode peakMinThreshold so the live peak list
            // self-calibrates to each tap's actual signal level.
            let liveThreshold: Float?
            if usesFastTapDetection {
                let loFreq = minFrequency
                let hiFreq = maxFrequency
                let sIdx = frequencies.firstIndex(where: { $0 >= loFreq }) ?? 0
                let eIdx = frequencies.firstIndex(where: { $0 > hiFreq }) ?? frequencies.count - 1
                if sIdx < eIdx {
                    let searchMags = Array(magnitudes[sIdx..<eIdx])
                    liveThreshold = searchMags.sorted()[searchMags.count / 2]
                } else {
                    liveThreshold = nil
                }
            } else {
                liveThreshold = nil
            }
            // Find peaks in spectrum
            let peaks = findPeaks(magnitudes: magnitudes, frequencies: frequencies, peakMinOverride: liveThreshold)
            currentPeaks = peaks
            // Auto-select all newly detected peaks so visibility mode "selected" shows everything by default.
            // In plate/brace mode, selection is managed exclusively by the phase-completion handlers
            // so that only the identified peak(s) appear selected — don't clobber it here.
            if TapDisplaySettings.measurementType.isGuitar {
                selectedPeakIDs = Set(peaks.map { $0.id })
            }

            // Classify modes using context-aware algorithm so overlapping ranges resolve correctly
            let modeMap = GuitarMode.classifyAll(peaks)
            identifiedModes = peaks.map { (peak: $0, mode: modeMap[$0.id] ?? .unknown) }
            
        }
        
    }

    /// Re-runs peak finding on the frozen spectrum when the peak threshold changes.
    ///
    /// Called from the `peakMinThreshold` `didSet` observer. Has no effect when the
    /// spectrum is not frozen or when frozen data is unavailable.
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
                previouslySelectedFrequencies = currentPeaks.filter { selectedPeakIDs.contains($0.id) }.map { $0.frequency }
            }
        } else {
            previouslySelectedFrequencies = []
        }

        // Annotation offsets keyed by frequency (currentPeaks is always in sync with peakAnnotationOffsets).
        let offsetsByFrequency: [(frequency: Float, offset: CGPoint)] = peakAnnotationOffsets.compactMap { uuid, offset in
            guard let peak = currentPeaks.first(where: { $0.id == uuid }) else { return nil }
            return (peak.frequency, offset)
        }

        // Mode overrides keyed by frequency (currentPeaks is always in sync with peakModeOverrides).
        let overridesByFrequency: [(frequency: Float, override: UserAssignedMode)] = peakModeOverrides.compactMap { uuid, mode in
            guard let peak = currentPeaks.first(where: { $0.id == uuid }) else { return nil }
            return (peak.frequency, mode)
        }

        // --- Loaded-measurement path ---
        // When peaks come from a loaded file, the saved peaks are the authoritative
        // analysis record and may not be reproducible by re-running findPeaks on the
        // frozen spectrum (spectrum averaging, FFT windowing, and analysis settings can
        // all differ between sessions). Filter the saved peaks by threshold instead.
        if let savedPeaks = loadedMeasurementPeaks {
            let peaks = savedPeaks.filter { $0.magnitude >= peakMinThreshold }

            guard !peaks.isEmpty else {
                currentPeaks = []
                identifiedModes = []
                return
            }

            currentPeaks = peaks

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
            if !tapEntries.isEmpty {
                recalculateTapEntryPeaks()
            }
            return
        }

        // --- Live-tap path (no loaded measurement) ---
        // Mode assignments keyed by frequency. Stable across slider moves; cleared only
        // when peaks go to zero (identifiedModes = []).
        let modesByFrequency: [(frequency: Float, mode: GuitarMode)] = identifiedModes.map {
            ($0.peak.frequency, $0.mode)
        }

        let peaks = findPeaks(magnitudes: frozenMagnitudes, frequencies: frozenFrequencies)

        // If no peaks are found at the current threshold, clear the display but
        // do NOT update selectedPeakIDs — preserving them means the selection can
        // be remapped correctly when the threshold is lowered again.
        guard !peaks.isEmpty else {
            currentPeaks = []
            identifiedModes = []
            return
        }

        currentPeaks = peaks

        applyFrozenPeakState(
            peaks: peaks,
            modesByFrequency: modesByFrequency,
            offsetsByFrequency: offsetsByFrequency,
            overridesByFrequency: overridesByFrequency,
            previouslySelectedFrequencies: previouslySelectedFrequencies,
            isGuitar: isGuitar,
            tolerance: tolerance
        )

        // Recompute per-tap peaks so the multi-tap comparison table reflects the
        // current Peak Min setting. Each TapEntry stores its full spectrum snapshot,
        // so we can re-run findPeaks with the updated threshold.
        if !tapEntries.isEmpty {
            recalculateTapEntryPeaks()
        }
    }

    /// Re-runs peak detection on every stored `TapEntry` snapshot using the
    /// current `peakMinThreshold`, then updates `tapEntries` so the multi-tap
    /// comparison table shows peaks consistent with the Peak Min slider.
    /// Re-runs peak detection on every stored `TapEntry` snapshot using the
    /// current `peakMinThreshold`, then updates `tapEntries` so the multi-tap
    /// comparison table shows peaks consistent with the Peak Min slider.
    ///
    /// Called from `recalculateFrozenPeaksIfNeeded()` (slider changes) and
    /// from `loadMeasurement(_:)` (recompute with saved threshold on load).
    func recalculateTapEntryPeaks() {
        tapEntries = tapEntries.map { entry in
            let tapPeaks = findPeaks(
                magnitudes: entry.snapshot.magnitudes,
                frequencies: entry.snapshot.frequencies
            )
            let modeSelected = guitarModeSelectedPeakIDs(from: tapPeaks)
            var updated = entry
            updated.peaks = tapPeaks
            updated.selectedPeakIDs = Array(modeSelected)
            return updated
        }
    }

    /// Resets peak selections back to the automatic mode-priority algorithm and
    /// clears the manual-modification flag.
    ///
    /// Call this when the user explicitly requests auto-selection (e.g. via a
    /// "Reset to Auto" button). If the spectrum is frozen the selection is
    /// applied immediately to `currentPeaks`; otherwise it will take effect on
    /// the next freeze.
    func resetToAutoSelection() {
        userHasModifiedPeakSelection = false
        // Do not nil loadedMeasurementPeaks: the threshold slider must continue
        // to use the saved peaks as the source of truth rather than re-running
        // findPeaks on the frozen spectrum (which may not reproduce every saved peak).
        selectedPeakFrequencies = []
        let peaks = currentPeaks
        guard !peaks.isEmpty else { return }
        gtLog("🎯 resetToAutoSelection: guitarType=\(TapDisplaySettings.guitarType.rawValue), \(peaks.count) candidate peaks")
        selectedPeakIDs = guitarModeSelectedPeakIDs(from: peaks)
        gtLog("🎯 resetToAutoSelection: selected \(selectedPeakIDs.count) peak(s)")
    }

    /// Re-runs peak detection on the frozen spectrum using the current analysis
    /// settings (Peak Min, analysis range, guitar type), replacing the peaks that
    /// were stored in the saved measurement.
    ///
    /// Lets the user retune a saved measurement — trying a different Peak Min,
    /// analysis range, or guitar type — without re-tapping.  After re-analysis the
    /// user can re-save the measurement to persist the updated peaks.
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
        gtLog("🔬 Re-analyzed peaks from frozen spectrum: \(currentPeaks.count) peaks found")
    }

    /// Finds all significant spectral peaks within the configured frequency range.
    ///
    /// The algorithm uses a two-pass strategy with mode-priority selection:
    ///
    /// **Pass 1 — Known modes:**
    /// Scans each mode's band from ``GuitarType/modeRanges`` for local maxima
    /// that exceed ``TapToneAnalyzer/peakMinThreshold``. Tracks the strongest peak
    /// per canonical mode name so each guitar mode always gets a guaranteed slot
    /// in the output.
    ///
    /// **Pass 2 — Unknown/inter-mode peaks:**
    /// Scans the entire configured frequency window for local maxima that fall
    /// outside all known mode ranges.
    ///
    /// **Step 3 — Assembly:**
    /// The strongest peak from each mode occupies a guaranteed slot. All
    /// remaining peaks are then appended in descending magnitude order.
    ///
    /// Each accepted peak has its frequency and magnitude refined with
    /// parabolic interpolation and its Q factor calculated using the −3 dB
    /// bandwidth method.
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
    /// - Returns: Array of ``ResonantPeak`` values sorted by magnitude
    ///   (descending).
    func findPeaks(magnitudes: [Float], frequencies: [Float], minHz: Float? = nil, maxHz: Float? = nil, peakMinOverride: Float? = nil) -> [ResonantPeak] {
        guard magnitudes.count == frequencies.count else { return [] }
        
        var allPeaks: [ResonantPeak] = []
        let windowSize = 5  // Look at ±5 bins around each point
        
        // Find frequency range indices — caller can override the analysis window
        let loFreq = minHz ?? minFrequency
        let hiFreq = maxHz ?? maxFrequency
        let startIdx = frequencies.firstIndex(where: { $0 >= loFreq }) ?? 0
        let endIdx = frequencies.firstIndex(where: { $0 > hiFreq }) ?? frequencies.count - 1
        
        // For plate/brace, the caller may supply an adaptive noise-floor threshold
        // (median of the search-range magnitudes) instead of the guitar-mode peakMinThreshold.
        let effectiveThreshold = peakMinOverride ?? peakMinThreshold
        
        // Define all known modes to search for (excluding unknown), sorted by
        // ascending range lower bound so we scan the spectrum low-to-high.
        let guitarType = TapDisplaySettings.guitarType
        let knownModes: [GuitarMode] = [.air, .top, .back, .dipole, .ringMode, .upperModes]
            .sorted { $0.modeRange(for: guitarType).lowerBound < $1.modeRange(for: guitarType).lowerBound }

        // Track the strongest peak found in each mode range.
        var strongestPeakPerMode: [GuitarMode: ResonantPeak] = [:]

        // Step 1: Search known mode ranges for peaks sequentially, low-to-high.
        //
        // Each mode's scan window starts at:
        //   max(mode range lower bound, frequency just above the last claimed peak)
        //
        // This prevents the same physical peak from being claimed by two overlapping
        // mode ranges (e.g. the Top/Back overlap zone at 190–230 Hz for classical
        // guitar). Whichever mode's range starts lower gets first claim; the next
        // mode's scan begins above the claimed peak's raw bin so it cannot re-find
        // the same local maximum even when parabolic interpolation pulls the
        // reported frequency below the bin's own center frequency.
        var lastClaimedBinIdx: Int = -1                    // raw bin index of the last claimed peak
        var strongestBinPerMode: [GuitarMode: Int] = [:]  // normalised mode → raw bin of winner

        for mode in knownModes {
            let modeRange = mode.modeRange(for: guitarType)

            // Find the raw index boundaries for this mode's range, clamped to the
            // analysis window. upperModes extends to 20 kHz but the display window
            // may end at 2 kHz — still scan within the window.
            let modeStartIdx = max(frequencies.firstIndex(where: { $0 >= modeRange.lowerBound }) ?? startIdx, startIdx)
            let modeEndIdx   = min(frequencies.firstIndex(where: { $0 > modeRange.upperBound  }) ?? endIdx,   endIdx)
            guard modeStartIdx < modeEndIdx else { continue }

            // Advance the scan start to one bin past the last claimed peak's raw bin.
            // Using the raw bin index (not the interpolated frequency) prevents
            // parabolic interpolation from pulling the cursor back onto the
            // claimed peak's own bin, which would allow the next mode to re-claim it.
            let claimedIdx = lastClaimedBinIdx >= 0 ? lastClaimedBinIdx + 1 : startIdx
            let effectiveStartIdx = max(modeStartIdx, claimedIdx)

            let scanStart = max(effectiveStartIdx, startIdx + windowSize)
            let scanEnd   = min(modeEndIdx, endIdx - windowSize)
            guard scanStart < scanEnd else { continue }

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

                let peak = makePeak(at: i, magnitudes: magnitudes, frequencies: frequencies)
                // Add every above-threshold local maximum to the candidate pool
                // so that non-strongest peaks within a mode range are still visible
                // and selectable by the user.  The strongest peak per mode gets a
                // guaranteed slot in step 3; the rest compete for remaining slots
                // by magnitude alongside unknown (inter-mode) peaks.
                allPeaks.append(peak)
                let normalizedMode = mode.normalized
                if let existing = strongestPeakPerMode[normalizedMode] {
                    if magnitude > existing.magnitude {
                        strongestPeakPerMode[normalizedMode] = peak
                        strongestBinPerMode[normalizedMode] = i
                    }
                } else {
                    strongestPeakPerMode[normalizedMode] = peak
                    strongestBinPerMode[normalizedMode] = i
                }
            }

            // Advance the claimed-bin cursor to the raw bin of the strongest peak
            // found in this mode (if any), so the next mode's scan starts above it.
            // If the interpolated frequency of the newly claimed peak is within 2 Hz of
            // an already-claimed peak (can happen at mode-range boundaries when parabolic
            // interpolation pulls a bin frequency back across the cursor), discard it so
            // the same physical peak is not double-counted under two mode labels.
            let normalizedForCursor = mode.normalized
            if let claimed = strongestPeakPerMode[normalizedForCursor] {
                let isDuplicate = strongestPeakPerMode
                    .filter { $0.key != normalizedForCursor }
                    .values
                    .contains { abs($0.frequency - claimed.frequency) < TapToneAnalyzer.peakProximityHz }
                if isDuplicate {
                    strongestPeakPerMode.removeValue(forKey: normalizedForCursor)
                    strongestBinPerMode.removeValue(forKey: normalizedForCursor)
                } else if let claimedBin = strongestBinPerMode[normalizedForCursor] {
                    lastClaimedBinIdx = max(lastClaimedBinIdx, claimedBin)
                }
            }
        }
        
        // Step 2: Search entire spectrum for peaks outside known mode ranges (unknown peaks)
        let outerScanStart = startIdx + windowSize
        let outerScanEnd = endIdx - windowSize
        if outerScanStart < outerScanEnd {
            for i in outerScanStart..<outerScanEnd {
                let magnitude = magnitudes[i]
                let frequency = frequencies[i]
                
                // Skip if below threshold
                guard magnitude > effectiveThreshold else { continue }
                
                // Check if this frequency is already covered by a known mode
                let isInKnownMode = knownModes.contains { mode in
                    mode.modeRange(for: guitarType).contains(frequency)
                }
                
                // Only process if outside known mode ranges
                guard !isInKnownMode else { continue }
                
                // Check if local maximum
                var isLocalMax = true
                for offset in -windowSize...windowSize where offset != 0 {
                    if magnitudes[i + offset] >= magnitude {
                        isLocalMax = false
                        break
                    }
                }
                
                guard isLocalMax else { continue }
                
                let peak = makePeak(at: i, magnitudes: magnitudes, frequencies: frequencies)
                allPeaks.append(peak)
            }
        }
        
        // Remove duplicate peaks (in case of overlap)
        allPeaks = removeDuplicatePeaks(allPeaks)
        
        // Step 3: Build final peak list with mode priority.
        // First, include the strongest peak from each known mode (guaranteed slots).
        // Deduplicate the guaranteed-slot peaks by frequency before inserting them:
        // a peak in the Top/Back overlap zone is found independently by both mode
        // range scans and ends up in strongestPeakPerMode under two different keys
        // (with two different UUIDs). removeDuplicatePeaks collapses them to one.
        var finalPeaks: [ResonantPeak] = []
        var includedPeakIDs = Set<UUID>()

        // The sequential scan above ensures no physical peak appears in two mode
        // slots, so removeDuplicatePeaks here is just a safety net for edge cases.
        let guaranteedPeaks = removeDuplicatePeaks(Array(strongestPeakPerMode.values))
        for peak in guaranteedPeaks {
            finalPeaks.append(peak)
            includedPeakIDs.insert(peak.id)
        }
        
        // Then append all remaining peaks by magnitude (no limit).
        let otherPeaks = allPeaks
            .filter { !includedPeakIDs.contains($0.id) }
            .sorted { $0.magnitude > $1.magnitude }
        finalPeaks.append(contentsOf: otherPeaks)
        
        // Sort final result by magnitude descending
        return finalPeaks.sorted(by: { $0.magnitude > $1.magnitude })
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
    ///   - peaks: The new peak array (already stored in `currentPeaks`).
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
        overridesByFrequency: [(frequency: Float, override: UserAssignedMode)],
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
        var newOverrides: [UUID: UserAssignedMode] = [:]
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
    ///   `currentPeaks`.
    /// - Returns: A `Set<UUID>` containing at most one peak ID per named mode.
    func guitarModeSelectedPeakIDs(from peaks: [ResonantPeak]? = nil) -> Set<UUID> {
        let candidates = peaks ?? currentPeaks
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

    /// Re-runs mode classification on `currentPeaks` using the active guitar
    /// type's frequency ranges.
    ///
    /// Call this after the user changes the guitar type (acoustic ↔ classical)
    /// so that `identifiedModes` stays consistent with the updated
    /// ``GuitarMode/modeRange`` boundaries without requiring a new tap.
    func reclassifyPeaks() {
        let modeMap = GuitarMode.classifyAll(currentPeaks)
        identifiedModes = currentPeaks.map { (peak: $0, mode: modeMap[$0.id] ?? .unknown) }
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
            guard let mode = modeMap[peak.id], mode != .unknown else { continue }
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
