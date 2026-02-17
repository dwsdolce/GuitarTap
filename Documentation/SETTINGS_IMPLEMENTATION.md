# Settings Dialog Implementation

## Summary

I've implemented a comprehensive settings dialog for the GuitarTap app that allows users to configure all spectrum display and analysis parameters. The dialog is accessible via a standard settings gear icon button.

## What Was Added

### 1. New File: `SpectrumSettingsView.swift`

A dedicated settings view that includes:

#### Display Settings Section
- **Display Frequency Range**: Min and Max frequency in Hz (e.g., 75-350 Hz)
- **Display Magnitude Range**: Min and Max magnitude in dB (e.g., -100 to 0 dB)

#### Analysis Settings Section
- **Analysis Frequency Range**: Min and Max frequency for peak detection (e.g., 50-2000 Hz)
- **Peak Detection Threshold**: Minimum magnitude threshold for peak detection (e.g., -60 dB)

#### Audio Input Section
- **Audio Input Device**: Dropdown to select the audio input device (microphone)
- Shows device name and sample rate for each available input
- Displays current device's sample rate and channel count
- USB microphones like UMIK-1 appear when connected

#### Features
- **Form-based UI**: Clean, organized layout using SwiftUI Form with sections
- **Input validation**: All inputs are validated and clamped to reasonable ranges
- **Error alerts**: User-friendly error messages if invalid values are entered
- **Reset to Defaults**: Button to restore all settings to factory defaults
- **Cancel/Apply actions**: Standard dialog behavior with Cancel and Apply buttons
- **Cross-platform**: Works on both iOS and macOS with platform-specific keyboard types

### 2. Updated: `TapToneAnalysisView.swift`

Added integration for the settings dialog:

#### New State Variable
- `@State private var showingSettings = false`: Controls the presentation of the settings sheet

#### New Settings Button
Added a settings button with the gear icon (`gearshape`) to:
- **iPhone (compact)**: In the first row of controls alongside other action buttons
- **iPad**: In the main control bar with full label "Settings"
- **macOS**: In the main toolbar with full label "Settings"

#### Settings Sheet
- Integrated sheet presentation that binds to all relevant settings
- Binds to both display settings (minFreq, maxFreq, minDB, maxDB) and analysis settings (analysisMinFreq, analysisMaxFreq, peakThreshold)
- Added `onChange` modifiers to sync input text fields when settings change

#### Removed Inline Controls
- **Removed**: All inline range controls from above the chart
  - Frequency Range text fields (Min/Max Hz) with apply button
  - Magnitude Range text fields (Min/Max dB) with apply button
  - "Reset Zoom" button (replaced by "Reset All to Defaults" in settings)
  - "Frozen" status indicator from above chart (moved to status bar)
- **Removed**: Audio input device selector from header (moved to settings dialog)
- **Removed Functions**: 
  - `applyFrequencyRange()` - no longer needed
  - `applyMagnitudeRange()` - no longer needed
  - `resetZoom()` - replaced by settings dialog reset
  - `audioDeviceSelector` view - moved to settings dialog
- **Relocated**: "Frozen" indicator moved to bottom status bar (more appropriate location)

## Settings Included

### Display Settings
1. **Min Frequency**: Default 75 Hz (from `SpectrumDisplaySettings.minFrequency`)
2. **Max Frequency**: Default 350 Hz (from `SpectrumDisplaySettings.maxFrequency`)
3. **Min Magnitude**: Default -100 dB (from `SpectrumDisplaySettings.minMagnitude`)
4. **Max Magnitude**: Default 0 dB (from `SpectrumDisplaySettings.maxMagnitude`)

### Analysis Settings
5. **Analysis Min Frequency**: Default 50 Hz (from `SpectrumDisplaySettings.analysisMinFrequency`)
6. **Analysis Max Frequency**: Default 2000 Hz (from `SpectrumDisplaySettings.analysisMaxFrequency`)
7. **Peak Threshold**: Default -60 dB (from `SpectrumDisplaySettings.defaultPeakThreshold`)

### Audio Input (when devices available)
8. **Audio Input Device**: Select the microphone/audio input device for analysis

## Validation Rules

The settings dialog uses validation functions from `SpectrumDisplaySettings`:

### Frequency Range Validation
- Clamped between 20 Hz and 20,000 Hz
- Minimum separation of 10 Hz between min and max
- Falls back to defaults if validation fails

### Magnitude Range Validation
- Clamped between -120 dB and 20 dB
- Minimum separation of 10 dB between min and max
- Falls back to defaults if validation fails

### Peak Threshold Validation
- Clamped between -120 dB and 0 dB

## User Experience

1. **Opening Settings**: Click/tap the gear icon button in the toolbar
2. **Editing Values**: Text fields for all parameters with number pad keyboard on iOS
3. **Applying Changes**: Tap "Apply" to save changes, or "Cancel" to dismiss
4. **Resetting**: "Reset All to Defaults" button restores factory settings
5. **Validation**: Invalid inputs show an alert with a helpful error message
6. **Automatic Sync**: Changes are immediately reflected in the spectrum display after applying

## Benefits

- **Centralized Configuration**: All spectrum-related settings in one place
- **Cleaner UI**: All inline controls removed from above the chart
- **More Screen Space**: Chart area maximized for data viewing
- **Better Organization**: Status indicators (like "Frozen") now in status bar
- **User-Friendly**: Clear labels and descriptions for each setting
- **Safe**: Input validation prevents invalid configurations
- **Discoverable**: Standard gear icon makes settings easy to find
- **Flexible**: Users can fine-tune display and analysis parameters for different use cases
- **Consistent**: Uses the same `SpectrumDisplaySettings` defaults and validation throughout the app
- **Single Reset**: One "Reset All to Defaults" button handles all settings

## Technical Details

- Uses SwiftUI `@Binding` for two-way data synchronization
- Leverages existing validation logic from `SpectrumDisplaySettings`
- Integrates seamlessly with the existing analyzer architecture
- Supports both sheet presentation (iOS/macOS) with proper toolbar items
- Updates text input fields automatically via `onChange` modifiers
