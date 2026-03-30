# GuitarTap Quick-Start Guide

## ![](/tmp/guitar-tap-symbols/waveform.path.ecg.png){height=18pt width=18pt} What Guitar Tap Does

Guitar Tap uses your device's microphone to capture the brief ring-out after you tap a guitar or wood sample. A 65,536-point FFT (≈0.67 Hz resolution) reveals the resonant peaks that carry information about structural modes and material stiffness.

Three main workflows are supported:
- Guitar mode — classify resonant modes of a completed instrument.
- Plate mode — measure Young's modulus and quality of a raw tonewood plate.
- Brace mode — measure Young's modulus and quality of a brace strip (single longitudinal tap).

## ![](/tmp/guitar-tap-symbols/wrench.and.screwdriver.png){height=18pt width=18pt} First-Time Setup

### Grant Microphone Access

The first time the app launches it will ask for microphone permission. Tap OK. Without it the analyzer cannot run.

### Select Audio Input

Open Settings. The Audio Input & Calibration section appears at the top. Choose your microphone or audio interface here. If you have a calibration file for your measurement mic, import it in this section too.

### Choose a Measurement Type

In Settings, the Measurement Type section is directly below Audio Input. Pick Classical Guitar, Flamenco, Steel String, Material (Plate), or Material (Brace). The right choice determines which mode-frequency ranges are used and which measurements are calculated.

### Advanced Settings

Display range, analysis range, and FFT processing options are grouped under the Advanced section at the bottom of Settings. These rarely need changing after initial setup — expand the section by tapping the Advanced row.

### Quiet Environment

Background noise raises the noise floor. A quiet workbench with the device resting on a folded cloth a few centimetres from the tap point gives the most repeatable results.

## ![](/tmp/guitar-tap-symbols/guitars.png){height=18pt width=18pt} Guitar Mode

### Overview

Guitar mode identifies the key structural resonances of a completed body: Air (Helmholtz cavity resonance), Top (main top-plate resonance), Back, Dipole, Ring Mode, and Upper Modes.

### Step 1 — Configure

In Settings choose the guitar type (Classical, Flamenco, or Acoustic/Steel String) in the Measurement Type section. Each type has calibrated frequency windows for each mode, shown there. The Show Unknown Modes toggle is in the Advanced section.

### Step 2 — Position the Microphone

The spectrum updates in real time as soon as the app opens. Set the device microphone 5–15 cm from the guitar, aimed at the sound hole or tap point.

### Step 3 — Tap New Tap

Tap the New Tap button to arm the detector, then give the guitar top (or back, side, etc.) a firm knuckle rap. The spectrum freezes automatically when a tap is detected.

### Step 4 — Inspect Peaks

Coloured markers label each resonant peak with its mode, frequency, and pitch. In guitar mode, one peak per mode is auto-selected based on the strongest peak in each frequency range, working lowest-to-highest so overlapping ranges resolve in favour of the lower mode. Tap a peak label to toggle its selection. Use the Annotations button to cycle through All / Selected / None label modes. In the Results panel, the wand button resets selections back to automatic if you have made manual changes.

### Step 5 — Read the Results

On iOS/iPadOS, tap Results to open the results panel. On macOS, the results panel is always visible on the right side of the window. The panel shows the peak list with frequency, magnitude, Q factor, bandwidth, and pitch. Decay time (ring-out in seconds) and Tap Tone Ratio (Top ÷ Air) are shown when applicable. Typical top/air ratios range from 1.8 to 2.4 for quality instruments.

### Multi-Tap Averaging

Setting the tap count to 2–10 averages multiple taps together, reducing noise from finger squeaks and ambient sounds. Progress is shown in the status bar. Use Pause between taps to let the ring-out decay.

### Overriding Mode Classification

If a peak is labelled Unknown, or misclassified, tap it in the Results list and assign the correct mode manually. Your override is saved with the measurement.

### Step 6 — Save

Tap Save. Enter a location (e.g. "Upper Bout" or "Treble Side") and any notes. The measurement is stored with all peaks, the spectrum snapshot, and a chart image.

## ![](/tmp/guitar-tap-symbols/square.3.layers.3d.png){height=18pt width=18pt} Plate Mode

### Overview

Plate material mode measures the stiffness of a rectangular tonewood sample using three free-free beam bending taps: Longitudinal (along grain), Cross-grain, and optionally FLC (diagonal/torsional). From the tap frequencies it derives Young's modulus, speed of sound, specific modulus, radiation ratio, and a quality rating.

### Prepare the Sample

Cut or plane a rectangular blank. Measure length (along grain), width (cross grain), thickness, and mass precisely — accuracy here directly affects the calculated moduli. A kitchen scale accurate to 0.1 g is adequate for most samples.

### Enter Dimensions in Settings

Open Settings → Measurement Type → Material. Enter Length (along grain), Width (cross grain), Thickness, and Mass. The app instantly shows the calculated density so you can catch data-entry errors before tapping.

### Suspension Technique

Hold the plate at one point 22% from one end along the dimension being measured, positioned near one edge in the other dimension (not on that dimension's nodal line). This damps the unwanted resonance while approximating the free-free boundary condition. The other hand taps.

### Tap 1 — Longitudinal

With the grain running left–right, hold the plate at one point 22% from one end along the length, near one long edge (not at the width nodal line — this damps the cross-grain resonance). Tap center. Tap New Tap and follow the on-screen prompt "Capturing Longitudinal". The app selects the strongest peak as the longitudinal frequency.

### Tap 2 — Cross-Grain

Rotate the plate 90° so the grain runs front–back. Hold at one point 22% from one end along the width, near one short edge (not at the length nodal line — this damps the longitudinal resonance). Tap center. The app prompts "Capturing Cross-Grain" automatically after the longitudinal tap is accepted.

### Tap 3 — FLC (Optional)

Enable Measure FLC in Settings. Hold the plate at the midpoint of one long edge and tap near the opposite corner (~22% from both the end and the side). This adds a shear modulus measurement used in the Gore target-thickness calculation. Omitting it over-estimates target thickness by roughly 5–7%.

### Reading the Results

After all taps, tap Results to see:
- E_L / E_C — Young's modulus along and across grain (GPa)
- c_L / c_C — Speed of sound in each direction (m/s)
- Specific modulus E/ρ — The primary quality metric (GPa per g/cm³)
- Radiation ratio — Sound radiation efficiency
- Cross/Long ratio — Anisotropy (spruce: typically 0.04–0.08)
- Quality rating — Excellent / Very Good / Good / Fair / Poor (spruce scale)
- Gore target thickness — Recommended finished plate thickness for a guitar of your specified body dimensions (requires FLC or uses an approximation)

### Spruce Quality Scale

Specific modulus (longitudinal): ≥ 25 → Excellent (Master grade); ≥ 22 → Very Good (AAA); ≥ 19 → Good (AA); ≥ 16 → Fair (A); < 16 → Poor.

### Gore Target Thickness

Enter the finished guitar body length and lower bout width in Settings (Material section). Choose the plate stiffness preset: Steel String Top (f_vs 75), Steel String Back (55), Classical (50), or Custom. The result is the plate thickness that hits the preset vibrational stiffness after bracing is factored in — a direct implementation of Gore Equation 4.5-7.

## ![](/tmp/guitar-tap-symbols/align.horizontal.center.png){height=18pt width=18pt} Brace Mode

### Overview

Brace mode is a fast single-tap variant of Plate mode designed for brace strips. Only a longitudinal tap is needed; cross-grain and FLC are skipped.

### Brace Orientation

In Settings → Brace Dimensions, Height is the dimension in the tap direction (the brace standing upright on the bench). This is the t value in the stiffness formula. Length is along the grain.

### Technique

Hold the brace at one point 22% from one end along the length, near one edge in the width direction (not on the width nodal line). Tap the top face at the center. The same one-point hold technique as Plate mode.

### Results

E_L, c_L, specific modulus, and a spruce quality rating are reported. No cross-grain or Gore thickness calculation is available in Brace mode.

## ![](/tmp/guitar-tap-symbols/hand.tap.png){height=18pt width=18pt} Controls Reference

### ![](/tmp/guitar-tap-symbols/hand.tap.png){height=14pt width=14pt} New Tap

Arms the detector for the next tap (or begins a plate measurement sequence). A green indicator shows when a tap has been registered.

### ![](/tmp/guitar-tap-symbols/pause.circle.png){height=14pt width=14pt} ![](/tmp/guitar-tap-symbols/play.circle.png){height=14pt width=14pt} Pause / Resume

Temporarily suspends tap detection while keeping the spectrum live. Useful between taps in a multi-tap sequence.

### ![](/tmp/guitar-tap-symbols/xmark.circle.png){height=14pt width=14pt} Cancel

Aborts a multi-tap or plate measurement sequence and discards the partial data.

### ![](/tmp/guitar-tap-symbols/doc.text.png){height=14pt width=14pt} Results (iOS/iPadOS)

Opens the analysis results panel: peak list, decay time, plate properties, quality rating, and (for Plate mode) the Gore target thickness. The panel also contains Export Spectrum and Export PDF Report buttons. On macOS this button is not shown — the results panel is permanently visible on the right side of the window.

### ![](/tmp/guitar-tap-symbols/arrow.up.arrow.down.circle.png){height=14pt width=14pt} Auto dB

Scales the magnitude axis to fit the current signal. Tap it after each measurement to keep peaks visible.

### ![](/tmp/guitar-tap-symbols/eye.png){height=14pt width=14pt} ![](/tmp/guitar-tap-symbols/star.fill.png){height=14pt width=14pt} ![](/tmp/guitar-tap-symbols/eye.slash.png){height=14pt width=14pt} Annotations

Cycles through three label modes: All peaks annotated, Selected peaks only, or None.

### ![](/tmp/guitar-tap-symbols/tag.png){height=14pt width=14pt} Peak Labels

Drag any peak label to reposition it and avoid overlaps. To reset an individual label: double-tap it (iOS/iPadOS) or right-click it and choose "Reset Position" (macOS). To reset all labels at once: use the ellipsis menu's "Reset Labels" (iOS/iPadOS) or right-click the chart area (not a label) and choose "Reset Labels" (macOS).

### ![](/tmp/guitar-tap-symbols/square.and.arrow.down.png){height=14pt width=14pt} Save

Saves the current measurement — enabled only when the spectrum is frozen and peaks have been detected. Enter a location label and optional notes.

### ![](/tmp/guitar-tap-symbols/list.bullet.clipboard.png){height=14pt width=14pt} Measurements

Lists all saved measurements. Right-click (macOS) or long-press (iOS/iPadOS) a row to access: Load into View, View Details, Edit Location & Notes, Export Measurement (opens the share sheet — use AirDrop, Mail, etc. to send the .guitartap file), Save Measurement to Disk… (macOS only — saves the .guitartap file via a save dialog), Export Spectrum (saves the chart image), Export PDF Report, or Delete. Use Import Measurement to load a .guitartap (or .json) file from Files or another device. Tap Compare to enter multi-select mode and overlay 2–5 saved guitar measurements on the main chart for side-by-side comparison. The location and notes can also be edited from the Edit button in the Measurement Details toolbar.

### ![](/tmp/guitar-tap-symbols/waveform.path.png){height=14pt width=14pt} Compare Measurements

In the Measurements list, tap Compare to enter selection mode. Tap 2–5 saved guitar measurements to select them (plate and brace measurements cannot be compared). Tap Compare Selected (N) to overlay all selected spectra on the main chart as colour-coded curves with a legend. The chart, cursor, zoom, and pan all work normally. Press New Tap to exit comparison and return to single-measurement mode. While comparing: Save and Annotations are disabled; Export Spectrum produces an image with all curves and a legend; Export PDF Report is not available.

### ![](/tmp/guitar-tap-symbols/chart.bar.png){height=14pt width=14pt} Metrics

Shows FFT engine statistics: frame rate, bin width (Hz/bin), sample rate, and buffer size.

### ![](/tmp/guitar-tap-symbols/dot.viewfinder.png){height=14pt width=14pt} Crosshair *(iOS only)*

Enables a draggable crosshair on the spectrum for reading the exact frequency and magnitude at any point.

### ![](/tmp/guitar-tap-symbols/ellipsis.circle.png){height=14pt width=14pt} … Chart Options *(iOS only)*

The ellipsis button in the top-right corner of the spectrum opens the Chart Options sheet. From here you can reset either or both axes to the values you last saved in Settings ("Reset to Saved"), or restore the factory defaults ("Reset to Defaults"). If peak labels have been dragged from their auto-positions, "Reset Labels" moves them back.

### ![](/tmp/guitar-tap-symbols/info.circle.png){height=14pt width=14pt} ⓘ Zoom & Pan Help *(macOS only)*

The info (ⓘ) button in the top-right corner of the spectrum shows a full reference card for navigating the chart. Scroll wheel and drag gestures are context-sensitive: position the pointer over the plot to operate on both axes, over the frequency axis (bottom) to operate on frequency only, or over the magnitude axis (left) to operate on magnitude only. Modifier—key shortcuts are also available: ⇧ Scroll — pan frequency; ⌥ Scroll — pan magnitude; ⌘ Scroll — zoom both axes; ⌃ Scroll — zoom both axes; Pinch — zoom of both axes or each individual axis (trackpad). Right-click the chart area to reset axes and labels; right-click a label to reset just that label's position.

## ![](/tmp/guitar-tap-symbols/slider.horizontal.3.png){height=18pt width=18pt} Tap Controls

### Taps (stepper)

How many taps to average together (1–10). Averaging reduces noise from tap-position variability and ambient sound. Values of 3–5 are a good starting point for material work.

### Threshold (slider)

The signal level that triggers tap detection. If taps are being missed, move the slider left (lower). If ambient noise triggers false detections, move it right (higher). Displayed in dB.

### Peak Min (slider)

Minimum magnitude a spectral peak must reach to be annotated on the spectrum chart. In guitar mode, a peak must also clear this threshold to be reported; adjusting it on a frozen spectrum re-runs peak finding and updates auto—selections (or carries forward manual selections if you have changed them). In brace/plate mode, the tap capture uses its own adaptive noise floor — Peak Min only affects what is visible on the chart, not which peaks are selected. Move the slider left to show quieter peaks; right to suppress noise. Displayed in dB.

### Reset arrows

Each slider has a small ↺ button that resets it to the factory default value.

## ![](/tmp/guitar-tap-symbols/gearshape.png){height=18pt width=18pt} Settings Reference

### Audio Input & Calibration

Shown at the top of Settings. Select your microphone or audio interface here. Import a frequency-response calibration file (.txt/.cal) to compensate for microphone coloration; calibrations are automatically associated with each device. Audio input and calibration changes take effect immediately and are not affected by Cancel.

### Measurement Type

Shown below Audio Input. Choose Classical Guitar, Flamenco, Acoustic/Steel String, Material (Plate), or Material (Brace). Determines which mode frequency windows are applied and which calculations appear in Results.

### Advanced (collapsed section)

Tap the Advanced row to expand Display Settings, Analysis Settings, and FFT Processing. These options rarely need changing after initial setup.

### Show Unknown Modes

Guitar mode only — found in Advanced → Analysis Settings. When off, peaks outside the known mode frequency windows are hidden, reducing clutter.

### Display Frequency Range

Advanced → Display Settings. Sets the horizontal zoom of the spectrum chart. Narrow the range to zoom in on a region of interest. Use Save Current View to persist the current pan/zoom as the default.

### Display Magnitude Range

Advanced → Display Settings. Sets the vertical scale (dB). Use Auto dB in the main view for a quick fit, or set explicit Min/Max here.

### Analysis Frequency Range

Advanced → Analysis Settings. Peaks outside this window are ignored during detection. Narrow it to exclude spurious low-frequency rumble or high-frequency noise.

### Peak Min

Advanced → Analysis Settings. Sets the minimum magnitude (dB) for a peak to be annotated on the spectrum chart. In guitar mode this also gates which peaks are reported; adjusting it on a frozen spectrum re-runs peak finding and updates selections. In brace/plate mode it only affects what is annotated on the live chart. Typical useful range: −60 to −40 dB.

### Hysteresis Margin

Advanced → Analysis Settings. How far the signal must drop below the detection threshold before the detector resets and is ready for the next tap. A higher value prevents a single loud tap from triggering multiple detections. Range: 1–10 dB; default is 6 dB.

### Maximum Peaks

Advanced → Analysis Settings. Caps the number of peaks reported. Set to All to include every peak above the threshold. Fewer peaks reduces visual clutter when testing assembled guitars.

### FFT Processing

Advanced → FFT Processing. Controls the hop-size overlap between FFT windows. Higher overlap provides smoother results but reduces frame rate. Changes take effect the next time the analyzer is started.

## ![](/tmp/guitar-tap-symbols/lightbulb.png){height=18pt width=18pt} Tips & Technique

### Tap Technique

Use a short, crisp knuckle, fingertip tap, or a bouncy ball on a stick. A slow, pressing contact excites fewer overtones and produces a cleaner fundamental. Avoid tapping near the edges — aim for the centre of the plate or brace in Plate and Brace modes and near the bridge area for guitar-body mode surveys.

### Consistent Mic Position

Keep the microphone at the same distance and angle between measurements for the most comparable magnitude values. Frequency readings are position-independent, but relative magnitudes are not.

### Damping Check with Decay Time

The decay time (ring-out) appears in Results. A longer decay on the top plate typically correlates with lower internal damping — desirable in a soundboard. Compare braced vs. unbraced sections this way.

### Air Mode for Setup

The Helmholtz air resonance is easily produced by holding the assembled body near the microphone and clapping your palm over the sound hole. It does not require tapping the wood itself.

### Comparing Guitar Measurements

Save a measurement for each build stage or tap location with a descriptive label. Use the Measurements list Compare button to overlay 2–5 saved guitar measurements as colour-coded spectra on the main chart — ideal for tracking how bracing or finishing changes the resonant modes over time. Export measurements as .guitartap files for transfer between devices.

### PDF Reports

Each saved measurement can generate a PDF report containing the spectrum chart, peak table, and analysis summary. Open Measurements, select a measurement, then tap the PDF export button.

### ![](/tmp/guitar-tap-symbols/ellipsis.circle.png){height=14pt width=14pt} Zooming the Spectrum *(iOS only)*

Pinch to zoom both axes or each individual axis and drag to pan within the chart or on an axis to pan that axis. To reset the axes, tap the … button in the top-right corner of the spectrum and choose Reset to Saved or Reset to Defaults.

### ![](/tmp/guitar-tap-symbols/info.circle.png){height=14pt width=14pt} Zooming the Spectrum *(macOS only)*

Scroll over the chart to zoom — the axis depends on where the pointer is: over the plot area it zooms both axes; over the frequency axis (bottom) it zooms frequency only; over the magnitude axis (left) it zooms magnitude only. Drag to pan the same way. Modifier keys: ⇧ Scroll — pan frequency; ⌥ Scroll — pan magnitude; ⌘/⌃ Scroll — zoom both axes. To reset the axes, right-click anywhere inside the chart.

## ![](/tmp/guitar-tap-symbols/text.book.closed.png){height=18pt width=18pt} Glossary

### Air (Helmholtz) mode

The resonance of the air mass in the sound hole, analogous to blowing across a bottle. Typically 80–110 Hz for classical guitar.

### Top / Back mode

The fundamental bending resonance of the top or back plate. The relationship between these and the Air mode strongly influences the low-frequency response of the instrument.

### Q Factor

Sharpness of a resonance peak. Q = frequency ÷ −3 dB bandwidth. A higher Q means lower internal damping and a longer, purer ring-out.

### Specific Modulus (E/ρ)

Young's modulus divided by density. The single best predictor of tonewood quality because it determines how fast sound travels through the wood relative to its weight. Higher is better for soundboards.

### Young's Modulus (E)

A measure of how stiff the wood is along a given direction. E_L is along the grain; E_C is across. Reported in GPa.

### Speed of Sound (c)

How fast longitudinal sound waves travel through the wood: c = √(E/ρ). Sitka spruce averages ≈5500 m/s along the grain.

### Radiation Ratio (R)

Sound radiation efficiency: R = c/ρ. A higher value means the plate radiates sound more efficiently for its weight.

### Cross/Long Ratio

E_C ÷ E_L. A measure of wood anisotropy. For spruce guitar tops this typically falls between 0.04 and 0.08; lower values indicate stronger grain structure.

### Tap Tone Ratio

Top mode frequency ÷ Air mode frequency. A rough structural quality indicator for assembled guitars; values between 1.8 and 2.4 are typical for well-made instruments.

### Gore Target Thickness

A plate thickness prediction based on Gore Equation 4.5-7, derived from E_L, E_C, shear modulus G_LC, the wood density, and the guitar body dimensions. It targets a specified vibrational stiffness (f_vs) preset.

### FLC Tap

A diagonal-mode tap that excites the torsional resonance of the plate. Used to calculate the shear modulus G_LC for the Gore thickness formula. Hold the plate at the midpoint of one long edge and tap near the opposite corner (~22% from both the end and the side).

### Free-Free Beam

The boundary condition assumed by the tap-tone formula. The plate ends are unsupported (free), which is approximated by holding the sample at one nodal point (22% from one end along the dimension being measured). The formula constant 22.37 comes from the first mode shape of a free-free Euler–Bernoulli beam.

### FFT (Fast Fourier Transform)

The algorithm that converts a time-domain audio signal into a frequency-domain spectrum. Guitar Tap uses a 65,536-point windowed FFT (Hann window) giving a frequency resolution of approximately 0.67 Hz per bin at a 44.1 kHz sample rate.

