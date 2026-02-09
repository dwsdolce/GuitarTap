# 🚀 Quick Start - Tap Tone Analysis

## Integration Steps

### 1. Add Files to Your Project

✅ `TapToneAnalyzer.swift` - Analysis engine  
✅ `TapToneAnalysisView.swift` - Complete UI  
✅ `TAP_TONE_DOCUMENTATION.md` - This guide

### 2. Update Your App Entry Point

Replace your ContentView with the new TapToneAnalysisView:

```swift
import SwiftUI

@main
struct GuitarTapApp: App {
    var body: some Scene {
        WindowGroup {
            TapToneAnalysisView()  // ← Use the tap tone UI
        }
    }
}
```

### 3. Verify Info.plist

Ensure you have microphone permissions:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app analyzes guitar tap tones by measuring frequency response from the microphone.</string>
```

### 4. Build and Run!

```
Product → Clean Build Folder (Cmd+Shift+K)
Product → Build (Cmd+B)
Product → Run (Cmd+R)
```

---

## 🎸 First Use

1. **Grant Microphone Permission** when prompted
2. **Tap "Start"** to begin analysis
3. **Tap your guitar** (bridge, soundhole, etc.)
4. **Watch peaks appear** in real-time
5. **Tap "Save"** to store measurement
6. **View "Measurements"** to see saved data

---

## 📊 What You'll See

### Main Screen

```
┌─────────────────────────────────────┐
│ [Start] [Save] [Reset]              │ ← Controls
├─────────────────────────────────────┤
│ ● Tap Detected!            -45.2 dB │ ← Tap indicator
├─────────────────────────────────────┤
│ Detected Peaks                      │
│  105.3 Hz    Q: 18.5    -45.2 dB   │ ← Top peaks
│  210.6 Hz    Q: 22.1    -48.1 dB   │
│  315.9 Hz    Q: 15.3    -52.4 dB   │
├─────────────────────────────────────┤
│ Identified Modes                    │
│  🌬️ Helmholtz (Air)     105.3 Hz   │ ← Auto-classified
│  🌳 Long-Grain          210.6 Hz   │
│  🔵 Monopole            315.9 Hz   │
├─────────────────────────────────────┤
│ Ring-Out Time                       │
│  1.85 seconds          Excellent   │ ← Decay measurement
├─────────────────────────────────────┤
│ Tap Tone Ratio                      │
│  2.03 : 1             Excellent    │ ← Stiffness ratio
├─────────────────────────────────────┤
│ [Peak Tracking Chart]               │ ← Frequency over time
└─────────────────────────────────────┘
```

---

## 🎯 Common Workflows

### Workflow 1: Testing Raw Top Plate

```swift
1. Hold plate by edges (at nodes)
2. Tap "Start"
3. Tap center of plate
4. Wait for peaks to stabilize
5. Save as "Raw Top - Cross Grain"
6. Rotate plate 90°
7. Tap again
8. Save as "Raw Top - Long Grain"
9. Compare the two measurements
```

### Workflow 2: Before/After Bracing

```swift
1. Test raw plate (save measurement)
2. Glue on braces
3. Test again after glue dries
4. Compare frequencies
   - Should shift higher (stiffer)
   - Ratio may change
5. Adjust brace height if needed
```

### Workflow 3: Final Voicing

```swift
1. Tap at multiple locations
   - Bridge
   - Soundhole
   - Upper bout
   - Lower bout
2. Save each location
3. Compare to target instrument
4. Scrape/sand to adjust modes
5. Re-test until satisfied
```

---

## ⚙️ Customization

### Adjust Sensitivity

If you're getting too many/few peaks:

```swift
// In TapToneAnalysisView or wherever you create TapToneAnalyzer:
tapToneAnalyzer.peakThreshold = -70  // More sensitive (more peaks)
// or
tapToneAnalyzer.peakThreshold = -50  // Less sensitive (fewer peaks)
```

### Change Frequency Range

For different analysis needs:

```swift
// Full range (guitars)
tapToneAnalyzer.minFrequency = 50
tapToneAnalyzer.maxFrequency = 2000

// Focus on fundamentals only
tapToneAnalyzer.minFrequency = 80
tapToneAnalyzer.maxFrequency = 400

// Include higher modes
tapToneAnalyzer.minFrequency = 50
tapToneAnalyzer.maxFrequency = 5000
```

### Adjust Decay Measurement

```swift
// Faster decay detection (useful for heavily damped guitars)
tapToneAnalyzer.decayThreshold = 15  // dB

// Slower decay detection (for highly resonant instruments)
tapToneAnalyzer.decayThreshold = 25  // dB
```

---

## 📱 Platform Support

### iPhone / iPad
✅ Full functionality  
✅ Tap with finger or stylus  
✅ Portrait and landscape  
✅ Save to Files app  

### Mac
✅ Full functionality  
✅ Use external mic or tap near built-in mic  
✅ Export to Desktop  
✅ Share via AirDrop  

---

## 🎨 Optional: Add to Existing App

If you want to add this to an existing app:

```swift
import SwiftUI

struct YourExistingApp: View {
    var body: some View {
        TabView {
            // Your existing views
            YourOriginalView()
                .tabItem {
                    Label("Spectrum", systemImage: "waveform")
                }
            
            // Add tap tone analysis
            TapToneAnalysisView()
                .tabItem {
                    Label("Tap Tone", systemImage: "hammer")
                }
        }
    }
}
```

---

## 🐛 Troubleshooting

### "No peaks detected"
- **Tap harder** (but not too hard!)
- **Lower threshold:** `peakThreshold = -70`
- **Check mic permissions**
- **Reduce background noise**

### "Tap not detected"
- **Tap more sharply** (quick impulse)
- **Check average magnitude** (should spike on tap)
- **Verify analyzer is running** (green dot)

### "Weird frequencies"
- **Check for background noise** (HVAC, fans)
- **Ensure guitar is free** (not touching anything)
- **Tap cleanly** (single sharp tap, not rubbing)

### "No decay measurement"
- **Need stronger tap** (higher peak magnitude)
- **Wait longer** (measurement takes a few seconds)
- **Reduce background noise**

---

## 📈 Understanding Your Results

### Good Results Look Like:

✅ **Sharp, distinct peaks** at expected frequencies  
✅ **High Q factors** (>15) for main modes  
✅ **Decay time 1-2 seconds** for quality guitar  
✅ **Tap tone ratio 1.9-2.1**  
✅ **Stable frequencies** in tracking chart  

### Problem Signs:

⚠️ **Multiple overlapping peaks** - May indicate loose parts  
⚠️ **Very broad peaks (low Q)** - Heavy damping  
⚠️ **Decay < 0.5s** - Too thick or heavy bracing  
⚠️ **Ratio < 1.5 or > 2.5** - Imbalanced stiffness  
⚠️ **Unstable frequencies** - Inconsistent tapping  

---

## 💾 Data Management

### Export Data

1. Tap **"Measurements"**
2. Tap **Export button** (↑)
3. See JSON data
4. Tap **Share** to send via:
   - Email
   - AirDrop
   - Files app
   - Notes app

### Import Data

1. Copy JSON text
2. Create import button in your UI (optional feature)
3. Call `tapToneAnalyzer.importMeasurements(json: jsonString)`

### Backup Measurements

Export to:
- **iCloud Drive** - Automatic backup
- **Email** - Send to yourself
- **Dropbox/Google Drive** - Cloud storage
- **Git repository** - Version control for serious lutherie!

---

## 🎓 Next Steps

1. **Read the full documentation:** `TAP_TONE_DOCUMENTATION.md`
2. **Experiment with different guitars** to see variations
3. **Build a reference library** of quality instruments
4. **Track construction progress** plate → assembly → voicing
5. **Compare your builds** to professional instruments

---

## 🎸 Example Measurement Session

```
Day 1: Raw Plates
├─ Top Plate - Cross Grain: 102 Hz
├─ Top Plate - Long Grain: 205 Hz  
├─ Ratio: 2.01 ✓ Excellent
└─ Notes: "Sitka spruce, 0.100" thick"

Day 7: After Bracing
├─ Top Plate - Bridge: 235 Hz (was 205)
├─ Shift: +30 Hz ✓ Expected
└─ Notes: "Scalloped X-bracing installed"

Day 14: Assembled Body
├─ Helmholtz: 98 Hz
├─ Monopole: 245 Hz
├─ Dipole: 405 Hz
└─ Notes: "Body complete, before final voicing"

Day 21: Final
├─ All modes present
├─ Decay time: 1.9s ✓ Excellent
└─ Notes: "Voicing complete, ready for finish"
```

---

## ✨ That's It!

You now have a **complete professional tap tone analysis system** for lutherie! 🎸🔬

**Features:**
- ✅ 0.67 Hz resolution
- ✅ Multi-peak detection
- ✅ Automatic mode classification
- ✅ Decay measurement
- ✅ Tap tone ratio
- ✅ History tracking
- ✅ Save/export data
- ✅ Professional UI

**Happy building!** 🔨✨
