# 🎸 Tap Tone Analysis System Documentation

## Overview

A professional lutherie tool for analyzing guitar resonances through tap tone testing. Uses 65536-point FFT for **0.67 Hz frequency resolution** to precisely identify and track resonant modes in guitar construction.

---

## ✨ Features Implemented

### 1. **Multi-Peak Detection** 
✅ Finds all significant peaks above threshold  
✅ Calculates Q factor (sharpness) for each peak  
✅ Measures -3dB bandwidth  
✅ Configurable number of peaks to track (default: 10)  
✅ Automatic local maximum detection with windowing

### 2. **Mode Classification**
✅ Automatic identification of guitar modes:
- **Helmholtz (85-115 Hz)** - Air resonance through soundhole
- **Cross-Grain (90-120 Hz)** - Stiffness across wood grain
- **Long-Grain (180-220 Hz)** - Stiffness along wood grain  
- **Monopole (200-280 Hz)** - Top and back moving together
- **Dipole (350-450 Hz)** - Top and back moving opposite
- **Ring Mode (600-850 Hz)** - Circular mode around soundhole
- **Upper Modes (850+ Hz)** - Higher order resonances

### 3. **Decay Time Measurement**
✅ Automatic tap detection (20 dB sudden increase)  
✅ Ring-out time measurement (configurable threshold)  
✅ Quality assessment (Short/Good/Excellent/Very Long)  
✅ Visual indicator for tap events  
✅ Cooldown period to prevent double-detection

### 4. **Tap Tone Ratio**
✅ Calculates Long-Grain / Cross-Grain ratio  
✅ Ideal ratio: **1.9 - 2.1** (indicates proper stiffness balance)  
✅ Quality assessment (Excellent/Good/Fair/Needs Work)  
✅ Visual color coding (Green/Blue/Orange/Red)

### 5. **Peak History Tracking**
✅ Tracks peak frequencies over time  
✅ Interactive chart showing frequency stability  
✅ Color-coded by mode type  
✅ Stores last 100 measurements  
✅ Real-time visualization of mode evolution

### 6. **Measurement Management**
✅ Save measurements with metadata:
  - Tap location (Bridge, Soundhole, Upper Bout, etc.)
  - Notes/observations
  - Full spectrum snapshot
  - Timestamp
  - All detected peaks
  - Decay time
  
✅ Compare current vs. saved measurements  
✅ Export to JSON format  
✅ Import saved measurements  
✅ Delete individual measurements  
✅ Share data via system share sheet

### 7. **Real-Time Analysis**
✅ Live peak detection while tapping  
✅ Immediate mode identification  
✅ Continuous decay tracking  
✅ Average magnitude monitoring  
✅ Visual tap detection indicator

---

## 🎯 Usage Guide

### Basic Workflow

1. **Start Analyzer**
   - Tap "Start" button
   - Grant microphone permissions if needed
   - Wait for "Waiting for tap..." indicator

2. **Tap the Guitar**
   - Use knuckle or small rubber mallet
   - Tap different locations:
     - **Bridge** - Primary structural modes
     - **Soundhole** - Air resonance
     - **Upper Bout** - Cross-grain modes
     - **Lower Bout** - Long-grain modes
     - **Center of Top** - Monopole mode

3. **Analyze Results**
   - Check "Detected Peaks" - Top 5 resonances
   - Review "Identified Modes" - Classified by type
   - Monitor "Ring-Out Time" - Damping quality
   - Calculate "Tap Tone Ratio" - Stiffness balance

4. **Save Measurement**
   - Tap "Save" button
   - Enter tap location (optional)
   - Add notes about construction stage
   - Measurement saved with full data

5. **Compare Over Time**
   - View "Measurements" list
   - Compare before/after bracing changes
   - Track mode shifts during construction
   - Export data for external analysis

---

## 📊 Interpreting Results

### Peak Magnitude
- **> -40 dB** (Green) - Strong resonance, good energy transfer
- **-60 to -40 dB** (Blue) - Moderate resonance
- **-80 to -60 dB** (Orange) - Weak resonance
- **< -80 dB** (Red) - Very weak, may indicate damping issues

### Q Factor (Quality)
- **High Q (>20)** - Sharp, narrow peak = low damping, pure tone
- **Medium Q (10-20)** - Normal damping
- **Low Q (<10)** - Broad peak = high damping, may indicate issues

### Decay Time
- **< 0.5s** (Very Short) - Heavy damping, may need thinner top
- **0.5-1.0s** (Short) - Moderate damping
- **1.0-2.0s** (Good) - Normal for quality acoustic guitar
- **2.0-3.0s** (Excellent) - Low damping, great sustain
- **> 3.0s** (Very Long) - Very light damping, may be too thin

### Tap Tone Ratio
- **1.9-2.1** (Excellent) - Ideal stiffness balance
- **1.7-1.9 or 2.1-2.3** (Good) - Acceptable range
- **1.5-1.7 or 2.3-2.5** (Fair) - May need adjustment
- **< 1.5 or > 2.5** (Needs Work) - Imbalanced stiffness

---

## 🛠️ Configuration

### In TapToneAnalyzer:

```swift
// Adjust these properties as needed:
tapToneAnalyzer.peakThreshold = -60       // Minimum peak magnitude (dB)
tapToneAnalyzer.minFrequency = 50         // Lowest frequency to analyze
tapToneAnalyzer.maxFrequency = 2000       // Highest frequency to analyze
tapToneAnalyzer.maxPeaks = 10             // Number of peaks to track
tapToneAnalyzer.decayThreshold = 20       // dB below peak for decay measurement
```

### FFT Settings:

```swift
// In your initialization:
RealtimeFFTAnalyzer(
    fftSize: 65536,              // Do not change! Required for resolution
    targetSampleRate: 48000,     // 48000 or 44100
    useHardwareSampleRate: true  // Use device's native rate
)
```

---

## 🎸 Guitar Mode Reference

### Bare Top Plate (Before Assembly)

**Cross-Grain Mode** (90-110 Hz)
- Stiffness perpendicular to grain
- Lower = more flexible top
- Affected by: top thickness, wood species

**Long-Grain Mode** (180-220 Hz)  
- Stiffness parallel to grain
- Should be ~2× cross-grain
- Affected by: grain orientation, bracing

**Target Ratios:**
- Spruce top: 1.95-2.05
- Cedar top: 1.90-2.00
- Mahogany top: 1.85-1.95

### Assembled Guitar

**Helmholtz Resonance** (95-105 Hz)
- Air pumping through soundhole
- Lower = larger body cavity
- Formula: f = (c/2π) × √(A/(V×L))
  - A = soundhole area
  - V = body volume  
  - L = effective length (top thickness)

**Monopole Mode** (220-260 Hz)
- Top and back vibrating in phase
- "Breathing" mode
- Should be strong and clear

**Dipole Mode** (380-420 Hz)
- Top and back vibrating opposite
- "Pumping" mode
- Affects midrange response

**Ring Mode** (650-750 Hz)
- Circular mode around soundhole
- Affects treble clarity
- Should be present but not dominant

---

## 📁 Data Export Format

Measurements export as JSON with full details:

```json
{
  "id": "UUID",
  "timestamp": "2026-01-25T...",
  "peaks": [
    {
      "frequency": 105.3,
      "magnitude": -45.2,
      "quality": 18.5,
      "bandwidth": 5.7
    }
  ],
  "decayTime": 1.85,
  "tapLocation": "Bridge",
  "notes": "After final voicing",
  "tapToneRatio": 2.03
}
```

---

## 🔬 Advanced Usage

### Tracking Construction Progress

1. **Raw Top Plate**
   - Measure cross-grain and long-grain
   - Calculate initial ratio
   - Save as baseline

2. **After Bracing**
   - Modes shift higher (stiffer)
   - Ratio may change
   - Compare to raw plate

3. **After Assembly**
   - New modes appear (Helmholtz, etc.)
   - Body coupling affects all modes
   - Compare to target instrument

4. **After Voicing**
   - Fine-tune mode frequencies
   - Optimize decay times
   - Final comparison to goals

### Troubleshooting Issues

**No Peaks Detected:**
- Lower `peakThreshold` (try -70 dB)
- Tap harder
- Check microphone permissions
- Ensure analyzer is running

**Erratic Peaks:**
- Tap more gently
- Reduce background noise
- Wait for previous tap to decay
- Check for loose parts on guitar

**Low Decay Time:**
- Top too thick or heavily damped
- Bracing too heavy
- Wood density too high
- Check for contact points

**Wrong Tap Tone Ratio:**
- < 1.5: Top too stiff cross-grain
- > 2.5: Top too stiff long-grain  
- Adjust thickness or bracing accordingly

---

## 🎯 Professional Tips

1. **Consistency** - Always tap same location with same force
2. **Environment** - Quiet room, no fans or HVAC noise
3. **Support** - Hold plate/guitar consistently (nodes vs. antinodes)
4. **Mallet** - Use consistent tapping tool (knuckle, small mallet)
5. **Temperature** - Wood properties change with humidity/temp
6. **Multiple Taps** - Average 3-5 measurements per location
7. **Document** - Save measurements at every construction stage

---

## 📚 Mode Shapes (Visual Reference)

```
CROSS-GRAIN MODE (~100 Hz)
  ╔═══════════╗
  ║ ↑       ↑ ║  Top vibrates side-to-side
  ║ ↓       ↓ ║  Node line along center
  ╚═══════════╝

LONG-GRAIN MODE (~200 Hz)
  ╔═══════════╗
  ║ ←   →   ← ║  Top vibrates end-to-end
  ║ ←   →   ← ║  Node line across center
  ╚═══════════╝

MONOPOLE MODE (~240 Hz)
  ╔═══════════╗
  ║ ↑↑↑↑↑↑↑↑↑ ║  Top and back move together
  ║ ↑↑↑↑↑↑↑↑↑ ║  No nodes
  ╚═══════════╝

DIPOLE MODE (~400 Hz)
  ╔═══════════╗
  ║ ↑↑↑   ↓↓↓ ║  Top and back opposite
  ║ ↑↑↑   ↓↓↓ ║  Node in center
  ╚═══════════╝

RING MODE (~700 Hz)
  ╔═══════════╗
  ║ ↻  ( )  ↺ ║  Circular motion around hole
  ║ ↺  ( )  ↻ ║  Node at soundhole
  ╚═══════════╝
```

---

## 🎼 Musical Context

Mode frequencies relate to musical notes:

- **95 Hz** ≈ G2 (bass E string, 3rd fret)
- **100 Hz** ≈ G2 (typical cross-grain)
- **110 Hz** = A2 (open A string)
- **200 Hz** ≈ G3 (open G string)
- **240 Hz** ≈ B3 (open B string)
- **400 Hz** ≈ G4 (high E string, 3rd fret)

Body resonances enhance notes at these frequencies!

---

## 🚀 Quick Reference

### Ideal Target Ranges

| Mode | Frequency | Quality | 
|------|-----------|---------|
| Cross-Grain | 95-110 Hz | Sharp peak |
| Long-Grain | 190-210 Hz | Sharp peak |
| Ratio | 1.9-2.1 | - |
| Helmholtz | 95-105 Hz | Medium peak |
| Monopole | 220-260 Hz | Strong peak |
| Dipole | 380-420 Hz | Medium peak |
| Ring | 650-750 Hz | Weak peak |

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Ratio < 1.5 | Stiff cross-grain | Thin sides more |
| Ratio > 2.5 | Stiff long-grain | Adjust bracing |
| Decay < 0.5s | Heavy damping | Thin top |
| Decay > 3.0s | Very light | Add mass |
| No Helmholtz | Soundhole blocked | Check assembly |
| Multiple peaks close | Coupled modes | Normal in assembly |

---

## 📱 UI Features

✅ Real-time tap detection indicator  
✅ Top 5 peaks with magnitude/Q/bandwidth  
✅ Automatic mode classification with icons  
✅ Color-coded quality indicators  
✅ Peak frequency tracking chart  
✅ Decay time with quality assessment  
✅ Tap tone ratio calculator  
✅ Save measurements with notes  
✅ Compare measurements  
✅ Export/import JSON data  
✅ Swipe to delete measurements  
✅ Share functionality

---

## 🎓 Learning Resources

**Recommended Reading:**
- "Tap Tuning" by Roger Siminoff
- "Guitar Making: Tradition and Technology" - William Cumpiano
- "The Responsive Guitar" - Ervin Somogyi

**Key Concepts:**
- Modal analysis in acoustics
- Coupled oscillator systems
- Chladni patterns (mode visualization)
- Frequency response optimization
- Wood mechanics and stiffness

---

## ✨ Summary

You now have a **professional-grade tap tone analysis system** with:

- ✅ 0.67 Hz frequency resolution  
- ✅ Multi-peak detection with Q factor
- ✅ Automatic mode classification
- ✅ Decay time measurement
- ✅ Tap tone ratio calculation
- ✅ Peak history tracking
- ✅ Measurement management
- ✅ Export/import capabilities
- ✅ Before/after comparison

**Perfect for lutherie work from raw plates through final voicing!** 🎸🔨

---

**Created: January 25, 2026**  
**Version: 1.0**  
**For: GuitarTap - Professional Tap Tone Analysis**
