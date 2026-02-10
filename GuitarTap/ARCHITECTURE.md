# GuitarTap Architecture Guide

## Overview

GuitarTap is a cross-platform (macOS and iOS) guitar tap tone analysis application built with SwiftUI. This document outlines the architectural patterns, design decisions, and best practices used throughout the codebase.

---

## Architecture Pattern: MVVM (Model-View-ViewModel)

### Models
- **`ResonantPeak`**: Represents a detected frequency peak with metadata
- **`TapToneMeasurement`**: Complete measurement session with peaks and metadata
- **`SpectrumSnapshot`**: Frozen FFT data for recreating visualizations
- **`GuitarMode`**: Enum representing different guitar resonance modes

### View Models (ObservableObject)
- **`TapToneAnalyzer`**: Core business logic for tap detection and analysis
- **`RealtimeFFTAnalyzer`**: FFT engine and audio input handling

### Views
- **`TapToneAnalysisView`**: Main analysis interface
- **`SpectrumView`**: Interactive frequency spectrum chart
- **`TapAnalysisResultsView`**: Results panel
- **`MeasurementsListView`**: Saved measurements management

---

## Cross-Platform Design Principles

### 1. **Conditional Compilation**
Use `#if os(macOS)` and `#if os(iOS)` to provide platform-specific implementations:

```swift
#if os(macOS)
// macOS-specific layout with HSplitView
var macOSLayout: some View { ... }
#else
// iOS-specific layout with adaptive sizing
var iOSLayout: some View { ... }
#endif
```

### 2. **Platform Adapters**
Abstract platform differences through unified interfaces (see `PlatformAdapters.swift`):
- `PlatformImage` type alias
- `ImageRenderer.platformScale`
- `FileExportHelper` for unified save/share dialogs
- `ToolbarItemPlacement` extensions

### 3. **Shared Business Logic**
Keep all business logic platform-agnostic in model and view model layers:
- `TapToneAnalyzer` works identically on both platforms
- Audio processing in `RealtimeFFTAnalyzer` uses AVFoundation (available on both)

### 4. **Adaptive UI**
Use SwiftUI's environment values for adaptive layouts:

```swift
@Environment(\.horizontalSizeClass) var horizontalSizeClass

// Adapt layout based on device size
if horizontalSizeClass == .regular {
    // iPad side-by-side layout
} else {
    // iPhone sheet-based layout
}
```

---

## Key Architectural Components

### 1. **Tap Detection State Machine**

The tap detection system uses a state machine pattern with hysteresis:

**States:**
- `isDetecting: Bool` - Whether detection is active
- `isAboveThreshold: Bool` - Current signal level state
- `currentTapCount: Int` - Progress in multi-tap sequence

**State Transitions:**
1. User starts sequence → `isDetecting = true`
2. Signal crosses threshold → Tap detected, capture FFT
3. Cooldown period → Wait for next tap
4. Sequence complete → Average results, freeze display

**Key Insight:** Rising edge detection with hysteresis prevents false triggers:
```swift
let risingThreshold = tapDetectionThreshold
let fallingThreshold = tapDetectionThreshold - hysteresisMargin

// Only trigger on rising edge (BELOW→ABOVE transition)
if currentlyAboveThreshold && !isAboveThreshold {
    // TAP!
}
```

### 2. **Annotation Offset System**

Peak annotations can be dragged to prevent overlap. The system stores custom positions:

**Storage:** `[UUID: CGPoint]` dictionary keyed by peak ID
**Persistence:** Saved with measurements in JSON
**Thread Safety:** All updates go through main thread checks

**Best Practices:**
- Update offsets synchronously when already on main thread (prevents deadlock)
- Store offsets relative to default position (allows recalculation on zoom)
- Cache calculated positions during drag to reduce overhead

### 3. **Spectrum Freezing**

When a tap sequence completes, the spectrum is "frozen" to prevent live updates:

```swift
@Published var isSpectrumFrozen: Bool = false
@Published var frozenFrequencies: [Float] = []
@Published var frozenMagnitudes: [Float] = []

// In chart view:
frequencies: analyzer.isSpectrumFrozen ? 
    analyzer.frozenFrequencies : fftAnalyzer.frequencies
```

**Why?** This allows users to save/export the exact spectrum captured during taps, not whatever is currently happening.

### 4. **Multi-Tap Averaging**

To reduce noise, users can average multiple taps:

**Process:**
1. Capture raw FFT data from each tap
2. Find peaks in each capture independently
3. Group similar peaks across taps (within 5 Hz tolerance)
4. Average frequency, magnitude, Q-factor per group
5. Average raw FFT bins (in linear power domain, not dB)

**Implementation Note:** Averaging in dB domain is incorrect! Convert to linear first:
```swift
let linearPower = pow(10.0, magnitudeDB / 10.0)
// ... average linear values ...
let averageDB = 10.0 * log10(averageLinear)
```

---

## Platform-Specific Considerations

### macOS

**Layout:**
- `HSplitView` for resizable panels
- Multiple simultaneous panels (metrics + results)
- Native `NSSavePanel` for file exports
- Mouse hover effects and cursor changes

**Controls:**
- Right-click context menus
- Keyboard shortcuts (Cmd+S, etc.)
- Window chrome and title bar

**Example:**
```swift
HSplitView {
    mainContentView
        .frame(minWidth: 600)
    
    metricsPanel
        .frame(minWidth: 300, idealWidth: 350, maxWidth: 450)
}
```

### iOS

**Layout:**
- `HStack` for split view on iPad (regular size class)
- Sheet-based panels on iPhone (compact size class)
- `UIActivityViewController` for sharing
- Compact overlays for limited screen space

**Controls:**
- Gesture-based navigation
- Bottom sheets for secondary content
- Share sheets for file export

**Example:**
```swift
if horizontalSizeClass == .regular {
    // iPad: side-by-side
    HStack {
        mainContent
        Divider()
        resultsPanel.frame(width: 350)
    }
} else {
    // iPhone: overlay or sheet
    mainContent
        .sheet(isPresented: $showingResults) {
            NavigationView { resultsPanel }
        }
}
```

---

## Data Persistence

### Measurement Export Format

Measurements are saved as JSON with optional PNG images:

**Files:**
- `measurement.json` - Peak data, metadata, spectrum snapshot
- `location-timestamp.png` - Chart image (optional)

**Structure:**
```swift
struct TapToneMeasurement: Codable {
    let peaks: [ResonantPeak]
    let timestamp: Date
    let tapLocation: String?
    let spectrumSnapshot: SpectrumSnapshot?
    let chartImageFilename: String?
    let peakAnnotationOffsets: [UUID: CGPoint]?
    
    // NOT SAVED: transient runtime data
    var chartImageData: Data?  // Excluded via CodingKeys
}
```

**Why separate image file?**
- Keeps JSON human-readable
- Allows image previews in file browsers
- Reduces memory footprint when loading metadata only

### Import/Export Workflow

**Export:**
1. User saves measurement
2. Capture current spectrum → `SpectrumSnapshot`
3. Render chart to PNG → `ImageRenderer`
4. Save JSON + PNG together
5. Store reference in `savedMeasurements` array

**Import:**
1. User selects JSON file
2. Decode measurement data
3. Look for associated PNG (same directory)
4. Load image data if found
5. Append to `savedMeasurements`

---

## Performance Considerations

### 1. **FFT Processing**

**Challenge:** 65,536-point FFT at ~1.8 Hz update rate
**Solution:** Background thread processing with main thread UI updates

```swift
// NEVER do this on main thread:
try tapToneAnalyzer.start()

// Instead:
DispatchQueue.global(qos: .userInitiated).async {
    try self.tapToneAnalyzer.start()
}
```

### 2. **Chart Rendering**

**Challenge:** Rendering 10,000+ data points in real-time
**Solution:** Filter data to visible range only

```swift
private var chartData: [SpectrumDataPoint] {
    zip(frequencies, magnitudes)
        .filter { $0.0 >= minFreq && $0.0 <= maxFreq }  // ← Key optimization
        .map { SpectrumDataPoint(frequency: $0.0, magnitude: $0.1) }
}
```

### 3. **Annotation Position Caching**

**Challenge:** Recalculating annotation positions every frame during drag
**Solution:** Cache positions at drag start, reuse during gesture

```swift
@State private var cachedChartPosition: CGPoint = .zero

// On drag start:
if !isDragging {
    isDragging = true
    cachedChartPosition = calculateChartPosition()  // Expensive!
}

// During drag:
let position = CGPoint(
    x: cachedChartPosition.x + dragOffset.width,  // Cheap!
    y: cachedChartPosition.y + dragOffset.height
)
```

### 4. **Transaction Animation Control**

**Challenge:** SwiftUI animations interfere with smooth dragging
**Solution:** Disable animations during interactive gestures

```swift
var transaction = Transaction()
transaction.disablesAnimations = true
withTransaction(transaction) {
    onOffsetChange(newOffset)
}
```

---

## Testing Strategy

### Unit Tests
- Peak detection algorithm
- Tap tone ratio calculations
- Mode classification logic
- FFT averaging math

### Integration Tests
- Multi-tap sequence flow
- Save/load measurement cycle
- Export/import round-trip

### Platform-Specific Tests
- macOS: `HSplitView` resizing
- iOS: Sheet presentation on different size classes

---

## Code Organization Best Practices

### File Structure
```
GuitarTap/
├── Models/
│   ├── TapToneAnalyzer.swift       (Business logic + models)
│   └── RealtimeFFTAnalyzer.swift   (Audio engine)
├── Views/
│   ├── TapToneAnalysisView.swift   (Main interface)
│   ├── SpectrumView.swift          (Chart component)
│   ├── TapAnalysisResultsView.swift
│   └── MeasurementsListView.swift
├── Components/
│   ├── Extensions.swift            (Float, GuitarMode extensions)
│   ├── PlatformAdapters.swift      (Cross-platform helpers)
│   └── LoadingOverlay.swift        (Reusable UI)
└── GuitarTapApp.swift              (App entry point)
```

### Naming Conventions
- **Views:** `[Feature]View` (e.g., `SpectrumView`)
- **Models:** Descriptive nouns (e.g., `ResonantPeak`)
- **View Models:** `[Feature]Analyzer` or `[Feature]Manager`
- **State Properties:** Descriptive bools (e.g., `isSpectrumFrozen`)

### Documentation
- Use `/// ...` for public APIs
- Include `- Parameter` and `- Returns` tags
- Add `- Note` for important implementation details
- Document **why**, not just **what**

Example:
```swift
/// Handles pinch-to-zoom gestures on both frequency and dB axes.
///
/// The zoom is centered on the midpoint of the current visible range.
/// Different zoom algorithms are used for logarithmic vs. linear frequency scales.
///
/// - Parameter scale: The magnification factor from the gesture (> 1 = zoom in, < 1 = zoom out)
///
/// - Note: Zoom ranges are clamped to reasonable limits to prevent invalid states
private func handleZoom(scale: CGFloat) { ... }
```

---

## Common Pitfalls & Solutions

### 1. **Main Thread Deadlock**
**Problem:** Calling `DispatchQueue.main.async` when already on main thread can cause deadlock in some cases.

**Solution:**
```swift
if Thread.isMainThread {
    // Update directly
    self.property = value
} else {
    DispatchQueue.main.async {
        self.property = value
    }
}
```

### 2. **Gesture Interference**
**Problem:** Multiple gesture recognizers fighting for touch events.

**Solution:** Use `.allowsHitTesting()` strategically:
```swift
.overlay(
    GeometryReader { plotGeometry in
        ZStack {
            // Draggable annotations
        }
        .allowsHitTesting(true)  // ← Allow annotations to capture gestures
    }
    .allowsHitTesting(true)      // ← Allow overlay to receive events
)
```

### 3. **Logarithmic Scale Calculations**
**Problem:** Pan/zoom feels wrong on log scale when using linear math.

**Solution:** Work in log space for logarithmic scales:
```swift
if isLogarithmic {
    let logMin = log10(Double(minFreq))
    let logMax = log10(Double(maxFreq))
    let logCenter = (logMin + logMax) / 2
    // ... zoom/pan in log space ...
    newMinFreq = Float(pow(10, logCenter - newRange/2))
}
```

### 4. **Audio Session Lifecycle (iOS)**
**Problem:** Audio session conflicts with other apps or doesn't handle interruptions.

**Solution:** Configure properly and handle interruptions:
```swift
#if os(iOS)
let session = AVAudioSession.sharedInstance()
try session.setCategory(.record, mode: .measurement, options: [])
try session.setActive(true)

// TODO: Add interruption handling
NotificationCenter.default.addObserver(
    forName: AVAudioSession.interruptionNotification,
    object: session,
    queue: .main
) { notification in
    // Handle interruption
}
#endif
```

---

## Future Enhancements

### 1. **SwiftData Migration**
Consider migrating from JSON persistence to SwiftData for:
- Better query performance
- Sync with iCloud
- Rich relationships between measurements

### 2. **Accessibility**
- VoiceOver labels for all interactive elements
- Dynamic Type support for text
- High contrast mode support

### 3. **Export Formats**
- CSV export for spreadsheet analysis
- PDF reports with multiple measurements
- Batch export functionality

### 4. **Advanced Features**
- Comparison mode (overlay two spectra)
- Time-domain waveform view
- Harmonic analysis
- Guitar builder database integration

---

## Conclusion

This architecture balances several competing concerns:
- **Performance:** Real-time FFT analysis without UI lag
- **Usability:** Platform-appropriate UI conventions
- **Maintainability:** Shared logic, minimal duplication
- **Extensibility:** Easy to add new features

The key insight is to keep platform differences isolated at the UI layer while sharing all business logic. Use SwiftUI's built-in adaptation (environment values, size classes) where possible, and only resort to conditional compilation when truly necessary.

---

**Last Updated:** February 9, 2026
**Version:** 1.0
