# Comparison Feature Enhancement Plan

## Background

This document captures the design discussion and implementation plan for two
enhancements to GuitarTap's comparison mode:

1. **Phase 1** — Add a peak mode comparison table to the Analysis Results panel
   when a comparison is active.
2. **Phase 2** — Treat a comparison as a first-class "measurement" that can be
   saved to the measurements store, exported as a `.guitartap` file, imported,
   loaded, and reported via PDF.

---

## Current State

### What comparison mode does today

- The user selects 2–5 saved guitar measurements in `MeasurementsListView` and
  taps **Compare**.
- `TapToneAnalyzer.loadComparison(measurements:)` extracts the `frequencies[]`
  and `magnitudes[]` arrays from each measurement's `spectrumSnapshot` and
  assembles `comparisonSpectra`:

  ```swift
  @Published var comparisonSpectra:
      [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)]
  ```

  Colors cycle through a fixed palette: blue, orange, green, purple, teal.
  Labels are derived from `tapLocation` (or timestamp) and disambiguated if
  duplicates exist (e.g. "Bridge (1)", "Bridge (2)").

- The axis bounds are set to the **union** of all source measurements' saved
  display ranges (`minFreq/maxFreq/minDB/maxDB` from each `SpectrumSnapshot`).

- `displayMode` is set to `.comparison`.

### What the Analysis Results panel shows today

When `displayMode == .comparison` the results panel shows only:

```
⚡ Comparing N measurements
```

No peak data, no properties section. The Export PDF button is also suppressed
(`analyzer.displayMode != .comparison` guard in `TapAnalysisResultsView`).

### What is NOT carried into comparisonSpectra

When `loadComparison` runs, the source `TapToneMeasurement` objects are
available but only spectrum data is extracted. The following are discarded:

- `peaks: [ResonantPeak]` — the detected resonant peaks
- `selectedPeakIDs: [UUID]?` — which peaks the user marked as significant
- `peakModeOverrides: [UUID: UserAssignedMode]?` — any user-assigned mode labels
- `spectrumSnapshot.guitarType` — the guitar type active at save time

---

## Key Technical Facts

### Mode labels

Each peak's mode label is written into the `.guitartap` JSON at save time via
`PeakExportCodingKeys.modeLabel`, using the following resolution priority:

1. User override from `peakModeOverrides[peak.id]` (`.assigned(String)` case)
2. Auto-classification via `GuitarMode.classifyAll(peaks, guitarType:)`
3. Plate/brace material role

**The `modeLabel` field is not read back on decode** — it is a write-only
annotation in the JSON for external consumers (Python tools, etc.). On load,
modes are always recomputed from peaks via `reclassifyPeaks()`.

This means mode classification is *algorithmically* stable across app versions
only as long as `GuitarMode.classifyAll` and the classification boundaries do
not change — the same sensitivity that applies to all other loaded measurements.
This is an accepted trade-off consistent with the existing behaviour.

### Selected peaks

`selectedPeakIDs: [UUID]?` identifies which peaks the user marked as
significant. `nil` means all peaks are selected (backward-compatible default).
The comparison table should use only selected peaks when resolving mode
assignments, matching the intent of the user's saved selections.

### Guitar type per measurement

Mode frequency ranges are guitar-type-dependent (classical/flamenco/acoustic
each have different bands for Air, Top, Back, etc.). The `guitarType` is stored
in `spectrumSnapshot.guitarType`. Cross-type comparisons (e.g. classical vs
acoustic) are valid and each row should use its own measurement's saved guitar
type for classification.

---

## Phase 1: Peak Mode Comparison Table in Analysis Results

### Goal

Replace the bare "Comparing N measurements" message with a grid showing the
**Air**, **Top**, and **Back** peak frequencies for each compared measurement,
using the colour already assigned to that spectrum in the chart.

### Layout

```
┌─────────────────┬──────────┬──────────┬──────────┐
│ Spectrum        │   Air    │   Top    │   Back   │
├─────────────────┼──────────┼──────────┼──────────┤
│ ● Bridge        │  97.3 Hz │ 198.1 Hz │ 215.4 Hz │
│ ● Neck          │  94.1 Hz │ 201.6 Hz │    —     │
│ ● Bridge (2)    │  98.8 Hz │    —     │ 220.0 Hz │
└─────────────────┴──────────┴──────────┴──────────┘
```

- The coloured dot in the first column matches the spectrum line colour in the
  chart.
- Cells show frequency to 1 decimal place (consistent with existing peak
  display). Magnitude is omitted — recording and tapping conditions are not
  controlled enough to make cross-measurement magnitude comparison meaningful.
- A `—` is shown when no peak for that mode was found among the selected peaks.
- Columns are fixed: Air, Top, Back. Dipole and Ring Mode are omitted from
  this summary table (they are less frequently the focus of comparison work).

### Data pipeline changes

#### 1. Extend `comparisonSpectra` tuple

Add `peaks` and `guitarType` to the tuple stored in `TapToneAnalyzer`:

```swift
@Published var comparisonSpectra: [(
    magnitudes:  [Float],
    frequencies: [Float],
    color:       Color,
    label:       String,
    peaks:       [ResonantPeak],           // NEW
    guitarType:  GuitarType?               // NEW
)] = []
```

> **Note on tuple growth:** If the tuple continues to grow it should be
> promoted to a named struct (`ComparisonEntry`) at that point. For Phase 1
> two additional fields is acceptable.

#### 2. Populate in `loadComparison`

In `TapToneAnalyzer+MeasurementManagement.swift`, `loadComparison` already
iterates `withSnapshots` (the filtered array of measurements that have a
`spectrumSnapshot`). Add:

```swift
let selectedIDs = Set(measurement.selectedPeakIDs ?? measurement.peaks.map(\.id))
let selectedPeaks = measurement.peaks.filter { selectedIDs.contains($0.id) }
let guitarType = snap.guitarType
```

Store `selectedPeaks` and `guitarType` in the tuple alongside the existing
spectrum data.

#### 3. Mode resolution helper

Add a helper (e.g. on `TapToneAnalyzer` or as a free function) that, given a
`[ResonantPeak]`, a `[UUID: UserAssignedMode]?`, and a `GuitarType?`, returns
`[GuitarMode: Float]` — a map from mode to the frequency of the peak classified
into that mode:

```swift
func resolvedModePeaks(
    peaks: [ResonantPeak],
    overrides: [UUID: UserAssignedMode]?,
    guitarType: GuitarType?
) -> [GuitarMode: Float] {
    // 1. Run classifyAll to get the base GuitarMode per peak
    // 2. Apply overrides: .assigned(label) does not change the GuitarMode,
    //    only the display string — so overrides have no effect on this map
    //    (the GuitarMode classification is not altered by UserAssignedMode)
    // 3. Return [mode: peak.frequency] for the winning peak per mode
}
```

> **Note:** `UserAssignedMode` only overrides the *display string*, not the
> underlying `GuitarMode` enum value. So override application is not needed
> for the frequency lookup — `GuitarMode.classifyAll` alone is sufficient.

#### 4. New comparison results view

Replace the "Comparing N measurements" placeholder in `TapAnalysisResultsView`
with a new `ComparisonResultsView` (or inline `@ViewBuilder`). It iterates
`analyzer.comparisonSpectra`, calls `resolvedModePeaks` per entry, and renders
the grid. The view is self-contained and stateless — it reads from the published
`comparisonSpectra` array.

### Files touched (Phase 1)

| File | Change |
|------|--------|
| `TapToneAnalyzer+MeasurementManagement.swift` | Extend tuple; populate `peaks` + `guitarType` in `loadComparison` |
| `TapToneAnalyzer.swift` | Add `resolvedModePeaks` helper (or new extension file) |
| `TapAnalysisResultsView.swift` | Replace placeholder with `ComparisonResultsView` |
| `ComparisonResultsView.swift` | New file: the grid view |

No model changes, no persistence changes, no export changes.

---

## Phase 2: Comparison as a Saved Measurement

### Goal

Allow the user to:

- **Save** the current comparison to the measurements store
- **Export** it as a `.guitartap` file
- **Import** a `.guitartap` file that contains a saved comparison
- **Load** a saved comparison (restoring the chart overlays and the Phase 1
  peak table)
- **Export PDF** — a comparison-specific PDF report
- **Export Spectrum** — the comparison chart rendered as a PNG

A saved comparison is a new kind of first-class measurement. It does not
represent a single tap event; it represents a named snapshot of N spectra that
were compared at a point in time.

### Data model

#### New `ComparisonEntry` struct

```swift
struct ComparisonEntry: Codable, Identifiable {
    let id: UUID                        // stable identity for the entry
    let label: String                   // display label (already disambiguated)
    let colorComponents: [Double]       // RGBA — Color is not Codable
    let snapshot: SpectrumSnapshot      // full spectrum data + axis ranges
    let peaks: [ResonantPeak]           // selected peaks at save time
    let guitarType: GuitarType?         // guitar type at save time
    let sourceMeasurementID: UUID?      // optional back-reference to source
}
```

Storing `colorComponents` instead of `Color` is required because `Color` does
not conform to `Codable`. A simple `[Double]` (red, green, blue, alpha) is
sufficient; the fixed palette makes round-tripping exact.

#### Changes to `TapToneMeasurement`

Add an optional array of `ComparisonEntry`:

```swift
var comparisonEntries: [ComparisonEntry]?
```

When `comparisonEntries` is non-nil, the measurement is a comparison record.
Existing fields (`peaks`, `spectrumSnapshot`, etc.) remain present but are
effectively unused for comparison records — they can be left `nil` or empty.

This is additive and backward-compatible: existing measurements that do not
have `comparisonEntries` decode with `nil` and are unaffected.

A new `MeasurementType` case is **not** required. The presence of
`comparisonEntries` is sufficient to identify a comparison record.
Alternatively a `Bool` flag `isComparison` could be added, but the array's
non-nil state is unambiguous.

> **Alternative considered:** Adding `case comparison` to `MeasurementType`.
> Rejected because `MeasurementType` drives guitar-vs-plate/brace display
> logic throughout the app via exhaustive `switch` statements. Adding a new
> case causes compiler-enforced changes across all those switches, many of
> which would just be `case .comparison: break`. The array presence flag
> avoids that churn.

#### Save action

A **Save Comparison** button appears in the Analysis Results panel (or
toolbar) when `displayMode == .comparison`. It:

1. Snapshots the current `comparisonSpectra` into `[ComparisonEntry]`
2. Prompts for a name/label for the comparison record
3. Creates a `TapToneMeasurement` with `comparisonEntries` populated and all
   other fields nil/empty
4. Appends to the measurements store via the existing save path

#### Load / display

When `loadMeasurement` is called with a comparison record:

1. Detect `comparisonEntries != nil`
2. Rebuild `comparisonSpectra` directly from the entries (no source measurements
   needed — the data is self-contained)
3. Set `displayMode = .comparison`
4. Restore axis bounds from the union of entry snapshot bounds (same logic as
   `loadComparison`)

#### Export `.guitartap`

No changes to the file format beyond the new `comparisonEntries` field on
`TapToneMeasurement`. The existing `exportMeasurement` function and
`MeasurementFileExporter` work unchanged — the measurement serialises to JSON
like any other.

#### Import `.guitartap`

No changes needed. The existing import path decodes `TapToneMeasurement` from
JSON; the new `comparisonEntries` field decodes automatically. The importer
calls `loadMeasurement` which already handles comparison records after the load
path change above.

#### Export PDF

A comparison PDF has a different structure from a single-measurement PDF:

| Section | Content |
|---------|---------|
| Header | App name, comparison label, date |
| Metadata | N spectra listed with label, guitar type, timestamp |
| Spectrum image | The comparison overlay chart rendered to PNG |
| Peak mode table | Same Air/Top/Back grid from Phase 1 |
| Footer | Version, generation timestamp |

The single-measurement sections (ring-out time, stiffness properties, tap
instructions) are absent.

Implementation requires:
- `ComparisonPDFReportData` struct (parallel to `PDFReportData`)
- `ComparisonPDFReportContentView` — the SwiftUI layout view rendered
  off-screen by `ImageRenderer`
- A new `exportComparisonPDFReport()` function in `TapToneAnalysisView+Export`
  that routes to this path when `displayMode == .comparison`

The spectrum image rendering already works — `ExportableSpectrumChart` handles
comparison overlays correctly and is already used for the existing spectrum
export.

#### Export Spectrum (PNG)

The existing `exportCurrentSpectrum()` / `MeasurementFileExporter.exportSpectrumImage`
path works as-is for comparison mode — `ExportableSpectrumChart` already renders
the comparison overlays. The only change needed is to un-suppress the export
button when `displayMode == .comparison` (currently it may be disabled).

### Files touched (Phase 2)

| File | Change |
|------|--------|
| `TapToneMeasurement.swift` | Add `comparisonEntries: [ComparisonEntry]?`; new `ComparisonEntry` struct |
| `TapToneAnalyzer+MeasurementManagement.swift` | `loadMeasurement` — detect and restore comparison; add `saveComparison()` |
| `TapToneAnalysisView+Export.swift` | Route PDF export to comparison path when `displayMode == .comparison` |
| `PDFReportGenerator.swift` | Add `generateComparisonPDF(data:)` method |
| `ComparisonPDFReportData.swift` | New file: data struct for comparison PDF |
| `ComparisonPDFReportContentView.swift` | New file: SwiftUI layout for comparison PDF |
| `TapAnalysisResultsView.swift` | Add Save Comparison button; un-suppress export buttons |
| `MeasurementsListView.swift` | Display comparison records correctly in the list |

---

## Implementation Order

Phase 1 and Phase 2 are independent and can be done in sequence. Phase 1 is
purely additive — it touches no persistence, no file format, and no export
paths. Phase 2 depends on Phase 1's `ComparisonEntry`-like data structure and
the `resolvedModePeaks` helper, so Phase 1 first is the natural order.

### Phase 1 steps

1. Extend `comparisonSpectra` tuple with `peaks` and `guitarType`
2. Populate in `loadComparison`
3. Add `resolvedModePeaks` helper
4. Build `ComparisonResultsView` grid
5. Wire into `TapAnalysisResultsView`

### Phase 2 steps

1. Define `ComparisonEntry` struct
2. Add `comparisonEntries` to `TapToneMeasurement` (with encode/decode)
3. Add `saveComparison()` and update `loadMeasurement` in the analyzer
4. Add Save Comparison button to results panel
5. Update `MeasurementsListView` to display comparison records
6. Build `ComparisonPDFReportData` and `ComparisonPDFReportContentView`
7. Route PDF export when `displayMode == .comparison`
8. Un-suppress spectrum export for comparison mode

---

## Resolved Decisions

- **Naming a saved comparison:** Use the existing save form — the same
  Location + Notes sheet presented for any other measurement save. No
  auto-generated name. The user types the comparison name into the Location
  field exactly as they would for a tap measurement.

- **Re-compare from a saved record:** Out of scope. A saved comparison is
  read-only. Re-selecting measurements to compare is not supported from a
  loaded comparison record. This is naturally enforced because
  `MeasurementsListView` only allows comparison selection of guitar
  measurements, not comparison records.

- **Dipole/Ring Mode columns:** Omitted by design. Luthiers do not routinely
  track Dipole or Ring Mode across builds. The table is Air, Top, Back only.
  Additional columns are not planned.

- **Python parity:** After Phase 2 is complete and the Swift file format is
  stable, Phase 1 and Phase 2 will be implemented in the Python codebase.
  The Python implementation must mirror the Swift structure to avoid
  structural divergence — the same `ComparisonEntry` shape in the JSON,
  the same grid layout in the analysis results view, and the same PDF
  section order. The Python work is treated as a follow-on task, not part
  of this plan.
