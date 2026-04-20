# Chapter 3 — Guitar Mode

<!-- STATUS: STUB — needs full content -->

## 3.1 Overview of Guitar Resonances

<!-- TODO: Write section -->
<!-- Cover: Air mode (Helmholtz), Top mode, Back mode, Dipole mode, Ring mode, Upper modes.
     Explain why these resonances matter for instrument voicing and how tap-tone analysis
     fits into the lutherie workflow. -->

## 3.2 Setting Up for Guitar Mode

<!-- TODO: Write section -->
<!-- Cover:
     - Selecting guitar type in Settings (Classical / Flamenco / Acoustic Steel String)
     - How the type choice changes the frequency windows used for mode identification
     - Show Unknown Modes toggle (Advanced → Analysis Settings): when to enable it -->

## 3.3 Microphone Placement

<!-- TODO: Write section -->
<!-- Cover:
     - Recommended distance: 5–15 cm from sound hole or tap point
     - Angle and height relative to the instrument
     - Avoiding reflections from hard surfaces or the workbench
     - Marking a position for reproducible comparisons across sessions -->

## 3.4 Single Tap Measurement

<!-- NOTE: Include the Pause workflow for dialling in settings before committing to a
     tap. Pause keeps the spectrum live and suspends detection, allowing the user to
     adjust Threshold and Peak Min while tapping freely. Previously the workaround was
     to move Threshold to -20 (maximum sensitivity / no detection) while adjusting
     Peak Min, then move it back. That workaround is now obsolete — use Pause instead. -->

<!-- TODO: Write section -->
<!-- Cover:
     - Arming with New Tap
     - Using Pause to dial in Threshold and Peak Min before the live take (see §2.6–2.7)
     - Making the tap: short crisp knuckle or fingertip rap; bouncy ball on a stick
     - Green indicator: tap registered; spectrum freezes
     - Reading the annotated peaks on the frozen spectrum -->

## 3.5 Multi-Tap Averaging

<!-- TODO: Write section -->
<!-- Cover:
     - Setting the tap count (1–10) with the Taps stepper
     - Why averaging helps: reduces variance from finger noise and ambient transients
     - Phase progress indicator in the status bar: "Tap N/M"
     - Using Pause between individual taps within a sequence
     - Cancelling mid-sequence with the Cancel button -->

## 3.6 Inspecting and Adjusting Peak Selections

<!-- TODO: Write section -->
<!-- Cover:
     - How automatic mode assignment works: strongest peak in each frequency window,
       lowest-to-highest priority (Air first, then Top, etc.)
     - Tapping a peak label on the chart to toggle its selected state
     - Cycling Annotations (All / Selected / None) using the Annotations button
     - The wand (auto-select) button in the Results panel header: re-runs automatic
       selection on the current frozen spectrum after the user has changed Peak Min
     - Select All / Select None / Reset to Auto buttons in the Results header -->

## 3.7 Overriding Mode Classification

<!-- TODO: Write section -->
<!-- Cover:
     - Identifying a misclassified or Unknown peak in the Results list
     - Tapping the peak row to open the mode picker
     - Available assignments: Air, Top, Back, Dipole, Ring, Upper Modes, Unknown,
       or a custom free-text label
     - How overrides are persisted: saved with the measurement; reapplied on reload -->

## 3.8 Reading the Results Panel

<!-- TODO: Write section -->
<!-- Cover:
     - Peak list columns: mode name / label, frequency (Hz, to 0.1 Hz precision),
       magnitude (dB), Q factor, bandwidth (−3 dB, Hz), nearest pitch
     - Decay time (ring-out in seconds): structural damping indicator
     - Tap Tone Ratio (f_Top ÷ f_Air): typical range 1.8–2.4 for a well-voiced guitar
     - Quality colour indicators next to each value -->

## 3.9 Comparing Guitar Measurements

<!-- TODO: Write section -->
<!-- Cover:

     STARTING A COMPARISON
     - Open the Measurements list
     - Tap to select 2–5 saved guitar measurements (plate/brace records are excluded
       from comparison selection and cannot be mixed with guitar measurements)
     - Tap the Compare button that appears when 2+ records are selected
     - The app overlays all selected spectra on the chart, each in a distinct colour

     THE COMPARISON VIEW
     - Colour-coded curves with a legend identifying each spectrum
     - The Comparison Results table in the Analysis Results panel: columns for each
       spectrum (label + coloured dot), rows for Air, Top, and Back mode frequencies;
       "—" displayed where a mode was not detected
     - Frequency values shown to 0.1 Hz precision, matching the main Results panel

     WHAT IS AND IS NOT AVAILABLE DURING COMPARISON
     - Available: Export Spectrum (overlay PNG), Export PDF Report (comparison PDF)
     - Disabled / inactive: Annotations button, Save (new individual measurement),
       Threshold slider, Peak Min slider, Taps stepper
     - Note: Threshold and Peak Min cannot be adjusted during comparison because they
       affect live detection; the comparison is a static overlay of frozen measurements

     SAVING A COMPARISON
     - Tap Save while the comparison is active: a Save sheet appears, accepting an
       optional location label and notes
     - The saved record appears in the Measurements list alongside regular measurements,
       identified by a distinct comparison badge
     - Reloading a saved comparison restores the full overlay — all spectra, colours,
       and the Comparison Results table — exactly as at save time

     EXPORTING A COMPARISON
     - Export Spectrum: produces an overlay PNG with all curves, their colours, and
       a legend; available from the toolbar (⌘E on macOS) or from the Measurements list
       for a saved comparison record
     - Export PDF Report: produces a comparison PDF containing a metadata header
       (number of spectra, labels, date), the overlay spectrum image, and an
       Air / Top / Back frequency table with one column per spectrum; available from
       the toolbar (⇧⌘E on macOS) or from the Measurements list for a saved record

     IMPORTING A COMPARISON
     - Saved comparison .guitartap files can be imported via File → Import Measurement
       (macOS) or the Import Measurement button (iOS)
     - The app detects the comparison record automatically and restores the overlay
       when the record is loaded

     EXITING COMPARISON
     - Tap New Tap to exit comparison mode and return to single-measurement operation -->
