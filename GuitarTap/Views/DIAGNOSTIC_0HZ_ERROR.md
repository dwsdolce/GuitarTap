# Diagnostic Steps for 0 Hz Error

## 🔍 Problem

Still getting:
```
AddInstanceForFactory: No factory registered...
AURemoteIO.cpp:1135  failed: -10851 (enable 1, outf< 2 ch, 0 Hz, Float32...
```

## 🎯 Root Causes

This error with `0 Hz` sample rate indicates the audio hardware isn't initializing properly. Possible causes:

### 1. **FFT Size Too Large** ⚠️

Your ContentView has:
```swift
@StateObject private var analyzer = RealtimeFFTAnalyzer(
    fftSize: 65536,  // ⚠️ VERY LARGE!
    targetSampleRate: 48000
)
```

**Problem:** 65536 samples is:
- **1.37 seconds** of audio at 48000 Hz
- **1.49 seconds** at 44100 Hz  
- Requires **huge** buffer allocations
- May exceed system limits on some devices

**Fix:** Start with a reasonable size:
```swift
@StateObject private var analyzer = RealtimeFFTAnalyzer(
    fftSize: 8192   // Good balance of resolution and performance
)
```

### 2. **Microphone Permissions**

Check Info.plist has:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need microphone access to analyze audio frequencies</string>
```

### 3. **No Audio Input Device** (macOS)

On macOS, system may not have a default input device selected.

### 4. **Audio Driver Issues**

System audio drivers may not be loaded/functioning.

---

## ✅ Step-by-Step Fix

### Step 1: Update ContentView.swift

Replace line 50 with:

```swift
@StateObject private var analyzer = RealtimeFFTAnalyzer(fftSize: 8192)
```

This will:
- Use a reasonable FFT size
- Automatically use hardware sample rate (no conversion issues)
- Work reliably across all devices

### Step 2: Add Better Error Handling

Update your start button logic to show the error:

```swift
Button(analyzer.isRunning ? "Stop" : "Start Analyzer") {
    if analyzer.isRunning {
        analyzer.stop()
    } else {
        do {
            try analyzer.start()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            print("Failed to start analyzer: \(error)")
        }
    }
}
```

And add an error display:

```swift
if let errorMessage {
    Text(errorMessage)
        .foregroundColor(.red)
        .font(.caption)
        .padding()
}
```

### Step 3: Check Console Output

The updated `start()` method will now print:

```
Hardware sample rate: 44100.0 Hz
Target sample rate: 48000.0 Hz
Using sample rate: 44100.0 Hz
FFT size: 8192
Hardware format: <AVAudioFormat 0x...:  2 ch,  44100 Hz, Float32>
Tap format: <AVAudioFormat 0x...:  1 ch,  44100 Hz, Float32>
Audio engine started successfully
```

If you see `0 Hz`, the error will now throw with a helpful message.

### Step 4: Check Microphone Permissions

#### iOS:
```swift
#if os(iOS)
let status = AVAudioSession.sharedInstance().recordPermission
switch status {
case .undetermined:
    print("Microphone permission: Not requested yet")
case .denied:
    print("Microphone permission: DENIED - check Settings")
case .granted:
    print("Microphone permission: Granted")
@unknown default:
    print("Microphone permission: Unknown")
}
#endif
```

#### macOS:
Go to System Settings → Privacy & Security → Microphone → Enable your app

---

## 🧪 Testing Different FFT Sizes

### Recommended Sizes

| FFT Size | Resolution | Update Rate | Use Case |
|----------|-----------|-------------|----------|
| 2048 | ~23 Hz | ~24 Hz | Beat detection |
| 4096 | ~12 Hz | ~12 Hz | General use |
| **8192** | **~6 Hz** | **~6 Hz** | **Recommended** |
| 16384 | ~3 Hz | ~3 Hz | Pitch detection |
| 32768 | ~1.5 Hz | ~1.5 Hz | Very high precision |
| 65536 | ~0.7 Hz | ~0.7 Hz | ⚠️ May be too large |

### Why 65536 May Cause Issues

1. **Memory:** Requires ~260 KB per FFT
2. **Latency:** 1.37 second delay between updates
3. **Buffer Size:** May exceed AVAudioEngine buffer limits
4. **Processing Time:** Takes longer to compute

### If You Really Need 65536

If you absolutely need this resolution:

```swift
@StateObject private var analyzer = RealtimeFFTAnalyzer(
    fftSize: 65536,
    targetSampleRate: 48000,
    useHardwareSampleRate: false  // Enable resampling
)
```

But be aware:
- Will be much slower
- May drop frames
- Requires powerful hardware
- Better to use multiple smaller FFTs and average results

---

## 🔧 Updated ContentView Example

```swift
struct ContentView: View {
    // Use reasonable FFT size
    @StateObject private var analyzer = RealtimeFFTAnalyzer(fftSize: 8192)
    
    @State private var errorMessage: String?
    @State private var minFreq: Float = 75
    @State private var maxFreq: Float = 300
    @State private var minDB: Float = -100
    @State private var maxDB: Float = 0
    @State private var isLogarithmic: Bool = false
    
    var body: some View {
        VStack {
            // Error display
            if let errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
            
            // Start/Stop button
            Button(analyzer.isRunning ? "Stop" : "Start") {
                if analyzer.isRunning {
                    analyzer.stop()
                } else {
                    do {
                        try analyzer.start()
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                        print("Start error: \(error)")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            
            // Spectrum view
            SpectrumView(
                frequencies: analyzer.frequencies,
                magnitudes: analyzer.magnitudes,
                minFreq: $minFreq,
                maxFreq: $maxFreq,
                minDB: $minDB,
                maxDB: $maxDB,
                isLogarithmic: $isLogarithmic
            )
        }
        .onAppear {
            // Check permissions on iOS
            #if os(iOS)
            let status = AVAudioSession.sharedInstance().recordPermission
            print("Microphone permission: \(status.rawValue)")
            #endif
        }
    }
}
```

---

## 🎯 Quick Fix Summary

**Change this line:**
```swift
// BEFORE (line 50)
@StateObject private var analyzer = RealtimeFFTAnalyzer(fftSize: 65536, targetSampleRate: 48000)

// AFTER
@StateObject private var analyzer = RealtimeFFTAnalyzer(fftSize: 8192)
```

**That's it!** This will likely fix your 0 Hz error.

---

## 📊 What the New Code Does

The updated `start()` method now:

1. ✅ **Resets audio engine** - Ensures clean state
2. ✅ **Configures iOS audio session** - Proper permissions handling
3. ✅ **Validates sample rate** - Throws helpful error if 0 Hz
4. ✅ **Prints hardware format** - Shows what the system provides
5. ✅ **Adds small delay** - Gives hardware time to initialize

---

## 🔍 Still Not Working?

If you still get the error after changing FFT size to 8192:

1. **Check Console** - Look for the error message after the exception
2. **Check Permissions** - Verify microphone access is granted
3. **Check Audio Device** - Ensure microphone is connected and working
4. **Restart App** - Sometimes audio subsystem needs reset
5. **Restart Mac/Device** - Audio drivers may need reload

---

## 💡 Pro Tip

For guitar tuning, you don't need 65536 samples! Here's why:

- **Frequency resolution at 65536:** ~0.73 Hz
- **Frequency resolution at 8192:** ~5.86 Hz
- **Musical note spacing:** ~6 Hz between semitones in guitar range

**8192 is more than sufficient for guitar tuning!**

---

**Try the FFT size fix first** - that's very likely your issue! 🎸
