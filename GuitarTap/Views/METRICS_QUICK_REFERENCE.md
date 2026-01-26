# FFT Metrics Quick Reference

## How to Access

### Show Metrics
1. Look for the chart icon (📊) in the toolbar
2. Tap/Click "Show Metrics"
3. Metrics panel will appear

### Hide Metrics  
1. Find the filled chart icon in toolbar
2. Tap/Click "Hide Metrics"
3. Metrics panel will disappear

---

## What You'll See

### On macOS
✅ Full metrics panel on the right side
✅ Resizable with drag divider
✅ All 11 metrics visible

### On iPad (Landscape)
✅ Full metrics panel on the right side
✅ Fixed 350pt width
✅ All 11 metrics visible

### On iPhone
✅ Compact overlay in top-right corner
✅ 5 key metrics only
✅ Translucent background

---

## Key Metrics Explained

### Frequency Resolution
**What**: Spacing between FFT bins
**Good Value**: 0.5-2 Hz for guitar analysis
**Too High**: > 5 Hz (poor frequency precision)
**Too Low**: < 0.1 Hz (slow updates, wasted computation)

### Sample Length
**What**: Duration of audio analyzed per frame
**Good Value**: 0.5-2 seconds
**Trade-off**: Longer = better resolution but slower updates

### Frame Rate
**What**: How often FFT updates per second
**Good Value**: 30-60 Hz
**Too Low**: < 20 Hz (choppy, laggy)
**Too High**: > 100 Hz (wasted CPU, no benefit)

### Processing Time
**What**: How long last FFT took to compute
**Good**: < 5ms (green)
**OK**: 5-10ms (yellow)
**High**: 10-15ms (orange)
**Critical**: > 15ms (red)

### Average Processing
**What**: 30-frame rolling average of processing time
**Why Important**: More stable than instantaneous reading
**Monitor**: Should stay consistent, not spike randomly

### CPU Usage
**What**: Percentage of available frame time used
**Excellent**: < 50% (green) - lots of headroom
**Good**: 50-80% (yellow) - normal
**High**: 80-95% (orange) - optimize if possible
**Critical**: > 95% (red) - likely dropping frames

### Peak Frequency
**What**: Strongest frequency detected right now
**Guitar Range**: 82 Hz (E2) to 1,318 Hz (E6)
**Updates**: Real-time with every FFT frame

### Peak Magnitude
**What**: Strength of peak frequency in dB
**Quiet Room**: -60 to -40 dB
**Normal Playing**: -40 to -20 dB  
**Loud/Close**: -20 to 0 dB

---

## Color Guide

| Color | CPU % | Action |
|-------|-------|--------|
| 🟢 | < 50% | Great! No action needed |
| 🟡 | 50-80% | Good, keep monitoring |
| 🟠 | 80-95% | Consider reducing FFT size |
| 🔴 | > 95% | Reduce FFT size ASAP |

---

## Quick Troubleshooting

### Metrics Not Updating
**Problem**: Numbers frozen or not changing
**Causes**:
- Analyzer not running (check status dot)
- Audio input disconnected
- App paused/backgrounded

**Fix**:
1. Check status: Should see green dot + "Analyzing"
2. Press Stop, then Start again
3. Check microphone permissions
4. Verify audio input device (macOS)

---

### High CPU Usage (Red)
**Problem**: CPU Usage > 95%, red color
**Causes**:
- FFT size too large (65,536+)
- Sample rate too high (96 kHz+)
- Other CPU-intensive apps running

**Fix**:
1. Reduce FFT size: Try 32,768 or 16,384
2. Lower sample rate: Try 48,000 Hz
3. Close other apps
4. Check Activity Monitor (macOS) / Battery settings (iOS)

**Edit This In**: `TapToneAnalysisView.swift` line 38:
```swift
let fft = RealtimeFFTAnalyzer(fftSize: 32768, targetSampleRate: 48000)
```

---

### Choppy/Laggy Updates
**Problem**: UI feels slow, stutters
**Causes**:
- Frame rate too low (< 20 Hz)
- CPU maxed out
- Too much data being processed

**Fix**:
1. Check Frame Rate metric - should be 30+ Hz
2. Check CPU Usage - should be < 80%
3. If CPU high, reduce FFT size
4. Close background apps

---

### Poor Frequency Resolution
**Problem**: Can't distinguish close frequencies
**Current**: Frequency Resolution shows high value (> 5 Hz)
**Causes**:
- FFT size too small
- Sample rate too high for FFT size

**Fix**:
1. Increase FFT size: Try 65,536 or 131,072
2. Keep sample rate at 48,000 Hz
3. Trade-off: Slower updates, higher CPU

**Example**:
- 8,192 FFT @ 48 kHz = 5.86 Hz/bin (poor)
- 65,536 FFT @ 48 kHz = 0.73 Hz/bin (good)

---

### Metrics Panel Too Narrow/Wide
**Problem**: macOS split view not optimal size

**Fix**:
1. Drag the divider between panels
2. Minimum width: 300pt
3. Maximum width: 450pt
4. macOS remembers your preference

---

### Overlay Blocking Content (iPhone)
**Problem**: Compact overlay covers important info

**Fix Option 1** - Move It:
Edit `TapToneAnalysisView.swift` around line 85:
```swift
ZStack(alignment: .topTrailing) {  // Change to:
// .topLeading    = top-left
// .bottomLeading = bottom-left  
// .bottomTrailing = bottom-right
```

**Fix Option 2** - Hide It:
Just tap "Hide Metrics" in toolbar

---

### Wrong Layout on iPad
**Problem**: Showing overlay instead of side panel

**Check**:
1. Are you in landscape? (Portrait = overlay)
2. Is it iPad or iPad Mini? (Mini portrait = overlay)
3. Try rotating device

**Note**: iPad Mini in portrait uses compact layout (overlay)

---

## Performance Optimization Tips

### For Guitar Analysis (Current Use)
**Recommended Settings**:
- FFT Size: 32,768 - 65,536
- Sample Rate: 48,000 Hz
- Expected CPU: 10-30%
- Expected Frame Rate: 40-60 Hz

### For High Precision (Research)
**Settings**:
- FFT Size: 131,072
- Sample Rate: 48,000 Hz
- Expected CPU: 40-70%
- Expected Frame Rate: 20-30 Hz

### For Maximum Speed (Live Performance)
**Settings**:
- FFT Size: 8,192 - 16,384
- Sample Rate: 44,100 Hz
- Expected CPU: 5-15%
- Expected Frame Rate: 80-120 Hz

---

## Reading the Metrics Panel

### Top to Bottom Priority

**Most Important** (Check First):
1. ● Status indicator (running or stopped?)
2. CPU Usage (< 80%?)
3. Frame Rate (> 30 Hz?)

**Important** (Monitor Regularly):
4. Average Processing (stable?)
5. Peak Frequency (detecting audio?)
6. Peak Magnitude (strong signal?)

**Nice to Know** (Reference):
7. Frequency Resolution
8. Bandwidth
9. Sample Length
10. Processing Time (instantaneous)

---

## When to Open Metrics

### Always Open When:
- [ ] First time using app (learn normal values)
- [ ] Debugging audio issues
- [ ] Optimizing performance
- [ ] Testing different settings
- [ ] App running slowly
- [ ] Developing/testing

### Can Close When:
- [ ] Everything working smoothly
- [ ] Need maximum screen space
- [ ] Presenting/demonstrating
- [ ] Know your settings are good
- [ ] End-user mode
- [ ] Performance is stable

---

## Typical Values Reference

### 65,536 FFT @ 48,000 Hz (Current Default)
```
Frequency Resolution: 0.73 Hz
Bandwidth:           24.00 kHz
Sample Length:       1.37 s
Frame Rate:          ~60 Hz
Processing Time:     2-5 ms
CPU Usage:           10-30%
```

### 32,768 FFT @ 48,000 Hz (Balanced)
```
Frequency Resolution: 1.46 Hz
Bandwidth:           24.00 kHz
Sample Length:       0.68 s
Frame Rate:          ~60 Hz
Processing Time:     1-3 ms
CPU Usage:           5-20%
```

### 16,384 FFT @ 48,000 Hz (Fast)
```
Frequency Resolution: 2.93 Hz
Bandwidth:           24.00 kHz
Sample Length:       0.34 s
Frame Rate:          ~60 Hz
Processing Time:     0.5-1.5 ms
CPU Usage:           3-10%
```

---

## Keyboard Shortcuts

### macOS Only
- `⌘ ,` - Preferences (future)
- `⌘ M` - Hide/Show Metrics (if implemented)
- `⌘ I` - Inspector (future)

### Not Yet Implemented
Request these features by adding `KeyboardShortcut` modifiers to buttons

---

## Pro Tips

💡 **Tip 1**: Watch CPU Usage, not Processing Time
Processing time jumps around, CPU % is smoothed and more reliable

💡 **Tip 2**: Green Doesn't Mean Better
50% CPU (yellow) is perfectly fine. You don't get extra points for green!

💡 **Tip 3**: Resolution vs Speed Trade-off
Can't have both ultra-high resolution AND ultra-fast updates. Pick what matters for your use case.

💡 **Tip 4**: Sample Length = 1 / Resolution
Want 0.5 Hz resolution? Need 2 second sample length.

💡 **Tip 5**: Bandwidth is Always Half Sample Rate
48 kHz sample rate = 24 kHz bandwidth (Nyquist limit)

💡 **Tip 6**: Hide Metrics in Production
End users don't need to see this. Show it during development, hide it for release.

💡 **Tip 7**: Check Metrics on Different Devices
iPad performance ≠ iPhone performance. Test on target hardware!

💡 **Tip 8**: Metrics Help You Set FFT Size
If CPU < 30%, you can probably increase FFT size for better resolution.

---

## Quick Access Checklist

Before analyzing audio:
- [ ] Open metrics panel
- [ ] Press Start
- [ ] Verify green status dot
- [ ] Check CPU < 80%
- [ ] Confirm frame rate > 30 Hz
- [ ] Close metrics if not needed

When performance seems poor:
- [ ] Open metrics panel
- [ ] Check CPU usage color
- [ ] Note processing time
- [ ] Compare to expected values (above)
- [ ] Adjust FFT size if needed
- [ ] Restart analyzer

---

## Related Documentation

- **Full Guide**: `METRICS_INTEGRATION_GUIDE.md`
- **Visual Layouts**: `METRICS_VISUAL_GUIDE.md`
- **FFT Details**: `FFT_METRICS_QUICK_START.md`
- **Source Code**: `FFTAnalysisMetricsView.swift`

---

## Support

Questions? Check:
1. This reference card
2. Full integration guide
3. Source code comments
4. Xcode console output
