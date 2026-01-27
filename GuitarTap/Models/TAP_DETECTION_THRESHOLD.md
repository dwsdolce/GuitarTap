# Adjustable Tap Detection Threshold Feature

## Overview

Added a configurable tap detection threshold with visual feedback to help users tune sensitivity and avoid missing taps.

## Problem Solved

**Issue**: Too many taps were being missed due to fixed 20 dB threshold
**Solution**: Adjustable threshold (5-40 dB) with visual indicator showing detection level

## New Features

### 1. **Adjustable Sensitivity Slider**

**Location**: Tap sequence controls (when analyzer running)

**Range**: 5-40 dB
- **Low** (40 dB): Less sensitive, requires loud/hard taps
- **High** (5 dB): More sensitive, detects lighter taps
- **Default**: 20 dB (balanced)

**UI Control**:
```
Tap sensitivity:
Low ═══●═══════════════ High    20 dB
```

### 2. **Visual Threshold Line on Spectrum**

**Appearance**: Orange dashed line across spectrum chart
**Label**: "Tap threshold: -35 dB" (example)
**Shows**: Current detection level (recent average + threshold)
**Updates**: Real-time as signal changes

## How It Works

### Detection Logic

```swift
// Calculate recent average
recentAvg = last 5 peak magnitudes averaged

// Calculate detection level
tapDetectionLevel = recentAvg + tapDetectionThreshold

// Detect tap
if currentPeakMagnitude > tapDetectionLevel {
    // TAP DETECTED! 🎯
}
```

### Example

```
Recent average: -55 dB
Threshold setting: 20 dB
Detection level: -35 dB  ← Shown on chart

Current peak: -40 dB → No tap (below -35)
Current peak: -30 dB → TAP! (above -35)
```

## UI Components

### Slider Control

```
┌─ Tap Sensitivity ─────────────────────────────┐
│ Tap sensitivity:                              │
│ Low ═══════════●═════ High        20 dB      │
└───────────────────────────────────────────────┘
```

**Features**:
- Slider from 5 to 40 dB
- Step size: 1 dB
- Current value displayed in blue
- "Low" and "High" labels for context

### Visual Threshold Line

```
┌─ Spectrum Chart ──────────────────────────────┐
│                                               │
│  ↑                                            │
│ 0├─────────────────────────────────────       │
│  │                                            │
│  │          ╱╲                                │
│  │         ╱  ╲                               │
│  │        ╱    ╲                              │
│  │       ╱      ╲╱╲                           │
│  │      ╱          ╲                          │
│  ├─ ─ ─ ─ ─ ─ ─ ─ ─ ─  Tap threshold: -35 dB │ ← Orange dashed line
│  │     ╱                 ╲                    │
│  │    ╱                    ╲                  │
│-100──────────────────────────────────         │
│  └────────────────────────────────→           │
└───────────────────────────────────────────────┘
```

**Line Characteristics**:
- **Style**: Dashed (5pt dash, 3pt gap)
- **Color**: Orange (70% opacity)
- **Width**: 2pt
- **Label**: White background with orange text
- **Position**: Dynamically calculated based on dB scale

### Only Shows When:
- ✅ Analyzer is running
- ✅ Detection is active (`isDetecting = true`)
- ✅ Threshold is within visible range (`minDB < level < maxDB`)
- ❌ Hidden when frozen or stopped

## User Workflow

### Adjusting Sensitivity

1. **Start analyzer** (click [Start])
2. **Tap guitar** to see current level
3. **Watch**: Does orange line appear above or below spectrum peaks?
4. **Adjust slider**:
   - If missing taps: Move slider toward "High" (lower dB)
   - If too sensitive: Move slider toward "Low" (higher dB)
5. **Test**: Tap again and verify detection
6. **Fine-tune**: Adjust until reliable

### Recommended Settings

| Use Case | Threshold | Description |
|----------|-----------|-------------|
| **Soft taps** | 5-10 dB | Detect light touches |
| **Normal taps** | 15-25 dB | Balanced (default: 20) |
| **Hard taps only** | 30-40 dB | Ignore accidental noise |

### Environment-Specific

| Environment | Recommended | Reason |
|-------------|-------------|---------|
| **Quiet room** | 10-15 dB | Low ambient noise |
| **Normal room** | 20-25 dB | Some background noise |
| **Noisy environment** | 30-40 dB | High noise floor |

## Implementation Details

### New Properties (TapToneAnalyzer)

```swift
@Published var tapDetectionThreshold: Float = 20.0  // Configurable (5-40 dB)
@Published var tapDetectionLevel: Float = -100      // Current threshold level
```

### Updated Detection Logic

**Before**:
```swift
if peakMagnitude > recentAvg + 20 {  // Fixed 20 dB
    // Detect tap
}
```

**After**:
```swift
tapDetectionLevel = recentAvg + tapDetectionThreshold
if peakMagnitude > tapDetectionLevel {
    // Detect tap
}
```

### Visual Overlay

**Geometry Calculation**:
```swift
// Normalize threshold position to chart coordinates
normalizedPosition = (tapDetectionLevel - minDB) / (maxDB - minDB)
yPosition = chartHeight * (1 - normalizedPosition) + padding
```

**Conditional Rendering**:
```swift
// Only show if within visible range
if tapDetectionLevel > minDB && tapDetectionLevel < maxDB {
    // Draw threshold line and label
}
```

## Console Output

### Before Adjustment
```
🎯 Tap detected! Peak: -30.5 dB (threshold: -35.0 dB)
```

### After Adjustment (threshold = 15 dB)
```
🎯 Tap detected! Peak: -40.2 dB (threshold: -45.0 dB)
```

**Note**: Console now shows exact threshold value used

## Testing

### Test 1: Verify Visual Line
```
1. Start analyzer
2. Wait for spectrum to appear
3. See orange dashed line appear
4. Line should move with signal level changes
```

### Test 2: Adjust Sensitivity
```
1. Set slider to 10 dB (high sensitivity)
2. Tap lightly
3. Verify detection (green "Tap Detected!" flash)
4. Set slider to 35 dB (low sensitivity)
5. Tap lightly again
6. Verify no detection
7. Tap hard
8. Verify detection
```

### Test 3: Line Visibility Range
```
1. Start analyzer
2. See threshold line
3. Adjust magnitude range controls
4. Set maxDB below threshold
5. Line disappears (out of range)
6. Reset range
7. Line reappears
```

### Test 4: Frozen Spectrum
```
1. Complete tap sequence (spectrum freezes)
2. Threshold line disappears (detection paused)
3. Click [Resume]
4. Line reappears (detection active)
```

## Benefits

### 1. **Visual Feedback**
- See exactly where threshold is
- Understand why taps are/aren't detected
- No guesswork

### 2. **Environment Adaptation**
- Adjust for quiet vs. noisy rooms
- Compensate for different guitar volumes
- Handle various tapping techniques

### 3. **Fewer Missed Taps**
- Fine-tune to your specific setup
- Detect light taps when needed
- Ignore background noise

### 4. **Real-Time Adjustment**
- No need to restart
- Immediate visual feedback
- Test different values quickly

## Troubleshooting

### Threshold Line Not Showing

**Possible causes**:
1. Analyzer not running
2. Detection paused (spectrum frozen)
3. Threshold outside visible range

**Fix**:
- Click [Start]
- Click [Resume] if frozen
- Adjust magnitude range to include threshold

### Still Missing Taps

**Possible causes**:
1. Threshold too high
2. Tapping too softly
3. Noisy signal

**Fix**:
- Lower threshold (move slider toward "High")
- Tap harder
- Move closer to microphone
- Reduce background noise

### Too Many False Detections

**Possible causes**:
1. Threshold too low
2. Noisy environment
3. Handling guitar creates spikes

**Fix**:
- Raise threshold (move slider toward "Low")
- Quiet environment
- Hold guitar still between taps

### Line Position Seems Wrong

**Check**:
- dB range settings
- Threshold value in console
- Recent signal levels

**Debug**:
```
Console shows:
"🎯 Tap detected! Peak: -30 dB (threshold: -35 dB)"

If threshold is -35 dB:
- Should see line at -35 dB on chart
- Peak (-30) should be above line
```

## Advanced Tips

### Optimal Threshold Selection

1. **Baseline**: Start at 20 dB (default)
2. **Test**: Tap with normal force
3. **Observe**: Is orange line above or below peaks?
4. **Adjust**: 
   - Line too high? Lower threshold
   - Line too low? Raise threshold
5. **Target**: Line should be just below your tap peaks

### Different Guitars

| Guitar Type | Recommended | Reason |
|-------------|-------------|---------|
| **Acoustic** | 15-25 dB | Naturally loud |
| **Classical** | 10-20 dB | Softer response |
| **Solid body** | 25-35 dB | Quiet without amp |

### Tapping Locations

| Location | Adjust | Reason |
|----------|--------|---------|
| **Bridge** | Lower threshold | Loudest response |
| **Soundhole** | Default | Moderate response |
| **Upper bout** | Raise threshold | Quieter response |

## Persistence

**Current**: Threshold resets to 20 dB on app restart

**Future Enhancement**: Could save preference:
```swift
@AppStorage("tapDetectionThreshold") var tapDetectionThreshold: Float = 20.0
```

## Summary

✅ **Adjustable slider** (5-40 dB range)
✅ **Visual threshold line** on spectrum (orange dashed)
✅ **Real-time position** updates with signal
✅ **Clear labeling** showing current threshold
✅ **Conditional display** (only when detecting)
✅ **Improved detection** fewer missed taps!

This feature gives users complete control over tap sensitivity with immediate visual feedback, making it easy to tune the analyzer for any situation. 🎸🎯
