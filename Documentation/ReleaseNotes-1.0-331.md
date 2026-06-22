# GuitarTap Release Notes

---

## Version 1.0 · Build 331
### What's New Since Build 330

---

## Improvements

### Cross-Platform File Compatibility

- Measurement files (`.guitartap`) are now fully interchangeable with the open-source GuitarTap Python build. The file-format appendix in the User Manual has been corrected to describe the exact on-disk format, and the example measurement published on the website has been refreshed to the current format.

---

## Bug Fixes

- Fixed loading of `.guitartap` files created by the GuitarTap Python build that contained user-assigned peak **mode-label overrides**. Such files previously failed to open; they now load correctly. Files without custom mode labels were unaffected.

---

---

## Version 1.0 · Build 330
### What's New Since Build 319

---

## New Features

### User Manual

- A comprehensive **User Manual** is now available, covering all three measurement modes (Guitar, Plate, Brace), the spectrum chart, saving and exporting measurements, a complete settings reference, a controls reference, and tips and troubleshooting. Eleven chapters plus appendices for keyboard shortcuts and file formats. The manual is published separately as HTML and PDF. The manual can be opened from the Help in the menu bar, from the Settings dialog, or from the help (?) button on iOS.

---

## Improvements

### Measurement Detail View

- The detail-pane buttons (Load into View, Edit, Export Spectrum, Export PDF Report) have been removed. All these actions are still available — and were always available — via the popup menu on a measurement row. The detail pane is now strictly a read-only view of the measurement.
- The Edit popup-menu item has been renamed from "Edit…" to **Edit Name & Notes** so the action is explicit about what it edits.

### Date and Time in the Measurements List

- Each measurement row now shows both the **date and time** of capture rather than time only. The display respects the current locale.

### Quick-Start Guide

- The Quick-Start Guide has been refreshed.

---

## Bug Fixes

- Fixed a detection-state hang reproducible on iPad: loading a saved plate measurement, lowering the Threshold below the room's noise floor, then changing the measurement type back to Generic Guitar would cause a phantom tap to fire, leaving the analyzer stuck with **Pause** enabled and **New Tap** disabled. The fix is mirrored in the Python build.
- Fixed a state-machine glitch on measurement-type change when the Threshold setting is below the noise floor.

---

---

## Version 1.0 · Build 319
### What's New Since Build 254

---

## New Features

### Plate and Brace Measurements

- The Plate and Brace measurement modes have been overhauled and now produce correct, repeatable results across iOS, macOS, iPadOS, and the Python build for the same captured audio.
- Each tap phase (Longitudinal, Cross-grain, FLC for plates; Longitudinal for braces) freezes the spectrum on completion so the result can be reviewed before accepting or redoing.
- Cross-grain (fC) peak selection now picks the strongest peak rather than the lowest, which avoids re-selecting the longitudinal peak when the two frequency ranges overlap.
- An optional preference makes fC always greater than fL, useful for plates where the two modes are close.
- Plate PDF report generation has been completed: results from all phases are rendered with annotations matching the live view.
- The Hann window applied during the gated brace/plate capture has been corrected, and the actual hardware sample rate is now read from the input format rather than assumed (fixes a UMIK-1 mis-rate on some Macs).

### Generic Guitar Type

- A new **Generic Guitar** measurement type joins Classical, Flamenco, and Acoustic. Use it for guitars that do not fit cleanly into one of the specific body types, or for initial exploration. Generic uses broad mode-frequency ranges that cover every guitar style.

### Multi-Tap Comparison for Guitar Measurements

- When you capture a multi-tap guitar measurement, the Results panel now provides a comparison view showing each individual tap alongside the averaged result. Switch between the averaged spectrum and per-tap spectra to identify variation across taps.
- PDF export for multi-tap guitar measurements now renders as a two-page report — the averaged spectrum on page 1 and the per-tap comparison on page 2.
- Peak annotations and the peaks table update live during a multi-tap sequence so you can watch the average converge.

### Re-Analyze Button on Loaded Measurements

- Loaded measurements have a **Re-analyze** button that re-runs peak detection against the stored spectrum using the current settings. Useful for trying a different peak-min threshold or guitar type without re-tapping.

### Magnitude Edge-Detection Trigger

- The tap-trigger has been changed from "FFT peak above threshold" to **magnitude (RMS) edge detection**. This is faster, more responsive, and far less prone to false triggers from spectral leakage. The Threshold slider continues to control the trigger level in all modes.

### Microphone Name on the Results Panel

- The Analysis Results panel now displays the name of the microphone used for the capture. Saved measurements record the microphone name so it appears on subsequent loads and on the PDF report.

### Pause / Resume in Guitar Mode

- Pause was previously only available in plate/brace mode. It now works in guitar mode too, letting you freeze the live display, adjust Threshold or Peak Min, and resume without an accidental measurement firing.

---

## Improvements

### Hysteresis and Max Peaks — Settings Removed

- The Hysteresis and Maximum Peaks settings have been retired. Hysteresis is now hardcoded to a sensible value (3 dB), and Maximum Peaks is "all" — every peak above the Peak-Min threshold is returned. This simplifies the settings panel and removes two knobs that needed tuning to get good results.

### Threshold Naming and Coverage

- The "Peak Threshold" setting has been renamed to **Peak Min Threshold** to make clear that it gates the minimum magnitude required for a peak to be reported. The Tap Detection Threshold remains a separate setting that controls the rising-edge tap trigger and is now active in every measurement mode.
- The Peak Min slider is automatically disabled when a measurement comparison is being displayed, since the threshold cannot meaningfully apply across multiple saved results.

### Audio File Playback

- Stereo input files are now downmixed to mono correctly, matching the live-mic processing path.
- File reading uses a more robust API that handles a wider range of WAV variants.
- Playback flutter introduced by the audio engine has been eliminated by reworking the playback engine.
- The chart title shows the filename during and after playback and resets to "New" when a fresh tap sequence is started (for example, by switching measurement type to brace after playback ends).

### Microphone and Audio Engine

- iPhone microphone connect / disconnect during a measurement is now handled gracefully — transient audio-engine errors no longer cause a crash, and a new microphone is picked up automatically.
- The audio engine no longer stops when a non-main window closes.
- The "CADefaultDeviceAggregate" pseudo-device that macOS sometimes synthesises is now filtered out of the device list.
- Fixed an audio-engine restart crash and cleaned up the hot-switch flow.

### iPhone

- The VU meter and threshold slider now use the correct layout in landscape orientation.
- Slow text editing on iPhone (in measurement notes / location) has been addressed.

### Spectrum Image and PDF Export

- Exported images and PDFs now match the live view: same chart title, same mode-line label positions, and the captured measurement type, platform, and software version are stamped on the export.
- Mode identification has been fixed so the correct modes are labelled on every export.

### Saved Measurements

- Double-click a saved measurement to load it; a single click no longer triggers a load (which previously made it easy to load a measurement by accident while trying to select one for comparison).
- Peak annotations are now suppressed in comparison mode for clarity.
- The peak-comparison view no longer scrolls when a measurement row is selected.

### Comparison Mode

- Fixed the transition from a multi-tap measurement to a comparison so the comparison view renders correctly.
- Disabled the Peak Min slider while a comparison is shown.

### User-Defined Modes

- User-defined modes now have their own dedicated color and icon and are surfaced in the peak table and annotations during multi-tap sequences.

### Logging

- Logs are now reachable on every platform via the app's standard log location, making it easier to diagnose issues without a developer build.

---

## Bug Fixes

- Fixed a bug where captured guitar taps were silently discarded whenever the measurement type was Acoustic, Classical, or Flamenco. Only Generic Guitar produced results before this fix.
- Fixed the chart title not resetting after switching measurement type post file-playback.
- Fixed a spurious peak detected in brace measurements.
- Fixed a crash caused by a double-free during measurement transitions.
- Fixed peak dots being drawn outside the visible graph range.
- Fixed mode-identification algorithm so modes are labelled consistently.
- Fixed a Hann-windowing bug that affected the gated-FFT amplitude.
- Fixed UMIK-1 sample rate detection on some Macs (was assumed, now read from the input format).
- Fixed transitions from a multi-tap measurement with results showing into a comparison measurement.
- Fixed save-name behaviour and the New Tap button visibility after a Cancel.

---

---

## Version 1.0 · Build 254
### What's New Since Build 245

---

## New Features

### Play Audio File

- You can now analyse a tap tone from a **WAV file** rather than a live microphone input. Use **File > Play Audio File** (macOS menu bar) or the Play File button in the toolbar.
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
