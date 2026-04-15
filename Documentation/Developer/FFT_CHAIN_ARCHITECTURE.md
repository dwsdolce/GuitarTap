# FFT Chain Architecture

GuitarTap has two distinct FFT processing chains that share the same audio
hardware input but diverge immediately after sample delivery.

---

## Overview

### Diagram FFT Chain Architecture
![alt text](<FFT_CHAIN_ARCHITECTURE-Diagram 1 — Background Thread.drawio.svg>)

---

## Continuous FFT Chain (Guitar Mode)

Used for live spectrum display and guitar tap detection. Operates on a
rolling window of audio samples.

### Stage 1 — Audio Capture

**File:** `RealtimeFFTAnalyzer+EngineControl.swift`

| What | Details |
|------|---------|
| Method | `start()` installs AVAudioEngine tap |
| Buffer size | 1 024 samples (hardcoded `maxSafeBufferSize`) |
| Rate | Hardware sample rate (~44 100 Hz) |
| Thread | CoreAudio thread → `audioProcessingQueue.async` |

The 1 024-sample buffer is intentionally small: it gives a ~23 ms level
meter update rate (`inputLevelDB`, `recentPeakLevelDB`) independent of
the longer FFT window.

### Stage 2 — Sample Accumulation and Level Metering

**File:** `RealtimeFFTAnalyzer+FFTProcessing.swift` — `processAudioBuffer(_:)`

On every 1 024-sample callback:

1. Calls `rawSampleHandler?(samples, actualSampleRate)` — feeds the gated chain.
2. Computes RMS level → `inputLevelDB` and `recentPeakLevelDB` (main thread).
3. Appends samples to `inputBuffer` (protected by `bufferAccessQueue`).
4. While `inputBuffer.count >= fftSize`: extracts a `fftSize`-sample chunk,
   advances `inputBuffer` by `hopSize`, calls `performFFT(on:)`.

**Hop size** controls overlap and therefore frame rate:

```
hopSize = fftSize × (1 − hopSizeOverlap / 100)
frameRate = sampleRate / hopSize
```

Default is 0% overlap → one FFT per `fftSize` samples (~2.7 Hz at 44 100 Hz
with `fftSize = 16 384`).

**Key data:**

| Property | Type | Description |
|----------|------|-------------|
| `inputBuffer` | `[Float]` | Accumulator; access via `bufferAccessQueue` |
| `fftSize` | `Int` | FFT window size (power of 2, default 16 384) |
| `hopSizeOverlap` | `Float` | 0–75%; 0 = no overlap |
| `inputLevelDB` | `@Published Float` | Per-callback RMS level (dBFS) |
| `recentPeakLevelDB` | `@Published Float` | 2-second rolling peak (dBFS) |

### Stage 3 — FFT Computation

**File:** `RealtimeFFTAnalyzer+FFTProcessing.swift` — `performFFT(on:)`

1. Apply rectangular (boxcar) window — all ones, no windowing effect.
   Chosen to preserve flat amplitude response for the live display.
2. Deinterleave even/odd samples into `realParts` / `imagParts`
   (required by `vDSP_DFT_zrop` split-complex format).
3. Execute FFT: `vDSP_DFT_Execute(fftSetup, ...)`.
4. Compute magnitudes: `vDSP_zvabs` → scale by `1/fftSize`.
5. Convert to dB: `vDSP_vdbcon` (20 × log₁₀).
6. Apply microphone calibration corrections (`calibrationCorrections[]`).
7. Find peak bin → `peakFrequency`, `peakMagnitude`.
8. Throttle UI publish to ≥ 500 ms intervals (`minPublishInterval`).
9. Publish `magnitudes`, `peakFrequency`, `peakMagnitude`, `displayLevelDB`
   on main thread.

**Key data:**

| Property | Type | Description |
|----------|------|-------------|
| `fftSetup` | `vDSP_DFT_Setup` | Pre-allocated DFT setup (reused each frame) |
| `window` | `[Float]` | Rectangular window coefficients (all 1.0) |
| `magnitudes` | `@Published [Float]` | dBFS spectrum, `fftSize/2` bins |
| `frequencies` | `@Published [Float]` | Hz axis matching `magnitudes` |
| `peakMagnitude` | `@Published Float` | Strongest bin (dBFS) |
| `peakFrequency` | `@Published Float` | Frequency of strongest bin (Hz) |
| `calibrationCorrections` | `[Float]` | Pre-interpolated per-bin dB offsets |

### Stage 4 — Tap Detection (Guitar Mode)

**File:** `TapToneAnalyzer+TapDetection.swift` — `detectTap()`

Called from `analyzeMagnitudes()` on the main thread each FFT frame.

Uses **absolute threshold with hysteresis**:

```
risingThreshold  = tapDetectionThreshold
fallingThreshold = tapDetectionThreshold − hysteresisMargin
```

State machine:

```
below threshold  ──rising edge──►  above threshold (tap fires)
above threshold  ──falling edge──►  below threshold (ready for next tap)
```

Guards: warm-up period (0.5 s), tap cooldown, `isDetecting` flag.

On confirmed rising edge: sets `tapPeakLevel = fftAnalyzer.recentPeakLevelDB`,
calls `handleTapDetection()`.

### Stage 5 — Guitar Tap Accumulation

**File:** `TapToneAnalyzer+TapDetection.swift` — `handleTapDetection()`

Appends `(magnitudes, frequencies, captureTime)` to `capturedTaps[]`.
Starts decay tracking. After `numberOfTaps` taps collected, schedules
`processMultipleTaps()` via `captureWindow` timer.

**File:** `TapToneAnalyzer+SpectrumCapture.swift` — `processMultipleTaps()`

Averages all captured spectra in the **linear power domain**:

```
p_avg[bin] = (1/N) × Σ 10^(dB_n[bin] / 10)
dB_avg[bin] = 10 × log₁₀(p_avg[bin])
```

Runs `findPeaks()` on the averaged spectrum → `currentPeaks[]`.

---

## Gated FFT Chain (Plate / Brace Mode)

Used for material property measurements. Captures a short raw-PCM window
around each tap onset and runs a separate, higher-quality FFT on it.

The gated chain is more accurate than the continuous chain for short-decay
materials because it avoids the energy dilution from averaging the tap
transient across a long FFT window.

### Stage 1 — Pre-Roll Ring Buffer

**File:** `TapToneAnalyzer+SpectrumCapture.swift` — `accumulateGatedSamples(_:sampleRate:)`

Called by `rawSampleHandler` on **every** 1 024-sample audio callback
(background thread, `audioProcessingQueue`). Maintains a ring buffer of
the most recent `preRollSamples` audio samples at all times.

```
preRollSamples = preRollDuration × sampleRate
                 (default 200 ms → ~8 820 samples at 44 100 Hz)
```

Protected by `mpmLock` (NSLock).

### Stage 2 — Tap Detection (Plate/Brace Mode)

**File:** `TapToneAnalyzer.swift` — `setupSubscriptions()`, sink on `$inputLevelDB`
**File:** `TapToneAnalyzer+TapDetection.swift` — `detectTap()`

Plate/brace tap detection is driven by a **dedicated Combine subscription to
`fftAnalyzer.$inputLevelDB`**, not by the continuous FFT path. This is
intentional: the long-window FFT dilutes a short tap transient by ~15 dB,
making `peakMagnitude` unreliable for plate/brace detection. The `inputLevelDB`
RMS level updates at ~43 Hz and captures the transient spike cleanly.

```swift
fftAnalyzer.$inputLevelDB
    .receive(on: DispatchQueue.main)
    .sink { levelDB in
        guard type == .plate || type == .brace else { return }
        self.detectTap(peakMagnitude: levelDB, ...)
    }
```

Guitar mode uses a separate Combine sink on `$magnitudes`/`$peakMagnitude`
(~2.7 Hz) so the full spectrum is available at tap time.

`detectTap()` uses **relative threshold** against a running noise floor EMA:

```
noiseFloor ← α × level + (1−α) × noiseFloor   (α = 0.05)
headroom   = max(tapDetectionThreshold − noiseFloor, 10 dB)
risingThreshold  = noiseFloor + headroom
fallingThreshold = noiseFloor + max(headroom − hysteresisMargin, 4 dB)
```

Level input is `fftAnalyzer.inputLevelDB` (RMS, ~43 Hz), not `peakMagnitude`.

### Stage 3 — Open Gated Capture Window

**File:** `TapToneAnalyzer+SpectrumCapture.swift` — `startGatedCapture(phase:)`

Called from `handlePlateTapDetection()` on confirmed rising edge.

1. Seeds `gatedAccumBuffer` with current `preRollBuffer` contents
   (so the tap attack, which arrived before detection, is included).
2. Sets `gatedCaptureActive = true`.
3. Schedules 2-second safety timeout on main thread.

```
gatedAccumBuffer = preRollBuffer   ← tap attack captured here
gatedCaptureActive = true
```

Capture window layout:

```
│◄── 200 ms pre-roll ──►│◄──── 400 ms gate ────►│
│  (from ring buffer)   │  (new incoming audio)  │
                        ↑ tap onset detected
```

### Stage 4 — Gated Sample Accumulation

**File:** `TapToneAnalyzer+SpectrumCapture.swift` — `accumulateGatedSamples(_:sampleRate:)`

When `gatedCaptureActive == true`, each incoming 1 024-sample chunk is
appended to `gatedAccumBuffer` under `mpmLock`.

When `gatedAccumBuffer.count >= gatedCaptureSamples`:

```
gatedCaptureSamples = gatedCaptureDuration × sampleRate
                      (default 400 ms → ~17 640 samples at 44 100 Hz)
```

1. Sets `gatedCaptureActive = false`.
2. Trims buffer to exactly `gatedCaptureSamples`.
3. Dispatches `finishGatedFFTCapture(samples:sampleRate:phase:)` to main thread.

Protected by `mpmLock` throughout.

### Stage 5 — Gated FFT Computation

**File:** `RealtimeFFTAnalyzer+FFTProcessing.swift` — `computeGatedFFT(samples:sampleRate:)`

Called from `finishGatedFFTCapture()` on the main thread.

Differences from the continuous FFT:

| | Continuous FFT | Gated FFT |
|---|---|---|
| Input | `fftSize` samples from ring buffer | Pre-roll + gate window (variable length) |
| FFT size | Fixed `fftSize` | Next power-of-two ≤ 32 768 |
| Window | Rectangular (all ones) | **Hann** (`vDSP_hann_window`) |
| DFT setup | Pre-allocated, reused | Created per-call, `defer`-destroyed |
| Output | Published `@Published` properties | Returned as `(magnitudes, frequencies)` |
| Calibration | Pre-computed `calibrationCorrections[]` | Interpolated per-call from `activeCalibration` |

The Hann window is used here because the gated result feeds material
property calculations — sidelobe suppression improves frequency accuracy
and Q-factor readings. The tap buffer naturally starts and ends near
silence, so edge amplitude roll-off is not a concern.

### Stage 6 — Dominant Peak Selection

**File:** `TapToneAnalyzer+SpectrumCapture.swift` — `findDominantPeak()`

Two-pass algorithm on the gated FFT output:

**Pass 1 — Candidate collection** (search window: per-phase Hz bounds):

For each local maximum above the median noise floor:
- Compute HPS score: `linear[i] × linear[2i] × linear[3i]`
- Compute Q factor via −3 dB bandwidth method
- Add to `candidates[]`

**Pass 2 — Selection:**

1. Filter out candidates with Q < 3 (impact thuds / broadband noise).
2. If `preferLowestSignificant` (longitudinal / cross-grain phases):
   pick the lowest-frequency candidate within 15 dB of the strongest.
3. Otherwise: strongest wins unless a lower-frequency candidate is
   within 6 dB and has HPS score within one order of magnitude
   (prefers fundamental over harmonics).
4. Refine with **parabolic interpolation** for sub-bin accuracy.

Returns a `ResonantPeak`.

Per-phase frequency search windows:

| Phase | Min Hz | Max Hz | Rationale |
|-------|--------|--------|-----------|
| Brace (longitudinal) | 100 | 1 200 | Exclude sub-100 Hz table thud |
| Plate — longitudinal | 50 | 500 | fL mode range |
| Plate — cross-grain | 20 | 250 | fC mode range |
| Plate — FLC | 20 | 200 | fLC shear mode; tight cap avoids harmonics |

### Stage 7 — Phase Routing and Averaging

**File:** `TapToneAnalyzer+SpectrumCapture.swift`

Phase state machine:

```
notStarted
    │
    ▼ start()
capturingLongitudinal ──► (N taps) ──► averageSpectra() ──► longitudinalSpectrum
    │
    ▼ (plate only)
waitingForCrossTap ──► capturingCross ──► (N taps) ──► averageSpectra() ──► crossSpectrum
    │
    ▼ (FLC enabled)
waitingForFlcTap ──► capturingFlc ──► (N taps) ──► averageSpectra() ──► flcSpectrum
    │
    ▼
complete
```

Spectrum averaging (same as guitar mode) uses linear power domain:

```
p_avg = (1/N) × Σ 10^(dB_n / 10)
dB_avg = 10 × log₁₀(p_avg)
```

Handlers: `handleLongitudinalGatedProgress()`, `handleCrossGatedProgress()`,
`handleFlcGatedProgress()`.

---

## Key Data Structures

### `ResonantPeak`
**File:** `ResonantPeak.swift`

The primary output of both chains. Produced by parabolic interpolation.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `UUID` | Stable identity for SwiftUI / dictionaries |
| `frequency` | `Float` | Centre frequency (Hz), sub-bin accurate |
| `magnitude` | `Float` | Peak level (dBFS) |
| `quality` | `Float` | Q factor = f₀ / Δf₋₃dB |
| `bandwidth` | `Float` | −3 dB bandwidth (Hz) |
| `pitchNote` | `String?` | Nearest equal-temperament note, e.g. "A4" |
| `pitchCents` | `Double?` | Cents deviation from `pitchNote` |
| `pitchFrequency` | `Double?` | Frequency of `pitchNote` (Hz) |

### Spectrum tuple
Used throughout as `(magnitudes: [Float], frequencies: [Float])`.

- `magnitudes`: dBFS values, one per bin
- `frequencies`: Hz values, one per bin, same length

### `capturedTaps` (guitar mode)
`[(magnitudes: [Float], frequencies: [Float], captureTime: Date)]`

Accumulates raw continuous-FFT frames per tap. Averaged by
`processMultipleTaps()`.

### `materialCapturedTaps` (plate/brace mode)
`[(magnitudes: [Float], frequencies: [Float], captureTime: Date)]`

Accumulates gated-FFT frames per phase. Averaged per phase by the
phase handlers.

### `preRollBuffer` / `gatedAccumBuffer`
`[Float]` — raw PCM samples (mono, ±1.0 normalised).
Both protected by `mpmLock` (NSLock).

---

## Thread Model

| Activity | Thread |
|----------|--------|
| AVAudioEngine tap callback | CoreAudio thread |
| `processAudioBuffer(_:)` | `audioProcessingQueue` (serial) |
| `rawSampleHandler` / `accumulateGatedSamples` | `audioProcessingQueue` |
| `inputBuffer` access | `bufferAccessQueue` (serial, sync) |
| `mpmLock`-protected buffer writes | `audioProcessingQueue` |
| `gatedAccumBuffer` → `finishGatedFFTCapture` dispatch | `DispatchQueue.main.async` |
| `performFFT` result publish | `DispatchQueue.main.async` |
| `inputLevelDB` / `recentPeakLevelDB` update | `DispatchQueue.main.async` |
| `detectTap` / `handleTapDetection` | Main thread |
| `finishGatedFFTCapture` / `computeGatedFFT` | Main thread |
| `findDominantPeak` | Main thread |

---

## Important Constants

| Constant | Value | Location | Effect |
|----------|-------|----------|--------|
| `maxSafeBufferSize` | 1 024 samples | `+EngineControl.swift` | Hardware tap size; controls level meter rate |
| `fftSize` | 16 384 (default) | `RealtimeFFTAnalyzer.init` | FFT window; controls freq resolution and frame rate |
| `hopSizeOverlap` | 0% (default) | `TapDisplaySettings` | Frame rate multiplier |
| `gatedCaptureDuration` | 400 ms | `TapToneAnalyzer` | Gated window length |
| `preRollDuration` | 200 ms | `TapToneAnalyzer` | Pre-roll ring buffer length |
| `minPublishInterval` | 500 ms | `RealtimeFFTAnalyzer` | Throttle on UI publish (2 Hz) |
| `peakHoldDuration` | 2.0 s | `RealtimeFFTAnalyzer` | `recentPeakLevelDB` hold time |
| Gated FFT max size | 32 768 | `computeGatedFFT` | ~0.74 Hz/bin at 44 100 Hz |
| Min Q filter | 3.0 | `findDominantPeak` | Rejects impact thuds |

---

## File Map

| File | Responsibility |
|------|---------------|
| `RealtimeFFTAnalyzer.swift` | Class declaration, all stored properties, `init`/`deinit` |
| `RealtimeFFTAnalyzer+EngineControl.swift` | `start()`, `stop()`, AVAudioEngine tap setup |
| `RealtimeFFTAnalyzer+FFTProcessing.swift` | `processAudioBuffer`, `performFFT`, `computeGatedFFT`, `resample`, metrics |
| `RealtimeFFTAnalyzer+DeviceManagement.swift` | Device enumeration, CoreAudio/AVAudioSession listeners, `setInputDevice` |
| `TapToneAnalyzer+TapDetection.swift` | `detectTap`, `handleTapDetection`, `handlePlateTapDetection`, hysteresis state machine |
| `TapToneAnalyzer+SpectrumCapture.swift` | `accumulateGatedSamples`, `startGatedCapture`, `finishGatedFFTCapture`, `findDominantPeak`, phase handlers, spectrum averaging |
| `TapToneAnalyzer+PeakAnalysis.swift` | `findPeaks`, `parabolicInterpolate`, `calculateQFactor` |
| `TapToneAnalyzer+DecayTracking.swift` | `startDecayTracking`, decay curve fitting |
| `ResonantPeak.swift` | `ResonantPeak` struct definition |
