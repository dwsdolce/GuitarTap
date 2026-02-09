# FFT Metrics View Integration Guide

## Overview

The `FFTAnalysisMetricsView` has been successfully integrated into the GuitarTap app. This view provides detailed real-time performance statistics and FFT analysis metrics.

## What Was Added

### 1. New State Variable
Added to `TapToneAnalysisView`:
```swift
@State private var showingMetrics = false
```

This controls whether the metrics panel is visible.

### 2. Platform-Adaptive Layout

The app now features different layouts for different platforms:

#### macOS
- **With Metrics Enabled**: `HSplitView` layout with:
  - Main content on the left (resizable, min 600pt)
  - Metrics panel on the right (resizable, 300-450pt)
- **With Metrics Disabled**: Full-width main content

#### iPad (Regular Horizontal Size Class)
- **With Metrics Enabled**: Side-by-side layout with:
  - Main content (flexible width)
  - Fixed 350pt metrics panel on the right
- **With Metrics Disabled**: Full-width main content

#### iPhone (Compact Horizontal Size Class)
- **With Metrics Enabled**: Compact overlay using `CompactFFTMetricsOverlay`
  - Small translucent card in top-right corner
  - Shows key metrics without blocking content
- **With Metrics Disabled**: Full-screen main content

### 3. Toolbar Button

Added a "Show/Hide Metrics" button in the toolbar:
- Icon changes based on state (empty/filled chart.bar)
- Label updates: "Show Metrics" / "Hide Metrics"
- Placed alongside the existing "Measurements" button

## How to Use

### For Users

1. **Show Metrics**: Tap/click the chart icon in the toolbar
2. **Hide Metrics**: Tap/click the filled chart icon to toggle off
3. **Resize (macOS/iPad)**: Drag the divider to resize the metrics panel

### What Metrics Are Displayed

The metrics view shows:

#### Analysis Configuration
- **Frequency Resolution**: Hz per FFT bin
- **Bandwidth**: 0 Hz to Nyquist frequency
- **Sample Length**: Time window duration in seconds
- **Frame Rate**: FFT calculations per second

#### Performance
- **Processing Time**: Last frame processing time (color-coded)
- **Average Processing**: 30-frame rolling average
- **CPU Usage**: Percentage of available frame time

#### Peak Detection
- **Peak Frequency**: Current dominant frequency
- **Peak Magnitude**: Signal strength in dB

#### Status Indicator
- Green dot + "Analyzing" when running
- Gray dot + "Stopped" when stopped

## Color-Coded Performance Indicators

Performance metrics use traffic-light colors:

| Color  | CPU Usage | Meaning |
|--------|-----------|---------|
| 🟢 Green | < 50% | Excellent performance |
| 🟡 Yellow | 50-80% | Good performance |
| 🟠 Orange | 80-95% | High load |
| 🔴 Red | > 95% | Critical - may drop frames |

## Components Used

### 1. FFTAnalysisMetricsView
The main detailed metrics view with grouped sections and comprehensive statistics.

**Location**: `FFTAnalysisMetricsView.swift`

### 2. CompactFFTMetricsOverlay
A compact overlay version for iPhone that shows key metrics in minimal space.

**Location**: `CompactFFTMetricsOverlay.swift`

### 3. MetricRow
A reusable component for displaying individual metrics with label, value, and subtitle.

**Defined in**: `FFTAnalysisMetricsView.swift`

## Architecture Notes

### Shared Analyzer Instance
The same `RealtimeFFTAnalyzer` instance is used for both:
- `TapToneAnalyzer` (for tap tone analysis)
- `FFTAnalysisMetricsView` (for metrics display)

This ensures:
- No duplicate FFT calculations
- Consistent performance metrics
- Single source of truth for FFT data

### Reactive Updates
Both views use `@ObservedObject` to observe the analyzer, so metrics update automatically when:
- FFT calculations complete
- Performance stats are updated
- Analyzer starts/stops

## Testing the Integration

### On macOS
1. Run the app
2. Click "Show Metrics" in toolbar
3. Verify side panel appears with metrics
4. Try resizing the split view
5. Click "Hide Metrics" to dismiss

### On iPad
1. Run on iPad or iPad Simulator
2. Rotate to landscape for regular size class
3. Tap "Show Metrics"
4. Verify 350pt panel appears on right
5. Tap "Hide Metrics" to dismiss

### On iPhone
1. Run on iPhone or iPhone Simulator
2. Tap "Show Metrics"
3. Verify compact overlay appears in top-right
4. Should not block important content
5. Tap "Hide Metrics" to dismiss

## Customization Options

### Adjust Panel Sizes

**macOS/iPad side panel width**:
```swift
.frame(width: 350)  // Change to desired width
```

**macOS minimum sizes**:
```swift
.frame(minWidth: 300, idealWidth: 350, maxWidth: 450)
```

### Change Overlay Position

**iPhone compact overlay**:
```swift
ZStack(alignment: .topTrailing) {  // Change alignment
    mainContentView
    
    if showingMetrics && horizontalSizeClass != .regular {
        CompactFFTMetricsOverlay(analyzer: fftAnalyzer)
            .padding(12)  // Adjust padding
    }
}
```

### Hide Specific Metrics

Edit `FFTAnalysisMetricsView.swift` to comment out unwanted `GroupBox` sections:
- Analysis Configuration
- Performance
- Peak Detection

## Performance Considerations

### Memory
- Metrics view is lightweight (< 1KB)
- No additional FFT calculations
- Minimal impact on memory

### CPU
- Metrics update at same rate as FFT (~60 Hz)
- UI updates are throttled by SwiftUI
- Color calculations are simple comparisons

### Best Practices
- Hide metrics panel when not needed for maximum screen space
- On iPhone, use compact overlay for at-a-glance monitoring
- Watch CPU usage metric - if consistently > 80%, consider reducing FFT size

## Related Files

- `FFTAnalysisMetricsView.swift` - Main detailed metrics view
- `CompactFFTMetricsOverlay.swift` - Compact overlay for iPhone
- `TapToneAnalysisView.swift` - Main app view with integration
- `RealtimeFFTAnalyzer.swift` - FFT analyzer providing metrics data
- `ContentView.swift` - Alternative view showing similar integration pattern

## Future Enhancements

Potential improvements:
- [ ] Add metrics export (CSV, JSON)
- [ ] Historical performance graphs
- [ ] Alert system for performance issues
- [ ] Customizable metric thresholds
- [ ] Metrics recording/playback
- [ ] Additional audio statistics (THD, SNR, etc.)

## Troubleshooting

### Metrics not updating
- Ensure analyzer is running (green status dot)
- Check that `fftAnalyzer` is properly initialized
- Verify `@ObservedObject` is used in metrics view

### Layout issues on iPad
- Check `horizontalSizeClass` is being read correctly
- Verify device is in landscape orientation
- Test on actual device, not just simulator

### Performance degradation
- Watch CPU usage metric
- Reduce FFT size if consistently > 80%
- Close other apps/system monitors
- Check for memory leaks in Instruments

## Support

For questions or issues:
1. Check this guide first
2. Review source code comments
3. Test on multiple devices/orientations
4. Check Xcode console for errors
