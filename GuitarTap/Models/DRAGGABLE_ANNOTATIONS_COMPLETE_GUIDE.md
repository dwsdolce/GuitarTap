# Draggable Peak Annotations - Complete Feature Guide

## Overview
Peak annotation labels on the spectrum chart can now be repositioned by dragging them. This prevents overlapping labels and allows users to organize the display for better readability and screenshots.

## What's New

### Interactive Labels
- **Drag to Move**: Click and drag any peak label to reposition it
- **Visual Feedback**: Labels highlight when hovered, show drag handle icon
- **Connection Lines**: Dashed lines connect moved labels to their peaks
- **Context Menu**: Right-click for reset option

### UI Controls
- **Reset Labels Button**: Appears in toolbar when labels have been moved
  - Resets all labels to default positions
  - Helpful when starting fresh or after extensive repositioning

### Smart State Management
- Label positions cleared automatically when starting new tap sequence
- Positions maintained during analysis and when spectrum is frozen
- Thread-safe updates ensure no runtime warnings

## How It Works

### Architecture

```
┌─────────────────────────────────────────────────────┐
│              TapToneAnalyzer                        │
│  ┌───────────────────────────────────────────────┐  │
│  │ @Published peakAnnotationOffsets              │  │
│  │ [UUID: CGPoint]                               │  │
│  │                                               │  │
│  │ - updateAnnotationOffset(for:offset:)        │  │
│  │ - resetAnnotationOffset(for:)                │  │
│  │ - resetAllAnnotationOffsets()                │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
                         │
                         │ Binding
                         ▼
┌─────────────────────────────────────────────────────┐
│              SpectrumView                           │
│  ┌───────────────────────────────────────────────┐  │
│  │ var annotationOffsets:                        │  │
│  │     Binding<[UUID: CGPoint]>?                 │  │
│  │                                               │  │
│  │ For each peak:                                │  │
│  │   - Render PointMark                         │  │
│  │   - Render DraggablePeakAnnotation           │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
                         │
                         │ Peak & Callbacks
                         ▼
┌─────────────────────────────────────────────────────┐
│         DraggablePeakAnnotation                     │
│  ┌───────────────────────────────────────────────┐  │
│  │ State:                                        │  │
│  │ - offset: CGPoint (from binding)             │  │
│  │ - dragOffset: CGSize (temporary)             │  │
│  │ - isHovering: Bool                           │  │
│  │ - isDragging: Bool                           │  │
│  │                                               │  │
│  │ Gestures:                                     │  │
│  │ - DragGesture → onOffsetChange callback      │  │
│  │ - Context Menu → onReset callback            │  │
│  │                                               │  │
│  │ Visual Elements:                              │  │
│  │ - Connection line (when moved)               │  │
│  │ - Drag handle icon                           │  │
│  │ - Reset icon                                 │  │
│  │ - Enhanced hover effects                     │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

### Data Flow

1. **User Interaction**
   ```swift
   User drags label
   → DragGesture.onChanged updates local dragOffset
   → DragGesture.onEnded calls onOffsetChange
   ```

2. **State Update**
   ```swift
   onOffsetChange callback
   → Updates annotationOffsets binding
   → TapToneAnalyzer.peakAnnotationOffsets updated
   → SwiftUI triggers view update
   ```

3. **Visual Update**
   ```swift
   SpectrumView re-renders
   → Reads new offset from binding
   → DraggablePeakAnnotation renders at new position
   → Connection line drawn from peak to label
   ```

## Code Examples

### Using Draggable Annotations

```swift
// In your view:
@StateObject var tapToneAnalyzer: TapToneAnalyzer

var body: some View {
    SpectrumView(
        frequencies: fftAnalyzer.frequencies,
        magnitudes: fftAnalyzer.magnitudes,
        minFreq: $minFreq,
        maxFreq: $maxFreq,
        minDB: $minDB,
        maxDB: $maxDB,
        isLogarithmic: $isLogarithmic,
        peaks: tapToneAnalyzer.currentPeaks,
        showModeBoundaries: true,
        annotationOffsets: $tapToneAnalyzer.peakAnnotationOffsets  // ← Enable dragging
    )
}
```

### Without Draggable Annotations (Legacy)

```swift
// Simply omit the annotationOffsets parameter:
SpectrumView(
    frequencies: frequencies,
    magnitudes: magnitudes,
    minFreq: $minFreq,
    maxFreq: $maxFreq,
    minDB: $minDB,
    maxDB: $maxDB,
    isLogarithmic: $isLogarithmic,
    peaks: peaks
    // annotationOffsets not provided → static labels
)
```

### Programmatically Setting Label Positions

```swift
// Set specific offset for a peak
tapToneAnalyzer.updateAnnotationOffset(
    for: peakID,
    offset: CGPoint(x: 50, y: -30)
)

// Reset all positions
tapToneAnalyzer.resetAllAnnotationOffsets()

// Reset specific peak
tapToneAnalyzer.resetAnnotationOffset(for: peakID)
```

## Visual Design Details

### Color Coding
Labels use mode-specific colors:
- **Helmholtz**: Cyan
- **Cross-Grain**: Blue  
- **Long-Grain**: Green
- **Monopole**: Orange
- **Dipole**: Red
- **Ring Mode**: Purple
- **Upper Modes**: Gray

### Interactive States

| State | Border Width | Shadow | Background | Icons |
|-------|-------------|---------|-----------|-------|
| Default | 1.5pt | Subtle | 95% opaque | None |
| Hover | 2.5pt | Enhanced | 100% opaque | Drag handle |
| Moved | 1.5pt | Subtle | 95% opaque | Drag + Reset |
| Dragging | 2.5pt | Strong | 100% opaque | Drag (filled) |

### Connection Line
- **Style**: Dashed line (4pt dash, 3pt gap)
- **Width**: 1.5pt
- **Color**: Mode color at 40% opacity
- **Visibility**: Only shown when label is moved or being dragged

### Animations
- **Duration**: 150ms
- **Curve**: Ease in/out
- **Properties**: Border width, shadow, background opacity
- **Smooth**: Icon transitions use fade + scale

## Accessibility

### Keyboard Access
Currently labels are mouse/touch only. Future enhancement could add:
- Arrow keys to nudge selected label
- Tab to cycle through labels
- Enter to reset selected label

### VoiceOver
Labels inherit accessibility from SwiftUI Charts:
- Peak frequency announced
- Peak magnitude announced
- Mode name announced

### Reduced Motion
Animations respect system settings:
- Transitions still occur but instantaneous if motion reduced
- Hover effects still visible but without animation

## Best Practices

### When to Use Draggable Labels

✅ **Good Use Cases:**
- Multiple peaks within 5-10 Hz of each other
- Creating presentation materials or reports
- Analyzing complex spectra with many peaks
- Comparing measurements side-by-side

❌ **Less Useful When:**
- Only 1-2 peaks detected
- Peaks are widely spaced (> 50 Hz apart)
- Quickly scanning multiple measurements
- Using very large chart view (ample space)

### Label Organization Strategies

1. **Vertical Stacking**: Move labels up/down to create layers
   ```
   ┌─────┐
   │ 105 │  ← Moved up 30px
   └─────┘
        ╲
   ┌─────┐
   │ 107 │  ← Default position
   └─────┘
   ```

2. **Horizontal Spreading**: Move labels left/right
   ```
   ┌─────┐      ┌─────┐
   │ 105 │      │ 107 │
   └─────┘      └─────┘
      ╲           ╱
       ●─────────●
   ```

3. **Corner Placement**: Move to chart corners
   ```
   ┌─────┐
   │ Peak│  ← Moved to upper left
   └─────┘
      ╲
       ╲_______________
                       ╲
                        ●
   ```

## Integration with Other Features

### Works With:
- ✅ Frozen spectrum mode
- ✅ Multi-tap averaging
- ✅ Mode boundary markers
- ✅ Zoom and pan gestures
- ✅ Logarithmic/linear frequency scales

### Cleared On:
- Starting new tap sequence (via "New Tap" button)
- Calling `reset()` on analyzer
- Creating new measurements

### Preserved During:
- Analysis and processing
- Spectrum freezing
- Zooming and panning
- Switching between views

## Performance Considerations

### Memory Usage
- Minimal: Dictionary with ~5-10 entries (one per peak)
- Each entry: UUID (16 bytes) + CGPoint (16 bytes) = 32 bytes
- Total: < 1KB for typical use

### Rendering Performance
- No measurable impact on chart rendering
- Offset lookup is O(1) dictionary access
- Animations are GPU-accelerated by SwiftUI

### Thread Safety
- All offset updates dispatched to main thread
- No data races or conflicts
- Safe for concurrent access

## Debugging

### Enable Debug Logging
Add print statements to track offset changes:

```swift
func updateAnnotationOffset(for peakID: UUID, offset: CGPoint) {
    print("🎯 Moving annotation \(peakID): \(offset)")
    DispatchQueue.main.async { [weak self] in
        self?.peakAnnotationOffsets[peakID] = offset
    }
}
```

### Inspect Current Offsets
```swift
print("Current annotation offsets:", tapToneAnalyzer.peakAnnotationOffsets)
```

### Verify Main Thread Updates
If you see warnings about background thread publishing, check that:
- All `@Published` property updates are in `DispatchQueue.main.async`
- Callbacks from gestures don't bypass main thread
- Timer callbacks dispatch to main if updating published properties

## Known Limitations

1. **No Automatic Collision Avoidance**: Labels can still overlap if user positions them poorly
2. **No Persistence**: Positions reset on app restart
3. **No Undo/Redo**: Must manually reset to default
4. **Chart Coordinate Relative**: Labels move with zoom/pan (intentional design)

## Future Roadmap

### Planned Enhancements
- [ ] Automatic smart positioning algorithm
- [ ] Snap to grid or predefined positions
- [ ] Save/load label layouts with measurements
- [ ] Keyboard navigation and nudging
- [ ] Magnetic snapping to align labels
- [ ] Label clustering for very close peaks
- [ ] Export positioned chart as image

### Community Feedback
This feature was implemented to address user requests for better label management in dense spectrum charts. Please provide feedback on:
- Most useful positioning strategies
- Desired automatic positioning behaviors
- Integration with other workflow features
