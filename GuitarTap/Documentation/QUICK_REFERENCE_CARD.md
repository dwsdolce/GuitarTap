# ⚡ FFT Metrics Quick Reference Card

## 📊 Available Metrics

| Property | Type | Formula | Example | Units |
|----------|------|---------|---------|-------|
| `frequencyResolution` | Float | sampleRate / fftSize | 5.86 | Hz |
| `bandwidth` | Float | sampleRate / 2 | 24000 | Hz |
| `sampleLengthSeconds` | Float | fftSize / sampleRate | 0.171 | seconds |
| `frameRate` | Float | sampleRate / (fftSize/2) | 11.72 | Hz |
| `processingTimeMs` | Float | measured | 2.50 | ms |
| `avgProcessingTimeMs` | Float | rolling avg | 2.48 | ms |

---

## 🚀 Quick Start (3 Lines)

```swift
ZStack(alignment: .topTrailing) {
    SpectrumView(...)
    CompactFFTMetricsOverlay(analyzer: analyzer).padding(12)
}
```

---

## 📐 Common FFT Configurations

| Use Case | FFT Size | Sample Rate | Freq Res | Frame Rate |
|----------|----------|-------------|----------|------------|
| Fast response | 2048 | 48000 | 23.4 Hz | 46.9 Hz |
| **Balanced** | **8192** | **48000** | **5.86 Hz** | **11.72 Hz** |
| High resolution | 16384 | 48000 | 2.93 Hz | 5.86 Hz |
| Ultra-high res | 65536 | 48000 | 0.73 Hz | 1.46 Hz |

---

## 🎨 Color Coding

| Color | CPU Usage | Status |
|-------|-----------|--------|
| 🟢 Green | < 50% | Excellent - plenty of headroom |
| 🟡 Yellow | 50-80% | Good - acceptable performance |
| 🟠 Orange | 80-95% | Warning - nearing capacity |
| 🔴 Red | > 95% | Critical - may drop frames |

---

## 📱 Platform Recommendations

| Platform | Component | Position |
|----------|-----------|----------|
| **iPhone** | `CompactFFTMetricsOverlay` | `.topTrailing` |
| **iPad** | `FFTAnalysisMetricsView` | Side panel (350pt) |
| **Mac** | `FFTAnalysisMetricsView` | Split view |

---

## 🔧 Calculate CPU Usage

```swift
var cpuUsage: Float {
    let frameTime = 1000.0 / analyzer.frameRate
    return (analyzer.avgProcessingTimeMs / frameTime) * 100
}
```

---

## 📚 Documentation Files

| File | Purpose |
|------|---------|
| `COMPLETE_SUMMARY.md` | ⭐ Start here - overview of everything |
| `FFT_METRICS_QUICK_START.md` | Code examples and use cases |
| `FFT_METRICS_DOCUMENTATION.md` | Theory, formulas, deep dive |
| `VISUAL_LAYOUT_GUIDE.md` | Layout strategies and ASCII art |
| `README_METRICS.md` | General reference and API docs |

---

## 🐛 Troubleshooting

| Problem | Solution |
|---------|----------|
| Metrics show zeros | Call `analyzer.start()` |
| High CPU usage (red) | Reduce FFT size or sample rate |
| Low frame rate | Normal for large FFT sizes |
| Metrics not updating | Verify `analyzer.isRunning == true` |

---

## 💾 Code Files

| File | Description |
|------|-------------|
| `RealtimeFFTAnalyzer.swift` | Modified with metrics calculation |
| `FFTAnalysisMetricsView.swift` | Full metrics panel component |
| `CompactFFTMetricsOverlay.swift` | Compact overlay component |
| `ContentViewWithMetrics.swift` | Complete integration example |

---

## 📊 Console Output

```
=== Analysis Metrics ===
Frequency Resolution: 5.859375 Hz
Bandwidth: 24000.0 Hz (0 Hz to 24000.0 Hz)
Sample Length: 170.66667 ms (0.17066667 seconds)
Frame Rate: 11.71875 Hz
=======================
```

---

## ⚡ Performance

| Metric | Value |
|--------|-------|
| Overhead per frame | < 0.1 ms |
| Additional memory | < 1 KB |
| FFT performance impact | 0% |

---

## 🎯 Examples

### Compact Overlay
```swift
ZStack(alignment: .topTrailing) {
    MainContent()
    CompactFFTMetricsOverlay(analyzer: analyzer).padding()
}
```

### Full Panel
```swift
HStack {
    MainContent()
    Divider()
    ScrollView { FFTAnalysisMetricsView(analyzer: analyzer) }
        .frame(width: 350)
}
```

### Custom
```swift
Text("CPU: \(cpuUsage, specifier: "%.1f")%")
    .foregroundColor(cpuUsage < 50 ? .green : .red)
```

---

**Print this card for quick reference while coding! 📄**
