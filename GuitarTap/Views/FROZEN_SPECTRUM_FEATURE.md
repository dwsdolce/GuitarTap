# Frozen Spectrum Feature

## Overview

The spectrum plot now freezes automatically when all taps in a sequence are captured. This allows users to review the exact spectrum that was used for analysis without it being obscured by ongoing live updates.

## Behavior

### When Spectrum Freezes

The spectrum **automatically freezes** when:
- All N taps have been captured
- Averaging is complete
- Results are displayed

### When Spectrum Unfreezes

The spectrum **automatically resumes** when:
- User clicks **[New Tap]** button
- User clicks **[Resume]** button
- User clicks **[Reset]** button

### Visual Indicator

When frozen, a badge appears next to the spectrum title:

```
Real-Time Frequency Response  ⏸ Frozen
```

## Implementation Details

### New Properties in TapToneAnalyzer

```swift
@Published var frozenFrequencies: [Float] = []
@Published var frozenMagnitudes: [Float] = []
@Published var isSpectrumFrozen: Bool = false
```

### Freezing Logic

**In `processMultipleTaps()`**:
```swift
// After averaging peaks...
if let lastTap = capturedTaps.last {
    frozenFrequencies = lastTap.frequencies
    frozenMagnitudes = lastTap.magnitudes
    isSpectrumFrozen = true
    print("📸 Spectrum frozen at last tap")
}
```

**In UI (TapToneAnalysisView)**:
```swift
SpectrumView(
    frequencies: tapToneAnalyzer.isSpectrumFrozen ? 
        tapToneAnalyzer.frozenFrequencies : fftAnalyzer.frequencies,
    magnitudes: tapToneAnalyzer.isSpectrumFrozen ? 
        tapToneAnalyzer.frozenMagnitudes : fftAnalyzer.magnitudes,
    ...
)
```

### Unfreezing Logic

**In `startTapSequence()`**:
```swift
isSpectrumFrozen = false
frozenFrequencies = []
frozenMagnitudes = []
```

**In `resumeDetection()`**:
```swift
isSpectrumFrozen = false
frozenFrequencies = []
frozenMagnitudes = []
```

**In `reset()`**:
```swift
isSpectrumFrozen = false
frozenFrequencies = []
frozenMagnitudes = []
```

## User Workflows

### Workflow 1: Single Tap

1. Click [New Tap]
2. Tap guitar
3. **Spectrum freezes** at tap
4. Review results
5. Click [New Tap] or [Resume]
6. **Spectrum resumes** updating

### Workflow 2: Multiple Taps

1. Set taps to 3
2. Click [New Tap]
3. Tap 3 times (spectrum updates live during tapping)
4. After 3rd tap: **Spectrum freezes** at last tap
5. Review averaged results with frozen spectrum
6. Click [Resume]
7. **Spectrum resumes** for next sequence

### Workflow 3: Compare Measurements

1. Complete tap sequence → Spectrum frozen
2. Review peaks on frozen spectrum
3. Click [Save] to store
4. Click [Resume] → Spectrum unfreezes
5. Complete new sequence → Spectrum freezes again
6. Compare new frozen spectrum to previous

## Benefits

### 1. **Clear Reference**
Frozen spectrum shows exactly what was analyzed, not what's happening now.

### 2. **No Confusion**
Users don't wonder why peaks don't match the live spectrum (because it's frozen at capture time).

### 3. **Review Time**
Users can take time to examine results without the spectrum changing.

### 4. **Screenshot-Friendly**
Capture consistent screenshots of analysis results.

### 5. **Teaching/Demo**
Explain results using a stable reference spectrum.

## Visual States

### Live (Not Frozen)
```
┌─ Real-Time Frequency Response ─────────────────┐
│                                                 │
│  [Updating spectrum visualization]             │
│                                                 │
└─────────────────────────────────────────────────┘
```

### Frozen (After Completion)
```
┌─ Real-Time Frequency Response  ⏸ Frozen ──────┐
│                                                 │
│  [Static spectrum from last tap]               │
│                                                 │
└─────────────────────────────────────────────────┘
```

## Console Output

### When Freezing
```
🔬 Processing 3 taps for averaging...
✅ Averaged 3 taps into 8 peaks
📸 Spectrum frozen at last tap
```

### When Unfreezing
```
🎬 Starting tap sequence: 3 tap(s)
[Spectrum unfreezes automatically]
```

## Testing

### Test 1: Verify Freeze
1. Set taps to 3
2. Start sequence
3. Tap 3 times
4. Verify spectrum stops updating
5. Verify frozen badge appears
6. Wave hand in front of mic
7. Confirm spectrum doesn't change

### Test 2: Verify Unfreeze
1. With frozen spectrum
2. Click [Resume]
3. Verify frozen badge disappears
4. Make noise near mic
5. Confirm spectrum updates

### Test 3: Reset While Frozen
1. Complete tap sequence (frozen)
2. Click [Reset]
3. Verify spectrum unfreezes
4. Verify updates resume

### Test 4: Multiple Sequences
1. Complete sequence 1 (frozen)
2. Click [Resume]
3. Complete sequence 2 (frozen)
4. Verify spectrum shows sequence 2 data

## Edge Cases

### Single Tap Mode (numberOfTaps = 1)
- Spectrum still freezes after the single tap
- Shows the captured tap spectrum
- Unfreezes on [New Tap] or [Resume]

### Cancel During Sequence
- If cancelled, spectrum is **not** frozen
- Continues updating live
- `isSpectrumFrozen` remains `false`

### No Taps Captured
- If no valid taps detected, spectrum not frozen
- Continues showing live data

## Technical Notes

### Memory Usage
- Frozen spectrum: ~30-65 KB (one copy of frequencies + magnitudes)
- Cleared when unfrozen
- Minimal memory impact

### Performance
- No performance impact
- Just swaps data source (frozen vs. live)
- No additional computation

### Data Accuracy
- Frozen spectrum is from **last tap** in sequence
- This is the most recent capture
- Matches the averaged peaks time-wise

## Customization Options

### Change Frozen Indicator

**Current**:
```swift
Image(systemName: "pause.circle.fill")
Text("Frozen")
```

**Alternatives**:
```swift
// Snapshot icon
Image(systemName: "camera.fill")
Text("Captured")

// Lock icon
Image(systemName: "lock.fill")
Text("Locked")

// Stop icon
Image(systemName: "stop.circle.fill")
Text("Paused")
```

### Auto-Unfreeze Timeout

Add optional auto-unfreeze after N seconds:

```swift
// In processMultipleTaps():
isSpectrumFrozen = true

// Schedule auto-unfreeze (optional)
DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
    if self?.tapProgress == 1.0 {  // Still complete
        self?.isSpectrumFrozen = false
        print("⏱ Auto-unfroze spectrum after timeout")
    }
}
```

### Manual Freeze/Unfreeze Toggle

Add toggle button to UI:

```swift
Button(action: {
    if tapToneAnalyzer.tapProgress >= 1.0 {
        tapToneAnalyzer.isSpectrumFrozen.toggle()
    }
}) {
    Image(systemName: tapToneAnalyzer.isSpectrumFrozen ? 
        "play.circle" : "pause.circle")
}
.disabled(tapToneAnalyzer.tapProgress < 1.0)
```

## Related Features

### Save Frozen Spectrum

The frozen spectrum can be saved with measurements:

```swift
func saveMeasurement(...) {
    let spectrum = isSpectrumFrozen ? 
        frozenMagnitudes : fftAnalyzer.magnitudes
    // Save with measurement...
}
```

### Compare Frozen Spectra

Future enhancement: Show multiple frozen spectra side-by-side:

```swift
struct FrozenSpectrumComparison {
    let measurement1Spectrum: [Float]
    let measurement2Spectrum: [Float]
    // Display both in overlay or split view
}
```

## Troubleshooting

### Spectrum Not Freezing

**Check**:
- All taps captured? (`currentTapCount == numberOfTaps`)
- Processing complete? (`tapProgress == 1.0`)
- Console shows "📸 Spectrum frozen at last tap"?

**Fix**:
- Verify `processMultipleTaps()` is called
- Check `capturedTaps` is not empty

### Spectrum Not Unfreezing

**Check**:
- Did you click [New Tap] or [Resume]?
- Console shows "🎬 Starting tap sequence" or "▶️ Resuming"?

**Fix**:
- Click [Reset] to force unfreeze
- Verify `isSpectrumFrozen` set to `false`

### Frozen Badge Not Showing

**Check**:
- Is `isSpectrumFrozen == true`?
- UI properly observing `tapToneAnalyzer`?

**Fix**:
- Check `@ObservedObject` or `@StateObject` decorator
- Verify view updates when property changes

### Wrong Spectrum Frozen

**Check**:
- Which tap is being captured?
- Console shows which tap was used

**Current Behavior**:
- Uses **last tap** (most recent)

**To Change**:
```swift
// Use first tap instead:
if let firstTap = capturedTaps.first {
    frozenFrequencies = firstTap.frequencies
    frozenMagnitudes = firstTap.magnitudes
}

// Or average all spectra:
let avgMagnitudes = averageSpectra(capturedTaps.map { $0.magnitudes })
frozenMagnitudes = avgMagnitudes
```

## Summary

✅ **Spectrum freezes** after all taps captured
✅ **Visual indicator** (⏸ Frozen badge)
✅ **Unfreezes** on [New Tap], [Resume], or [Reset]
✅ **Shows captured data** not live updates
✅ **Zero performance impact**
✅ **Helps users** review analysis accurately

This feature ensures users can review their measurements without the spectrum changing underneath them, providing a stable reference for analysis.
