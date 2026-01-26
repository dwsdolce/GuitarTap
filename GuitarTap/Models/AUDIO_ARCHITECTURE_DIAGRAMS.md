# Audio Engine Architecture - Before & After

## 🔴 BEFORE (Broken)

```
┌─────────────────────────────────────────────────────────────┐
│                    RealtimeFFTAnalyzer                      │
│                                                             │
│  func start() throws {                                      │
│    ┌─────────────────────────────────────────┐             │
│    │ 1. Get hardware format                  │ ❌ 0 Hz!    │
│    │    let format = inputNode.inputFormat   │             │
│    ├─────────────────────────────────────────┤             │
│    │ 2. Create tap with different rate       │ ❌ Mismatch │
│    │    installTap(format: 48000 Hz)         │             │
│    ├─────────────────────────────────────────┤             │
│    │ 3. Start engine                         │             │
│    │    try audioEngine.start()              │             │
│    └─────────────────────────────────────────┘             │
│  }                                                          │
│                                                             │
│  func stop() {                                              │
│    ┌─────────────────────────────────────────┐             │
│    │ 1. Check if running                     │             │
│    │    if audioEngine.isRunning {           │             │
│    ├─────────────────────────────────────────┤             │
│    │ 2. Remove tap                           │ ❌ May crash│
│    │    inputNode.removeTap(onBus: 0)        │             │
│    ├─────────────────────────────────────────┤             │
│    │ 3. Stop engine                          │ ❌ Device   │
│    │    audioEngine.stop()                   │    gone!    │
│    └─────────────────────────────────────────┘             │
│  }                                                          │
│                                                             │
│  ❌ No configuration change handling                        │
│  ❌ No iOS audio session setup                              │
│  ❌ No observer cleanup                                     │
└─────────────────────────────────────────────────────────────┘

RESULT: 💥 Three types of crashes!
```

---

## ✅ AFTER (Fixed)

```
┌─────────────────────────────────────────────────────────────┐
│                    RealtimeFFTAnalyzer                      │
│                                                             │
│  + useHardwareSampleRate: Bool = true   (NEW PROPERTY)     │
│  + configurationChangeObserver          (NEW PROPERTY)     │
│                                                             │
│  func start() throws {                                      │
│    ┌─────────────────────────────────────────┐             │
│    │ 1. Configure iOS audio session          │ ✅ Platform │
│    │    #if os(iOS)                          │    aware    │
│    │    AVAudioSession.setCategory(.record)  │             │
│    ├─────────────────────────────────────────┤             │
│    │ 2. Add configuration observer           │ ✅ Auto     │
│    │    NotificationCenter.addObserver       │    recovery │
│    │    (.AVAudioEngineConfigurationChange)  │             │
│    ├─────────────────────────────────────────┤             │
│    │ 3. Start engine FIRST                   │ ✅ Valid    │
│    │    try audioEngine.start()              │    format   │
│    ├─────────────────────────────────────────┤             │
│    │ 4. Get hardware format (now valid!)     │ ✅ Real Hz  │
│    │    let format = inputNode.inputFormat   │             │
│    ├─────────────────────────────────────────┤             │
│    │ 5. Create tap with hardware rate        │ ✅ Match!   │
│    │    installTap(format: hardware.rate)    │             │
│    └─────────────────────────────────────────┘             │
│  }                                                          │
│                                                             │
│  func stop() {                                              │
│    ┌─────────────────────────────────────────┐             │
│    │ 1. Check & remove tap FIRST             │ ✅ Safe     │
│    │    if inputNode.numberOfInputs > 0 {    │    check    │
│    │      inputNode.removeTap(onBus: 0)      │             │
│    │    }                                     │             │
│    ├─────────────────────────────────────────┤             │
│    │ 2. Stop engine if running               │ ✅ Handles  │
│    │    if audioEngine.isRunning {           │    missing  │
│    │      audioEngine.stop()                 │    device   │
│    │    }                                     │             │
│    ├─────────────────────────────────────────┤             │
│    │ 3. Deactivate iOS audio session         │ ✅ Clean    │
│    │    #if os(iOS)                          │    shutdown │
│    │    AVAudioSession.setActive(false)      │             │
│    └─────────────────────────────────────────┘             │
│  }                                                          │
│                                                             │
│  func handleConfigurationChange() {         (NEW METHOD)   │
│    ┌─────────────────────────────────────────┐             │
│    │ 1. Stop analyzer                        │ ✅ Clean    │
│    │    stop()                               │    reset    │
│    ├─────────────────────────────────────────┤             │
│    │ 2. Wait for system to settle            │ ✅ Delay    │
│    │    DispatchQueue.asyncAfter(0.1s)       │             │
│    ├─────────────────────────────────────────┤             │
│    │ 3. Restart analyzer                     │ ✅ Auto     │
│    │    try start()                          │    restart  │
│    └─────────────────────────────────────────┘             │
│  }                                                          │
│                                                             │
│  deinit {                                                   │
│    ┌─────────────────────────────────────────┐             │
│    │ 1. Remove observer FIRST                │ ✅ No leaks │
│    │    NotificationCenter.removeObserver    │             │
│    ├─────────────────────────────────────────┤             │
│    │ 2. Stop analyzer                        │ ✅ Clean    │
│    │    stop()                               │    cleanup  │
│    ├─────────────────────────────────────────┤             │
│    │ 3. Destroy FFT setup                    │ ✅ Release  │
│    │    vDSP_DFT_DestroySetup()             │    memory   │
│    └─────────────────────────────────────────┘             │
│  }                                                          │
└─────────────────────────────────────────────────────────────┘

RESULT: ✅ Rock-solid audio processing!
```

---

## 🎯 Error Prevention Flow

```
┌──────────────────────────────────────────────────────────────┐
│                        USER ACTION                           │
└────────────────────────┬─────────────────────────────────────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         v               v               v
  ┌──────────┐   ┌──────────┐   ┌──────────┐
  │  Start   │   │   Stop   │   │  Device  │
  │ Analyzer │   │ Analyzer │   │  Change  │
  └────┬─────┘   └────┬─────┘   └────┬─────┘
       │              │              │
       v              v              v
┌──────────────┐ ┌──────────────┐ ┌──────────────────┐
│ Configure    │ │ Check node   │ │ Configuration    │
│ iOS session  │ │ has inputs   │ │ change observer  │
│              │ │              │ │ triggered        │
│ ✅ Prevents  │ │ ✅ Prevents  │ │                  │
│   iOS issues │ │   crash      │ │ ✅ Auto-restarts │
└──────┬───────┘ └──────┬───────┘ └────┬─────────────┘
       │              │              │
       v              v              v
┌──────────────┐ ┌──────────────┐ ┌──────────────────┐
│ Start engine │ │ Remove tap   │ │ Stop() then      │
│ FIRST        │ │ safely       │ │ Start()          │
│              │ │              │ │                  │
│ ✅ Valid fmt │ │ ✅ No errors │ │ ✅ Seamless      │
└──────┬───────┘ └──────┬───────┘ └────┬─────────────┘
       │              │              │
       v              v              v
┌──────────────┐ ┌──────────────┐ ┌──────────────────┐
│ Get hardware │ │ Stop engine  │ │ New device       │
│ format       │ │ if running   │ │ ready            │
│              │ │              │ │                  │
│ ✅ Real Hz   │ │ ✅ Safe      │ │ ✅ Continues     │
└──────┬───────┘ └──────┬───────┘ └────┬─────────────┘
       │              │              │
       v              v              v
┌──────────────┐ ┌──────────────┐ ┌──────────────────┐
│ Create tap   │ │ Clear buffer │ │ User sees smooth │
│ with HW rate │ │              │ │ transition       │
│              │ │ ✅ Clean     │ │                  │
│ ✅ Matches!  │ │   state      │ │ ✅ Great UX      │
└──────┬───────┘ └──────────────┘ └──────────────────┘
       │
       v
┌──────────────┐
│ SUCCESS! 🎉  │
│              │
│ ✅ Working   │
│   analyzer   │
└──────────────┘
```

---

## 🔄 Sample Rate Decision Flow

```
                    START
                      │
                      v
        ┌─────────────────────────┐
        │ useHardwareSampleRate?  │
        └───────┬─────────┬───────┘
                │         │
         true   │         │   false
                │         │
                v         v
    ┌───────────────┐   ┌─────────────────┐
    │ Use hardware  │   │ Use target rate │
    │ sample rate   │   │ (with resample) │
    │               │   │                 │
    │ ✅ Default    │   │ ⚠️  Optional    │
    │ ✅ Fast       │   │ ⚠️  Slower      │
    │ ✅ No errors  │   │ ⚠️  More CPU    │
    └───────┬───────┘   └────────┬────────┘
            │                    │
            │                    v
            │          ┌──────────────────┐
            │          │ Resample audio   │
            │          │ samples          │
            │          │                  │
            │          │ Linear interp.   │
            │          └────────┬─────────┘
            │                    │
            └────────┬───────────┘
                     │
                     v
            ┌─────────────────┐
            │ Update metrics  │
            │ with effective  │
            │ sample rate     │
            └────────┬────────┘
                     │
                     v
            ┌─────────────────┐
            │ Frequency bins  │
            │ calculated with │
            │ correct spacing │
            └────────┬────────┘
                     │
                     v
                  SUCCESS
```

---

## 📊 Component Interaction Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                         Your App                             │
│                                                              │
│  ┌────────────────────────────────────────────────┐         │
│  │              ContentView                        │         │
│  │  @StateObject var analyzer                      │         │
│  │                                                  │         │
│  │  .onAppear { try? analyzer.start() }           │         │
│  │  .onDisappear { analyzer.stop() }              │         │
│  │  .onChange(of: scenePhase) { ... }             │         │
│  └────────────────┬──────────────┬────────────────┘         │
│                   │              │                           │
└───────────────────┼──────────────┼───────────────────────────┘
                    │              │
                    │ start()      │ stop()
                    v              v
┌──────────────────────────────────────────────────────────────┐
│              RealtimeFFTAnalyzer                             │
│                                                              │
│  ┌─────────────────────────────────────────────┐            │
│  │         Audio Engine Management             │            │
│  │                                              │            │
│  │  • AVAudioEngine                            │            │
│  │  • AVAudioInputNode                         │            │
│  │  • Configuration Observer  ←────────────────┼─┐          │
│  └──────┬─────────────────────────────────┬────┘ │          │
│         │                                  │      │          │
│         │ installTap                       │      │ Config   │
│         │                                  │      │ Change   │
│         v                                  v      │          │
│  ┌─────────────────┐              ┌──────────────┴────┐     │
│  │ Audio Buffers   │              │ handleConfigChange│     │
│  │                 │              │                   │     │
│  │ • inputBuffer   │              │ 1. Stop           │     │
│  │ • thread-safe   │              │ 2. Wait 0.1s      │     │
│  └────────┬────────┘              │ 3. Restart        │     │
│           │                        └───────────────────┘     │
│           │ processAudioBuffer                               │
│           v                                                  │
│  ┌─────────────────────────────────────────┐                │
│  │         FFT Processing                  │                │
│  │                                          │                │
│  │  • Windowing (Boxcar)                   │                │
│  │  • vDSP_DFT_Execute                     │                │
│  │  • Magnitude calculation                │                │
│  │  • dB conversion                         │                │
│  │  • Peak detection                        │                │
│  └─────────┬───────────────────────────────┘                │
│            │                                                 │
│            │ Update @Published properties                    │
│            v                                                 │
│  ┌─────────────────────────────────────────┐                │
│  │      Published Outputs                  │                │
│  │                                          │                │
│  │  • magnitudes: [Float]                  │                │
│  │  • frequencies: [Float]                 │                │
│  │  • peakFrequency: Float                 │                │
│  │  • peakMagnitude: Float                 │                │
│  │  • isRunning: Bool                      │                │
│  │  • Metrics (resolution, rate, etc.)     │                │
│  └──────┬──────────────────────────────────┘                │
└─────────┼──────────────────────────────────────────────────┘
          │
          │ Combine / SwiftUI binding
          v
┌──────────────────────────────────────────────────────────────┐
│                       Your UI                                │
│                                                              │
│  • SpectrumView(analyzer: analyzer)                         │
│  • MetricsView(analyzer: analyzer)                          │
│  • Start/Stop buttons                                        │
│  • Status indicators                                         │
└──────────────────────────────────────────────────────────────┘
```

---

## 🎛️ State Machine

```
                    ┌─────────────┐
                    │  STOPPED    │ ◄──── Initial State
                    │             │
                    │ isRunning = │
                    │    false    │
                    └──────┬──────┘
                           │
                           │ start() called
                           │
                           v
                    ┌─────────────┐
                    │  STARTING   │
                    │             │
                    │ • Config iOS│
                    │ • Observer  │
                    │ • Start eng.│
                    └──────┬──────┘
                           │
                  ┌────────┴─────────┐
                  │                  │
             Success              Failure
                  │                  │
                  v                  v
           ┌─────────────┐    ┌─────────────┐
           │   RUNNING   │    │   ERROR     │
           │             │    │             │
           │ isRunning = │    │ isRunning = │
           │    true     │    │    false    │
           └──────┬──────┘    └─────────────┘
                  │
      ┌───────────┼───────────┐
      │           │           │
      │           │           │
      v           v           v
 ┌────────┐  ┌────────┐  ┌────────────┐
 │ stop() │  │Device  │  │Scene phase │
 │ called │  │changed │  │background  │
 └───┬────┘  └───┬────┘  └─────┬──────┘
     │           │             │
     │           │             │
     └───────────┼─────────────┘
                 │
                 v
          ┌─────────────┐
          │  STOPPING   │
          │             │
          │ • Remove tap│
          │ • Stop eng. │
          │ • Cleanup   │
          └──────┬──────┘
                 │
                 v
          ┌─────────────┐
          │  STOPPED    │ ◄──── Can restart
          │             │
          │ isRunning = │
          │    false    │
          └─────────────┘
```

---

## 🎨 Visual Summary

```
╔══════════════════════════════════════════════════════════════╗
║                    ALL FIXES APPLIED                         ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  ✅ Fix 1: Start engine BEFORE getting format                ║
║     Result: No more 0 Hz error                              ║
║                                                              ║
║  ✅ Fix 2: Use hardware sample rate for tap                  ║
║     Result: No more format mismatch                         ║
║                                                              ║
║  ✅ Fix 3: Safe tap removal + configuration observer         ║
║     Result: No more device stop error                       ║
║                                                              ║
║  ✅ Bonus: iOS audio session management                      ║
║     Result: Better iOS compatibility                        ║
║                                                              ║
║  ✅ Bonus: Auto-restart on device changes                    ║
║     Result: Seamless user experience                        ║
║                                                              ║
╠══════════════════════════════════════════════════════════════╣
║              🎉 PRODUCTION READY! 🎉                         ║
╚══════════════════════════════════════════════════════════════╝
```

---

**All diagrams show the complete transformation from broken to bulletproof!**
