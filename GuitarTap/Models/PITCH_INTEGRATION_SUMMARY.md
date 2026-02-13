# Pitch Integration Summary

## Overview
Successfully integrated musical pitch analysis into the GuitarTap tap tone analyzer. All detected resonant peaks now include:
- Musical note name (e.g., "A4", "C#3")
- Cents offset from the nearest pitch (-50 to +50 cents)
- Frequency of the nearest pitch

## Files Modified

### 1. **Pitch.swift** (NEW)
- Converted from Python `pitch.py`
- Class for calculating musical pitch information from frequencies
- Methods:
  - `pitch(frequency:)` - Returns note index and octave
  - `note(frequency:)` - Returns formatted note string (e.g., "A4")
  - `cents(frequency:)` - Returns cents offset from nearest pitch
  - `freq0(frequency:)` - Returns frequency of nearest pitch
  - `pitchRange(frequency:)` - Returns upper and lower pitch frequencies
  - `formattedNote(frequency:)` - Returns formatted string with cents
  - `isInTune(frequency:threshold:)` - Checks if frequency is in tune

### 2. **TapToneAnalyzer.swift**
#### Changes to `ResonantPeak` struct:
- Added `pitchNote: String?` - Musical note name
- Added `pitchCents: Double?` - Cents offset from nearest pitch
- Added `pitchFrequency: Double?` - Frequency of nearest pitch
- Added `formattedPitch` computed property - Returns formatted string like "A4 (+23 ¢)"

#### Changes to `TapToneAnalyzer` class:
- Added `private let pitchCalculator = Pitch(a4: 440.0)` property
- Updated `findPeaks()` method to calculate pitch information for each detected peak:
  ```swift
  let freq = Double(frequencies[i])
  let pitchNote = pitchCalculator.note(frequency: freq)
  let pitchCents = pitchCalculator.cents(frequency: freq)
  let pitchFreq = pitchCalculator.freq0(frequency: freq)
  ```

### 3. **CombinedPeakModeRowView.swift**
- Added pitch information display in the results panel
- Shows musical note with purple music note icon
- Displays formatted pitch with cents offset
- Example: "🎵 A4 (+23 ¢)"

### 4. **SpectrumView.swift**
- Updated `PeakAnnotationLabel` to show pitch information on chart annotations
- Shows musical note name and cents offset in purple
- Format: Note name + cents offset (e.g., "A4", "+23 ¢")
- Updated preview to include pitch data in sample peaks

## Data Flow

1. **Peak Detection** (`TapToneAnalyzer.findPeaks()`)
   - Detects resonant peak at frequency (e.g., 440.5 Hz)
   - Calculates pitch information using `Pitch` class
   - Creates `ResonantPeak` with pitch data

2. **Display in Results Panel** (`CombinedPeakModeRowView`)
   - Shows formatted pitch: "A4 (+2 ¢)"
   - Displayed prominently with music note icon

3. **Display on Chart** (`SpectrumView` annotations)
   - Shows note name above frequency
   - Shows cents offset below note
   - Color-coded in purple to distinguish from other data

4. **Export/Import** (Codable)
   - All pitch fields are `Codable` and included in saved measurements
   - Automatically serialized/deserialized with JSON

## Export/Import Compatibility

### Already Compatible ✅
The pitch information is automatically included in export/import because:

1. **ResonantPeak is Codable**:
   ```swift
   struct ResonantPeak: Identifiable, Codable {
       let pitchNote: String?
       let pitchCents: Double?
       let pitchFrequency: Double?
   }
   ```

2. **TapToneMeasurement contains ResonantPeak array**:
   ```swift
   struct TapToneMeasurement: Identifiable, Codable {
       let peaks: [ResonantPeak]  // Includes all pitch data
       // ... other fields
   }
   ```

3. **JSON encoding/decoding happens automatically** via Swift's `Codable` protocol

### Backwards Compatibility
- Old measurements without pitch data: Fields will be `nil`
- New measurements: Include complete pitch information
- Views handle optional pitch data gracefully (show only when available)

## Visual Examples

### Chart Annotation:
```
┌─────────────────┐
│   Helmholtz     │
│   ♪ G2          │ ← Musical note
│   +15 ¢         │ ← Cents offset
│   98.5 Hz       │
│   -45.3 dB      │
└─────────────────┘
```

### Results Panel:
```
┌─────────────────────────────────────┐
│ [Icon] Helmholtz (Air)    98.5 Hz  │
│ 🎵 G2 (+15 ¢)                       │ ← Pitch info
│ Q: 12.5  BW: 7.9 Hz     -45.3 dB   │
└─────────────────────────────────────┘
```

## Technical Notes

### Pitch Calculation Details:
- **Reference**: A4 = 440 Hz (standard concert pitch)
- **Calculation**: Based on equal temperament (12-TET)
- **Cents**: 100 cents = 1 semitone
- **Formula**: `cents = 1200 × log₂(f₁/f₀)`

### Performance:
- Pitch calculation is very fast (simple math operations)
- Calculated once per peak during peak detection
- No performance impact on real-time analysis

## Testing

To verify the integration:

1. **Run the app** and detect peaks
2. **Check Results panel**: Should show musical notes next to frequencies
3. **Check Chart**: Annotations should show note names in purple
4. **Save measurement**: Pitch data included automatically
5. **Load measurement**: Pitch data restored correctly

## Future Enhancements (Optional)

- Add pitch bend visualization (show how far from perfect pitch)
- Add alternative tuning support (A4 = 432 Hz, historical tunings)
- Add harmonic relationship detection (octaves, fifths, etc.)
- Add pitch stability analysis over time
- Add visual pitch "sharpness" indicator (color-coded by cents offset)
