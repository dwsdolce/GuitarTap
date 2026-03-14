# Complete Export Functionality Guide

## Overview

Your GuitarTap app now has comprehensive export capabilities for both data (JSON) and visualizations (PNG images). This guide explains all the export options available to you.

## Export Options

### 1. Export Current Spectrum View (NEW!)

**What it does:** Exports the real-time frequency response plot as a high-quality PNG image.

**How to use:**
1. Start the analyzer and tap the guitar
2. Wait for the spectrum to show interesting data
3. Click the **"Export Spectrum"** button in the header toolbar
4. Choose where to save the PNG file (or share it on iOS)

**What's included in the export:**
- Full frequency response curve
- Detected peaks with color-coded mode markers
- Peak annotations showing frequency, mode, and magnitude
- Chart header with date, frequency range, and dB range
- Peak summary showing up to 8 detected peaks
- Legend showing all guitar mode colors
- High resolution: 1400×800 pixels (scaled for retina displays)

**File naming:** `spectrum-{timestamp}.png`

**Best for:** 
- Analyzing the complete frequency response
- Comparing before/after adjustments
- Documentation and reports
- Sharing with other builders

---

### 2. Export Measurement Data (JSON)

**What it does:** Saves measurement data in JSON format for analysis, backup, or sharing.

#### Option A: Export All Measurements

**How to use:**
1. Click **"Measurements"** button
2. Click **"Export All"** (macOS) or tap menu → **"Export All as JSON"** (iOS)
3. Choose where to save the file

**File naming:** `guitar-measurements-{timestamp}.json`

#### Option B: Export Single Measurement from List

**How to use:**
1. Open **"Measurements"**
2. Right-click (macOS) or long-press (iOS) on a measurement
3. Select **"Export as JSON"**
4. Choose where to save

**File naming:** `guitar-measurements-{timestamp}.json`

#### Option C: Export from Detail View

**How to use:**
1. Open **"Measurements"**
2. Click/tap a measurement to open details
3. Click export menu → **"Export JSON"**
4. Choose where to save

**File naming:** `{location}-{timestamp}.json`

**What's included:**
```json
{
  "id": "unique-id",
  "timestamp": "2026-02-08T10:30:00Z",
  "peaks": [
    {
      "frequency": 105.2,
      "magnitude": -42.3,
      "quality": 12.5,
      "bandwidth": 8.4
    }
  ],
  "decayTime": 1.85,
  "tapLocation": "Bridge",
  "notes": "Your observations",
  "tapToneRatio": 2.05
}
```

**Best for:**
- Backing up measurements
- Importing into spreadsheets
- Sharing with collaborators
- Long-term data storage

---

### 3. Export Peak Chart Image (From Measurements)

**What it does:** Creates a publication-quality chart showing detected peaks with full annotations.

**How to use:**
1. Open **"Measurements"**
2. Click/tap a measurement to open details
3. Click export menu → **"Export Chart Image"**
4. Choose where to save or share

**File naming:** `{location}-{timestamp}.png`

**What's included:**
- Color-coded peak markers by guitar mode
- Individual peak labels (frequency, mode, magnitude)
- Header with measurement metadata
- Tap tone ratio (if available)
- Legend showing mode colors
- High resolution: 1200×700 pixels

**Best for:**
- Creating reports
- Presentations
- Comparing specific measurements
- Documentation

---

## Platform Differences

### iOS
- **File Export**: Uses the Files app picker - you can save to iCloud Drive, local storage, or any file provider
- **Image Export**: Uses the Share Sheet - save to Photos, share via AirDrop, Messages, Email, etc.
- **Access**: Export buttons are in menus (three dots icon)

### macOS
- **File Export**: Uses standard Save Panel with file browser
- **Image Export**: Uses standard Save Panel
- **Access**: Export buttons are in the toolbar
- **Default Location**: Last used folder or Documents

---

## Quick Reference

| What to Export | Where to Find It | Button Name | Format |
|---------------|------------------|-------------|---------|
| Real-time spectrum | Main view header | "Export Spectrum" | PNG |
| All measurements | Measurements list | "Export All" | JSON |
| Single measurement data | Measurement context menu | "Export as JSON" | JSON |
| Single measurement data | Measurement detail view | "Export JSON" | JSON |
| Peak chart | Measurement detail view | "Export Chart Image" | PNG |

---

## Tips & Best Practices

### For Best Spectrum Exports
1. **Zoom to the range you want** before exporting - the export captures your current view
2. **Use frozen spectrum** when you want to capture a specific moment
3. **Wait for peaks to be detected** for the most informative charts
4. **Adjust dB range** to show the relevant magnitude levels

### For Best Peak Chart Exports
1. Save measurements with descriptive **tap locations** (e.g., "Bridge - Center", "Upper Bout - Left")
2. Add detailed **notes** about what you're testing
3. The export uses the same color coding as the app (blue = cross-grain, green = long-grain, etc.)

### For Data Analysis
1. Export measurements as JSON for use in:
   - Spreadsheet apps (Excel, Numbers, Google Sheets)
   - Python/R for statistical analysis
   - Custom analysis tools
2. The JSON format is standardized and easy to parse
3. All measurements include timestamps for tracking changes over time

---

## Sharing Workflow Examples

### Example 1: Document a Build
1. Take measurements at key stages (pre-bracing, post-bracing, finished)
2. Add notes for each measurement
3. Export all as JSON for records
4. Export individual spectrum images for your build journal

### Example 2: Compare Adjustments
1. Take initial measurement
2. Make an adjustment
3. Take second measurement
4. Export both peak charts
5. Compare side-by-side

### Example 3: Share with Mentor
1. Take measurement with detailed notes
2. Export spectrum image showing full response
3. Export JSON for detailed analysis
4. Share both via email or cloud storage

---

## Technical Details

### Image Specifications
- **Spectrum Export**: 1400×800 pixels base resolution
- **Peak Chart Export**: 1200×700 pixels base resolution
- **Scaling**: 2x-3x for retina displays
- **Format**: PNG with transparency support
- **Color Space**: sRGB
- **Background**: White for printing compatibility

### JSON Structure
- **Encoding**: UTF-8
- **Date Format**: ISO 8601 (e.g., "2026-02-08T10:30:00Z")
- **Formatting**: Pretty-printed with sorted keys for readability
- **Decimals**: Floats use appropriate precision (2 decimals for frequencies)

### Performance Notes
- Exports run on background threads to avoid UI freezes
- Progress indicators show during long operations
- Temporary files are automatically cleaned up on iOS
- Images are rendered on-demand (not stored in memory)

---

## Troubleshooting

### "Export Spectrum" button is disabled
- **Cause**: Analyzer is not running or no data available
- **Solution**: Press "Start" and wait for frequency data to appear

### "Save" button is disabled
- **Cause**: No peaks have been detected yet
- **Solution**: Tap the guitar and use "New Tap" to capture peaks

### Export seems slow
- **Normal**: Large FFT sizes (65,536 points) take a moment to render
- **Wait for**: Progress indicator to disappear

### Can't find exported file (iOS)
- **Check**: Files app → "On My iPhone/iPad" → Downloads folder
- **Tip**: Choose "iCloud Drive" during export for easy access across devices

### Image quality is poor
- **Ensure**: You're viewing at 100% zoom
- **Note**: The images are designed for retina displays and will look sharp when printed or viewed at full size

---

## File Storage Recommendations

### For Long-Term Storage
- Export as JSON regularly (it's compact)
- Store images only for key milestones
- Use descriptive tap locations for easy searching

### For Sharing
- PNG images for visual sharing (social media, email)
- JSON files for technical collaboration
- Consider zipping multiple files together

### For Analysis
- Export all measurements as one JSON file
- Import into your analysis tool of choice
- Images can supplement written reports

---

## Future Enhancement Ideas

These features are not yet implemented but could be added:
- [ ] CSV export for direct spreadsheet import
- [ ] PDF report generation with multiple charts
- [ ] Batch export of multiple spectrum views
- [ ] Comparison overlays (multiple measurements on one chart)
- [ ] Cloud sync (iCloud, Dropbox, Google Drive)
- [ ] Email integration for direct sharing
- [ ] Print support for charts
- [ ] Custom export templates

---

## Support

If you have questions or encounter issues:
1. Check that you have permission to write files
2. Ensure adequate storage space is available
3. Verify that temporary files can be created
4. Check console logs for error messages
5. Try exporting to a different location

---

## Version History

- **v1.1** (Feb 2026): Added real-time spectrum export
  - New "Export Spectrum" button
  - High-quality spectrum rendering
  - Peak summary in exports
  
- **v1.0** (Feb 2026): Initial export features
  - JSON export for measurements
  - Peak chart image export
  - Platform-specific save dialogs
