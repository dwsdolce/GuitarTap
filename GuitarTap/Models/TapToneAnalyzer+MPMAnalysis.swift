//
//  TapToneAnalyzer+MPMAnalysis.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import Foundation

// MARK: - MPM Analysis Extension

extension TapToneAnalyzer {

    // MARK: - Raw Sample Accumulation

    /// Called on the audioProcessingQueue for every incoming buffer of raw samples.
    func accumulateMPMSamples(_ samples: [Float], sampleRate: Double) {
        mpmSampleRate = sampleRate

        // --- Gated FFT path (material/brace tap measurement) ---
        if gatedCaptureActive {
            mpmLock.lock()
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
            return  // Mutually exclusive with MPM path
        }

        // --- MPM path (brace/plate MPM measurement) ---
        guard mpmCaptureActive else { return }

        mpmLock.lock()
        mpmAccumBuffer.append(contentsOf: samples)
        let count = mpmAccumBuffer.count
        mpmLock.unlock()

        if count >= mpmCaptureSamples {
            mpmCaptureActive = false
            let captured: [Float]
            mpmLock.lock()
            captured = Array(mpmAccumBuffer.prefix(mpmCaptureSamples))
            mpmAccumBuffer = []
            mpmLock.unlock()

            DispatchQueue.main.async { [weak self] in
                self?.finishMPMCapture(samples: captured, sampleRate: sampleRate)
            }
        }
    }

    // MARK: - Tap Detection for MPM

    /// Called when a tap is detected in MPM mode.
    func handleMPMTapDetection(time: Date) {
        let measurementType = SpectrumDisplaySettings.measurementType

        mpmLock.lock()
        mpmAccumBuffer = []
        mpmLock.unlock()
        mpmCaptureActive = true
        mpmIsCapturing = true

        // Configure frequency range for the analyser.
        // Brace mode: cap at 700 Hz rather than 1000 Hz so that minLag = sr/700 ≈ 63
        // samples, keeping the search well away from the 2nd harmonic of a ~500 Hz
        // brace resonance (whose period is ~43 samples at 44.1 kHz).  Using 1000 Hz
        // caused the NSDF to lock onto the harmonic lobe instead of the fundamental.
        if measurementType == .braceMPM {
            mpmAnalyzerInstance = MPMAnalyzer(minFrequency: 30, maxFrequency: 700)
        } else {
            mpmAnalyzerInstance = MPMAnalyzer(minFrequency: 30, maxFrequency: 600)
        }
        print("🎯 MPM tap detected — opening \(mpmCaptureSamples)-sample capture window (\(Int(TapToneAnalyzer.mpmCaptureDuration * 1000)) ms at \(Int(mpmSampleRate)) Hz)")

        // Safety timeout: close capture window after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, self.mpmCaptureActive else { return }
            self.mpmCaptureActive = false
            self.mpmIsCapturing = false
            self.mpmLock.lock()
            let partial = self.mpmAccumBuffer
            self.mpmAccumBuffer = []
            self.mpmLock.unlock()
            if !partial.isEmpty {
                self.finishMPMCapture(samples: partial, sampleRate: self.mpmSampleRate)
            }
        }
    }

    // MARK: - Gated FFT Tap Capture

    /// Open a short raw-PCM capture window for the current material/brace phase.
    ///
    /// `accumulateMPMSamples` routes incoming audio into `gatedAccumBuffer` while
    /// `gatedCaptureActive` is true.  When the window fills (400 ms by default)
    /// `finishGatedFFTCapture` is called on the main thread.
    func startGatedCapture(phase: MaterialTapPhase) {
        mpmLock.lock()
        gatedAccumBuffer = []
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

        // Find the dominant peak using harmonic product spectrum analysis.
        // This finds the fundamental regardless of whether harmonics are louder.
        guard let dominantPeak = findDominantPeak(magnitudes: magnitudes,
                                                   frequencies: frequencies) else {
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
                          frequencies: [Float]) -> ResonantPeak? {
        guard magnitudes.count == frequencies.count, magnitudes.count > 10 else { return nil }

        // Work in linear amplitude (convert from dB).
        // HPS multiplication is meaningful in linear scale.
        let linear = magnitudes.map { (m: Float) -> Float in
            let clamped = max(m, -160)
            return pow(10.0, clamped / 20.0)
        }

        let n = linear.count
        // Limit HPS to the usable range: 20 Hz to 2000 Hz.
        // Above 2000 Hz we'd be looking at harmonics of >500 Hz fundamentals,
        // which are not plate resonances.
        let startIdx = frequencies.firstIndex(where: { $0 >= 20 }) ?? 0
        let endIdx   = frequencies.firstIndex(where: { $0 > 2000 }) ?? n

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
                self.isAboveThreshold = self.fftAnalyzer.recentPeakLevelDB > (self.tapDetectionThreshold - self.hysteresisMargin)
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
                self.isAboveThreshold = self.fftAnalyzer.recentPeakLevelDB > (self.tapDetectionThreshold - self.hysteresisMargin)
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

    // MARK: - MPM Result Processing

    /// Called on main thread once the capture window has been filled.
    func finishMPMCapture(samples: [Float], sampleRate: Double) {
        mpmIsCapturing = false

        let result = mpmAnalyzerInstance.analyse(samples: samples, sampleRate: sampleRate)
        let measurementType = SpectrumDisplaySettings.measurementType

        guard let freq = result.frequency, freq > 0, freq.isFinite else {
            print("⚠️ MPM: no usable frequency (raw: \(result.frequency.map { String($0) } ?? "nil"), confidence: \(result.confidence))")
            statusMessage = "No frequency detected — tap again"
            reEnableDetectionForNextMaterialTap()
            return
        }

        // Reject low-confidence results — boundary artifacts and noisy taps score 0.27–0.33,
        // while true resonances score 0.84–0.87. Threshold at 0.50 cleanly separates them.
        guard result.confidence >= 0.50 else {
            print("⚠️ MPM: low confidence (\(String(format: "%.2f", result.confidence))) at \(String(format: "%.2f", freq)) Hz — rejecting, tap again")
            statusMessage = "Tap again — signal too weak (\(String(format: "%.0f%%", result.confidence * 100)) confidence)"
            reEnableDetectionForNextMaterialTap()
            return
        }

        mpmDetectedFrequency = freq
        mpmConfidence = result.confidence
        print("✅ MPM detected: \(String(format: "%.2f", freq)) Hz (confidence: \(String(format: "%.2f", result.confidence)))")

        // Build a ResonantPeak from the MPM result
        let pitchNote = pitchCalculator.note(frequency: Double(freq))
        let pitchCents = pitchCalculator.cents(frequency: Double(freq))
        let pitchFreq = pitchCalculator.freq0(frequency: Double(freq))
        let captureLevel = fftAnalyzer.recentPeakLevelDB
        let peak = ResonantPeak(
            frequency: freq,
            magnitude: captureLevel,
            quality: result.confidence,
            bandwidth: 0,
            pitchNote: pitchNote,
            pitchCents: pitchCents,
            pitchFrequency: pitchFreq
        )

        // Phase routing — mirrors material/brace state machine
        switch materialTapPhase {
        case .capturingLongitudinal:
            mpmLongitudinalFrequency = freq
            autoSelectedLongitudinalPeakID = peak.id
            longitudinalPeaks = [peak]
            currentPeaks = [peak]

            if measurementType == .braceMPM {
                materialTapPhase = .complete
                tapProgress = 1.0
                statusMessage = "Complete — fL: \(String(format: "%.1f", freq)) Hz"
                print("✅ Brace MPM complete: fL = \(freq) Hz")
            } else {
                materialTapPhase = .waitingForCrossTap
                statusMessage = "fL: \(String(format: "%.1f", freq)) Hz — rotate 90° for cross tap"
                DispatchQueue.main.asyncAfter(deadline: .now() + tapCooldown) { [weak self] in
                    guard let self = self else { return }
                    let currentLevel = self.fftAnalyzer.peakMagnitude
                    let fallingThreshold = self.tapDetectionThreshold - self.hysteresisMargin
                    self.isAboveThreshold = currentLevel > fallingThreshold
                    self.isDetecting = true
                    self.tapDetected = false
                    self.materialTapPhase = .capturingCross
                    self.analyzerStartTime = Date()
                }
            }

        case .capturingCross, .waitingForCrossTap:
            mpmCrossFrequency = freq
            autoSelectedCrossPeakID = peak.id
            crossPeaks = [peak]
            var selectedPeaks: [ResonantPeak] = []
            if let lPeak = longitudinalPeaks.first { selectedPeaks.append(lPeak) }
            selectedPeaks.append(peak)
            currentPeaks = selectedPeaks

            materialTapPhase = .complete
            tapProgress = 1.0
            let lFreq = mpmLongitudinalFrequency.map { String(format: "%.1f", $0) } ?? "?"
            statusMessage = "Complete — fL: \(lFreq) Hz, fC: \(String(format: "%.1f", freq)) Hz"
            print("✅ Plate MPM complete: fL = \(lFreq) Hz, fC = \(freq) Hz")

        default:
            print("⚠️ Unexpected MPM tap in phase: \(materialTapPhase)")
        }
    }
}
