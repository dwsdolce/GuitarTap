# Chapter 5 — Brace Mode

<!-- STATUS: STUB — needs full content -->

## 5.1 Overview

<!-- TODO: Write section -->
<!-- Cover:
     - Purpose: fast longitudinal-only measurement for brace strips
     - What is skipped compared to Plate mode: no cross-grain tap, no FLC tap,
       no Cross/Long ratio, no Gore target thickness
     - What is calculated: E_L, c_L, specific modulus E_L/ρ, quality rating
     - Suitable sample shapes: rectangular strip cut from brace stock, held at 22% from each end
     - Typical workflow: batch-test a set of brace strips before selecting stock for a build -->

## 5.2 Setting Up Brace Dimensions

<!-- TODO: Write section -->
<!-- Cover:
     - Open Settings → Measurement Type → Material (Brace)
     - Fields: Length (mm) — along the grain; Height (mm) — the dimension in the tap direction
       (brace standing upright, tapped on the top face)
     - Note on which dimension is 't' in the Euler–Bernoulli formula: it is Height (the
       dimension perpendicular to the tapping face); this is often the narrower dimension
       for a triangular-profile brace strip that has been pre-profiled
     - No mass field: density is not required for the longitudinal calculation (only
       frequency, length, and height are needed)
     - Live preview of dimension plausibility is not available in Brace mode -->

## 5.3 Technique

<!-- TODO: Write section -->
<!-- Cover:
     - Single-point hold: finger and thumb at 22% from each end along the length
     - Tap the top face at the centre point
     - No rotation needed (single tap, single orientation)
     - Accept / Redo review flow applies (same as Plate mode §4.5):
         * After the tap the spectrum freezes and the Accept / Redo buttons appear
         * Accept locks in the result; Redo discards it and returns to capture
         * No phase progress indicator shown (single phase = phase count hidden)
     - After Accept: the Results panel updates with the brace calculations -->

## 5.4 Reading Brace Results

<!-- TODO: Write section -->
<!-- Cover:
     - E_L (GPa): longitudinal Young's modulus
     - c_L (m/s): speed of sound along grain
     - Specific modulus E_L/ρ: not available (mass not entered); note this limitation
       if specific modulus comparison is required — use Plate mode with mass
     - Quality rating: based on the same spruce scale as Plate mode
       (≥25 Excellent, ≥22 Very Good, ≥19 Good, ≥16 Fair, <16 Poor)
     - No Gore thickness: cross-grain and shear data are absent; use Plate mode if
       Gore target thickness is needed -->

## 5.5 Using Brace Mode to Compare Stock

<!-- TODO: Write section -->
<!-- Cover:
     - Practical workflow: label each brace strip (pencil mark on end grain or sticky
       label); enter length and height in Settings; tap; note the E_L and c_L values;
       repeat for each strip
     - Sorting strips by longitudinal frequency (higher = stiffer for a given length)
     - Using the Notes field when saving each measurement to record strip identity
     - Exporting a PDF or spectrum image per strip for a permanent record
     - Limitation: without cross-grain data brace-to-brace comparisons are on one axis
       only; anisotropy and shear behaviour are unknown -->
