//
//  TapToneAnalyzer+SpectrumCapture.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

/// # TapToneAnalyzer+SpectrumCapture
///
/// Implements the gated-FFT capture pipeline used for plate and brace
/// measurements, along with the frequency-domain spectrum averaging used
/// for both multi-tap guitar and material measurements.
///
/// ## Gated FFT Architecture
/// The continuous FFT operates on a fixed long window (≈ 400 ms at the
/// `gatedCaptureDuration` constant). For guitar measurements this is fine
/// because the tap-detection threshold ensures we see the ring-out. For
/// plate and brace measurements the ring-out is much shorter and the
/// transient tap energy is spread across the full window, reducing the
/// apparent peak magnitude by up to ~15 dB.
///
/// The gated approach captures *raw PCM samples* starting just before the
/// tap onset (via the pre-roll buffer) and running until the window fills:
///
/// ```
/// ┌────────────────────────────────────┐
/// │  200 ms pre-roll  │  400 ms gate   │
/// │  (ring buffer)    │  (new samples) │
/// └────────────────────────────────────┘
///               ↑ tap onset
/// ```
///
/// The pre-roll ring buffer (``preRollBuffer``) holds the most recent
/// `preRollSamples` worth of audio at all times.  When
/// ``startGatedCapture(phase:)`` is called, the pre-roll is immediately
/// seeded into ``gatedAccumBuffer`` so the tap attack transient — which
/// arrived slightly before the detection event — is included in the
/// captured window.
///
/// ## Dominant Peak Selection — HPS + Q filter
/// ``findDominantPeak(magnitudes:frequencies:minHz:maxHz:preferLowestSignificant:)``
/// uses a two-stage strategy:
///
/// 1. **Q filtering**: candidates with Q < 3 are rejected as impact thuds
///    or broadband noise (real material resonances have Q ≥ 3 even in a
///    short 400 ms window).
/// 2. **Magnitude + HPS tie-breaking**: the highest-magnitude remaining
///    candidate wins unless a lower-frequency candidate is within 6 dB
///    and has a comparable HPS score (within 1 order of magnitude),
///    in which case the lower-frequency fundamental is preferred.
///
/// HPS (Harmonic Product Spectrum) is computed up to the 3rd harmonic:
/// ```
/// HPS(i) = linear(i) × linear(2i) × linear(3i)
/// ```
/// where `linear(i) = 10^(magnitudes[i] / 20)`.
///
/// ## Frequency-Domain Power Averaging
/// Multiple taps from the same phase are averaged in the **linear power
/// domain** before peak detection runs on the average:
/// ```
/// p_avg = (1/N) × Σ 10^(dB_n / 10)       [per bin]
/// dB_avg = 10 × log10(p_avg)
/// ```
/// Averaging power (rather than amplitude or dB) is the physically correct
/// approach for non-periodic impulse responses where inter-tap phase
/// alignment cannot be guaranteed.

import Foundation

extension TapToneAnalyzer {

    // MARK: - Gated FFT Capture (Plate/Brace)

    /// Receives raw PCM samples from the audio engine and maintains both the
    /// pre-roll ring buffer and the active gated capture buffer.
    ///
    /// Called on `audioProcessingQueue` for every incoming audio buffer.
    /// When `gatedCaptureActive` is `true`, incoming samples are appended
    /// to `gatedAccumBuffer`. When the buffer reaches `gatedCaptureSamples`
    /// the capture is closed and `finishGatedFFTCapture` is dispatched to
    /// the main thread.
    ///
    /// - Parameters:
    ///   - samples: Raw PCM samples (mono, normalised to ±1.0) from the
    ///     current audio buffer.
    ///   - sampleRate: The current hardware sample rate in Hz. Stored as
    ///     `mpmSampleRate` for use in the FFT computation.
    ///
    /// - Note: This method is **not** thread-safe without the surrounding
    ///   `mpmLock` NSLock; all access to `preRollBuffer` and
    ///   `gatedAccumBuffer` is protected by that lock.
    func accumulateGatedSamples(_ samples: [Float], sampleRate: Double) {
        mpmSampleRate = sampleRate

        mpmLock.lock()

        // Always maintain the pre-roll ring buffer so that when a tap is detected
        // the most recent `preRollSamples` worth of audio (including the tap attack)
        // can be prepended to the gated window.
        preRollBuffer.append(contentsOf: samples)
        let maxPreRoll = preRollSamples
        if preRollBuffer.count > maxPreRoll {
            preRollBuffer.removeFirst(preRollBuffer.count - maxPreRoll)
        }

        guard gatedCaptureActive else {
            mpmLock.unlock()
            return
        }

        gatedAccumBuffer.append(contentsOf: samples)
        let count = gatedAccumBuffer.count
        mpmLock.unlock()

        if count >= gatedCaptureSamples {
            gatedCaptureActive = false
            let captured: [Float]
            let phase = gatedCapturePhase
            mpmLock.lock()
            captured = Array(gatedAccumBuffer.prefix(gatedCaptureSamples))
            gatedAccumBuffer = []
            mpmLock.unlock()

            DispatchQueue.main.async { [weak self] in
                self?.finishGatedFFTCapture(samples: captured, sampleRate: sampleRate, phase: phase)
            }
        }
    }

    /// Opens a raw-PCM capture window for the current plate/brace phase.
    ///
    /// Seeds `gatedAccumBuffer` with the pre-roll contents so the tap attack
    /// transient (which arrived slightly before this call) is included in
    /// the captured window. Sets `gatedCaptureActive = true` to start
    /// accumulating new samples via ``accumulateGatedSamples(_:sampleRate:)``.
    ///
    /// A safety timeout fires after 2 seconds: if the buffer still has audio
    /// at that point, it is flushed to `finishGatedFFTCapture(samples:sampleRate:phase:)`; if empty,
    /// the user is prompted to tap again.
    ///
    /// - Parameter phase: The ``MaterialTapPhase`` being captured. Stored as
    ///   `gatedCapturePhase` so the phase handler can be routed correctly
    ///   when the window closes.
    func startGatedCapture(phase: MaterialTapPhase) {
        mpmLock.lock()
        // Seed the gated buffer with the pre-roll contents so the tap attack transient
        // (which arrived before this call) is included in the captured window.
        gatedAccumBuffer = preRollBuffer
        mpmLock.unlock()
        gatedCapturePhase = phase
        gatedCaptureActive = true

        let windowMs = Int(TapToneAnalyzer.gatedCaptureDuration * 1000)
        print("🎯 Gated FFT capture started for phase \(phase) — \(gatedCaptureSamples)-sample window (\(windowMs) ms at \(Int(mpmSampleRate)) Hz)")

        // Safety timeout: close capture window after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, self.gatedCaptureActive else { return }
            self.gatedCaptureActive = false
            self.mpmLock.lock()
            let partial = self.gatedAccumBuffer
            self.gatedAccumBuffer = []
            self.mpmLock.unlock()
            if !partial.isEmpty {
                self.finishGatedFFTCapture(samples: partial, sampleRate: self.mpmSampleRate, phase: phase)
            } else {
                print("⚠️ Gated capture timeout with no samples — tap again")
                self.statusMessage = "No signal detected — tap again"
                self.reEnableDetectionForNextPlateTap()
            }
        }
    }

    /// Processes the captured PCM window and routes the result to the
    /// appropriate phase handler.
    ///
    /// Runs `RealtimeFFTAnalyzer.computeGatedFFT` to transform the raw
    /// samples into a magnitude spectrum. Applies a phase-specific frequency
    /// search window and calls ``findDominantPeak(magnitudes:frequencies:minHz:maxHz:preferLowestSignificant:)``
    /// to identify the strongest material resonance.
    ///
    /// Rejects the capture and requests a re-tap if:
    /// - The FFT returns an empty spectrum.
    /// - No peak is found in the search window.
    /// - The dominant peak is below `tapDetectionThreshold` (weak tap).
    ///
    /// The per-phase frequency search windows are:
    ///
    /// | Mode / Phase | Min Hz | Max Hz |
    /// |---|---|---|
    /// | Brace (longitudinal) | 100 | 1200 |
    /// | Plate — longitudinal | 50 | 500 |
    /// | Plate — cross-grain | 20 | 250 |
    /// | Plate — FLC | 20 | 200 |
    ///
    /// - Parameters:
    ///   - samples: Captured PCM samples (pre-roll + gate window).
    ///   - sampleRate: Hardware sample rate in Hz.
    ///   - phase: The ``MaterialTapPhase`` active at capture time.
    ///
    /// - Note: Called on the main thread via `DispatchQueue.main.async`.
    func finishGatedFFTCapture(samples: [Float], sampleRate: Double, phase: MaterialTapPhase) {
        let (magnitudes, frequencies) = fftAnalyzer.computeGatedFFT(samples: samples, sampleRate: sampleRate)

        guard !magnitudes.isEmpty else {
            print("⚠️ Gated FFT returned empty spectrum — tap again")
            statusMessage = "No signal detected — tap again"
            reEnableDetectionForNextPlateTap()
            return
        }

        // Determine the frequency search window for this phase.
        // Using per-phase windows rejects out-of-range peaks that would otherwise
        // compete with the true resonance.
        let mType = TapDisplaySettings.measurementType
        let hpsMinHz: Float
        let hpsMaxHz: Float
        switch mType {
        case .brace:
            // Brace bars resonate 100–1000 Hz; exclude sub-100 Hz table/impact thud
            hpsMinHz = 100; hpsMaxHz = 1200
        case .plate:
            switch phase {
            case .capturingLongitudinal:
                // fL: longitudinal stiffness mode, typically 70–400 Hz
                hpsMinHz = 50; hpsMaxHz = 500
            case .capturingCross, .waitingForCrossTap:
                // fC: cross-grain stiffness mode, typically 30–200 Hz
                hpsMinHz = 20; hpsMaxHz = 250
            case .capturingFlc, .waitingForFlcTap:
                // fLC: shear/diagonal mode, typically 20–150 Hz — tighter cap to avoid
                // harmonics and other plate modes competing with the true shear fundamental
                hpsMinHz = 20; hpsMaxHz = 200
            default:
                hpsMinHz = 20; hpsMaxHz = 600
            }
        default:
            hpsMinHz = 20; hpsMaxHz = 2000
        }

        // For all three plate phases the tap orientation physically selects the lowest
        // resonant mode of the plate (longitudinal, cross-grain, or shear), so always
        // prefer the lowest significant peak in the search window.
        let preferLowest = (mType == .plate || phase == .capturingLongitudinal || phase == .capturingCross)

        // Find the dominant peak using harmonic product spectrum analysis.
        // This finds the fundamental regardless of whether harmonics are louder.
        guard let dominantPeak = findDominantPeak(magnitudes: magnitudes,
                                                   frequencies: frequencies,
                                                   minHz: hpsMinHz,
                                                   maxHz: hpsMaxHz,
                                                   preferLowestSignificant: preferLowest) else {
            print("⚠️ Gated FFT: no peak found — tap again")
            statusMessage = "No resonance detected — tap again"
            reEnableDetectionForNextPlateTap()
            return
        }

        // Reject captures where the dominant peak is below the tap detection threshold.
        // If the best peak found is below the threshold, the ring-out was too weak —
        // likely a noise trigger, not a real tap — so ask the user to tap again.
        if dominantPeak.magnitude < tapDetectionThreshold {
            print("⚠️ Gated FFT: dominant peak \(String(format: "%.1f", dominantPeak.frequency)) Hz @ \(String(format: "%.1f", dominantPeak.magnitude)) dB is below tap detection threshold (\(String(format: "%.0f", tapDetectionThreshold)) dB) — tap again")
            statusMessage = "Signal too quiet — tap harder"
            reEnableDetectionForNextPlateTap()
            return
        }

        print("📊 Gated FFT complete: \(magnitudes.count) bins, dominant peak \(String(format: "%.1f", dominantPeak.frequency)) Hz @ \(String(format: "%.1f", dominantPeak.magnitude)) dB, phase \(phase)")

        // Store spectrum so the UI can display it and the user can select alternate peaks
        materialCapturedTaps.append((magnitudes: magnitudes, frequencies: frequencies, captureTime: Date()))
        currentTapCount += 1
        tapProgress = Float(currentTapCount) / Float(totalPlateTaps)

        // Route to phase handler, passing the full spectrum for display and the
        // dominant peak for auto-selection.
        switch phase {
        case .capturingLongitudinal:
            handleLongitudinalGatedProgress(magnitudes: magnitudes,
                                            frequencies: frequencies,
                                            dominantPeak: dominantPeak)
        case .capturingCross, .waitingForCrossTap:
            handleCrossGatedProgress(magnitudes: magnitudes,
                                     frequencies: frequencies,
                                     dominantPeak: dominantPeak)
        case .capturingFlc, .waitingForFlcTap:
            handleFlcGatedProgress(magnitudes: magnitudes,
                                   frequencies: frequencies,
                                   dominantPeak: dominantPeak)
        case .notStarted, .complete:
            print("⚠️ Unexpected gated FFT capture in phase: \(phase)")
        }
    }

    /// Selects the dominant resonance peak from a gated-FFT spectrum.
    ///
    /// The algorithm operates in two steps:
    ///
    /// **Step 1 — Candidate collection:** Find all local maxima above the
    /// median (noise floor) of the search range. For each candidate, compute:
    /// - Raw magnitude (dB).
    /// - HPS score: `linear[i] × linear[2i] × linear[3i]` (order 3).
    /// - Q factor via the −3 dB bandwidth method.
    ///
    /// **Step 2 — Selection:**
    /// - Filter out candidates with Q < 3 (impact thuds / broadband noise).
    /// - If `preferLowestSignificant` is `true` (plate/brace longitudinal and
    ///   cross-grain phases): among Q-filtered candidates, pick the
    ///   lowest-frequency one within 15 dB of the strongest.
    /// - Otherwise: the highest-magnitude candidate wins unless a
    ///   lower-frequency candidate is within 6 dB and has an HPS score
    ///   within one order of magnitude (prefers fundamental over harmonics).
    ///
    /// The winner's frequency and magnitude are refined with parabolic
    /// interpolation before being returned.
    ///
    /// - Parameters:
    ///   - magnitudes: dBFS magnitude spectrum from the gated FFT.
    ///   - frequencies: Frequency axis matching `magnitudes`, in Hz.
    ///   - minHz: Lower search bound in Hz. Defaults to 20 Hz.
    ///   - maxHz: Upper search bound in Hz. Defaults to 2000 Hz.
    ///   - preferLowestSignificant: When `true`, the lowest-frequency
    ///     candidate within 15 dB of the peak is chosen instead of the
    ///     highest-magnitude candidate. Use for longitudinal and cross-grain
    ///     phases where the tap orientation selects the plate's fundamental.
    /// - Returns: The best ``ResonantPeak``, or `nil` if no candidates are
    ///   found above the adaptive noise floor.
    func findDominantPeak(magnitudes: [Float],
                          frequencies: [Float],
                          minHz: Float = 20,
                          maxHz: Float = 2000,
                          preferLowestSignificant: Bool = false) -> ResonantPeak? {
        guard magnitudes.count == frequencies.count, magnitudes.count > 10 else { return nil }

        let n = magnitudes.count
        let startIdx = frequencies.firstIndex(where: { $0 >= minHz }) ?? 0
        let endIdx   = frequencies.firstIndex(where: { $0 > maxHz }) ?? n
        guard startIdx < endIdx else { return nil }

        // --- Step 1: find all local maxima in the search range ---
        // Use a window of ±5 bins (wider than HPS windowSize=3) to avoid picking
        // shoulders of broad low-frequency peaks.
        let windowSize = 5

        // Compute an adaptive noise floor from the median of the search range so
        // that very quiet gated captures aren't dominated by DC/noise bins.
        let searchMags = Array(magnitudes[startIdx..<endIdx])
        let sortedMags = searchMags.sorted()
        let noiseFloor: Float = sortedMags[sortedMags.count / 2]  // median

        struct Candidate {
            let index: Int
            let magnitude: Float
            let hpsScore: Float
            let qFactor: Float
        }
        var candidates: [Candidate] = []

        // Pre-compute linear amplitudes for HPS scoring
        let linear = magnitudes.map { pow(10.0, max($0, -160) / 20.0) }

        for i in (startIdx + windowSize)..<(endIdx - windowSize) {
            let mag = magnitudes[i]
            guard mag > noiseFloor else { continue }

            // Local maximum check
            var isLocal = true
            for offset in -windowSize...windowSize where offset != 0 {
                if magnitudes[i + offset] >= mag { isLocal = false; break }
            }
            guard isLocal else { continue }

            // HPS score: product of fundamental and up to 3 harmonics (order 3 to
            // avoid the n/hpsOrder constraint cutting off low-frequency candidates).
            var hpsScore = linear[i]
            for k in 2...3 {
                let harmIdx = i * k
                if harmIdx < n { hpsScore *= linear[harmIdx] }
            }

            // Q factor: the key discriminant between material resonances (high Q,
            // narrow peak) and impact thuds / ambient noise (low Q, broad smear).
            // A well-tapped brace or plate resonance typically has Q > 10.
            // Impact contact noise and table rumble rarely exceed Q ~ 3–5.
            let (q, _) = calculateQFactor(magnitudes: magnitudes, frequencies: frequencies,
                                          peakIndex: i, peakMagnitude: mag)

            candidates.append(Candidate(index: i, magnitude: mag, hpsScore: hpsScore, qFactor: q))
        }

        guard !candidates.isEmpty else { return nil }

        // --- Step 2: pick the best candidate ---
        // Prefer high-Q candidates (material resonances) over low-Q ones (impact thuds).
        // Q < 3 reliably identifies impact contact smear and broadband noise (seen at
        // Q=1.9–2.3 in practice). Real tap-tone resonances — even weak ones in a short
        // 400 ms gated window — rarely fall below Q=3.
        // If no candidate clears the Q threshold, fall back to all candidates so we
        // always return something the user can manually override.
        let minQ: Float = 3.0
        let highQCandidates = candidates.filter { $0.qFactor >= minQ }
        if highQCandidates.count < candidates.count {
            let rejected = candidates.filter { $0.qFactor < minQ }
            let rejStr = rejected.map { String(format: "%.0f Hz (Q=%.1f)", frequencies[$0.index], $0.qFactor) }.joined(separator: ", ")
            print("🔇 Q-filtered out low-Q peaks: \(rejStr)")
        }
        let pool = highQCandidates.isEmpty ? candidates : highQCandidates

        let byMagnitude = pool.sorted { $0.magnitude > $1.magnitude }
        let strongest = byMagnitude[0]

        let best: Candidate
        if preferLowestSignificant {
            // For longitudinal and cross-grain taps the tap orientation physically
            // selects the plate's fundamental (lowest) resonant mode.
            // Among Q-filtered candidates, pick the lowest-frequency one within 15 dB
            // of the strongest. Q filtering handles thud rejection; 15 dB is tight
            // enough to exclude distant ambient resonances while tolerating a genuine
            // fundamental that is a bit quieter than its harmonics.
            let thresholdDB = strongest.magnitude - 15.0
            let significant = pool.filter { $0.magnitude >= thresholdDB }
            best = significant.min(by: { $0.index < $1.index }) ?? strongest
        } else {
            // Default: strongest peak wins unless a lower-frequency candidate has a
            // comparable HPS score (within one order of magnitude) AND is within 6 dB.
            var current = strongest
            for candidate in byMagnitude.dropFirst() {
                guard candidate.index < current.index else { continue }
                let magDiff = current.magnitude - candidate.magnitude
                if magDiff < 6.0 && candidate.hpsScore >= current.hpsScore * 0.1 {
                    current = candidate
                }
            }
            best = current
        }

        // Refine the winning candidate's frequency and magnitude with parabolic interpolation
        let (freq, mag) = parabolicInterpolate(magnitudes: magnitudes, frequencies: frequencies, peakIndex: best.index)
        let (quality, bandwidth) = calculateQFactor(magnitudes: magnitudes,
                                                    frequencies: frequencies,
                                                    peakIndex: best.index,
                                                    peakMagnitude: mag)
        let pitchNote  = pitchCalculator.note(frequency: Double(freq))
        let pitchCents = pitchCalculator.cents(frequency: Double(freq))
        let pitchFreq  = pitchCalculator.freq0(frequency: Double(freq))
        print("🎯 Dominant peak: \(String(format: "%.1f", freq)) Hz @ \(String(format: "%.1f", mag)) dB (Q: \(String(format: "%.1f", best.qFactor)), HPS score: \(String(format: "%.3e", best.hpsScore)))")
        return ResonantPeak(frequency: freq, magnitude: mag,
                            quality: quality, bandwidth: bandwidth,
                            pitchNote: pitchNote, pitchCents: pitchCents,
                            pitchFrequency: pitchFreq)
    }

    /// Gated-FFT handler for the longitudinal capture phase.
    ///
    /// Mirrors ``handleLongitudinalTapProgress(magnitudes:frequencies:)`` but
    /// uses the pre-computed `dominantPeak` from `findDominantPeak` instead of
    /// re-running `findPeaks`. Also calls
    /// ``buildAllPeaks(magnitudes:frequencies:dominantPeak:)`` to populate the
    /// full peak list for manual override.
    ///
    /// Transitions to `.waitingForCrossTap` (plate) or `.complete` (brace)
    /// when `numberOfTaps` longitudinal taps have been collected.
    ///
    /// - Parameters:
    ///   - magnitudes: Averaged gated-FFT magnitude spectrum (dBFS).
    ///   - frequencies: Frequency axis matching `magnitudes`, in Hz.
    ///   - dominantPeak: The pre-selected dominant peak from this tap.
    func handleLongitudinalGatedProgress(magnitudes: [Float],
                                         frequencies: [Float],
                                         dominantPeak: ResonantPeak) {
        let captured = materialCapturedTaps.count
        let total = numberOfTaps
        print("📊 Gated LONGITUDINAL tap \(captured)/\(total): \(String(format: "%.1f", dominantPeak.frequency)) Hz")

        if captured < total {
            statusMessage = "L tap \(captured)/\(total) captured. Tap again..."
            reEnableDetectionForNextPlateTap()
            return
        }

        // Average all captured spectra for display
        let (avgMags, avgFreqs) = averageSpectra(from: materialCapturedTaps)
        longitudinalSpectrum = (magnitudes: avgMags, frequencies: avgFreqs)

        // Build the full peak list for display/manual override, but auto-select the
        // dominant peak from the most recent (or averaged) tap.
        longitudinalPeaks = buildAllPeaks(magnitudes: avgMags, frequencies: avgFreqs,
                                          dominantPeak: dominantPeak)
        autoSelectedLongitudinalPeakID = dominantPeak.id
        selectedLongitudinalPeak = longitudinalPeaks.first(where: { $0.id == dominantPeak.id }) ?? dominantPeak
        print("🔵 Auto-selected longitudinal peak: \(dominantPeak.frequency) Hz")

        frozenFrequencies = avgFreqs
        frozenMagnitudes  = avgMags
        isSpectrumFrozen  = true
        currentPeaks      = longitudinalPeaks
        selectedPeakIDs   = Set(longitudinalPeaks.map { $0.id })
        materialCapturedTaps = []

        let isBrace = TapDisplaySettings.measurementType == .brace
        if isBrace {
            if let selPeak = longitudinalPeaks.first(where: { $0.id == dominantPeak.id }) {
                currentPeaks = [selPeak]
            } else {
                currentPeaks = [dominantPeak]
            }
            isSpectrumFrozen = false; frozenFrequencies = []; frozenMagnitudes = []
            materialTapPhase = .complete
            tapProgress = 1.0
            statusMessage = "Complete - check Results"
            print("✅ Brace measurement complete: fL=\(dominantPeak.frequency) Hz")
        } else {
            materialTapPhase = .waitingForCrossTap
            statusMessage = "fL: \(String(format: "%.1f", dominantPeak.frequency)) Hz — rotate 90° for C tap"
            DispatchQueue.main.asyncAfter(deadline: .now() + tapCooldown) { [weak self] in
                guard let self = self else { return }
                self.isAboveThreshold = self.fftAnalyzer.inputLevelDB > (self.tapDetectionThreshold - self.hysteresisMargin)
                self.isDetecting = true; self.tapDetected = false
                self.materialTapPhase = .capturingCross
                self.isSpectrumFrozen = false; self.frozenFrequencies = []; self.frozenMagnitudes = []
                self.analyzerStartTime = Date()
            }
        }
    }

    /// Gated-FFT handler for the cross-grain capture phase.
    ///
    /// Accumulates cross-grain taps until `numberOfTaps` have been collected.
    /// Averages all captured spectra, auto-selects the best cross-grain peak,
    /// and either transitions to `.waitingForFlcTap` (FLC enabled) or marks
    /// the measurement `.complete`.
    ///
    /// - Parameters:
    ///   - magnitudes: Current gated-FFT magnitude spectrum (dBFS).
    ///   - frequencies: Frequency axis matching `magnitudes`, in Hz.
    ///   - dominantPeak: The pre-selected dominant peak from this tap.
    func handleCrossGatedProgress(magnitudes: [Float],
                                   frequencies: [Float],
                                   dominantPeak: ResonantPeak) {
        let captured = materialCapturedTaps.count
        let total = numberOfTaps
        print("📊 Gated CROSS-GRAIN tap \(captured)/\(total): \(String(format: "%.1f", dominantPeak.frequency)) Hz")

        if captured < total {
            statusMessage = "C tap \(captured)/\(total) captured. Tap again..."
            reEnableDetectionForNextPlateTap()
            return
        }

        let (avgMags, avgFreqs) = averageSpectra(from: materialCapturedTaps)
        crossSpectrum = (magnitudes: avgMags, frequencies: avgFreqs)
        crossPeaks = buildAllPeaks(magnitudes: avgMags, frequencies: avgFreqs, dominantPeak: dominantPeak)
        autoSelectedCrossPeakID = dominantPeak.id
        selectedCrossPeak = crossPeaks.first(where: { $0.id == dominantPeak.id }) ?? dominantPeak
        print("🟠 Auto-selected cross-grain peak: \(dominantPeak.frequency) Hz")
        materialCapturedTaps = []

        if TapDisplaySettings.measureFlc {
            currentPeaks = combinePlatePeaks()
            frozenFrequencies = avgFreqs; frozenMagnitudes = avgMags; isSpectrumFrozen = true
            materialTapPhase = .waitingForFlcTap
            statusMessage = "fC: \(String(format: "%.1f", dominantPeak.frequency)) Hz — set up for FLC tap"
            DispatchQueue.main.asyncAfter(deadline: .now() + tapCooldown) { [weak self] in
                guard let self = self else { return }
                self.isAboveThreshold = self.fftAnalyzer.inputLevelDB > (self.tapDetectionThreshold - self.hysteresisMargin)
                self.isDetecting = true; self.tapDetected = false
                self.materialTapPhase = .capturingFlc
                self.isSpectrumFrozen = false; self.frozenFrequencies = []; self.frozenMagnitudes = []
                self.analyzerStartTime = Date()
            }
        } else {
            var sel: [ResonantPeak] = []
            if let p = selectedLongitudinalPeak { sel.append(p) }
            else if let p = longitudinalPeaks.first { sel.append(p) }
            sel.append(selectedCrossPeak ?? dominantPeak)
            currentPeaks = sel
            selectedPeakIDs = Set(sel.map { $0.id })
            isSpectrumFrozen = false; frozenFrequencies = []; frozenMagnitudes = []
            materialTapPhase = .complete; tapProgress = 1.0
            let fLStr = selectedLongitudinalPeak.map { String(format: "%.1f", $0.frequency) } ?? "?"
            statusMessage = "Complete — fL: \(fLStr) Hz, fC: \(String(format: "%.1f", dominantPeak.frequency)) Hz"
            print("✅ Plate complete: fL=\(fLStr) Hz, fC=\(dominantPeak.frequency) Hz")
        }
    }

    /// Gated-FFT handler for the FLC (shear/diagonal) capture phase.
    ///
    /// Accumulates FLC taps until `numberOfTaps` have been collected, then
    /// averages all captured spectra, auto-selects the best FLC peak, and
    /// marks the measurement `.complete` with all three phase peaks populated.
    ///
    /// - Parameters:
    ///   - magnitudes: Current gated-FFT magnitude spectrum (dBFS).
    ///   - frequencies: Frequency axis matching `magnitudes`, in Hz.
    ///   - dominantPeak: The pre-selected dominant peak from this tap.
    func handleFlcGatedProgress(magnitudes: [Float],
                                 frequencies: [Float],
                                 dominantPeak: ResonantPeak) {
        let captured = materialCapturedTaps.count
        let total = numberOfTaps
        print("📊 Gated FLC tap \(captured)/\(total): \(String(format: "%.1f", dominantPeak.frequency)) Hz")

        if captured < total {
            statusMessage = "FLC tap \(captured)/\(total) captured. Tap again..."
            reEnableDetectionForNextPlateTap()
            return
        }

        let (avgMags, avgFreqs) = averageSpectra(from: materialCapturedTaps)
        flcSpectrum = (magnitudes: avgMags, frequencies: avgFreqs)
        flcPeaks = buildAllPeaks(magnitudes: avgMags, frequencies: avgFreqs, dominantPeak: dominantPeak)
        autoSelectedFlcPeakID = dominantPeak.id
        selectedFlcPeak = flcPeaks.first(where: { $0.id == dominantPeak.id }) ?? dominantPeak
        print("🟣 Auto-selected FLC peak: \(dominantPeak.frequency) Hz")
        materialCapturedTaps = []

        var sel: [ResonantPeak] = []
        if let p = selectedLongitudinalPeak { sel.append(p) }
        else if let p = longitudinalPeaks.first { sel.append(p) }
        if let p = selectedCrossPeak { sel.append(p) }
        else if let p = crossPeaks.first { sel.append(p) }
        sel.append(selectedFlcPeak ?? dominantPeak)
        currentPeaks = sel
        selectedPeakIDs = Set(sel.map { $0.id })
        isSpectrumFrozen = false; frozenFrequencies = []; frozenMagnitudes = []
        materialTapPhase = .complete; tapProgress = 1.0
        statusMessage = "Complete - check Results"
        print("✅ Plate complete: L=\(longitudinalPeaks.first?.frequency ?? 0) C=\(crossPeaks.first?.frequency ?? 0) FLC=\(dominantPeak.frequency) Hz")
    }

    /// Builds a display-ready peak list from a gated-FFT spectrum, ensuring
    /// that `dominantPeak` is always present.
    ///
    /// Runs the standard ``findPeaks(magnitudes:frequencies:minHz:maxHz:)``
    /// finder with no range restrictions so the user can see and manually
    /// select any peak in the spectrum. If a peak near `dominantPeak.frequency`
    /// (within 2 Hz) is found, it is replaced with `dominantPeak` so that the
    /// `autoSelectedXxxPeakID == dominantPeak.id` identity invariant holds
    /// for all subsequent UUID-based lookups. If no nearby peak is found,
    /// `dominantPeak` is prepended.
    ///
    /// - Parameters:
    ///   - magnitudes: Averaged gated-FFT spectrum (dBFS).
    ///   - frequencies: Frequency axis matching `magnitudes`, in Hz.
    ///   - dominantPeak: The already-selected dominant peak whose UUID must
    ///     appear in the returned array.
    /// - Returns: Full peak array with `dominantPeak` guaranteed to be present.
    func buildAllPeaks(magnitudes: [Float],
                       frequencies: [Float],
                       dominantPeak: ResonantPeak) -> [ResonantPeak] {
        // Run the standard finder with no range restrictions so the user can see
        // and manually select any peak in the spectrum.
        var peaks = findPeaks(magnitudes: magnitudes, frequencies: frequencies)
        // Replace any nearby peak with dominantPeak so UUID is always consistent.
        // This is critical: autoSelectedXxxPeakID == dominantPeak.id, so the peak
        // stored in the array must share that UUID for ID-based lookups to work.
        if let idx = peaks.firstIndex(where: { abs($0.frequency - dominantPeak.frequency) < 2.0 }) {
            peaks[idx] = dominantPeak
        } else {
            peaks.insert(dominantPeak, at: 0)
        }
        return peaks
    }

    // MARK: - Spectrum Capture

    /// Invalidates the capture-window timer after the ring-out window closes.
    ///
    /// For guitar mode, `captureTimer` is started immediately after a tap is
    /// detected and fires after `captureWindow` seconds. This method is called
    /// from the timer callback to clean up the reference.
    func finishCapture() {
        captureTimer?.invalidate()
        captureTimer = nil
    }
    
    /// Averages multiple tap spectra using frequency-domain power averaging.
    ///
    /// Averaging in the frequency domain after discarding phase is the correct
    /// approach for non-periodic impulse responses: there is no meaningful
    /// inter-tap phase relationship to preserve, and power averaging reduces
    /// random noise while keeping consistent resonance peaks.
    ///
    /// The per-bin averaging formula is:
    /// ```
    /// p_i = 10^(dB_i / 10)           [dB → linear power, per tap]
    /// avg_p = (1/N) Σ p_i            [average power across N taps]
    /// dB_avg = 10 × log10(avg_p)     [back to dB]
    /// ```
    ///
    /// - Parameter taps: Array of captured tap records, each containing a
    ///   magnitude spectrum (dBFS), its frequency axis, and a timestamp.
    /// - Returns: `(magnitudes, frequencies)` of the averaged spectrum.
    ///   Returns `([], [])` if `taps` is empty, and returns the single tap's
    ///   data unchanged if `taps.count == 1`. Returns the first tap's data
    ///   unchanged if spectrum lengths differ (mismatch logged to console).
    func averageSpectra(from taps: [(magnitudes: [Float], frequencies: [Float], captureTime: Date)]) -> (magnitudes: [Float], frequencies: [Float]) {
        guard !taps.isEmpty else { return ([], []) }
        
        // If only one tap, return its spectrum
        if taps.count == 1 {
            return (taps[0].magnitudes, taps[0].frequencies)
        }
        
        // Ensure all spectra have the same length
        let spectrumLength = taps[0].magnitudes.count
        guard taps.allSatisfy({ $0.magnitudes.count == spectrumLength }) else {
            print("⚠️ Warning: Spectrum lengths don't match, using first tap only")
            return (taps[0].magnitudes, taps[0].frequencies)
        }
        
        // Average magnitudes bin-by-bin
        var averagedMagnitudes = [Float](repeating: 0, count: spectrumLength)
        
        // Convert dB to linear (power), average, then convert back to dB
        for binIndex in 0..<spectrumLength {
            var linearSum: Float = 0
            
            for tap in taps {
                let magnitudeDB = tap.magnitudes[binIndex]
                // Convert dB to linear power: power = 10^(dB/10)
                let linearPower = pow(10.0, magnitudeDB / 10.0)
                linearSum += linearPower
            }
            
            // Average and convert back to dB
            let averageLinear = linearSum / Float(taps.count)
            averagedMagnitudes[binIndex] = 10.0 * log10(averageLinear)
        }
        
        // Frequencies should be identical across all taps, use first one
        let frequencies = taps[0].frequencies
        
        print("📊 Averaged \(taps.count) spectra: \(spectrumLength) bins each")
        
        return (magnitudes: averagedMagnitudes, frequencies: frequencies)
    }

    /// Processes multiple captured guitar taps using frequency-domain
    /// magnitude averaging.
    ///
    /// Each tap's magnitude spectrum was already computed by the continuous
    /// FFT at the moment of tap detection. This method averages those spectra
    /// bin-by-bin in the linear power domain via ``averageSpectra(from:)``,
    /// then runs peak detection once on the averaged result. The averaged
    /// spectrum is frozen for display.
    ///
    /// - Note: Called after all required taps have been captured
    ///   (`currentTapCount >= numberOfTaps`), scheduled via
    ///   `DispatchQueue.main.asyncAfter(deadline:execute:)`.
    func processMultipleTaps() {
        guard !capturedTaps.isEmpty else { return }
        
        print("🔬 Processing \(capturedTaps.count) taps for averaging...")
        
        // Average the per-tap magnitude spectra in the frequency domain
        let (avgMagnitudes, avgFrequencies) = averageSpectra(from: capturedTaps)
        
        // Freeze the averaged spectrum for display
        frozenFrequencies = avgFrequencies
        frozenMagnitudes = avgMagnitudes
        isSpectrumFrozen = true
        print("📸 Spectrum frozen with averaged data from \(capturedTaps.count) taps")
        
        // Find peaks in the AVERAGED spectrum so they align with what's displayed.
        // This ensures peak markers sit on actual peaks in the averaged waveform.
        let peaksFromAveragedSpectrum = findPeaks(magnitudes: avgMagnitudes, frequencies: avgFrequencies)
        
        // Update current peaks with peaks from averaged spectrum.
        // Auto-select one best peak per guitar mode (lowest range first) so that
        // overlapping ranges resolve in favour of the lower-frequency mode.
        // Clear the manual-modification flag so subsequent Peak Min changes re-run
        // auto-selection rather than carrying forward a now-stale manual state.
        currentPeaks = peaksFromAveragedSpectrum
        selectedPeakIDs = guitarModeSelectedPeakIDs(from: peaksFromAveragedSpectrum)
        userHasModifiedPeakSelection = false
        
        // Classify modes based on peaks
        identifiedModes = peaksFromAveragedSpectrum.map { peak in
            (peak: peak, mode: GuitarMode.classify(frequency: peak.frequency))
        }
        
        // Update status
        statusMessage = "Analysis complete! \(peaksFromAveragedSpectrum.count) peaks identified (from \(capturedTaps.count) averaged taps)."
        tapProgress = 1.0
        
        print("✅ Found \(peaksFromAveragedSpectrum.count) peaks in averaged spectrum from \(capturedTaps.count) taps")
    }
}
