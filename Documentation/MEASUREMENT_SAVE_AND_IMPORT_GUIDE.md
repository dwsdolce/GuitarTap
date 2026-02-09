# Measurement Save & Import System - Complete Guide

## Overview

The GuitarTap app now includes a comprehensive measurement management system that:
1. **Automatically saves chart images** with every measurement
2. **Stores complete spectrum data** for recreating plots
3. **Saves annotation positions** to preserve your customizations
4. **Imports measurements** from JSON files to recreate the exact analysis
5. **Exports measurements** with all associated data

## What Gets Saved

When you click the "Save" button after taking measurements, the app now captures and stores:

### 1. Peak Data
- All detected peaks with frequencies, magnitudes, Q factors, and bandwidths
- Guitar mode classifications
- Timestamps for each peak

### 2. Chart Image (PNG)
- High-resolution image (1400×800 pixels, scaled for retina)
- Shows the complete frequency response curve
- Includes all detected peaks with annotations
- Color-coded by guitar mode
- Ready to share or use in reports

### 3. Complete Spectrum Snapshot
- Full frequency array
- Full magnitude array
- Current zoom settings (min/max frequency, min/max dB)
- Scale type (logarithmic or linear)

### 4. Annotation Positions
- Custom label positions you've dragged
- Prevents label overlap when recreating

### 5. Metadata
- Tap location (e.g., "Bridge", "Soundhole")
- Your notes and observations
- Decay time measurement
- Calculated tap tone ratio
- Timestamp

## How to Use

### Saving a Measurement

1. **Start the analyzer** and tap the guitar
2. **Use "New Tap"** to collect measurements
3. **Adjust zoom/pan** to show the frequency range you want
4. **(Optional) Drag peak labels** to avoid overlaps
5. **Click "Save"** button
6. **Fill in details:**
   - Tap Location (optional but recommended)
   - Notes (optional observations)
7. **Click "Save"** in the sheet
8. **Wait for progress indicator** - the app is rendering the chart image

The measurement is now saved with:
- ✅ All peak data
- ✅ Chart image
- ✅ Complete spectrum
- ✅ Your custom annotations
- ✅ Current zoom settings

### Viewing Saved Measurements

1. Click **"Measurements"** button
2. See all saved measurements in the list
3. Each row shows:
   - Location name (if provided)
   - Time saved
   - Number of peaks
   - Tap tone ratio (if calculated)
   - Decay time (if measured)
   - **📷 Photo icon** = Has chart image attached
   - **〰️ Waveform icon** = Has spectrum data attached

### Loading a Measurement (Recreate the Plot)

To recreate a saved measurement in the main view:

1. Open **"Measurements"**
2. **Tap/click a measurement** to open details
3. Click the **"Load"** button (download icon) in toolbar
4. **Confirm** you want to load it
5. The main view updates with:
   - The saved spectrum (frozen view)
   - All detected peaks
   - Custom annotation positions restored
   - Zoom settings restored

**This is perfect for:**
- Comparing "before" and "after" measurements
- Revisiting past measurements
- Sharing measurement state with colleagues
- Creating presentations from historical data

### Exporting Measurements

#### Export Individual Measurement

**From List:**
1. Right-click (macOS) or long-press (iOS) on a measurement
2. Select "Export as JSON"
3. Choose save location

**From Detail View:**
1. Open measurement details
2. Click export menu → "Export JSON"
3. Choose save location

**File includes:** All data (peaks, spectrum, image as base64, annotations, etc.)

#### Export All Measurements

1. Open **"Measurements"**
2. Click **"Export All"** (macOS toolbar) or menu → "Export All as JSON" (iOS)
3. Choose save location

**File includes:** Array of all measurements with complete data

#### Export Saved Chart Image

If a measurement has a chart image attached:

1. Open measurement details
2. Click **"Saved Image"** button (photo icon)
3. **iOS:** Share sheet appears (save to Photos, AirDrop, etc.)
4. **macOS:** Save panel appears

**Image is:** The exact chart from when you saved the measurement

### Importing Measurements

To import measurements from JSON files:

1. Open **"Measurements"**
2. Click **"Import"** button
3. **iOS:** Document picker opens - select a JSON file
4. **macOS:** File browser opens - select a JSON file
5. **Success:** Alert shows how many measurements were imported
6. **Imported measurements appear** in the list

**What gets restored:**
- ✅ All peaks with complete data
- ✅ Chart images (if they were in the export)
- ✅ Spectrum snapshots
- ✅ Annotation positions
- ✅ All metadata (location, notes, ratios, etc.)

**After importing, you can:**
- View measurement details
- Load measurements to recreate plots
- Re-export measurements
- Share chart images

## JSON File Format

The exported JSON contains complete measurement data:

```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "timestamp": "2026-02-08T10:30:00Z",
    "tapLocation": "Bridge",
    "notes": "First measurement after soundhole adjustment",
    "decayTime": 1.85,
    "peaks": [
      {
        "id": "660e8400-e29b-41d4-a716-446655440001",
        "frequency": 105.2,
        "magnitude": -42.3,
        "quality": 12.5,
        "bandwidth": 8.4,
        "timestamp": "2026-02-08T10:30:00Z"
      }
    ],
    "spectrumSnapshot": {
      "frequencies": [20.0, 20.67, 21.35, ...],
      "magnitudes": [-98.2, -95.1, -92.3, ...],
      "minFreq": 75.0,
      "maxFreq": 350.0,
      "minDB": -100.0,
      "maxDB": 0.0,
      "isLogarithmic": false
    },
    "chartImageData": "iVBORw0KGgoAAAANSUhEUgAA...",
    "peakAnnotationOffsets": {
      "660e8400-e29b-41d4-a716-446655440001": {
        "x": 12.5,
        "y": -20.0
      }
    }
  }
]
```

**Notes:**
- `chartImageData` is base64-encoded PNG
- `frequencies` and `magnitudes` are complete arrays (can be large)
- All UUIDs are preserved for tracking
- Dates use ISO 8601 format

## Use Cases

### 1. Document a Guitar Build

**Workflow:**
1. Take measurements at key stages
2. Save each with descriptive location/notes
3. Export all as JSON for your records
4. Share chart images in your build journal

**Benefits:**
- Complete history of your build
- Can compare any two stages
- Images ready for documentation
- Data backup for analysis

### 2. Compare Before/After Adjustments

**Workflow:**
1. Take "before" measurement
2. Save with notes about current state
3. Make your adjustment (bracing, thickness, etc.)
4. Take "after" measurement
5. Load the "before" measurement to compare
6. Export both for your records

**Benefits:**
- See exact impact of changes
- Document what works/doesn't work
- Build knowledge base over time

### 3. Share with Mentor or Colleague

**Workflow:**
1. Take measurement with detailed notes
2. Save measurement (includes chart image)
3. Export as JSON
4. Send JSON file via email or cloud storage
5. Recipient imports JSON
6. They can load it and see your exact view

**Benefits:**
- Complete data transfer
- No information loss
- They see exactly what you saw
- Can analyze your data independently

### 4. Create a Guitar Database

**Workflow:**
1. Measure multiple guitars
2. Save each with guitar name as location
3. Add notes about guitar characteristics
4. Export all as one JSON file
5. Build your reference database

**Benefits:**
- Compare guitars objectively
- Identify patterns
- Reference for future builds
- Share database with community

### 5. Prepare for Presentations

**Workflow:**
1. Take measurements throughout build
2. Save with descriptive names
3. Export chart images from saved measurements
4. Use images in slides/documents
5. Keep JSON for interactive demos

**Benefits:**
- Professional quality charts
- Can recreate plots during presentation
- Answer questions with actual data
- Audience can request exports

## Tips & Best Practices

### For Best Results

1. **Always add tap location** - Makes finding measurements easier
2. **Use descriptive notes** - "After reducing top thickness by 0.5mm at bridge"
3. **Adjust zoom before saving** - The chart image captures your current view
4. **Organize labels before saving** - Drag them to avoid overlaps
5. **Save incrementally** - Don't wait until the end of a project

### For Organization

1. **Name consistently** - e.g., "Guitar-01-Bridge", "Guitar-01-Soundhole"
2. **Export regularly** - Backup your measurements
3. **Use dates in exports** - Files are automatically timestamped
4. **Keep measurements in projects** - Export separate JSON files per guitar

### For Collaboration

1. **Export with images** - Images are included in JSON automatically
2. **Add context in notes** - Temperature, humidity, string tension, etc.
3. **Share JSON files** - Complete data, not just images
4. **Document your setup** - Include mic placement notes

### For Analysis

1. **Export all measurements** - Import into analysis tools
2. **Use spectrum data** - Full frequency response is available
3. **Track changes over time** - Timestamps enable time-series analysis
4. **Preserve annotation positions** - Shows what you considered important

## Technical Details

### Image Storage
- **Format:** PNG with alpha channel
- **Encoding:** Base64 in JSON
- **Size:** ~200KB-500KB per image (depending on complexity)
- **Quality:** Retina resolution (2x-3x scaling)

### Spectrum Data Storage
- **Frequencies:** Float array (typically 65,536 values)
- **Magnitudes:** Float array (matching length)
- **Size:** ~500KB per spectrum in JSON
- **Precision:** Full floating-point precision preserved

### Performance
- **Save time:** 1-2 seconds (includes image rendering)
- **Export time:** ~1 second per 10 measurements
- **Import time:** <1 second for typical files
- **File size:** ~1MB per measurement with image and spectrum

### Compatibility
- **iOS 14+**
- **macOS 11+**
- **Forward compatible:** New features won't break old JSON files
- **Backward compatible:** Old exports can be imported (image/spectrum will be nil)

## Troubleshooting

### Save button disabled
- **Cause:** No peaks detected
- **Solution:** Tap guitar and use "New Tap" to capture peaks

### Save seems slow
- **Normal:** Rendering high-quality chart takes 1-2 seconds
- **Wait for:** Progress indicator to disappear

### Import fails
- **Check:** File is valid JSON
- **Check:** File was exported from GuitarTap
- **Check:** File isn't corrupted
- **Try:** Re-export the original measurements

### Loaded measurement looks different
- **Remember:** Frozen spectrum is shown (not live)
- **This is normal:** You're seeing the exact capture from save time
- **To resume live:** Click "Resume" button

### Chart image missing in old measurements
- **Expected:** Old measurements saved before this feature was added
- **Solution:** Load the measurement and save it again to capture image

### JSON file is very large
- **Normal:** Full spectrum data + images = ~1MB per measurement
- **Reduce size:** Don't include spectrum (but you lose recreation ability)
- **Alternative:** Export and compress with ZIP

## Keyboard Shortcuts (macOS)

- **⌘S** - Save current measurement (when peaks detected)
- **⌘I** - Import measurements
- **⌘E** - Export all measurements
- **⌘L** - Load selected measurement

*Note: Some shortcuts may require focus on specific views*

## Future Enhancements

Potential improvements:
- [ ] Cloud sync for measurements
- [ ] Automatic backups
- [ ] Measurement comparison view (overlay two plots)
- [ ] Batch operations (export multiple, delete multiple)
- [ ] Search and filter measurements
- [ ] Tags and categories
- [ ] PDF report generation
- [ ] CSV export for spreadsheet analysis

## Support

If you encounter issues:
1. Check console logs for error messages
2. Verify file permissions
3. Ensure adequate storage space
4. Try exporting a single measurement first
5. Check JSON file structure if import fails

## Summary

The measurement system is now complete:
- ✅ Auto-save chart images with measurements
- ✅ Store complete spectrum for plot recreation
- ✅ Preserve custom annotations
- ✅ Export/import with full data
- ✅ Load measurements to recreate exact view
- ✅ Share images from saved measurements
- ✅ Track measurements with visual indicators

Every measurement is now a complete snapshot that can be perfectly recreated at any time!
