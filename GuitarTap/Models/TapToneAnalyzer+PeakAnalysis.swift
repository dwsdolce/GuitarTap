//
//  TapToneAnalyzer+PeakAnalysis.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

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
/// 4. **Decay tracking** — ``trackDecay(peakMagnitude:)`` is always called,
///    even when detection is paused, so ring-out time continues to be measured
///    after a tap.
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
        
        // Only detect taps if detection is enabled.
        // Plate/brace modes use the fast recentPeakLevelDB subscription instead of
        // this slow FFT path — the long-window FFT dilutes transient tap energy by ~15 dB.
        let mType = TapDisplaySettings.measurementType
        let usesFastTapDetection = (mType == .plate || mType == .brace)
        if isDetecting && !usesFastTapDetection {
            detectTap(peakMagnitude: peakMagnitude, magnitudes: magnitudes, frequencies: frequencies)
        }
        
        // Analyze peaks if detection is enabled, paused (spectrum stays live), or in capture window.
        // Do not overwrite currentPeaks after a plate/brace measurement is complete —
        // those peaks are the final selected L/C/FLC peaks and must not be replaced by live audio.
        if (isDetecting || isDetectionPaused || captureTimer != nil) && materialTapPhase != .complete {
            // Find peaks in spectrum
            let peaks = findPeaks(magnitudes: magnitudes, frequencies: frequencies)
            currentPeaks = peaks
            // Auto-select all newly detected peaks so visibility mode "selected" shows everything by default
            selectedPeakIDs = Set(peaks.map { $0.id })

            // Classify modes
            identifiedModes = peaks.map { peak in
                (peak: peak, mode: GuitarMode.classify(frequency: peak.frequency))
            }
            
        }
        
        // Always track peak magnitude for decay analysis (even when not detecting taps)
        // This ensures we can measure ring-out time after a tap is detected
        trackDecay(peakMagnitude: peakMagnitude)
    }

    /// Re-runs peak finding on the frozen spectrum when the peak threshold changes.
    ///
    /// Called from the `peakThreshold` `didSet` observer. Has no effect when the
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
        guard isSpectrumFrozen,
              !frozenFrequencies.isEmpty,
              !frozenMagnitudes.isEmpty else { return }

        let isGuitar = TapDisplaySettings.measurementType.isGuitar

        // Snapshot selected frequencies before peaks are replaced (UUIDs change).
        let previouslySelectedFrequencies: [Float] = isGuitar && userHasModifiedPeakSelection
            ? currentPeaks.filter { selectedPeakIDs.contains($0.id) }.map { $0.frequency }
            : []

        let peaks = findPeaks(magnitudes: frozenMagnitudes, frequencies: frozenFrequencies)
        currentPeaks = peaks
        identifiedModes = peaks.map { peak in
            (peak: peak, mode: GuitarMode.classify(frequency: peak.frequency))
        }

        if !isGuitar {
            // Plate/brace: the frozen peaks are final gated-capture results — select all.
            selectedPeakIDs = Set(peaks.map { $0.id })
        } else if userHasModifiedPeakSelection {
            // User has made manual changes: carry forward selections by frequency proximity.
            // A new peak is selected only if its frequency is within 5 Hz of a previously
            // selected peak — anything further away is treated as a new/different peak and
            // left deselected so the user can choose it explicitly.
            let tolerance: Float = 5.0
            selectedPeakIDs = Set(
                peaks.filter { newPeak in
                    previouslySelectedFrequencies.contains { oldFreq in
                        abs(newPeak.frequency - oldFreq) <= tolerance
                    }
                }.map { $0.id }
            )
        } else {
            // No user changes yet: re-run the mode-priority auto-selection.
            selectedPeakIDs = guitarModeSelectedPeakIDs(from: peaks)
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
        let peaks = currentPeaks
        guard !peaks.isEmpty else { return }
        selectedPeakIDs = guitarModeSelectedPeakIDs(from: peaks)
    }

    /// Finds all significant spectral peaks within the configured frequency range.
    ///
    /// The algorithm uses a two-pass strategy with mode-priority selection:
    ///
    /// **Pass 1 — Known modes:**
    /// Scans each mode's band from ``GuitarType/modeRanges`` for local maxima
    /// that exceed ``TapToneAnalyzer/peakThreshold``. Tracks the strongest peak
    /// per canonical mode name so each guitar mode always gets a guaranteed slot
    /// in the output.
    ///
    /// **Pass 2 — Unknown/inter-mode peaks:**
    /// Scans the entire configured frequency window for local maxima that fall
    /// outside all known mode ranges.
    ///
    /// **Step 3 — Assembly:**
    /// The strongest peak from each mode occupies a guaranteed slot. Remaining
    /// slots (up to ``TapToneAnalyzer/maxPeaks``) are filled by magnitude.
    /// When `maxPeaks == 0` all found peaks are returned.
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
    /// - Returns: Array of ``ResonantPeak`` values sorted by magnitude
    ///   (descending).
    func findPeaks(magnitudes: [Float], frequencies: [Float], minHz: Float? = nil, maxHz: Float? = nil) -> [ResonantPeak] {
        guard magnitudes.count == frequencies.count else { return [] }
        
        var allPeaks: [ResonantPeak] = []
        let windowSize = 5  // Look at ±5 bins around each point
        
        // Find frequency range indices — caller can override the analysis window
        let loFreq = minHz ?? minFrequency
        let hiFreq = maxHz ?? maxFrequency
        let startIdx = frequencies.firstIndex(where: { $0 >= loFreq }) ?? 0
        let endIdx = frequencies.firstIndex(where: { $0 > hiFreq }) ?? frequencies.count - 1
        
        // Define all known modes to search for (excluding unknown).
        // Use canonical modern cases only — legacy aliases normalise to the same
        // modeRange and would cause the same physical peak to be found twice,
        // landing it in two separate guaranteed slots.
        let knownModes: [GuitarMode] = [.air, .top, .back, .dipole, .ringMode, .upperModes]
        
        // Track the strongest peak found in each mode range
        var strongestPeakPerMode: [GuitarMode: ResonantPeak] = [:]
        
        // Step 1: Search known mode ranges for peaks.
        // Uses modeRanges (the classification bands shown in Settings) so that
        // peak detection covers the same frequency window the user sees.
        let guitarType = TapDisplaySettings.guitarType
        for mode in knownModes {
            let modeRange = mode.modeRange(for: guitarType)
            let normalizedMode = mode.normalized
            
            // Find indices for this mode's range, clamped to the analysis window.
            // A mode whose range extends beyond the window (e.g. upperModes goes to 20 kHz
            // but the display window ends at 2 kHz) is still scanned within the window.
            let modeStartIdx = max(frequencies.firstIndex(where: { $0 >= modeRange.lowerBound }) ?? startIdx, startIdx)
            let modeEndIdx   = min(frequencies.firstIndex(where: { $0 > modeRange.upperBound }) ?? endIdx, endIdx)

            // Skip if the mode range doesn't intersect the analysis window at all
            guard modeStartIdx < modeEndIdx else { continue }

            // Scan for local maxima within this mode's range
            let scanStart = max(modeStartIdx, startIdx + windowSize)
            let scanEnd = min(modeEndIdx, endIdx - windowSize)
            guard scanStart < scanEnd else { continue }
            for i in scanStart..<scanEnd {
                let magnitude = magnitudes[i]
                
                // Skip if below threshold
                guard magnitude > peakThreshold else { continue }
                
                // Check if local maximum
                var isLocalMax = true
                for offset in -windowSize...windowSize where offset != 0 {
                    if magnitudes[i + offset] >= magnitude {
                        isLocalMax = false
                        break
                    }
                }
                
                guard isLocalMax else { continue }
                
                // Refine peak location and magnitude with parabolic interpolation
                let (interpFreq, interpMag) = parabolicInterpolate(magnitudes: magnitudes, frequencies: frequencies, peakIndex: i)
                
                // Calculate Q factor using interpolated peak magnitude for accurate -3 dB threshold
                let (quality, bandwidth) = calculateQFactor(magnitudes: magnitudes, frequencies: frequencies, peakIndex: i, peakMagnitude: interpMag)
                
                // Calculate pitch information from interpolated frequency
                let freq = Double(interpFreq)
                let pitchNote = pitchCalculator.note(frequency: freq)
                let pitchCents = pitchCalculator.cents(frequency: freq)
                let pitchFreq = pitchCalculator.freq0(frequency: freq)
                
                let peak = ResonantPeak(
                    frequency: interpFreq,
                    magnitude: interpMag,
                    quality: quality,
                    bandwidth: bandwidth,
                    pitchNote: pitchNote,
                    pitchCents: pitchCents,
                    pitchFrequency: pitchFreq
                )
                allPeaks.append(peak)
                
                // Track strongest peak for this mode
                if let existing = strongestPeakPerMode[normalizedMode] {
                    if magnitude > existing.magnitude {
                        strongestPeakPerMode[normalizedMode] = peak
                    }
                } else {
                    strongestPeakPerMode[normalizedMode] = peak
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
                guard magnitude > peakThreshold else { continue }
                
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
                
                // Refine peak location and magnitude with parabolic interpolation
                let (interpFreq, interpMag) = parabolicInterpolate(magnitudes: magnitudes, frequencies: frequencies, peakIndex: i)
                
                // Calculate Q factor using interpolated peak magnitude for accurate -3 dB threshold
                let (quality, bandwidth) = calculateQFactor(magnitudes: magnitudes, frequencies: frequencies, peakIndex: i, peakMagnitude: interpMag)
                
                // Calculate pitch information from interpolated frequency
                let freq = Double(interpFreq)
                let pitchNote = pitchCalculator.note(frequency: freq)
                let pitchCents = pitchCalculator.cents(frequency: freq)
                let pitchFreq = pitchCalculator.freq0(frequency: freq)
                
                let peak = ResonantPeak(
                    frequency: interpFreq,
                    magnitude: interpMag,
                    quality: quality,
                    bandwidth: bandwidth,
                    pitchNote: pitchNote,
                    pitchCents: pitchCents,
                    pitchFrequency: pitchFreq
                )
                allPeaks.append(peak)
            }
        }
        
        // Remove duplicate peaks (in case of overlap)
        allPeaks = removeDuplicatePeaks(allPeaks)
        
        // Step 3: Build final peak list with mode priority.
        // First, include the strongest peak from each known mode (guaranteed slots).
        var finalPeaks: [ResonantPeak] = []
        var includedPeakIDs = Set<UUID>()
        
        for (_, peak) in strongestPeakPerMode {
            finalPeaks.append(peak)
            includedPeakIDs.insert(peak.id)
        }
        
        // Then fill remaining slots with other peaks by magnitude.
        // maxPeaks == 0 means "capture all peaks".
        if maxPeaks == 0 {
            // Add all remaining peaks (no limit)
            let otherPeaks = allPeaks
                .filter { !includedPeakIDs.contains($0.id) }
                .sorted { $0.magnitude > $1.magnitude }
            finalPeaks.append(contentsOf: otherPeaks)
        } else {
            let remainingSlots = maxPeaks - finalPeaks.count
            if remainingSlots > 0 {
                let otherPeaks = allPeaks
                    .filter { !includedPeakIDs.contains($0.id) }
                    .sorted { $0.magnitude > $1.magnitude }
                    .prefix(remainingSlots)
                finalPeaks.append(contentsOf: otherPeaks)
            }
        }
        
        // Sort final result by magnitude descending
        return finalPeaks.sorted(by: { $0.magnitude > $1.magnitude })
    }
    
    /// Selects one peak per guitar mode using a lowest-frequency-first priority
    /// rule, so overlapping mode ranges always resolve in favour of the lower mode.
    ///
    /// The algorithm:
    /// 1. Orders known modes by the lower bound of their ``GuitarType/modeRanges``
    ///    band, ascending.
    /// 2. Walks them in that order. For each mode it picks the highest-magnitude
    ///    peak whose frequency lies inside the mode's range and has not already
    ///    been claimed by a lower-frequency mode.
    /// 3. Claiming is done by both UUID and frequency proximity (±3 Hz), so when
    ///    overlapping mode ranges cause `findPeaks` to produce two near-duplicate
    ///    entries for the same physical resonance, the second mode cannot re-select it.
    /// 4. Returns the `UUID` set of the selected peaks.
    ///
    /// Peaks whose frequency falls outside all mode ranges (`.unknown`) are
    /// **not** auto-selected; the user can toggle them individually in the
    /// results panel.
    ///
    /// - Parameter peaks: The candidate peak array to select from. Defaults
    ///   to `currentPeaks`.
    /// - Returns: A `Set<UUID>` containing at most one peak ID per mode.
    func guitarModeSelectedPeakIDs(from peaks: [ResonantPeak]? = nil) -> Set<UUID> {
        let candidates = peaks ?? currentPeaks
        let guitarType = TapDisplaySettings.guitarType

        // Canonical modern modes ordered by ascending lower-bound of their classification range.
        // Legacy cases are excluded because findPeaks() works with normalised modes.
        let orderedModes: [GuitarMode] = [.air, .top, .back, .dipole, .ringMode, .upperModes]
            .sorted { $0.modeRange(for: guitarType).lowerBound < $1.modeRange(for: guitarType).lowerBound }

        var selected = Set<UUID>()
        // Track claimed frequencies (not just IDs) so that when mode ranges overlap
        // and findPeaks produces two near-duplicate peaks at the same physical frequency,
        // the second mode doesn't re-select what is effectively the same resonance.
        var claimedFrequencies: [Float] = []
        let duplicateTolerance: Float = 3.0   // Hz — tighter than removeDuplicatePeaks (2 Hz) + interpolation jitter

        for mode in orderedModes {
            let range = mode.modeRange(for: guitarType)
            // Find the highest-magnitude peak within this mode's range that has not
            // already been claimed by a lower-frequency mode (by ID or by frequency proximity).
            if let best = candidates
                .filter({ peak in
                    range.contains(peak.frequency) &&
                    !selected.contains(peak.id) &&
                    !claimedFrequencies.contains(where: { abs($0 - peak.frequency) <= duplicateTolerance })
                })
                .max(by: { $0.magnitude < $1.magnitude }) {
                selected.insert(best.id)
                claimedFrequencies.append(best.frequency)
            }
        }
        return selected
    }

    /// Re-runs mode classification on `currentPeaks` using the active guitar
    /// type's frequency ranges.
    ///
    /// Call this after the user changes the guitar type (acoustic ↔ classical)
    /// so that `identifiedModes` stays consistent with the updated
    /// ``GuitarMode/modeRange`` boundaries without requiring a new tap.
    func reclassifyPeaks() {
        identifiedModes = currentPeaks.map { peak in
            (peak: peak, mode: GuitarMode.classify(frequency: peak.frequency))
        }
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
        let frequencyTolerance: Float = 2.0  // Hz - peaks closer than this are considered duplicates
        
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
