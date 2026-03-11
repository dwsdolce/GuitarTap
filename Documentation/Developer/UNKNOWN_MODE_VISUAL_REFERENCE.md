# Unknown Peak Mode - Visual Reference Guide

## Color Scheme Comparison

### Known Modes
| Mode | Color | Icon | Abbreviation |
|------|-------|------|--------------|
| Helmholtz | Cyan | `wind` | HH |
| Cross-Grain | Blue | `arrow.left.and.right` | XG |
| Long-Grain | Green | `arrow.up.and.down` | LG |
| Monopole | Orange | `circle.fill` | MP |
| Dipole | Red | `circle.lefthalf.filled` | DP |
| Ring Mode | Purple | `circle.dashed` | Ring |
| Upper Modes | Gray | `waveform` | Upper |

### Unknown Mode ⭐
| Mode | Color | Icon | Abbreviation |
|------|-------|------|--------------|
| **Unknown** | **Secondary (Gray)** | **`questionmark.circle`** | **?** |

---

## Example Peak Display

### Scenario: Guitar Tap with Unknown Resonance at 150 Hz

```
Detected Peaks (sorted by magnitude):

1. ┌──────────────────────────────────────┐
   │ [wind] Helmholtz (Air)    98.5 Hz   │ ← CYAN
   │ 🎵 G2 (+15 ¢)                        │
   │ Q: 12.5  BW: 7.9 Hz      -42.1 dB   │
   │ ✓ In range                           │
   └──────────────────────────────────────┘

2. ┌──────────────────────────────────────┐
   │ [?] Unknown              150.0 Hz    │ ← GRAY ⭐
   │ 🎵 D3 (-8 ¢)                         │
   │ Q: 8.2  BW: 18.3 Hz      -48.5 dB   │
   │ (no range indicator)                 │
   └──────────────────────────────────────┘

3. ┌──────────────────────────────────────┐
   │ [↕] Long-Grain           195.2 Hz    │ ← GREEN
   │ 🎵 G3 (+2 ¢)                         │
   │ Q: 10.3  BW: 18.9 Hz     -45.8 dB   │
   │ ✓ In range                           │
   └──────────────────────────────────────┘
```

---

## Chart Annotation Appearance

### Known Mode (e.g., Helmholtz at 98.5 Hz)
```
     ┌─────────────┐
     │ Helmholtz   │ ← Cyan text
     │ ♪ G2        │ ← Purple music note
     │ +15 ¢       │ ← Purple cents
     │ 98.5 Hz     │ ← Black text
     │ -42.1 dB    │ ← Gray text
     └─────────────┘
          ↑
          │ ← Cyan dashed line
          │
          ● ← Cyan dot on chart
```

### Unknown Mode (e.g., at 150.0 Hz) ⭐
```
     ┌─────────────┐
     │ Unknown     │ ← Gray text
     │ ♪ D3        │ ← Purple music note
     │ -8 ¢        │ ← Purple cents
     │ 150.0 Hz    │ ← Black text
     │ -48.5 dB    │ ← Gray text
     └─────────────┘
          ↑
          │ ← Gray dashed line
          │
          ● ← Gray dot on chart
```

---

## Full Spectrum View

```
Frequency (Hz) →
─────────────────────────────────────────────────────────────────

0-84 Hz:      [?????] ← Unknown region (sub-bass)

85-115 Hz:    [■■■■■] ← Helmholtz (Cyan)

116-179 Hz:   [?????] ← Unknown region (gap) ⭐

180-220 Hz:   [■■■■■] ← Long-Grain (Green)

221-349 Hz:   [?????] ← Unknown region (gap) ⭐

350-450 Hz:   [■■■■■] ← Dipole (Red)

451-599 Hz:   [?????] ← Unknown region (gap) ⭐

600-850 Hz:   [■■■■■] ← Ring Mode (Purple)

850+ Hz:      [■■■■■] ← Upper Modes (Gray)

─────────────────────────────────────────────────────────────────

Legend:
[■■■■■] = Known mode range (colored)
[?????] = Unknown/unclassified range (gray) ⭐
```

---

## Real-World Example Output

### Typical Guitar Tap (with anomaly at 145 Hz)

```
═══════════════════════════════════════════════════════════════
                      ANALYSIS RESULTS
═══════════════════════════════════════════════════════════════

DETECTED PEAKS: 6 total

┌─ Known Modes (5) ──────────────────────────────────────────┐
│                                                             │
│  98.5 Hz   [Helmholtz]   G2 (+15¢)   -42.1 dB   [CYAN]   │
│ 195.2 Hz   [Long-Grain]  G3 (+2¢)    -45.8 dB   [GREEN]  │
│ 245.0 Hz   [Monopole]    B3 (-12¢)   -51.2 dB   [ORANGE] │
│ 390.5 Hz   [Dipole]      G4 (+18¢)   -48.9 dB   [RED]    │
│ 720.0 Hz   [Ring Mode]   F#5 (+5¢)   -55.3 dB   [PURPLE] │
│                                                             │
└─────────────────────────────────────────────────────────────┘

┌─ Unknown Peaks (1) ────────────────────────────────────────┐
│                                                             │
│ 145.0 Hz   [Unknown]     D3 (-8¢)    -48.5 dB   [GRAY] ⭐ │
│                                                             │
│ ⚠️  Note: This peak is outside known guitar mode ranges.   │
│    Possible causes:                                         │
│    • Structural resonance (loose brace?)                   │
│    • Environmental interference                             │
│    • Harmonic interaction                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘

TAP TONE RATIO: 1.98 : 1  [IDEAL] ✓

RING-OUT TIME: 1.25 seconds  [GOOD]

═══════════════════════════════════════════════════════════════
```

---

## Interaction Behaviors

### Chart Annotation (Unknown Peak)
- **Hover**: Highlight with gray border
- **Drag**: Reposition label (same as known modes)
- **Right-click/Long-press**: Reset to default position
- **Tooltip**: "Unknown (Unclassified frequency)"

### Results Panel Row (Unknown Peak)
- **Click**: No special action (same as known modes)
- **No range indicator**: Unknown has no "ideal range"
- **Gray background**: `mode.color.opacity(0.05)` with secondary color
- **Question mark icon**: Distinguishes from known modes

### Export Behavior
```json
{
  "peaks": [
    {
      "frequency": 145.0,
      "magnitude": -48.5,
      "quality": 8.2,
      "bandwidth": 18.3,
      "pitchNote": "D3",
      "pitchCents": -8.0,
      "pitchFrequency": 146.832
      // Mode classification happens during import via classify()
    }
  ]
}
```

---

## Diagnostic Value

### What Unknown Peaks Can Reveal

#### ✅ **Normal Scenarios**
- **Harmonics**: Natural overtones from string vibration
- **Room modes**: Environmental acoustic resonances
- **Test artifacts**: Microphone placement, mounting effects

#### ⚠️ **Potential Issues**
- **Loose braces**: Rattling or buzzing at odd frequencies
- **Cracks**: Structural damage creates anomalous peaks
- **Glue failure**: Separation between components
- **Material defects**: Internal voids or inconsistencies

#### 🔬 **Research Opportunities**
- **Non-standard designs**: Alternative bracing patterns
- **Experimental materials**: Composite or synthetic tops
- **Acoustic coupling**: Interaction between components
- **Frequency response**: Complete spectral analysis

---

## Configuration Tips

### To Minimize Unknown Peaks (Focus on Guitar Modes)
```
Settings:
  Peak Threshold: -50 dB (higher = fewer weak peaks)
  Min Frequency: 80 Hz (skip sub-bass)
  Max Frequency: 1000 Hz (skip high harmonics)
  
Result: Mostly known guitar modes detected
```

### To Maximize Unknown Peaks (Complete Analysis)
```
Settings:
  Peak Threshold: -70 dB (lower = more weak peaks)
  Min Frequency: 20 Hz (include sub-bass)
  Max Frequency: 5000 Hz (include high harmonics)
  
Result: All significant resonances detected
```

### Balanced Approach (Recommended)
```
Settings:
  Peak Threshold: -60 dB (default)
  Min Frequency: 50 Hz
  Max Frequency: 2000 Hz
  
Result: Guitar modes + significant anomalies
```

---

## Summary

### Unknown Mode Characteristics
- **Color**: Gray (secondary)
- **Icon**: Question mark circle (?)
- **Purpose**: Capture all significant peaks
- **Frequency**: Outside known mode ranges
- **Display**: Same detail as known modes
- **Analysis**: Full Q-factor, bandwidth, pitch data

### When You'll See Unknown Peaks
1. Frequencies below 85 Hz (sub-bass)
2. Gaps between known modes (116-179 Hz, 221-349 Hz, etc.)
3. Structural anomalies at any frequency
4. Environmental interference
5. Harmonic overtones outside classified ranges

### Why They're Important
- **Quality control**: Detect structural issues
- **Research**: Complete acoustic analysis
- **Diagnosis**: Identify problem frequencies
- **Documentation**: Comprehensive measurements

**Unknown peaks = Complete spectrum coverage!** 🎯
