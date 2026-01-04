# Making SpectrumView Expand with Window Size

## Problem

Currently, SpectrumView has a fixed height of 300 points wherever it's used:

```swift
SpectrumView(...)
    .frame(height: 300)  // ← Fixed height
```

This prevents it from expanding when the window is resized.

---

## Solution: Make Height Flexible

### Option 1: Use Available Space (Recommended)

Replace fixed height with flexible frame modifiers:

```swift
// Before
SpectrumView(...)
    .frame(height: 300)

// After - Fill available space
SpectrumView(...)
    .frame(maxHeight: .infinity)
```

### Option 2: Minimum Height with Growth

Set a minimum height but allow it to grow:

```swift
SpectrumView(...)
    .frame(minHeight: 200, maxHeight: .infinity)
```

### Option 3: Specific Range

Define both minimum and ideal height:

```swift
SpectrumView(...)
    .frame(minHeight: 200, idealHeight: 400, maxHeight: .infinity)
```

---

## Where to Make Changes

### 1. In ContentView.swift

Find where SpectrumView is used (likely in the `mainContentView` property):

```swift
// Current code (somewhere around line 650-700):
SpectrumView(
    frequencies: analyzer.frequencies,
    magnitudes: analyzer.magnitudes,
    minFreq: $minFreq,
    maxFreq: $maxFreq,
    minDB: $minDB,
    maxDB: $maxDB,
    isLogarithmic: $isLogarithmic,
    onFrequencyRangeChanged: updateFrequencyInputFields
)
.frame(height: 300)  // ← CHANGE THIS
.padding()
.background(Color.gray.opacity(0.05))
.cornerRadius(10)

// New code:
SpectrumView(
    frequencies: analyzer.frequencies,
    magnitudes: analyzer.magnitudes,
    minFreq: $minFreq,
    maxFreq: $maxFreq,
    minDB: $minDB,
    maxDB: $maxDB,
    isLogarithmic: $isLogarithmic,
    onFrequencyRangeChanged: updateFrequencyInputFields
)
.frame(minHeight: 200, maxHeight: .infinity)  // ← FLEXIBLE HEIGHT
.padding()
.background(Color.gray.opacity(0.05))
.cornerRadius(10)
```

### 2. In ContentViewWithMetrics.swift (if you use it)

Same change:

```swift
// Around line 100-110:
SpectrumView(
    frequencies: analyzer.frequencies,
    magnitudes: analyzer.magnitudes,
    minFreq: $minFreq,
    maxFreq: $maxFreq,
    minDB: $minDB,
    maxDB: $maxDB,
    isLogarithmic: $isLogarithmic
)
.frame(height: 300)  // ← CHANGE THIS
.padding()
.background(Color.gray.opacity(0.05))
.cornerRadius(10)

// To:
.frame(minHeight: 200, maxHeight: .infinity)  // ← FLEXIBLE HEIGHT
```

### 3. In Preview (SpectrumView.swift)

The preview can keep fixed height for consistency, but you can also make it flexible:

```swift
// At the bottom of SpectrumView.swift:
return SpectrumView(
    frequencies: sampleFrequencies,
    magnitudes: sampleMagnitudes,
    minFreq: $minFreq,
    maxFreq: $maxFreq,
    minDB: $minDB,
    maxDB: $maxDB,
    isLogarithmic: $isLogarithmic
)
.frame(height: 300)  // ← Keep this for preview consistency
.padding()
```

---

## Implementation Steps

### Step 1: Find All Usages

Search your project for `.frame(height: 300)` near SpectrumView:

1. In Xcode: **Cmd+Shift+F** (Find in Project)
2. Search for: `SpectrumView(`
3. Look for `.frame(height:` on nearby lines

### Step 2: Replace Fixed Height

For each usage, change:

```swift
.frame(height: 300)
```

To:

```swift
.frame(minHeight: 200, maxHeight: .infinity)
```

### Step 3: Adjust Layout Container

Make sure the container VStack allows growth:

```swift
VStack(spacing: 20) {
    // ... title and controls ...
    
    // Spectrum section - add Spacer() if needed
    VStack(alignment: .leading, spacing: 8) {
        // ... toolbar ...
        
        SpectrumView(...)
            .frame(minHeight: 200, maxHeight: .infinity)  // ← Flexible
            .padding()
    }
    
    // ... buttons ...
    
    // Remove or adjust Spacer() at bottom
    // Spacer()  // ← This might prevent growth
}
```

### Step 4: Test on All Platforms

- **iPhone**: Should fill available space in tab
- **iPad**: Should expand in side-by-side layout
- **Mac**: Should resize with window

---

## Platform-Specific Considerations

### iPhone (Compact)

In tab view, spectrum should fill available space:

```swift
TabView {
    ZStack(alignment: .topTrailing) {
        mainContentView  // Contains flexible SpectrumView
        CompactFFTMetricsOverlay(analyzer: analyzer).padding(12)
    }
    .tabItem { Label("Spectrum", systemImage: "waveform.path") }
}
```

### iPad (Regular)

In side-by-side layout, spectrum should expand vertically:

```swift
HStack(spacing: 0) {
    mainContentView  // Contains flexible SpectrumView
        .frame(maxWidth: .infinity)
    
    Divider()
    
    ScrollView {
        FFTAnalysisMetricsView(analyzer: analyzer).padding()
    }
    .frame(width: 350)
}
```

### macOS

In split view, spectrum should resize with panel:

```swift
HSplitView {
    mainContentView  // Contains flexible SpectrumView
        .frame(minWidth: 600, idealWidth: 800)
    
    ScrollView {
        FFTAnalysisMetricsView(analyzer: analyzer).padding()
    }
    .frame(minWidth: 300, idealWidth: 350, maxWidth: 450)
}
```

---

## Common Issues & Solutions

### Issue: Chart doesn't expand

**Cause:** Container has `Spacer()` at bottom or fixed height

**Solution:**
```swift
VStack {
    // ... content ...
    
    SpectrumView(...)
        .frame(maxHeight: .infinity)  // ← Must have this
    
    // Remove this if present:
    // Spacer()
    
    // Buttons should stay at bottom
    Button(...) { }
}
```

### Issue: Chart is too small

**Cause:** No minimum height set

**Solution:**
```swift
SpectrumView(...)
    .frame(minHeight: 200, maxHeight: .infinity)  // ← Add minimum
```

### Issue: Chart is too large on iPhone

**Cause:** Takes up entire screen, pushing buttons off

**Solution:**
```swift
VStack {
    // ... title ...
    
    SpectrumView(...)
        .frame(minHeight: 150, maxHeight: 500)  // ← Cap maximum
    
    // ... controls ...
}
```

### Issue: Doesn't resize when window changes

**Cause:** Fixed frame somewhere in parent hierarchy

**Solution:** Check all parent views for fixed heights:
```swift
// Bad:
VStack {
    SpectrumView(...).frame(maxHeight: .infinity)
}
.frame(height: 500)  // ← This prevents resizing!

// Good:
VStack {
    SpectrumView(...).frame(maxHeight: .infinity)
}
.frame(maxHeight: .infinity)  // ← Now it can resize
```

---

## Recommended Configuration

### For Best Results

```swift
// In the spectrum section of your view:
VStack(alignment: .leading, spacing: 8) {
    // Toolbar
    HStack {
        Text("Frequency Spectrum").font(.headline)
        Spacer()
        Toggle(isOn: $isLogarithmic) { Text("Logarithmic") }
        Button(action: resetZoom) { Text("Reset Zoom") }
    }
    
    // Range controls (if you have them)
    // ...
    
    // ★ The chart - with flexible height ★
    SpectrumView(
        frequencies: analyzer.frequencies,
        magnitudes: analyzer.magnitudes,
        minFreq: $minFreq,
        maxFreq: $maxFreq,
        minDB: $minDB,
        maxDB: $maxDB,
        isLogarithmic: $isLogarithmic,
        onFrequencyRangeChanged: updateFrequencyInputFields
    )
    .frame(minHeight: 200, maxHeight: .infinity)  // ← Key change
    .padding()
    .background(Color.gray.opacity(0.05))
    .cornerRadius(10)
    
    // Range display
    HStack {
        Text("Range: \(formatFrequency(minFreq)) - \(formatFrequency(maxFreq))")
            .font(.caption)
        Spacer()
        Text("\(Int(minDB)) to \(Int(maxDB)) dB")
            .font(.caption)
    }
}
.padding()
```

---

## Complete Example

Here's a complete example of a properly sized spectrum view:

```swift
struct MyContentView: View {
    @StateObject private var analyzer = RealtimeFFTAnalyzer(...)
    @State private var minFreq: Float = 75
    @State private var maxFreq: Float = 350
    @State private var minDB: Float = -100
    @State private var maxDB: Float = 0
    @State private var isLogarithmic = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text("Real-Time FFT Analyzer")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Peak frequency display (fixed height - OK)
            VStack {
                Text("Peak: \(analyzer.peakFrequency, specifier: "%.1f") Hz")
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(15)
            
            // Spectrum section - THIS EXPANDS ★
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Frequency Spectrum").font(.headline)
                    Spacer()
                    Toggle(isOn: $isLogarithmic) { Text("Log") }
                }
                
                // The chart - flexible height
                SpectrumView(
                    frequencies: analyzer.frequencies,
                    magnitudes: analyzer.magnitudes,
                    minFreq: $minFreq,
                    maxFreq: $maxFreq,
                    minDB: $minDB,
                    maxDB: $maxDB,
                    isLogarithmic: $isLogarithmic
                )
                .frame(minHeight: 200, maxHeight: .infinity)  // ← FLEXIBLE
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(10)
            }
            .padding()
            
            // Controls (fixed height - OK)
            Button(action: { /* ... */ }) {
                Text("Start")
            }
            
            // NO Spacer() here - allows spectrum to expand
        }
        .padding()
    }
}
```

---

## Testing Checklist

After making changes:

- [ ] **iPhone Portrait**: Chart fills most of vertical space
- [ ] **iPhone Landscape**: Chart fills available space
- [ ] **iPad Portrait**: Chart expands with window height
- [ ] **iPad Landscape**: Chart expands in split view
- [ ] **Mac**: Chart resizes when dragging window edge
- [ ] **Mac**: Chart resizes when dragging split view divider
- [ ] **Minimum height**: Chart never gets too small (200pt min)
- [ ] **Controls visible**: Buttons don't get pushed off screen

---

## Summary

**Quick Fix:**

1. Find: `.frame(height: 300)`
2. Replace with: `.frame(minHeight: 200, maxHeight: .infinity)`
3. Remove any `Spacer()` that might interfere
4. Test on all platforms

**Result:** SpectrumView now expands to fill available vertical space while maintaining a reasonable minimum height! 🎉
