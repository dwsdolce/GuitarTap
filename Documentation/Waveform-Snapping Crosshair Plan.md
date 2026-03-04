# Plan: Waveform-Snapping Crosshair with Multi-Curve Disambiguation

## Goals
1. When frozen, snap the crosshair/cursor to the nearest point on the waveform rather than floating freely.
2. In material mode (multiple curves), color the frequency text in the readout label to match the tracked curve.
3. Lock to the curve nearest to the initial touch/hover; switch curves at intersections only when a different curve is `curveGravityThreshold` screen-points closer (gravity-based hysteresis).
4. Interpolate smoothly: parabolic near peaks (±2 bins), linear elsewhere.
5. dB text stays `.secondary` gray; only the frequency text line gets the curve color.
6. No change needed to peak dot rendering — `ResonantPeak.frequency/magnitude` already store parabolic-interpolated values from `findPeaks`.

## Files to Modify
- `GuitarTap/GuitarTap/Views/SpectrumView.swift` — all new types, state, and logic
- `GuitarTap/GuitarTap/Views/TapToneAnalysisView+SpectrumViews.swift` — pass `isSpectrumFrozen` to both SpectrumView call sites

## Step-by-Step Plan

---

### Step 1 — Add `CursorSnapState` struct (above `// MARK: - Spectrum View`, after `SpectrumDataPoint`)

```swift
struct CursorSnapState {
    let frequency: Double      // interpolated Hz
    let magnitude: Double      // interpolated dB
    let seriesIndex: Int?      // nil = primary spectrum; 0+ = materialSpectra index
    let curveColor: Color      // curve color, or .primary in single-curve mode
}
```

---

### Step 2 — Add `isSpectrumFrozen` parameter to `SpectrumView`

Near line 99 (after `hasLabelsToReset`):
```swift
/// When true the cursor/crosshair snaps to the nearest waveform point.
var isSpectrumFrozen: Bool = false
```

Pass it from both `SpectrumView(...)` call sites in `TapToneAnalysisView+SpectrumViews.swift` (macOS ~line 107, iOS ~line 131):
```swift
isSpectrumFrozen: tap.isSpectrumFrozen,
```

---

### Step 3 — Replace old position state variables

**macOS** (replace `cursorPosition` at ~line 126):
```swift
@State private var cursorSnapState: CursorSnapState? = nil
@State private var isCursorVisible: Bool = false          // unchanged
@State private var lockedSeriesIndex: Int = -1            // -1 = primary
```

**iOS** (replace `crosshairPosition` at ~line 142):
```swift
@State private var crosshairSnapState: CursorSnapState? = nil
@State private var lockedSeriesIndex: Int = -1
```

Note: `lockedSeriesIndex` is shared state across both `#if` branches — declare it once in the shared section (or duplicate under each conditional if the compiler requires it given the `#if os(macOS)` split).

---

### Step 4 — Add spectral interpolation utilities (new `// MARK: - Spectral Interpolation` section)

#### 4a. `parabolicInterpolate` (mirrors `TapToneAnalyzer+PeakAnalysis.swift` verbatim, as a `private static func`)

```swift
private static func parabolicInterpolate(
    magnitudes: [Float], frequencies: [Float], peakIndex i: Int
) -> (frequency: Float, magnitude: Float) {
    guard i > 0, i < magnitudes.count - 1 else { return (frequencies[i], magnitudes[i]) }
    let val = magnitudes[i], lval = magnitudes[i-1], rval = magnitudes[i+1]
    let denom = lval - 2 * val + rval
    guard abs(denom) > 1e-6 else { return (frequencies[i], val) }
    let delta    = 0.5 * (lval - rval) / denom
    let binWidth = frequencies[i] - frequencies[i-1]
    return (frequencies[i] + delta * binWidth, val - 0.25 * (lval - rval) * delta)
}
```

#### 4b. `snapToWaveform` — returns interpolated `(frequency, magnitude)` on a single series

Algorithm:
1. Binary search for the bin index closest to `targetHz`.
2. Check ±2 bins around that index for a local maximum.
   - If found: apply `parabolicInterpolate`.
   - Otherwise: linearly interpolate between the two bins bracketing `targetHz`.

```swift
private static func snapToWaveform(
    targetHz: Float, magnitudes: [Float], frequencies: [Float]
) -> (frequency: Float, magnitude: Float)? {
    guard magnitudes.count == frequencies.count, !frequencies.isEmpty else { return nil }
    // Binary search for nearest bin
    var lo = 0, hi = frequencies.count - 1
    while lo < hi {
        let mid = (lo + hi) / 2
        frequencies[mid] < targetHz ? (lo = mid + 1) : (hi = mid)
    }
    let nearIdx = (lo > 0 && abs(frequencies[lo-1] - targetHz) < abs(frequencies[lo] - targetHz)) ? lo-1 : lo
    // Look for local max in ±2-bin window
    let start = max(1, nearIdx - 2), end = min(magnitudes.count - 2, nearIdx + 2)
    var bestPeakIdx: Int? = nil
    for i in start...end where magnitudes[i] >= magnitudes[i-1] && magnitudes[i] >= magnitudes[i+1] {
        if bestPeakIdx.map({ magnitudes[i] > magnitudes[$0] }) ?? true { bestPeakIdx = i }
    }
    if let pi = bestPeakIdx {
        return parabolicInterpolate(magnitudes: magnitudes, frequencies: frequencies, peakIndex: pi)
    }
    // Linear interpolation between bracketing bins
    let l = max(0, nearIdx - 1), r = min(frequencies.count - 1, nearIdx)
    guard l != r else { return (frequencies[nearIdx], magnitudes[nearIdx]) }
    let t = (targetHz - frequencies[l]) / (frequencies[r] - frequencies[l])
    return (frequencies[l] + t * (frequencies[r] - frequencies[l]),
            magnitudes[l] + t * (magnitudes[r] - magnitudes[l]))
}
```

#### 4c. Gravity constant and `nearestSeriesIndex`

```swift
private static let curveGravityThreshold: CGFloat = 12.0

/// Returns the series index to lock to (-1 = primary). Only switches from
/// `lockedIndex` when a competitor curve is ≥ `curveGravityThreshold` pts closer.
private static func nearestSeriesIndex(
    targetHz: Float,
    cursorScreenY: CGFloat,
    proxy: ChartProxy,
    plotFrame: CGRect,
    materialSpectra: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String)],
    lockedIndex: Int
) -> Int {
    guard !materialSpectra.isEmpty else { return -1 }
    var candidates: [(index: Int, dist: CGFloat)] = []
    for (i, series) in materialSpectra.enumerated() {
        guard let snapped = snapToWaveform(targetHz: targetHz,
                                           magnitudes: series.magnitudes,
                                           frequencies: series.frequencies),
              let screenY = proxy.position(forY: Double(snapped.magnitude))
        else { continue }
        candidates.append((i, abs((plotFrame.minY + screenY) - cursorScreenY)))
    }
    guard !candidates.isEmpty else { return lockedIndex }
    let best = candidates.min(by: { $0.dist < $1.dist })!
    guard best.index != lockedIndex else { return lockedIndex }
    let lockedDist = candidates.first(where: { $0.index == lockedIndex })?.dist
    if let ld = lockedDist, ld - best.dist < curveGravityThreshold { return lockedIndex }
    return best.index   // switch: either no locked dist, or gravity exceeded
}
```

---

### Step 5 — Add `resolveSnapState` instance method

This is the single entry point called by both overlay functions. It runs the lock/snap logic and returns a `CursorSnapState`.

```swift
private func resolveSnapState(
    location: CGPoint,
    plotFrame: CGRect,
    proxy: ChartProxy,
    lockedSeriesIndex: inout Int
) -> CursorSnapState? {
    let plotLocal = CGPoint(x: location.x - plotFrame.minX, y: location.y - plotFrame.minY)
    guard let rawFreq = proxy.value(atX: plotLocal.x, as: Double.self),
          let rawDB   = proxy.value(atY: plotLocal.y, as: Double.self) else { return nil }

    guard isSpectrumFrozen else {
        return CursorSnapState(frequency: rawFreq, magnitude: rawDB,
                               seriesIndex: nil, curveColor: .primary)
    }
    let targetHz = Float(rawFreq)
    let newLock = Self.nearestSeriesIndex(
        targetHz: targetHz, cursorScreenY: location.y,
        proxy: proxy, plotFrame: plotFrame,
        materialSpectra: materialSpectra, lockedIndex: lockedSeriesIndex)
    lockedSeriesIndex = newLock

    let snapMags: [Float], snapFreqs: [Float], color: Color, seriesIdx: Int?
    if !materialSpectra.isEmpty, newLock >= 0, newLock < materialSpectra.count {
        let s = materialSpectra[newLock]
        (snapMags, snapFreqs, color, seriesIdx) = (s.magnitudes, s.frequencies, s.color, newLock)
    } else {
        (snapMags, snapFreqs, color, seriesIdx) = (magnitudes, frequencies, Color.primary, nil)
    }
    guard let snapped = Self.snapToWaveform(targetHz: targetHz,
                                            magnitudes: snapMags,
                                            frequencies: snapFreqs)
    else {
        return CursorSnapState(frequency: rawFreq, magnitude: rawDB,
                               seriesIndex: seriesIdx, curveColor: color)
    }
    return CursorSnapState(frequency: Double(snapped.frequency),
                           magnitude: Double(snapped.magnitude),
                           seriesIndex: seriesIdx, curveColor: color)
}
```

---

### Step 6 — Modify `cursorOverlay` (macOS, ~line 555)

Replace references to `cursorPosition` with `cursorSnapState` and call `resolveSnapState`:

- `.active(let location):` block: replace the `proxy.value` calls with:
  ```swift
  cursorSnapState = resolveSnapState(location: location, plotFrame: plotFrame,
                                     proxy: proxy, lockedSeriesIndex: &lockedSeriesIndex)
  isCursorVisible = cursorSnapState != nil
  ```
- `.ended:` block: set `cursorSnapState = nil; lockedSeriesIndex = -1; isCursorVisible = false`
- Display condition: `if isCursorVisible, let snap = cursorSnapState { cursorReadout(snap: snap, ...) }`

---

### Step 7 — Modify `crosshairOverlay` (iOS, ~line 688)

Same pattern as Step 6:

- `DragGesture.onChanged`: replace with `resolveSnapState` call → `crosshairSnapState`
- `DragGesture.onEnded`: `crosshairSnapState = nil; lockedSeriesIndex = -1`
- `onChange(of: crosshairMode.wrappedValue)`: `if !newValue { crosshairSnapState = nil; lockedSeriesIndex = -1 }`
- Display condition: `if crosshairMode.wrappedValue, let snap = crosshairSnapState { crosshairReadout(snap: snap, ...) }`

---

### Step 8 — Modify `cursorReadout` and `crosshairReadout`

Change signatures from `pos: (frequency: Double, magnitude: Double)` to `snap: CursorSnapState`.

Update coordinate calculations:
```swift
let cursorX = plotFrame.minX + (proxy.position(forX: snap.frequency) ?? 0)
let cursorY = plotFrame.minY + (proxy.position(forY: snap.magnitude) ?? 0)
```

Update the `VStack` label — frequency text gets curve color, dB text stays `.secondary`:
```swift
Text(formatCursorFrequency(snap.frequency))   // or formatCrosshairFrequency on iOS
    .font(.caption2).fontWeight(.semibold)
    .foregroundColor(snap.curveColor)          // curve color (or .primary in single-curve mode)
Text(String(format: "%.1f dB", snap.magnitude))
    .font(.caption2)
    .foregroundColor(.secondary)               // unchanged
```

---

### Step 9 — No change to peak dot rendering

`ResonantPeak.frequency` and `.magnitude` already contain parabolic-interpolated values (set by `findPeaks` in `TapToneAnalyzer+PeakAnalysis.swift`). The `peakAnnotationContent` `PointMark` is already correct.

---

## Verification

1. Build with `BuildProject` — confirm no compiler errors.
2. Run in macOS simulator / device, open a material measurement with all 3 phases captured (L, C, FLC).
3. Hover over the spectrum — confirm:
   - Cursor snaps to waveform (no free-float when frozen).
   - Frequency text color matches the curve currently being tracked.
   - Hovering near a curve intersection causes the cursor to stick to the initial curve until the other is `~12 pts` closer, then snaps across.
   - dB text remains gray.
4. Repeat on iOS — same checks via drag gesture.
5. Confirm guitar mode (single spectrum, `materialSpectra` empty) still works: cursor snaps to the single waveform, text uses `.primary` color.
6. Confirm unfrozen (live) spectrum: cursor floats freely with `.primary` color (no snapping).
