# Chapter 10 — Tips, Technique, and Troubleshooting

<!-- STATUS: STUB — needs full content -->

## 10.1 Tap Technique

<!-- TODO: Write section -->
<!-- Cover:
     - Recommended implement: small bouncy ball on the end of a stick — short contact time,
       clean impulse, very repeatable; suitable for all three modes (Guitar, Plate, Brace)
     - Alternative for guitar body surveys: short crisp knuckle or fingertip rap
     - Why contact time matters: a long slow push excites fewer overtones and muddies the
       spectrum; the shorter the contact the better the high-frequency content
     - Where to tap:
         * Guitar body: top, back, or sides — each position emphasises different modes
         * Plate/brace: centre of the face; any off-centre tap position biases the result
     - Consistent force: the tap does not need to be loud — it needs to be above Threshold;
       an unnecessarily hard tap can cause distortion or trigger false multi-tap -->

## 10.2 Consistent Microphone Position

<!-- TODO: Write section -->
<!-- Cover:
     - Why position affects magnitude but not frequency: the resonant frequencies of the
       wood are fixed; only the coupling efficiency to the microphone changes
     - Practical marking: a small piece of tape or chalk mark on the workbench defines the
       microphone position and distance; reproducing it ensures valid comparisons over time
     - Distance: 5–15 cm is a useful range; too close can cause off-axis rejection with
       directional microphones; too far reduces signal-to-noise ratio -->

## 10.3 Dealing with Background Noise

<!-- TODO: Write section -->
<!-- Cover:
     - Threshold slider: moving right (higher dB, less negative) to reject ambient noise;
       moving left (lower dB, more negative) to catch quiet taps
     - Hysteresis margin: prevents double-detection by requiring the signal to drop below
       Threshold by this margin before re-arming; default 3 dB is appropriate for most rooms
     - Practical noise floor target: background noise should be at least 10 dB below Threshold
       to avoid false triggers
     - Using Pause to assess the noise floor: press Pause and watch the live spectrum for
       sustained noise peaks; adjust Threshold until the noise is clearly below it
     - Worst offenders: HVAC fans, refrigerators, traffic — consider switching them off or
       moving to a quieter space for plate/brace measurements that require consistency -->

## 10.4 Air Mode Technique

<!-- TODO: Write section -->
<!-- Cover:
     - The Air (Helmholtz) mode is excited by compressing the air in the body cavity,
       not by flexing the wood
     - Technique: cup the palm over the sound hole and push quickly, or clap over the hole;
       no wood tapping required; the entire guitar or soundbox can be in its normal position
     - Threshold: the air tap is typically a different signal level than a wood tap;
       consider using Pause to set Threshold specifically for air mode measurements
     - Multi-tap averaging: 3–5 taps is usually sufficient for the air mode; the resonance
       is stable and not affected by grain variation -->

## 10.5 Ring-Out and Decay Time

<!-- TODO: Write section -->
<!-- Cover:
     - What decay time measures: the time (seconds) for the tap response to decay to 1/e
       (~37%) of its peak amplitude — a measure of structural damping
     - Higher decay time = lower damping = more sustain; lower decay time = more damping
       = the wood is absorbing energy more quickly
     - Typical values for quality soundboards: >1.5 s is excellent; 1.0–1.5 s is good;
       <0.8 s may indicate over-drying or excessive internal friction
     - Braced vs. unbraced: a top plate before bracing typically has a higher decay time
       than after bracing; comparing the two at each stage tracks how the bracing damps
       the resonance
     - Note: decay time is measured from the tap capture; multi-tap averaging averages
       the spectra and uses the decay from the averaged capture -->

## 10.6 Multi-Tap Averaging Strategy

<!-- TODO: Write section -->
<!-- Cover:
     - Recommended tap counts for different scenarios:
         * Guitar body survey: 1–3 taps; the resonances are stable and averaging mainly
           reduces occasional missed or noisy taps
         * Plate/brace material: 3–5 taps; averaging reduces variance from finger noise
           and slight position variation; more taps give more stable E_L values
         * FLC tap: 1–3 taps; the FLC resonance is often weaker; avoid over-tapping
           as position consistency is more critical than averaging
     - When averaging helps least: very quiet room, experienced tapper, firm bouncy-ball
       implement; single-tap results are usually sufficient
     - Checking stability: after a measurement, compare the frequency result from a single
       tap to a 5-tap average for the same blank; if they agree to within 1 Hz the
       technique is consistent enough that single-tap measurements are reliable
     - Pause between taps in a multi-tap sequence: press Pause after each tap is registered
       if you want to reposition your hand before the next tap; Resume to re-arm -->

## 10.7 Common Problems

| Problem | Likely cause | Fix |
|---------|-------------|-----|
| No tap detected | Threshold too high | Lower Threshold slider |
| False detections | Threshold too low or noisy room | Raise Threshold; use Pause between taps |
| Peaks missing | Peak Min too high | Lower Peak Min slider |
| Unknown peaks everywhere | Analysis range too wide | Narrow analysis range in Advanced settings |
| Spectrum doesn't update | Microphone permission not granted | Check System Settings (macOS) or iOS Settings |
| Plate calculation missing | Dimensions not entered | Open Settings → Measurement Type → Material |
| Gore thickness not shown | FLC not captured or not enabled | Enable Measure FLC in Settings |
| Results panel not visible | macOS: window too narrow | Widen the window |
| Plate/brace: stuck waiting for next phase | Missed the Accept button | Look for Accept (green, checkmark) in the tap controls — it replaces Pause during review |
| Plate/brace: want to redo a phase already accepted | Phase locked in | Tap New Tap to restart the whole sequence; individual phase redo is only available before Accept is tapped |
| Compare button not appearing | Fewer than 2 or more than 5 selected, or a plate/brace record is in the selection | Select 2–5 guitar measurements only; deselect any plate/brace records |
| Comparison: all curves same colour in exported image | Exporting from an older version | Update the app and re-export |
| Comparison PDF shows 0 spectra | Older app version | Update the app; comparison PDFs now report the correct spectra count |
| Loaded measurement: threshold/tap count differ from Settings | Loaded measurement values override live settings | The status bar shows a warning; adjust Threshold and Taps stepper as needed, or press New Tap to clear the loaded state and restore your current settings |
