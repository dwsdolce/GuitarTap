# Audio Engine Format Fix

## Problem

The app was crashing with these errors:

1. **First Error:**
```
AddInstanceForFactory: No factory registered for id <CFUUID 0x6000002078c0> F8BB1C28-BAE8-11D6-9C31-00039315CD46
AURemoteIO.cpp:1135  failed: -10851 (enable 1, outf< 2 ch, 0 Hz, Float32, deinterleaved> inf< 2 ch, 0 Hz, Float32, deinterleaved>)
```

**Cause:** Trying to get `inputNode.inputFormat(forBus: 0)` before starting the audio engine resulted in an invalid format with `0 Hz` sample rate.

2. **Second Error:**
```
VAEUtility.mm:176   Format mismatch: input hw <AVAudioFormat 0x60000212bac0:  1 ch,  44100 Hz, Float32>, 
                                     client format <AVAudioFormat 0x600002163c50:  1 ch,  48000 Hz, Float32>
```

**Cause:** Hardware was running at 44100 Hz but the code was requesting a tap format with 48000 Hz, causing a format mismatch that AVAudioEngine couldn't automatically resolve.

---

## Solution

### Key Changes

1. **Start engine before getting format**
   - Call `audioEngine.start()` first
   - Then get `inputNode.inputFormat(forBus: 0)` - now it's valid

2. **Use hardware's native sample rate for tap**
   - Create tap format using `hardwareFormat.sampleRate`
   - This avoids format conversion issues

3. **Add configuration option**
   - New `useHardwareSampleRate` parameter (default: `true`)
   - When `true`: Use hardware sample rate directly (no resampling, best performance)
   - When `false`: Resample to target rate (useful for specific sample rate requirements)

---

## Usage

### Default (Recommended) - Use Hardware Sample Rate

```swift
let analyzer = RealtimeFFTAnalyzer(
    fftSize: 8192
)
try analyzer.start()

// Will use whatever sample rate the hardware provides (typically 44100 or 48000 Hz)
// No resampling overhead, best compatibility
```

### Specific Sample Rate (with resampling)

```swift
let analyzer = RealtimeFFTAnalyzer(
    fftSize: 8192,
    targetSampleRate: 48000,
    useHardwareSampleRate: false  // Enable resampling
)
try analyzer.start()

// Will resample hardware audio (e.g., 44100 Hz) to target rate (48000 Hz)
// Slightly more CPU usage, useful if you need exact sample rate
```

---

## Technical Details

### Before (Broken)

```swift
func start() throws {
    // ❌ Hardware format not initialized yet - returns 0 Hz
    let inputFormat = inputNode.inputFormat(forBus: 0)
    
    // ❌ Installing tap with different rate causes mismatch error
    inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: tapFormat)
    
    try audioEngine.start()
}
```

### After (Fixed)

```swift
func start() throws {
    // ✅ Start engine first
    try audioEngine.start()
    
    // ✅ Now hardware format is valid
    let hardwareFormat = inputNode.inputFormat(forBus: 0)
    actualSampleRate = hardwareFormat.sampleRate
    
    // ✅ Create tap format matching hardware rate
    let tapFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: hardwareFormat.sampleRate,  // Use hardware rate
        channels: 1,
        interleaved: false
    )
    
    // ✅ No format mismatch
    inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: tapFormat)
}
```

---

## Benefits

✅ **No Format Errors** - Tap format matches hardware exactly  
✅ **Better Performance** - No unnecessary resampling by default  
✅ **More Flexible** - Optional resampling when you need specific sample rate  
✅ **Better Logging** - Console shows hardware vs. target vs. using sample rates  
✅ **Correct Metrics** - Frequency bins calculated with actual sample rate  

---

## Console Output

You'll now see:

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

## Why This Happened

AVAudioEngine requires:
1. Engine must be **started** before hardware format is available
2. Tap format **must match** hardware format (or engine must be configured for conversion)
3. Simple tap installation **doesn't automatically handle** sample rate conversion

The fix ensures we always use the hardware's native format, avoiding conversion issues entirely.

---

## Alternative Approaches (Not Recommended)

### Approach 1: Let AVAudioEngine convert (doesn't work reliably)
```swift
// ❌ Can cause "Format mismatch" errors
let tapFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 48000,  // Different from hardware
    channels: 1,
    interleaved: false
)
```

### Approach 2: Explicit AVAudioConverter (overkill)
```swift
// ⚠️ Works but adds complexity
let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat)
// Need to manually convert in tap callback
```

### Approach 3: Our Solution (simple and reliable)
```swift
// ✅ Use hardware format, optional resampling
let tapFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: hardwareFormat.sampleRate,  // Match hardware
    channels: 1,
    interleaved: false
)
```

---

## Testing

Test on different devices to verify various sample rates:

- **iPhone/iPad**: Usually 44100 Hz or 48000 Hz
- **Mac**: Can vary (44100, 48000, 96000 Hz depending on audio settings)
- **External Audio Interfaces**: May use different rates

The code will now adapt to whatever the hardware provides.

---

## Related Files Modified

- `RealtimeFFTAnalyzer.swift`:
  - Added `useHardwareSampleRate` property
  - Modified `init()` to accept new parameter
  - Modified `start()` to start engine first, then get format
  - Modified `updateFrequencyBins()` to use effective sample rate
  - Modified `updateMetrics()` to use effective sample rate
  - Modified `processAudioBuffer()` to conditionally resample

---

## Version

- **Fixed:** January 25, 2026
- **iOS/iPadOS/macOS**: 15.0+
- **Swift**: 5.5+

---

**Status: ✅ Fixed and tested**
