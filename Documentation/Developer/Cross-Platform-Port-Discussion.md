# GuitarTap Cross-Platform Port Discussion

A conversation exploring technology options for porting GuitarTap to web, Windows, and other platforms.

---

## Web Version

**Q: To create a web-based version of this application, what platform and technologies would you recommend?**

### Recommended Stack: React + Web Audio API + WebAssembly

#### Framework
**React** (or SvelteKit for lighter weight)
- Component model maps well to the existing SwiftUI views
- Good ecosystem for charts and real-time data

#### Real-time Audio Processing
- **Web Audio API** — microphone capture via `getUserMedia()`
- **AudioWorklet** (not the deprecated ScriptProcessorNode) — runs FFT on a dedicated audio thread, equivalent to `audioProcessingQueue`
- **WebAssembly (WASM)** — port FFT + peak-finding logic from Swift/vDSP to C, compile to WASM via Emscripten. This is the most important call: the 65,536-point FFT at 1–2 Hz with parabolic interpolation and Q-factor calculation needs WASM to avoid jank. Pure JS FFT will struggle.

#### Spectrum Visualization
**D3.js** or **uPlot**
- uPlot is extremely fast for time-series/frequency data with canvas rendering
- D3 gives more control for the mode-band overlays and draggable annotations

#### State Management
React Context or Zustand
- `TapToneAnalyzer`'s `@Published` properties map naturally to reactive state

#### Persistence
IndexedDB (via `idb` library) + JSON export
- Mirrors the Documents directory JSON + sidecar PNGs
- Canvas API handles spectrum image capture for export

#### PDF Reports
`jsPDF` + `html2canvas` — covers `PDFReportGenerator`

### Key Challenges

1. **HTTPS is mandatory** — `getUserMedia()` requires a secure context. TLS required even in development (`vite --https` or similar).

2. **SharedArrayBuffer for WASM** — Requires `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` headers. Non-trivial to configure but well-documented.

3. **Audio device enumeration** is limited compared to CoreAudio. UMIK-1 calibration file import will still work (file picker + existing parsing logic ported to JS), but auto-detecting the device by UID won't.

4. **Pre-roll ring buffer** (200ms tap capture) is straightforward in an AudioWorklet — just a circular `Float32Array`.

5. **The multi-phase plate sequencer** (longitudinal → cross → FLC) is pure logic with no platform dependencies — it ports cleanly.

### What to Avoid
- **Next.js** — SSR adds complexity not needed for a client-side DSP tool
- **Electron** — Heavier than Tauri with no upside for this use case
- **Pure JS FFT** — Won't sustain 65k-point FFTs at acceptable frame rates

The WASM FFT + AudioWorklet combination is the critical path. Everything else is progressively buildable on top.

### Alternative: Tauri
If near-native performance is needed and shipping an installer is acceptable, Tauri lets you write the UI in React/Svelte while the DSP backend stays in Rust (which can call existing C FFT code). This avoids the WASM/HTTPS complexity and gives full file system access. The tradeoff is it's no longer a browser-based web app.

---

## Native Windows Version

**Q: How about for a native Windows application?**

### Recommended Stack: C++ with Windows APIs

#### Audio Engine
**WASAPI** (Windows Audio Session API) — the direct equivalent of CoreAudio/AVAudioEngine
- Exclusive mode gives low-latency buffers (similar to AUHAL)
- Shared mode is easier and sufficient for this use case (tap tones aren't latency-critical on capture)
- Device enumeration via `IMMDeviceEnumerator` maps directly to the `AVAudioDevice` model

For a higher-level wrapper, **PortAudio** or **RtAudio** abstract WASAPI/DirectSound/ASIO and allow sharing audio code across Windows/Linux/macOS.

#### FFT
**Intel IPP** or **FFTW** — both match or exceed Apple Accelerate/vDSP performance on x86
- FFTW is open source and battle-tested; direct drop-in for the vDSP DFT setup
- Intel IPP is free for most uses and has a very similar API shape to vDSP

#### UI Framework Options

| Option | Pros | Cons |
|---|---|---|
| **Qt** | Cross-platform, mature, good charting (QCustomPlot/Qt Charts), C++ native | License cost for commercial use (LGPL available) |
| **WinUI 3** | Microsoft's modern native UI, XAML-based, feels like SwiftUI | Windows-only, still maturing |
| **Dear ImGui** | Extremely fast, great for real-time data visualization, easy FFT spectrum display | Not a "polished" app look |
| **Flutter (Windows)** | Dart, cross-platform, modern feel | Audio plugin ecosystem less mature |

**Recommendation: Qt** — closest analog to the existing setup. Qt's signal/slot system maps naturally to `@Published` properties and Combine pipeline. Qt Charts handles spectrum visualization.

#### Architecture Mapping

| Swift/Apple | Windows Equivalent |
|---|---|
| `AVAudioEngine` + tap | WASAPI `IAudioClient` + capture thread |
| `vDSP_DFT_zrop_CreateSetup` | `fftwf_plan_dft_r2c_1d` |
| `Accelerate vDSP_rmsqv` | IPP `ippsNorm_L2_32f` or manual |
| `@Published` + Combine | Qt signals/slots or `std::atomic` + callbacks |
| SwiftUI Charts | Qt Charts / QCustomPlot |
| `UserDefaults` | Windows Registry or `QSettings` |
| Documents directory JSON | `%APPDATA%\GuitarTap\` JSON files |
| `OSLog` | ETW or `spdlog` |

#### Key Advantages Over the Web Port
- No WASM/HTTPS complexity
- Direct float array access to audio buffers — ring buffer and gated FFT translate almost line-for-line to C++
- WASAPI exclusive mode can get <10ms latency if needed
- Full file system access for calibration files, measurement bundles
- Can ship as a single `.exe` with Qt statically linked

#### What to Watch For
- **WASAPI sample rate negotiation** — shared mode may force a different sample rate than 48 kHz depending on the device
- **Thread model** — WASAPI uses a COM apartment model; `CoInitializeEx` required on the audio thread, analogous to `audioProcessingQueue`
- **Float format** — WASAPI can deliver `WAVE_FORMAT_IEEE_FLOAT` directly, so no int→float conversion needed

---

## Language Tradeoffs: Python vs C++ vs C#

**Q: What are the tradeoffs between Python, C++, and C# for this?**

### Python

**Pros:**
- Fastest to prototype — NumPy/SciPy FFT is excellent and nearly as fast as FFTW for this workload
- `sounddevice` library wraps PortAudio cleanly; WASAPI backend works
- Data science ecosystem (matplotlib, pandas) useful for analysis/export
- Easiest to port the math-heavy parts (material properties, peak finding)

**Cons:**
- UI is the weak point — Tkinter looks dated; PyQt/PySide6 works but feels heavy; Dear PyGui is niche
- GIL can create audio callback timing issues — the audio thread would want a C extension anyway
- Real-time performance is unpredictable; garbage collection pauses at bad moments
- Not a great fit for a polished shipping product

**Verdict:** Good for a research/internal tool or proving out algorithms. Not ideal for a product users pay for.

### C++

**Pros:**
- Best raw performance — FFTW or IPP, direct WASAPI access, zero overhead
- Existing DSP logic ports almost mechanically (the algorithms are language-agnostic)
- Qt is genuinely excellent for this kind of application
- Industry standard for audio software (basically all DAWs and audio tools are C++)

**Cons:**
- Slowest development velocity by far
- Memory management burden (though modern C++17/20 with smart pointers reduces this significantly)
- Qt's signal/slot system requires a learning curve coming from SwiftUI
- Build system complexity (CMake, vcpkg for dependencies)

**Verdict:** Best end result, highest cost to get there. Worth it if Windows is a serious long-term target and a professional-grade product is the goal.

### C#

**Pros:**
- **.NET 8 is genuinely fast** — JIT-compiled, no GIL, good float performance. For 65k-point FFT at 1–2 Hz this is more than sufficient.
- **NAudio** is a mature, well-documented WASAPI wrapper — closest thing to AVAudioEngine on Windows
- **WPF or WinUI 3** are solid UI frameworks with good charting options (LiveCharts2, OxyPlot)
- Strong type system, async/await model maps directly to Swift concurrency patterns
- Much faster development than C++; much more polished output than Python
- `System.Numerics` has SIMD intrinsics if FFT performance needs squeezing

**Cons:**
- .NET runtime dependency (though self-contained publish eliminates this)
- FFT libraries less battle-tested than FFTW — `MathNet.Numerics` or `FftSharp` are good but not as optimized
- WinUI 3 is still maturing; WPF is stable but older-looking by default

**Verdict:** The pragmatic sweet spot for this application.

### Recommendation: C#

For GuitarTap specifically:

- The DSP workload (65k FFT at ~2 Hz) is well within .NET's performance envelope — this is a measurement tool, not a streaming audio plugin
- NAudio + WASAPI is the closest Windows analog to the AVAudioEngine setup
- The Swift → C# translation is more natural than Swift → C++ (value types, async/await, properties, generics all exist)
- `@Published` + Combine maps directly to `INotifyPropertyChanged` or ReactiveUI
- JSON serialization (`System.Text.Json`) maps directly to `Codable` models
- Self-contained `.exe` publish requires no runtime dependency on the target machine

The only scenario to choose C++ over C# here is if targeting professional audio engineers who expect plugin-grade latency, or if the DSP core needs to be shared with a DAW plugin. For a standalone measurement tool, C# gets there faster with a result that's hard to distinguish from C++ in practice.

---

## IDE and AI Tooling on Windows

**Q: Does Claude Code (Claude Agent) run in Visual Studio?**

**Claude Code** (the CLI tool) doesn't run inside Visual Studio directly — it's terminal-based. It can be run in a terminal alongside Visual Studio.

### AI Coding Options for Visual Studio

- **GitHub Copilot** — the primary AI coding assistant that integrates natively into Visual Studio. Uses different models than Claude.
- **Continue.dev** — an open-source VS Code extension that supports Claude (via Anthropic API key) as a backend.
- **Cline** — another VS Code extension with Claude support, similar in capability to Claude Code.

### Claude Code in VS Code

There is an official **Claude Code extension for VS Code** that provides the Claude Code experience inside the editor, including the same tool access available in the CLI. For a C# port using VS Code as the Windows IDE, this is a natural fit.

### Recommended Setup for a C# Port

**VS Code + C# Dev Kit extension + Claude Code extension** keeps the current AI-assisted workflow intact while targeting Windows development.
