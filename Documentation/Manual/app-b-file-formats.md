# Appendix B — File Formats

## .guitartap

A JSON-based measurement container. Contains:

- All detected peaks (frequency, magnitude, Q, bandwidth, mode assignment, annotation offset, manual overrides)
- Spectrum snapshot: Base64-encoded little-endian float32 array of magnitude values
- Settings at time of capture (measurement type, frequency windows, Peak Min, analysis range)
- Metadata: capture date, device, location label, notes

Compatible between iOS, iPadOS, and macOS versions of GuitarTap. Can be round-tripped: exported on iOS, imported on macOS, and vice versa.

## Calibration Files (.txt / .cal)

Frequency response compensation data for a measurement microphone. Format: two-column plain text, one frequency–magnitude pair per line.

```
# Frequency (Hz)   Magnitude (dB)
20.0               -1.2
50.0               -0.4
100.0               0.0
...
20000.0            -3.1
```

The app applies the inverse of the calibration curve to the incoming spectrum, correcting for microphone frequency response deviations.

## Exported Formats

| Format | Extension | Contents |
|--------|-----------|---------|
| Measurement data | .guitartap | Full peak data + spectrum (JSON) |
| Spectrum image | .png | Chart as rendered on screen |
| PDF report | .pdf | Spectrum chart + peak table + analysis summary |
