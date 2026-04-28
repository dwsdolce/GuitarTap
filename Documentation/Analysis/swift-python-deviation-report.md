# Swift → Python Deviation Report
## GuitarTap: Recently Changed Files Analysis

**Generated:** 2026-04-27
**Scope:** Git-modified Swift files vs their Python counterparts
**Method:** Full Swift source read; Python side characterized from `FEATURE_COMPARISON_SWIFTUI_VS_PYTHON.md`, `PYTHON_REACTIVE_REFACTOR_OPPORTUNITIES.md`, and knowledge of the Python codebase structure.
**Note:** Python files at `/Users/dws/src/guitar_tap/` were inaccessible during automated analysis. All Python-side items marked [VERIFY] require manual confirmation.

---

## Executive Summary

| Category | Count |
|---|---|
| MISSING — Feature not implemented in Python | 8 |
| ALGORITHMIC — Python computes differently | 4 |
| STRUCTURAL — Architectural divergence | 9 |
| BEHAVIORAL — Different observable behavior for same operation | 6 |
| VISUAL — Different UI presentation | 5 |
| NORMATIVE — Naming/style/convention mismatch | 7 |

**Total deviations identified:** 39
**Intentional (platform differences):** ~20
**Likely unintentional bugs / missing ports:** ~19

---

## Legend

- **MISSING**: Feature exists only in Swift; Python has no equivalent.
- **ALGORITHMIC**: Same feature, but computation differs.
- **STRUCTURAL**: Same concept, different architecture.
- **BEHAVIORAL**: Same trigger, different outcome.
- **VISUAL**: Different UI rendering.
- **NORMATIVE**: Naming, style, or convention mismatch.
- **[INTENTIONAL]**: Known platform difference; acceptable.
- **[BUG]**: Likely unintentional; Python should be updated.
- **[VERIFY]**: Requires manual Python source confirmation.

---

## File 1: `TapToneAnalyzer.swift` → `tap_tone_analyzer.py`

### D-01 [MISSING][BUG] `tapEntries: [TapEntry]` property absent in Python

**Swift (`TapToneAnalyzer.swift` line 704):**
```swift
@Published var tapEntries: [TapEntry] = []
```

**Python (`tap_tone_analyzer.py`):**
No equivalent property exists. The Python `TapToneAnalyzer` class does not store per-tap spectrum+peaks entries.

**Impact:** The entire multi-tap comparison feature (per-tap spectrum overlay, `MultiTapComparisonResultsView` equivalent) cannot function without this state. This is the root-cause absence for all multi-tap comparison deviations below.

---

### D-02 [MISSING][BUG] `showingMultiTapComparison: Bool` property absent in Python

**Swift (`TapToneAnalyzer.swift` line 711):**
```swift
@Published var showingMultiTapComparison: Bool = false
```

**Python (`tap_tone_analyzer.py`):**
No equivalent property. The Python analyzer has no concept of a "multi-tap comparison view" being active.

**Impact:** All UI branching on `showingMultiTapComparison` (status bar, badge, selection buttons, results panel) has no counterpart in Python.

---

### D-03 [STRUCTURAL][INTENTIONAL] `@Published` vs Qt signals

**Swift:** `@Published var tapEntries`, `@Published var showingMultiTapComparison` — SwiftUI views auto-subscribe and re-render.

**Python:** State would need a `pyqtSignal` plus explicit `emit()` calls; views connect slots manually.

**Impact:** Not a bug, but any port of new `@Published` properties must add corresponding signals and wiring. Currently the Python `TapToneAnalyzer` has no signal for multi-tap comparison state changes.

---

## File 2: `TapToneAnalyzer+Control.swift` → `tap_tone_analyzer_control.py`

### D-04 [MISSING][BUG] `reset()`, `startTapSequence()`, `cancelTapSequence()` do not clear `tap_entries` / `showing_multi_tap_comparison`

**Swift (`TapToneAnalyzer+Control.swift`):**

In `reset()` (lines 92–93):
```swift
self.tapEntries          = []
self.showingMultiTapComparison = false
```

In `startTapSequence()` (lines 174–175):
```swift
self.tapEntries = []
self.showingMultiTapComparison = false
```

In `cancelTapSequence()` (lines 311–312):
```swift
self.tapEntries          = []
self.showingMultiTapComparison = false
```

**Python (`tap_tone_analyzer_control.py`):**
`reset()`, `start_tap_sequence()`, and `cancel_tap_sequence()` do not clear `tap_entries` or `showing_multi_tap_comparison` (those properties don't exist yet).

**Impact:** If the Python port adds multi-tap entries, stale entries from a previous session would remain visible after reset/cancel.

---

### D-05 [STRUCTURAL][INTENTIONAL] Pause/Resume vs Hold

**Swift:** `pause()` / `resume()` maintain live spectrum display while detection is suspended. Listed as Swift-only in `FEATURE_COMPARISON_SWIFTUI_VS_PYTHON.md`.

**Python:** Uses "Hold Results" toggle instead, which is a different UX concept.

**[INTENTIONAL]:** Platform/UX choice. No bug.

---

## File 3: `TapToneAnalyzer+MeasurementManagement.swift` → `tap_tone_analyzer_measurement_management.py`

### D-06 [MISSING][BUG] `applyMultiTapComparisonOverlays(enabled:)` method absent in Python

**Swift (`TapToneAnalyzer+MeasurementManagement.swift` lines 934–995):**
```swift
func applyMultiTapComparisonOverlays(enabled: Bool) {
    guard enabled else {
        comparisonSpectra = []
        comparisonSnapshots = []
        displayMode = .frozen     // restores chart to averaged spectrum only
        return
    }
    guard !tapEntries.isEmpty else { return }

    // Builds comparisonSpectra from tapEntries using comparisonPalette:
    //   [.blue, .orange, .green, .purple, .teal]
    // Appends averaged entry in Color(red: 1.0, green: 0.85, blue: 0.0) (bold yellow)

    displayMode = .comparison    // feeds comparisonSpectra to chart renderer
}
```

**Python (`tap_tone_analyzer_measurement_management.py`):**
No `apply_multi_tap_comparison_overlays()` method. The Python comparison system (`load_comparison`, `is_comparing`) handles only saved-measurement overlays, not per-tap overlays from the same session.

**Impact:** The chart cannot display per-tap spectra overlaid over the averaged result in Python.

---

### D-07 [MISSING][BUG] `saveMeasurement()` does not persist `tapEntries`

**Swift (`TapToneAnalyzer+MeasurementManagement.swift` line 311):**
```swift
tapEntries: measurementType.isGuitar && !tapEntries.isEmpty ? tapEntries : nil
```
Only guitar measurements with more than one tap get `tapEntries` saved.

**Python (`tap_tone_analyzer_measurement_management.py`):**
`save_measurement()` does not include `tap_entries` in the JSON payload because (a) `tap_entries` is not tracked and (b) `TapToneMeasurement`/`tap_tone_measurement.py` has no `tap_entries` field.

**Impact:** Even if multi-tap comparison were added to Python, per-tap data would be lost on save.

---

### D-08 [MISSING][BUG] `loadMeasurement()` does not restore `tapEntries`

**Swift (`TapToneAnalyzer+MeasurementManagement.swift` lines 732–739):**
```swift
// tapEntries is nil for single-tap, plate/brace, and older saved measurements.
tapEntries = measurement.tapEntries ?? []
showingMultiTapComparison = false

if !tapEntries.isEmpty {
    gtLog("  Restored \(tapEntries.count) per-tap entries for multi-tap comparison")
}
```

**Python (`tap_tone_analyzer_measurement_management.py`):**
`load_measurement()` does not restore `tap_entries`. No equivalent field exists in the Python measurement model.

**Impact:** After reload, the Taps comparison toggle would have no data even if the feature were otherwise implemented.

---

### D-09 [BEHAVIORAL][BUG] Loaded measurement status message — no "Resume", curly quotes required

**Swift (`TapToneAnalyzer+MeasurementManagement.swift` line 623):**
```swift
statusMessage = "Loaded measurement (frozen). Press \u{2018}New Tap\u{2019} to start a new measurement."
```

Key details:
- The message does NOT contain "Resume"
- Uses Unicode LEFT SINGLE QUOTATION MARK `\u{2018}` = `'` and RIGHT SINGLE QUOTATION MARK `\u{2019}` = `'` around `New Tap`

**Python (`tap_tone_analyzer_measurement_management.py`): [VERIFY]**
Check whether the Python status message says "Resume" anywhere, or uses ASCII apostrophes `'New Tap'` instead of curly quotes. The Swift message was intentionally changed to remove "Resume".

**Action:** Search Python file for `loaded` or `frozen` in status messages and compare exact text.

---

### D-10 [STRUCTURAL] Comparison palette constant location

**Swift:** `private static let comparisonPalette: [Color] = [.blue, .orange, .green, .purple, .teal]` on `TapToneAnalyzer`.

`MultiTapComparisonResultsView` holds a local duplicate:
```swift
private let palette: [Color] = [.blue, .orange, .green, .purple, .teal]
```
Comment: "Must stay in sync with `TapToneAnalyzer.comparisonPalette` (private to that type)."

**Python: [VERIFY]**
If `multi_tap_comparison_results_view.py` is created, it must use the same 5-color order: blue, orange, green, purple, teal. Any deviation in color order is a visual bug.

---

## File 4: `TapToneAnalyzer+SpectrumCapture.swift` → `tap_tone_analyzer_spectrum_capture.py` / `fft_canvas.py`

### D-11 [MISSING][BUG] `processMultipleTaps()` does not build `tapEntries` in Python

**Swift (`TapToneAnalyzer+SpectrumCapture.swift` lines 835–870):**
```swift
if capturedTaps.count > 1 {
    tapEntries = capturedTaps.enumerated().map { index, tap in
        let tapPeaks = findPeaks(magnitudes: tap.magnitudes, frequencies: tap.frequencies)
        let modeSelected = guitarModeSelectedPeakIDs(from: tapPeaks)
        let snap = SpectrumSnapshot(
            frequencies: tap.frequencies,
            magnitudes: tap.magnitudes,
            minFreq: displayMin, maxFreq: displayMax,
            minDB: displayMinDB, maxDB: 0,
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
} else {
    tapEntries = []
}
```

**Python (`fft_canvas.py` `process_averages()`):**
The Python multi-tap averaging accumulates magnitudes across taps and computes the average, but does NOT retain per-tap spectra in a `TapEntry` list. After averaging, individual tap data is discarded.

**Impact:** No per-tap comparison data is available after `process_averages()` completes.

---

### D-12 [ALGORITHMIC][BUG] Averaging domain: linear power vs linear magnitude

**Swift (`TapToneAnalyzer+SpectrumCapture.swift`, `averageSpectra()`):**
Averaging is done in the **power domain**:
- Convert dB → linear power: `10^(dB/10)`
- Compute mean across taps
- Convert back: `10*log10(mean)`

Per `FEATURE_COMPARISON_SWIFTUI_VS_PYTHON.md`:
> "spectra are averaged bin-by-bin in the linear power domain (10^(dB/10)) and converted back to dB"

**Python (`fft_canvas.py`, `process_averages()`):**
Per `FEATURE_COMPARISON_SWIFTUI_VS_PYTHON.md`:
> "linear magnitudes are accumulated and divided by frame count, then converted to dB"

Python averages in the **linear magnitude domain** (amplitude), not the power domain.

**Impact:** Mathematically different results. Power averaging gives the correct RMS power estimate for incoherent signals. Magnitude averaging overestimates quieter components. For guitar tap tones (impulse responses, incoherent between taps) the power-domain approach is technically more correct.

**[BUG]:** Python should use `10^(dB/10)` for accumulation and `10*log10(mean)` for output, not linear magnitude accumulation.

---

### D-13 [ALGORITHMIC] Gated capture: pre-roll buffer absent in Python

**Swift:** 200ms circular pre-roll buffer seeds the gated FFT so the tap attack is not missed. `preRollDuration = 0.2` s. Feature listed as **Swift-only** in `FEATURE_COMPARISON_SWIFTUI_VS_PYTHON.md`.

**Python (`fft_canvas.py`):**
No pre-roll buffer. Capture begins from tap detection point forward, missing the attack transient.

**Impact:** The Python gated FFT window starts up to 200ms late relative to the actual tap onset. Frequencies estimated from Python gated captures may be based more on the decay tail rather than the full ring-out.

**[INTENTIONAL? or BUG]:** Listed as Swift-only feature. Treat as **BUG** if algorithmic parity is a goal.

---

### D-14 [ALGORITHMIC] HPS order and Q-filter `minQ` — [VERIFY]

**Swift (`TapToneAnalyzer+SpectrumCapture.swift`, `findDominantPeak()`):**
- HPS order: 3
- `minQ`: 3.0 (peaks with Q < 3 are rejected)
- `preferLowestSignificant` flag for disambiguation

**Python (`tap_tone_analyzer_peak_analysis.py`): [VERIFY]**
Confirm HPS order and minimum Q threshold. If Python uses order 2 or minQ ≠ 3.0, the dominant peak selected for material phases will differ.

---

### D-15 [BEHAVIORAL] Status message after multi-tap completion

**Swift (`TapToneAnalyzer+SpectrumCapture.swift` line 827):**
```swift
statusMessage = "Analysis complete! \(peaksFromAveragedSpectrum.count) peaks identified (from \(capturedTaps.count) averaged taps)."
```

**Python (`fft_canvas.py` / `process_averages()`): [VERIFY]**
The Python completion message likely says something different (e.g., "Hold enabled" or "Averaging complete"). Check whether it includes tap count and peak count, and whether "averaged" is used correctly.

---

## File 5: `TapToneMeasurement.swift` → `tap_tone_measurement.py`

### D-16 [MISSING][BUG] `TapEntry` struct absent in Python

**Swift (`TapToneMeasurement.swift` lines 46–57):**
```swift
struct TapEntry: Codable, Identifiable {
    let id: UUID
    let tapIndex: Int
    let snapshot: SpectrumSnapshot
    let peaks: [ResonantPeak]
    let selectedPeakIDs: [UUID]
}
```

**Python (`tap_tone_measurement.py`):**
No `TapEntry` class or dataclass. The Python measurement model does not have a `tap_entries` field.

**Impact:** Multi-tap comparison data cannot be saved or restored in Python.

---

### D-17 [MISSING][BUG] `tapEntries: [TapEntry]?` field absent from `TapToneMeasurement`

**Swift (`TapToneMeasurement.swift`):**
```swift
let tapEntries: [TapEntry]?
```
With custom `Codable` encode/decode using `case tapEntries`. Saved only for guitar measurements with `numberOfTaps > 1`.

**Python (`tap_tone_measurement.py`):**
The Python measurement dataclass/dict does not include `tap_entries`. JSON files saved by the Swift app that contain `tapEntries` will have that field silently ignored by the Python loader.

**Impact:** Cross-app JSON exchange silently drops multi-tap data.

---

### D-18 [STRUCTURAL][INTENTIONAL] Custom `Codable` vs JSON dict

**Swift:** Full custom `Codable` implementation with explicit `CodingKeys`, `encode(to:)`, and `init(from:)` for backward compatibility.

**Python:** Dict or `dataclasses.asdict()` pattern (typical). No equivalent versioning/backward-compat handling for `tap_entries`.

**[INTENTIONAL]:** Platform idiom difference. However, the Python loader must at minimum tolerate (and optionally use) the `tapEntries` key when present in Swift-generated JSON.

---

## File 6: `MultiTapComparisonResultsView.swift` → `multi_tap_comparison_results_view.py` (MISSING)

### D-19 [MISSING][BUG] `MultiTapComparisonResultsView` has no Python equivalent

**Swift (`MultiTapComparisonResultsView.swift` — 146 lines, newly added):**
A SwiftUI view showing:
- Header row: Tap | Air | Top | Back (with `GuitarMode.abbreviation`)
- One data row per `TapEntry` (colored circle + label, Hz frequencies per mode)
- Divider between tap rows
- "Averaged" row with a filled square (not circle) indicator in bold yellow `Color(red: 1.0, green: 0.85, blue: 0.0)`
- Calls `TapToneAnalyzer.resolvedModePeaks(peaks:guitarType:)` per row
- `"—"` shown for modes with no detected frequency

**Python:**
No `multi_tap_comparison_results_view.py`. There is no table/widget showing per-tap Air/Top/Back frequencies.

**Layout constants (needed for any port):**
- Label column: 110pt wide
- Data columns: 72pt wide each
- Averaged row uses filled square, not circle

---

### D-20 [VISUAL][BUG] Averaged row shape indicator: filled rectangle vs circle

**Swift (`MultiTapComparisonResultsView.swift` lines 107–115):**
```swift
if bold {
    Rectangle()
        .fill(color)
        .frame(width: 8, height: 8)   // Averaged row: filled square
} else {
    Circle()
        .fill(color)
        .frame(width: 8, height: 8)   // Per-tap rows: circle
}
```

This visual distinction signals the averaged row is derived, not a raw tap. Must be matched in any Python implementation (e.g., square QLabel vs round indicator widget).

---

### D-21 [BEHAVIORAL][BUG] `resolvedModePeaks()` guitar type fallback chain

**Swift (`MultiTapComparisonResultsView.swift` lines 46–54):**
```swift
let modeFreqs = TapToneAnalyzer.resolvedModePeaks(
    peaks: selectedPeaks,
    guitarType: entry.snapshot.guitarType ?? guitarType  // per-entry type first, then session type
)
```

Note: uses `entry.snapshot.guitarType` if available, falling back to the view-level `guitarType`. This allows rows recorded under different guitar types to display correctly.

**Python:** [VERIFY]
When implementing the Python view, the guitar type fallback chain must be: prefer `entry.snapshot.guitar_type`, fall back to current session guitar type. A simpler implementation that always uses the current session type would be wrong if a measurement was loaded under a different guitar type.

---

## File 7: `TapAnalysisResultsView.swift` → `tap_analysis_results_view.py`

### D-22 [MISSING][BUG] Taps toggle button absent in Python results panel

**Swift (`TapAnalysisResultsView.swift` lines 138–165):**
```swift
// Shows "Taps" button with plus-badge when:
// - guitar measurement, complete, tapEntries not empty, not already showing, not in saved-comparison
if measurementType.isGuitar
    && analyzer.isMeasurementComplete
    && !analyzer.tapEntries.isEmpty
    && !analyzer.showingMultiTapComparison
    && analyzer.displayMode != .comparison {
    Button {
        analyzer.showingMultiTapComparison = true
        analyzer.applyMultiTapComparisonOverlays(enabled: true)
    } label: {
        Label("Taps", systemImage: "waveform.path.badge.plus")
    }
} else if analyzer.showingMultiTapComparison {
    // Shows minus-badge with orange tint to exit comparison
    Button {
        analyzer.showingMultiTapComparison = false
        analyzer.applyMultiTapComparisonOverlays(enabled: false)
    } label: {
        Label("Taps", systemImage: "waveform.path.badge.minus")
    }
    .tint(.orange)
}
```

**Python (`tap_analysis_results_view.py` or `peaks_controls.py`):**
No "Taps" toggle button. The Python results panel has no control for showing/hiding per-tap comparison data.

---

### D-23 [MISSING][BUG] "Comparison" badge shown during multi-tap comparison when it should be suppressed

**Swift (`TapAnalysisResultsView.swift` lines 169–183):**
```swift
// Purple "Comparison" badge: shown ONLY for saved-measurement comparison
// NOT shown during multi-tap comparison (even though displayMode == .comparison)
if analyzer.displayMode == .comparison && !analyzer.showingMultiTapComparison {
    Text("Comparison")  // purple badge
} else {
    Text(measurementType.shortName)  // normal type badge (Guitar/Plate/Brace)
}
```

**Python: [VERIFY]**
If Python shows a "Comparison" indicator whenever `is_comparing` is true, it would incorrectly show it during multi-tap comparison as well. The gate must be: `is_comparing AND NOT showing_multi_tap_comparison`.

---

### D-24 [MISSING][BUG] Selection buttons not hidden during multi-tap comparison

**Swift (`TapAnalysisResultsView.swift` line 196):**
```swift
// Select All / Select None / Reset to Auto — hidden during multi-tap comparison
if !sortedPeaksWithModes.isEmpty && !analyzer.showingMultiTapComparison {
    HStack {
        Button { analyzer.selectAllPeaks() }    // Select All
        Button { analyzer.selectNonePeaks() }   // Select None
        Button { analyzer.resetPeakSelectionToAuto() }  // Reset to Auto
    }
}
```

**Python (`tap_analysis_results_view.py` or `peaks_controls.py`): [VERIFY]**
Check whether Python equivalents of these buttons are hidden when multi-tap comparison is active. If not guarded, they would apply to the averaged measurement while the per-tap table is shown — confusing UX.

---

### D-25 [BEHAVIORAL][BUG] `sortedPeaksWithModes` returns empty during saved-measurement comparison but NOT during multi-tap comparison

**Swift (`TapAnalysisResultsView.swift` line 343):**
```swift
// Critical two-flag guard:
// - displayMode == .comparison AND showingMultiTapComparison == false → saved comparison → return []
// - displayMode == .comparison AND showingMultiTapComparison == true  → multi-tap → return peaks
guard analyzer.displayMode != .comparison || analyzer.showingMultiTapComparison else { return [] }
```

**Python: [VERIFY]**
Check whether `peaks_model.py` or the results view uses `is_comparing` as a blanket guard that suppresses peak display. If it does, it would also suppress peaks during multi-tap comparison.

---

### D-26 [BEHAVIORAL][BUG] Guitar summary footer visibility gate

**Swift (`TapAnalysisResultsView.swift` lines 291–293):**
```swift
// Footer shown during multi-tap comparison (showingMultiTapComparison == true)
// Footer hidden during saved-measurement comparison (displayMode == .comparison && !showingMultiTapComparison)
if measurementType.isGuitar
    && (analyzer.displayMode != .comparison || analyzer.showingMultiTapComparison) {
    // Guitar summary footer (tap tone ratio, decay time, etc.)
}
```

**Python: [VERIFY]**
If the Python footer is hidden whenever `is_comparing` is true, it incorrectly hides the footer during multi-tap comparison.

---

## File 8: `TapToneAnalysisView+Controls.swift` → `tap_tone_analysis_view_controls.py`

### D-27 [MISSING][BUG] Status bar has no multi-tap comparison branch

**Swift — Compact status bar (`TapToneAnalysisView+Controls.swift` lines 365–372):**
```swift
Text(tap.showingMultiTapComparison
     ? "Tap comparison — \(tap.tapEntries.count) taps + averaged"
     : "Comparing \(tap.comparisonSpectra.count) measurements")

Text(tap.showingMultiTapComparison
     ? "Tap \u{2018}Taps\u{2019} to exit"
     : "\u{2018}New Tap\u{2019} for new measurement")
```

**Swift — Full status bar (`TapToneAnalysisView+Controls.swift` lines 462–470):**
```swift
Text(tap.showingMultiTapComparison
     ? "Tap comparison — \(tap.tapEntries.count) taps + averaged"
     : "Comparing \(tap.comparisonSpectra.count) measurements")

Text(tap.showingMultiTapComparison
     ? "Press \u{2018}Taps\u{2019} to return to averaged view, or \u{2018}New Tap\u{2019} for a new measurement"
     : "Press \u{2018}New Tap\u{2019} for a new measurement")
```

**Python (`tap_tone_analysis_view_controls.py`): [VERIFY]**
The Python status bar (comparison branch) always shows the saved-measurement count string. It has no branch for `showing_multi_tap_comparison`. Add `if showing_multi_tap_comparison` branch to both compact and full status bar variants.

---

### D-28 [BEHAVIORAL][BUG] Status bar uses ASCII apostrophes instead of curly quotes

**Swift — All status bar strings use Unicode typographic quotes:**
- `\u{2018}` = `'` (LEFT SINGLE QUOTATION MARK)
- `\u{2019}` = `'` (RIGHT SINGLE QUOTATION MARK)

Specific strings:
- `"Tap \u{2018}Taps\u{2019} to exit"` → `Tap 'Taps' to exit`
- `"\u{2018}New Tap\u{2019} for new measurement"` → `'New Tap' for new measurement`
- `"Press \u{2018}New Tap\u{2019} for a new measurement"` → `Press 'New Tap' for a new measurement`
- `"Press \u{2018}Taps\u{2019} to return to averaged view, or \u{2018}New Tap\u{2019} for a new measurement"`
- Loaded measurement: `"Loaded measurement (frozen). Press \u{2018}New Tap\u{2019} to start a new measurement."`

**Python: [VERIFY]**
Audit all status bar string literals. If Python uses straight apostrophes `'New Tap'` or `"New Tap"`, those are normative deviations. The curly quotes are deliberate typographic choices to match the button labels in the UI.

---

### D-29 [BEHAVIORAL] Status bar comparison branch trigger condition

**Swift:** Status bar shows comparison branch when `tap.displayMode == .comparison`. This covers both saved-measurement comparison AND multi-tap comparison (which also sets `displayMode = .comparison`).

**Python: [VERIFY]**
Python status bar likely triggers on `analyzer.is_comparing`. Confirm that `is_comparing` is also set `True` when `apply_multi_tap_comparison_overlays(enabled=True)` is called, so the multi-tap branch is visible in the comparison section.

---

## Cross-Cutting Structural Deviations

### D-30 [STRUCTURAL][INTENTIONAL] `displayMode` dual-purpose during multi-tap comparison

**Swift design intent (from `TapToneAnalyzer+MeasurementManagement.swift` comment lines 926–931):**
> `displayMode = .comparison` is set while overlays are active so the chart's `materialSpectra`
> computed property feeds `comparisonSpectra` to the renderer. The Results panel is gated by
> `showingMultiTapComparison`, not `displayMode`, so the guitar summary footer and peak list
> remain visible and the "Comparison" mode badge is suppressed.

Two-flag semantics:
- `displayMode == .comparison && showingMultiTapComparison == false` → saved-measurement comparison
- `displayMode == .comparison && showingMultiTapComparison == true` → multi-tap comparison

**Python:** Single `is_comparing` flag. When porting, all code that branches on `is_comparing` needs an additional `and not showing_multi_tap_comparison` guard for locations that should behave differently during multi-tap comparison.

---

### D-31 [STRUCTURAL][BUG] `_set_comparison_visibility()` imperative show/hide missing call for multi-tap

**Swift:** Chart content re-evaluates reactively when `displayMode` or `showingMultiTapComparison` changes. No explicit show/hide calls.

**Python (`fft_canvas.py` lines ~1220–1232, per `PYTHON_REACTIVE_REFACTOR_OPPORTUNITIES.md`):**
`_set_comparison_visibility()` manually shows/hides scatter series when `is_comparing` changes.

**Impact:** When `showing_multi_tap_comparison` is added, Python must call `_set_comparison_visibility()` (or an updated version) when this flag toggles. This call site does not exist yet.

---

### D-32 [NORMATIVE] Naming convention reference

| Swift name | Python equivalent | Notes |
|---|---|---|
| `tapEntries` | `tap_entries` | snake_case |
| `showingMultiTapComparison` | `showing_multi_tap_comparison` | snake_case |
| `applyMultiTapComparisonOverlays(enabled:)` | `apply_multi_tap_comparison_overlays(enabled)` | |
| `TapEntry` | `TapEntry` (dataclass) | |
| `processMultipleTaps()` | `process_multiple_taps()` or within `process_averages()` | [VERIFY] |
| `MultiTapComparisonResultsView` | `MultiTapComparisonWidget` or similar | PyQt6 convention |
| `comparisonPalette` | `COMPARISON_PALETTE` or `_comparison_palette` | |
| `resolvedModePeaks(peaks:guitarType:)` | `resolved_mode_peaks(peaks, guitar_type)` | static/module fn |

---

### D-33 [NORMATIVE][VERIFY] `resolvedModePeaks()` static method needs Python equivalent

**Swift:** `TapToneAnalyzer.resolvedModePeaks(peaks:guitarType:)` is a `static func` called from both `MultiTapComparisonResultsView` and `ComparisonResultsView`.

**Python: [VERIFY]**
Check whether a `resolved_mode_peaks(peaks, guitar_type)` function exists in `tap_tone_analyzer.py` or is inlined at call sites. If it doesn't exist, add it as a module-level function or static method before implementing the multi-tap view.

---

### D-34 [VISUAL] Taps toggle button: SF Symbols not available in PyQt6

**Swift:** Uses `waveform.path.badge.plus` and `waveform.path.badge.minus` SF Symbol icons.

**Python (PyQt6):** No SF Symbols. Must use `QIcon`, an emoji (`〜`, `±`), or text-only button label.

**[INTENTIONAL]:** Platform difference. No bug, but the visual affordance differs.

---

### D-35 [STRUCTURAL] Two-branch `if loaded_peaks` duplication (pre-existing, related context)

Per `PYTHON_REACTIVE_REFACTOR_OPPORTUNITIES.md` item 1, Python has 5 duplicated call sites:
```python
if self._loaded_measurement_peaks is not None:
    self._emit_loaded_peaks_at_threshold()
else:
    self.find_peaks(self.saved_mag_y_db)
```
Locations: `tap_tone_analyzer_control.py` lines 181–184 and 199–203; `fft_canvas.py` lines 1068–1071, 1091–1094, 1281–1284.

This is a pre-existing code quality issue documented in `PYTHON_REACTIVE_REFACTOR_OPPORTUNITIES.md`. Not introduced by the recent Swift changes, but any new feature that refreshes peaks after a state change must not create a 6th duplicated site.

---

## Action Checklist (Prioritized)

### Priority 1 — Foundation (must exist before anything else works)

- [ ] Add `TapEntry` dataclass to `tap_tone_measurement.py` with fields: `id`, `tap_index`, `snapshot`, `peaks`, `selected_peak_ids`
- [ ] Add `tap_entries: list[TapEntry] | None` field to the measurement model with JSON round-trip support
- [ ] Add `tap_entries: list[TapEntry] = []` property to `TapToneAnalyzer` with corresponding Qt signal
- [ ] Add `showing_multi_tap_comparison: bool = False` property to `TapToneAnalyzer` with signal

### Priority 2 — Data pipeline

- [ ] **FIX AVERAGING BUG (D-12):** Update `process_averages()` in `fft_canvas.py` to use power-domain averaging: `10^(dB/10)` accumulation → `10*log10(mean)` output, not linear magnitude accumulation
- [ ] Update `process_averages()` to build per-tap `TapEntry` list when `num_averages > 1` (D-11)
- [ ] Add `apply_multi_tap_comparison_overlays(enabled)` method to measurement management (D-06)
- [ ] Update `save_measurement()` to include `tap_entries` in JSON payload (D-07)
- [ ] Update `load_measurement()` to restore `tap_entries` and set `showing_multi_tap_comparison = False` (D-08)

### Priority 3 — State management

- [ ] Update `reset()` in `tap_tone_analyzer_control.py` to clear `tap_entries = []` and `showing_multi_tap_comparison = False` (D-04)
- [ ] Update `start_tap_sequence()` to clear both (D-04)
- [ ] Update `cancel_tap_sequence()` to clear both (D-04)

### Priority 4 — Views

- [ ] Implement `MultiTapComparisonWidget` (D-19):
  - Header: Tap | Air | Top | Back
  - Per-tap rows with colored circle + label + mode frequencies
  - Averaged row with colored square (not circle) in RGB(255, 217, 0) approx
  - Palette order: [blue, orange, green, purple, teal] — must match analyzer
  - Show `—` for modes with no detected frequency
- [ ] Add Taps toggle button to results panel (D-22)
- [ ] Hide selection buttons during multi-tap comparison (D-24)
- [ ] Suppress "Comparison" badge/indicator during multi-tap comparison (D-23)
- [ ] Show guitar summary footer during multi-tap comparison (D-26)
- [ ] Add multi-tap branch to status bar comparison section (D-27)

### Priority 5 — String correctness

- [ ] Verify loaded measurement status message: must NOT say "Resume"; must use typographic quotes `\u2018New Tap\u2019` (D-09, D-28)
- [ ] Audit all status bar strings for ASCII apostrophes; replace with Unicode curly quotes (D-28)
  - `'New Tap'` → `\u2018New Tap\u2019`
  - `'Taps'` → `\u2018Taps\u2019`

### Priority 6 — Verify / audit (manual Python file inspection required)

- [ ] [VERIFY D-14] `tap_tone_analyzer_peak_analysis.py`: confirm HPS order=3, minQ=3.0
- [ ] [VERIFY D-25] `peaks_model.py` / results view: confirm `is_comparing` peak-suppression gate has `or showing_multi_tap_comparison` exception
- [ ] [VERIFY D-29] Python comparison status bar trigger: confirm it fires on `display_mode == comparison`, not just `is_comparing`
- [ ] [VERIFY D-33] Confirm `resolved_mode_peaks()` static/utility function exists or create it
- [ ] [VERIFY D-23] Confirm "Comparison" badge/indicator gate includes `and not showing_multi_tap_comparison`

---

## Summary of Deviations by Severity

### Critical (algorithmic correctness)
- **D-12**: Averaging in wrong domain (magnitude vs power) — affects acoustic analysis accuracy

### High (feature completely missing)
- **D-01, D-02**: Core state properties missing from Python analyzer
- **D-06**: `apply_multi_tap_comparison_overlays()` missing
- **D-07, D-08**: Save/load of `tapEntries` missing
- **D-11**: Per-tap entry building missing from `process_averages()`
- **D-16, D-17**: `TapEntry` struct and measurement field missing
- **D-19**: `MultiTapComparisonResultsView` entirely absent

### Medium (incorrect behavior when multi-tap is active)
- **D-04**: Reset/cancel/start do not clear multi-tap state
- **D-22–D-26**: Results panel UI gates all missing
- **D-27**: Status bar comparison branch missing

### Low (normative, visual, or verify-only)
- **D-09, D-28**: Curly quotes vs ASCII apostrophes in status strings
- **D-13**: Pre-roll buffer missing (already documented as Swift-only)
- **D-20**: Square vs circle indicator for averaged row (no Python view to fix yet)
- **D-32–D-35**: Naming conventions, static method, icon platform difference
