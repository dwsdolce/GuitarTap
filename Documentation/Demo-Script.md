# GuitarTap — Screen Recording Demo Script
### Audience: Luthiers | Platform: Mac

---

## Before You Start

**Props to have ready:**
- A completed guitar body (or finished instrument)
- A rectangular tonewood plate sample (spruce or cedar), with length, width, thickness, and mass already measured
- A brace strip (optional, for Brace Mode segment)
- A quiet workbench
- Mac with GuitarTap open and the microphone positioned 10 cm from the tap point

**App state to start from:**
- GuitarTap open, analyzer running (live FFT visible)
- Measurement type set to "Classical Guitar"
- No saved measurements yet (or a clean state)
- Frequency range: 75–350 Hz

---

## SEGMENT 1 — Introduction (~30 seconds)

> *Show the main window. Live FFT spectrum is gently updating with background noise. No taps yet.*

**Narration:**
"GuitarTap turns your Mac's microphone into a precision acoustic measurement tool. It uses a high-resolution FFT — 65,536 points — to reveal the resonant modes inside your guitar body and the stiffness properties of your tonewoods, in real time, right at the workbench."

**What to show:**
- The live spectrum updating with ambient room noise
- The frequency axis (75–350 Hz range showing the luthier-relevant range)
- The results panel on the right side of the window

---

## SEGMENT 2 — Guitar Mode: Reading a Completed Body (~2 minutes)

### 2a. Settings

> *Click the Settings button (gear icon). The settings panel slides in.*

**Narration:**
"Let's start with a completed guitar body. In Settings, I've selected Classical Guitar. GuitarTap knows the expected frequency windows for each structural mode — Air, Top, Back, Dipole, Ring Mode — so it can label them automatically."

**What to show:**
- Measurement Type picker showing "Classical Guitar" selected
- The mode frequency windows listed (briefly)
- Close Settings

### 2b. Taking a Tap

> *Position the guitar near the microphone. Click "New Tap". The button state changes to show the detector is armed.*

**Narration:**
"I click New Tap to arm the detector — then give the top a firm knuckle rap."

> *Tap the guitar top. The spectrum freezes within a second. Colored peak labels appear.*

**What to show:**
- The spectrum snapping from live to frozen
- Colored annotations appearing: Air, Top, Back, Dipole labeled on distinct peaks
- The peak labels sitting above their peaks with mode names and frequencies

### 2c. Reading the Results Panel

> *Point to the results panel on the right.*

**Narration:**
"On the Mac, the results panel is always visible. Each resonant peak is listed with its frequency, magnitude, Q-factor, and the nearest musical pitch. Two key metrics appear at the top."

**What to show:**
- **Ring-Out Time** — point to it and say: "Ring-out time tells me how long the tap tone sustained — a proxy for internal damping. Longer is better for a soundboard."
- **Tap Tone Ratio** — point to it and say: "The Tap Tone Ratio is the Top mode frequency divided by the Air resonance. Quality instruments typically land between 1.8 and 2.4."

### 2d. Zooming and Inspecting

> *Scroll the mouse wheel over the frequency axis to zoom in around the Air and Top peaks.*

**Narration:**
"I can zoom into any region by scrolling over the frequency axis. Here I can clearly see the Air resonance at [X] Hz and the Top resonance at [Y] Hz, separated by [Z] Hz."

> *Scroll wheel over the plot area to pan.*

**What to show:**
- Zooming in on the Air–Top peak pair
- The exact frequency readout on each label
- Scrolling back out with a right-click → "Reset Frequency Axis"

### 2e. Multi-Tap Averaging (optional segment)

> *Set the Taps stepper to 3. Click New Tap.*

**Narration:**
"For cleaner results, I can average multiple taps. I'll set it to 3. The status bar counts down as I tap."

> *Tap the guitar three times, pausing briefly between each.*

**What to show:**
- The progress indicator: "Tap 1 of 3… Tap 2 of 3… Tap 3 of 3…"
- The final averaged spectrum appearing

---

## SEGMENT 3 — Saving and the Measurements List (~45 seconds)

> *After the tap above, click the Save button (down-arrow icon).*

**Narration:**
"Once I'm happy with the measurement, I save it. I can tag it with a location — 'Upper Bout' — and add any notes about bracing or voicing decisions."

> *Type "Upper Bout" in the location field, add a short note, and click Save.*

**What to show:**
- The save sheet appearing
- Typing a location label
- Clicking Save

> *Open the Measurements panel (list icon).*

**Narration:**
"The Measurements list keeps a record of every tap. I can reload any measurement, compare them, or export a PDF report."

> *Right-click the saved measurement row.*

**What to show:**
- The context menu: Load into View, View Details, Export Measurement, Export Spectrum, Export PDF Report, Delete
- Briefly highlight "Export PDF Report"

---

## SEGMENT 4 — Plate Mode: Measuring Tonewood (~2.5 minutes)

> *Open Settings. Change Measurement Type to "Material (Plate)".*

**Narration:**
"Now let's evaluate a raw tonewood plate. Switching to Plate mode changes everything — instead of classifying guitar body modes, the app calculates material stiffness properties directly from the tap frequencies."

### 4a. Entering Dimensions

> *In Settings, show the plate dimension fields: Length, Width, Thickness, Mass.*

**Narration:**
"First I enter the plate's dimensions. Length is along the grain, width is cross-grain. I've already measured this Engelmann spruce sample: 520 mm long, 185 mm wide, 3.8 mm thick, 68 grams."

> *Enter the numbers. The density field updates automatically.*

**What to show:**
- Each field being filled in
- The density value updating in real time to confirm the numbers are plausible (~0.4–0.5 g/cm³ for spruce)

> *Close Settings.*

### 4b. Longitudinal Tap

> *Hold the plate at 22% from one end along the length, near one long edge. Show the holding technique.*

**Narration:**
"The holding technique is critical. I hold the plate at one point — 22% from one end along the grain — near one edge in the width direction. This mimics a free-free beam boundary condition, which is what the physics formula assumes. My other hand taps the center."

> *Click New Tap. Tap the plate. The spectrum freezes and a prompt appears: "Capturing Longitudinal".*

**What to show:**
- The on-screen prompt "Capturing Longitudinal"
- A clear dominant longitudinal peak appearing and being selected automatically

### 4c. Cross-Grain Tap

**Narration:**
"Now I rotate the plate 90° so the grain runs front-to-back. Same technique — hold at 22% from one end along the width, near one short edge. The app automatically arms for the cross-grain tap."

> *Rotate the plate. Tap the center. The spectrum updates.*

**What to show:**
- The cross-grain peak appearing — noticeably lower frequency than the longitudinal
- The status updating to show both taps captured

### 4d. Results

> *Point to the results panel.*

**Narration:**
"And there it is. The app has calculated the material properties from just two taps."

**Walk through each result:**
- **E_L** — "Young's modulus along the grain — [X] GPa. That's the primary stiffness axis."
- **E_C** — "Cross-grain modulus — [X] GPa. Notice it's much lower — spruce is strongly anisotropic."
- **Specific Modulus (E/ρ)** — "This is the key number for a luthier. Specific modulus — stiffness divided by density — tells you how fast sound travels through the wood relative to its weight. This plate scores [X], which is [Excellent / Very Good / Good]. For reference, master-grade spruce is typically above 25."
- **Gore Target Thickness** — "And if I've entered my guitar body dimensions in Settings, the app uses Gore's equation to tell me exactly how thick to leave this plate for the target vibrational stiffness. Here it's recommending [X] mm for a steel-string body."

---

## SEGMENT 5 — Brace Mode: Quick Brace Screening (~45 seconds)

> *Open Settings. Change Measurement Type to "Material (Brace)". Enter brace dimensions (e.g., 300 mm long, 25 mm wide, 10 mm tall, 15 g).*

**Narration:**
"Brace mode is a fast version designed for brace strips. One tap — no cross-grain measurement needed — and you immediately know the longitudinal stiffness and quality of the brace."

> *Pick up the brace strip. Hold at 22% from one end. Click New Tap. Tap the brace.*

**What to show:**
- A sharp, clean resonance peak appearing
- Results showing: E_L, speed of sound, specific modulus, quality rating

**Narration:**
"This brace comes in at a specific modulus of [X] — [quality rating]. In a few seconds I can screen an entire box of brace blanks and rank them before a single saw cut."

---

## SEGMENT 6 — Export (~30 seconds)

> *Go back to Guitar Mode measurement. Open Measurements list. Right-click the saved measurement → Export PDF Report.*

**Narration:**
"Every measurement can be exported as a PDF report — spectrum chart, peak table, ring-out time, tap tone ratio, all in one document. Useful for tracking build decisions across a guitar or documenting wood stock for customers."

> *Show the PDF appearing (Quick Look preview or Preview app).*

**What to show:**
- The spectrum chart in the PDF
- The peak table below it
- The summary section with ring-out and tap tone ratio

---

## SEGMENT 7 — Closing (~15 seconds)

> *Return to the main window with the live spectrum running.*

**Narration:**
"GuitarTap brings precision acoustic measurement to the workbench — guitar body modes, tonewood quality, Gore target thickness, decay time — all from a tap and a microphone. Available now on Mac and iPhone."

---

## Tips for the Recording

- **Resolution**: Record at 1440p or higher. The spectrum chart has fine detail worth preserving.
- **Window size**: Expand the GuitarTap window to fill most of the screen. The results panel is always visible on Mac — use a wide aspect ratio to show both the spectrum and results simultaneously.
- **Cursor**: Use a cursor highlighter tool so viewers can track where you're clicking.
- **Silence**: Record in a quiet room. The live FFT will show any background noise; a clean noise floor makes for a more professional recording.
- **Tap sounds**: Let the microphone capture the actual tap sound naturally — hearing the resonance reflected in the spectrum is compelling.
- **Pacing**: Pause briefly after each result appears to let viewers read the numbers before moving on.
- **Color callouts**: The peak labels are color-coded by mode. If you're adding post-production annotations, match the label colors.
