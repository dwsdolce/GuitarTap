# Chapter 5 — Brace Mode

Brace mode is a fast, single-tap longitudinal measurement for an
individual brace strip. It reports the moduli, specific modulus,
and quality rating in one capture; cross-grain, shear, and Gore
thickness are all skipped. This chapter assumes the microphone,
calibration, threshold, and peak-min are already tuned as in
Chapter 2.

## 5.1 Overview

Brace mode runs a single longitudinal tap on a brace strip and
returns the wood's stiffness and quality. Compared to Plate mode:

- **No cross-grain tap.** E_C is not measured.
- **No FLC tap.** G_LC is not measured.
- **No Cross/Long ratio.**
- **No Gore target thickness.** Brace mode is for stock evaluation,
  not for thicknessing.

What you get: E_L, c_L, specific modulus E_L/ρ with a per-direction
quality rating against the spruce scale, and radiation ratio R.

Brace mode is intended for batch-evaluating brace strips before
selecting stock for a build. For a free plate, use Plate mode
(Chapter 4); for a complete instrument, use Guitar mode (Chapter 3).

## 5.2 Setting Up Brace Dimensions

<!--
SCREENSHOT:

  File:    images/ch05-settings-brace.png
  Subject: Settings sheet on macOS, Measurement Type set to Brace,
           scrolled to the "Brace Dimensions" section. All four
           input fields visible: Length (along grain), Width
           (breadth), Height (tap direction) with its helper text,
           and Mass. Calculated Density preview line below them.
  Notes:   Use plausible spruce-brace numbers (e.g. 480 x 18 x 15
           mm, 18 g) so the density preview reads in the spruce
           range. Crop to the settings sheet.
-->

![Settings sheet with Measurement Type set to Brace — Length, Width, Height, and Mass fields with calculated density preview.](images/ch05-settings-brace.png){: .screenshot-panel }

Open **Settings → Measurement Type → Brace**. The Brace
Dimensions section has four fields:

- **Length (along grain)** (mm) — the long axis of the strip.
- **Width (breadth)** (mm) — the brace's breadth lying flat.
- **Height (tap direction)** (mm) — the dimension perpendicular
  to the face you tap. This is the `t` in the Euler–Bernoulli
  stiffness formula, so it's the one that drives E_L most
  strongly. The Settings panel itself flags this with a helper
  line under the field; double-check it before tapping.
- **Mass** (g).

A **Calculated Density** line appears below the fields once all
four are populated. Use it the same way as the plate-mode density
preview — spruce should land in the 0.35–0.45 g/cm³ range, and a
value well outside that is almost always a digit transposition.

## 5.3 Technique

A brace strip is a long thin beam — the same free-free fundamental
applies, but the measurement is much simpler than plate because
only one mode is in play.

1. Hold the strip between thumb and forefinger **22% in from one
   end along the length**. The other end hangs free.
2. Lay the strip flat (or mount it however you usually orient it
   on the bench) so the face you intend to tap is exposed. The
   `Height` value in Settings must match the dimension
   perpendicular to this face.
3. Press **New Tap**.
4. Tap the centre of the top face. The spectrum freezes when the
   tap registers.

The **Accept** / **Redo** review flow is the same as in Plate mode
(see §4.5). Accept locks in the measurement; Redo discards it and
re-arms the detector. There is no phase counter — Brace mode runs
in a single phase, so the status bar shows just the current state.

## 5.4 Reading Brace Results

<!--
SCREENSHOT:

  File:    images/ch05-results-panel.png
  Subject: Brace measurement Results panel scrolled to show all
           three sections: Detected Peaks (the single L row with
           star + frequency + magnitude + L phase badge), Brace
           Properties (Frequency used, Speed of Sound, Young's
           Modulus, Specific Modulus in large type with quality
           rating colour, Radiation Ratio), and Brace Process
           Instructions.
  Notes:   Use a real measurement so the numbers are plausible;
           pick a strip whose specific modulus lands in one of
           the named rating bands so the colour cue is visible.
           Crop to the panel only.
-->

![Brace Results panel showing the three sections — Detected Peaks (single L row), Brace Properties, and Brace Process Instructions.](images/ch05-results-panel.png){: .screenshot-panel }

A completed brace measurement displays three sections in the
Results panel.

### Detected Peaks

A single row for the longitudinal peak. It shows a
selection-indicator star, the peak frequency, the peak magnitude
in dB, and a blue **L** phase badge.

### Brace Properties

- **Frequency used** — fL in Hz.
- **Speed of Sound** — c_L in m/s.
- **Young's Modulus (E)** — in GPa.
- **Specific Modulus (E/ρ)** — the headline number, in
  GPa/(g/cm³), shown in large type. A quality rating
  (Excellent / Very Good / Good / Fair / Poor against the spruce
  scale) accompanies the value with a matching colour cue.
- **Radiation Ratio (R)** — in the same column.

There is no Cross/Long ratio or Overall Quality row — both are
plate-only since they need cross-grain data.

### Brace Process Instructions

A reference card describing the brace measurement procedure.
Useful as an in-place refresher when you have come back to Brace
mode after a break.

## 5.5 Using Brace Mode to Compare Stock

A practical workflow for evaluating a batch of brace strips:

1. Label each strip (a pencil mark on the end grain or a small
   sticky label works) so you can match measurements to physical
   pieces later.
2. Enter the strip's Length, Width, Height, and Mass in Settings.
   For a batch of strips with consistent stock dimensions you
   only have to change Mass between measurements; for variable
   stock all four fields need updating.
3. Tap the strip.
4. Record the result. The **Notes** field on the Save sheet is the
   right place for the strip's identifier — once saved, the
   saved measurement carries its provenance.
5. Move on to the next strip.

For sorting by stiffness alone, the longitudinal frequency at the
same dimensions is a sufficient proxy — higher fL means stiffer
stock. For triaging across different sizes, sort by specific
modulus (E_L/ρ).

A practical limitation worth keeping in mind: with no cross-grain
or shear data, brace-to-brace comparisons are one-dimensional. A
strip that reads well in brace mode might still have anisotropy
or grain runout that only shows up in a plate-style measurement
on the parent billet.
