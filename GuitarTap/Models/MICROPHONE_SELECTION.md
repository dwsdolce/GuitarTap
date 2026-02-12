# Microphone Selection Guide

## Overview

GuitarTap supports selecting specific audio input devices on both iOS and macOS, including USB microphones like the dayton audio UMIK-1.

## How to Select Your Microphone

### On macOS

1. **Connect your microphone** - Plug in your UMIK-1 or other USB microphone before launching the app
2. **Launch GuitarTap** - The app will automatically detect all available audio input devices
3. **Find the audio input selector** - In the header section of the Tap Tone Analysis view, you'll see a blue-tinted section with:
   - A microphone icon 🎤
   - "Audio Input:" label
   - A dropdown picker showing available devices
4. **Select your device** - Click the picker and choose your UMIK-1 from the list
   - Each device shows its name and sample rate (e.g., "UMIK-1 (48 kHz)")
5. **The app will restart audio** - If analysis is running, it will automatically restart with the new device

### On iOS

1. **Connect your audio interface** - Connect your UMIK-1 or other USB audio interface using:
   - USB-C to USB adapter (for iPad Pro with USB-C)
   - Lightning to USB Camera Adapter (for iPad/iPhone with Lightning)
   - Direct USB-C connection (for newer iPads)
2. **Launch GuitarTap** - The app will detect all available audio inputs
3. **Find the audio input selector** - In the header section, you'll see:
   - A microphone icon 🎤
   - "Audio Input:" label
   - A menu picker showing available inputs
4. **Select your input** - Tap the picker to choose from:
   - Built-in Microphone
   - Headset Microphone (if connected)
   - USB Audio Interface (your UMIK-1)
   - Any other connected audio devices
5. **Audio switches immediately** - The app uses the new input without restarting

### Features

- **Automatic device detection** - All connected audio input devices are detected on startup
- **Sample rate display** - Each device shows its native sample rate
- **Hot-swapping** - You can change devices while analysis is running
- **Persistent selection** - Your selected device is remembered during the session
- **iOS route change detection** - Automatically detects when devices are connected/disconnected

## Troubleshooting

### My UMIK-1 doesn't appear in the list

#### macOS
1. **Check USB connection** - Ensure the microphone is properly connected
2. **Check System Settings** - Open System Settings > Sound > Input and verify the UMIK-1 appears there
3. **Restart the app** - Quit and relaunch GuitarTap to refresh the device list
4. **Check permissions** - Ensure GuitarTap has microphone access in System Settings > Privacy & Security > Microphone

#### iOS
1. **Check adapter** - Ensure you're using an official Apple Lightning to USB adapter or USB-C adapter
2. **Check iOS compatibility** - USB audio interfaces require:
   - iOS 17.0 or later for best compatibility
   - Lightning to USB Camera Adapter (not just the basic Lightning to USB adapter)
3. **Check device power** - Some USB devices may need powered adapters
4. **Restart the app** - Force quit and relaunch GuitarTap
5. **Check Settings** - Go to Settings > Privacy > Microphone and ensure GuitarTap has access

### Audio quality issues

- **Sample rate mismatch** - The UMIK-1 typically runs at 48 kHz. GuitarTap will use the device's native sample rate
- **Check Audio MIDI Setup** (macOS) - Open Audio MIDI Setup (in /Applications/Utilities/) and verify your UMIK-1 settings
- **Try a different USB port** - Some USB hubs may cause issues; try connecting directly
- **Check iOS adapter** - On iOS, use an official Apple adapter for best results

### No audio devices detected

If no devices appear:

#### macOS
1. Restart the app
2. Check Console.app for error messages from GuitarTap
3. Verify other audio apps can see your devices

#### iOS
1. Disconnect and reconnect the adapter
2. Force quit and relaunch GuitarTap
3. Try connecting the adapter before launching the app
4. Verify the device works in other iOS audio apps (like GarageBand)

## UMIK-1 Specific Notes

The dayton audio UMIK-1 is a calibrated measurement microphone ideal for acoustic analysis:

- **Flat frequency response** - Designed for accurate measurements (±2dB from 10 Hz to 20 kHz)
- **USB powered** - No external power needed
- **Multiple sample rates** - Supports 44.1 kHz, 48 kHz, and 96 kHz
- **iOS compatible** - Works with iPad/iPhone using appropriate USB adapter
- **Calibration file** - The UMIK-1 comes with a calibration file (not currently used by GuitarTap)

### iOS Connection Tips for UMIK-1

- **iPad Pro (USB-C)**: Use a USB-C to USB-A adapter
- **iPad/iPhone (Lightning)**: Use the Lightning to USB Camera Adapter (the one with the Lightning port for power)
- **Power**: The UMIK-1 is bus-powered and should work without additional power, but if you experience issues, use the powered Camera Adapter
- **Position**: The UMIK-1 is omnidirectional, so point it toward the sound source for best results

### Future Enhancement

In a future version, GuitarTap could support loading UMIK-1 calibration files to apply frequency response correction for even more accurate measurements.

## Platform-Specific Behaviors

### macOS
- Uses Core Audio API for device enumeration
- Requires audio engine restart when changing devices
- Can access all system audio input devices
- Device list is static (detected at app launch)
### iOS
- Uses AVAudioSession API for device management
- Seamlessly switches devices without restart
- Automatically detects when devices are connected/disconnected
- Supports built-in microphone, headsets, and USB audio interfaces
- May show multiple inputs for multi-channel interfaces

