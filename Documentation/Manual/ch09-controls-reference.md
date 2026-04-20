# Chapter 9 — Controls Reference

<!-- STATUS: STUB — needs full content -->

## 9.1 Toolbar — iOS iPhone (Portrait)

<!-- TODO: Write section -->
<!-- Cover:
     - Leading items (left): Results, Auto dB
     - Trailing items (right): Metrics, Settings
     - Below toolbar (always visible): Taps stepper, Threshold slider + reset,
       Peak Min slider + reset
     - Action buttons row: New Tap, Pause/Resume/Accept, Cancel/Redo
     - Compact labels; no text for toolbar items — icon only
     - Items that are hidden or disabled in comparison mode:
       Threshold slider, Peak Min slider, Taps stepper -->

## 9.2 Toolbar — iOS iPhone (Landscape)

<!-- TODO: Write section -->
<!-- Cover:
     - Leading items: Results, Auto dB, Crosshair, Annotations
     - Trailing items: Save, Measurements, Metrics, Settings, Help (?)
     - Tap controls are condensed; Taps stepper, Threshold, and Peak Min are
       in a row below the spectrum rather than a full panel
     - Landscape layout places the spectrum and controls side by side -->

## 9.3 Toolbar — iOS iPad (Portrait and Landscape)

<!-- TODO: Write section -->
<!-- Cover:
     - Leading items: Results, Auto dB, Crosshair, Annotations
     - Trailing items: Save, Measurements, Metrics, Settings, Help (?)
     - Full tap controls panel visible (same as macOS); not collapsed to compact form
     - iPad shows the Comparison Results table in the Results panel rather than a sheet -->

## 9.4 Menu Bar — macOS, Windows, and Linux

<!-- TODO: Write section -->
<!-- Overview paragraph noting that §9.4a covers macOS and §9.4b covers the Python
     desktop app on Windows and Linux. Point out where the menus differ. -->

### 9.4a Menu Bar — macOS

<!-- TODO: Write section -->
<!-- Cover each menu in order:

     GuitarTap menu:
     - Settings… (⌘,)

     File menu:
     - Save Measurement… (⌘S)
     - Export Spectrum Image… (⌘E)
     - Export PDF Report… (⇧⌘E)
     - Import Measurement…

     View menu:
     - Auto dB (⌘0)
     - Cycle Annotations (⌘`)
     - Show Metrics (⌘M)
     - Show Measurements (⌘L)

     Help menu:
     - Search field
     - GuitarTap Help (opens HelpView sheet) -->

### 9.4b Menu Bar — Windows and Linux (Python desktop app)

<!-- TODO: Write section -->
<!-- Cover:
     - File menu: equivalent save and export actions (Save Measurement, Export Spectrum
       Image, Export PDF Report, Import Measurement); keyboard shortcuts may differ
     - Help menu: Guitar Tap Help item (opens in-app help dialog)
     - Differences from macOS: no dedicated application menu; Settings accessed via
       File menu or equivalent; macOS ⌘ shortcuts use Ctrl on Windows/Linux -->

## 9.5 Individual Controls

<!-- TODO: Write section -->
<!-- For each control provide: icon description, name, what it does,
     when it is enabled/disabled, any keyboard shortcut (macOS).

     NEW TAP
     - Icon: hand.tap
     - Resets/arms the tap detector; clears the frozen spectrum and returns to live view
     - Also exits comparison mode when comparison is active
     - Always enabled

     PAUSE / RESUME / ACCEPT
     - Icon changes based on state:
         * Pause (pause.circle): suspends tap detection; spectrum stays live; allows
           Threshold and Peak Min adjustment without risking accidental detection;
           also available during guitar multi-tap sequences between taps
         * Resume (play.circle): re-arms detection after Pause
         * Accept (checkmark.circle, green tint): appears only during plate/brace review
           phases; locks in the current phase result and advances to the next phase
     - Disabled during comparison mode and when no measurement is in progress

     CANCEL / REDO
     - Icon changes based on state:
         * Cancel (xmark.circle, orange): cancels the current tap sequence in progress;
           spectrum returns to live; available during guitar and plate/brace sequences
         * Redo L / Redo C / Redo FLC (arrow.counterclockwise, orange): appears only
           during the corresponding plate/brace review phase; discards the current phase
           result and returns to capture for that phase
     - Disabled when there is no active sequence

     RESULTS
     - Opens/closes the Analysis Results panel
     - On iPhone: Results opens as a sheet
     - On iPad and macOS: Results is a persistent side panel

     AUTO DB
     - Scales the magnitude (dB) axis to fit the currently visible spectrum
     - Keyboard shortcut: ⌘0 (macOS)

     ANNOTATIONS
     - Cycles through annotation display modes: All → Selected → None → All…
     - Keyboard shortcut: ⌘` (macOS)
     - Disabled during comparison mode

     SAVE
     - Opens the Save Measurement sheet when a spectrum is frozen and peaks detected
     - During comparison: saves the full comparison as a single record
     - Keyboard shortcut: ⌘S (macOS)
     - Disabled when spectrum is live (no frozen measurement) or no peaks detected

     MEASUREMENTS
     - Opens/closes the Measurements list
     - Keyboard shortcut: ⌘L (macOS)

     METRICS
     - Opens/closes the FFT Diagnostics panel (frame rate, FFT size, input level etc.)
     - Keyboard shortcut: ⌘M (macOS)

     CROSSHAIR (iOS/iPadOS only)
     - Toggles the crosshair overlay on the spectrum
     - Drag the crosshair to read frequency and magnitude at any point
     - Not available on macOS (use the mouse hover readout instead)

     … CHART OPTIONS (iOS/iPadOS only)
     - Opens a menu with: Reset Labels, Reset to Saved View, Reset to Defaults
     - macOS equivalent: right-click on the chart area

     ⓘ ZOOM & PAN HELP (macOS only)
     - Displays a brief summary of scroll-wheel and trackpad zoom/pan gestures

     SETTINGS
     - Opens the Settings sheet
     - Keyboard shortcut: ⌘, (macOS)

     HELP (?)
     - Opens the in-app Help sheet (HelpView)
     - Lists all controls, tips, and gesture references in a searchable list -->

## 9.6 Tap Controls

<!-- TODO: Write section -->
<!-- Cover:

     TAPS STEPPER
     - Range: 1–10
     - Sets the number of taps to average for each phase
     - For plate/brace: applies per phase (e.g. 3 Taps means 3 taps for Longitudinal,
       3 for Cross-grain, 3 for FLC)
     - Disabled during an active sequence and during comparison mode

     THRESHOLD SLIDER
     - Range: −80 dB to −20 dB
     - Sets the signal level that triggers tap detection
     - Value displayed in dB next to the slider
     - Reset arrow (↺): resets to the factory default
     - Disabled during comparison mode
     - Tip: use Pause to adjust while tapping freely and watching the live spectrum

     PEAK MIN SLIDER
     - Range: −100 dB to −20 dB
     - Sets the minimum magnitude a spectral peak must reach to be annotated
       and included in guitar mode analysis
     - In plate/brace modes: affects chart display only; does not change which peak
       is selected for the calculation (determined by the capture algorithm)
     - Value displayed in dB next to the slider
     - Reset arrow (↺): resets to the factory default
     - Disabled during comparison mode and during plate/brace measurements -->

## 9.7 Spectrum Chart Interactions

See Chapter 6 for a complete reference to spectrum chart gestures and interactions.
