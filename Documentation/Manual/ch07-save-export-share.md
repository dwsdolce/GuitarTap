# Chapter 7 — Saving, Exporting, and Sharing Measurements

<!-- STATUS: STUB — needs full content -->

## 7.1 Saving a Measurement

<!-- TODO: Write section -->
<!-- Cover:
     - When Save is enabled: spectrum must be frozen and at least one peak detected;
       Save is disabled when comparison mode is active for a new individual measurement
       (use §7.8 to save a comparison)
     - The Save sheet: location label field (optional, e.g. "Bridge", "Soundhole",
       "Upper Bout"); Notes field (optional, free text)
     - What is stored: frozen spectrum data, detected peaks, chart image (PNG sidecar),
       all settings active at time of capture (guitar type, plate dimensions, etc.),
       annotation positions, mode overrides
     - Keyboard shortcut: ⌘S (macOS)
     - After save: measurement appears at top of Measurements list -->

## 7.2 Viewing Saved Measurements

<!-- TODO: Write section -->
<!-- Cover:
     - Opening the Measurements list (toolbar button; ⌘L on macOS)
     - List layout: each row shows location label (or date if no label), date/time,
       measurement type badge (Guitar / Plate / Brace / Comparison)
     - Comparison records are identified by a distinct badge in the list
     - The list is sorted by date, newest first -->

## 7.3 Loading a Measurement into the View

<!-- TODO: Write section -->
<!-- Cover:
     - Right-click / long-press a measurement row → Load into View (or equivalent button)
     - What is restored: frozen spectrum, peaks, annotation positions, mode overrides,
       the settings active at capture time (note: current Settings panel values are not
       changed; loaded values are shown as a warning in the status bar)
     - For a comparison record: all constituent spectra are overlaid; the Comparison
       Results table is restored; comparison mode becomes active -->

## 7.4 Viewing Measurement Details

<!-- TODO: Write section -->
<!-- Cover:
     - Right-click / long-press → View Details (or tap the row on iPad/macOS where a
       detail pane is available)
     - Detail view contents: spectrum image thumbnail, peak frequency table, analysis
       summary (decay time, Tap Tone Ratio for guitar; E_L, E_C etc. for plate/brace)
     - Export buttons available within the detail view
     - For comparison records: shows the constituent spectrum list and the
       Air / Top / Back frequency table -->

## 7.5 Editing Location and Notes

<!-- TODO: Write section -->
<!-- Cover:
     - Right-click / long-press → Edit Location & Notes (or Edit button in Detail toolbar)
     - Edit sheet: Location label field and Notes multi-line text field
     - Changes are saved immediately on tapping Save in the sheet
     - There is no undo for label/notes edits -->

## 7.6 Exporting a Spectrum Image

<!-- TODO: Write section -->
<!-- Cover:
     - What is produced: PNG image of the current chart at display resolution
     - From toolbar: Export Spectrum Image… button (⌘E on macOS)
     - From Measurements list: right-click / long-press a saved record → Export Spectrum
     - For a single measurement: the frozen spectrum with peak annotations
     - For a comparison (live or saved): the overlay PNG with all coloured curves, their
       labels, and a legend; each curve colour matches the Comparison Results table -->

## 7.7 Exporting a PDF Report

<!-- TODO: Write section -->
<!-- Cover:
     SINGLE-MEASUREMENT PDF
     - What the PDF contains: spectrum chart image, peak frequency table
       (mode, frequency, magnitude, Q, bandwidth, pitch), analysis summary
       (decay time, Tap Tone Ratio for guitar; E_L, E_C, specific modulus, quality
       rating, Gore thickness for plate/brace), metadata (date, location, notes)
     - From toolbar: Export PDF Report… button (⇧⌘E on macOS)
     - From Measurements list: right-click / long-press → Export PDF Report

     COMPARISON PDF
     - What the comparison PDF contains: metadata header (number of spectra, labels, date),
       overlay spectrum image showing all curves, Air / Top / Back frequency table with
       one column per spectrum ("—" where a mode was not detected)
     - From toolbar when comparison is active: Export PDF Report → comparison PDF
     - From Measurements list for a saved comparison record: Export PDF Report → comparison PDF
     - See §7.10 for details on the comparison PDF -->

## 7.8 Saving a Comparison

<!-- TODO: Write section -->
<!-- Cover:
     - A comparison can be saved while it is active (initiated via the Measurements list
       Compare button; see §3.9)
     - The Save button is available during comparison (it saves the comparison itself,
       not a new individual measurement)
     - The Save sheet accepts a location label and notes; all constituent spectra are
       embedded in the saved record
     - The saved record appears in the Measurements list with a Comparison badge
     - Reloading a saved comparison (§7.3) restores the full overlay and Comparison
       Results table exactly as at save time
     - Saving a comparison does not consume the individual constituent measurements;
       they remain separately in the list -->

## 7.9 Exporting a Comparison Spectrum Image

<!-- TODO: Write section -->
<!-- Cover:
     - From the toolbar while a live comparison is active: Export Spectrum produces the overlay PNG
     - From the Measurements list: select a saved comparison record → Export Spectrum
     - The PNG includes all coloured curves, their labels, and a legend
     - On iOS the image is passed to the system share sheet (AirDrop, Mail, Files, etc.)
     - On macOS a save dialog appears -->

## 7.10 Exporting a Comparison PDF Report

<!-- TODO: Write section -->
<!-- Cover:
     - From the toolbar while a live comparison is active: Export PDF Report → comparison PDF
     - From the Measurements list: select a saved comparison record → Export PDF Report
     - Comparison PDF contents:
         * Metadata header: number of spectra compared, each label, date exported
         * Overlay spectrum image (same as the exported PNG)
         * Air / Top / Back frequency table: rows = modes, columns = each spectrum;
           frequency shown to 0.1 Hz; "—" where the mode was not detected
     - On iOS: share sheet; on macOS: save dialog -->

## 7.11 Exporting a .guitartap File

<!-- TODO: Write section -->
<!-- Cover:
     - What .guitartap contains: JSON container with all peaks, spectrum snapshot
       (Base64-encoded little-endian float32 arrays), annotation offsets, mode overrides,
       settings at capture time, chart PNG embedded as Base64
     - For comparison records: all constituent spectra are embedded; the file is larger
       but self-contained
     - iOS/iPadOS: right-click / long-press → Export Measurement → system share sheet
       (AirDrop, Mail, Files, etc.)
     - macOS: right-click → Save Measurement to Disk… → save dialog
     - File extension: .guitartap; compatible between iOS and macOS versions of the app -->

## 7.12 Importing a Measurement or Comparison

<!-- TODO: Write section -->
<!-- Cover:
     - Supported formats: .guitartap (native format) and .json (legacy)
     - iOS/iPadOS: Import Measurement button in the Measurements toolbar → Files picker
     - macOS: File menu → Import Measurement → open dialog, or drag-and-drop onto the
       Measurements list
     - What happens after import: the measurement appears in the list; comparison records
       are automatically detected and will restore the overlay when loaded
     - If a microphone name in the imported file does not match any available device on
       the current system: a fallback is applied and the import succeeds -->

## 7.13 Sharing Between iOS and macOS

<!-- TODO: Write section -->
<!-- Cover:
     - AirDrop: iOS share sheet → AirDrop; on Mac: accept in Finder, then open with GuitarTap
       (File → Import Measurement) or drag-and-drop onto the Measurements list
     - iCloud / Files: save to iCloud Drive from iOS share sheet; open from Files on Mac
     - Email: attach via share sheet; recipient opens the attachment in GuitarTap
     - Round-trip: export from Mac with Save Measurement to Disk; transfer to iPhone;
       import via Import Measurement
     - Comparison files are cross-platform compatible (same .guitartap format) -->

## 7.14 Deleting Measurements

<!-- TODO: Write section -->
<!-- Cover:
     - Right-click / long-press → Delete (macOS) or swipe-to-delete on iOS
     - A confirmation prompt prevents accidental deletion
     - Deleting a comparison record removes all embedded constituent data
     - Deleting a measurement that was used in a previously saved comparison does not
       affect the comparison record (it is self-contained) -->
