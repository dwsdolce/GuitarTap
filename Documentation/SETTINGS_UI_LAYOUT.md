# Settings Dialog UI Layout

## Settings Button Location

The settings button (gear icon) appears in the main toolbar:

### iPhone (Compact Layout)
```
[Start/Stop] [Save] [Measurements] [Results] [Metrics] [Reset] [⚙️Settings]
```

### iPad (Regular Layout)
```
[Start/Stop]  ... [Show Results] [Show Metrics] [Save] [Export] [Measurements] [Reset] [Settings] [Reset Labels]
```

### macOS
```
[Start/Stop]  ... [Show Results] [Show Metrics] [Save] [Export] [Measurements] [Reset] [Settings]
```

## Settings Dialog Structure

When the gear icon is tapped/clicked, a sheet presents the following form:

```
┌─────────────────────────────────────────────┐
│  ✕ Cancel    Spectrum Settings    Apply ✓  │
├─────────────────────────────────────────────┤
│                                             │
│  📊 DISPLAY SETTINGS                        │
│                                             │
│  Display Frequency Range                   │
│  [75    ] to [350   ] Hz                   │
│  Frequency range shown in the spectrum chart│
│                                             │
│  Display Magnitude Range                   │
│  [-100  ] to [0     ] dB                   │
│  Magnitude range shown in the spectrum chart│
│                                             │
│─────────────────────────────────────────────│
│                                             │
│  🫀 ANALYSIS SETTINGS                       │
│                                             │
│  Analysis Frequency Range                  │
│  [50    ] to [2000  ] Hz                   │
│  Frequency range used for peak detection   │
│  and analysis                              │
│                                             │
│  Peak Detection Threshold                  │
│  [-60   ] dB                               │
│  Minimum magnitude for peak detection      │
│  (typically -60 to -40 dB)                 │
│                                             │
│─────────────────────────────────────────────│
│                                             │
│  [↺ Reset All to Defaults]                 │
│  Resets all settings to factory defaults   │
│                                             │
└─────────────────────────────────────────────┘
```

## Settings Included

### Display Settings (Controls what's shown in the chart)
1. **Display Frequency Range**
   - Min: 75 Hz (default)
   - Max: 350 Hz (default)
   - Description: "Frequency range shown in the spectrum chart"

2. **Display Magnitude Range**
   - Min: -100 dB (default)
   - Max: 0 dB (default)
   - Description: "Magnitude range shown in the spectrum chart"

### Analysis Settings (Controls how peaks are detected)
3. **Analysis Frequency Range**
   - Min: 50 Hz (default)
   - Max: 2000 Hz (default)
   - Description: "Frequency range used for peak detection and analysis"

4. **Peak Detection Threshold**
   - Value: -60 dB (default)
   - Description: "Minimum magnitude for peak detection (typically -60 to -40 dB)"

## User Actions

### Apply Button
- Validates all input values
- Clamps values to safe ranges
- Updates the bindings
- Dismisses the sheet
- Changes are immediately reflected in the spectrum display

### Cancel Button
- Dismisses the sheet without applying changes
- All edits are discarded

### Reset All to Defaults
- Restores all values to factory defaults from `SpectrumDisplaySettings`
- Does not dismiss the dialog
- User can still cancel or modify further before applying

## Validation

When "Apply" is tapped:
1. All text fields are parsed as Float values
2. Invalid entries show an alert: "Invalid Settings"
3. Valid values are clamped to safe ranges:
   - Frequencies: 20 Hz to 20,000 Hz
   - Magnitudes: -120 dB to 20 dB
   - Peak threshold: -120 dB to 0 dB
4. Minimum separations enforced:
   - Frequency ranges: 10 Hz minimum
   - Magnitude ranges: 10 dB minimum
5. If validation fails, defaults are used

## Keyboard Types (iOS)

- Frequency fields: Decimal pad (allows numbers and decimal point)
- Magnitude/Threshold fields: Numbers and punctuation (allows negative sign)
- macOS: Standard text input

## Integration

The settings dialog binds directly to:
- Display range state variables in `TapToneAnalysisView`
- Analysis properties in `TapToneAnalyzer` (via `@Published` properties)
- Changes are automatically reflected in:
  - Spectrum chart display
  - Peak detection algorithm
  - Analysis results
