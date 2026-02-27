//
//  TapToneAnalyzer+SpectrumCapture.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import Foundation

extension TapToneAnalyzer {

    // MARK: - Gated FFT Capture (Material/Brace)

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

    /// Open a short raw-PCM capture window for the current material/brace phase.
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
                self.reEnableDetectionForNextMaterialTap()
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
            reEnableDetectionForNextMaterialTap()
            return
        }

        // Check that the captured signal has meaningful energy
        let peakDb = magnitudes.max() ?? -160
        guard peakDb > -60 else {
            print("⚠️ Gated FFT peak is only \(String(format: "%.1f", peakDb)) dB — signal too quiet, tap again")
            statusMessage = "Signal too quiet — tap firmer"
            reEnableDetectionForNextMaterialTap()
            return
        }

        // Determine the frequency search window for this measurement type.
        // Using the known physical range rejects low-frequency impact thuds (20–80 Hz)
        // that are present in every tap but are not resonances of the workpiece.
        let mType = SpectrumDisplaySettings.measurementType
        let hpsMinHz: Float
        let hpsMaxHz: Float
        switch mType {
        case .brace:
            // Brace bars resonate 100–1000 Hz; exclude sub-100 Hz table/impact thud
            hpsMinHz = 100; hpsMaxHz = 1200
        case .material:
            // Plate material modes: fL ~70–400 Hz, fC ~30–200 Hz, fLC ~20–150 Hz
            hpsMinHz = 20; hpsMaxHz = 600
        default:
            hpsMinHz = 20; hpsMaxHz = 2000
        }

        // Find the dominant peak using harmonic product spectrum analysis.
        // This finds the fundamental regardless of whether harmonics are louder.
        guard let dominantPeak = findDominantPeak(magnitudes: magnitudes,
                                                   frequencies: frequencies,
                                                   minHz: hpsMinHz,
                                                   maxHz: hpsMaxHz) else {
            print("⚠️ Gated FFT: no peak found — tap again")
            statusMessage = "No resonance detected — tap again"
            reEnableDetectionForNextMaterialTap()
            return
        }

        print("📊 Gated FFT complete: \(magnitudes.count) bins, dominant peak \(String(format: "%.1f", dominantPeak.frequency)) Hz @ \(String(format: "%.1f", dominantPeak.magnitude)) dB, phase \(phase)")

        // Store spectrum so the UI can display it and the user can select alternate peaks
        materialCapturedTaps.append((magnitudes: magnitudes, frequencies: frequencies, captureTime: Date()))
        currentTapCount += 1
        tapProgress = Float(currentTapCount) / Float(totalMaterialTaps)

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

    /// Find the fundamental resonance peak in the gated FFT spectrum using
    /// Harmonic Product Spectrum (HPS) analysis.
    ///
    /// Plain magnitude-picking fails when a harmonic is louder than the fundamental.
    /// HPS works by multiplying the spectrum by decimated copies of itself (×½, ×⅓, ×¼).
    /// The fundamental is the only frequency where all copies align and reinforce;
    /// harmonics cancel because their sub-harmonic copies land in noise.
    ///
    /// This requires no frequency-range assumptions — the tap orientation selects
    /// the mode and HPS finds its fundamental without needing to know what to expect.
    func findDominantPeak(magnitudes: [Float],
                          frequencies: [Float],
                          minHz: Float = 20,
                          maxHz: Float = 2000) -> ResonantPeak? {
        guard magnitudes.count == frequencies.count, magnitudes.count > 10 else { return nil }

        // Work in linear amplitude (convert from dB).
        // HPS multiplication is meaningful in linear scale.
        let linear = magnitudes.map { (m: Float) -> Float in
            let clamped = max(m, -160)
            return pow(10.0, clamped / 20.0)
        }

        let n = linear.count
        // Limit HPS to the caller-supplied frequency range.
        // minHz excludes low-frequency impact thuds; maxHz avoids looking for
        // fundamentals whose harmonics would fall outside the spectrum.
        let startIdx = frequencies.firstIndex(where: { $0 >= minHz }) ?? 0
        let endIdx   = frequencies.firstIndex(where: { $0 > maxHz }) ?? n

        // Number of harmonics to include in the product (2–4 is typical).
        // Using 4 gives strong discrimination; reduce to 3 if spectrum is noisy.
        let hpsOrder = 4

        // Only compute HPS up to endIdx / hpsOrder so decimated copies stay in bounds
        let hpsEnd = min(endIdx, n / hpsOrder)
        guard startIdx < hpsEnd else { return nil }

        // Build the HPS array: hps[i] = linear[i] * linear[2i] * linear[3i] * linear[4i]
        var hps = [Float](repeating: 0, count: hpsEnd)
        for i in startIdx..<hpsEnd {
            var product = linear[i]
            for k in 2...hpsOrder {
                let harmIdx = i * k
                if harmIdx < n {
                    product *= linear[harmIdx]
                }
            }
            hps[i] = product
        }

        // Find the strongest local maximum in the HPS array
        let windowSize = 3
        var best: (index: Int, hpsValue: Float)? = nil

        for i in (startIdx + windowSize)..<(hpsEnd - windowSize) {
            let val = hps[i]
            // Require the original spectrum also has a real peak here (not just HPS noise)
            guard magnitudes[i] > peakThreshold else { continue }
            var isLocal = true
            for j in (i - windowSize)...(i + windowSize) where j != i {
                if hps[j] >= val { isLocal = false; break }
            }
            guard isLocal else { continue }
            if best == nil || val > best!.hpsValue {
                best = (index: i, hpsValue: val)
            }
        }

        guard let b = best else { return nil }
        let freq = frequencies[b.index]
        let mag  = magnitudes[b.index]
        let (quality, bandwidth) = calculateQFactor(magnitudes: magnitudes,
                                                    frequencies: frequencies,
                                                    peakIndex: b.index,
                                                    peakMagnitude: mag)
        let pitchNote  = pitchCalculator.note(frequency: Double(freq))
        let pitchCents = pitchCalculator.cents(frequency: Double(freq))
        let pitchFreq  = pitchCalculator.freq0(frequency: Double(freq))
        print("🎯 HPS dominant peak: \(String(format: "%.1f", freq)) Hz @ \(String(format: "%.1f", mag)) dB (HPS score: \(String(format: "%.3e", b.hpsValue)))")
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
            reEnableDetectionForNextMaterialTap()
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
        materialCapturedTaps = []

        let isBrace = SpectrumDisplaySettings.measurementType == .brace
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
            reEnableDetectionForNextMaterialTap()
            return
        }

        let (avgMags, avgFreqs) = averageSpectra(from: materialCapturedTaps)
        crossSpectrum = (magnitudes: avgMags, frequencies: avgFreqs)
        crossPeaks = buildAllPeaks(magnitudes: avgMags, frequencies: avgFreqs, dominantPeak: dominantPeak)
        autoSelectedCrossPeakID = dominantPeak.id
        selectedCrossPeak = crossPeaks.first(where: { $0.id == dominantPeak.id }) ?? dominantPeak
        print("🟠 Auto-selected cross-grain peak: \(dominantPeak.frequency) Hz")
        materialCapturedTaps = []

        if SpectrumDisplaySettings.measureFlc {
            currentPeaks = combineMaterialPeaks()
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
            isSpectrumFrozen = false; frozenFrequencies = []; frozenMagnitudes = []
            materialTapPhase = .complete; tapProgress = 1.0
            let fLStr = selectedLongitudinalPeak.map { String(format: "%.1f", $0.frequency) } ?? "?"
            statusMessage = "Complete — fL: \(fLStr) Hz, fC: \(String(format: "%.1f", dominantPeak.frequency)) Hz"
            print("✅ Material complete: fL=\(fLStr) Hz, fC=\(dominantPeak.frequency) Hz")
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
            reEnableDetectionForNextMaterialTap()
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
        isSpectrumFrozen = false; frozenFrequencies = []; frozenMagnitudes = []
        materialTapPhase = .complete; tapProgress = 1.0
        statusMessage = "Complete - check Results"
        print("✅ Material complete: L=\(longitudinalPeaks.first?.frequency ?? 0) C=\(crossPeaks.first?.frequency ?? 0) FLC=\(dominantPeak.frequency) Hz")
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
    
    /// Process multiple captured taps and average the results
    func processMultipleTaps() {
        guard !capturedTaps.isEmpty else { return }
        
        print("🔬 Processing \(capturedTaps.count) taps for averaging...")
        
        // Average the raw FFT spectrum across all taps FIRST
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
        
        // Classify modes based on peaks
        identifiedModes = peaksFromAveragedSpectrum.map { peak in
            (peak: peak, mode: GuitarMode.classify(frequency: peak.frequency))
        }
        
        // Update status
        statusMessage = "Analysis complete! \(peaksFromAveragedSpectrum.count) peaks identified (from \(capturedTaps.count) averaged taps)."
        tapProgress = 1.0
        
        print("✅ Found \(peaksFromAveragedSpectrum.count) peaks in averaged spectrum from \(capturedTaps.count) taps")
    }
    
    /// Average peaks across multiple taps
    /// Maintains mode priority: strongest peak for each known mode is guaranteed,
    /// then fills remaining slots with additional peaks by magnitude
    func averagePeaks(from tapPeaks: [[ResonantPeak]]) -> [ResonantPeak] {
        guard !tapPeaks.isEmpty else { return [] }
        
        // If only one tap, return its peaks
        if tapPeaks.count == 1 {
            return tapPeaks[0]
        }
        
        // Collect all unique peak frequencies (with tolerance)
        var peakGroups: [[ResonantPeak]] = []
        let frequencyTolerance: Float = 5.0  // Hz
        
        // Group similar peaks across taps
        for tapIndex in 0..<tapPeaks.count {
            for peak in tapPeaks[tapIndex] {
                // Try to find existing group
                var foundGroup = false
                for groupIndex in 0..<peakGroups.count {
                    let groupAvgFreq = peakGroups[groupIndex].map({ $0.frequency }).reduce(0, +) / Float(peakGroups[groupIndex].count)
                    if abs(peak.frequency - groupAvgFreq) < frequencyTolerance {
                        peakGroups[groupIndex].append(peak)
                        foundGroup = true
                        break
                    }
                }
                
                // Create new group if no match found
                if !foundGroup {
                    peakGroups.append([peak])
                }
            }
        }
        
        // Average each group
        var averagedPeaks: [ResonantPeak] = []
        for group in peakGroups {
            let avgFreq = group.map({ $0.frequency }).reduce(0, +) / Float(group.count)
            let avgMag = group.map({ $0.magnitude }).reduce(0, +) / Float(group.count)
            let avgQuality = group.map({ $0.quality }).reduce(0, +) / Float(group.count)
            let avgBandwidth = group.map({ $0.bandwidth }).reduce(0, +) / Float(group.count)
            
            let averagedPeak = ResonantPeak(
                frequency: avgFreq,
                magnitude: avgMag,
                quality: avgQuality,
                bandwidth: avgBandwidth
            )
            averagedPeaks.append(averagedPeak)
        }
        
        // Apply mode-priority selection (same logic as findPeaks)
        // Define known modes to search for
        let knownModes: [GuitarMode] = [.air, .top, .back, .dipole, .ringMode, .upperModes]
        
        // Find strongest peak for each mode
        var strongestPeakPerMode: [GuitarMode: ResonantPeak] = [:]
        for peak in averagedPeaks {
            let mode = GuitarMode.classify(frequency: peak.frequency).normalized
            if mode != .unknown {
                if let existing = strongestPeakPerMode[mode] {
                    if peak.magnitude > existing.magnitude {
                        strongestPeakPerMode[mode] = peak
                    }
                } else {
                    strongestPeakPerMode[mode] = peak
                }
            }
        }
        
        // Build final list: mode peaks first, then fill remaining by magnitude
        var finalPeaks: [ResonantPeak] = []
        var includedPeakIDs = Set<UUID>()
        
        for mode in knownModes {
            if let peak = strongestPeakPerMode[mode] {
                finalPeaks.append(peak)
                includedPeakIDs.insert(peak.id)
            }
        }
        
        // Fill remaining slots
        // maxPeaks == 0 means "capture all peaks"
        if maxPeaks == 0 {
            // Add all remaining peaks (no limit)
            let otherPeaks = averagedPeaks
                .filter { !includedPeakIDs.contains($0.id) }
                .sorted { $0.magnitude > $1.magnitude }
            finalPeaks.append(contentsOf: otherPeaks)
        } else {
            let remainingSlots = maxPeaks - finalPeaks.count
            if remainingSlots > 0 {
                let otherPeaks = averagedPeaks
                    .filter { !includedPeakIDs.contains($0.id) }
                    .sorted { $0.magnitude > $1.magnitude }
                    .prefix(remainingSlots)
                finalPeaks.append(contentsOf: otherPeaks)
            }
        }
        
        // Sort final result by magnitude descending
        return finalPeaks.sorted { $0.magnitude > $1.magnitude }
    }
    
    /// Average raw FFT spectra across multiple taps
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
