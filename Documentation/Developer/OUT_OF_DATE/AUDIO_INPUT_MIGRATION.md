# Audio Input Selection - Moved to Settings

## Summary

The audio input device selector has been successfully moved from the header area to the centralized settings dialog.

## What Changed

### BEFORE: Audio Selector in Header
The audio device selector appeared as a separate row in the header, between the tap controls and the spectrum chart:

```
┌────────────────────────────────────────────────────┐
│ [Tap Controls: Taps, Threshold, etc.]             │
├────────────────────────────────────────────────────┤
│ 🎤 Audio Input: [Built-in Microphone ▾]           │
│     Shows device name and sample rate inline      │
├────────────────────────────────────────────────────┤
│         ↓ Spectrum Chart Below ↓                   │
└────────────────────────────────────────────────────┘
```

**Issues:**
- Took up an entire row in the header
- Added visual clutter
- Separated from other settings
- Didn't fit thematically with viewing area

### AFTER: Audio Selector in Settings Dialog
The audio device selector is now integrated into the settings dialog as its own section:

```
Settings Dialog (⚙️):
┌─────────────────────────────────────────────┐
│  📊 DISPLAY SETTINGS                        │
│  ...                                        │
│                                             │
│  🫀 ANALYSIS SETTINGS                       │
│  ...                                        │
│                                             │
│  🎤 AUDIO INPUT                             │
│  Audio Input Device:                        │
│  ▾ [Built-in Microphone              ]     │
│                                             │
│  Sample Rate: 48000 Hz                     │
│  Channels: 1                               │
│  USB microphones like UMIK-1 will          │
│  appear here when connected.               │
└─────────────────────────────────────────────┘
```

## Implementation Details

### SpectrumSettingsView.swift
**Added:**
- `fftAnalyzer: RealtimeFFTAnalyzer` parameter (passed as `@ObservedObject`)
- New "Audio Input" section (only shown when devices are available)
- Picker for selecting audio input device
- Display of current device's sample rate and channel count
- Helpful footer text explaining USB microphone support

**Section Structure:**
```swift
Section {
    Picker("Audio Input Device", ...) {
        ForEach(fftAnalyzer.availableInputDevices) { device in
            // Device name and sample rate
        }
    }
    
    // Show details of selected device
    if let selectedDevice = fftAnalyzer.selectedInputDevice {
        // Sample rate and channel count
    }
} header: {
    Label("Audio Input", systemImage: "mic.fill")
} footer: {
    Text("Select the audio input device...")
}
```

### TapToneAnalysisView.swift
**Removed:**
- `audioDeviceSelector` view definition (~45 lines)
- Call to `audioDeviceSelector` in header view
- Entire audio input row from header

**Updated:**
- Both `SpectrumSettingsView` initializations (macOS and iOS) now pass `fftAnalyzer` parameter
- Settings dialog has access to FFT analyzer for device selection

## Benefits

✅ **Cleaner Header**: Removed entire audio input row from header
✅ **Better Organization**: Audio settings grouped with other configuration
✅ **Consistent Location**: All settings in one place
✅ **Better UI Flow**: Settings are modal - configure once, then analyze
✅ **Same Functionality**: Audio device selection works exactly as before
✅ **More Context**: Settings dialog can show more device details
✅ **Conditional Display**: Only shows section when devices are available

## User Experience

**Before:**
- Audio device selector always visible in header
- Takes up space even when not being changed
- Separate from other settings

**After:**
1. Open Settings dialog (⚙️)
2. Scroll to "Audio Input" section
3. See all available devices with sample rates
4. Select device
5. View device details (sample rate, channels)
6. Close settings and start analyzing

## Code Cleanup

**Lines removed from main view:** ~50 (audio selector view + integration)
**Lines added to settings view:** ~45 (audio input section)
**Net effect:** 
- Same functionality
- Better organization
- Cleaner main interface
- Settings are centralized

## Notes

- Audio device selection works identically to before
- Device changes are applied immediately (doesn't require "Apply" button)
- Section only appears when audio devices are available
- Maintains iOS and macOS compatibility
- Includes helpful footer text about USB microphones
