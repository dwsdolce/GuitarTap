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

Dates are ISO-8601 strings (`YYYY-MM-DDTHH:MM:SSZ`).

**Ids.** Every id — a measurement's, a peak's, and every reference
to one — is a UUID (RFC 9562), written as 36 characters:
hexadecimal digits in groups of 8-4-4-4-12 joined by hyphens, in
uppercase. Ids are read in either case, so two that differ only in
case are the same id. A file in which any id is missing, or is not
in that form (braces, a `urn:uuid:` prefix and unhyphenated digits
are not accepted), cannot be opened: the app says so and adds
nothing from it.

**Number precision.** Most numeric fields are single-precision
(`float32`): they are written as the shortest decimal that
round-trips to the stored value, and integral values carry no
decimal point (`-100`, not `-100.0`). Treat them as accurate to
about 7 significant digits, no more. A few fields are full
double-precision and are written at full precision — `pitchCents`,
`pitchFrequency`, `sampleRate`, the four `colorComponents`, and
the `absFreqHz` / `absDB` annotation offsets. Per-spectrum arrays
do not use JSON numbers at all; they use the compact binary
encoding described below.

**Key order and whitespace are not significant.** Current writers
sort object keys alphabetically and indent two spaces, but a
parser must not depend on either — always read by key name.

**Optional fields are omitted, never `null`.** A field that is
not set is left out of the object entirely. Treat a missing field
and an explicit `null` the same way on read.

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
| `selectedLongitudinalPeakID`, `selectedCrossPeakID`, `selectedFlcPeakID` | UUID | The peak chosen as fL / fC / fLC. |
| `selectedPeakIDs` | array of UUID | Currently-selected peaks (guitar). |
| `selectedPeakFrequencies` | array of float | Frequencies (Hz) of the selected peaks, parallel to `selectedPeakIDs` — for a program reading the file that wants the selected peaks' frequencies without resolving the IDs or repeating GuitarTap's selection. GuitarTap itself does not read it back. |
| `userModifiedSelection` | bool | Guitar only. `true` once the user has changed peak selection away from the automatic default; Reset to automatic selection is offered only then. Omitted on material measurements and on files saved before 1.0.2; a missing value is read as `true`. |
| `peakAnnotationOffsets` | array | UUID-keyed map of custom label positions, encoded as a flat array (see "UUID-keyed maps"). Each value is `{ "absFreqHz": <freq Hz>, "absDB": <magnitude dB> }`. |
| `annotationVisibilityMode` | string | Enum: `all` / `selected` / `none`. |
| `tapDetectionThreshold` | float | Threshold (dB) at save time. |
| `numberOfTaps` | int | Taps stepper value at save time. |
| `peakMinThreshold` | float | Peak Min (dB) at save time. |
| `peakModeOverrides` | array | UUID-keyed map of per-peak mode overrides, encoded as a flat array (see "UUID-keyed maps"). Each value is `{ "type": "assigned", "label": <mode> }`. |
| `microphoneName`, `microphoneUID` | string | Input device provenance. |
| `calibrationName` | string | Active calibration profile, if any. |
| `sampleRate` | float | Capture sample rate (Hz) in effect when recorded. Omitted in files saved before this field existed; absence is treated as "unknown" (no warning). |
| `comparisonEntries` | array of ComparisonEntry | Present **only** for saved comparisons. |
| `tapEntries` | array of TapEntry | Per-tap data for multi-tap guitar. |
| `measurementType`, `guitarType` | string | Convenience copies for external consumers; mirror `spectrumSnapshot` fields. |

### UUID-keyed maps

`peakAnnotationOffsets` and `peakModeOverrides` are logically maps from
a peak UUID to a value. Because a UUID is not a JSON string key, both
are encoded as a **flat array** of alternating key/value elements — the
array form produced by the platform's JSON encoder. A parser must read
element 0 as a UUID string, element 1 as its value, element 2 as the
next UUID, and so on:

```json
"peakModeOverrides": [
  "5E2A8C7D-…",
  { "type": "assigned", "label": "Top" },
  "9F31B0A4-…",
  { "type": "auto" }
]
```

A mode value is `{ "type": "auto" }` or
`{ "type": "assigned", "label": "<string>" }`; a peak with no entry (or
a `"type": "auto"` entry) uses automatic classification.
`peakAnnotationOffsets` uses the same alternating layout with values of
`{ "absFreqHz": <Hz>, "absDB": <dB> }`.

> **Compatibility note.** Some files written by early Guitar Tap Python
> 1.0.x builds encode `peakModeOverrides` as a JSON *object*
> (`{ "<uuid>": { "type": …, "label": … } }`) instead of the flat array.
> Robust parsers should accept both shapes; current builds always write
> the flat array.

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
| `guitarType` | string | One of `Generic`, `Acoustic`, `Classical`, `Flamenco`. |
| `measurementType` | string | One of `Generic Guitar`, `Acoustic Guitar`, `Classical Guitar`, `Flamenco Guitar`, `Material (Plate)`, `Material (Brace)`. |
| `plateLength`, `plateWidth`, `plateThickness`, `plateMass` | float | Plate dimensions in mm / g. |
| `guitarBodyLength`, `guitarBodyWidth` | float | Body inputs for Gore thickness (mm). |
| `plateStiffnessPreset` | string | One of `Steel String Top`, `Steel String Back`, `Classical Top`, `Classical Back`, `Custom`. |
| `customPlateStiffness` | float | Value when `plateStiffnessPreset` is `Custom`. |
| `measureFlc` | bool | Whether the Diagonal (fLC) phase was captured. |
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
| `pitchNote` | string | Nearest equal-temperament note, e.g. `"D4"`. Optional. |
| `pitchCents` | number | Cents offset from `pitchNote` (double precision). Optional. |
| `pitchFrequency` | number | Frequency of `pitchNote` in Hz (double precision). Optional. |
| `modeLabel` | string | Resolved mode label — see note below. Top-level peaks only. |

`pitchNote`, `pitchCents`, and `pitchFrequency` are present only
when pitch detection produced a result; otherwise all three are
omitted together.

`modeLabel` is a convenience the writer adds to each peak in the
**top-level** `peaks` array: the resolved guitar mode name (e.g.
`"Air (Helmholtz)"`, `"Top"`), the user's assigned override if
any, or — for plate / brace — the peak's role (`"Longitudinal"`,
`"Cross-grain"`, `"Diagonal"`, or `"Peak"`). It is derived from the
other fields and the measurement settings, so a reader can use it
directly or ignore it and reclassify. It is **not** written on
peaks nested inside `tapEntries` or `comparisonEntries`.

### ComparisonEntry (when `comparisonEntries` is present)

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Identifier for the overlay entry. |
| `label` | string | Display label shown in the legend. |
| `colorComponents` | array of 4 floats | RGBA, each 0.0 – 1.0. |
| `snapshot` | SpectrumSnapshot | Full spectrum data for this overlay curve. |
| `peaks` | array of Peak | Peaks for this overlay's source measurement. |
| `guitarType` | string | For mode classification. |
| `modePeakIDs` | object | Maps each identified mode name (`air`, `top`, `back`, …) to the UUID of the peak that carries it in this overlay — computed override-aware when the comparison was saved, so the entry is self-describing and a reader need not re-classify. A plain JSON object with string keys (not a flat UUID-map). Omitted by builds before this field existed; such files are upgraded on open by re-deriving the map. |
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

### Legacy compatibility (reader-only)

Everything above describes what current builds **write**. Files
saved by older versions of Guitar Tap may differ in the ways
listed here. If you are parsing `.guitartap` files you are likely
to meet some of these in the wild, so a robust reader should
accept them all; a writer should emit only the current forms.

| You may encounter | Read it as | Why |
|---|---|---|
| `peakThreshold` | `peakMinThreshold` | The field was renamed; older files use the old name. If both are present, prefer `peakMinThreshold`. |
| `tapLocation` | `measurementName` | Renamed. |
| `frequencies` / `magnitudes` (plain arrays of float) | `frequenciesData` / `magnitudesData` | The spectrum arrays predate the compact Base64 binary encoding and were stored as ordinary JSON float arrays. |
| `peakModeOverrides` as a JSON **object** (`{ "<uuid>": { … } }`) | the flat alternating array | Early Python 1.0.x builds. See "UUID-keyed maps" above. |
| Annotation offsets as `{ "hzOffset": …, "dbOffset": … }` | *(drop them)* | An old delta-based label-position format that cannot be converted reliably; affected labels simply revert to their default position. |
| Any field not documented here (e.g. `hysteresisMargin`, `maxPeaks`) | *(ignore it)* | The format is additive. Skip unknown keys rather than rejecting the file. |

Two absences are themselves meaningful: a missing `sampleRate`
means the capture rate was not recorded (treated as "unknown",
no warning), and a missing `selectedPeakIDs` means every peak is
considered selected.

**The saved-measurements library.** The measurements you save are
kept in the same format, in a file of the app's own
(`saved_measurements.json`). If that file cannot be read when the
app starts, the app does not write over it: it renames it
`saved_measurements-unreadable-<date and time>.json` in the same
folder, starts with an empty library, and tells you where the file
is. Correct it and rename it back to `saved_measurements.json` to
restore your measurements. In the browser edition each saved
measurement is stored on its own; one that cannot be read is left
out of the list and kept until you choose to delete it.

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
