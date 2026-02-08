# Export Features Implementation Summary

## Overview
This document describes the export functionality implemented in the GuitarTap app for saving measurements and chart images.

## Features Implemented

### 1. JSON File Export

#### From Measurements List
- **"Export All" Button** (macOS toolbar / iOS menu)
  - Exports all saved measurements as a single JSON file
  - Opens native save dialog (macOS: NSSavePanel, iOS: UIDocumentPickerViewController)
  - Filename format: `guitar-measurements-{timestamp}.json`

- **Individual Measurement Export** (Context menu on each measurement)
  - Exports a single measurement as JSON
  - Same save dialog as "Export All"
  
#### From Measurement Detail View
- **Export JSON Button** (macOS toolbar / iOS menu)
  - Exports the currently viewed measurement
  - Filename format: `{location}-{timestamp}.json` (e.g., "bridge-1707123456.json")

### 2. Chart Image Export

#### From Measurement Detail View
- **Export Chart Image Button** (macOS toolbar / iOS menu)
  - Renders the peak frequency chart as a high-quality image
  - iOS: Opens share sheet (save to Photos, Files, AirDrop, etc.)
  - macOS: Opens save dialog to save PNG file
  - Filename format: `{location}-{timestamp}.png`

#### Chart Export Features
- High-resolution export (uses device's native scale factor)
- Includes:
  - Title: "Guitar Tap Tone Analysis"
  - Location name (if provided)
  - Timestamp
  - Tap tone ratio (if calculable)
  - All detected peaks with frequency, magnitude, and mode classification
  - Color-coded mode markers
  - Legend showing all guitar modes
- Export size: 1200x700 pixels (before scaling)

## Implementation Details

### File Locations

#### iOS
- **JSON Export**: Uses `UIDocumentPickerViewController` to let users choose save location
  - Can save to iCloud Drive, Files app, or any file provider
  - File is created in temporary directory first, then moved to user's chosen location

- **Image Export**: Uses `UIActivityViewController` for sharing
  - Users can save to Photos, Files, or share via Messages, Mail, AirDrop, etc.

#### macOS
- **JSON Export**: Uses `NSSavePanel` to let users choose save location
  - Default location: Documents folder (or last used location)
  - Users can navigate to any folder and create new directories

- **Image Export**: Uses `NSSavePanel` with PNG content type
  - Saves as PNG file to user-selected location

### JSON Structure
Exported JSON includes:
```json
{
  "id": "UUID",
  "timestamp": "2026-02-08T12:34:56Z",
  "peaks": [
    {
      "id": "UUID",
      "frequency": 105.5,
      "magnitude": -42.3,
      "quality": 12.5,
      "bandwidth": 8.4
    }
  ],
  "decayTime": 1.85,
  "tapLocation": "Bridge",
  "notes": "User notes here",
  "spectrumSnapshot": [...]  // Array of magnitude values (if captured)
}
```

### Chart Visualization
The exported chart uses Swift Charts with:
- `PointMark` for peaks (color-coded by guitar mode)
- `RuleMark` for vertical reference lines
- Annotations showing frequency, mode name, and magnitude
- Color scheme:
  - Helmholtz: Cyan
  - Cross-Grain: Blue  
  - Long-Grain: Green
  - Monopole: Orange
  - Dipole: Red
  - Ring Mode: Purple
  - Upper Modes: Gray

## User Interface

### Measurements List
```
┌─────────────────────────────────┐
│ Saved Measurements         Done │
├─────────────────────────────────┤
│                                 │
│  ┌─────────────────────────┐   │
│  │ Bridge          10:30 AM │   │  ← Tap to view details
│  │ 5 peaks • Ratio: 2.05   │   │  → Right-click for menu:
│  │ Decay: 1.85s            │   │     • View Details
│  └─────────────────────────┘   │     • Export as JSON
│                                 │     • Delete
│  ...more measurements...        │
│                                 │
└─────────────────────────────────┘
 [Export All] [Delete All] (toolbar)
```

### Measurement Detail View
```
┌──────────────────────────────────┐
│ Measurement Details    Done [···]│  ← Menu: Export JSON
├──────────────────────────────────┤           Export Chart Image
│                                  │
│  ┌─ Measurement Info ──────────┐│
│  │ Location: Bridge            ││
│  │ Date: Feb 8, 2026 10:30 AM  ││
│  │ Ring-Out: 1.85 seconds      ││
│  │ Tap Tone Ratio: 2.05 : 1    ││
│  └─────────────────────────────┘│
│                                  │
│  ┌─ Detected Peaks (5) ────────┐│
│  │ 🔵 Cross-Grain              ││
│  │    105.2 Hz    -42.3 dB     ││
│  │                              ││
│  │ 🟢 Long-Grain               ││
│  │    195.8 Hz    -45.1 dB     ││
│  │ ...                          ││
│  └─────────────────────────────┘│
│                                  │
│  ┌─ Peak Frequency Chart ──────┐│
│  │     Chart visualization      ││
│  │                              ││
│  └─────────────────────────────┘│
└──────────────────────────────────┘
```

## Code Files Modified

1. **TapToneAnalysisView.swift**
   - `MeasurementsListView`: Added `exportMeasurements()` and `saveJSONToFile()`
   - `MeasurementDetailView`: Added export buttons and chart rendering
   - `ExportView`: Enhanced with actual file save capabilities

## Usage Instructions

### Exporting All Measurements
1. Click "Measurements" button in main view
2. Click "Export All" button (macOS) or menu (iOS)
3. Choose a location and filename
4. Click "Save"

### Exporting Single Measurement (from list)
1. Right-click (macOS) or long-press (iOS) a measurement
2. Select "Export as JSON"
3. Choose a location and filename
4. Click "Save"

### Exporting from Detail View
1. Click a measurement to open details
2. Click the export button/menu
3. Choose "Export JSON" or "Export Chart Image"
4. Save to desired location

## Future Enhancements

Potential improvements:
- Export multiple selected measurements
- Export as CSV for spreadsheet analysis
- Export charts with full spectrum data (not just peaks)
- Batch export with auto-naming
- Export to cloud services (iCloud, Dropbox, etc.)
- Print support for charts
- PDF export with full analysis report

## Testing Checklist

- [ ] Export all measurements (iOS & macOS)
- [ ] Export single measurement from context menu
- [ ] Export JSON from detail view
- [ ] Export chart image (iOS share sheet)
- [ ] Export chart image (macOS save panel)
- [ ] Verify JSON is valid and contains all data
- [ ] Verify chart image quality and content
- [ ] Test with measurements that have/don't have location names
- [ ] Test with measurements that have/don't have notes
- [ ] Test file naming with special characters in location names

## Known Issues

- `spectrumSnapshot` data may be empty if spectrum capture was disabled
- Chart export only shows peaks, not full spectrum curve
- No progress indicator for large exports
- No error alerts if save fails

## Dependencies

- **SwiftUI**: UI and layout
- **Charts**: Chart rendering for export
- **ImageRenderer**: Convert views to images
- **UIKit/AppKit**: File pickers and save panels
- **Foundation**: JSON encoding, file management
