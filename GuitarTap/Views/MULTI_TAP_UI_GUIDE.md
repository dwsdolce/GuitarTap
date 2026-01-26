# Multi-Tap UI Integration - Complete Guide

## Overview

The UI has been updated to support the new multi-tap averaging feature with intuitive controls and real-time feedback.

## New UI Components

### 1. **Tap Configuration Controls**

Located in the header (shows when analyzer is running):

```
┌─────────────────────────────────────────────────────────────┐
│ Taps to average: [1] [-] [+]     [New Tap] [Cancel/Resume] │
└─────────────────────────────────────────────────────────────┘
```

**Components**:
- **Stepper**: Configure number of taps (1-10)
- **New Tap button**: Start a new tap sequence
- **Cancel button**: Abort current sequence (only during active tapping)
- **Resume button**: Start new sequence after completion

### 2. **Status Display**

Shows real-time detection status:

```
┌──────────────────────────────────────────────────────┐
│ ● Ready to detect taps                      0/3     │
│ ████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 33%    │
└──────────────────────────────────────────────────────┘
```

**Elements**:
- **Status dot**: 
  - 🟢 Green = Detecting (listening for taps)
  - 🟠 Orange = Processing (paused between taps or analyzing)
- **Status message**: Human-readable text
- **Counter**: "X/N" shows progress
- **Progress bar**: Visual progress indicator

### 3. **Enhanced Header Layout**

New two-row layout:

**Row 1 - Main Controls**:
```
[Start/Stop] [Show Metrics] [Save] [Reset]
```

**Row 2 - Tap Sequence** (only when running):
```
Taps to average: [stepper]  [New Tap] [Cancel/Resume]
● Status message                           2/3
████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 67%
```

## User Workflows

### Workflow 1: Single Tap (Quick Mode)

1. **Start analyzer**: Click [Start]
2. **Ensure taps = 1**: (default setting)
3. **Tap guitar**: 
   - Status: "Tap the guitar..."
   - After tap: "Analysis complete! 8 peaks identified."
4. **View results**: Peaks and modes appear immediately
5. **Save** (optional): Click [Save] to store measurement
6. **Tap again**: Click [New Tap] or [Resume]

### Workflow 2: Three-Tap Average (Recommended)

1. **Start analyzer**: Click [Start]
2. **Set taps to 3**: Use stepper to select 3
3. **Start sequence**: Click [New Tap]
   - Status: "Tap the guitar 3 times..."
   - Status dot: 🟢 Green
4. **Tap 1**: 
   - Detected: "🎯 Tap detected!" (brief flash)
   - Status: "Tap 1/3 captured. Tap again..."
   - Progress: 33%
   - Status dot: 🟠 Orange (paused)
5. **Wait 0.5s** (automatic cooldown)
   - Status dot: 🟢 Green (ready)
6. **Tap 2**:
   - Status: "Tap 2/3 captured. Tap again..."
   - Progress: 67%
7. **Tap 3**:
   - Status: "All taps captured. Processing..."
   - Progress: 100%
8. **Automatic averaging** (< 10ms)
   - Status: "Analysis complete! 8 peaks identified."
   - Results updated with averaged peaks
   - Modes classified from averaged data
9. **Review results**
10. **Save** (optional)
11. **Next measurement**: Click [Resume] → repeats from step 3

### Workflow 3: Cancel and Retry

1. **Start sequence**: 3 taps configured
2. **Tap once**: "Tap 1/3 captured..."
3. **Realize mistake** (wrong location/force)
4. **Click [Cancel]**:
   - Status: "Cancelled. Ready for new sequence."
   - Counters reset
   - Progress cleared
5. **Click [New Tap]**: Start fresh sequence

### Workflow 4: Multiple Measurements

```swift
// Production workflow for quality control
for location in ["Bridge", "Upper Bout", "Lower Bout"] {
    1. Set location context
    2. Click [New Tap]
    3. Tap guitar 5 times (configured)
    4. Wait for "Analysis complete!"
    5. Click [Save] with location name
    6. Click [Resume]
}
```

## UI State Management

### Button States

| Button | Enabled When | Action |
|--------|--------------|--------|
| **Start** | Analyzer stopped | Start FFT engine |
| **Stop** | Analyzer running | Stop FFT engine |
| **New Tap** | No active sequence | Start new tap sequence |
| **Cancel** | Mid-sequence (1 < count < N) | Abort and reset |
| **Resume** | Sequence complete (count = N) | Ready for new sequence |
| **Save** | Has peaks | Save measurement |
| **Reset** | Always | Clear all data |

### Status Messages

| State | Message | Status Dot |
|-------|---------|------------|
| Ready | "Ready to detect taps" | 🟢 Green |
| Configured | "Tap the guitar 3 times..." | 🟢 Green |
| After Tap 1 | "Tap 1/3 captured. Tap again..." | 🟠 Orange |
| Cooldown | "Tap 1/3 captured. Tap again..." | 🟠 → 🟢 |
| Processing | "All taps captured. Processing..." | 🟠 Orange |
| Complete | "Analysis complete! 8 peaks identified." | 🟠 Orange |
| Cancelled | "Cancelled. Ready for new sequence." | 🟢 Green |

## Visual Design

### Colors

**Status Indicators**:
- 🟢 **Green**: Ready to detect / Listening
- 🟠 **Orange**: Processing / Paused / Complete
- 🔴 **Red**: Error / Stopped
- 🔵 **Blue**: Action available (Resume)

**Buttons**:
- **Green** (Start): Begin analysis
- **Red** (Stop): End analysis
- **Blue** (Resume): Continue after completion
- **Orange** (Cancel): Abort sequence
- **Gray** (Disabled): Not available

### Layout Hierarchy

```
┌─ Header ──────────────────────────────────────────────┐
│  ┌─ Main Controls ────────────────────────────────┐  │
│  │ [Start] [Metrics] [Save] [Reset]              │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─ Tap Sequence ─────────────────────────────────┐  │
│  │ Taps: [3] [-] [+]      [New Tap] [Resume]     │  │
│  │ ● Tap 2/3 captured. Tap again...         2/3  │  │
│  │ ████████████████████░░░░░░░░░░░░░░░░░░░ 67%   │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Responsive Design

### macOS
- Full header with all controls visible
- Two-row layout with generous spacing
- Stepper with text label

### iPad
- Same as macOS
- May wrap on smaller iPads in portrait

### iPhone
- Stepper becomes more compact
- Buttons may use icon-only mode
- Status text truncates if needed

## Keyboard Shortcuts (Future Enhancement)

Potential shortcuts for macOS:

- `⌘T` - New Tap sequence
- `⌘R` - Resume detection
- `⌘K` - Cancel sequence
- `⌘S` - Save measurement
- `⌘⌫` - Reset all

## Accessibility

### VoiceOver Support

**Status Announcement**:
- "Ready to detect taps"
- "Tap detected, 1 of 3 captured"
- "Analysis complete, 8 peaks identified"

**Button Labels**:
- "Start tap detection sequence"
- "Cancel current tap sequence"
- "Resume tap detection"

### Dynamic Type

All text respects user's font size preferences:
- Status messages
- Button labels
- Counter display

## Animation Details

### Progress Bar
- **Duration**: Instant jump per tap
- **Style**: Linear progress
- **Color**: System blue

### Status Dot
- **Transition**: 0.3s smooth fade
- **Green ↔ Orange**: Detection state change
- **Pulse** (optional): On tap detection

### Button State Changes
- **Fade**: 0.2s opacity transition
- **Disabled** → **Enabled**: Smooth enable

## Code Integration

### Accessing Tap State

```swift
// In any view with access to tapToneAnalyzer:

// Current state
let isDetecting = tapToneAnalyzer.isDetecting
let progress = tapToneAnalyzer.tapProgress
let status = tapToneAnalyzer.statusMessage

// Current count
let captured = tapToneAnalyzer.currentTapCount
let total = tapToneAnalyzer.numberOfTaps

// Check completion
if tapToneAnalyzer.tapProgress >= 1.0 {
    // Sequence complete, show results
}
```

### Custom UI Integration

```swift
// Custom progress view
VStack {
    Text(analyzer.statusMessage)
        .font(.headline)
    
    ProgressView(value: analyzer.tapProgress) {
        HStack {
            Text("\(analyzer.currentTapCount)")
            Text("of")
            Text("\(analyzer.numberOfTaps)")
        }
    }
}

// Detection indicator
HStack {
    Image(systemName: analyzer.isDetecting ? 
        "waveform" : "pause.circle")
    Text(analyzer.isDetecting ? "Listening" : "Paused")
}
.foregroundColor(analyzer.isDetecting ? .green : .orange)
```

## Testing the UI

### Test Checklist

- [ ] Stepper changes numberOfTaps (1-10)
- [ ] "New Tap" button starts sequence
- [ ] Status updates after each tap
- [ ] Progress bar fills correctly
- [ ] Counter increments (1/3, 2/3, 3/3)
- [ ] Cancel button appears during sequence
- [ ] Cancel button resets state
- [ ] Resume button appears when complete
- [ ] Status dot changes color appropriately
- [ ] Save button only enabled with peaks
- [ ] Reset clears everything

### Test Scenarios

**Scenario 1: Happy Path**
1. Set taps to 3
2. Click New Tap
3. Tap 3 times
4. Verify averaging works
5. Click Save
6. Click Resume
7. Repeat

**Scenario 2: Cancel Mid-Sequence**
1. Set taps to 5
2. Click New Tap
3. Tap twice
4. Click Cancel
5. Verify reset
6. Click New Tap
7. Complete sequence

**Scenario 3: Change Configuration**
1. Set taps to 1
2. Tap once
3. Results immediate
4. Change to 5 taps
5. Click Resume
6. Tap 5 times
7. Verify averaging

## Troubleshooting UI Issues

### Buttons Not Responding

**Check**:
- Is analyzer running? (Start button clicked)
- Is sequence already active?
- Are buttons disabled (grayed out)?

### Status Not Updating

**Check**:
- Is FFT analyzer running?
- Console logs for tap detection
- Check `isDetecting` property

### Progress Bar Stuck

**Check**:
- Tap detection sensitivity
- Cooldown timing (wait 0.5s between taps)
- Microphone input level

### Cancel Button Missing

**Check**:
- Must be mid-sequence (0 < count < N)
- If count = 0: Use "New Tap"
- If count = N: Use "Resume"

## Future Enhancements

### Potential Additions

1. **Visual Tap Feedback**:
   - Flash animation on tap detect
   - Waveform visualization spike

2. **Tap Quality Indicator**:
   - Consistency meter across taps
   - Warning if taps vary too much

3. **Auto-Advance**:
   - Option to auto-start next sequence
   - Batch mode for multiple measurements

4. **Tap History**:
   - Show individual tap results
   - Compare variations between taps

5. **Sound Feedback**:
   - Beep on successful tap capture
   - Different tones for progress

6. **Configuration Presets**:
   - Quick (1 tap)
   - Standard (3 taps)
   - Precision (5 taps)
   - Research (10 taps)

## Summary

The UI now provides:
✅ **Clear visual feedback** for tap detection state
✅ **Progress tracking** with bar and counter
✅ **Flexible controls** for starting, cancelling, and resuming
✅ **Configuration options** for number of taps
✅ **Status messages** for user guidance
✅ **Responsive layout** that adapts to available space

Users can now:
- Quickly measure with single tap
- Average multiple taps for accuracy
- Cancel and retry if needed
- Track progress in real-time
- Understand system state at a glance
