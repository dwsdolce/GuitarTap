# Python Reactive Refactor Opportunities

Analysis of imperative patterns in the Python codebase that could be made more reactive,
mirroring Swift's `@Published`/SwiftUI approach.

---

## Background

Swift uses `@Published` properties and SwiftUI's `body` re-evaluation as its reactivity
mechanism. Python uses Qt signals/slots. The key improvement in each case is making model
methods **pure notifiers** (store state + emit signal) rather than having them also
recompute or re-cache derived state imperatively at every call site.

The `PeaksModel` reactive refactor (completed) is a good example of the target pattern:
`selected_frequencies: set[float]` + `is_live: bool` replace the imperative
`show: dict` + `disable_editing: bool`, and `update_data` is now a pure notifier.

---

## High Impact

### 1. Two-branch `if loaded_peaks` logic

**4+ call sites repeat the same conditional.**

Every place that needs to refresh peak display after a parameter change branches on whether
a measurement is loaded:

```python
if self._loaded_measurement_peaks is not None:
    self._emit_loaded_peaks_at_threshold()
else:
    self.find_peaks(self.saved_mag_y_db)
```

**Locations:**
- `tap_tone_analyzer_control.py` lines 181–184 (`set_threshold`)
- `tap_tone_analyzer_control.py` lines 199–203 (`update_axis`)
- `fft_canvas.py` lines 1068–1071 (`update_axis`)
- `fft_canvas.py` lines 1091–1094 (`_refresh_peaks_for_viewport`)
- `fft_canvas.py` lines 1281–1284 (`set_threshold`)

**Swift equivalent:** A single `recalculateFrozenPeaksIfNeeded` method handles both paths.

**Fix:** Consolidate into one method on `TapToneAnalyzer`:
```python
def _recalculate_peaks(self) -> None:
    """Refresh peak display after threshold or axis change. Mirrors Swift recalculateFrozenPeaksIfNeeded."""
    if self._loaded_measurement_peaks is not None:
        self._emit_loaded_peaks_at_threshold()
    else:
        self.find_peaks(self.saved_mag_y_db)
```
All call sites become `self.analyzer._recalculate_peaks()` (or `self._recalculate_peaks()`
in mixin methods), eliminating the duplication.

---

### 2. Duplicated `threshold` and `avg_enable` on `FftCanvas`

`FftCanvas` stores `self.threshold` (line 207) and `self.avg_enable` (line 202) as instance
variables that mirror `self.analyzer.threshold` and `self.analyzer.avg_enable`. Every setter
that touches these values must update both.

**Locations:**
- `fft_canvas.py` line 202: `self.avg_enable: bool = False`
- `fft_canvas.py` line 207: `self.threshold: int = threshold`
- `fft_canvas.py` `set_threshold` updates `self.threshold` then calls `self.analyzer.set_threshold`
- `fft_canvas.py` `set_avg_enable` updates `self.avg_enable` then calls `self.analyzer.set_avg_enable`

**Swift equivalent:** Single `@Published var threshold` on `TapToneAnalyzer`; the view reads
from the analyzer directly.

**Fix:** Remove `self.threshold` and `self.avg_enable` from `FftCanvas`. Anywhere the canvas
reads these values, read from `self.analyzer` instead. The setters become pass-throughs with
no local storage.

---

### 3. `b_peaks_freq`, `peaks_f_min_index/max_index` cached viewport state

`find_peaks` and `_emit_loaded_peaks_at_threshold` store viewport-filtered peak indices as
instance state on the analyzer. These are only used to allow callers to later query which
peaks are in the current frequency window.

**Locations:**
- `tap_tone_analyzer_peak_analysis.py` lines 223–243: assigns `self.peaks_f_min_index`,
  `self.peaks_f_max_index`, `self.b_peaks_freq`

**Swift equivalent:** `SpectrumView+ChartContent` filters `currentPeaks` by the chart's
visible domain at render time. The analyzer never stores viewport-filtered subsets.

**Fix:** The `peaksChanged` signal already emits the viewport-filtered slice. Callers that
query `b_peaks_freq` or the index fields should instead use the data received via the signal.
Once no callers reference these fields they can be deleted from `__init__` and the
assignment sites removed.

---

## Medium Impact

### 4. `_mode_color_map` duplicated on canvas + `update_mode_colors` sync

`FftCanvas` maintains its own `_mode_color_map` dictionary (line 393) that mirrors the
analyzer's equivalent. `update_mode_colors` is a method that copies the analyzer's map to
the canvas and triggers a repaint.

**Swift equivalent:** The view reads `tap.identifiedModes` (a `@Published` value) directly;
there is no separate copy on the view.

**Fix:** Remove `FftCanvas._mode_color_map`. Everywhere the canvas uses its local color map,
read from `self.analyzer._mode_color_map` instead. Eliminate `update_mode_colors`.

---

### 5. `_set_comparison_visibility` imperative show/hide

When `is_comparing` changes, `fft_canvas.py` lines 1220–1232 manually shows and hides
scatter series and threshold lines.

**Swift equivalent:** `SpectrumView.body` conditionally includes/excludes chart marks based
on `tap.displayMode == .comparison`. No explicit show/hide calls.

**Fix:** Move the comparison visibility logic into the rendering path (`_rebuild_plot` or
equivalent), driven by the current `AnalysisDisplayMode` state rather than side-effecting
calls. The `displayMode` property (now present on the analyzer) is the authoritative gate.

---

### 6. Comparison axis range recomputed in canvas

`fft_canvas.load_comparison` (lines 1184–1191) recomputes axis bounds from comparison
snapshots. The analyzer's `load_comparison` method already computed and applied these bounds
via `update_axis`.

**Swift equivalent:** `TapToneAnalyzer.loadComparison(measurements:)` sets
`@Published loadedMinFreq/MaxFreq/MinDB/MaxDB`; the view reacts via `.onReceive`.

**Fix:** `FftCanvas.load_comparison` should just call `self.analyzer.load_comparison(...)`,
then read the axis bounds back from `self.analyzer` (which the analyzer already has set),
rather than re-deriving them from the snapshots.

---

### 7. `set_guitar_type_bands` sets `_guitar_type` in two places

`fft_canvas.py` line 650 (approx.):
```python
self._guitar_type = guitar_type
self.analyzer._guitar_type = guitar_type
```
Two separate assignments where the canvas copy should derive from the analyzer.

**Fix:** Remove `FftCanvas._guitar_type`. Read from `self.analyzer._guitar_type` where needed.

---

### 8. `_tap_threshold_y` and `_hysteresis_margin` on canvas

Lines 845–849, 857–861: the canvas stores its own copies of tap threshold and hysteresis
margin and syncs them to the analyzer on each setter call.

**Fix:** Same pattern as `threshold` above — remove from canvas, pass through to analyzer,
read from analyzer at render time.

---

## Lower Impact

### 9. `process_averages` manual annotation clear on count change

`fft_canvas.py` lines 1359–1363: inline logic detects whether `num_averages` changed and
clears annotations if so.

**Swift equivalent:** A `onChange(of: tap.numAverages)` modifier handles annotation clearing
reactively.

**Fix:** Connect `analyzer.averagesChanged` signal (already emitted) to a slot that clears
annotations. Remove the inline check from `process_averages`.

---

## Summary Table

| # | Pattern | Locations | Impact |
|---|---------|-----------|--------|
| 1 | Two-branch `if loaded_peaks` | `tap_tone_analyzer_control.py`, `fft_canvas.py` (5 sites) | High |
| 2 | `threshold`/`avg_enable` duplicated on canvas | `fft_canvas.py` | High |
| 3 | `b_peaks_freq`/index viewport cache | `tap_tone_analyzer_peak_analysis.py` | High |
| 4 | `_mode_color_map` duplicated + `update_mode_colors` | `fft_canvas.py` | Medium |
| 5 | `_set_comparison_visibility` imperative show/hide | `fft_canvas.py` | Medium |
| 6 | Comparison axis recomputed in canvas | `fft_canvas.py` | Medium |
| 7 | `_guitar_type` set in two places | `fft_canvas.py` | Medium |
| 8 | `_tap_threshold_y`/`_hysteresis_margin` on canvas | `fft_canvas.py` | Medium |
| 9 | `process_averages` inline annotation clear | `fft_canvas.py` | Low |

**Recommended starting point:** Item 1 (consolidate `_recalculate_peaks`) — it eliminates the
most duplication with a contained change, and is the most direct analog of Swift's single
`recalculateFrozenPeaksIfNeeded` path.
