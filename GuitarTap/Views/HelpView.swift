//
//  HelpView.swift
//  GuitarTap
//

/// # HelpView
///
/// In-app user guide presented as a `List` of `Section` groups.
///
/// ## Content Sections
///
/// | Section | Topics |
/// |---|---|
/// | What Guitar Tap Does | App overview and three workflows |
/// | First-Time Setup | Microphone permission, measurement type, quiet environment |
/// | Guitar Mode | Steps 1–5, mode descriptions, interpreting results |
/// | Plate Mode | Two-tap / three-tap process (L, C, FLC), node-point technique |
/// | Brace Mode | Single-tap longitudinal process |
/// | Ring-Out Time | Decay quality thresholds and interpretation |
/// | Tap Tone Ratio | Top/Air frequency ratio and quality levels |
/// | Material Properties | Young's modulus, radiation ratio, Gore equations |
/// | Tips & Troubleshooting | Common issues and remedies |
///
/// ## Presentation
///
/// - **macOS**: Opened in a dedicated `Window` (id `"help"`) from the Help
///   menu (`⌘?`) via `AppCommands`. Default size 520 × 620 pt.
/// - **iOS**: Shown as a sheet from the main analysis toolbar.
///
/// All content is static text; no external resources are fetched.
///
/// - SeeAlso: `GuitarTapApp`, `AppCommands`

import SwiftUI

// MARK: - Top-level Help View

struct HelpView: View {
    var body: some View {
        List {
            // ── Overview ──────────────────────────────────────────────────
            Section {
                Text("""
Guitar Tap uses your device's microphone to capture the brief ring-out after \
you tap a guitar or wood sample. A 65,536-point FFT (≈0.67 Hz resolution) \
reveals the resonant peaks that carry information about structural modes and \
material stiffness.

Three main workflows are supported:
• Guitar mode — classify resonant modes of a completed instrument.
• Plate mode — measure Young's modulus and quality of a raw tonewood plate.
• Brace mode — measure Young's modulus and quality of a brace strip (single longitudinal tap).
""")
                .font(.body)
            } header: {
                Label("What Guitar Tap Does", systemImage: "waveform.path.ecg")
            }

            // ── First-Time Setup ──────────────────────────────────────────
            Section {
                helpRow(
                    title: "Grant Microphone Access",
                    body: "The first time the app launches it will ask for microphone permission. Tap OK. Without it the analyzer cannot run."
                )
                helpRow(
                    title: "Choose a Measurement Type",
                    body: "Open Settings and pick Classical Guitar, Flamenco, Steel String, Material (Plate), or Material (Brace). The right choice determines which mode-frequency ranges are used and which measurements are calculated."
                )
                helpRow(
                    title: "Quiet Environment",
                    body: "Background noise raises the noise floor. A quiet workbench with the device resting on a folded cloth a few centimetres from the tap point gives the most repeatable results."
                )
            } header: {
                Label("First-Time Setup", systemImage: "wrench.and.screwdriver")
            }

            // ── Guitar Mode ───────────────────────────────────────────────
            Section {
                helpRow(
                    title: "Overview",
                    body: "Guitar mode identifies the key structural resonances of a completed body: Air (Helmholtz cavity resonance), Top (main top-plate resonance), Back, Dipole, Ring Mode, and Upper Modes."
                )
                helpRow(
                    title: "Step 1 — Configure",
                    body: "In Settings choose the guitar type (Classical, Flamenco, or Acoustic/Steel String). Each type has calibrated frequency windows for each mode. You can view those windows in the Settings Measurement Type section."
                )
                helpRow(
                    title: "Step 2 — Position the Microphone",
                    body: "The spectrum updates in real time as soon as the app opens. Set the device microphone 5–15 cm from the guitar, aimed at the sound hole or tap point."
                )
                helpRow(
                    title: "Step 3 — Tap New Tap",
                    body: "Tap the New Tap button to arm the detector, then give the guitar top (or back, side, etc.) a firm knuckle rap. The spectrum freezes automatically when a tap is detected."
                )
                helpRow(
                    title: "Step 4 — Inspect Peaks",
                    body: "Coloured markers label each resonant peak with its mode, frequency, and pitch. In guitar mode, one peak per mode is auto-selected based on the strongest peak in each frequency range, working lowest-to-highest so overlapping ranges resolve in favour of the lower mode. Tap a peak label to toggle its selection. Use the Annotations button to cycle through All / Selected / None label modes. In the Results panel, the wand button resets selections back to automatic if you have made manual changes."
                )
                helpRow(
                    title: "Step 5 — Read the Results",
                    body: "On iOS/iPadOS, tap Results to open the results panel. On macOS, the results panel is always visible on the right side of the window. The panel shows the peak list with frequency, magnitude, Q factor, bandwidth, and pitch. Decay time (ring-out in seconds) and Tap Tone Ratio (Top ÷ Air) are shown when applicable. Typical top/air ratios range from 1.8 to 2.4 for quality instruments."
                )
                helpRow(
                    title: "Multi-Tap Averaging",
                    body: "Setting the tap count to 2–10 averages multiple taps together, reducing noise from finger squeaks and ambient sounds. Progress is shown in the status bar. Use Pause between taps to let the ring-out decay."
                )
                helpRow(
                    title: "Overriding Mode Classification",
                    body: "If a peak is labelled Unknown, or misclassified, tap it in the Results list and assign the correct mode manually. Your override is saved with the measurement."
                )
                helpRow(
                    title: "Step 6 — Save",
                    body: "Tap Save. Enter a location (e.g. \"Upper Bout\" or \"Treble Side\") and any notes. The measurement is stored with all peaks, the spectrum snapshot, and a chart image."
                )
            } header: {
                Label("Guitar Mode", systemImage: "guitars")
            }

            // ── Plate Mode ───────────────────────────────────────────────
            Section {
                helpRow(
                    title: "Overview",
                    body: "Plate material mode measures the stiffness of a rectangular tonewood sample using three free-free beam bending taps: Longitudinal (along grain), Cross-grain, and optionally FLC (diagonal/torsional). From the tap frequencies it derives Young's modulus, speed of sound, specific modulus, radiation ratio, and a quality rating."
                )
                helpRow(
                    title: "Prepare the Sample",
                    body: "Cut or plane a rectangular blank. Measure length (along grain), width (cross grain), thickness, and mass precisely — accuracy here directly affects the calculated moduli. A kitchen scale accurate to 0.1 g is adequate for most samples."
                )
                helpRow(
                    title: "Enter Dimensions in Settings",
                    body: "Open Settings → Measurement Type → Material. Enter Length (along grain), Width (cross grain), Thickness, and Mass. The app instantly shows the calculated density so you can catch data-entry errors before tapping."
                )
                helpRow(
                    title: "Suspension Technique",
                    body: "Hold the plate at one point 22% from one end along the dimension being measured, positioned near one edge in the other dimension (not on that dimension's nodal line). This damps the unwanted resonance while approximating the free-free boundary condition. The other hand taps."
                )
                helpRow(
                    title: "Tap 1 — Longitudinal",
                    body: "With the grain running left–right, hold the plate at one point 22% from one end along the length, near one long edge (not at the width nodal line — this damps the cross-grain resonance). Tap center. Tap New Tap and follow the on-screen prompt \"Capturing Longitudinal\". The app selects the strongest peak as the longitudinal frequency."
                )
                helpRow(
                    title: "Tap 2 — Cross-Grain",
                    body: "Rotate the plate 90° so the grain runs front–back. Hold at one point 22% from one end along the width, near one short edge (not at the length nodal line — this damps the longitudinal resonance). Tap center. The app prompts \"Capturing Cross-Grain\" automatically after the longitudinal tap is accepted."
                )
                helpRow(
                    title: "Tap 3 — FLC (Optional)",
                    body: "Enable Measure FLC in Settings. Hold the plate at the midpoint of one long edge and tap near the opposite corner (~22% from both the end and the side). This adds a shear modulus measurement used in the Gore target-thickness calculation. Omitting it over-estimates target thickness by roughly 5–7%."
                )
                helpRow(
                    title: "Reading the Results",
                    body: """
After all taps, tap Results to see:
• E_L / E_C — Young's modulus along and across grain (GPa)
• c_L / c_C — Speed of sound in each direction (m/s)
• Specific modulus E/ρ — The primary quality metric (GPa per g/cm³)
• Radiation ratio — Sound radiation efficiency
• Cross/Long ratio — Anisotropy (spruce: typically 0.04–0.08)
• Quality rating — Excellent / Very Good / Good / Fair / Poor (spruce scale)
• Gore target thickness — Recommended finished plate thickness for a guitar of your specified body dimensions (requires FLC or uses an approximation)
"""
                )
                helpRow(
                    title: "Spruce Quality Scale",
                    body: "Specific modulus (longitudinal): ≥ 25 → Excellent (Master grade); ≥ 22 → Very Good (AAA); ≥ 19 → Good (AA); ≥ 16 → Fair (A); < 16 → Poor."
                )
                helpRow(
                    title: "Gore Target Thickness",
                    body: "Enter the finished guitar body length and lower bout width in Settings (Material section). Choose the plate stiffness preset: Steel String Top (f_vs 75), Steel String Back (55), Classical (50), or Custom. The result is the plate thickness that hits the preset vibrational stiffness after bracing is factored in — a direct implementation of Gore Equation 4.5-7."
                )
            } header: {
                Label("Plate Mode", systemImage: "square.3.layers.3d")
            }

            // ── Brace Mode ────────────────────────────────────────────────
            Section {
                helpRow(
                    title: "Overview",
                    body: "Brace mode is a fast single-tap variant of Plate mode designed for brace strips. Only a longitudinal tap is needed; cross-grain and FLC are skipped."
                )
                helpRow(
                    title: "Brace Orientation",
                    body: "In Settings → Brace Dimensions, Height is the dimension in the tap direction (the brace standing upright on the bench). This is the t value in the stiffness formula. Length is along the grain."
                )
                helpRow(
                    title: "Technique",
                    body: "Hold the brace at one point 22% from one end along the length, near one edge in the width direction (not on the width nodal line). Tap the top face at the center. The same one-point hold technique as Plate mode."
                )
                helpRow(
                    title: "Results",
                    body: "E_L, c_L, specific modulus, and a spruce quality rating are reported. No cross-grain or Gore thickness calculation is available in Brace mode."
                )
            } header: {
                Label("Brace Mode", systemImage: "align.horizontal.center")
            }

            // ── Controls Reference ────────────────────────────────────────
            Section {
                helpRow(
                    title: "New Tap",
                    body: "Arms the detector for the next tap (or begins a plate measurement sequence). A green indicator shows when a tap has been registered.",
                    systemImages: ["hand.tap"]
                )
                helpRow(
                    title: "Pause / Resume",
                    body: "Temporarily suspends tap detection while keeping the spectrum live. Useful between taps in a multi-tap sequence.",
                    systemImages: ["pause.circle", "play.circle"]
                )
                helpRow(
                    title: "Cancel",
                    body: "Aborts a multi-tap or plate measurement sequence and discards the partial data.",
                    systemImages: ["xmark.circle"]
                )
                helpRow(
                    title: "Results (iOS/iPadOS)",
                    body: "Opens the analysis results panel: peak list, decay time, plate properties, quality rating, and (for Plate mode) the Gore target thickness. The panel also contains Export Spectrum and Export PDF Report buttons. On macOS this button is not shown — the results panel is permanently visible on the right side of the window.",
                    systemImages: ["doc.text"]
                )
                helpRow(
                    title: "Auto dB",
                    body: "Scales the magnitude axis to fit the current signal. Tap it after each measurement to keep peaks visible.",
                    systemImages: ["arrow.up.arrow.down.circle"]
                )
                helpRow(
                    title: "Annotations",
                    body: "Cycles through three label modes: All peaks annotated, Selected peaks only, or None.",
                    systemImages: ["eye", "star.fill", "eye.slash"]
                )
                helpRow(
                    title: "Peak Labels",
                    body: "Drag any peak label to reposition it and avoid overlaps. To reset an individual label: double-tap it (iOS/iPadOS) or right-click it and choose \"Reset Position\" (macOS). To reset all labels at once: use the ellipsis menu's \"Reset Labels\" (iOS/iPadOS) or right-click the chart area (not a label) and choose \"Reset Labels\" (macOS).",
                    systemImages: ["tag"]
                )
                helpRow(
                    title: "Save",
                    body: "Saves the current measurement — enabled only when peaks are detected. Enter a location label and optional notes.",
                    systemImages: ["square.and.arrow.down"]
                )
                helpRow(
                    title: "Measurements",
                    body: "Lists all saved measurements. Right-click (macOS) or long-press (iOS/iPadOS) a row to access: Load into View, View Details, Export Measurement (opens the share sheet — use AirDrop, Mail, etc. to send the .guitartap file), Save Measurement to Disk… (macOS only — saves the .guitartap file via a save dialog), Export Spectrum (saves the chart image), Export PDF Report, or Delete. Use Import Measurement to load a .guitartap (or .json) file from Files or another device.",
                    systemImages: ["list.bullet.clipboard"]
                )
                helpRow(
                    title: "Metrics",
                    body: "Shows FFT engine statistics: frame rate, bin width (Hz/bin), sample rate, and buffer size.",
                    systemImages: ["chart.bar"]
                )
                #if os(iOS)
                helpRow(
                    title: "Crosshair",
                    body: "Enables a draggable crosshair on the spectrum for reading the exact frequency and magnitude at any point.",
                    systemImages: ["dot.viewfinder"]
                )
                helpRow(
                    title: "… Chart Options",
                    body: "The ellipsis button in the top-right corner of the spectrum opens the Chart Options sheet. From here you can reset either or both axes to the values you last saved in Settings (\"Reset to Saved\"), or restore the factory defaults (\"Reset to Defaults\"). If peak labels have been dragged from their auto-positions, \"Reset Labels\" moves them back.",
                    systemImages: ["ellipsis.circle"]
                )
                #else
                helpRow(
                    title: "ⓘ Zoom & Pan Help",
                    body: "The info (ⓘ) button in the top-right corner of the spectrum shows a full reference card for navigating the chart. Scroll wheel and drag gestures are context-sensitive: position the pointer over the plot to operate on both axes, over the frequency axis (bottom) to operate on frequency only, or over the magnitude axis (left) to operate on magnitude only. Modifier—key shortcuts are also available: ⇧ Scroll — pan frequency; ⌥ Scroll — pan magnitude; ⌘ Scroll — zoom both axes; ⌃ Scroll — zoom both axes; Pinch — zoom of both axes or each individual axis (trackpad). Right-click the chart area to reset axes and labels; right-click a label to reset just that label's position.",
                    systemImages: ["info.circle"]
                )
                #endif
            } header: {
                Label("Controls Reference", systemImage: "hand.tap")
            }

            // ── Tap Controls Reference ────────────────────────────────────
            Section {
                helpRow(
                    title: "Taps (stepper)",
                    body: "How many taps to average together (1–10). Averaging reduces noise from tap-position variability and ambient sound. Values of 3–5 are a good starting point for material work."
                )
                helpRow(
                    title: "Threshold (slider)",
                    body: "The signal level that triggers tap detection. If taps are being missed, move the slider left (lower). If ambient noise triggers false detections, move it right (higher). Displayed in dB."
                )
                helpRow(
                    title: "Hysteresis (slider)",
                    body: "How far the signal must drop below the detection threshold before the detector resets and is ready for the next tap. A higher value prevents a single loud tap from triggering multiple detections."
                )
                helpRow(
                    title: "Peak Min (slider)",
                    body: "Minimum magnitude a spectral peak must reach to be annotated on the spectrum chart. In guitar mode, a peak must also clear this threshold to be reported; adjusting it on a frozen spectrum re-runs peak finding and updates auto—selections (or carries forward manual selections if you have changed them). In brace/plate mode, the tap capture uses its own adaptive noise floor — Peak Min only affects what is visible on the chart, not which peaks are selected. Move the slider left to show quieter peaks; right to suppress noise. Displayed in dB."
                )
                helpRow(
                    title: "Reset arrows",
                    body: "Each slider has a small ↺ button that resets it to the factory default value."
                )
            } header: {
                Label("Tap Controls (main view)", systemImage: "slider.horizontal.3")
            }

            // ── Settings Reference ────────────────────────────────────────
            Section {
                helpRow(
                    title: "Measurement Type",
                    body: "Classical Guitar, Flamenco, Acoustic/Steel String, Material (Plate), or Material (Brace). Determines which mode frequency windows are applied and which calculations appear in Results."
                )
                helpRow(
                    title: "Show Unknown Modes",
                    body: "Guitar mode only. When off, peaks outside the known mode frequency windows are hidden, reducing clutter."
                )
                helpRow(
                    title: "Display Frequency Range",
                    body: "Sets the horizontal zoom of the spectrum chart. Narrow the range to zoom in on a region of interest. Use Save Current View to persist the current pan/zoom as the default."
                )
                helpRow(
                    title: "Display Magnitude Range",
                    body: "Sets the vertical scale (dB). Use Auto dB in the main view for a quick fit, or set explicit Min/Max here."
                )
                helpRow(
                    title: "Analysis Frequency Range",
                    body: "Peaks outside this window are ignored during detection. Narrow it to exclude spurious low-frequency rumble or high-frequency noise."
                )
                helpRow(
                    title: "Peak Min",
                    body: "Same control as Peak Min on the main view — also accessible here. Sets the minimum magnitude (dB) for a peak to be annotated on the spectrum chart. In guitar mode this also gates which peaks are reported; adjusting it on a frozen spectrum re-runs peak finding and updates selections (auto if untouched, carry-forward by frequency if manually changed). In brace/plate mode the measurement capture uses its own adaptive noise floor, so Peak Min only affects what is annotated on the live chart. Typical useful range: −60 to −40 dB."
                )
                helpRow(
                    title: "Maximum Peaks",
                    body: "Caps the number of peaks reported. Set to All to include every peak above the threshold. Fewer peaks reduces visual clutter when testing assembled guitars."
                )
                helpRow(
                    title: "Microphone Selection",
                    body: "If multiple inputs are available (e.g. USB measurement mic or audio interface), you can select the input device here. Changes take effect the next time the analyzer is started."
                )
                helpRow(
                    title: "Calibration",
                    body: "Import a frequency-response calibration file for a measurement microphone. The correction is applied to all future spectra, compensating for microphone coloration. Calibration files must be in the REW/TXT format supported by the app."
                )
            } header: {
                Label("Settings Reference", systemImage: "gearshape")
            }

            // ── Tips ─────────────────────────────────────────────────────
            Section {
                helpRow(
                    title: "Tap Technique",
                    body: "Use a short, crisp knuckle, fingertip tap, or a bouncy ball on a stick. A slow, pressing contact excites fewer overtones and produces a cleaner fundamental. Avoid tapping near the edges — aim for the centre of the plate or brace in Plate and Brace modes and near the bridge area for guitar-body mode surveys."
                )
                helpRow(
                    title: "Consistent Mic Position",
                    body: "Keep the microphone at the same distance and angle between measurements for the most comparable magnitude values. Frequency readings are position-independent, but relative magnitudes are not."
                )
                helpRow(
                    title: "Damping Check with Decay Time",
                    body: "The decay time (ring-out) appears in Results. A longer decay on the top plate typically correlates with lower internal damping — desirable in a soundboard. Compare braced vs. unbraced sections this way."
                )
                helpRow(
                    title: "Air Mode for Setup",
                    body: "The Helmholtz air resonance is easily produced by holding the assembled body near the microphone and clapping your palm over the sound hole. It does not require tapping the wood itself."
                )
                helpRow(
                    title: "Comparing Plates",
                    body: "Save a measurement for each plate with a descriptive location label (wood species, dimensions, sequence number). Use the Measurements list to review and compare side by side, or export measurements as .guitartap files for transfer between devices."
                )
                helpRow(
                    title: "PDF Reports",
                    body: "Each saved measurement can generate a PDF report containing the spectrum chart, peak table, and analysis summary. Open Measurements, select a measurement, then tap the PDF export button."
                )
                #if os(iOS)
                helpRow(
                    title: "Zooming the Spectrum",
                    body: "Pinch to zoom both axes or each individual axis and drag to pan within the chart or on an axis to pan that axis. To reset the axes, tap the … button in the top-right corner of the spectrum and choose Reset to Saved or Reset to Defaults.",
                    systemImages: ["ellipsis.circle"]
                )
                #else
                helpRow(
                    title: "Zooming the Spectrum",
                    body: "Scroll over the chart to zoom — the axis depends on where the pointer is: over the plot area it zooms both axes; over the frequency axis (bottom) it zooms frequency only; over the magnitude axis (left) it zooms magnitude only. Drag to pan the same way. Modifier keys: ⇧ Scroll — pan frequency; ⌥ Scroll — pan magnitude; ⌘/⌃ Scroll — zoom both axes. To reset the axes, right-click anywhere inside the chart.",
                    systemImages: ["info.circle"]
                )
                #endif
            } header: {
                Label("Tips & Technique", systemImage: "lightbulb")
            }

            // ── Glossary ─────────────────────────────────────────────────
            Section {
                helpRow(
                    title: "Air (Helmholtz) mode",
                    body: "The resonance of the air mass in the sound hole, analogous to blowing across a bottle. Typically 80–130 Hz for classical guitar."
                )
                helpRow(
                    title: "Top / Back mode",
                    body: "The fundamental bending resonance of the top or back plate. The relationship between these and the Air mode strongly influences the low-frequency response of the instrument."
                )
                helpRow(
                    title: "Q Factor",
                    body: "Sharpness of a resonance peak. Q = frequency ÷ −3 dB bandwidth. A higher Q means lower internal damping and a longer, purer ring-out."
                )
                helpRow(
                    title: "Specific Modulus (E/ρ)",
                    body: "Young's modulus divided by density. The single best predictor of tonewood quality because it determines how fast sound travels through the wood relative to its weight. Higher is better for soundboards."
                )
                helpRow(
                    title: "Young's Modulus (E)",
                    body: "A measure of how stiff the wood is along a given direction. E_L is along the grain; E_C is across. Reported in GPa."
                )
                helpRow(
                    title: "Speed of Sound (c)",
                    body: "How fast longitudinal sound waves travel through the wood: c = √(E/ρ). Sitka spruce averages ≈5500 m/s along the grain."
                )
                helpRow(
                    title: "Radiation Ratio (R)",
                    body: "Sound radiation efficiency: R = c/ρ. A higher value means the plate radiates sound more efficiently for its weight."
                )
                helpRow(
                    title: "Cross/Long Ratio",
                    body: "E_C ÷ E_L. A measure of wood anisotropy. For spruce guitar tops this typically falls between 0.04 and 0.08; lower values indicate stronger grain structure."
                )
                helpRow(
                    title: "Tap Tone Ratio",
                    body: "Top mode frequency ÷ Air mode frequency. A rough structural quality indicator for assembled guitars; values between 1.8 and 2.4 are typical for well-made instruments."
                )
                helpRow(
                    title: "Gore Target Thickness",
                    body: "A plate thickness prediction based on Gore Equation 4.5-7, derived from E_L, E_C, shear modulus G_LC, the wood density, and the guitar body dimensions. It targets a specified vibrational stiffness (f_vs) preset."
                )
                helpRow(
                    title: "FLC Tap",
                    body: "A diagonal-mode tap that excites the torsional resonance of the plate. Used to calculate the shear modulus G_LC for the Gore thickness formula. Hold the plate at the midpoint of one long edge and tap near the opposite corner (~22% from both the end and the side)."
                )
                helpRow(
                    title: "Free-Free Beam",
                    body: "The boundary condition assumed by the tap-tone formula. The plate ends are unsupported (free), which is approximated by holding the sample at one nodal point (22% from one end along the dimension being measured). The formula constant 22.37 comes from the first mode shape of a free-free Euler–Bernoulli beam."
                )
                helpRow(
                    title: "FFT (Fast Fourier Transform)",
                    body: "The algorithm that converts a time-domain audio signal into a frequency-domain spectrum. Guitar Tap uses a 65,536-point windowed FFT (Hann window) giving a frequency resolution of approximately 0.67 Hz per bin at a 44.1 kHz sample rate."
                )
            } header: {
                Label("Glossary", systemImage: "text.book.closed")
            }
        }
        .navigationTitle("Quick-Start Guide")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }

    // MARK: - Private helpers

    @ViewBuilder
    private func helpRow(title: String, body: String, systemImages: [String] = []) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if systemImages.isEmpty {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            } else {
                HStack(spacing: 6) {
                    ForEach(systemImages, id: \.self) { symbol in
                        Image(systemName: symbol)
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                            .frame(width: 20)
                    }
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            Text(body)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
