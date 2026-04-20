# Chapter 4 — Plate Mode

<!-- STATUS: STUB — needs full content -->

## 4.1 Overview of Plate Material Measurements

<!-- TODO: Write section -->
<!-- Cover:
     - Free-free beam theory: why the 22% nodal-point suspension minimises support damping
     - The three-tap sequence: Longitudinal → Cross-grain → FLC (optional)
     - What the measurements calculate: E_L, E_C (Young's moduli), c_L, c_C (speed of sound),
       specific modulus (E/ρ), radiation ratio (R), Cross/Long ratio, quality rating,
       Gore target thickness
     - When to use Plate mode: raw blanks before cutting, not assembled instruments
     - Difference from Brace mode: Plate does all three taps; Brace does longitudinal only -->

## 4.2 Preparing the Sample

<!-- TODO: Write section -->
<!-- Cover:
     - Cutting a rectangular blank (no irregular edges; grain running parallel to one long axis)
     - Required measurements: length along grain (mm), width cross-grain (mm), thickness (mm), mass (g)
     - Accuracy targets: length/width to 0.5 mm; thickness to 0.1 mm; mass to 0.1 g
     - Suitable scales: jeweller's scale or kitchen scale with 0.1 g resolution
     - How errors in each dimension affect the result (mass errors are most sensitive) -->

## 4.3 Entering Dimensions in Settings

<!-- TODO: Write section -->
<!-- Cover:
     - Open Settings → Measurement Type → Material (Plate)
     - Fields: Length (mm), Width (mm), Thickness (mm), Mass (g)
     - Live density preview: cross-check against expected wood density (spruce ~400 kg/m³;
       any value below 300 or above 700 suggests a data-entry error)
     - Body dimensions (for Gore target thickness): Body Length (mm), Lower Bout Width (mm)
     - Plate stiffness preset selector: Steel String Top (75), Steel String Back (55),
       Classical (50), Custom — affects the Gore target thickness calculation
     - Measure FLC toggle: when enabled a third phase (FLC) is added to the sequence -->

## 4.4 The 22% Suspension Technique

<!-- TODO: Write section -->
<!-- Cover:
     - Principle: a free-free beam has nodal points at 22.4% from each end; holding at
       these points does not damp the resonance being measured
     - Longitudinal hold: finger and thumb at 22% from each end along the LENGTH of the plate,
       near one long edge — this suspends the plate for the longitudinal bending mode
     - Cross-grain hold: plate rotated 90°; finger and thumb at 22% from each end along
       the WIDTH, near one short edge
     - FLC hold: midpoint of one long edge (one hold point; tap near the opposite corner
       at approximately 22% from both the end and side)
     - Common errors: holding too far in (over-damps) or at the centre (changes the mode shape);
       gripping too firmly (adds damping)
     - Tap location for all three orientations: centre of the plate face -->

## 4.5 The Accept / Redo Review Flow

<!-- TODO: Write section -->
<!-- Cover:
     - After each phase the spectrum freezes automatically and tap detection pauses;
       the user reviews the frozen spectrum before the sequence continues
     - The tap controls change during review:
         * The Pause button becomes Accept (green tint, checkmark icon): tap to lock in
           the current result and advance to the next phase
         * The Cancel button becomes Redo (orange, labelled "Redo L", "Redo C", or "Redo FLC"):
           tap to discard the current phase result and return to capture for that phase
     - During review the live spectrum is suppressed so the accepted measurement stays on screen
     - The status bar shows the current phase and tap count: "Phase 1/2 · Tap N/M"
       (phase count hidden if only one phase, e.g. Brace mode)
     - After all phases are accepted the Results panel updates with the complete plate calculations
     - To restart the entire sequence (e.g. wrong plate orientation throughout): tap New Tap;
       individual phase redo is only available before that phase is accepted -->

## 4.6 Tap 1 — Longitudinal

<!-- TODO: Write section -->
<!-- Cover:
     - Grain orientation: grain runs left–right (along the length dimension entered in Settings)
     - Hold: finger and thumb at 22% from each end along the length, near one long edge
     - Tap: centre of the plate face
     - Press New Tap to arm detection, then make the tap
     - Status bar prompt: "Capturing Longitudinal · Phase 1/2" (or "Phase 1/3" if FLC enabled)
     - Spectrum freezes; Accept / Redo buttons appear
     - After Accept: sequence advances automatically to Phase 2 (Cross-grain) -->

## 4.7 Tap 2 — Cross-Grain

<!-- TODO: Write section -->
<!-- Cover:
     - Rotate the plate 90° so grain now runs top–bottom (along the width dimension)
     - Hold: finger and thumb at 22% from each end along the width, near one short edge
     - Status bar prompt: "Capturing Cross-grain · Phase 2/2" (or "Phase 2/3")
     - Make the tap after detection arms automatically (no need to press New Tap again)
     - Spectrum freezes; Accept / Redo appears again
     - After Accept: sequence advances to FLC (if enabled) or marks measurement complete -->

## 4.8 Tap 3 — FLC (Optional)

<!-- TODO: Write section -->
<!-- Cover:
     - Enable: Settings → Measure FLC toggle (adds Phase 3 to the sequence)
     - Purpose: measures the flat long/cross bending mode, which gives the shear modulus G_LC;
       required for the full Gore target thickness formula; omitting it causes ~5–7% over-estimate
     - Hold: midpoint of one long edge (one hold point only)
     - Tap: near the opposite corner, approximately 22% from the end and 22% from the side
     - Status bar prompt: "Capturing FLC · Phase 3/3"
     - Accept / Redo flow as for Phases 1 and 2
     - After Accept: measurement complete; Results panel updates with Gore thickness including
       shear correction -->

## 4.9 Reading Plate Results

<!-- TODO: Write section -->
<!-- Cover:
     - E_L (GPa): longitudinal Young's modulus — primary stiffness along grain
     - E_C (GPa): cross-grain Young's modulus
     - c_L / c_C (m/s): speed of sound along grain / cross grain
     - Specific modulus E_L/ρ (m²/s²): stiffness per unit weight; key tonewood selector
     - Radiation ratio R = √(E_L/ρ³): efficiency of sound radiation; higher is better
     - Cross/Long ratio E_C/E_L: for spruce typically 0.04–0.08
     - Quality rating (spruce scale):
         ≥ 25 → Excellent (Master grade)
         ≥ 22 → Very Good (AAA)
         ≥ 19 → Good (AA)
         ≥ 16 → Fair (A)
         < 16 → Poor
     - Gore target thickness (mm): recommended final thickness for the plate; requires
       body dimensions and plate stiffness preset to be set in Settings; more accurate
       when FLC tap is included (shear correction applied) -->

## 4.10 Interpreting and Comparing Plate Results

<!-- TODO: Write section -->
<!-- Cover:
     - What specific modulus predicts vs. Young's modulus alone
       (a heavy stiff plate can have the same E as a light stiff plate, but the lighter
       one will vibrate more freely — specific modulus captures this)
     - How to use Gore target thickness in practice: it is a starting point, not a guarantee;
       final voicing still requires hands-on tap-tone evaluation
     - Cross/Long ratio as a spruce species/quality indicator (lower = more anisotropic = better)
     - Keeping records: use the Notes field to record which blank each measurement came from;
       export a PDF or spectrum image for each blank as a paper trail -->
