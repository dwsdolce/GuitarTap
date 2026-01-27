# Draggable Peak Annotations - User Guide

## Quick Start

### How to Move a Peak Label

1. **Hover** over a peak annotation label
   - A hand pointer icon (🫴) will appear
   - The border will become thicker
   - The shadow will intensify

2. **Click and Drag** the label
   - Drag to any position on the chart
   - A dashed line connects the label to its peak
   - The label follows your cursor smoothly

3. **Release** to commit the position
   - The label stays where you placed it
   - A reset icon appears in the label
   - Position is saved for this analysis session

### How to Reset Label Positions

**Reset One Label:**
- Right-click on the moved label
- Select "Reset Position"
- The label returns to its default position above the peak

**Reset All Labels:**
- Click the "Reset Labels" button in the toolbar
- (This button only appears when labels have been moved)
- All labels return to their default positions

## Visual States

### Default State
```
┌─────────────┐
│ Cross-Grain │  <- Peak label at default position
│  105.3 Hz   │
│  -42.1 dB   │
└─────────────┘
      ▲
      │         <- Invisible connection
      ●         <- Peak marker on spectrum
```

### Hovering State
```
┌─────────────┐
│🫴          │  <- Drag handle appears
│ Cross-Grain │  <- Thicker border
│  105.3 Hz   │  <- Enhanced shadow
│  -42.1 dB   │
└─────────────┘
      ●
```

### Moved State
```
      ┌─────────────┐
      │🫴 🔄       │  <- Drag handle + reset icon
      │ Cross-Grain │
      │  105.3 Hz   │
      │  -42.1 dB   │
      └─────────────┘
          ╱
         ╱           <- Dashed connection line
        ╱
       ●             <- Peak marker
```

### Dragging State
```
                 ┌─────────────┐
                 │🫴          │  <- Following cursor
                 │ Cross-Grain │  <- Enhanced visuals
                 │  105.3 Hz   │
                 │  -42.1 dB   │
                 └─────────────┘
                    ╱╱╱
                   ╱╱╱         <- Animated dashed line
                  ╱╱╱
                 ●             <- Peak stays in place
```

## Use Cases

### Scenario 1: Overlapping Labels
**Problem:** Two peaks at 105 Hz and 107 Hz have overlapping labels

**Solution:**
1. Drag the 107 Hz label to the right
2. Drag the 105 Hz label to the left
3. Both labels are now readable

### Scenario 2: Labels Obscuring Spectrum
**Problem:** Label is covering an important part of the frequency response

**Solution:**
1. Drag the label upward or to the side
2. Spectrum detail is now visible
3. Dashed line shows which peak the label belongs to

### Scenario 3: Creating a Clean Screenshot
**Problem:** Labels are scattered and make the chart look cluttered

**Solution:**
1. Arrange labels in a logical layout
2. Align related labels vertically or horizontally
3. Take screenshot with organized labels

### Scenario 4: Starting Fresh
**Problem:** Labels have been moved around during exploration

**Solution:**
1. Click "Reset Labels" button
2. All labels return to standard positions
3. Ready for new measurement

## Keyboard and Mouse Reference

### macOS
- **Click + Drag**: Move label
- **Right-Click**: Open context menu
- **Hover**: Show drag handle
- **Cmd + Z**: (Not implemented - manual reset only)

### iOS/iPadOS
- **Touch + Drag**: Move label
- **Long Press**: Open context menu
- **Tap**: Select (no action currently)

## Tips and Best Practices

### Organizing Labels
- **Vertical Alignment**: Drag labels to different heights to create layers
- **Horizontal Spacing**: Space out labels for close frequency peaks
- **Strategic Placement**: Move labels to clear areas of the spectrum

### When to Reset
- Starting a new measurement session
- Comparing different instruments
- Creating presentation-ready visualizations
- After significant zoom/pan changes

### Performance Notes
- Label positions are stored in memory only
- Not persisted to disk (resets on app restart)
- Cleared when starting new tap sequence
- Minimal performance impact (simple dictionary lookup)

## Troubleshooting

### Labels Won't Move
- Ensure you're clicking on the label itself, not nearby
- Check if the FFT analyzer is running
- Try clicking "Reset Labels" and starting fresh

### Labels Reset Unexpectedly
- This happens when starting a new tap sequence (by design)
- Save your measurements before starting new analysis
- Consider taking screenshots of positioned labels

### Connection Line Not Visible
- Line only appears when label has been moved
- Zoom in if the label is very close to peak
- Connection line uses mode color at 40% opacity

### "Reset Labels" Button Missing
- Button only appears when at least one label has been moved
- Try moving a label first
- Check if labels were auto-reset by starting new sequence

## Implementation Notes

For developers modifying this code:

- **Peak ID Tracking**: Labels are tracked by `ResonantPeak.id` (UUID)
- **Offset Storage**: `[UUID: CGPoint]` dictionary in `TapToneAnalyzer`
- **Thread Safety**: All offset updates happen on main thread
- **Cleanup**: Stale offsets are automatically discarded when peaks change
- **Optional Binding**: `SpectrumView` works with or without offset binding
