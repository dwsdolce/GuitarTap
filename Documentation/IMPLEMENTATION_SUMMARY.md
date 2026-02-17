# iOS Microphone Selection Implementation Summary

## Overview

Successfully implemented cross-platform audio input device selection for both iOS and macOS in GuitarTap. Users can now select from available audio input devices including USB microphones like the UMIK-1.

## Changes Made

### 1. RealtimeFFTAnalyzer.swift

#### Property Updates
- Removed platform-specific `#if os(macOS)` guards from device properties
- Made `selectedInputDevice` and `availableInputDevices` available on all platforms

#### Device Enumeration
- **macOS**: Uses Core Audio API (`AudioObjectGetPropertyData`) to enumerate all audio hardware devices
  - Filters for devices with input channels
  - Retrieves device name, UID, sample rate, and device ID
  
- **iOS**: Uses `AVAudioSession` API to enumerate available inputs
  - Uses `AVAudioSession.sharedInstance().availableInputs`
  - Includes built-in mic, headsets, and USB audio interfaces
  - Automatically tracks current route

#### Device Selection
- **macOS**: Sets device via `AudioUnitSetProperty` with `kAudioOutputUnitProperty_CurrentDevice`
  - Requires engine restart to apply changes
  
- **iOS**: Sets device via `AVAudioSession.setPreferredInput()`
  - Seamless switching without engine restart
  - More responsive to device changes

#### Route Change Monitoring (iOS only)
- Added `NotificationCenter` observer for `AVAudioSession.routeChangeNotification`
- Automatically refreshes device list when devices are connected/disconnected
- Handles cases: `.newDeviceAvailable`, `.oldDeviceUnavailable`

#### AVAudioDevice Struct Updates
- **macOS**: Stores `AudioDeviceID` for Core Audio API
- **iOS**: Stores `AVAudioSessionPortDescription` for session management
- Unified interface with `name`, `uid`, and `sampleRate` on both platforms

### 2. TapToneAnalysisView.swift

#### UI Updates
- Removed platform guard from `audioDeviceSelector` view
- Now displays on both iOS and macOS
- Added platform-specific picker styling:
  - macOS: Standard dropdown with fixed width
  - iOS: Menu-style picker (more touch-friendly)
- Displays device name and sample rate in picker

#### Layout
- Appears in header section below tap controls
- Blue background tint for visibility
- Microphone icon for easy identification
- Only shows when devices are available

### 3. MICROPHONE_SELECTION.md

#### Documentation Updates
- Added comprehensive iOS section
- Included iOS-specific troubleshooting
- Added UMIK-1 connection tips for iOS (USB adapters required)
- Documented platform differences in behavior
- Added section on iOS audio route detection

## Technical Details

### iOS Audio Session Integration

The iOS implementation properly integrates with the existing audio session setup:

```swift
// In TapToneAnalysisView.swift startAnalyzer()
let session = AVAudioSession.sharedInstance()
try session.setCategory(.record, mode: .measurement, options: [])
try session.setActive(true)
```

Device selection via `setPreferredInput()` works within this existing session configuration.

### Device Discovery Timing

- **macOS**: Devices discovered once at init, static list
- **iOS**: Devices discovered at init + dynamically updated via route change notifications

### Error Handling

Both platforms gracefully handle:
- Missing permissions (microphone access)
- Device disconnection during use
- Invalid device selection
- Empty device lists (fallback to current route)

## User Experience

### macOS Flow
1. User plugs in UMIK-1
2. User launches app → devices enumerated
3. User sees dropdown with all audio inputs
4. User selects UMIK-1
5. If running, engine restarts with new device

### iOS Flow
1. User connects UMIK-1 via Lightning/USB-C adapter
2. User launches app → devices enumerated
3. Route change notification fires (optional, if connected after launch)
4. User sees menu picker with all inputs
5. User selects "USB Audio Device" or device name
6. Audio switches immediately without restart

## Benefits

### For Users
- ✅ Select professional measurement microphones (UMIK-1, etc.)
- ✅ Switch between built-in mic and external devices
- ✅ Visual confirmation of current input device
- ✅ See sample rate of each device
- ✅ Works on both iPhone and iPad

### For Measurements
- ✅ Use calibrated microphones for accurate analysis
- ✅ Better frequency response with quality mics
- ✅ Lower noise floor with professional equipment
- ✅ Consistent results across measurement sessions

## Testing Recommendations

### macOS
1. Test with built-in microphone
2. Test with UMIK-1 USB microphone
3. Test with other USB audio interfaces
4. Test device switching while running
5. Test device removal during use

### iOS
1. Test with built-in microphone
2. Test with wired headset
3. Test with UMIK-1 via Lightning to USB adapter
4. Test with UMIK-1 via USB-C (iPad Pro)
5. Test device connection/disconnection during use
6. Test with powered USB hubs
7. Test on different iOS device types (iPhone, iPad)

## Future Enhancements

### Calibration File Support
- Load UMIK-1 calibration files (.txt)
- Apply frequency response correction
- Store calibration data per device
- Display calibration status in UI

### Device Metadata
- Show device type icons (built-in, USB, etc.)
- Display channel count
- Show buffer size and latency
- Indicate device capabilities

### Preferences
- Remember last selected device per platform
- Auto-select preferred device on startup
- Save device preferences to UserDefaults

### Advanced Features
- Support multi-channel inputs
- Allow channel selection for multi-channel devices
- Show input level meters per device
- Device-specific audio settings

## Known Limitations

### iOS
- Requires external USB adapter for UMIK-1
- Some devices may need powered adapters
- Sample rate is determined by iOS audio session
- Limited control over device-specific settings

### macOS
- Device list not updated when devices are hot-plugged (requires restart)
- May need to restart engine when changing devices
- Some aggregate devices may not appear correctly

## Conclusion

The implementation provides a robust, cross-platform solution for audio input device selection. Users on both iOS and macOS can now select their preferred microphone, including professional measurement devices like the UMIK-1, for more accurate acoustic analysis.
