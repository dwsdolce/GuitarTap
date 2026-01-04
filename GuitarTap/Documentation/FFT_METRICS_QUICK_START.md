# FFT Metrics Quick Start Guide

## Overview

The FFT analyzer now calculates and displays comprehensive metrics about its analysis configuration and performance. This guide shows you how to access and display these metrics.

## Available Metrics

The `RealtimeFFTAnalyzer` publishes the following metrics (all are `@Published` properties):

### Analysis Configuration
- `frequencyResolution: Float` - Hz per FFT bin
- `bandwidth: Float` - Maximum frequency (Nyquist)
- `sampleLengthSeconds: Float` - Time window duration in seconds
- `frameRate: Float` - FFT calculations per second

### Performance
- `processingTimeMs: Float` - Last frame processing time in milliseconds
- `avgProcessingTimeMs: Float` - 30-frame rolling average in milliseconds

### Detection Results
- `peakFrequency: Float` - Dominant frequency in Hz
- `peakMagnitude: Float` - Peak magnitude in dB

## Display Options

### Option 1: Full Metrics Panel (Recommended for iPad/Mac)

Use `FFTAnalysisMetricsView` for a comprehensive, organized display:

```swift
import SwiftUI

struct MyView: View {
    @StateObject private var analyzer = RealtimeFFTAnalyzer(
        fftSize: 8192,
        targetSampleRate: 48000
    )
    
    var body: some View {
        HStack {
            // Your main content
            SpectrumView(...)
            
            // Metrics panel on the side
            ScrollView {
                FFTAnalysisMetricsView(analyzer: analyzer)
            }
            .frame(width: 350)
        }
    }
}
```

**Features:**
- Analysis configuration section
- Performance monitoring with color-coded warnings
- Peak detection display
- CPU usage calculation
- Status indicator

---

### Option 2: Compact Overlay (Recommended for iOS)

Use `CompactFFTMetricsOverlay` for a small, translucent overlay:

```swift
import SwiftUI

struct MyView: View {
    @StateObject private var analyzer = RealtimeFFTAnalyzer(
        fftSize: 4096,
        targetSampleRate: 44100
    )
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Your spectrum chart
            SpectrumView(
                frequencies: analyzer.frequencies,
                magnitudes: analyzer.magnitudes,
                minFreq: $minFreq,
                maxFreq: $maxFreq,
                minDB: $minDB,
                maxDB: $maxDB,
                isLogarithmic: $isLogarithmic
            )
            
            // Compact metrics overlay
            CompactFFTMetricsOverlay(analyzer: analyzer)
                .padding(12)
        }
    }
}
```

**Positioning options:**
- `.topTrailing` - Top right corner
- `.topLeading` - Top left corner  
- `.bottomLeading` - Bottom left
- `.bottomTrailing` - Bottom right

---

### Option 3: Custom Display

Access the metrics directly to build your own UI:

```swift
import SwiftUI

struct CustomMetricsView: View {
    @ObservedObject var analyzer: RealtimeFFTAnalyzer
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Configuration")
                .font(.headline)
            
            Text("Frequency Resolution: \(analyzer.frequencyResolution, specifier: "%.2f") Hz")
            Text("Bandwidth: \(analyzer.bandwidth / 1000, specifier: "%.1f") kHz")
            Text("Sample Length: \(analyzer.sampleLengthSeconds * 1000, specifier: "%.1f") ms")
            Text("Frame Rate: \(analyzer.frameRate, specifier: "%.1f") Hz")
            
            Divider()
            
            Text("Performance")
                .font(.headline)
            
            Text("Processing: \(analyzer.avgProcessingTimeMs, specifier: "%.2f") ms")
            
            // Calculate CPU usage
            let frameTime = 1000.0 / analyzer.frameRate
            let cpuUsage = (analyzer.avgProcessingTimeMs / frameTime) * 100
            
            Text("CPU Usage: \(cpuUsage, specifier: "%.1f")%")
                .foregroundColor(cpuUsageColor(cpuUsage))
        }
        .padding()
    }
    
    private func cpuUsageColor(_ usage: Float) -> Color {
        usage < 50 ? .green : usage < 80 ? .yellow : .red
    }
}
```

---

## Console Output

The analyzer also prints metrics to the console when started:

```
=== Analysis Metrics ===
Frequency Resolution: 5.859375 Hz
Bandwidth: 24000.0 Hz (0 Hz to 24000.0 Hz)
Sample Length: 170.66667 ms (0.17066667 seconds)
Frame Rate: 11.71875 Hz
=======================
```

This is useful for debugging and verification during development.

---

## Examples for Different Use Cases

### Music Analysis (High Frequency Resolution)

```swift
@StateObject private var analyzer = RealtimeFFTAnalyzer(
    fftSize: 16384,      // Large FFT for precise frequency detection
    targetSampleRate: 48000
)

// Results:
// - Frequency Resolution: ~2.93 Hz (can distinguish musical notes)
// - Frame Rate: ~2.93 Hz (updates every ~341 ms)
// - Good for: Pitch detection, tuner apps, music theory tools
```

### Real-Time Visualizer (Balanced)

```swift
@StateObject private var analyzer = RealtimeFFTAnalyzer(
    fftSize: 8192,       // Balanced size
    targetSampleRate: 48000
)

// Results:
// - Frequency Resolution: ~5.86 Hz (good for general audio)
// - Frame Rate: ~11.72 Hz (smooth ~12 fps updates)
// - Good for: Spectrum analyzers, audio effects visualization
```

### Fast Response (Low Latency)

```swift
@StateObject private var analyzer = RealtimeFFTAnalyzer(
    fftSize: 2048,       // Small FFT for quick response
    targetSampleRate: 48000
)

// Results:
// - Frequency Resolution: ~23.4 Hz (less precise)
// - Frame Rate: ~23.4 Hz (very responsive ~23 fps)
// - Good for: Beat detection, rhythm analysis, VU meters
```

### Ultra-High Resolution (Research/Studio)

```swift
@StateObject private var analyzer = RealtimeFFTAnalyzer(
    fftSize: 65536,      // Very large FFT
    targetSampleRate: 96000
)

// Results:
// - Frequency Resolution: ~1.46 Hz (extremely precise)
// - Frame Rate: ~1.46 Hz (slow updates every ~683 ms)
// - Good for: Scientific analysis, studio mixing, steady signals
```

---

## Performance Monitoring

### Understanding CPU Usage

The CPU usage metric shows what percentage of available time is used for FFT processing:

```
CPU Usage = (avgProcessingTime / frameTime) × 100%

where:
  frameTime = 1000 ms / frameRate
```

**Example:**
- Frame Rate: 11.72 Hz → Frame time = 85.3 ms
- Avg Processing: 2.5 ms
- CPU Usage: (2.5 / 85.3) × 100% = **2.9%**

### Color Coding

Both `FFTAnalysisMetricsView` and `CompactFFTMetricsOverlay` use color coding:

- 🟢 **Green (< 50%)**: Excellent - plenty of headroom
- 🟡 **Yellow (50-80%)**: Good - acceptable performance  
- 🟠 **Orange (80-95%)**: Warning - approaching limits
- 🔴 **Red (> 95%)**: Critical - may drop frames

### Optimization Tips

If you see high CPU usage (yellow/orange/red):

1. **Reduce FFT size**: Try half the current size
2. **Lower sample rate**: Use 44100 Hz instead of 48000 Hz
3. **Reduce overlap**: Modify code to use 0% overlap instead of 50%
4. **Limit frequency range**: Filter data before FFT if you only need specific frequencies
5. **Optimize display**: Reduce chart update frequency independently

---

## Complete Integration Example

Here's a complete example showing all three display options in a tabbed interface:

```swift
import SwiftUI

struct FFTAnalyzerApp: View {
    @StateObject private var analyzer = RealtimeFFTAnalyzer(
        fftSize: 8192,
        targetSampleRate: 48000
    )
    
    var body: some View {
        TabView {
            // Tab 1: Spectrum with compact overlay
            SpectrumWithOverlay(analyzer: analyzer)
                .tabItem {
                    Label("Spectrum", systemImage: "waveform")
                }
            
            // Tab 2: Full metrics panel
            ScrollView {
                FFTAnalysisMetricsView(analyzer: analyzer)
            }
            .tabItem {
                Label("Metrics", systemImage: "chart.bar")
            }
            
            // Tab 3: Custom combined view
            SideBySideView(analyzer: analyzer)
                .tabItem {
                    Label("Combined", systemImage: "square.split.2x1")
                }
        }
    }
}

struct SpectrumWithOverlay: View {
    @ObservedObject var analyzer: RealtimeFFTAnalyzer
    @State private var minFreq: Float = 20
    @State private var maxFreq: Float = 5000
    @State private var minDB: Float = -80
    @State private var maxDB: Float = 0
    @State private var isLogarithmic = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack {
                SpectrumView(
                    frequencies: analyzer.frequencies,
                    magnitudes: analyzer.magnitudes,
                    minFreq: $minFreq,
                    maxFreq: $maxFreq,
                    minDB: $minDB,
                    maxDB: $maxDB,
                    isLogarithmic: $isLogarithmic
                )
                
                Button(analyzer.isRunning ? "Stop" : "Start") {
                    toggleAnalyzer()
                }
                .buttonStyle(.borderedProminent)
            }
            
            CompactFFTMetricsOverlay(analyzer: analyzer)
                .padding()
        }
    }
    
    private func toggleAnalyzer() {
        if analyzer.isRunning {
            analyzer.stop()
        } else {
            try? analyzer.start()
        }
    }
}

struct SideBySideView: View {
    @ObservedObject var analyzer: RealtimeFFTAnalyzer
    
    var body: some View {
        HStack {
            // Spectrum on left
            SpectrumWithOverlay(analyzer: analyzer)
            
            Divider()
            
            // Metrics panel on right
            ScrollView {
                FFTAnalysisMetricsView(analyzer: analyzer)
            }
            .frame(width: 350)
        }
    }
}
```

---

## Troubleshooting

### Metrics show zeros

**Problem:** All metrics display as 0.0  
**Solution:** Call `analyzer.start()` - metrics are updated when the analyzer is running

### High CPU usage (red)

**Problem:** CPU usage shows > 95%, possible frame drops  
**Solutions:**
- Reduce FFT size (try 4096 or 2048)
- Lower sample rate to 44100 Hz
- Close other apps to free up CPU
- Test on a faster device

### Frame rate seems low

**Problem:** Frame rate is lower than expected  
**Explanation:** Frame rate depends on FFT size and overlap:
- Larger FFT = slower frame rate (this is normal)
- With 50% overlap: frameRate = sampleRate / (fftSize / 2)
- Example: 48000 / (8192/2) = 11.72 Hz is expected

### Processing time fluctuates

**Problem:** Processing time jumps around  
**Solution:** Look at average processing time instead - it smooths out spikes  
**Note:** Some variation is normal due to system load

---

## See Also

- `FFT_METRICS_DOCUMENTATION.md` - Detailed explanation of all metrics
- `RealtimeFFTAnalyzer.swift` - Main analyzer implementation
- `FFTAnalysisMetricsView.swift` - Full metrics panel view
- `CompactFFTMetricsOverlay.swift` - Compact overlay view
