# GuitarTap Beta Release Notes

---

## Version 1.0 · Build 254
### What's New Since Build 245

---

## New Features

### Play Audio File

- You can now analyse a tap tone from a **WAV file** rather than a live microphone input. Use **File → Play Audio File** (macOS menu bar) or the Play File button in the toolbar.
- The file plays through the FFT analyser exactly as a live tap would — peak detection, spectrum display, and results all work identically.
- After playback the spectrum freezes and results are available to save, export, or compare as normal.
- The last-used folder for audio files is remembered between sessions.

---

## Improvements

### Comparison Table

- Long measurement titles in the Comparison Results table are now truncated so the table remains readable when measurement names are lengthy.

### Reliability

- Fixed several cases where the audio engine could fail to start, particularly on first launch or after switching audio devices. The engine now recovers more reliably.
- Fixed erratic or inconsistent results when analysing from a WAV file — playback timing and FFT synchronisation have been made more robust.
- Fixed an issue where the FFT analyser tap could fail to start under certain conditions; the app version is now also written to the log on launch to aid diagnostics.

### macOS — Wrong Build Warning

- If you accidentally try to run an iOS build of GuitarTap on macOS (via Catalyst or a mismatched binary), the app now detects this and shows a clear message rather than misbehaving silently.

---

## Bug Fixes

- Fixed a bug where the last-used directory for audio file selection was not being saved correctly between sessions.

---

---

## Version 1.0 · Build 245
### What's New Since Build 180

---

## New Features

### Comparison Mode — Major Upgrade

- The Analysis Results panel now shows a **Comparison Results table** while comparing: Air, Top, and Back peak frequencies are displayed in a grid, one column per spectrum, with colour-coded dots matching the chart curves. Missing modes show "—".
- **Save a Comparison** — while a live comparison is active, the Save button stores the entire overlay as a single record in the Measurements list. Reloading it later restores all spectra, colours, and the Comparison table exactly as they were.
- **Export Comparison Spectrum** — Export Spectrum during a live comparison (or from a saved comparison record) produces an overlay PNG with all coloured curves and a legend.
- **Export Comparison PDF** — Export PDF Report during a live comparison produces a comparison PDF containing the spectrum overlay image and the Air / Top / Back frequency table. (Previously unavailable during comparison.)
- **Import Comparison** — saved comparison `.guitartap` files can be imported and reloaded.

### Accept / Redo for Plate and Brace Measurements

- After each tap phase (Longitudinal, Cross-grain, FLC) the spectrum now **freezes automatically** and the detector pauses while you review the result.
- The **Pause button becomes Accept** (green) — tap it to lock in the result and advance to the next phase.
- The **Cancel button becomes Redo** (labelled "Redo L", "Redo C", or "Redo FLC") — tap it to discard the phase and re-tap without restarting the whole sequence.
- The live spectrum is suppressed during review so the captured result stays on screen.
- The phase progress indicator ("Phase 1/2", "Phase 1/3") is shown in the status bar; it is hidden when there is only one phase (Brace mode).

### Pause / Resume Now Available in Guitar Mode

- Pause was previously only available during plate/brace sequences. It now works in guitar mode too, letting you freeze the live display, adjust Threshold and Peak Min, and re-arm without triggering an accidental measurement.

### Edit Measurement Location and Notes

- Saved measurements can now have their location label and notes edited after the fact. Long-press (iOS) or right-click (macOS) a measurement row to access Edit Location & Notes.

### Spectrum Chart Title

- The chart now displays the measurement's location label (or "New" if unsaved) as the chart title, making it easier to track which measurement is on screen.

### Loaded-Measurement Warning

- When a saved measurement is loaded into the view, a warning is shown in the status bar if the measurement's recorded settings (Threshold, tap count) differ from the current live settings.

---

## Improvements

### Plate and Brace

- Adaptive noise floor for plate/brace live measurements — the detector now uses an EMA-based noise floor rather than a fixed threshold, reducing false triggers during the multi-phase sequence.
- FLC peak detection refined for better identification of the weaker FLC resonance.
- Peak selection in the Analysis Results panel for plate/brace is now cleaner — phase badges (L, C, FLC) are shown as informational labels, not interactive controls.
- Results ordering for plate and brace has been reorganised to match the natural measurement sequence.
- PDF output for plate/brace now matches what is shown in the live results panel.

### Peak Frequencies

- All peak frequencies are now displayed to **0.1 Hz precision** (one decimal place) in the Results panel, Comparison table, and PDF reports.

### Spectrum Image Export

- Exported spectrum images now match the live view: same chart title, same mode-line label positions, and correct coordinate handling for dragged annotations.

### Measurements List

- Default documents folder changed to `Documents/GuitarTap` for cleaner file organisation.
- The last-used export/import directory is remembered between sessions.
- Duplicate measurement import is handled correctly.

### macOS Menu Bar

- Menu bar items have been cleaned up and reorganised.
- The Edit menu no longer flickers on macOS.
- The Help menu item now works correctly again (was broken in an earlier build).

### Show Unknown Peaks

- Fixed a bug where toggling "Show Unknown Modes" in Settings did not update the peak annotations already displayed on the chart.

### Status Bar

- Status bar values (peak magnitude, input level) now update at the correct rate and show consistent numbers between the left and right sides.
- Status bar correctly shows different information for guitar vs. plate/brace measurements.

### Quality Colour Indicators

- Fixed a duplication where the quality colour was being applied incorrectly in the PDF vs. the live results view.

---

## Bug Fixes

- Fixed display oscillation (spectrum flickering between states) that could occur in certain conditions.
- Fixed import error handling — import failures now report correctly rather than silently failing.
- Fixed the Save button disappearing unexpectedly in some states.
- Fixed wrong coordinate space being used when exporting a spectrum with repositioned (dragged) annotations.
- Fixed scroll wheel on macOS causing too-rapid axis updates and visual clutter.
- Fixed cross-platform import: measurements saved on iOS can now be imported on macOS and vice versa, even if the microphone name doesn't match (a fallback is applied).
- Fixed a bug on iOS/iPadOS where receiving a `.guitartap` file via AirDrop would open a new instance of the app rather than routing the file to the existing running instance. Multiple app instances no longer accumulate after repeated AirDrop receives.

---

*Build number is generated automatically from the git commit count.*
