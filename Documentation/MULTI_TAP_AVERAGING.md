# Multi-Tap Averaging Feature

## Overview

The `TapToneAnalyzer` now supports **multi-tap averaging** to improve measurement accuracy and reduce the impact of inconsistent tapping technique or environmental noise.

## New Features

### 1. **Automatic Tap Detection Pause**
When a tap is detected, peak detection automatically stops to avoid analyzing transient noise or secondary reflections.

### 2. **Multi-Tap Sequence**
Configure the analyzer to capture multiple taps (1-10) and average the results for more reliable measurements.

### 3. **Smart Peak Averaging**
Peaks from multiple taps are intelligently grouped by frequency (±5 Hz tolerance) and averaged for:
- Frequency
- Magnitude
- Quality factor (Q)
- Bandwidth

### 4. **Progress Tracking**
Real-time feedback on tap sequence progress with status messages and completion percentage.

## New Configuration Properties

### `numberOfTaps: Int` (default: 1)
Number of taps to capture and average.

**Recommendations**:
- **1 tap**: Quick analysis, single measurement
- **3 taps**: Good balance of speed and accuracy (recommended)
- **5 taps**: High accuracy for quality control
- **10 taps**: Maximum accuracy for research

### `captureWindow: TimeInterval` (default: 0.2 seconds)
Time window after tap to capture spectrum data during ring-out.

**Recommendations**:
- **0.1s**: Fast taps, minimal ring-out
- **0.2s**: Standard (recommended)
- **0.5s**: Long sustain instruments

## New Published Properties

### `isDetecting: Bool`
Indicates whether tap detection is currently active.

**States**:
- `true`: Listening for taps
- `false`: Processing captured data or paused

### `currentTapCount: Int`
Number of taps captured in current sequence (0 to `numberOfTaps`).

### `tapProgress: Float`
Progress of tap sequence as percentage (0.0 to 1.0).

**Example**: With 5 taps configured:
- After 1st tap: `0.2` (20%)
- After 3rd tap: `0.6` (60%)
- After 5th tap: `1.0` (100%)

### `statusMessage: String`
Human-readable status for UI display.

**Example messages**:
- "Ready to detect taps"
- "Tap the guitar 3 times..."
- "Tap 2/3 captured. Tap again..."
- "All taps captured. Processing..."
- "Analysis complete! 8 peaks identified."

## New Control Methods

### `startTapSequence()`
Start a new tap detection sequence.

**Usage**:
```swift
// Configure number of taps
tapToneAnalyzer.numberOfTaps = 3

// Start sequence
tapToneAnalyzer.startTapSequence()

// Now tap the guitar 3 times...
```

**What it does**:
1. Clears previous data
2. Resets tap count to 0
3. Enables detection
4. Updates status message

### `cancelTapSequence()`
Cancel current sequence and restart detection.

**Usage**:
```swift
tapToneAnalyzer.cancelTapSequence()
```

**What it does**:
1. Discards captured taps
2. Resets counters
3. Re-enables detection
4. Clears results

### `resumeDetection()`
Resume detection after completing a sequence.

**Usage**:
```swift
// After analysis is complete
tapToneAnalyzer.resumeDetection()
```

**What it does**:
1. Clears captured data
2. Resets counters
3. Re-enables detection
4. Ready for new sequence

## Workflow Examples

### Example 1: Single Tap (Quick Analysis)

```swift
// Configure
analyzer.numberOfTaps = 1

// Start
analyzer.startTapSequence()

// User taps once
// ↓
// Results appear immediately
```

### Example 2: Three-Tap Average (Recommended)

```swift
// Configure
analyzer.numberOfTaps = 3

// Start
analyzer.startTapSequence()
// Status: "Tap the guitar 3 times..."

// User taps (1st)
// Status: "Tap 1/3 captured. Tap again..."
// tapProgress = 0.33

// User taps (2nd)
// Status: "Tap 2/3 captured. Tap again..."
// tapProgress = 0.67

// User taps (3rd)
// Status: "All taps captured. Processing..."
// tapProgress = 1.0
// ↓
// Averaging happens automatically
// ↓
// Status: "Analysis complete! 8 peaks identified."
// currentPeaks = [averaged peaks]
// identifiedModes = [modes from averaged peaks]
```

### Example 3: Continuous Measurements

```swift
// Configure
analyzer.numberOfTaps = 3

while needingMoreMeasurements {
    // Start sequence
    analyzer.startTapSequence()
    
    // Wait for user to tap 3 times
    // (UI shows progress)
    
    // Wait for completion
    while analyzer.tapProgress < 1.0 {
        // UI updates automatically
    }
    
    // Save measurement
    analyzer.saveMeasurement(tapLocation: location, notes: notes)
    
    // Prepare for next measurement
    analyzer.resumeDetection()
}
```

### Example 4: Cancel and Retry

```swift
// Start sequence
analyzer.startTapSequence()

// User taps once
// Status: "Tap 1/3 captured..."

// User realizes they tapped wrong location
// Cancel and restart
analyzer.cancelTapSequence()
// Status: "Cancelled. Ready for new sequence."

// Start again
analyzer.startTapSequence()
// Status: "Tap the guitar 3 times..."
```

## Peak Averaging Algorithm

### Step 1: Group Similar Peaks
Peaks from different taps are grouped if their frequencies are within **±5 Hz**.

**Example**:
- Tap 1: 196.2 Hz
- Tap 2: 195.8 Hz  
- Tap 3: 197.1 Hz
- → Grouped as same peak

### Step 2: Average Each Group
For each group, calculate:
```
avgFrequency = mean(all frequencies)
avgMagnitude = mean(all magnitudes)
avgQuality = mean(all Q factors)
avgBandwidth = mean(all bandwidths)
```

**Result**:
- Averaged peak: 196.37 Hz

### Step 3: Sort and Limit
- Sort peaks by magnitude (strongest first)
- Return top N peaks (configurable via `maxPeaks`)

### Step 4: Classify Modes
Modes are identified **after** averaging, ensuring classification is based on the most reliable frequency data.

## UI Integration Example

```swift
struct TapSequenceView: View {
    @ObservedObject var analyzer: TapToneAnalyzer
    
    var body: some View {
        VStack(spacing: 20) {
            // Configuration
            Stepper("Number of taps: \(analyzer.numberOfTaps)", 
                    value: $analyzer.numberOfTaps, 
                    in: 1...10)
            
            // Status
            HStack {
                Circle()
                    .fill(analyzer.isDetecting ? .green : .orange)
                    .frame(width: 12, height: 12)
                
                Text(analyzer.statusMessage)
                    .font(.headline)
            }
            
            // Progress
            ProgressView(value: analyzer.tapProgress)
                .progressViewStyle(.linear)
            
            Text("\(analyzer.currentTapCount) / \(analyzer.numberOfTaps) taps")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Controls
            HStack {
                Button("Start Sequence") {
                    analyzer.startTapSequence()
                }
                .disabled(!analyzer.isDetecting || analyzer.currentTapCount > 0)
                
                Button("Cancel") {
                    analyzer.cancelTapSequence()
                }
                .disabled(analyzer.currentTapCount == 0)
                
                Button("New Sequence") {
                    analyzer.resumeDetection()
                }
                .disabled(analyzer.currentTapCount < analyzer.numberOfTaps)
            }
        }
        .padding()
    }
}
```

## Behavior Details

### Detection States

| State | isDetecting | currentTapCount | Behavior |
|-------|-------------|-----------------|----------|
| Ready | `true` | 0 | Listening for first tap |
| Capturing | `false` | 1-N | Cooldown between taps |
| Processing | `false` | N | Averaging peaks |
| Complete | `false` | N | Results displayed |

### Timing

```
Tap 1 detected
    ↓
Detection paused (isDetecting = false)
    ↓
Capture window (0.2s) - record spectrum
    ↓
Cooldown (0.5s) - prevent double-tap
    ↓
Detection resumed (isDetecting = true)
    ↓
Ready for Tap 2
```

### After Last Tap

```
Tap N detected
    ↓
Detection paused
    ↓
Capture window (0.2s)
    ↓
Processing:
  - Group similar peaks
  - Average frequencies
  - Average magnitudes
  - Classify modes
    ↓
Results displayed
    ↓
Detection remains paused (manual resume required)
```

## Benefits of Multi-Tap Averaging

### 1. **Reduced Variance**
Averaging multiple taps smooths out inconsistencies in:
- Tap force
- Tap location precision
- Hand/object used for tapping

### 2. **Noise Reduction**
Random noise peaks are less likely to appear consistently across multiple taps.

### 3. **Increased Confidence**
Peaks that appear in all taps are genuine resonances.

### 4. **Better Mode Identification**
More accurate frequencies lead to more reliable mode classification.

### 5. **Quality Assurance**
For production guitars, 5-10 tap average provides consistent, repeatable measurements.

## Performance Considerations

### Memory Usage
- Each tap stores ~30KB of spectrum data
- 10 taps = ~300KB total
- Memory is freed after averaging

### Processing Time
- Averaging 10 taps: < 10ms
- Negligible impact on user experience

### Real-Time Feedback
All UI properties (`tapProgress`, `statusMessage`, etc.) update immediately for responsive UX.

## Testing Examples

### Test 1: Single Tap
```swift
analyzer.numberOfTaps = 1
analyzer.startTapSequence()
// Tap once
// Should get immediate results
```

### Test 2: Three Taps
```swift
analyzer.numberOfTaps = 3
analyzer.startTapSequence()
// Tap three times with slight variations
// Results should be averaged
```

### Test 3: Inconsistent Tapping
```swift
analyzer.numberOfTaps = 5
analyzer.startTapSequence()
// Tap with varying force/location
// Verify averaged results are stable
```

### Test 4: Cancel and Retry
```swift
analyzer.numberOfTaps = 3
analyzer.startTapSequence()
// Tap twice
// Cancel
analyzer.cancelTapSequence()
// Verify state is reset
```

## Troubleshooting

### Taps Not Detected
**Problem**: Tap detection not triggering
**Solutions**:
- Check microphone is active (`analyzer.isDetecting = true`)
- Increase tap force
- Check `peakThreshold` setting
- Verify audio input is working

### Too Sensitive
**Problem**: Detecting false taps
**Solutions**:
- Increase detection threshold (change `20 dB` threshold in code)
- Increase `tapCooldown` duration
- Use quieter environment

### Results Too Variable
**Problem**: Results differ too much between taps
**Solutions**:
- Increase `numberOfTaps` (try 5 or 10)
- Tap same location consistently
- Use consistent force
- Check guitar is stable (not moving)

### Averaging Not Working
**Problem**: Getting results before all taps captured
**Solutions**:
- Check `numberOfTaps` is set correctly
- Verify `currentTapCount` increments properly
- Check console logs for debugging

## Migration Guide

### Before (Old Code)
```swift
// Immediate analysis on every frame
analyzer.currentPeaks  // Always updating
```

### After (New Code)
```swift
// Configure multi-tap
analyzer.numberOfTaps = 3

// Start sequence
analyzer.startTapSequence()

// Monitor progress
if analyzer.tapProgress >= 1.0 {
    // Analysis complete
    let peaks = analyzer.currentPeaks  // Averaged results
}
```

## API Reference

### Configuration
- `numberOfTaps: Int` - Taps to average (1-10)
- `captureWindow: TimeInterval` - Spectrum capture duration

### State
- `isDetecting: Bool` - Detection active?
- `currentTapCount: Int` - Taps captured so far
- `tapProgress: Float` - Completion (0.0-1.0)
- `statusMessage: String` - User-friendly status

### Control
- `startTapSequence()` - Begin new sequence
- `cancelTapSequence()` - Abort current sequence
- `resumeDetection()` - Ready for next sequence

### Results (After Averaging)
- `currentPeaks: [ResonantPeak]` - Averaged peaks
- `identifiedModes: [(peak, mode)]` - Classified modes

## Related Files

- `TapToneAnalyzer.swift` - Main implementation
- `TapToneAnalysisView.swift` - UI integration (needs update)
- `TAP_TONE_DOCUMENTATION.md` - General documentation
