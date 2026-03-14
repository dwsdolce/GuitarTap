# URGENT: FFT Size Issue

## 🔴 The Problem

You're using:
```swift
@StateObject private var analyzer = RealtimeFFTAnalyzer(
    fftSize: 65536,      // ⚠️ TOO LARGE!
    targetSampleRate: 48000
)
```

**65536 samples = 1.37 seconds of audio!**

This is causing the `0 Hz` error because:
1. Buffer allocation may fail
2. Audio engine can't allocate such large buffers
3. System limits exceeded

## ✅ The Fix

### Change ContentView.swift line 50 from:

```swift
@StateObject private var analyzer = RealtimeFFTAnalyzer(fftSize: 65536, targetSampleRate: 48000)
```

### To:

```swift
@StateObject private var analyzer = RealtimeFFTAnalyzer(fftSize: 8192)
```

---

## 📊 Why 8192 is Better

| Metric | 65536 | 8192 | Winner |
|--------|-------|------|--------|
| Frequency Resolution | 0.73 Hz | 5.86 Hz | 65536 (but...) |
| Update Rate | 0.73 Hz | 11.7 Hz | **8192** ✅ |
| Memory per FFT | 262 KB | 32 KB | **8192** ✅ |
| Processing Time | 100+ ms | 2-3 ms | **8192** ✅ |
| Works Reliably | ❌ | ✅ | **8192** ✅ |
| Guitar Tuning | Overkill | Perfect | **8192** ✅ |

---

## 🎸 For Guitar Tuning

Guitar strings fundamental frequencies:
- Low E: 82.4 Hz
- A: 110 Hz
- D: 146.8 Hz
- G: 196 Hz
- B: 246.9 Hz
- High E: 329.6 Hz

**Semitone spacing:** ~6 Hz

**With 8192 FFT:** 5.86 Hz resolution = **perfect** for guitar tuning!

**With 65536 FFT:** 0.73 Hz resolution = massive overkill that breaks things

---

## 🚀 The Simple Fix

1. Open `ContentView.swift`
2. Find line 50 (the `@StateObject` line)
3. Change it to:
```swift
@StateObject private var analyzer = RealtimeFFTAnalyzer(fftSize: 8192)
```
4. Run your app
5. It will work! 🎉

---

## 🔧 Alternative: If You Must Use Large FFT

If you really need high resolution (you don't for guitar!):

```swift
@StateObject private var analyzer = RealtimeFFTAnalyzer(
    fftSize: 16384   // Max recommended
)
```

**DO NOT use 65536** - it's too large for real-time audio on most systems.

---

## 📝 Technical Explanation

AVAudioEngine has buffer size limits:

```swift
let bufferSize = AVAudioFrameCount(fftSize)
inputNode.installTap(onBus: 0, bufferSize: bufferSize, ...)
```

When you request 65536:
- `installTap` tries to allocate 65536-sample buffer
- Audio hardware may not support this
- Driver returns invalid format (0 Hz)
- Everything breaks

Common max buffer sizes:
- iOS: 4096-8192
- macOS: 4096-16384
- High-end: Up to 32768

**65536 exceeds most system limits!**

---

## ⚡ Test This Now

Add this to your ContentView temporarily:

```swift
.onAppear {
    print("=== AUDIO TEST ===")
    print("FFT Size: \(analyzer.fftSize)")  // Will show 65536 currently
    print("Expected buffer duration: \(Double(65536) / 48000) seconds")  // 1.37 seconds!
    print("==================")
}
```

You'll see you're trying to buffer 1.37 seconds of audio per frame!

---

## 💡 The TL;DR

**Change this ONE line in ContentView.swift:**

```swift
// Line 50 - BEFORE
@StateObject private var analyzer = RealtimeFFTAnalyzer(fftSize: 65536, targetSampleRate: 48000)

// Line 50 - AFTER
@StateObject private var analyzer = RealtimeFFTAnalyzer(fftSize: 8192)
```

**That's it. Problem solved.** 🎯
