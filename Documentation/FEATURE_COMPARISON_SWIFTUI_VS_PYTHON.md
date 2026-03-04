# GuitarTap: SwiftUI vs Python App Feature Comparison

This document compares the two implementations of GuitarTap:

1. **SwiftUI app** — Native iOS/macOS app (`GuitarTap/`)
2. **Python app** — PyQt6 desktop app (`guitar_tap/`)

---

## Features Only in the SwiftUI App

### Material & Brace Acoustic Analysis

- **Three-phase tap measurement** (longitudinal, cross-grain, FLC/diagonal) — `TapToneAnalyzer+SpectrumCapture.swift`, `MaterialTapPhase.swift`
- **Young's modulus (EL, EC), speed of sound, specific modulus, radiation ratio, cross/long stiffness ratio** — `MaterialProperties.swift`
- **Gore plate thicknessing formula** — target plate thickness calculation for guitar bodies — `MaterialProperties.goreTargetThickness()`
- **Wood quality assessment** (Excellent / Very Good / Good / Fair / Poor ratings) — `MaterialProperties.WoodQuality`
- **Brace-specific measurement mode** — `BraceProperties` in `MaterialProperties.swift`
- **Pre-roll buffer for gated FFT capture** — captures the tap attack before threshold trigger — `TapToneAnalyzer+SpectrumCapture.swift`

### Automatic Tap Detection

- **Rising-edge hysteresis tap detection** with noise floor EMA tracking — `TapToneAnalyzer+TapDetection.swift`
- **Warm-up period** to prevent false startup triggers — `TapToneAnalyzer+Control.swift`
- **Tap cooldown** between successive detections — `TapToneAnalyzer+TapDetection.swift`
- **Relative vs. absolute threshold modes** (material/brace vs. guitar) — `TapToneAnalyzer+TapDetection.swift`
- **Spectrum freeze at tap detection** — live spectrum locks at moment of tap — `TapToneAnalyzer.isSpectrumFrozen`

### Multi-Tap Averaging

- **True multi-tap signal averaging** (1–5+ taps) with progress tracking and per-tap accumulation — `TapToneAnalyzer.swift`, `TapToneAnalyzer.numberOfTaps`

### Decay Time Measurement

- **Ring-out duration tracking** — time for signal to fall below configurable threshold — `TapToneAnalyzer+DecayTracking.swift`
- **Per-buffer fast decay tracking** at ~10 Hz update rate — `trackDecayFast(inputLevel:)`
- **Decay quality assessment** — `TapToneAnalyzer+DecayTracking.swift`

### Tap Tone Ratio

- **Top/Air frequency ratio** calculation per measurement — `TapToneMeasurement.tapToneRatio`

### Guitar Mode Classification

- **Automatic mode classification** into Air/Helmholtz, Top, Back, Dipole, Ring Mode, Upper Modes — `GuitarMode.swift`
- **Per-guitar-type frequency ranges** for mode detection — `GuitarType.modeRanges`
- **Mode boundary markers** overlaid on the spectrum display — `SpectrumView.swift`
- **Guitar type selection**: Classical, Flamenco, Acoustic — `GuitarType` enum

### Microphone Calibration

- **Import `.cal` calibration files** (e.g., from UMIK-1 measurement microphones) — `MicrophoneCalibration.swift`
- **Frequency-dependent correction curves** applied during FFT processing — `RealtimeFFTAnalyzer.performFFT(on:)`
- **Linear interpolation** of correction at arbitrary frequencies — `MicrophoneCalibration.correction(at:frequency:)`
- **Per-device calibration persistence** across sessions — `RealtimeFFTAnalyzer.activeCalibration`

### Peak Q Factor / Bandwidth

- **Quality factor (Q) and bandwidth** calculated per detected peak — `ResonantPeak.quality`, `ResonantPeak.bandwidth`

### Interactive Spectrum Visualization

- **Pinch-to-zoom and drag-to-pan** gestures on the spectrum chart — `SpectrumView.swift`
- **Area + line chart overlay** using SwiftUI Charts — `SpectrumView.swift`
- **Logarithmic vs. linear frequency scale** toggle — `TapDisplaySettings.isLogarithmic`
- **Auto-scale dB axis** button — `SpectrumView.swift`
- **Draggable peak annotation labels** — `TapToneAnalyzer+AnnotationManagement.swift`, `SpectrumView.swift` (`DraggablePeakAnnotation`)
- **Per-peak visibility toggling** (show/hide individual peaks) — `TapToneAnalyzer.hiddenPeakIDs`

#### Draggable Peak Annotation Labels — Detail

The SwiftUI annotation system is implemented from scratch as a `ZStack` overlay rendered on top of the SwiftUI Charts view, using `DragGesture` for interaction.

- **Coordinate system:** Labels are positioned in screen pixel coordinates, computed by manually converting each peak's frequency and dB value against the chart's `plotFrame` geometry (`calculateChartPosition()`). The stored offset is a `CGPoint` in pixels. When the chart is panned or zoomed, `onChange` handlers on `minFreq`, `maxFreq`, `minDB`, `maxDB`, `plotFrame`, and scale recalculate the cached pixel positions to keep labels from drifting — `DraggablePeakAnnotation.onChange(of:)`
- **Gesture conflict handling:** Because both chart panning and annotation dragging use `DragGesture`, an `isAnnotationDragging: Bool` flag disables the chart-level pan/zoom gestures while a label is being moved (`simultaneousGesture(isAnnotationDragging ? nil : panGesture)`). `highPriorityGesture` is used on the label to win gesture arbitration — `SpectrumView.chartView`
- **Connector line:** A dashed straight `Path` line (no arrowhead) drawn in a `ZStack` layer beneath the label — `ConnectionLine`
- **Label content:** A structured card showing mode name (auto-classified), musical note + cents offset (guitar mode only), formatted frequency, and magnitude in dB — `PeakAnnotationLabel`
- **Reset:** Right-click context menu on each label offers "Reset Position"; a "Reset Labels" item also appears in the chart context menu (disabled when no offsets exist) — `DraggablePeakAnnotation.contextMenu`, `SpectrumView.baseChart`
- **Hover feedback (macOS):** Border widens on hover; cursor changes to `NSCursor.openHand`; tooltip shows "Drag to reposition label" or "Drag to adjust • Right-click to reset position" — `DraggablePeakAnnotation.onHover`
- **Persistence:** Offsets stored in `TapToneAnalyzer.peakAnnotationOffsets: [UUID: CGPoint]`, saved into `TapToneMeasurement`, and restored via `applyAnnotationOffsets(_:)` when loading a saved measurement

### Measurement Persistence & Management

- **Save measurements** with tap location metadata and free-text notes — `TapToneAnalyzer+MeasurementManagement.swift`, `SaveMeasurementSheet.swift`
- **Spectrum snapshot** embedded in each saved measurement — `SpectrumSnapshot.swift`
- **Chart image capture** per measurement — `TapToneMeasurement.chartImageFilename`
- **Measurement list with detail view** — `MeasurementsListView.swift`, `MeasurementDetailView.swift`
- **Load a saved measurement** back into the analysis view — `TapToneAnalyzer.loadMeasurement(timestamp:)`
- **JSON export/import** of full measurement data — `MeasurementFileExporter.swift`, `ExportView.swift`
- **Microphone and calibration metadata** embedded in each measurement record — `TapToneMeasurement.microphoneName`

### PDF Report Generation

- **Full PDF reports** including spectrum chart, peak table, decay time, and material properties — `PDFReportGenerator.swift`

### Settings

- **FFT hop size / overlap control** (0–75%) — `TapDisplaySettings.hopSizeOverlap`
- **FLC measurement toggle** — `TapDisplaySettings.measureFlc`
- **Gore plate thicknessing presets** — `PlateStiffnessPreset`
- **Material and brace dimension inputs** (length, width, thickness, mass) — `TapSettingsView.swift`
- **Tap detection threshold and hysteresis** configurable in settings UI — `TapSettingsView.swift`

### Help System

- **In-app help documentation** covering operation, settings, and tips — `HelpView.swift`

### Platform Features

- **iOS support** (iPhone/iPad responsive layouts, AVAudioSession device enumeration) — `PlatformAdapters.swift`
- **CoreAudio hardware device enumeration** with listener registration on macOS — `RealtimeFFTAnalyzer.loadAvailableInputDevicesMacOS()`
- **Audio route change detection** and automatic engine recovery — `RealtimeFFTAnalyzer.handleRouteChange()`

---

## Features Only in the Python App

### Interactive Draggable Annotations

- **Fully draggable text annotations** with arrow connectors positioned on the FFT plot — `fft_annotations.py`, `FftAnnotations`
- **Musical note range indicators** (upper/lower frequency bounds drawn on plot per peak) — `FftAnnotations`
- **Show/hide individual annotations** independently — `FftAnnotations`

#### Draggable Annotations — Detail

The Python annotation system is built on Matplotlib's native annotation support, activated by a single `ann.draggable()` call.

- **Coordinate system:** Annotations live in data coordinates (Hz on X, dB on Y). Matplotlib handles the screen transform automatically, so when you drag a label it moves in frequency/magnitude space. The stored position (`ann.xyann`) is also in data coordinates — `FftAnnotations.annotation_moved()`
- **Drag mechanism:** Matplotlib's built-in draggable annotation framework intercepts mouse press/move/release events and repositions the annotation object directly. No manual gesture routing or coordinate math is required — `create_annotation()` via `ann.draggable()`
- **Connector line:** A proper curved arrow (`arrowstyle="->"`, `connectionstyle="arc3"`) drawn by Matplotlib between the label and the peak data point — `FftAnnotations.create_annotation()`
- **Label content:** Plain text only — whatever string the user assigned as the mode label (e.g., "Top", "Helmholtz"). No frequency, magnitude, or pitch information is shown in the annotation itself; those appear in the separate peaks table
- **Note range indicators:** When an annotation is created, two vertical dashed red lines (`axvline`) are drawn at the upper and lower semitone boundaries of the peak's nearest note, and the corresponding note names are added to the secondary x-axis. These are removed when the annotation is hidden — `FftAnnotations.create_annotation()`, `hide_annotation()`
- **Pan/zoom conflict:** No conflict because chart pan/zoom is toolbar-button-driven (not drag gestures), so Matplotlib's annotation drag handling operates independently
- **Persistence:** In-memory only for the session. Positions are stored in `self.annotations` list of dicts and in `ann.xyann`, but are not saved to disk and do not survive app restart
- **Reset:** No reset-to-default concept. Annotations can be hidden (`hide_annotation()`) or fully cleared (`clear_annotations()`), but there is no way to return a moved annotation to its original position without clearing it

### User-Assigned Mode Labels

- **Manual mode assignment** via an in-table combo box editor — `mode_combo_delegate.py`, `ModeComboDelegate`
- **Richer mode vocabulary**: Helmholtz, Top, Back, Cross Dipole, Long Dipole, Quadrapole, Cross Tripole — `peaks_model.py`

### Mouse-Click Peak Picking

- **Click on FFT plot** to select/deselect individual peaks interactively — `fft_canvas.py`
- **Click on table row** to clear a peak — `PeakTableView`

### Continuous Spectrum Averaging

- **Rolling FFT frame averaging** (1–10 frames) with completion counter — `fft_canvas.py`
- **"Restart averaging" control** — `PeakControls`
- **Visual averaging-complete LED indicator** — `GtImages`, `peaks_controls.py`

### Peak Hold

- **"Hold Results" toggle** to freeze displayed peaks independently of the live spectrum — `peaks_controls.py`

### CSV Export

- **Save detected peaks to CSV** for external analysis — `peaks_table.py`, `PeakTable.save_peaks()`

### Threshold Slider with Amplitude Visualization

- **Custom-painted QSlider** showing real-time signal amplitude as a cyan-to-blue gradient fill — `threshold_slider.py`, `ThresholdSlider`

### Secondary Musical Note Axis

- **Second x-axis on the FFT chart** displaying chromatic note names at corresponding frequencies — `fft_canvas.py`

### Parabolic Peak Interpolation

- **Sub-bin peak accuracy** via parabolic interpolation of FFT magnitude — `freq_anal.peak_interp()`

### Configurable FFT Window Function

- **Boxcar or Blackman window** selectable (Blackman present but commented out) — `fft_canvas.py`

### Dual Audio Backend Support

- **Runtime switch between PyAudio and SoundDevice** backends via `USE_SOUNDDEVICE` flag — `configure.py`

### Windows Single-Instance Enforcement

- **Named mutex** prevents multiple simultaneous instances on Windows — `named_mutex.py`, `NamedMutex`

### Matplotlib Navigation Toolbar

- **Standard pan/zoom/save toolbar** — `fft_toolbar.py`, `FftToolbar`
- **Custom home button** restoring y-limits to −100 dB
- **Grid toggle** (major/minor gridlines)
- **Keyboard shortcuts** for navigation

---

## Features Present in Both

| Feature | SwiftUI | Python |
|---|---|---|
| Real-time FFT magnitude spectrum display | `SpectrumView`, `RealtimeFFTAnalyzer` | `fft_canvas.py` |
| Hann window FFT processing | `RealtimeFFTAnalyzer.performFFT` | `freq_anal.dft_anal` |
| 65,536-sample FFT window @ 48 kHz | `RealtimeFFTAnalyzer` | `configure.py` |
| Peak detection above amplitude threshold | `TapToneAnalyzer+PeakAnalysis` | `freq_anal.peak_detection` |
| Musical note + cents mapping per peak | `Pitch.swift` | `pitch.py` |
| Configurable frequency display range | `TapDisplaySettings.minFrequency` | `peaks_controls.py` f_min/f_max |
| Audio device selection UI | `TapSettingsView` | `show_devices*.py` |
| macOS microphone permission handling | `RealtimeFFTAnalyzer` | `mac_access.py` |
| Real-time performance stats (FPS, resolution, processing time) | `FFTAnalysisMetricsView` | `PeakControls` stats display |
| Audio capture (AVAudioEngine or PyAudio/SoundDevice) | `RealtimeFFTAnalyzer` | `microphone.py`, `microphone_sd.py` |
| Per-peak mode identification display | `GuitarMode`, results view | `peaks_model.py` Modes column |
