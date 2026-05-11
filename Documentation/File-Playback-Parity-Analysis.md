# File Playback: Swift vs Python Structural Parity Analysis

**Date:** 2026-05-10
**Context:** After achieving exact numerical parity (512.6 Hz @ -65.5 dB) between Swift and Python file playback for the same brace WAV file, this document catalogs remaining structural divergences and recommends which can be eliminated to reduce long-term maintenance burden.

## Current State

The core algorithm is functionally identical end-to-end:

```
stop mic → drain queue → zero-fill pre-roll → read file →
pace chunks via sleep → RMS → tap detection → gated accumulate →
Hann window → FFT → peak selection →
partial flush → flush gated capture → restart mic
```

The divergences below are structural — places where the two codebases solve the same problem with different mechanisms, creating maintenance friction when changes must be mirrored.

---

## Divergences: Removable

These can be unified to use the same pattern in both codebases.

### 1. Pre-Roll Zero-Fill Location

| | Swift | Python |
|--|-------|--------|
| **Where** | `postEngineStopHandler` callback fired from `RealtimeFFTAnalyzer` back to `TapToneAnalyzer` | Inline in `TapToneAnalyzer.start_from_file()` at line 539 |
| **Why different** | Swift's `RealtimeFFTAnalyzer` doesn't have access to `preRollBuffer` (it lives on `TapToneAnalyzer`), so a callback bridges the two objects. Python's `start_from_file` lives on `TapToneAnalyzer` itself, so it can set `_pre_roll_buf` directly. |

**Recommendation:** Move Swift's pre-roll zero-fill into `TapToneAnalyzer.startFromFile()` directly, after calling `fftAnalyzer.startFromFile()` returns from its synchronous teardown phase but before the worker starts pumping chunks. This would eliminate `postEngineStopHandler` entirely. Requires `startFromFile` to split into a synchronous teardown phase and an async worker launch, which it effectively already does — the zero-fill just needs to happen between them.

Alternatively, add the same `post_engine_stop_handler` callback to Python for symmetry. The Swift approach is arguably more correct (zero-fill happens provably after drain, before any chunks), but it adds a callback that Python doesn't need.

### 2. Worker Cancellation Pattern

| | Swift | Python |
|--|-------|--------|
| **Pattern** | Generation counter (`filePlaybackGeneration`). Worker checks `myGeneration == self.filePlaybackGeneration` each iteration. | Boolean flag (`is_playing_file = False`) + explicit `thread.join(timeout=0.5)` |

**Recommendation:** Adopt generation counter in Python. It's cleaner — no join/timeout, no risk of blocking, and handles rapid re-invocation gracefully. The boolean flag approach requires careful ordering (set flag before join, check flag is still false after join) that the generation counter avoids.

### 3. Partial Flush Dispatch Thread

| | Swift | Python |
|--|-------|--------|
| **Where** | Main thread (inside `DispatchQueue.main.async` block after worker ends) | Playback worker thread (before mic restart) |

**Recommendation:** Move Swift's partial flush to run on the worker thread (or audio queue) before dispatching to main, matching Python. The FFT computation itself doesn't need the main thread. Only the UI update afterward does.

### 4. `preMicRestartHandler` Dispatch

| | Swift | Python |
|--|-------|--------|
| **Call site** | `DispatchQueue.main.sync` from worker thread | Direct call from playback worker thread |
| **Handler body** | `flushGatedCaptureOnFileEnd()` runs on main thread | `_flush_gated_capture_on_file_end()` runs on worker thread, emits Qt signal to main thread |

**Recommendation:** The `DispatchQueue.main.sync` wrapper in Swift was added to fix `@Published` warnings. If the flush logic itself doesn't touch `@Published` properties, it could run on the worker thread like Python, with only the final UI emission dispatched to main. This would make the call sites structurally identical.

### 5. RMS Level Handler Wiring Timing

| | Swift | Python |
|--|-------|--------|
| **When wired** | Once at init in `setupSubscriptions()` — permanent | Each time in `start_from_file()` — per-playback |
| **Pattern** | Closure property on `RealtimeFFTAnalyzer`, set once | Lambda assigned to `mic._on_pre_mic_restart`, set per call |

**Recommendation:** Wire once at init in Python to match Swift. The callbacks don't change between invocations — rewiring per-call is unnecessary and obscures the lifetime.

### 6. TAP_DEBUG Call Count Disparity

| | Swift | Python |
|--|-------|--------|
| **Calls** | 47 TAP_DEBUG calls | 18 TAP_DEBUG calls |

Both codebases use `TAP_DEBUG` (not `logger.debug`). But Swift has 2.6x more instrumentation points, many added during this debugging session. Some are diagnostic scaffolding that should be reviewed.

**Recommendation:** Audit both codebases and converge on a common set of TAP_DEBUG call sites with identical categories and message formats. When a TAP_DEBUG exists in one codebase, its counterpart should exist in the other at the structurally equivalent location. Remove any that were purely temporary debugging aids.

---

## Divergences: Inherent (Platform-Imposed)

These cannot be removed — they reflect fundamental platform differences.

### 7. Audio Engine API

| | Swift | Python |
|--|-------|--------|
| **Engine** | AVAudioEngine (`engine.inputNode.removeTap`, `engine.stop()`, `engine.start()`) | PortAudio via sounddevice (`stream.stop()`, `stream.start()`) |

No action possible. Different platforms, different audio APIs.

### 8. File Reading Library

| | Swift | Python |
|--|-------|--------|
| **Library** | Custom `readWavFileAsMonoFloat32` (RIFF/WAV byte parser) | `soundfile.read()` (libsndfile wrapper, supports WAV/AIFF/FLAC/OGG) |

`AVAudioFile` silently truncates frames (returned 18421 from a 19200-frame file), so the custom parser was necessary. This is an inherent platform limitation.

**Note:** The custom parser only supports WAV. If non-WAV file playback is ever needed in Swift, this will need extension.

### 9. Queue Drain Mechanism

| | Swift | Python |
|--|-------|--------|
| **Pattern** | `audioProcessingQueue.sync {}` (GCD serial queue barrier) | `None` sentinel + `Event` handshake on dedicated `_FftProcessingThread` |

Both achieve the same result (block until all queued work completes). The mechanism differs because Swift uses GCD serial queues while Python uses a dedicated thread with an explicit work queue.

### 10. Threading Primitives

| | Swift | Python |
|--|-------|--------|
| **Worker thread** | `DispatchQueue.global(qos:).async` | `threading.Thread(daemon=True)` |
| **Main thread dispatch** | `DispatchQueue.main.sync` / `.async` | Qt signal/slot (queued connection) |
| **Locks** | `NSLock` (`mpmLock`) | `threading.Lock` (`_gated_lock`) |

No action possible. Different concurrency frameworks.

### 11. Inter-Object Communication

| | Swift | Python |
|--|-------|--------|
| **Pattern** | Closure properties (`rawSampleHandler`, `rmsLevelHandler`, etc.) wired in `setupSubscriptions()` | Qt signals/slots + lambda callbacks assigned per-call |

Both decouple `RealtimeFFTAnalyzer` from `TapToneAnalyzer`. The mechanism is dictated by the UI framework (SwiftUI vs Qt).

---

## Priority Order for Convergence

1. **TAP_DEBUG parity** (item 6) — Lowest effort, highest maintenance value. Converge on identical instrumentation points so logs from both platforms can be compared side-by-side.

2. **Worker cancellation** (item 2) — Adopt generation counter in Python. Small change, eliminates the join/timeout fragility.

3. **Callback wiring timing** (item 5) — Wire once at init in Python. Trivial change, reduces per-call ceremony.

4. **Pre-roll zero-fill location** (item 1) — Either add `post_engine_stop_handler` to Python or restructure Swift's `startFromFile` to do it inline. Medium effort, eliminates a callback that only exists in Swift.

5. **Partial flush thread** (item 3) and **preMicRestartHandler dispatch** (item 4) — Lower priority. These work correctly now; the divergence is which thread runs the computation vs which thread receives the result.

---

## Files Referenced

**Swift:**
- `GuitarTap/Models/RealtimeFFTAnalyzer+EngineControl.swift` — `startFromFile`, `readWavFileAsMonoFloat32`, worker loop, post-playback
- `GuitarTap/Models/RealtimeFFTAnalyzer.swift` — callback property declarations
- `GuitarTap/Models/TapToneAnalyzer.swift` — `setupSubscriptions()` wiring
- `GuitarTap/Models/TapToneAnalyzer+Control.swift` — `startTapSequence`, `startFromFile`
- `GuitarTap/Models/TapToneAnalyzer+SpectrumCapture.swift` — `accumulateGatedSamples`, `flushGatedCaptureOnFileEnd`

**Python** (`/Users/dws/src/guitar_tap/src/guitar_tap/`):
- `models/realtime_fft_analyzer_engine_control.py` — `start_from_file`, `_playback_worker`, drain barrier
- `models/tap_tone_analyzer_control.py` — `start_from_file`, `start_tap_sequence`
- `models/tap_tone_analyzer_spectrum_capture.py` — `_accumulate_gated_samples`, `_flush_gated_capture_on_file_end`
- `models/tap_tone_analyzer_tap_detection.py` — `_on_rms_level_changed`, `detect_tap`
