# Play File Dialog with Calibration Support

## Problem
When playing back a saved WAV file, the app uses whatever calibration is currently active for the connected microphone — but the WAV may have been recorded with a different mic/calibration (or externally). The user needs to specify both the WAV file and an optional calibration file at playback time. Both the Swift and Python apps must be updated in sync.

---

## Part A: Swift (GuitarTap Xcode project)

### Step 1: Create `PlayFileSheet.swift`

New file: `GuitarTap/GuitarTap/Views/PlayFileSheet.swift`

A modal sheet following the `SaveMeasurementSheet` pattern:
- Two file-browse rows: **Audio File** (required) and **Calibration File** (optional)
- Each row: label + file name display + "Browse…" button
- Platform-adaptive: VStack on macOS, Form on iOS (same as SaveMeasurementSheet)
- Cancel / Play buttons in toolbar
- `onPlay` closure receives `(audioURL: URL, calibrationURL: URL?)`

Content types for file importers:
- Audio: `[.audio]` (same as current)
- Calibration: `[.text, .plainText, .commaSeparatedText]` (covers `.txt`, `.cal`)

### Step 2: Update `TapToneAnalysisView.swift`

- Replace `@State var showingFilePicker = false` with `@State var showingPlayFileSheet = false`
- Remove the `.fileImporter` modifier (lines 272-290)
- Add `.sheet(isPresented: $showingPlayFileSheet) { PlayFileSheet(onPlay: openAudioFile) }`

### Step 3: Update all Play File button references

All buttons that set `showingFilePicker = true` change to `showingPlayFileSheet = true`:
- `TapToneAnalysisView+Controls.swift`: lines 190, 328
- `TapToneAnalysisView+Layouts.swift`: lines 341, 444, 716, 753
- `TapToneAnalysisView.swift` line 326 (menu action)

### Step 4: Add `setTemporaryCalibration` on `RealtimeFFTAnalyzer`

In `RealtimeFFTAnalyzer.swift`, add a method that sets `activeCalibration` without persisting:
```swift
func setTemporaryCalibration(_ calibration: MicrophoneCalibration?) {
    isLoadingDeviceCalibration = true
    activeCalibration = calibration
    isLoadingDeviceCalibration = false
}
```
Reuses the existing `isLoadingDeviceCalibration` guard (line 303) to skip UserDefaults/CalibrationStorage persistence.

### Step 5: Update `openAudioFile` signature

In `TapToneAnalysisView+Actions.swift`:
```swift
func openAudioFile(_ url: URL, calibrationURL: URL?)
```
- If `calibrationURL` is provided: parse with `CalibrationFileParser.parse(url:)`, save previous calibration, call `fftAnalyzer.setTemporaryCalibration(parsed)`.
- In the `startFromFile` completion closure: restore previous calibration via `setTemporaryCalibration(saved)`.

### Step 6: Update `playFileForTesting` for regression tests

In `TapToneAnalyzer.swift`:
```swift
func playFileForTesting(url: URL, measurementType: MeasurementType,
                        numberOfTaps: Int = 1, calibrationURL: URL? = nil) throws
```
If `calibrationURL` is provided: parse and call `fftAnalyzer.setTemporaryCalibration(parsed)`.

### Swift files to modify

| File | Change |
|------|--------|
| `Views/PlayFileSheet.swift` | **NEW** — Two-field dialog for WAV + calibration |
| `Views/TapToneAnalysisView.swift` | Replace `.fileImporter` with `.sheet`; rename state var |
| `Views/TapToneAnalysisView+Actions.swift` | Add `calibrationURL` param to `openAudioFile`; temp cal logic |
| `Views/TapToneAnalysisView+Controls.swift` | `showingFilePicker` → `showingPlayFileSheet` |
| `Views/TapToneAnalysisView+Layouts.swift` | `showingFilePicker` → `showingPlayFileSheet` |
| `Models/RealtimeFFTAnalyzer.swift` | Add `setTemporaryCalibration(_:)` |
| `Models/TapToneAnalyzer.swift` | Add optional `calibrationURL` to `playFileForTesting` |

---

## Part B: Python (guitar_tap)

### Step 7: Update `_open_audio_file` in `tap_tone_analysis_view.py`

Replace the single `QFileDialog.getOpenFileName` with a custom `QDialog` that has two file-browse rows (matching the Swift PlayFileSheet design):

Current flow (`tap_tone_analysis_view.py:2738-2795`):
- `QFileDialog.getOpenFileName()` → gets WAV path → calls `start_tap_sequence` → `start_from_file`

New flow:
- Show a `PlayFileDialog(QDialog)` with:
  - Audio File row: label + line edit (read-only) + "Browse…" button
  - Calibration File row: label + line edit (read-only) + "Browse…" button + "Clear" button
  - OK / Cancel buttons (QDialogButtonBox)
- On accept: extract WAV path and optional calibration path
- If calibration path provided: parse with `MicrophoneCalibration.from_path(path)`, apply via `set_calibration` on analyzer
- Proceed with existing `start_tap_sequence` → `start_from_file` flow
- On playback completion: restore previous calibration

### Step 8: Add temporary calibration support to Python analyzer

In `realtime_fft_analyzer.py` or `tap_tone_analyzer_control.py`:
```python
def set_temporary_calibration(self, cal: MicrophoneCalibration | None) -> None:
    """Apply calibration for file playback without persisting to storage."""
    if cal is not None:
        corrections = cal.interpolate_to_bins(self.freq)
        self.mic.set_calibration(corrections, profile=cal)
        self._active_calibration_name = cal.name
    else:
        self.mic.set_calibration(None)
        self._active_calibration_name = None
```

### Step 9: Update `play_file_for_testing` for regression tests

In `tap_tone_analyzer.py`:
```python
def play_file_for_testing(self, path, measurement_type, number_of_taps=1,
                          calibration_path=None):
```
If `calibration_path` is provided: parse and call `set_temporary_calibration`.

### Python files to modify

| File | Change |
|------|--------|
| `views/tap_tone_analysis_view.py` | Replace `QFileDialog` with `PlayFileDialog`; temp cal in `_open_audio_file` |
| `models/tap_tone_analyzer_control.py` | Add `set_temporary_calibration()` |
| `models/tap_tone_analyzer.py` | Add optional `calibration_path` to `play_file_for_testing` |

---

## Implementation order

1. Swift PlayFileSheet + wiring (Steps 1-6)
2. Build & preview verification
3. Python PlayFileDialog + wiring (Steps 7-9)

## Verification

1. **Swift build**: `BuildProject` — no errors
2. **Swift visual**: `RenderPreview` on `PlayFileSheet`
3. **Python**: Manual verification of the new dialog
