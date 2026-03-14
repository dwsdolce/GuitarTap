# Audio Engine Error Quick Reference

## 🔍 Common Errors & Quick Fixes

### ❌ Error: `AudioDeviceStop: no device with given ID`

**Cause:** Trying to stop device that's already gone  
**Fix:** ✅ FIXED - Improved stop() method checks node inputs first

```swift
// Now handles this automatically
analyzer.stop()
```

---

### ❌ Error: `Format mismatch: input hw <44100 Hz>, client format <48000 Hz>`

**Cause:** Tap format doesn't match hardware sample rate  
**Fix:** ✅ FIXED - Uses hardware sample rate by default

```swift
// Default behavior (recommended)
let analyzer = RealtimeFFTAnalyzer(fftSize: 8192)

// If you really need specific rate, use:
let analyzer = RealtimeFFTAnalyzer(
    fftSize: 8192,
    targetSampleRate: 48000,
    useHardwareSampleRate: false  // Enable resampling
)
```

---

### ❌ Error: `AddInstanceForFactory: no factory registered... 0 Hz`

**Cause:** Getting audio format before engine starts  
**Fix:** ✅ FIXED - Engine now starts before getting format

---

### ❌ Error: Audio stops when plugging/unplugging headphones

**Cause:** Configuration change not handled  
**Fix:** ✅ FIXED - Now observes configuration changes and auto-restarts

---

### ❌ Issue: Analyzer stops working when app backgrounds (iOS)

**Cause:** iOS suspends audio capture in background  
**Fix:** Add scene phase handling:

```swift
@Environment(\.scenePhase) private var scenePhase

var body: some View {
    // Your UI
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                analyzer.stop()
            case .active:
                if shouldBeRunning {
                    try? analyzer.start()
                }
            default:
                break
            }
        }
}
```

---

### ❌ Issue: Microphone permission denied

**Cause:** Missing Info.plist entry or user denied  
**Fix:** 

1. Add to Info.plist:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need microphone access to analyze audio frequencies</string>
```

2. Check permission status:
```swift
#if os(iOS)
let status = AVAudioSession.sharedInstance().recordPermission
if status == .denied {
    // Show alert directing user to Settings
}
#endif
```

---

### ❌ Issue: Analyzer crashes in deinit

**Cause:** Audio engine cleanup issues  
**Fix:** ✅ FIXED - deinit now removes observer first, then stops

---

### ❌ Issue: Multiple "configuration changed" messages

**Cause:** System is switching between audio devices  
**Fix:** This is normal behavior. Analyzer will auto-restart.

**To reduce logging:**
```swift
// Remove or comment out print statements if desired
print("Handling audio engine configuration change")
```

---

## ✅ Checklist for Audio Issues

When debugging audio problems, check these in order:

### 1. Permissions ✓
- [ ] `NSMicrophoneUsageDescription` in Info.plist
- [ ] User granted microphone permission
- [ ] Test on real device (Simulator has limited audio)

### 2. Audio Session (iOS) ✓
- [ ] Audio session configured correctly (✅ now automatic)
- [ ] Category set to `.record` (✅ now automatic)
- [ ] Session activated before engine starts (✅ now automatic)

### 3. Engine Configuration ✓
- [ ] Start engine before getting format (✅ now automatic)
- [ ] Use hardware sample rate (✅ now default)
- [ ] Tap format matches hardware (✅ now automatic)

### 4. Stop/Cleanup ✓
- [ ] Safe to call stop() multiple times (✅ fixed)
- [ ] Tap removed safely (✅ fixed)
- [ ] Observers removed in deinit (✅ fixed)

### 5. Lifecycle Management 🔄
- [ ] Stop in `onDisappear` (❌ you need to add this)
- [ ] Handle scene phase changes (❌ you need to add this)
- [ ] Handle configuration changes (✅ now automatic)

---

## 📋 Copy-Paste Solutions

### Basic Usage (iOS)
```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var analyzer = RealtimeFFTAnalyzer(fftSize: 8192)
    @Environment(\.scenePhase) private var scenePhase
    @State private var isAnalyzing = false
    
    var body: some View {
        VStack {
            Button(isAnalyzing ? "Stop" : "Start") {
                if isAnalyzing {
                    analyzer.stop()
                    isAnalyzing = false
                } else {
                    do {
                        try analyzer.start()
                        isAnalyzing = true
                    } catch {
                        print("Failed to start: \(error)")
                    }
                }
            }
            
            // Your visualization here
            SpectrumView(analyzer: analyzer)
        }
        .onDisappear {
            analyzer.stop()
            isAnalyzing = false
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                analyzer.stop()
                isAnalyzing = false
            }
        }
    }
}
```

### Basic Usage (macOS)
```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var analyzer = RealtimeFFTAnalyzer(fftSize: 8192)
    @State private var isAnalyzing = false
    
    var body: some View {
        VStack {
            Button(isAnalyzing ? "Stop" : "Start") {
                if isAnalyzing {
                    analyzer.stop()
                    isAnalyzing = false
                } else {
                    do {
                        try analyzer.start()
                        isAnalyzing = true
                    } catch {
                        print("Failed to start: \(error)")
                    }
                }
            }
            
            // Your visualization here
            SpectrumView(analyzer: analyzer)
        }
        .onDisappear {
            analyzer.stop()
            isAnalyzing = false
        }
    }
}
```

### With Automatic Restart on Configuration Change
```swift
struct ContentView: View {
    @StateObject private var analyzer = RealtimeFFTAnalyzer(fftSize: 8192)
    
    var body: some View {
        VStack {
            if analyzer.isRunning {
                Text("Analyzing... 🎤")
                    .foregroundColor(.green)
            } else {
                Text("Stopped")
                    .foregroundColor(.gray)
            }
            
            Button(analyzer.isRunning ? "Stop" : "Start") {
                if analyzer.isRunning {
                    analyzer.stop()
                } else {
                    try? analyzer.start()
                }
            }
        }
        .onAppear {
            try? analyzer.start()
        }
        .onDisappear {
            analyzer.stop()
        }
    }
}
```

---

## 🎯 When to Use Each Fix

| Issue | Solution | Implementation |
|-------|----------|----------------|
| Audio device errors | Use latest code | ✅ Automatic |
| Format mismatch | Use hardware sample rate | ✅ Default behavior |
| Configuration changes | Auto-restart observer | ✅ Automatic |
| App backgrounding | Scene phase handling | ❌ Add manually |
| View disappearing | onDisappear handler | ❌ Add manually |
| Specific sample rate | Set useHardwareSampleRate: false | ⚠️ Optional |

---

## 🚦 Status Legend

- ✅ **Automatic** - Built into RealtimeFFTAnalyzer
- ❌ **Manual** - You need to add to your view
- ⚠️ **Optional** - Only if you need this feature
- 🔄 **Recommended** - Best practice, strongly encouraged

---

## 🆘 Still Having Issues?

1. **Check Console Output**
   - Look for "Audio engine started successfully"
   - Check sample rate values match expectations
   - Look for error messages in start/stop

2. **Verify Setup**
   - Using `@StateObject` not `@State`?
   - Real device not Simulator?
   - Microphone permissions granted?

3. **Test Incrementally**
   - Start with basic example above
   - Add features one at a time
   - Test after each addition

4. **Common Mistakes**
   - Creating analyzer with `@State` instead of `@StateObject`
   - Creating multiple analyzer instances
   - Not handling scene phase on iOS
   - Testing in Simulator (audio behaves differently)

---

## 📚 More Help

- See `AUDIO_DEVICE_STOP_FIX.md` for detailed explanation
- See `AUDIO_ENGINE_FIX.md` for format mismatch details
- See `QUICK_FIX_REFERENCE.md` for migration guide

---

**All major audio engine errors have been fixed!** 🎉

Just remember to add scene phase handling and onDisappear cleanup to your views.
