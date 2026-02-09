# Draggable Peak Annotations Feature

## Overview

The peak annotation labels in the spectrum chart can now be dragged and repositioned by the user to prevent overlap and improve readability. This is especially useful when multiple peaks are detected close together in frequency.

## Features

### 1. **Draggable Labels**
- Click and drag any peak annotation label to move it
- The label remains connected to its peak marker
- Position is preserved until reset or new analysis

### 2. **Visual Feedback**
- Labels show a drag handle icon (hand pointer) when hovered
- Border thickness increases on hover to indicate interactivity
- Shadow intensifies during hover for depth perception
- Moved labels display a reset icon indicator

### 3. **Reset Functionality**
- **Individual Reset**: Right-click on any label and select "Reset Position"
- **Global Reset**: Click the "Reset Labels" button (appears when labels have been moved)
- Resets restore labels to their default positions above their peaks

### 4. **Persistence**
- Label positions are stored in `TapToneAnalyzer.peakAnnotationOffsets`
- Positions are maintained during analysis
- Cleared on reset or when starting a new tap sequence

## User Interactions

### Drag a Label
1. Hover over the peak annotation label
2. Click and hold
3. Drag to desired position
4. Release to commit the position

### Reset a Single Label
1. Right-click on the label
2. Select "Reset Position" from context menu
3. Label returns to default position above its peak

### Reset All Labels
1. Click the "Reset Labels" button in the toolbar
2. All labels return to default positions

## Technical Implementation

### Data Model
```swift
// In TapToneAnalyzer
@Published var peakAnnotationOffsets: [UUID: CGPoint] = [:]
```

The offsets are keyed by peak ID (`UUID`), allowing each peak's label position to be tracked independently. When peaks change, stale offsets are automatically discarded.

### SpectrumView Integration
- Added optional `annotationOffsets` binding parameter
- Backward compatible - works without the binding
- Falls back to non-draggable annotations if binding not provided

### DraggablePeakAnnotation Component
- Self-contained SwiftUI view
- Uses `DragGesture` for repositioning
- Includes context menu for reset
- Shows visual indicators for interactivity

## Best Practices

1. **When to Move Labels**: Move labels when they overlap or obscure important parts of the spectrum
2. **Reset After New Analysis**: Use "Reset Labels" when starting fresh measurements
3. **Visual Organization**: Arrange labels to create clear visual hierarchy

## Platform Support

- **macOS**: Full support with mouse interactions
  - Hover effects
  - Right-click context menu
  - Drag and drop
  
- **iOS/iPadOS**: Touch-based interactions
  - Long-press for context menu
  - Touch drag to reposition
  - No hover effects (touch-based devices)

## Future Enhancements

Potential improvements for future versions:
- [ ] Automatic label placement to avoid overlaps
- [ ] Snap-to-grid positioning
- [ ] Leader lines from labels to peaks
- [ ] Label position persistence across sessions (save/load)
- [ ] Smart label clustering for very close peaks
