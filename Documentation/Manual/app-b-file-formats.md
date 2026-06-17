# Appendix B — File Formats

## Measurement files (`.guitartap`)

The native portable measurement container. UTF-8 JSON,
self-contained, and identical across every platform Guitar Tap
runs on (iOS, iPadOS, macOS native, and the Python build on
Windows / Linux / macOS Python). A file written on any platform
opens on any other without conversion. The export and import
workflows are documented in §7.8 and §7.9.

The remainder of this section is a structural reference for
anyone parsing or generating `.guitartap` files outside the app.

### File-level structure

The file is pretty-printed JSON. The top-level value is an
**array** containing exactly one measurement object — the array
wrapping is part of the format and parsers must accept it even
when only one measurement is present.

```json
[
  {
    "id": "…",
    "timestamp": "…",
    ...
  }
]
```

Dates are ISO-8601 strings (`YYYY-MM-DDTHH:MM:SSZ`). UUIDs are
RFC 4122 strings. Numbers are JSON numbers (single-precision
floats are encoded as decimal; per-spectrum arrays use the
compact binary encoding below).

### Measurement object

Required fields:

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Stable identifier. |
| `timestamp` | ISO-8601 | When the measurement was saved. |
| `peaks` | array of Peak | All detected peaks (empty for a saved comparison). |

Optional fields — populated depending on measurement type and on
what the user did at save time:

| Field | Type | Notes |
|---|---|---|
| `measurementName` | string | User-entered name (§7.1). |
| `notes` | string | User notes. |
| `decayTime` | float | Seconds; guitar only. |
| `spectrumSnapshot` | SpectrumSnapshot | Averaged guitar spectrum. |
| `longitudinalSnapshot`, `crossSnapshot`, `flcSnapshot` | SpectrumSnapshot | Plate / brace per-phase spectra. |
| `selectedLongitudinalPeakID`, `selectedCrossPeakID`, `selectedFlcPeakID` | UUID | The peak chosen as L / C / FLC. |
| `selectedPeakIDs` | array of UUID | Currently-selected peaks (guitar). |
| `selectedPeakFrequencies` | array of float | Frequencies (Hz) parallel to the IDs, used to re-match after a Peak Min change generates new UUIDs. |
| `peakAnnotationOffsets` | object | Map of peak UUID → `{ "x": <freq Hz>, "y": <magnitude dB> }`. Custom label positions. |
| `annotationVisibilityMode` | string | Enum: `all` / `selected` / `none`. |
| `tapDetectionThreshold` | float | Threshold (dB) at save time. |
| `numberOfTaps` | int | Taps stepper value at save time. |
| `peakMinThreshold` | float | Peak Min (dB) at save time. |
| `peakModeOverrides` | object | Map of peak UUID → user-assigned mode label. |
| `microphoneName`, `microphoneUID` | string | Input device provenance. |
| `calibrationName` | string | Active calibration profile, if any. |
| `comparisonEntries` | array of ComparisonEntry | Present **only** for saved comparisons. |
| `tapEntries` | array of TapEntry | Per-tap data for multi-tap guitar. |
| `measurementType`, `guitarType` | string | Convenience copies for external consumers; mirror `spectrumSnapshot` fields. |

### SpectrumSnapshot

Required fields:

| Field | Type | Notes |
|---|---|---|
| `frequenciesData` | Base64 string | See "Spectrum data encoding" below. |
| `magnitudesData` | Base64 string | Same length as `frequenciesData`. |
| `minFreq`, `maxFreq` | float | Chart frequency range (Hz). |
| `minDB`, `maxDB` | float | Chart magnitude range (dB). |
| `isLogarithmic` | bool | Axis scale. |

Optional measurement-type fields:

| Field | Type | Notes |
|---|---|---|
| `showUnknownModes` | bool | Mirrors the Settings toggle. |
| `guitarType` | string | `generic` / `acoustic` / `classical` / `flamenco`. |
| `measurementType` | string | `generic` / `acoustic` / `classical` / `flamenco` / `plate` / `brace`. |
| `plateLength`, `plateWidth`, `plateThickness`, `plateMass` | float | Plate dimensions in mm / g. |
| `guitarBodyLength`, `guitarBodyWidth` | float | Body inputs for Gore thickness (mm). |
| `plateStiffnessPreset` | string | `steelStringTop` / `steelStringBack` / `classical` / `custom`. |
| `customPlateStiffness` | float | Value when preset is `custom`. |
| `measureFlc` | bool | Whether the FLC phase was captured. |
| `braceLength`, `braceWidth`, `braceThickness`, `braceMass` | float | Brace dimensions in mm / g. |

### Spectrum data encoding

`frequenciesData` and `magnitudesData` are Base64-encoded byte
strings. After Base64 decoding the bytes are a contiguous
little-endian IEEE-754 single-precision (`float32`) array — 4
bytes per value, length implicit (`byteCount / 4`). The two
arrays are the same length and are parallel: element *i* of
`magnitudesData` is the magnitude (dB) at the frequency (Hz)
given by element *i* of `frequenciesData`.

Reference decoder (Python):

```python
import base64, struct
b = base64.b64decode(snapshot["frequenciesData"])
freqs = list(struct.unpack(f"<{len(b)//4}f", b))
```

### Peak

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Stable identifier within the measurement. |
| `frequency` | float | Hz. |
| `magnitude` | float | dB. |
| `quality` | float | Q factor. |
| `bandwidth` | float | −3 dB bandwidth, Hz. |
| `timestamp` | ISO-8601 | When the peak was detected. |
| `pitchNote` | string | Nearest equal-temperament note, e.g. `"D4"`. |
| `pitchCents` | float | Cents offset from `pitchNote`. |
| `pitchFrequency` | float | Frequency of `pitchNote` in Hz. |

### ComparisonEntry (when `comparisonEntries` is present)

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Identifier for the overlay entry. |
| `label` | string | Display label shown in the legend. |
| `colorComponents` | array of 4 floats | RGBA, each 0.0 – 1.0. |
| `snapshot` | SpectrumSnapshot | Full spectrum data for this overlay curve. |
| `peaks` | array of Peak | Peaks for this overlay's source measurement. |
| `guitarType` | string | For mode classification. |
| `sourceMeasurementID` | UUID | The measurement this entry was created from, if known. |

When `comparisonEntries` is non-null the measurement is a saved
comparison: the top-level `peaks`, `spectrumSnapshot`,
`decayTime`, and similar fields are not meaningful and should
not be read.

### TapEntry (when `tapEntries` is present)

Present only for guitar multi-tap measurements (`numberOfTaps > 1`).
Each entry preserves the raw spectrum and peaks for one tap so
the multi-tap comparison view can be reconstructed:

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `tapIndex` | int | 1-based display index. |
| `snapshot` | SpectrumSnapshot | Raw single-tap spectrum. |
| `peaks` | array of Peak | Peaks detected in this single tap. |
| `selectedPeakIDs` | array of UUID | Auto-selected modes for this tap. |

## Calibration files (`.txt` / `.cal`)

Frequency-response compensation data for a measurement
microphone. Plain text; each data line carries a frequency and a
magnitude correction, separated by **tab, space, or comma**.
Either of the two common vendor formats works directly — UMIK-1
`.txt` files and Room EQ Wizard `.cal` files are both accepted:

```
"Sens Factor =-1.2 dB, SERNO 7123456"
"Frequency (Hz)   Magnitude (dB)"
20.0      -1.2
50.0      -0.4
100.0      0.0
...
20000.0   -3.1
```

Header and comment lines begin with `"` (UMIK-1) or `*` (REW)
and are skipped. Only frequencies in the range **1 Hz to
24,000 Hz** are used; values outside that range are ignored.

The app applies the inverse of this curve to the incoming
spectrum so that the displayed result reflects the wood, not the
microphone. Calibrations bind per-input-device — see §2.4 for
the import workflow.

## Exported formats

The export actions described in §7.6 – §7.8 produce these file
types:

| Action | Extension | Contents |
|---|---|---|
| Export Measurement / Save Measurement to Disk | `.guitartap` | Full measurement — peaks, spectrum data, settings, metadata (see above). |
| Export Spectrum Image | `.png` | Chart as rendered on screen — frozen spectrum with peak annotations for a single measurement, or the overlay with all coloured curves and legend for a comparison. |
| Export PDF Report | `.pdf` | Spectrum image + peak table + analysis summary + metadata header. Contents vary by measurement type; see §7.7 for the per-type breakdown. |
