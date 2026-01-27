# Peak Detection and Visualization Updates

## Summary
Enhanced the tap tone analyzer with mode-specific peak detection and comprehensive spectrum visualization features.

## Changes Made

### 1. TapToneAnalyzer.swift - Mode-Based Peak Detection

#### Old Behavior
- Scanned entire frequency range once
- Limited results to top N peaks by magnitude
- Could miss important modes if they were weaker than other peaks

#### New Behavior
- **Mode-specific scanning**: Iterates through each guitar mode and searches its specific frequency range
- **Guaranteed coverage**: Ensures all mode ranges are examined
- **Multiple peaks per mode**: Can detect multiple resonances within a single mode's range
- **Duplicate removal**: Removes duplicate peaks from overlapping mode ranges

#### Implementation Details

```swift
func findPeaks(magnitudes: [Float], frequencies: [Float]) -> [ResonantPeak] {
    // Define all modes to search
    let modesToSearch: [GuitarMode] = [.helmholtz, .crossGrain, .longGrain, 
                                       .monopole, .dipole, .ringMode, .upperModes]
    
    // For each mode, search its frequency range for peaks
    for mode in modesToSearch {
        let modeRange = mode.idealRange
        // Search only within this mode's frequency range
        // Find all local maxima in the range
    }
    
    // Remove duplicates from overlapping ranges
    peaks = removeDuplicatePeaks(peaks)
    
    // Return all peaks sorted by magnitude (no arbitrary limit)
    return peaks.sorted(by: { $0.magnitude > $1.magnitude })
}
```

#### New Helper Method
```swift
private func removeDuplicatePeaks(_ peaks: [ResonantPeak]) -> [ResonantPeak]
```
- Removes peaks within 2 Hz of each other
- Keeps the peak with higher magnitude when duplicates are found
- Handles overlapping mode ranges (e.g., Helmholtz 95-105 Hz and Cross-Grain 95-110 Hz)

### 2. SpectrumView.swift - Visual Enhancements

#### New Parameters
- `peaks: [ResonantPeak]?` - Array of peaks to annotate on the chart
- `showModeBoundaries: Bool = true` - Toggle for mode boundary markers

#### Visual Features Added

##### A. Mode Boundary Markers
- **Vertical dashed lines** at the start and end of each mode's frequency range
- **Color-coded** by mode type (same colors as mode identification)
- **Mode labels** at the start of each range (abbreviated: HH, XG, LG, MP, DP, Ring, Upper)
- **Semi-transparent** (30% opacity) to avoid cluttering the spectrum
- **Dynamic visibility** - only shows boundaries within the current frequency view

##### B. Peak Annotations
Each detected peak shows:
- **Colored marker** (PointMark) at the peak's frequency/magnitude
- **Annotation box** containing:
  - Mode name (e.g., "Cross-Grain")
  - Frequency (e.g., "102.5 Hz")
  - Magnitude (e.g., "-45.3 dB")
- **Color-coded border** matching the mode type
- **Semi-transparent background** for readability

#### Color Scheme
```
Helmholtz (Air):    Cyan
Cross-Grain:        Blue
Long-Grain:         Green
Monopole:           Orange
Dipole:             Red
Ring Mode:          Purple
Upper Modes:        Gray
Unknown:            Secondary
```

#### Mode Abbreviations
```
HH:     Helmholtz (Air)
XG:     Cross-Grain
LG:     Long-Grain
MP:     Monopole
DP:     Dipole
Ring:   Ring Mode
Upper:  Upper Modes
```

### 3. TapToneAnalysisView.swift - Integration

Updated the SpectrumView call to pass:
- Current peaks from analyzer
- Enable mode boundaries display

```swift
SpectrumView(
    frequencies: ...,
    magnitudes: ...,
    // ... other parameters ...
    peaks: tapToneAnalyzer.currentPeaks,
    showModeBoundaries: true,
    onFrequencyRangeChanged: updateFrequencyInputFields
)
```

## Mode Frequency Ranges

| Mode | Ideal Range (Hz) | Typical Characteristics |
|------|-----------------|------------------------|
| Helmholtz | 95-105 | Air resonance of the body cavity |
| Cross-Grain | 95-110 | Top plate vibration across the grain |
| Long-Grain | 190-210 | Top plate vibration with the grain |
| Monopole | 220-260 | Top and back move together |
| Dipole | 380-420 | Top and back move opposite |
| Ring Mode | 650-750 | Rim/bout resonance |
| Upper Modes | 850-2000 | Higher order vibrations |

## Benefits

### For Guitar Lutherie Analysis
1. **Complete mode coverage**: No longer miss important modes due to magnitude-based filtering
2. **Multi-peak modes**: Can detect multiple resonances in the same mode range
3. **Visual reference**: Mode boundaries help identify where peaks should appear
4. **Quick identification**: Peak annotations immediately show mode classification

### For User Experience
1. **Visual guidance**: Boundary markers show expected peak locations
2. **Immediate feedback**: Annotations provide all key information at a glance
3. **Professional appearance**: Color-coded system makes the chart easy to read
4. **Educational**: Helps users learn which frequencies correspond to which modes

## Technical Implementation

### Chart Rendering Order
1. Spectrum line (red)
2. Mode boundary RuleMarks (dashed, color-coded)
3. Peak PointMarks (solid circles, color-coded)
4. Peak annotations (info boxes above peaks)

### Performance Considerations
- Boundaries and peaks are filtered to only visible range
- Duplicate removal prevents redundant rendering
- Annotations use lightweight SwiftUI views

### Future Enhancements (Potential)
- Toggle to show/hide annotations
- Click on peak to see detailed information
- Highlight specific modes on demand
- Show ideal ranges as colored background regions
- Add Q-factor visualization in annotations
