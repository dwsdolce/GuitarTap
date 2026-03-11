# GuitarTap: SwiftUI vs Python App Feature Comparison

This document compares the two implementations of GuitarTap:

1. **SwiftUI app** — Native iOS/macOS app (`GuitarTap/`)
2. **Python app** — PyQt6 desktop app (`guitar_tap/`)

---

## Features Only in the SwiftUI App

### Material & Brace Acoustic Analysis

- **Three-phase tap measurement** (longitudinal, cross-grain, optional FLC/diagonal) — `TapToneAnalyzer+SpectrumCapture.swift`, `MaterialTapPhase.swift`
- **Young's modulus (EL, EC), speed of sound, specific modulus, radiation ratio, cross/long stiffness ratio** — `MaterialProperties.swift`
- **Gore plate thicknessing formula** — target plate thickness calculation for guitar bodies using body geometry inputs and stiffness presets — `MaterialProperties.goreTargetThickness()`
- **Wood quality assessment** (Excellent / Very Good / Good / Fair / Poor ratings) — `MaterialProperties.WoodQuality`
- **Wood type evaluation** for common tonewoods (Spruce, Cedar, Maple, Rosewood) — `MaterialProperties.swift`
- **Brace-specific measurement mode** with longitudinal stiffness calculation — `BraceProperties` in `MaterialProperties.swift`
- **Per-measurement-type spectrum snapshots** stored per phase (fL, fC, fLC) — `TapToneMeasurement.swift`
- **Pre-roll buffer for gated FFT capture** — captures the tap attack before threshold trigger using a 200ms circular lookback buffer — `TapToneAnalyzer+SpectrumCapture.swift`
- **Plate stiffness presets** (Steel String Top/Back, Classical Top/Back, Custom) for Gore thicknessing — `PlateStiffnessPreset`

### Automatic Tap Detection

- **Rising-edge hysteresis tap detection** with configurable threshold and hysteresis margin — `TapToneAnalyzer+TapDetection.swift`
- **Noise floor EMA tracking** for relative threshold mode (material/brace) — `TapToneAnalyzer+TapDetection.swift`
- **Warm-up period** (500ms) to prevent false startup triggers — `TapToneAnalyzer+Control.swift`
- **Tap cooldown** (500ms minimum between detections) — `TapToneAnalyzer+TapDetection.swift`
- **Relative vs. absolute threshold modes** (material/brace use noise-floor-relative threshold; guitar uses absolute dB) — `TapToneAnalyzer+TapDetection.swift`
- **Spectrum freeze at tap detection** — live spectrum locks at moment of tap — `TapToneAnalyzer.isSpectrumFrozen`
- **Pause/Resume detection** — maintains live spectrum display while paused — `TapToneAnalyzer+Control.swift`

### Multi-Tap Averaging

- **Frequency-domain magnitude averaging** across 1–N taps — each tap produces a separate gated FFT spectrum; spectra are averaged bin-by-bin in the linear power domain (10^(dB/10)) and converted back to dB — `TapToneAnalyzer+SpectrumCapture.swift`, `averageSpectra()`
- Phase is implicitly discarded by computing per-tap magnitude spectra independently before averaging, which is correct for non-periodic impulse responses where inter-tap phase alignment cannot be guaranteed
- **Cancellable multi-tap sequence** with progress tracking — `TapToneAnalysisView+Controls.swift`

### Decay Time Measurement

- **Ring-out duration tracking** — time for signal to fall below configurable dB threshold — `TapToneAnalyzer+DecayTracking.swift`
- **Per-buffer fast decay tracking** at ~10 Hz update rate using RMS input level — `trackDecayFast(inputLevel:)`
- **Decay quality assessment** against per-guitar-type thresholds — `TapToneAnalyzer+DecayTracking.swift`

### Tap Tone Ratio

- **Top/Air frequency ratio** calculation per measurement — `TapToneMeasurement.tapToneRatio`

### Guitar Mode Classification

- **Automatic mode classification** into Air (Helmholtz), Top, Back, Dipole, Ring Mode, Upper Modes — `GuitarMode.swift`
- **Per-guitar-type frequency ranges** for mode detection — `GuitarType.modeRanges`
- **Mode boundary markers** overlaid on the spectrum display — `SpectrumView+ChartContent.swift`
- **Guitar type selection**: Classical, Flamenco, Acoustic — `GuitarType` enum
- **Unknown mode display toggle** — show/hide peaks that don't match any defined mode range — `TapDisplaySettings.showUnknownModes`

### Microphone Calibration

- **Import `.cal` calibration files** (e.g., from UMIK-1 measurement microphones) — `MicrophoneCalibration.swift`
- **Frequency-dependent correction curves** applied during FFT processing — `RealtimeFFTAnalyzer.performFFT(on:)`
- **Linear interpolation** of correction at arbitrary frequencies — `MicrophoneCalibration.correction(at:frequency:)`
- **Per-device calibration persistence** across sessions keyed by device UID — `RealtimeFFTAnalyzer.activeCalibration`
- **Calibration metadata** embedded in each saved measurement — `TapToneMeasurement.microphoneName`

### Peak Q Factor / Bandwidth

- **Quality factor (Q) and bandwidth** calculated per detected peak using −3 dB bandwidth — `ResonantPeak.quality`, `ResonantPeak.bandwidth`

### Interactive Spectrum Visualization

- **Pinch-to-zoom and drag-to-pan** gestures on the spectrum chart — `SpectrumView+GestureHandlers.swift`
- **Scroll wheel zoom with modifier keys** (plain scroll: magnitude pan; Shift: frequency pan; Command: both-axis zoom; Option: frequency zoom; Control: magnitude zoom) — `SpectrumView+GestureHandlers.swift`
- **Anchor-aware zoom** — zoom is centered on the pinch point or cursor location, not the chart center — `SpectrumView+GestureHandlers.swift`
- **Area + line chart overlay** using SwiftUI Charts — `SpectrumView+ChartContent.swift`
- **Logarithmic vs. linear frequency scale** toggle — `TapDisplaySettings.isLogarithmic`
- **Per-measurement-type axis range persistence** — separate min/max freq/dB saved per measurement type — `TapDisplaySettings.swift`
- **Context menu axis reset** — right-click restores saved or default display ranges — `SpectrumView.swift`
- **Material spectra overlay** — display multiple phase spectra (L/C/FLC) as separate series with a legend — `SpectrumView.swift`
- **Cursor/crosshair readout** with frequency and magnitude display — hover on macOS, toggle mode on iOS — `SpectrumView+SnapInterpolation.swift`
- **Series-locked cursor** — cursor snaps to the closest spectrum series on macOS — `SpectrumView+SnapInterpolation.swift`
- **Per-peak visibility toggling** — show/hide individual peaks from the results view — `TapToneAnalyzer.hiddenPeakIDs`
- **Draggable peak annotation labels** — custom `ZStack` overlay with gesture-based repositioning — `PeakAnnotations.swift`, `TapToneAnalyzer+AnnotationManagement.swift`

#### Draggable Peak Annotation Labels — Detail

The SwiftUI annotation system is implemented as a `ZStack` overlay rendered on top of the SwiftUI Charts view, using `DragGesture` for interaction.

- **Coordinate system:** Labels are positioned in screen pixel coordinates, computed by manually converting each peak's frequency and dB value against the chart's `plotFrame` geometry (`calculateChartPosition()`). The stored offset is a `CGPoint` in pixels. When the chart is panned or zoomed, `onChange` handlers on `minFreq`, `maxFreq`, `minDB`, `maxDB`, `plotFrame`, and scale recalculate the cached pixel positions to keep labels from drifting — `DraggablePeakAnnotation.onChange(of:)`
- **Gesture conflict handling:** Because both chart panning and annotation dragging use `DragGesture`, an `isAnnotationDragging: Bool` flag disables the chart-level pan/zoom gestures while a label is being moved (`simultaneousGesture(isAnnotationDragging ? nil : panGesture)`). `highPriorityGesture` is used on the label to win gesture arbitration — `SpectrumView.chartView`
- **Connector line:** A dashed straight `Path` line (no arrowhead) drawn in a `ZStack` layer beneath the label — `ConnectionLine`
- **Label content:** A structured card showing mode name (auto-classified), musical note + cents offset (guitar mode only), formatted frequency, and magnitude in dB — `PeakAnnotationLabel`
- **Annotation visibility modes:** Cycle through all peaks, selected peaks only, or no annotations — `TapToneAnalyzer.annotationVisibility`
- **Reset:** Right-click context menu on each label offers "Reset Position"; a "Reset Labels" item also appears in the chart context menu (disabled when no offsets exist) — `DraggablePeakAnnotation.contextMenu`, `SpectrumView.baseChart`
- **Hover feedback (macOS):** Border widens on hover; cursor changes to `NSCursor.openHand`; tooltip shows "Drag to reposition label" or "Drag to adjust • Right-click to reset position" — `DraggablePeakAnnotation.onHover`
- **Persistence:** Offsets stored in `TapToneAnalyzer.peakAnnotationOffsets: [UUID: CGPoint]`, saved into `TapToneMeasurement`, and restored via `applyAnnotationOffsets(_:)` when loading a saved measurement

### Measurement Persistence & Management

- **Save measurements** with tap location metadata and free-text notes — `TapToneAnalyzer+MeasurementManagement.swift`, `SaveMeasurementSheet.swift`
- **Spectrum snapshot** (full FFT frequency and magnitude arrays + display settings) embedded in each saved measurement — `SpectrumSnapshot.swift`
- **Chart image capture** (PNG) per measurement, stored alongside JSON — `TapToneMeasurement.chartImageFilename`
- **Measurement list with detail view** — `MeasurementsListView.swift`, `MeasurementDetailView.swift`
- **Load a saved measurement** back into the analysis view with full state restoration (display range, annotation offsets, peak selections) — `TapToneAnalyzer.loadMeasurement(timestamp:)`
- **JSON export/import** of full measurement data — `MeasurementFileExporter.swift`, `ExportView.swift`
- **CSV bulk export** of all measurements — `TapToneAnalysisView+Export.swift`
- **Microphone and calibration metadata** embedded in each measurement record — `TapToneMeasurement.microphoneName`
- **Analysis settings snapshot** stored per measurement (threshold, hysteresis, tap count) — `TapToneMeasurement.swift`

### PDF Report Generation

- **Full PDF reports** including spectrum chart image, peak table with Q-factors, decay time, tap tone ratio, material properties, Gore thicknessing estimates, and microphone/calibration info — `PDFReportGenerator.swift`

### Settings

- **FFT hop size / overlap control** (0–75%) affecting frame rate and time-domain averaging — `TapDisplaySettings.hopSizeOverlap`
- **FLC measurement toggle** — enables the optional diagonal shear measurement phase — `TapDisplaySettings.measureFlc`
- **Gore plate thicknessing presets** with custom stiffness override — `PlateStiffnessPreset`
- **Material and brace dimension inputs** (length, width, thickness, mass in mm/grams) — `TapSettingsView.swift`
- **Guitar body geometry inputs** (body length, lower bout width) for Gore calculations — `TapSettingsView.swift`
- **Tap detection threshold and hysteresis** configurable in settings UI — `TapSettingsView.swift`
- **Maximum peak count** limit (0 = unlimited) — `TapDisplaySettings.maxPeaks`
- **Analysis frequency range** for peak search (default 30–2000 Hz) — `TapDisplaySettings.minAnalysisFrequency`

### Help System

- **In-app help documentation** covering operation, settings, and tips — `HelpView.swift`

### Platform Features

- **iOS support** (iPhone/iPad responsive layouts, portrait/landscape, face-up device orientation, AVAudioSession device enumeration) — `PlatformAdapters.swift`, `TapToneAnalysisView+Layouts.swift`
- **CoreAudio hardware device enumeration** with listener registration on macOS — `RealtimeFFTAnalyzer.loadAvailableInputDevicesMacOS()`
- **Audio route change detection** and automatic engine recovery with state re-synchronization — `RealtimeFFTAnalyzer.handleRouteChange()`

---

## Features Only in the Python App

### User-Assigned Mode Labels via In-Table Combo Box

- **Manual mode assignment** via an in-table combo box editor per row — `mode_combo_delegate.py`, `ModeComboDelegate`
- **Richer mode vocabulary in table**: Helmholtz, Top, Back, Cross Dipole, Long Dipole, Quadrapole, Cross Tripole — `peaks_model.py`
- **Mode assignment only enabled when data is held** (prevents accidental edits during live capture) — `ModeComboDelegate.createEditor()`

### Mouse-Click Peak Picking on Plot

- **Click directly on the FFT plot** to select/deselect individual peaks — `fft_canvas.py`
- **Click on table row** to select and highlight a peak — `PeakTableView`
- **Selected peak rendered in a distinct color** on the scatter overlay — `FftCanvas`

### Tap-Gated Frequency-Domain Averaging

- **Frequency-domain magnitude averaging** across 1–10 tap-triggered FFT frames — linear magnitudes are accumulated and divided by frame count, then converted to dB — `fft_canvas.py`, `process_averages()`
- Averaging is gated by tap detection: only frames that exceed the amplitude threshold and trigger peak detection contribute to the average; ambient noise frames are ignored
- Phase is discarded — only magnitude is averaged, which is the correct approach for non-periodic impulse responses where inter-tap phase alignment cannot be guaranteed
- **"Restart averaging" control** to reset accumulation mid-session — `PeakControls`
- **Visual averaging-complete LED indicator** (green when target reached, auto-enables hold) — `GtImages`, `peaks_controls.py`

### Peak Hold

- **"Hold Results" toggle** freezes displayed peaks independently of the live spectrum — `peaks_controls.py`
- **Editing (mode/show columns) only enabled when held** — `ModeComboDelegate`, `ShowButtonDelegate`

### CSV Export

- **Save detected peaks to CSV** (UTF-8-sig for Excel compatibility) including Show, Frequency, Magnitude, Pitch, Cents, Mode columns — `peaks_table.py`, `PeakTable.save_peaks()`
- **File dialog remembers last-used directory** across saves

### Draggable Matplotlib Annotations with Arrow Connectors

- **Fully draggable text annotations** with curved arrow connectors (`arrowstyle="->"`, `connectionstyle="arc3"`) on the FFT plot — `fft_annotations.py`, `FftAnnotations`
- **Musical note range indicators** — vertical dashed lines at the upper/lower semitone boundaries of each peak's nearest note — `FftAnnotations.create_annotation()`
- **Show/hide individual annotations** independently — `FftAnnotations.hide_annotation()`

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

### Threshold Slider with Real-Time Amplitude Visualization

- **Custom-painted QSlider** showing real-time signal amplitude as a cyan-to-blue gradient fill behind the slider track — `threshold_slider.py`, `ThresholdSlider`
- **Visual tick marks** (minor and major) for amplitude reference — `ThresholdSlider.paintEvent()`

### Secondary Musical Note Axis on FFT Chart

- **Second x-axis on the FFT chart** displaying chromatic note names at corresponding frequencies — `fft_canvas.py`

### Matplotlib Navigation Toolbar

- **Standard pan/zoom/save toolbar** from Matplotlib — `fft_toolbar.py`, `FftToolbar`
- **Custom home button** restoring y-limits to −100 dB / 0 dB — `FftToolbar`
- **Grid toggle** (major/minor gridlines) — `FftToolbar`
- **Keyboard shortcuts** for Matplotlib navigation actions

### Dual Audio Backend Support

- **Runtime switch between PyAudio and SoundDevice** backends via `USE_SOUNDDEVICE` flag — `configure.py`

### Windows Support

- **Runs natively on Windows** — PyQt6 and sounddevice are cross-platform
- **Named mutex prevents multiple simultaneous instances** on Windows — `named_mutex.py`, `NamedMutex`

---

## Features Present in Both

| Feature | SwiftUI | Python |
|---|---|---|
| Real-time FFT magnitude spectrum display | `SpectrumView`, `RealtimeFFTAnalyzer` | `fft_canvas.py` |
| Boxcar (rectangular) window FFT processing | `RealtimeFFTAnalyzer.performFFT` (Hann is present but commented out) | `freq_anal.dft_anal` (boxcar; Blackman also present but commented out) |
| 65,536-sample FFT window @ 48 kHz (~0.7 Hz/bin resolution) | `RealtimeFFTAnalyzer` | `fft_canvas.py` |
| Peak detection above amplitude threshold | `TapToneAnalyzer+PeakAnalysis` | `freq_anal.peak_detection` |
| Parabolic interpolation for sub-bin peak accuracy | `TapToneAnalyzer+PeakAnalysis.refineFrequency()` | `freq_anal.peak_interp()` |
| Musical note + cents mapping per peak | `Pitch.swift` | `pitch.py` |
| Per-peak mode display | `GuitarMode`, results view | `peaks_model.py` Modes column |
| Configurable frequency display range | `TapDisplaySettings.minFrequency` | `peaks_controls.py` f_min/f_max spinboxes |
| Threshold slider for peak detection | `TapSettingsView.swift` | `threshold_slider.py` |
| Audio device selection UI | `TapSettingsView` | `show_devices_sd.py` / `show_devices.py` |
| macOS microphone permission handling | `RealtimeFFTAnalyzer` | `mac_access.py` |
| Real-time performance metrics (FPS, Hz/bin, processing time) | `FFTAnalysisMetricsView` | `PeakControls` stats display |
| Audio capture (AVAudioEngine or PyAudio/SoundDevice) | `RealtimeFFTAnalyzer` | `microphone.py`, `microphone_sd.py` |
| Draggable peak annotation labels | `PeakAnnotations.swift` (pixel-space overlay) | `fft_annotations.py` (Matplotlib native, data-space) |
