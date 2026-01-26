# Quick Fix Reference - Audio Engine Errors

## 🔴 Problem
```
AddInstanceForFactory: No factory registered...
AURemoteIO.cpp:1135  failed: -10851 (enable 1, outf< 2 ch, 0 Hz, Float32...
```
OR
```
VAEUtility.mm:176   Format mismatch: input hw <... 44100 Hz>, client format <... 48000 Hz>
```

## ✅ Solution

### Update Your Code

**Old:**
```swift
let analyzer = RealtimeFFTAnalyzer(fftSize: 8192, targetSampleRate: 48000)
```

**New (Default - Recommended):**
```swift
// Uses hardware sample rate automatically - no resampling, no errors
let analyzer = RealtimeFFTAnalyzer(fftSize: 8192)
```

**Or with explicit flag:**
```swift
// Same as above - useHardwareSampleRate defaults to true
let analyzer = RealtimeFFTAnalyzer(
    fftSize: 8192,
    targetSampleRate: 48000,
    useHardwareSampleRate: true  // Use hardware rate, ignore targetSampleRate
)
```

**If you really need a specific sample rate:**
```swift
// Will resample hardware audio to your target rate
let analyzer = RealtimeFFTAnalyzer(
    fftSize: 8192,
    targetSampleRate: 48000,
    useHardwareSampleRate: false  // Enable resampling
)
```

---

## 🎯 What Changed

1. **Added `useHardwareSampleRate` parameter** (defaults to `true`)
2. **Start audio engine before getting format** (fixes 0 Hz error)
3. **Use hardware's native sample rate for tap** (fixes format mismatch)
4. **Only resample when explicitly requested** (better performance)

---

## 📊 Expected Console Output

```
Hardware sample rate: 44100.0 Hz
Target sample rate: 48000.0 Hz
Using sample rate: 44100.0 Hz
FFT size: 8192
Tap format: <AVAudioFormat 0x...:  1 ch,  44100 Hz, Float32>
=== Analysis Metrics ===
Frequency Resolution: 5.383301 Hz
Bandwidth: 22050.0 Hz (0 Hz to 22050.0 Hz)
Sample Length: 185.75964 ms (0.18575963 seconds)
Frame Rate: 10.766602 Hz
=======================
Audio engine started successfully
```

---

## 🚀 Benefits

- ✅ No more audio engine errors
- ✅ Works on all devices (adapts to hardware)
- ✅ Better performance (no unnecessary resampling)
- ✅ Accurate frequency calculations
- ✅ Clear console logging

---

## 💡 When to Use Each Mode

### Use Hardware Sample Rate (Default) ✅
**Best for:** Most apps, audio visualizers, spectrum analyzers

```swift
let analyzer = RealtimeFFTAnalyzer(fftSize: 8192)
```

**Pros:**
- No resampling overhead
- No format mismatch errors
- Automatically adapts to device
- Best performance

**Cons:**
- Sample rate varies by device (usually 44100 or 48000 Hz)

---

### Use Custom Sample Rate with Resampling ⚠️
**Best for:** Apps requiring specific sample rate for external processing

```swift
let analyzer = RealtimeFFTAnalyzer(
    fftSize: 8192,
    targetSampleRate: 48000,
    useHardwareSampleRate: false
)
```

**Pros:**
- Guaranteed sample rate
- Consistent across devices

**Cons:**
- Resampling overhead (CPU usage)
- Slightly lower audio quality (interpolation)

---

## 🔍 Troubleshooting

### Q: Still getting errors?
**A:** Make sure you updated to the new init signature:
```swift
// ✅ Good
let analyzer = RealtimeFFTAnalyzer(fftSize: 8192)

// ❌ If you get errors, check your init call
```

### Q: Frequencies seem wrong?
**A:** The analyzer now uses the actual sample rate for calculations. Check console output to see what sample rate is being used.

### Q: Want to force a specific sample rate?
**A:** Use `useHardwareSampleRate: false`:
```swift
let analyzer = RealtimeFFTAnalyzer(
    fftSize: 8192,
    targetSampleRate: 48000,
    useHardwareSampleRate: false
)
```

---

## 📝 Migration Guide

### If you have existing code:

**Before:**
```swift
@StateObject private var analyzer = RealtimeFFTAnalyzer(
    fftSize: 16384,
    targetSampleRate: 48000
)
```

**After (Simple - Recommended):**
```swift
@StateObject private var analyzer = RealtimeFFTAnalyzer(
    fftSize: 16384
    // That's it! Will use hardware sample rate automatically
)
```

**After (Keep target rate behavior):**
```swift
@StateObject private var analyzer = RealtimeFFTAnalyzer(
    fftSize: 16384,
    targetSampleRate: 48000,
    useHardwareSampleRate: false  // Add this to keep old behavior
)
```

---

## ✨ That's It!

Your audio engine errors should now be fixed. The analyzer will automatically adapt to whatever sample rate your device's hardware uses.

**For more details, see:** `AUDIO_ENGINE_FIX.md`
