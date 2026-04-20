# GuitarTap User Manual — Outline

**Document:** GuitarTap User Manual
**Scope:** iOS (iPhone & iPad), macOS, Windows, and Linux (Python desktop app)
**Output formats:** HTML and PDF (via WeasyPrint)
**Status:** Outline — not yet written

---

## Document Structure

Each chapter is a separate Markdown file under `Documentation/Manual/`.
Screenshots live in `Documentation/Manual/images/`.
A `generate-manual.sh` script combines them and produces HTML + PDF.

---

## Chapter 1 — Introduction

**Purpose:** Orient the new user. What the app does, what it does not do, and what equipment is needed.

### 1.1 What Guitar Tap Does
- Acoustic resonance analysis using FFT
- Three measurement modes: Guitar, Plate, Brace
- Brief explanation of tap tones and why they matter in lutherie

### 1.2 What You Need
- Device requirements:
  - **iOS/iPadOS:** iPhone or iPad (any model supported by the current iOS version)
  - **macOS:** Mac running macOS 14 Sonoma or later
  - **Windows:** PC running Windows 10 or later with Python desktop app installed
  - **Linux:** Desktop system with Python desktop app installed
- Microphone: built-in vs. external / audio interface — trade-offs discussed in Ch. 2
- A tapping implement: recommended is a small bouncy ball on the end of a stick (gives a consistent short contact time and clean impulse); a firm knuckle rap or fingertip works for most guitar-body measurements
- A quiet workspace
- The wood or instrument to be measured
- Optional: calibration file (.txt or .cal) for a measurement microphone

### 1.3 How This Manual Is Organised
- Pointer to Getting Started (Ch. 2) for first-time users
- Pointer to Guided Use Cases (Ch. 3–8) for task-focused workflows
- Pointer to Reference (Ch. 9–11) for complete feature details

**Screenshots required:**
- [ ] Main analysis screen — four-way comparison: macOS, iPad, iPhone portrait, Windows/Linux desktop
- [ ] Example frozen spectrum with annotated peaks (guitar mode)
- [ ] Example results panel showing tap tone ratio and decay time
- [ ] Photo: bouncy ball on a stick tapping implement

---

## Chapter 2 — Getting Started

**Purpose:** Get from fresh install to first successful measurement.

### 2.1 Installing the App
- **iOS/iPadOS:** App Store
- **macOS:** Mac App Store
- **Windows:** Python desktop app — installation steps (Python runtime, pip install, launch)
- **Linux:** Python desktop app — installation steps (Python runtime, pip install, Pango native library, launch)
- First launch on each platform

### 2.2 Granting Microphone Permission
- **iOS:** in-app permission dialog on first launch
- **macOS:** System Settings → Privacy & Security → Microphone
- **Windows:** Windows Settings → Privacy & Security → Microphone
- **Linux:** typically no permission dialog; microphone access governed by PulseAudio/PipeWire device permissions
- What happens if permission is denied on each platform; how to re-enable

### 2.3 Selecting Your Audio Input
- Opening Settings
- Choosing a microphone or audio interface from the list
- Built-in mic vs. external interface: trade-offs
- Note: changes take effect immediately, not affected by Cancel

### 2.4 Importing a Microphone Calibration File
- What a calibration file is and why it matters
- Supported formats: .txt, .cal
- How to import; how calibrations are associated per device
- How to tell if calibration is active

### 2.5 Choosing a Measurement Type
- Classical Guitar, Flamenco, Acoustic/Steel String
- Material (Plate), Material (Brace)
- How the choice affects frequency windows, results, and calculations

### 2.6 Setting the Threshold — Finding Your Tap Level
- What the Threshold slider controls: the signal level that triggers tap detection
- Why it needs to be set for your specific microphone, room, and tapping style before relying on results
- **Step 1 — Press Pause** (press New Tap first if a previous measurement is frozen): detection is suspended and the spectrum stays live; you can tap freely without triggering a measurement
- **Step 2 — Make a representative tap** and observe the peak magnitude on the live spectrum; note the highest dB level reached
- **Step 3 — Adjust Threshold** to approximately 6–10 dB below the observed peak level, giving headroom for variation while staying well above background noise
- **Step 4 — Press Resume, then test:** make the same tap; confirm the spectrum freezes and a "tap registered" indicator appears
- Iterating: if the tap is missed, lower the threshold; if ambient noise triggers false detections, raise it
- Relationship to Hysteresis Margin: the detector resets only when the signal drops this far below the threshold — default 3 dB is a good starting point
- Note: Threshold affects all three measurement modes equally

### 2.7 Setting Peak Min — Filtering the Peak List (Guitar Mode)
- What Peak Min controls: the minimum magnitude (dB) a spectral peak must reach to be annotated on the chart and included in guitar mode analysis
- **Why this step applies mainly to guitar mode:** in Plate and Brace modes the tap capture uses its own adaptive noise floor; Peak Min only affects which peaks are *displayed* on the chart, not which ones are selected for the calculation
- **Step 1 — Press Pause** (press New Tap first if a previous measurement is frozen): the spectrum stays live and peaks update in real time; adjust Threshold and Peak Min freely without risking an accidental tap trigger
- **Step 2 — Make representative taps** while paused and observe which peaks appear; raise Peak Min until noise peaks disappear, lower it until the structural resonances are visible
- **Step 3 — Press Resume** when the settings look right, then make the real measurement tap
- **Step 4 — Verify the Results panel** shows the expected modes; use the wand button to re-run automatic selection if needed after adjusting Peak Min on a frozen spectrum
- Saving the adjusted values: Peak Min and Threshold are saved automatically between sessions

### 2.8 Your First Tap — Guitar Mode Walkthrough
- Position the microphone (5–15 cm from sound hole or tap point)
- Press Pause to set Threshold and Peak Min as described in §2.6 and §2.7 (the analyzer is already running on first launch)
- Press Resume to arm the detector
- Give the guitar a knuckle rap or use the bouncy ball on a stick
- Observe the frozen spectrum and annotated peaks
- Open the Results panel and review frequencies, decay time, and tap tone ratio
- Save the measurement

**Screenshots required:**
- [ ] iOS permission dialog
- [ ] macOS Microphone permission in System Settings
- [ ] Windows Microphone permission in Settings
- [ ] Settings sheet — Audio Input section (iOS, macOS, and Windows/Linux desktop)
- [ ] Settings sheet — Measurement Type section
- [ ] New Tap armed then Pause pressed — live spectrum with tap impulse visible
- [ ] Threshold slider being adjusted while paused (live spectrum active)
- [ ] Peak Min being adjusted while paused (peaks updating in real time)
- [ ] Resume pressed — detector armed, status bar showing ready state
- [ ] Frozen spectrum immediately after a tap
- [ ] Results panel open alongside spectrum (iPad/macOS/desktop)
- [ ] Save Measurement sheet
- [ ] Photo: bouncy ball on stick vs. knuckle tap technique

---

## Chapter 3 — Guitar Mode

**Purpose:** Step-by-step guide to classifying resonant modes of a completed instrument.

### 3.1 Overview of Guitar Resonances
- Air mode (Helmholtz cavity resonance)
- Top mode (main top-plate bending)
- Back mode
- Dipole mode
- Ring mode
- Upper modes
- Why these matter for instrument voicing

### 3.2 Setting Up for Guitar Mode
- Selecting the correct guitar type in Settings (Classical / Flamenco / Steel String)
- Frequency windows shown in Settings for each mode
- Show Unknown Modes toggle (Advanced → Analysis Settings)

### 3.3 Microphone Placement
- Distance: 5–15 cm from sound hole or tap point
- Angle and position tips
- Avoiding reflections from hard surfaces

### 3.4 Single Tap Measurement
- Arming with New Tap
- Tapping technique: short crisp knuckle or fingertip rap
- Green indicator: tap registered
- Spectrum freezes automatically
- Reading the annotated peaks

### 3.5 Multi-Tap Averaging
- Setting the tap count (1–10) using the Taps stepper
- Why averaging helps: reduces noise from finger squeaks and ambient sounds
- Progress indicator in the status bar
- Using Pause between taps
- Cancelling a sequence mid-way

### 3.6 Inspecting and Adjusting Peak Selections
- How automatic mode selection works (strongest peak per frequency range, lowest-to-highest priority)
- Tapping a peak label to toggle selection
- Cycling Annotations: All / Selected / None
- Resetting to automatic selection using the wand button in Results

### 3.7 Overriding Mode Classification
- Identifying a misclassified or Unknown peak
- Tapping the peak in the Results list to assign a mode manually
- How overrides are saved with the measurement

### 3.8 Reading the Results Panel
- Peak list: frequency, magnitude, Q factor, bandwidth, pitch
- Decay time (ring-out in seconds)
- Tap Tone Ratio (Top ÷ Air): typical range 1.8–2.4
- Quality indicators

### 3.9 Comparing Guitar Measurements
- Saving measurements at different build stages or tap locations
- Using the Measurements list Compare button
- Selecting 2–5 guitar measurements (plate/brace measurements excluded)
- Overlaid colour-coded spectra with legend
- The Comparison Results table: Air / Top / Back peak frequencies for each spectrum, with colour-coded dots matching chart curves
- What is and is not available during comparison: Annotations and Save (new measurement) disabled; Threshold and Peak Min sliders disabled; Export Spectrum and Export PDF Report remain available
- Exiting comparison mode with New Tap
- **Saving a Comparison** — using the Save button during an active comparison saves the entire overlay as a single record in the Measurements list; it can be reloaded later to restore the overlay exactly as it was
- **Exporting a Comparison** — Export Spectrum produces an overlay PNG with all curves and legend; Export PDF generates a comparison report with the spectrum overlay and an Air / Top / Back frequency table for each spectrum (cross-reference §7.12–7.14)
- **Importing a Comparison** — saved comparison .guitartap files can be imported back; the app detects the comparison record and restores the overlay

**Screenshots required:**
- [ ] Settings — guitar type selection with frequency windows visible
- [ ] Microphone positioned near a guitar (suggested photo, not a screenshot)
- [ ] New Tap button in armed state
- [ ] Frozen spectrum with all six modes labelled
- [ ] Multi-tap progress bar / status indicator
- [ ] Peak label tapped to toggle selection
- [ ] Annotations cycle: All vs Selected vs None
- [ ] Results panel: peak list with Q, bandwidth, decay time, tap tone ratio
- [ ] Wand/reset button in Results panel
- [ ] Comparison mode: 3 overlaid spectra with colour legend
- [ ] Comparison Results table (Air / Top / Back grid with colour dots)
- [ ] Save Comparison sheet
- [ ] Comparison PDF report (one page)

---

## Chapter 4 — Plate Mode

**Purpose:** Measure Young's modulus and material quality of a raw tonewood plate using the free-free beam technique.

### 4.1 Overview of Plate Material Measurements
- Free-free beam theory: why we use 22% node-point suspension
- Three taps: Longitudinal, Cross-grain, FLC (optional)
- What the measurements tell you: E_L, E_C, specific modulus, radiation ratio, quality rating
- When to use Plate mode (raw blanks before cutting)

### 4.2 Preparing the Sample
- Cutting a rectangular blank
- Measuring: length (along grain), width (cross grain), thickness, mass
- Required accuracy; suitable scales
- How errors in dimensions affect results

### 4.3 Entering Dimensions in Settings
- Settings → Measurement Type → Material (Plate)
- Length, Width, Thickness, Mass fields
- Live density preview for catching data-entry errors
- Body dimensions for Gore target thickness (body length, lower bout width)
- Plate stiffness preset: Steel String Top (75), Steel String Back (55), Classical (50), Custom

### 4.4 The 22% Suspension Technique
- Diagram: hold point location on each axis
- How to hold without damping the resonance being measured
- Avoiding the cross-axis nodal line
- Tap location: centre of the plate

### 4.5 The Accept / Redo Review Flow
- After each tap phase the spectrum freezes and the detector pauses automatically — the user reviews the result before continuing
- **Accept** button (replaces Pause during review): advances to the next phase; the accepted result is locked in
- **Redo** button (replaces Cancel during review): discards the current phase and returns to capture; labelled "Redo L", "Redo C", or "Redo FLC" depending on phase
- The status bar shows which phase is active and how many taps remain within that phase
- During review the live spectrum is suppressed so the accepted measurement stays on screen
- After all phases are accepted the results panel updates with the complete plate calculations

### 4.6 Tap 1 — Longitudinal
- Grain orientation (left–right)
- Hold point: 22% from one end along the length, near one long edge
- Tapping: centre, after pressing New Tap
- Status prompt: "Capturing Longitudinal" → spectrum freezes → Accept or Redo
- Phase progress indicator: "Phase 1/2" (or "Phase 1/3" if FLC enabled)

### 4.7 Tap 2 — Cross-Grain
- Rotating the plate 90°
- Hold point: 22% from one end along the width, near one short edge
- Status prompt: "Capturing Cross-grain" (advances automatically after Longitudinal accepted)
- Accept or Redo as above

### 4.8 Tap 3 — FLC (Optional)
- Enabling Measure FLC in Settings
- Hold point: midpoint of one long edge
- Tap point: near opposite corner (~22% from both end and side)
- Why FLC matters: shear modulus for Gore thickness
- Effect of omitting FLC: ~5–7% over-estimate in target thickness
- Status prompt: "Capturing FLC" → Accept or Redo

### 4.9 Reading Plate Results
- E_L / E_C (GPa)
- c_L / c_C (m/s)
- Specific modulus E/ρ
- Radiation ratio R
- Cross/Long ratio (spruce: typically 0.04–0.08)
- Quality rating: Excellent / Very Good / Good / Fair / Poor (spruce scale)
  - ≥ 25 → Excellent (Master grade); ≥ 22 → Very Good (AAA); ≥ 19 → Good (AA); ≥ 16 → Fair (A); < 16 → Poor
- Gore target thickness (requires FLC or omits shear correction)

### 4.10 Interpreting and Comparing Plate Results
- What specific modulus tells you vs. Young's modulus alone
- How to use the Gore target thickness in practice
- Keeping notes across multiple blanks

**Screenshots required:**
- [ ] Settings — Material (Plate) dimensions entry with density preview
- [ ] Settings — Gore target thickness presets
- [ ] Diagram: plate with hold point and tap point marked for longitudinal tap
- [ ] Diagram: plate rotated for cross-grain tap
- [ ] Diagram: plate held at long edge for FLC tap
- [ ] Status bar during longitudinal capture ("Capturing Longitudinal · Phase 1/2")
- [ ] Review state: Accept / Redo buttons visible with frozen spectrum
- [ ] Results panel showing E_L, E_C, specific modulus, quality rating, Gore thickness
- [ ] Comparison of two plate spectra (same blank, different orientations)

---

## Chapter 5 — Brace Mode

**Purpose:** Fast single-tap measurement for brace strips.

### 5.1 Overview
- Brace mode vs. Plate mode: what is skipped and why
- Suitable sample shapes

### 5.2 Setting Up Brace Dimensions
- Settings → Brace Dimensions
- Height: dimension in the tap direction (brace standing upright)
- Length: along the grain
- Understanding which dimension is t in the stiffness formula

### 5.3 Technique
- Single-point hold at 22% from one end
- Tap the top face at centre
- No rotation needed
- Accept / Redo review flow applies (same as Plate mode §4.5): spectrum freezes after the tap, user reviews and Accept or Redo

### 5.4 Reading Brace Results
- E_L, c_L, specific modulus
- Spruce quality rating
- No cross-grain or Gore calculation available

### 5.5 Using Brace Mode to Compare Stock
- Practical workflow: batch-testing brace strips
- Recording results in notes for future reference

**Screenshots required:**
- [ ] Settings — Brace Dimensions entry
- [ ] Diagram: brace strip with hold point and tap point
- [ ] Results panel showing brace mode output

---

## Chapter 6 — Working with the Spectrum

**Purpose:** Navigate, zoom, annotate, and read the spectrum chart.

### 6.1 Live vs. Frozen Spectrum
- Real-time update before a tap
- Freeze on tap detection
- Returning to live with New Tap

### 6.2 Zooming and Panning — iOS/iPadOS
- Pinch to zoom both axes
- Pinch on a single axis to zoom that axis only
- Drag to pan
- Resetting: … button → Reset to Saved / Reset to Defaults

### 6.3 Zooming and Panning — macOS
- Scroll wheel over plot area: zoom both axes
- Scroll wheel over frequency axis (bottom): zoom frequency only
- Scroll wheel over magnitude axis (left): zoom magnitude only
- Drag to pan (same axis sensitivity)
- Modifier keys: ⇧ Scroll pan freq; ⌥ Scroll pan mag; ⌘/⌃ Scroll zoom both
- Pinch on trackpad: zoom both or individual axes
- Right-click chart area to reset axes and labels

### 6.4 Auto dB
- What it does: scales magnitude axis to fit current signal
- When to use it: after each measurement
- Keyboard shortcut: ⌘0 (macOS)

### 6.5 The Crosshair (iOS/iPadOS)
- Enabling the crosshair from the toolbar
- Dragging to read frequency and magnitude at any point
- Disabling the crosshair

### 6.6 Peak Labels
- What each label shows: mode name, frequency, pitch
- Dragging a label to reposition it
- Resetting an individual label: double-tap (iOS) / right-click → Reset Position (macOS)
- Resetting all labels: … menu → Reset Labels (iOS) / right-click chart area → Reset Labels (macOS)

### 6.7 Annotation Modes
- All: every detected peak labelled
- Selected: only the peaks chosen for analysis
- None: no labels
- Cycling via the Annotations button or ⌘` (macOS)

### 6.8 Saving the Current View as Default
- Settings → Advanced → Display Settings → Save Current View
- What is saved: frequency range and magnitude range

**Screenshots required:**
- [ ] Live spectrum (before tap)
- [ ] Frozen spectrum (after tap)
- [ ] Pinch-to-zoom gesture on iOS
- [ ] macOS scroll-zone diagram (plot area / freq axis / mag axis highlighted)
- [ ] Crosshair active on spectrum (iOS)
- [ ] Peak label being dragged
- [ ] Right-click context menu on a label (macOS)
- [ ] Annotation mode: All vs Selected vs None (three images)
- [ ] … menu on iOS showing Reset options

---

## Chapter 7 — Saving, Exporting, and Sharing Measurements

**Purpose:** Complete reference for all the ways measurements leave the app.

### 7.1 Saving a Measurement
- When Save is enabled (spectrum frozen, peaks detected)
- The Save sheet: entering a location label and optional notes
- What is stored: peaks, spectrum snapshot, chart image, settings at time of capture
- Keyboard shortcut: ⌘S (macOS)

### 7.2 Viewing Saved Measurements
- Opening the Measurements list
- List layout: location, date, measurement type
- Searching and sorting (if available)

### 7.3 Loading a Measurement into the View
- Right-click / long-press a row → Load into View
- What is restored: spectrum, peaks, settings

### 7.4 Viewing Measurement Details
- Right-click / long-press → View Details
- Detail view contents: peak table, spectrum image, analysis summary, export buttons

### 7.5 Editing Location and Notes
- Right-click / long-press → Edit Location & Notes
- Also accessible from the Edit button in the Measurement Details toolbar

### 7.6 Exporting a Spectrum Image
- What is produced: PNG of the current chart
- From toolbar: Export Spectrum Image… (⌘E on macOS)
- From Measurements list: right-click / long-press → Export Spectrum
- During comparison: image includes all overlaid curves and legend; each curve colour matches the Comparison Results table

### 7.7 Exporting a PDF Report
- What the PDF contains: spectrum chart, peak table, analysis summary, quality indicators
- From toolbar: Export PDF Report… (⇧⌘E on macOS)
- From Measurements list: right-click / long-press → Export PDF Report
- Single-measurement PDF vs. Comparison PDF (see §7.12)

### 7.8 Saving a Comparison
- The Save button is available during an active comparison (it is replaced by a disabled state only for new individual measurements — the comparison itself can be saved)
- The Save sheet accepts an optional location label and notes, as with single measurements
- The saved comparison record appears in the Measurements list alongside regular measurements
- Reloading a comparison record restores the full overlay (all spectra, colours, and legend) exactly as when it was saved
- Comparison records are identified by a distinct icon/badge in the Measurements list

### 7.9 Exporting a Comparison Spectrum Image
- From the toolbar while a live comparison is active: Export Spectrum produces the overlay PNG
- From the Measurements list: select a saved comparison record → Export Spectrum
- The PNG includes all coloured curves, their labels, and a legend

### 7.10 Exporting a Comparison PDF Report
- From the toolbar while a live comparison is active: Export PDF Report → comparison PDF
- From the Measurements list: select a saved comparison record → Export PDF Report → comparison PDF
- Comparison PDF contents: metadata header (number of spectra, labels, date), overlay spectrum image, Air / Top / Back frequency table (one column per spectrum)

### 7.11 Exporting a .guitartap File
- What .guitartap contains (full measurement data, JSON-based; for comparisons, all constituent spectra embedded)
- iOS/iPadOS: right-click / long-press → Export Measurement → share sheet (AirDrop, Mail, Files, etc.)
- macOS: right-click → Save Measurement to Disk… → save dialog

### 7.12 Importing a Measurement or Comparison
- Supported formats: .guitartap and .json
- iOS/iPadOS: Import Measurement button → Files picker
- macOS: Import Measurement → open dialog or drag-and-drop
- What happens after import: measurement (or comparison record) appears in list
- Comparison records are automatically detected and will reload the overlay when opened

### 7.13 Sharing Between iOS and macOS
- AirDrop workflow: send from iOS share sheet, open on Mac
- iCloud/Files workflow
- Email workflow
- Round-trip: export from Mac, import on iOS
- Comparison files: cross-platform compatible

### 7.14 Deleting Measurements
- Right-click / long-press → Delete
- Confirmation prompt
- Deleting a comparison record removes all constituent data

**Screenshots required:**
- [ ] Save sheet — single measurement (iOS and macOS)
- [ ] Save sheet — comparison (showing overlay is being saved)
- [ ] Measurements list showing comparison record with distinctive badge (iOS and macOS)
- [ ] Long-press context menu (iOS) — single measurement
- [ ] Long-press context menu (iOS) — comparison record
- [ ] Right-click context menu (macOS)
- [ ] Measurement Detail view
- [ ] Edit Location & Notes sheet
- [ ] Share sheet on iOS (AirDrop highlighted)
- [ ] Save dialog on macOS (Save Measurement to Disk)
- [ ] Single-measurement PDF report (one page)
- [ ] Comparison PDF report (one page showing spectrum overlay and frequency table)
- [ ] Exported single-spectrum PNG example
- [ ] Exported comparison overlay PNG example

---

## Chapter 8 — Settings Reference

**Purpose:** Complete description of every setting.

### 8.1 Opening Settings
- iOS/iPadOS: Settings button in toolbar
- macOS: Settings… in the GuitarTap application menu (⌘,)

### 8.2 Audio Input & Calibration
- Device selector
- Calibration file import
- Per-device calibration association
- Effect of calibration on spectrum

### 8.3 Measurement Type
- Classical Guitar / Flamenco / Acoustic Steel String
  - Frequency windows for each mode
- Material (Plate)
  - Sample dimensions: Length, Width, Thickness, Mass
  - Body dimensions: Body Length, Lower Bout Width
  - Plate stiffness preset selector
  - Measure FLC toggle
- Material (Brace)
  - Brace dimensions: Length, Height

### 8.4 Advanced — Display Settings
- Display Frequency Range: min and max Hz
- Display Magnitude Range: min and max dB
- Save Current View button

### 8.5 Advanced — Analysis Settings
- Analysis Frequency Range: min and max Hz for peak detection
- Peak Min (dB): minimum magnitude to annotate
- Hysteresis Margin (dB): re-arm distance below threshold
- Maximum Peaks: cap or All
- Show Unknown Modes (guitar mode only)

### 8.6 Advanced — FFT Processing
- Hop-size overlap: effect on smoothness vs. frame rate
- Note: takes effect on next analyzer start

**Screenshots required:**
- [ ] Full Settings sheet — top section (Audio Input)
- [ ] Settings — Measurement Type: guitar type selector
- [ ] Settings — Measurement Type: Material (Plate) fields
- [ ] Settings — Measurement Type: Material (Brace) fields
- [ ] Settings — Advanced section collapsed
- [ ] Settings — Advanced section expanded (Display, Analysis, FFT subsections)

---

## Chapter 9 — Controls Reference

**Purpose:** Exhaustive reference for every button, control, and gesture.

### 9.1 Toolbar — iOS iPhone (Portrait)
- Leading: Results, Auto dB
- Trailing: Metrics, Settings
- Tap controls below toolbar: Taps stepper, Threshold slider, Peak Min slider

### 9.2 Toolbar — iOS iPhone (Landscape)
- Leading: Results, Auto dB, Crosshair, Annotations
- Trailing: Save, Measurements, Metrics, Settings, Help (?)

### 9.3 Toolbar — iOS iPad (Portrait and Landscape)
- Leading: Results, Auto dB, Crosshair, Annotations
- Trailing: Save, Measurements, Metrics, Settings, Help (?)

### 9.4 Menu Bar — macOS, Windows, and Linux (Python desktop app)
- Note: Windows and Linux use the same Python desktop app with an equivalent menu bar structure; differences from macOS are called out per item

### 9.4a Menu Bar — macOS
- GuitarTap menu: Settings… (⌘,)
- File menu: Save Measurement… (⌘S), Export Spectrum Image… (⌘E), Export PDF Report… (⇧⌘E)
- View menu: Auto dB (⌘0), Cycle Annotations (⌘`), Show Metrics (⌘M), Show Measurements (⌘L)
- Help menu: Search field, GuitarTap Help item

### 9.4b Menu Bar — Windows and Linux (Python desktop app)
- File menu: equivalent save and export actions; keyboard shortcuts may differ
- Help menu: Guitar Tap Help item (opens in-app help dialog)
- Differences from macOS: no dedicated application menu; Settings accessed via File menu

### 9.5 Individual Controls
Each control: icon, name, what it does, availability notes, keyboard shortcut (macOS)

- New Tap
- Pause / Resume / **Accept** (replaces Pause during plate/brace review phase; green tint; advances to next phase)
- Cancel / **Redo** (replaces Cancel during plate/brace review phase; labelled "Redo L", "Redo C", or "Redo FLC"; discards phase and returns to capture)
- Results
- Auto dB
- Annotations
- Save (also used to save comparisons when comparison mode is active)
- Measurements
- Metrics
- Crosshair (iOS/iPadOS only)
- … Chart Options (iOS/iPadOS only)
- ⓘ Zoom & Pan Help (macOS only)
- Settings
- Help (?)

### 9.6 Tap Controls
- Taps stepper (1–10)
- Threshold slider (dB) + reset arrow
- Peak Min slider (dB) + reset arrow

### 9.7 Spectrum Chart Interactions
- (Cross-reference to Chapter 6)

**Screenshots required:**
- [ ] iPhone portrait toolbar annotated
- [ ] iPhone landscape toolbar annotated
- [ ] iPad toolbar annotated
- [ ] macOS toolbar annotated
- [ ] Windows/Linux desktop toolbar annotated
- [ ] macOS menu bar: File menu open
- [ ] macOS menu bar: View menu open
- [ ] Windows/Linux menu bar: File menu open
- [ ] Tap controls panel (iOS)
- [ ] Tap controls panel (desktop)
- [ ] Metrics panel (FFT statistics)

---

## Chapter 10 — Tips, Technique, and Troubleshooting

**Purpose:** Practical advice and solutions to common problems.

### 10.1 Tap Technique
- Recommended: small bouncy ball on the end of a stick — short contact time, clean impulse, very repeatable; suitable for all three modes
- Alternative: short crisp knuckle or fingertip rap — works well for guitar body surveys
- Avoiding slow pressing contact: why it excites fewer overtones and muddies the spectrum
- Where to tap: guitar body (top, back, sides) vs. plate centre vs. brace centre face

### 10.2 Consistent Microphone Position
- Why position affects magnitude but not frequency
- Marking a position for reproducible comparisons

### 10.3 Dealing with Background Noise
- Threshold slider: moving left (lower) to catch quiet taps; right (higher) to reject noise
- Hysteresis margin: preventing double-detection
- Practical noise floor targets

### 10.4 Air Mode Technique
- Clapping palm over sound hole (Helmholtz excitation)
- No wood tapping required

### 10.5 Ring-Out and Decay Time
- What decay time measures: structural damping
- Comparing braced vs. unbraced sections
- Typical values for quality soundboards

### 10.6 Multi-Tap Averaging Strategy
- Recommended tap counts for different scenarios
- When averaging helps least (very quiet room, single firm tap)

### 10.7 Common Problems
| Problem | Likely cause | Fix |
|---------|-------------|-----|
| No tap detected | Threshold too high | Lower threshold slider |
| False detections | Threshold too low or noisy room | Raise threshold; use Pause between taps |
| Peaks missing | Peak Min too high | Lower Peak Min slider |
| Unknown peaks everywhere | Analysis range too wide | Narrow analysis range in Advanced |
| Spectrum doesn't update | Microphone permission not granted | Check System Settings (macOS) or iOS Settings |
| Plate calculation missing | Dimensions not entered | Open Settings → Material |
| Gore thickness not shown | FLC not captured or not enabled | Enable Measure FLC in Settings |
| Results panel not visible | macOS: window too narrow | Widen the window |
| Plate/brace: stuck on one phase | Missed the Accept button | Look for Accept (green) in tap controls; it replaces Pause in review state |
| Plate/brace: want to redo a tap | Phase already accepted | Tap New Tap to restart the whole sequence; individual phase redo is only available before accepting |
| Compare button not appearing | Fewer than 2 or more than 5 measurements selected, or a plate/brace record is selected | Select 2–5 guitar measurements only |
| Comparison shows 0 spectra in PDF | Known fixed issue in earlier versions | Update the app; comparison PDFs now show correct spectra count |
| Comparison colours all the same | Exported image from an older version | Update and re-export; each spectrum now renders in its distinct colour |

**Screenshots required:**
- [ ] Photo: bouncy ball on stick in use — tapping a plate
- [ ] Photo: knuckle tap on guitar top for comparison
- [ ] Threshold slider at low vs. high position
- [ ] Decay time shown in Results panel
- [ ] Noisy spectrum vs. clean spectrum (same guitar, different environments)

---

## Chapter 11 — Glossary

Alphabetical definitions of all technical terms used in the app and manual.

- Air (Helmholtz) mode
- Bandwidth (−3 dB)
- Cross/Long ratio
- Decay time
- Dipole mode
- E_C (Young's modulus, cross-grain)
- E_L (Young's modulus, longitudinal)
- FFT (Fast Fourier Transform)
- FLC tap
- Free-free beam
- Gore target thickness
- Q factor
- Radiation ratio (R)
- Ring mode
- Specific modulus (E/ρ)
- Speed of sound (c)
- Tap Tone Ratio
- Top / Back mode
- Unknown mode
- Upper modes

---

## Appendix A — Keyboard Shortcuts (macOS)

| Shortcut | Action |
|----------|--------|
| ⌘, | Settings |
| ⌘S | Save Measurement… |
| ⌘E | Export Spectrum Image… |
| ⇧⌘E | Export PDF Report… |
| ⌘0 | Auto dB |
| ⌘` | Cycle Annotations |
| ⌘M | Show Metrics |
| ⌘L | Show Measurements |

---

## Appendix B — File Formats

### .guitartap
- JSON-based container
- Contains: all peaks, spectrum snapshot (Base64 little-endian float32), annotation offsets, mode overrides, settings at capture time
- Compatible between iOS and macOS versions

### Calibration files (.txt / .cal)
- Frequency response compensation data
- Format: two-column text (frequency Hz, magnitude dB)

---

## Screenshot Checklist Summary

Total screenshots required: approximately 90–100 (including photos)

| Chapter | Count |
|---------|-------|
| 1 — Introduction | 4 |
| 2 — Getting Started | 14 |
| 3 — Guitar Mode | 14 |
| 4 — Plate Mode | 9 |
| 5 — Brace Mode | 3 |
| 6 — Spectrum | 9 |
| 7 — Save/Export/Share | 14 |
| 8 — Settings Reference | 6 |
| 9 — Controls Reference | 11 |
| 10 — Tips & Troubleshooting | 5 |

Screenshots should be captured at:
- **macOS:** 1440×900 or similar, with window at standard size
- **Windows:** 1920×1080, Python desktop app at standard size
- **Linux:** 1920×1080, Python desktop app at standard size
- **iPad:** 12.9-inch Pro, landscape and portrait as needed
- **iPhone:** iPhone 15 Pro, portrait and landscape

All app screenshots should be saved as PNG at 2× (Retina) resolution where available.
Photos (tapping technique) should be clear, well-lit, shot against a neutral background.

---

## Generation Notes

- One Markdown file per chapter: `ch01-introduction.md`, `ch02-getting-started.md`, etc.
- Images referenced as `images/ch01-main-screen-comparison.png` etc.
- `generate-manual.sh` will concatenate chapters and run WeasyPrint
- CSS stylesheet: `manual.css` (to be created)
- Platform-conditional content (iOS vs. macOS) handled in Markdown with HTML `<div class="ios-only">` / `<div class="macos-only">` blocks and CSS `@media print` rules, or separate sidebar callout boxes

### Navigation and Table of Contents

#### PDF
- WeasyPrint 68 natively supports three CSS bookmark properties (confirmed in source):
  - `bookmark-level: 1` on `h1`, `bookmark-level: 2` on `h2`, `bookmark-level: 3` on `h3` — generates the full PDF outline/bookmark tree visible in Acrobat's Bookmarks panel, Preview's sidebar, and equivalent panels in other PDF readers
  - `bookmark-label` — controls the text shown in the bookmark panel (defaults to element text content)
  - `bookmark-state: open | closed` — controls whether a bookmark node is expanded by default
- Each heading also gets an `id` attribute; TOC entries are HTML anchor links (`<a href="#section-id">`) — WeasyPrint renders these as clickable internal links in the PDF
- A dedicated TOC page will be inserted as the first content (generated by the build script from heading metadata)
- Page numbers in the TOC are populated by CSS `content: target-counter(attr(href), page)` — standard WeasyPrint-supported CSS
- Result: the PDF will have both a visible TOC page with page numbers and a full navigable bookmark tree in the reader's sidebar

#### HTML
- A persistent left-side navigation panel (`<nav>`) listing all chapters and sections, generated from the heading structure at build time
- The nav panel uses CSS `position: sticky` so it stays visible while scrolling
- Active section highlighted via CSS `:target` pseudo-class (no JavaScript required for basic highlighting; JavaScript `IntersectionObserver` optional for scroll-based highlight)
- Each `<h2>` and `<h3>` heading gets a stable `id` derived from its text (slugified) so links are shareable
- "Back to top" link at the end of each chapter section

#### Implementation approach
- The `generate-manual.sh` script will run a Python pre-pass over the concatenated Markdown to:
  1. Extract all `##` and `###` headings and their slugified ids
  2. Emit a `ch00-toc.html` fragment for the PDF TOC page (with `target-counter` spans for page numbers)
  3. Emit a `nav.html` fragment for the HTML sidebar
- Both fragments are injected by the WeasyPrint/HTML build steps respectively
- The same `manual.css` serves both outputs; a separate `manual-print.css` (loaded via `@media print`) adjusts the nav panel for PDF (hidden or replaced by the TOC page)
