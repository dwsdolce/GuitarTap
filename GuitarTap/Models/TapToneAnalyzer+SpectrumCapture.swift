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
/// `preRollSamples` worth of audio at all times.  For guitar mode, the
/// audio-queue level-crossing handler starts the gated capture immediately
/// when the input level crosses the detection threshold — seeding
/// ``gatedAccumBuffer`` with the pre-roll and setting ``gatedCaptureActive``
/// right on the audio queue.  This eliminates both the pre-roll shift and
/// the sample gap that would otherwise occur during the main-thread Combine
/// dispatch delay.  For plate/brace mode, the live pre-roll is seeded when
/// ``startGatedCapture(phase:)`` is called on the main thread.
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
import Accelerate

extension TapToneAnalyzer {

    // MARK: - WAV Dump Helper

    /// Writes raw PCM samples to a mono 32-bit float WAV file in
    /// `~/Documents/GuitarTap/` when `TapDisplaySettings.dumpCaptureAudio`
    /// is enabled.  Shared by guitar, plate, and brace capture paths.
    ///
    /// - Parameters:
    ///   - samples: Raw Float32 PCM samples to dump.
    ///   - sampleRate: Hardware sample rate in Hz.
    ///   - label: Short string identifying the capture type (e.g. "guitar",
    ///     "capturingLongitudinal").
    func dumpCaptureWAV(samples: [Float], sampleRate: Double, label: String) {
        guard TapDisplaySettings.dumpCaptureAudio else { return }
        do {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dumpDir = docs.appendingPathComponent("GuitarTap")
            try FileManager.default.createDirectory(at: dumpDir, withIntermediateDirectories: true)
            let ts = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let name = "swift_\(label)_\(ts).wav"
            let url = dumpDir.appendingPathComponent(name)

            let sr = Int(sampleRate)
            let numSamples = samples.count
            let bytesPerSample = 4  // Float32
            let dataSize = numSamples * bytesPerSample
            var header = Data(capacity: 44 + dataSize)
            // RIFF header
            header.append(contentsOf: "RIFF".utf8)
            var chunkSize = UInt32(36 + dataSize).littleEndian
            header.append(Data(bytes: &chunkSize, count: 4))
            header.append(contentsOf: "WAVE".utf8)
            // fmt sub-chunk (IEEE float)
            header.append(contentsOf: "fmt ".utf8)
            var subchunk1Size = UInt32(16).littleEndian
            header.append(Data(bytes: &subchunk1Size, count: 4))
            var audioFormat = UInt16(3).littleEndian  // IEEE float
            header.append(Data(bytes: &audioFormat, count: 2))
            var numChannels = UInt16(1).littleEndian
            header.append(Data(bytes: &numChannels, count: 2))
            var sampleRateLE = UInt32(sr).littleEndian
            header.append(Data(bytes: &sampleRateLE, count: 4))
            var byteRate = UInt32(sr * bytesPerSample).littleEndian
            header.append(Data(bytes: &byteRate, count: 4))
            var blockAlign = UInt16(bytesPerSample).littleEndian
            header.append(Data(bytes: &blockAlign, count: 2))
            var bitsPerSample = UInt16(32).littleEndian
            header.append(Data(bytes: &bitsPerSample, count: 2))
            // data sub-chunk
            header.append(contentsOf: "data".utf8)
            var dataSizeLE = UInt32(dataSize).littleEndian
            header.append(Data(bytes: &dataSizeLE, count: 4))
            // Sample data
            header.append(samples.withUnsafeBufferPointer { Data(buffer: $0) })
            try header.write(to: url)
            gtLog("📦 WAV dump: \(url.path) (\(numSamples) samples, \(sr) Hz)")
        } catch {
            gtLog("⚠️ WAV dump failed: \(error.localizedDescription)")
        }
    }

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

        if fftAnalyzer.isPlayingFile {
            TAP_DEBUG("gatedAccum", "CHUNK | +\(samples.count) running=\(count) target=\(gatedCaptureSamples) phase=\(String(describing: gatedCapturePhase))")
        }

        if count >= gatedCaptureSamples {
            gatedCaptureActive = false
            let captured: [Float]
            let phase = gatedCapturePhase
            mpmLock.lock()
            captured = Array(gatedAccumBuffer.prefix(gatedCaptureSamples))
            gatedAccumBuffer = []
            mpmLock.unlock()

            // DIAG: log capture completion details
            let diagConsumed = fftAnalyzer.samplesConsumed
            let diagRms: Float = {
                let sumSq = captured.reduce(Float(0)) { $0 + $1 * $1 }
                let rms = sqrt(sumSq / max(Float(captured.count), 1))
                return 20 * log10(max(rms, 1e-10))
            }()
            let diagHash: Float = captured.count >= 16 ? captured[0..<16].reduce(0, +) : 0
            TAP_DEBUG("gatedAccum", "CAPTURE COMPLETE | samples=\(captured.count) fileSamplePos=\(diagConsumed) captureRMS=\(String(format: "%.2f", diagRms))dB first16hash=\(String(format: "%.6f", diagHash))")

            DispatchQueue.main.async { [weak self] in
                if let phase = phase {
                    self?.finishGatedFFTCapture(samples: captured, sampleRate: sampleRate, phase: phase)
                } else {
                    self?.finishGuitarGatedCapture(samples: captured, sampleRate: sampleRate)
                }
            }
        }
    }

    /// Zero-pads and completes any active gated capture when file playback ends.
    ///
    /// Called from `startFromFile`'s `asyncAfter` block (via `preMicRestartHandler`)
    /// after the input buffer flush but BEFORE `start()` restarts the mic.
    /// Without this, the mic restarts and mic noise fills the remaining gated
    /// capture window, contaminating the last tap's spectrum.
    ///
    /// Mirrors Python `_flush_gated_capture_on_file_end()`.
    ///
    /// The pattern is the same as the safety timeout flush: take whatever
    /// samples have accumulated, zero-pad to the target window size, and
    /// dispatch `finishGuitarGatedCapture` / `finishGatedFFTCapture` so the
    /// FFT runs on a clean (partial + silence) buffer rather than partial +
    /// mic noise.
    func flushGatedCaptureOnFileEnd() {
        TAP_DEBUG("flushGatedCapture", "FLUSH_GATED_CHECK | active=\(gatedCaptureActive) accumLen=\(gatedAccumBuffer.count) phase=\(String(describing: gatedCapturePhase)) target=\(gatedCaptureSamples)")
        guard gatedCaptureActive else {
            TAP_DEBUG("flushGatedCapture", "FLUSH_GATED_SKIP — no active capture")
            return
        }
        gatedCaptureActive = false

        mpmLock.lock()
        let partial = gatedAccumBuffer
        let phase = gatedCapturePhase
        gatedAccumBuffer = []
        mpmLock.unlock()

        guard !partial.isEmpty else { return }

        let target = gatedCaptureSamples
        var samples = partial
        if samples.count < target {
            samples.append(contentsOf: [Float](repeating: 0, count: target - samples.count))
        }

        TAP_DEBUG("gatedCapture", "Flushed on file end — \(partial.count) samples zero-padded to \(target)")

        if let phase = phase {
            finishGatedFFTCapture(samples: samples, sampleRate: mpmSampleRate, phase: phase)
        } else {
            finishGuitarGatedCapture(samples: samples, sampleRate: mpmSampleRate)
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
        // Bump capture identity — invalidates any pending safety-timeout from
        // a previous capture so it cannot flush this capture's accumulator
        // with a partial buffer.  See startGuitarGatedCapture for the full
        // explanation of the race this prevents.
        gatedCaptureID += 1
        let myCaptureID = gatedCaptureID
        let preRollCount = preRollBuffer.count
        gatedAccumBuffer = preRollBuffer
        mpmLock.unlock()
        gatedCapturePhase = phase
        gatedCaptureSamples = Int(mpmSampleRate * TapToneAnalyzer.gatedCaptureDuration)
        gatedCaptureActive = true

        let windowMs = Int(TapToneAnalyzer.gatedCaptureDuration * 1000)
        gtLog("🎯 Gated FFT capture started for phase \(phase) — \(gatedCaptureSamples)-sample window (\(windowMs) ms at \(Int(mpmSampleRate)) Hz)")
        TAP_DEBUG("gatedCapture", "SEED | preRollSamples=\(preRollCount) target=\(gatedCaptureSamples) rate=\(Int(mpmSampleRate))")

        // Safety timeout: close capture window after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            // Identity guard: if a newer capture has started since this
            // timeout was scheduled, this closure is stale — do nothing.
            guard self.gatedCaptureID == myCaptureID else { return }
            guard self.gatedCaptureActive else { return }
            self.gatedCaptureActive = false
            self.mpmLock.lock()
            let partial = self.gatedAccumBuffer
            self.gatedAccumBuffer = []
            self.mpmLock.unlock()
            if !partial.isEmpty {
                self.finishGatedFFTCapture(samples: partial, sampleRate: self.mpmSampleRate, phase: phase)
            } else {
                gtLog("⚠️ Gated capture timeout with no samples — tap again")
                self.statusMessage = "No signal detected — tap again"
                self.reEnableDetectionForNextPlateTap()
            }
        }
    }

    /// Opens a raw-PCM capture window for guitar mode, aligned to the tap onset.
    ///
    /// Capture window size = ``RealtimeFFTAnalyzer.fftSize`` so the resulting
    /// spectrum has the same frequency resolution as the live FFT path.  The
    /// pre-roll buffer (~200 ms) is seeded into ``gatedAccumBuffer`` so the
    /// impulse onset (which arrives ~one RMS chunk before this call fires)
    /// is included in the captured window.
    ///
    /// When the window fills, ``accumulateGatedSamples(_:sampleRate:)``
    /// dispatches ``finishGuitarGatedCapture(samples:sampleRate:)`` on the main
    /// thread instead of ``finishGatedFFTCapture(samples:sampleRate:phase:)``.
    ///
    /// A safety timeout fires after `targetMs + 500` to flush a partial buffer
    /// (file ended early, user stopped, etc.) so the partial spectrum is still
    /// captured rather than silently dropped.
    func startGuitarGatedCapture() {
        let fftSize = fftAnalyzer.fftSize

        // The audio-queue level-crossing handler may have already started the
        // gated capture (seeded gatedAccumBuffer with the pre-roll and set
        // gatedCaptureActive = true) to avoid losing samples during the
        // main-thread Combine dispatch delay.  If so, skip re-seeding -
        // just grab the capture ID for the safety timeout and log.
        mpmLock.lock()
        let alreadyActive = gatedCaptureActive
        if alreadyActive {
            // Capture was started on the audio queue — don't re-seed or
            // bump the ID, just read it for the timeout guard.
            let myCaptureID = gatedCaptureID
            let currentCount = gatedAccumBuffer.count
            mpmLock.unlock()

            let targetMs = Int((Double(fftSize) / max(mpmSampleRate, 1.0)) * 1000)
            gtLog("🎯 Guitar gated capture (audio-queue fast-start) — \(fftSize)-sample window (\(targetMs) ms at \(Int(mpmSampleRate)) Hz, pre-roll+accum \(currentCount) samples)")

            let timeoutMs = targetMs + 500
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) { [weak self] in
                guard let self = self else { return }
                guard self.gatedCaptureID == myCaptureID else { return }
                guard self.gatedCaptureActive, self.gatedCapturePhase == nil else { return }
                self.gatedCaptureActive = false
                self.mpmLock.lock()
                let partial = self.gatedAccumBuffer
                self.gatedAccumBuffer = []
                self.mpmLock.unlock()
                if !partial.isEmpty {
                    self.finishGuitarGatedCapture(samples: partial, sampleRate: self.mpmSampleRate)
                } else {
                    gtLog("⚠️ Guitar gated capture timeout with no samples")
                    self.statusMessage = "No signal detected — tap again"
                    self.scheduleGuitarReEnable()
                }
            }
            return
        }

        // Fallback: crossing handler didn't fire (e.g. microphone mode where
        // the RMS path detected the tap but the per-buffer level didn't cross
        // the threshold in a single step).  Seed from the live pre-roll.
        gatedCaptureID += 1
        let myCaptureID = gatedCaptureID
        gatedAccumBuffer = preRollBuffer
        mpmLock.unlock()
        gatedCapturePhase = nil   // nil = guitar-mode marker (mirrors Python phase=None)
        gatedCaptureSamples = fftSize
        gatedCaptureActive = true

        let targetMs = Int((Double(fftSize) / max(mpmSampleRate, 1.0)) * 1000)
        gtLog("🎯 Guitar gated capture started — \(fftSize)-sample window (\(targetMs) ms at \(Int(mpmSampleRate)) Hz, pre-roll \(gatedAccumBuffer.count) samples)")

        let timeoutMs = targetMs + 500
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) { [weak self] in
            guard let self = self else { return }
            // Identity guard: if a newer capture has started since this
            // timeout was scheduled, this closure is stale — do nothing.
            guard self.gatedCaptureID == myCaptureID else { return }
            guard self.gatedCaptureActive, self.gatedCapturePhase == nil else { return }
            self.gatedCaptureActive = false
            self.mpmLock.lock()
            let partial = self.gatedAccumBuffer
            self.gatedAccumBuffer = []
            self.mpmLock.unlock()
            if !partial.isEmpty {
                self.finishGuitarGatedCapture(samples: partial, sampleRate: self.mpmSampleRate)
            } else {
                gtLog("⚠️ Guitar gated capture timeout with no samples")
                self.statusMessage = "No signal detected — tap again"
                self.scheduleGuitarReEnable()
            }
        }
    }

    /// Re-arms guitar tap detection after a cooldown when no spectrum was
    /// captured (e.g. timeout with no audio).
    private func scheduleGuitarReEnable() {
        DispatchQueue.main.asyncAfter(deadline: .now() + tapCooldown) { [weak self] in
            guard let self = self else { return }
            let currentLevel = self.fftAnalyzer.inputLevelDB
            let fallingThreshold = self.tapDetectionThreshold - self.hysteresisMargin
            self.isAboveThreshold = currentLevel > fallingThreshold
            self.isDetecting = true
            self.tapDetected = false
        }
    }

    /// Processes a guitar-mode gated PCM capture: computes the FFT with the
    /// same `fftSize` and rectangular window as the live FFT path, appends the
    /// resulting `(magnitudes, frequencies)` tuple to ``capturedTaps``, and
    /// advances the tap counter.
    ///
    /// This is the new (option 3) capture path for guitar mode.  The legacy
    /// "store the live FFT frame at tap-detection time" path is gone, replaced
    /// by this onset-aligned capture so the same physical tap reliably yields
    /// the same captured spectrum.
    ///
    /// - Parameters:
    ///   - samples: Pre-roll + post-trigger PCM samples (length `fftSize`).
    ///   - sampleRate: Hardware sample rate in Hz.
    func finishGuitarGatedCapture(samples: [Float], sampleRate: Double) {
        // Orphan-capture guard.  In brace/plate mode the level-crossing handler
        // may seed a phase=nil (guitar) gated capture from a noise spike that
        // never produces a confirming rising-edge — when its 65536-sample
        // window fills (~1.36 s later) it lands here.  Without this guard we
        // would append a silent spectrum to capturedTaps, advance currentTapCount,
        // and overwrite the displayed frozen spectrum, masking the real
        // brace/plate phase capture that runs in parallel.  Mirrors the
        // equivalent guard in Python tap_tone_analyzer_spectrum_capture.py
        // finish_guitar_gated_capture.
        if TapDisplaySettings.measurementType != .generic {
            TAP_DEBUG("guitarGatedCapture", "ORPHAN — discarded (measurementType=\(TapDisplaySettings.measurementType), samples=\(samples.count))")
            return
        }

        dumpCaptureWAV(samples: samples, sampleRate: sampleRate, label: "guitar")

        let fftSize = fftAnalyzer.fftSize

        // Truncate or zero-pad to exactly fftSize.
        var chunk: [Float]
        if samples.count >= fftSize {
            chunk = Array(samples.prefix(fftSize))
        } else {
            chunk = samples
            chunk.append(contentsOf: Array(repeating: Float(0), count: fftSize - samples.count))
        }

        // Compute FFT with the SAME rectangular window and same fftSize as the
        // live FFT path so the resulting spectrum is bin-compatible with the
        // continuous FFT frames (and with capturedTaps entries from the legacy
        // path).  computeFFT applies the rectangular `window` (np.ones-equivalent)
        // and returns dBFS magnitudes; calibration is applied below to mirror what
        // performFFT does on every live frame.
        var magnitudes = fftAnalyzer.computeFFT(on: chunk)
        guard !magnitudes.isEmpty else {
            gtLog("⚠️ Guitar gated FFT returned empty spectrum")
            scheduleGuitarReEnable()
            return
        }
        let cal = fftAnalyzer.calibrationCorrections
        if !cal.isEmpty && cal.count == magnitudes.count {
            vDSP_vadd(magnitudes, 1, cal, 1, &magnitudes, 1, vDSP_Length(magnitudes.count))
        }
        let frequencies = fftAnalyzer.frequencies

        capturedTaps.append((magnitudes: magnitudes, frequencies: frequencies, captureTime: Date()))
        let peakDb = magnitudes.max() ?? -100
        // DIAG: spectrum fingerprint — sum of first 100 magnitude bins
        let diagSpecHash: Float = magnitudes.count >= 100 ? magnitudes[0..<100].reduce(0, +) : 0
        let diagSampleHash: Float = samples.count >= 16 ? samples[0..<16].reduce(0, +) : 0
        TAP_DEBUG("guitarGatedCapture", "FINISHED | newCount=\(capturedTaps.count)/\(numberOfTaps) capturedPeakMag=\(String(format: "%.2f", peakDb))dB samples=\(samples.count) specHash=\(String(format: "%.4f", diagSpecHash)) sampleHash=\(String(format: "%.6f", diagSampleHash))")

        // Update currentPeaks and identifiedModes from the captured spectrum so
        // the UI shows peak annotations and the Analysis Results table after each
        // tap — matching the Python behaviour where analyze_magnitudes() runs on
        // every live FFT frame during capture.
        let peaks = findPeaks(magnitudes: magnitudes, frequencies: frequencies)
        currentPeaks = peaks
        selectedPeakIDs = Set(peaks.map { $0.id })
        let modeMap = GuitarMode.classifyAll(peaks)
        identifiedModes = peaks.map { (peak: $0, mode: modeMap[$0.id] ?? .unknown) }

        currentTapCount = capturedTaps.count
        tapProgress = min(1.0, Float(currentTapCount) / Float(numberOfTaps))

        if currentTapCount < numberOfTaps {
            statusMessage = "Tap \(currentTapCount)/\(numberOfTaps) captured. Tap again..."
            scheduleGuitarReEnable()
        } else {
            statusMessage = "All taps captured. Processing..."
            captureTimer?.invalidate()
            captureTimer = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + captureWindow) { [weak self] in
                self?.processMultipleTaps()
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
        // DIAG: log what goes into computeGatedFFT
        let nonZero = samples.filter { $0 != 0 }.count
        let peakSample = samples.map { abs($0) }.max() ?? 0
        let rmsAll: Float = {
            let s = samples.reduce(Float(0)) { $0 + $1 * $1 }
            return 20 * log10(max(sqrt(s / max(Float(samples.count), 1)), 1e-10))
        }()
        TAP_DEBUG("gatedFFT", "FINISH | total=\(samples.count) nonZero=\(nonZero) peak=\(String(format: "%.6f", peakSample)) rms=\(String(format: "%.2f", rmsAll))dB rate=\(Int(sampleRate)) phase=\(phase)")

        dumpCaptureWAV(samples: samples, sampleRate: sampleRate,
                       label: phase.rawValue.replacingOccurrences(of: " ", with: "_"))

        let (magnitudes, frequencies) = fftAnalyzer.computeGatedFFT(samples: samples, sampleRate: sampleRate)

        guard !magnitudes.isEmpty else {
            gtLog("⚠️ Gated FFT returned empty spectrum — tap again")
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
                // fL: longitudinal bending mode of a free rectangular plate blank.
                // Gore course data: ~43–77 Hz across tonewoods (Gore & Gilet Vol.1 §4.5).
                // Note: fL and fLC ranges overlap (~43–77 Hz vs ~25–76 Hz); the tap
                // orientation physically selects the mode — fL is excited by a tap near
                // the centre of the long edge, not a corner tap.
                // Upper bound 100 Hz covers outliers; lower bound 20 Hz excludes DC/rumble.
                hpsMinHz = 20; hpsMaxHz = 100
            case .capturingCross:
                // fC: cross-grain bending mode of a free rectangular plate blank.
                // Gore course data: ~57–194 Hz across tonewoods (Gore & Gilet Vol.1 §4.5).
                // Upper bound 220 Hz covers outliers; lower bound 40 Hz excludes fL/fLC.
                hpsMinHz = 40; hpsMaxHz = 220
            case .capturingFlc, .waitingForFlcTap:
                // fLC: torsional (twist) mode of a free rectangular plate blank.
                // Gore course data: ~25–76 Hz across tonewoods (Gore & Gilet Vol.1 §4.5).
                // fLC is weak and overlaps fL in frequency; it is distinguished by tap
                // placement (corner tap) and the characteristic low-amplitude ring-out.
                // Upper bound 100 Hz covers outliers; lower bound 15 Hz is near the limit
                // of typical measurement microphones.
                hpsMinHz = 15; hpsMaxHz = 100
            default:
                hpsMinHz = 15; hpsMaxHz = 220
            }
        default:
            hpsMinHz = 20; hpsMaxHz = 2000
        }

        // For plate fL and fLC phases the tap orientation physically selects the
        // lowest resonant mode, so prefer the lowest significant peak.
        // For plate fC the strongest peak is correct — the cross-grain tap excites
        // fC as the dominant resonance; preferring the lowest would risk
        // re-selecting fL if it appears in the spectrum.
        // For brace mode, always use the strongest peak — there is only one
        // resonance of interest and it should dominate the spectrum.
        let preferLowest = mType != .brace
            && (phase == .capturingLongitudinal
                || phase == .capturingFlc || phase == .waitingForFlcTap)

        // Find the dominant peak using harmonic product spectrum analysis.
        // This finds the fundamental regardless of whether harmonics are louder.
        guard let dominantPeak = findDominantPeak(magnitudes: magnitudes,
                                                   frequencies: frequencies,
                                                   minHz: hpsMinHz,
                                                   maxHz: hpsMaxHz,
                                                   preferLowestSignificant: preferLowest) else {
            gtLog("⚠️ Gated FFT: no peak found — tap again")
            statusMessage = "No resonance detected — tap again"
            reEnableDetectionForNextPlateTap()
            return
        }

        // The FFT magnitude gate was removed because the rising-edge RMS tap
        // trigger has already confirmed a real physical strike before the gated
        // FFT capture runs.  The threshold slider's VU meter shows time-domain
        // RMS, but FFT bin magnitudes at a single frequency are a fundamentally
        // different (and typically lower) quantity — comparing them against the
        // same threshold caused valid taps to be rejected even when the VU meter
        // showed the tap well above the slider.  FLC and brace modes already
        // skipped this gate for the same reason; now all modes are consistent.

        gtLog("📊 Gated FFT complete: \(magnitudes.count) bins, dominant peak \(String(format: "%.1f", dominantPeak.frequency)) Hz @ \(String(format: "%.1f", dominantPeak.magnitude)) dB, phase \(phase)")

        // Store spectrum so the UI can display it and the user can select alternate peaks
        materialCapturedTaps.append((magnitudes: magnitudes, frequencies: frequencies, captureTime: Date()))
        currentTapCount += 1
        tapProgress = min(1.0, Float(currentTapCount) / Float(totalPlateTaps))

        // Route to phase handler, passing the full spectrum for display and the
        // dominant peak for auto-selection.
        switch phase {
        case .capturingLongitudinal:
            handleLongitudinalGatedProgress(magnitudes: magnitudes,
                                            frequencies: frequencies,
                                            dominantPeak: dominantPeak)
        case .capturingCross:
            handleCrossGatedProgress(magnitudes: magnitudes,
                                     frequencies: frequencies,
                                     dominantPeak: dominantPeak)
        case .capturingFlc, .waitingForFlcTap:
            handleFlcGatedProgress(magnitudes: magnitudes,
                                   frequencies: frequencies,
                                   dominantPeak: dominantPeak)
        case .notStarted, .complete,
             .reviewingLongitudinal, .reviewingCross, .reviewingFlc:
            gtLog("⚠️ Unexpected gated FFT capture in phase: \(phase)")
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
            gtLog("🔇 Q-filtered out low-Q peaks: \(rejStr)")
        }
        let pool = highQCandidates.isEmpty ? candidates : highQCandidates

        let byMagnitude = pool.sorted { $0.magnitude > $1.magnitude }
        let strongest = byMagnitude[0]

        let best: Candidate
        if preferLowestSignificant {
            // For longitudinal and cross-grain taps the tap orientation physically
            // selects the plate's fundamental (lowest) resonant mode.
            // Among Q-filtered candidates, pick the lowest-frequency one within 6 dB
            // of the strongest. The previous 15 dB window admitted spurious
            // low-frequency peaks (impact artifacts, environmental noise) that
            // happened to pass the Q ≥ 3 filter. 6 dB matches the tolerance
            // used in the non-preferLowest path and is tight enough to reject
            // these while still allowing a genuine fundamental that is slightly
            // quieter than its harmonics.
            let thresholdDB = strongest.magnitude - 6.0
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
        gtLog("🎯 Dominant peak: \(String(format: "%.1f", freq)) Hz @ \(String(format: "%.1f", mag)) dB (Q: \(String(format: "%.1f", best.qFactor)), HPS score: \(String(format: "%.3e", best.hpsScore)))")
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
    /// Transitions to `.reviewingLongitudinal` (plate) or `.complete` (brace)
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
        gtLog("📊 Gated LONGITUDINAL tap \(captured)/\(total): \(String(format: "%.1f", dominantPeak.frequency)) Hz")

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
        gtLog("🔵 Auto-selected longitudinal peak: \(dominantPeak.frequency) Hz")

        currentPeaks      = longitudinalPeaks
        // Only the identified (auto-selected) peak is selected — others are informational.
        selectedPeakIDs   = Set([dominantPeak.id])
        materialCapturedTaps = []

        let isBrace = TapDisplaySettings.measurementType == .brace
        if isBrace {
            if let selPeak = longitudinalPeaks.first(where: { $0.id == dominantPeak.id }) {
                currentPeaks = [selPeak]
            } else {
                currentPeaks = [dominantPeak]
            }
            setFrozenSpectrum(frequencies: [], magnitudes: [])
            materialTapPhase = .complete
            isMeasurementComplete = true
            tapProgress = 1.0
            statusMessage = "Complete - check Results"
            gtLog("✅ Brace measurement complete: fL=\(dominantPeak.frequency) Hz")
        } else if fftAnalyzer.isPlayingFile {
            // File playback: auto-advance L → C without pausing at the review state.
            // The file audio flows continuously, so pausing detection would miss
            // the cross-grain taps that follow immediately.
            materialTapPhase = .capturingCross
            setFrozenSpectrum(frequencies: [], magnitudes: [])
            isAboveThreshold = false
            isDetecting = true
            tapDetected = false
            statusMessage = "File: L complete, capturing C..."
            gtLog("📂 File playback: auto-advancing L → C")
        } else {
            // Freeze the L spectrum for display and pause at the review state.
            // The user must press Accept (advance to C) or Redo (re-capture L).
            setFrozenSpectrum(frequencies: avgFreqs, magnitudes: avgMags)
            materialTapPhase = .reviewingLongitudinal
            isDetecting = false
            statusMessage = "fL: \(String(format: "%.1f", dominantPeak.frequency)) Hz — Accept to continue or Redo to re-tap"
        }
    }

    /// Builds the ordered list of resolved plate/brace peaks for display after
    /// each gated-FFT capture phase completes.
    ///
    /// For each of the three plate peak slots (longitudinal, cross, FLC), the
    /// method prefers the user- or auto-selected peak, then falls back to the
    /// first peak from the corresponding captured array. Slots whose arrays are
    /// empty are skipped. An explicit `override` peak (the just-captured
    /// dominant peak) can replace the cross or FLC slot.
    ///
    /// - Parameters:
    ///   - includeCross: Whether to include the cross-grain slot.
    ///   - crossOverride: If non-nil, used as the cross-grain peak instead of
    ///     `selectedCrossPeak` / `crossPeaks.first`.
    ///   - includeFlc: Whether to include the FLC slot.
    ///   - flcOverride: If non-nil, used as the FLC peak instead of
    ///     `selectedFlcPeak` / `flcPeaks.first`.
    /// - Returns: Ordered array `[longitudinal?, cross?, flc?]` with nils dropped.
    func resolvedPlatePeaks(
        includeCross: Bool = true,
        crossOverride: ResonantPeak? = nil,
        includeFlc: Bool = false,
        flcOverride: ResonantPeak? = nil
    ) -> [ResonantPeak] {
        var sel: [ResonantPeak] = []
        if let p = selectedLongitudinalPeak { sel.append(p) }
        else if let p = longitudinalPeaks.first { sel.append(p) }
        if includeCross {
            let cross = crossOverride ?? selectedCrossPeak ?? crossPeaks.first
            if let p = cross { sel.append(p) }
        }
        if includeFlc {
            let flc = flcOverride ?? selectedFlcPeak ?? flcPeaks.first
            if let p = flc { sel.append(p) }
        }
        return sel
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
        gtLog("📊 Gated CROSS-GRAIN tap \(captured)/\(total): \(String(format: "%.1f", dominantPeak.frequency)) Hz")

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
        gtLog("🟠 Auto-selected cross-grain peak: \(dominantPeak.frequency) Hz")
        materialCapturedTaps = []

        currentPeaks = combinePlatePeaks()
        // Only the identified (auto-selected) peaks are selected — others are informational.
        selectedPeakIDs = Set([autoSelectedLongitudinalPeakID, autoSelectedCrossPeakID].compactMap { $0 })

        if fftAnalyzer.isPlayingFile {
            // File playback: auto-advance past the review state.
            let measureFlc = TapDisplaySettings.measureFlc
            if measureFlc {
                // Skip reviewingCross AND tapCooldown — go straight to capturingFlc.
                // The cooldown exists for user repositioning; irrelevant for file audio.
                materialTapPhase = .capturingFlc
                setFrozenSpectrum(frequencies: [], magnitudes: [])
                isAboveThreshold = false
                isDetecting = true
                tapDetected = false
                statusMessage = "File: C complete, capturing FLC..."
                gtLog("📂 File playback: auto-advancing C → FLC")
            } else {
                // No FLC: measurement complete.
                let sel = resolvedPlatePeaks(crossOverride: selectedCrossPeak ?? crossPeaks.first)
                currentPeaks = sel
                selectedPeakIDs = Set(sel.map { $0.id })
                setFrozenSpectrum(frequencies: [], magnitudes: [])
                materialTapPhase = .complete
                isMeasurementComplete = true
                tapProgress = 1.0
                let fLStr = selectedLongitudinalPeak.map { String(format: "%.1f", $0.frequency) } ?? "?"
                let fCStr = selectedCrossPeak.map { String(format: "%.1f", $0.frequency) } ?? "?"
                statusMessage = "File complete — fL: \(fLStr) Hz, fC: \(fCStr) Hz"
                gtLog("📂 File playback: C complete, measurement done (no FLC)")
            }
        } else {
            // Freeze the C spectrum for display and pause at the review state.
            // The user must press Accept (advance to FLC or complete) or Redo (re-capture C).
            setFrozenSpectrum(frequencies: avgFreqs, magnitudes: avgMags)
            materialTapPhase = .reviewingCross
            isDetecting = false
            statusMessage = "fC: \(String(format: "%.1f", dominantPeak.frequency)) Hz — Accept to continue or Redo to re-tap"
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
        gtLog("📊 Gated FLC tap \(captured)/\(total): \(String(format: "%.1f", dominantPeak.frequency)) Hz")

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
        gtLog("🟣 Auto-selected FLC peak: \(dominantPeak.frequency) Hz")
        materialCapturedTaps = []

        let sel = resolvedPlatePeaks(includeCross: true, includeFlc: true, flcOverride: selectedFlcPeak ?? dominantPeak)
        currentPeaks = sel
        selectedPeakIDs = Set(sel.map { $0.id })

        if fftAnalyzer.isPlayingFile {
            // File playback: auto-complete without pausing at the review state.
            setFrozenSpectrum(frequencies: [], magnitudes: [])
            materialTapPhase = .complete
            isMeasurementComplete = true
            tapProgress = 1.0
            statusMessage = "File complete - check Results"
            gtLog("📂 File playback: FLC complete, measurement done")
        } else {
            // Freeze the FLC spectrum for display and pause at the review state.
            // The user must press Accept (complete) or Redo (re-capture FLC).
            setFrozenSpectrum(frequencies: avgFreqs, magnitudes: avgMags)
            materialTapPhase = .reviewingFlc
            isDetecting = false
            statusMessage = "fLC: \(String(format: "%.1f", dominantPeak.frequency)) Hz — Accept to complete or Redo to re-tap"
        }
        gtLog("📊 FLC review: L=\(longitudinalPeaks.first?.frequency ?? 0) C=\(crossPeaks.first?.frequency ?? 0) FLC=\(dominantPeak.frequency) Hz")
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
        // Use an adaptive noise-floor threshold (median of the full spectrum)
        // for the plate/brace peak list. This mirrors findDominantPeak's approach
        // and self-calibrates to each tap's actual signal level, independent of
        // the guitar-mode peakMinThreshold which is disabled in the UI for plate/brace.
        let sortedMags = magnitudes.sorted()
        let medianThreshold: Float = sortedMags[sortedMags.count / 2]

        // Run the standard finder with no range restrictions so the user can see
        // and manually select any peak in the spectrum.
        var peaks = findPeaks(magnitudes: magnitudes, frequencies: frequencies, peakMinOverride: medianThreshold)
        // Replace any nearby peak with dominantPeak so UUID is always consistent.
        // This is critical: autoSelectedXxxPeakID == dominantPeak.id, so the peak
        // stored in the array must share that UUID for ID-based lookups to work.
        if let idx = peaks.firstIndex(where: { abs($0.frequency - dominantPeak.frequency) < TapToneAnalyzer.peakProximityHz }) {
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
            gtLog("⚠️ Warning: Spectrum lengths don't match, using first tap only")
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
        
        gtLog("📊 Averaged \(taps.count) spectra: \(spectrumLength) bins each")
        
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
        
        gtLog("🔬 Processing \(capturedTaps.count) taps for averaging...")
        
        // Average the per-tap magnitude spectra in the frequency domain
        let (avgMagnitudes, avgFrequencies) = averageSpectra(from: capturedTaps)
        
        // Store the averaged spectrum for display and peak recalculation.
        // Use setFrozenSpectrum so both arrays update in one objectWillChange notification —
        // assigning them separately causes a transient length mismatch between render passes.
        setFrozenSpectrum(frequencies: avgFrequencies, magnitudes: avgMagnitudes)
        isMeasurementComplete = true
        gtLog("📸 Guitar spectrum captured from \(capturedTaps.count) averaged taps")
        
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
        loadedMeasurementPeaks = nil      // New live result — no longer remapping from a loaded measurement
        selectedPeakFrequencies = []      // Reset frequency cache for the new live session
        
        // Classify modes using context-aware algorithm so overlapping ranges resolve correctly
        let captureModeMap = GuitarMode.classifyAll(peaksFromAveragedSpectrum)
        identifiedModes = peaksFromAveragedSpectrum.map { (peak: $0, mode: captureModeMap[$0.id] ?? .unknown) }
        
        // Update status
        statusMessage = "Analysis complete! \(peaksFromAveragedSpectrum.count) peaks identified (from \(capturedTaps.count) averaged taps)."
        tapProgress = 1.0
        
        gtLog("✅ Found \(peaksFromAveragedSpectrum.count) peaks in averaged spectrum from \(capturedTaps.count) taps")

        // Build per-tap entries for the multi-tap comparison view.
        // Only meaningful when more than one tap was captured; single-tap sessions
        // have nothing to compare and the toggle is hidden from the UI.
        if capturedTaps.count > 1 {
            let displayMin = TapDisplaySettings.minFrequency
            let displayMax = TapDisplaySettings.maxFrequency
            let displayMinDB = TapDisplaySettings.minMagnitude
            let guitarType = TapDisplaySettings.guitarType
            let measurementType = TapDisplaySettings.measurementType
            let showUnknown = TapDisplaySettings.showUnknownModes

            tapEntries = capturedTaps.enumerated().map { index, tap in
                let tapPeaks = findPeaks(magnitudes: tap.magnitudes, frequencies: tap.frequencies)
                let modeSelected = guitarModeSelectedPeakIDs(from: tapPeaks)
                let snap = SpectrumSnapshot(
                    frequencies: tap.frequencies,
                    magnitudes: tap.magnitudes,
                    minFreq: displayMin,
                    maxFreq: displayMax,
                    minDB: displayMinDB,
                    maxDB: 0,
                    isLogarithmic: false,
                    showUnknownModes: showUnknown,
                    guitarType: guitarType,
                    measurementType: measurementType,
                    maxPeaks: maxPeaks
                )
                return TapEntry(
                    id: UUID(),
                    tapIndex: index + 1,
                    snapshot: snap,
                    peaks: tapPeaks,
                    selectedPeakIDs: Array(modeSelected)
                )
            }
            gtLog("📋 Built \(tapEntries.count) per-tap entries for multi-tap comparison")
        } else {
            tapEntries = []
        }
    }
}
