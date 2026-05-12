# File Playback Regression Test Plan

**Date:** 2026-05-10
**Status:** Plan — not yet implemented

## Goal

Create end-to-end regression tests that exercise the full file-playback pipeline — WAV reading → chunk pacing → RMS → tap detection → gated capture → Hann window → FFT → peak selection → mode identification — in both Swift and Python, without requiring audio hardware.

The tests must cover guitar, brace, and plate measurement modes using user-supplied WAV files.

## Current State

### What Already Works

Both codebases already have file-playback tests at the **FFT level**:

- **Swift:** `FilePlaybackPipelineTests.swift` processes WAV files through `computeFFT`/`findPeaks` directly, bypassing tap detection and gated capture.
- **Python:** `test_file_playback.py` processes WAV files through `dft_anal`/`peak_detection` directly, bypassing tap detection and gated capture.

Both codebases can also construct analyzers for unit testing:

- **Swift:** `makeSUT()` creates `RealtimeFFTAnalyzer()` + `TapToneAnalyzer(fftAnalyzer:)`, then calls `sut.cancellables.removeAll()` to disconnect Combine subscriptions.
- **Python:** `TapToneAnalyzer()` constructs with no arguments (no audio hardware), but has no `RealtimeFFTAnalyzer` wired (`.mic` is `None`).

### What's Missing

No test exercises the **full pipeline** end-to-end: file → tap detection → gated capture → spectrum → peaks → mode classification.  The file-playback path (`startFromFile`) is entangled with audio hardware in two places:

1. **Constructor**: Swift creates `AVAudioEngine`; Python opens `sd.InputStream`.
2. **Post-playback**: Both restart the microphone after file playback ends.

## Approach: `forTesting` / `for_testing` Factory + `processFileData` / `process_file_data` Extraction

### Step 1: Extract `processFileData` from `startFromFile`

Factor the data-processing core out of the hardware lifecycle wrapper. The new method takes mono samples + sample rate as input and drives the pipeline synchronously (no real-time pacing needed for tests).

#### Swift — `RealtimeFFTAnalyzer+EngineControl.swift`

Extract from `startFromFile(_:completion:)` (lines 484–648):

```swift
/// Processes pre-read audio samples through the FFT pipeline.
///
/// This is the data-processing core of startFromFile, factored out so
/// tests can drive the pipeline without audio hardware.  The worker
/// loop, partial flush, and preMicRestartHandler call are all included.
/// The mic stop/restart and UI state management are NOT included.
///
/// - Parameters:
///   - samples: Mono Float32 PCM samples.
///   - sampleRate: Sample rate in Hz.
///   - fileName: Display name for status/logging.
func processFileData(samples: [Float], sampleRate: Double, fileName: String) {
    // Reset ordinals
    fftFrameCounter = 0
    samplesConsumed = 0

    actualSampleRate = sampleRate
    updateFrequencyBins()
    updateMetrics()

    magnitudes = [Float](repeating: -100, count: fftSize / 2)
    peakMagnitude = -100
    lastPublishTime = 0
    isPlayingFile = true
    playingFileName = fileName

    let chunkSize = 1024
    let chunkDuration = Double(chunkSize) / sampleRate
    let myGeneration = filePlaybackGeneration

    // Pump chunks (synchronous for tests, paced for real playback)
    var idx = 0
    while idx < samples.count {
        guard filePlaybackGeneration == myGeneration else { return }
        let end = min(idx + chunkSize, samples.count)
        let chunk = Array(samples[idx..<end])
        audioProcessingQueue.sync {
            processRawSamples(chunk)
        }
        idx = end
        Thread.sleep(forTimeInterval: chunkDuration)
    }

    // Partial flush
    audioProcessingQueue.sync {
        var partial: [Float] = []
        bufferAccessQueue.sync {
            partial = inputBuffer
            inputBuffer.removeAll()
        }
        if !partial.isEmpty {
            if partial.count < fftSize {
                partial.append(contentsOf: [Float](repeating: 0,
                    count: fftSize - partial.count))
            }
            performFFT(on: partial)
        }
    }

    // Flush gated capture
    DispatchQueue.main.sync {
        preMicRestartHandler?()
    }

    isPlayingFile = false
}
```

#### Python — `realtime_fft_analyzer_engine_control.py`

Extract from `start_from_file()` / `_playback_worker()`:

```python
def process_file_data(self, samples: np.ndarray, sample_rate: int,
                      file_name: str) -> None:
    """Process pre-read audio through the FFT pipeline.

    Data-processing core of start_from_file, factored out so tests can
    drive the pipeline without audio hardware.
    """
    self.rate = sample_rate
    self.is_playing_file = True
    self.playing_file_name = file_name
    self.is_stopped = False

    chunksize = self.chunksize
    chunk_duration = chunksize / sample_rate
    idx = 0

    while idx < len(samples):
        if not self.is_playing_file:
            return
        end = min(idx + chunksize, len(samples))
        chunk = samples[idx:end]
        self.queue.put(chunk)
        idx = end
        time.sleep(chunk_duration)

    # Partial flush — mirrors _playback_worker post-loop
    self.proc_thread.process_partial_flush()

    # Flush gated capture
    if hasattr(self, '_on_pre_mic_restart') and self._on_pre_mic_restart:
        self._on_pre_mic_restart()

    self.is_playing_file = False
```

**Structural correspondence:**

| Step | Swift `processFileData` | Python `process_file_data` |
|------|------------------------|---------------------------|
| Reset ordinals | `fftFrameCounter = 0` | (handled by proc_thread) |
| Set sample rate | `actualSampleRate = sampleRate` | `self.rate = sample_rate` |
| Update bins | `updateFrequencyBins()` | (auto from rate) |
| Chunk loop | `audioProcessingQueue.sync { processRawSamples(chunk) }` | `self.queue.put(chunk)` |
| Pacing | `Thread.sleep(forTimeInterval:)` | `time.sleep(chunk_duration)` |
| Partial flush | `performFFT(on: partial)` | `proc_thread.process_partial_flush()` |
| Gated flush | `preMicRestartHandler?()` | `self._on_pre_mic_restart()` |

### Step 2: `forTesting` / `for_testing` Factory Methods

#### Swift

```swift
extension RealtimeFFTAnalyzer {
    /// Creates a RealtimeFFTAnalyzer suitable for testing.
    /// No AVAudioEngine, no inputNode, no CoreAudio listeners.
    static func forTesting(fftSize: Int = 16384) -> RealtimeFFTAnalyzer {
        // Construct with a flag that skips hardware init
        let analyzer = RealtimeFFTAnalyzer(fftSize: fftSize, forTesting: true)
        return analyzer
    }
}
```

This requires adding a `forTesting: Bool = false` parameter to `init(fftSize:)` that, when `true`:
- Skips `audioEngine = AVAudioEngine()` (or creates it but never starts it — TBD which is simpler)
- Skips `loadAvailableInputDevices()`
- Skips `registerMacOSHardwareListener()`
- Skips iOS route-change observer registration
- Still initializes `fftSetup`, `magnitudes`, `frequencies`, `window`, `audioProcessingQueue`, `bufferAccessQueue`

```swift
extension TapToneAnalyzer {
    /// Creates a TapToneAnalyzer wired for file-playback testing.
    /// Subscriptions are connected (unlike makeSUT which disconnects them)
    /// so the full pipeline operates, but no audio engine is started.
    static func forTesting(fftSize: Int = 16384) -> TapToneAnalyzer {
        let fft = RealtimeFFTAnalyzer.forTesting(fftSize: fftSize)
        let analyzer = TapToneAnalyzer(fftAnalyzer: fft)
        // Subscriptions remain connected — we WANT the pipeline to work.
        return analyzer
    }
}
```

#### Python

```python
@classmethod
def for_testing(cls, fft_size: int = 16384,
                sample_rate: int = 48000) -> "RealtimeFFTAnalyzer":
    """Create a RealtimeFFTAnalyzer for testing — no PortAudio stream."""
    obj = cls.__new__(cls)
    # Initialize only computational state, skip sd.InputStream
    obj.rate = sample_rate
    obj.fft_size = fft_size
    obj.chunksize = 1024
    obj.h_fft_size = fft_size // 2
    obj.m_t = fft_size
    obj.window_fcn = np.ones(fft_size)
    obj.queue = queue.Queue()
    obj._stop_lock = threading.Lock()
    obj.is_stopped = False
    obj.is_playing_file = False
    obj.playing_file_name = None
    obj.raw_sample_handler = None
    obj.stream = None  # No hardware
    obj._selected_input_device = None
    # Start the processing thread (QThread, no hardware dependency)
    obj.proc_thread = _FftProcessingThread(mic=obj)
    return obj
```

```python
@classmethod
def for_testing(cls, fft_size: int = 16384,
                sample_rate: int = 48000) -> "TapToneAnalyzer":
    """Create a TapToneAnalyzer wired for file-playback testing."""
    mic = RealtimeFFTAnalyzer.for_testing(fft_size=fft_size,
                                          sample_rate=sample_rate)
    analyzer = cls(fft_analyzer=mic)
    # Wire signals — mirrors start() but without hardware
    mic.proc_thread.fftFrameReady.connect(analyzer.on_fft_frame)
    mic.proc_thread.rmsLevelChanged.connect(analyzer._on_rms_level_changed)
    mic.proc_thread.gatedCaptureComplete.connect(
        analyzer.finish_gated_fft_capture)
    mic.raw_sample_handler = analyzer._accumulate_gated_samples
    # Level-crossing handler
    def _level_crossing():
        with analyzer._gated_lock:
            analyzer._gated_capture_id += 1
            analyzer._gated_accum = list(analyzer._pre_roll_buf)
            analyzer._gated_capture_samples = fft_size
            analyzer._gated_capture_phase = None
            analyzer._gated_capture_active = True
    mic.proc_thread._level_crossing_handler = _level_crossing
    mic.proc_thread._level_crossing_threshold = analyzer.tap_detection_threshold
    return analyzer
```

**Structural correspondence:**

| Step | Swift `forTesting` | Python `for_testing` |
|------|-------------------|---------------------|
| FFT setup | `vDSP_DFT_zrop_CreateSetup` | `np.ones(fft_size)` window |
| Processing thread | `audioProcessingQueue` (GCD) | `_FftProcessingThread` (QThread) |
| Skip hardware | Skip `AVAudioEngine()` | Skip `sd.InputStream()` |
| Skip device enum | Skip `loadAvailableInputDevices()` | Skip `load_available_input_devices()` |
| Skip listeners | Skip CoreAudio/route-change | Skip hotplug monitor |
| Wire callbacks | Kept via `setupSubscriptions()` | Explicit `connect()` calls |

### Step 3: Convenience Method on `TapToneAnalyzer`

Both codebases need a method that combines "configure measurement type → start tap sequence → play file → wait for completion":

#### Swift

```swift
extension TapToneAnalyzer {
    /// Plays a WAV file through the full pipeline and returns when complete.
    /// For use in tests only — blocks the calling thread.
    func playFileForTesting(url: URL, measurementType: MeasurementType,
                            numberOfTaps: Int = 1) {
        TapDisplaySettings.measurementType = measurementType
        self.numberOfTaps = numberOfTaps

        let (samples, sampleRate) = try! RealtimeFFTAnalyzer
            .readAudioFileAsMonoFloat32(url: url)

        startTapSequence(skipWarmup: true)
        fftAnalyzer.processFileData(samples: samples,
                                     sampleRate: sampleRate,
                                     fileName: url.lastPathComponent)
    }
}
```

#### Python

```python
def play_file_for_testing(self, path: str,
                          measurement_type: MeasurementType,
                          number_of_taps: int = 1) -> None:
    """Play a WAV file through the full pipeline. Blocking. Tests only."""
    TapDisplaySettings.set_measurement_type(measurement_type)
    self.number_of_taps = number_of_taps

    import soundfile as sf
    data, file_rate = sf.read(path, dtype="float32", always_2d=True)
    mono = data.mean(axis=1).astype(np.float32)

    self.start_tap_sequence(skip_warmup=True)
    self.mic.process_file_data(mono, int(file_rate),
                                os.path.basename(path))
```

## Test Structure

### Test Files

| Platform | File | Framework |
|----------|------|-----------|
| Swift | `GuitarTapTests/FilePlaybackRegressionTests.swift` | Swift Testing (`@Test`) |
| Python | `tests/test_file_playback_regression.py` | pytest |

### Test Cases

All tests follow the same pattern:

1. Create analyzer via `forTesting`/`for_testing`
2. Configure measurement type
3. Load WAV file and play through pipeline
4. Assert peak frequency and magnitude within tolerance
5. Assert mode classification (where applicable)

#### Guitar Mode Tests

```
REG-G1: Guitar single-tap — known WAV produces expected peaks
    - Load a guitar tap WAV
    - Play through pipeline with measurementType = .generic
    - Verify: Air peak frequency ± tolerance, Top peak frequency ± tolerance
    - Verify: identifiedModes contains .air and .topPlate

REG-G2: Guitar multi-tap averaging
    - Load a multi-tap WAV (or play single-tap WAV N times)
    - numberOfTaps = N
    - Verify: averaged spectrum peaks match within tolerance
```

#### Brace Mode Tests

```
REG-B1: Brace single-tap — known WAV produces expected fL peak
    - Load a brace tap WAV (saved capture, ~400ms)
    - Play through pipeline with measurementType = .brace
    - Verify: dominant peak frequency matches expected fL ± tolerance
    - Verify: magnitude within ± tolerance of .guitartap reference

REG-B2: Brace frequency search window
    - Same WAV as REG-B1
    - Verify: dominant peak is in [100, 1200] Hz range
    - Verify: peaks outside this range are not selected as dominant
```

#### Plate Mode Tests

```
REG-P1: Plate longitudinal tap — known WAV produces expected fL
    - Load a plate L-tap WAV
    - Play through pipeline with measurementType = .plate
    - Verify: fL frequency ± tolerance
    - Verify: materialTapPhase transitions to .reviewingLongitudinal

REG-P2: Plate cross-grain tap — known WAV produces expected fC
    - Accept L phase, load a plate C-tap WAV
    - Verify: fC frequency ± tolerance
    - Verify: materialTapPhase transitions to .reviewingCross

REG-P3: Plate full sequence (L + C)
    - Play L WAV, accept, play C WAV, accept
    - Verify: both fL and fC match expected values
    - Verify: materialTapPhase == .complete
    - Verify: isMeasurementComplete == true
```

#### Cross-Platform Parity (Not a Test — a Convention)

Swift runs on macOS/iOS. Python runs on macOS/Windows/Linux. There is no
single test harness that can execute both. Instead, parity is enforced by
convention:

- REG-G1, REG-B1, REG-P1, etc. exist in **both** test suites.
- Both suites use the **same WAV files** (shared via relative path or copied).
- Both suites assert the **same expected peak frequencies and magnitudes**
  with the **same tolerances**.
- If both suites pass, the pipelines produce identical results.

When establishing expected values for a new WAV file, run the test on one
platform first, record the actual values, then use those as the expected
values in both suites. If the other platform fails, investigate the
divergence — it indicates a real pipeline difference.

### Test Tolerances

| Parameter | Tolerance | Rationale |
|-----------|-----------|-----------|
| Peak frequency | ± 1.0 Hz | Parabolic interpolation gives sub-bin accuracy; 1 Hz covers rounding |
| Peak magnitude | ± 1.0 dB | Window normalization, edge effects |
| Decay time | ± 50 ms | Chunk timing jitter |

### WAV Files

WAV files will be provided by the user and placed in:

- **Swift:** `GuitarTapTests/TestData/` (added to the test target bundle)
- **Python:** `tests/test_data/` (or shared from the Swift location via relative path, as `test_file_playback.py` already does with `../../GuitarTap/Tests/`)

Each test WAV needs a corresponding expected-values comment or constant block documenting:
- Source (how it was recorded/generated)
- Expected peak frequency and magnitude
- Expected mode classification (if applicable)

## Implementation Order

1. **`RealtimeFFTAnalyzer.forTesting` / `for_testing`** — Add the testing factory to both codebases. Verify that the FFT processing thread starts and can process synthetic data.

2. **`processFileData` / `process_file_data`** — Extract from `startFromFile` / `start_from_file`. Verify that `startFromFile` still works by calling `processFileData` internally.

3. **`TapToneAnalyzer.forTesting` / `for_testing`** — Wire callbacks without hardware. Verify by running a synthetic sine wave through `processFileData` and confirming tap detection fires.

4. **`playFileForTesting` / `play_file_for_testing`** — Convenience wrapper. Verify with a real WAV file.

5. **Write tests** — One test at a time, starting with REG-G1 (guitar) as the simplest path, then REG-B1 (brace), then REG-P1/P2/P3 (plate, most complex due to multi-phase).

6. **Establish expected values** — Run each test once with the provided WAV files, record the actual peak frequencies and magnitudes, and hardcode those as expected values with tolerances.

## Files to Create or Modify

| File | Action | Description |
|------|--------|-------------|
| `RealtimeFFTAnalyzer.swift` | Modify | Add `forTesting` parameter to `init`, add `static func forTesting()` |
| `RealtimeFFTAnalyzer+EngineControl.swift` | Modify | Extract `processFileData`, have `startFromFile` call it |
| `TapToneAnalyzer.swift` | Modify | Add `static func forTesting()` |
| `TapToneAnalyzer+Control.swift` | Modify | Add `playFileForTesting` convenience |
| `GuitarTapTests/FilePlaybackRegressionTests.swift` | Create | All REG-* test cases |
| `realtime_fft_analyzer.py` | Modify | Add `for_testing` classmethod |
| `realtime_fft_analyzer_engine_control.py` | Modify | Extract `process_file_data`, have `start_from_file` call it |
| `tap_tone_analyzer.py` | Modify | Add `for_testing` classmethod |
| `tap_tone_analyzer_control.py` | Modify | Add `play_file_for_testing` convenience |
| `tests/test_file_playback_regression.py` | Create | All REG-* test cases (Python) |

## Risks and Open Questions

1. **Threading in tests**: Swift's `processFileData` dispatches work to `audioProcessingQueue` and flushes gated captures on `DispatchQueue.main`. Tests using `@MainActor` may need to drain the run loop. Python's `_FftProcessingThread` is a `QThread` that needs a running `QApplication` event loop — existing tests already handle this with the `qt_app` fixture.

2. **Real-time pacing**: The `Thread.sleep(chunkDuration)` in `processFileData` means tests take real time (a 1-second WAV takes ~1 second). This is acceptable for a small number of regression tests. If speed becomes an issue, a `pacingEnabled: Bool = true` parameter can skip the sleep.

3. **`startFromFile` refactor risk**: Extracting `processFileData` must not change the behavior of the existing `startFromFile` path. The refactor should be verified by running the app and playing a file before writing any new tests.

4. **Test isolation**: `TapDisplaySettings` uses `UserDefaults` (Swift) and `QSettings` (Python). Both test suites already isolate these — Swift via the `TestRunner.swift` bootstrap, Python via `conftest.py`. The new tests must use the same isolation.
