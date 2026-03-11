//
//  TapToneAnalyzer+SpectrumCapture.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import Foundation

extension TapToneAnalyzer {

    // MARK: - Gated FFT Capture (Plate/Brace)

    /// Called on the audioProcessingQueue for every incoming buffer of raw samples.
    /// Maintains the pre-roll ring buffer and accumulates samples for gated FFT capture.
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

    /// Open a short raw-PCM capture window for the current plate/brace phase.
    ///
    /// `accumulateGatedSamples` routes incoming audio into `gatedAccumBuffer` while
    /// `gatedCaptureActive` is true.  When the window fills (400 ms by default)
    /// `finishGatedFFTCapture` is called on the main thread.
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

    /// Called on the main thread once the gated capture window fills (or times out).
    ///
    /// Runs `computeGatedFFT` on the captured samples and finds the dominant peak —
    /// the strongest resonance in the ring-out spectrum above 20 Hz.  No frequency
    /// window assumptions are made: the tap orientation physically selects the mode,
    /// so the strongest peak is the correct one.
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
        // If the best peak found is below the threshold, the ring-out was too weak -
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

    /// Find the dominant resonance peak in the gated FFT spectrum.
    ///
    /// Strategy: the tap orientation physically selects the resonant mode, so the
    /// highest-magnitude local peak in the expected frequency range is the right answer
    /// for plate/brace measurements.  HPS is applied as a secondary score to break ties
    /// between closely-matched peaks and to prefer the fundamental over a louder harmonic
    /// when the magnitude difference is small (< 6 dB).
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

    /// Gated-FFT handler for the longitudinal phase — mirrors `handleLongitudinalTapProgress`
    /// but uses the pre-computed `dominantPeak` instead of re-running `findPeaks`.
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

    /// Gated-FFT handler for the cross-grain phase.
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

    /// Gated-FFT handler for the FLC (shear/diagonal) phase.
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

    /// Build a peak list for display from the averaged gated-FFT spectrum.
    /// Ensures `dominantPeak` is always present (it may not appear in `findPeaks`
    /// if it falls outside the guitar mode ranges).
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

    /// Finish capturing spectrum after capture window
    func finishCapture() {
        captureTimer?.invalidate()
        captureTimer = nil
    }
    
    /// Process multiple captured taps using frequency-domain magnitude averaging.
    ///
    /// Each tap has already been independently transformed into a magnitude spectrum
    /// by `computeGatedFFT`. This function averages those spectra bin-by-bin in the
    /// linear power domain (see `averageSpectra`), then runs peak detection once on
    /// the averaged result. Averaging in the frequency domain after discarding phase
    /// is the correct approach for non-periodic impulse responses: there is no
    /// meaningful inter-tap phase relationship to preserve, and power averaging
    /// reduces random noise while keeping consistent resonance peaks.
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
        
        // Now find peaks in the AVERAGED spectrum so they align with what's displayed
        // This ensures peak markers sit on actual peaks in the averaged waveform
        let peaksFromAveragedSpectrum = findPeaks(magnitudes: avgMagnitudes, frequencies: avgFrequencies)
        
        // Update current peaks with peaks from averaged spectrum
        currentPeaks = peaksFromAveragedSpectrum
        selectedPeakIDs = Set(peaksFromAveragedSpectrum.map { $0.id })
        
        // Classify modes based on peaks
        identifiedModes = peaksFromAveragedSpectrum.map { peak in
            (peak: peak, mode: GuitarMode.classify(frequency: peak.frequency))
        }
        
        // Update status
        statusMessage = "Analysis complete! \(peaksFromAveragedSpectrum.count) peaks identified (from \(capturedTaps.count) averaged taps)."
        tapProgress = 1.0
        
        print("✅ Found \(peaksFromAveragedSpectrum.count) peaks in averaged spectrum from \(capturedTaps.count) taps")
    }
    
    /// Average per-tap FFT magnitude spectra in the linear power domain.
    ///
    /// Each entry in `taps` contains a magnitude spectrum (in dB) already produced
    /// by `computeGatedFFT` for a single tap. Averaging is done bin-by-bin:
    ///
    ///   1. Convert each bin from dB to linear power:  p = 10^(dB / 10)
    ///   2. Average the linear powers across all taps
    ///   3. Convert the average back to dB:  dB = 10 · log10(avg_power)
    ///
    /// Averaging power (rather than amplitude or dB directly) is the physically
    /// correct approach — it preserves energy relationships between taps.
    /// Phase is implicitly discarded because each tap's magnitude spectrum was
    /// computed independently; this is appropriate for non-periodic impulse
    /// responses where inter-tap phase alignment cannot be guaranteed.
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
}
