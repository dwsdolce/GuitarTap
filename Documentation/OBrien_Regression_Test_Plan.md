# Regression Test: O'Brien 8-Tap Generic Guitar Recording

## Overview

Add a REG-G2 regression test (Swift + Python) to the existing file playback regression test suites. This test plays `Recording.wav` — a live 8-tap generic guitar recording from a user — through the full analysis pipeline and validates that the averaged and all 8 individual taps produce the correct Air, Top, and Back frequencies and magnitudes.

This implements the REG-G2 case ("Guitar multi-tap averaging") from `File-Playback-Regression-Test-Plan.md`. REG-G1 ("Guitar single-tap") is covered for free by the averaged-peaks validation within this test.

**No duplicated analysis logic in the test.** The test relies entirely on the pipeline's own mode classification and peak selection — the same code paths used by the production UI:
- **Average peaks:** `sut.getPeak(for: .air)`, `.top`, `.back` (uses `identifiedModes`)
- **Per-tap peaks:** Filter `entry.peaks` by `entry.selectedPeakIDs`, then call `TapToneAnalyzer.resolvedModePeaks(peaks:guitarType:)` — the same call `MultiTapComparisonResultsView` makes to populate the Air/Top/Back table columns

Mode classification and peak selection happen at analysis time in `processMultipleTaps()` via `guitarModeSelectedPeakIDs()`. The `resolvedModePeaks()` call in the test is the same display-time resolution the UI performs.

---

## Reference Values

Source: `Recording.guitartap` and `Recording.pdf` from `Tests/O'Brien/`

### Settings
- Measurement type: Generic Guitar (`.generic` / `MeasurementType.GENERIC`)
- Number of taps: 8
- Peak min threshold: -76 dB
- Tap detection threshold: -40 dB
- FFT size: 16384
- Sample rate: 48000 Hz

### Average Peaks (from guitartap file)
| Mode | Frequency (Hz) | Magnitude (dB) |
|------|----------------|-----------------|
| Air  | 87.233154      | -44.34529       |
| Top  | 164.04662      | -35.105385      |
| Back | 240.57095      | -55.152287      |

### Per-Tap Peaks (from guitartap file selected peaks)
| Tap | Air Freq | Air Mag    | Top Freq  | Top Mag    | Back Freq | Back Mag   |
|-----|----------|------------|-----------|------------|-----------|------------|
| 1   | 87.20365 | -46.083164 | 164.15787 | -37.15723  | 296.5797  | -57.117817 |
| 2   | 87.22049 | -43.714653 | 163.98953 | -34.96168  | 240.6308  | -54.930405 |
| 3   | 87.21567 | -44.400375 | 164.00642 | -36.064285 | 240.54478 | -56.384575 |
| 4   | 87.23355 | -43.930878 | 164.02281 | -34.72927  | 240.58727 | -55.048416 |
| 5   | 87.23911 | -44.447514 | 164.09766 | -36.650166 | 240.52957 | -54.569893 |
| 6   | 87.258545| -44.08946  | 164.05678 | -34.239933 | 240.63478 | -54.847008 |
| 7   | 87.2434  | -43.969948 | 164.05476 | -33.775253 | 296.5151  | -54.0257   |
| 8   | 87.24372 | -44.523045 | 164.0366  | -34.412136 | 240.49031 | -54.849174 |

### Tolerances
- Frequency: ±1.0 Hz
- Magnitude: ±1.0 dB

---

## Files to Modify

### 1. Swift — Append to existing file
**Path:** `GuitarTap/GuitarTapTests/FilePlaybackRegressionTests.swift`

**WAV file:** `Recording.wav` already exists at `GuitarTap/GuitarTapTests/Recording.wav`

**Add to existing `FilePlaybackRegressionTests` suite:**
- Add expected value constants for the O'Brien guitar recording (average + 8 per-tap)
- `REG_G2_genericGuitar8Tap_producesExpectedPeaks()` — validates averaged Air/Top/Back freq+mag and all 8 individual taps' Air/Top/Back freq+mag

**Test approach:**
1. Load `Recording.wav` from the test bundle
2. Create analyzer via `TapToneAnalyzer.forTesting(fftSize: 16384)`
3. Set `peakMinThreshold = -76`, `tapDetectionThreshold = -40`
4. Call `playFileForTesting(url:, measurementType: .generic, numberOfTaps: 8)`
5. **Averaged peaks:** Use `sut.getPeak(for: .air)`, `.top`, `.back` to get the averaged peaks, assert freq and mag within tolerance
6. **Per-tap peaks:** For each of the 8 `sut.tapEntries`:
   - Filter `entry.peaks` by `entry.selectedPeakIDs`
   - Call `TapToneAnalyzer.resolvedModePeaks(peaks:guitarType:)` on the selected peaks (same code path as `MultiTapComparisonResultsView`)
   - Use `GuitarMode.classifyAll()` on the same selected peaks to get the mode→UUID map, then look up the full `ResonantPeak` object for each mode to check both frequency and magnitude
   - Assert freq and mag within tolerance against the per-tap reference table

### 2. Python — Append to existing file
**Path:** `/Users/dws/src/guitar_tap/tests/test_file_playback_regression.py`

**WAV file:** Already exists at `/Users/dws/src/guitar_tap/tests/Recording.wav`

**Add to existing `TestFilePlaybackRegression` class:**
- Add expected value constants for the O'Brien guitar recording
- Add a `guitar_analyzer` fixture
- `test_REG_G2_generic_guitar_8tap_produces_expected_peaks()` — validates averaged Air/Top/Back freq+mag and all 8 individual taps' Air/Top/Back freq+mag

**Test approach:** Mirror of Swift — same pipeline, same reference values, same tolerances. Use `TapToneAnalyzer.resolved_mode_peaks()` and `GuitarMode.classify_all()` on per-tap selected peaks — the same code paths the Python UI uses.

### 3. Verify Recording.wav in Xcode test target
Confirm `Recording.wav` is included in the `GuitarTapTests` target's bundle resources so the test can find it at runtime.

---

## Verification

1. **Swift:** Build project, then run `FilePlaybackRegressionTests` — REG-B1 and REG-G2 should all pass
2. **Python:** Run `pytest tests/test_file_playback_regression.py -v` — REG-B1 and REG-G2 should all pass
3. Cross-platform parity: same WAV, same expected values, same tolerances in both suites
