# Chapter 10 — Tips, Technique, and Troubleshooting

Practical advice for tighter results, plus a table of common
problems and their fixes.

## 10.1 Tap Technique

The cleanest impulse comes from a **small bouncy ball on the end
of a stick**. Short contact time, clean impulse, low operator
variability, and reproducible day to day. Works for all three
modes (guitar, plate, brace).

A **firm knuckle or fingertip rap** is the day-to-day alternative
for guitar-body surveys and works well there. It is less ideal
for plate and brace measurements because contact time varies
more.

**Contact time matters.** A long slow push excites fewer
overtones and muddies the spectrum; the shorter the contact, the
better the high-frequency content. If the spectrum looks
smeared-out around the peaks you care about, suspect contact time
before suspecting the mic or the room.

**Tap location:**

- **Guitar body** — on the bridge centered, on each wing of the bridge, below the bridge centered, on each side. The decision comes from experience and which node excitation is desired.
- **Plate or brace** — centre of the face. Off-centre taps bias
  the result; the centre is at the antinode of every mode the
  measurement is designed to capture.

**Force.** The tap does not have to be loud — it just has to
clear Threshold (§2.6). An unnecessarily hard tap is more likely
to trigger double-detection or saturate the input than a
deliberate, medium tap.

## 10.2 Consistent Microphone Position

The wood's resonant *frequencies* are fixed; only the *magnitude*
the microphone sees depends on where the mic is sitting. Position
therefore matters for any comparison you make over time — across
build stages, across thinning passes, across instruments.

Mark the position with a piece of tape or a chalk line on the
bench. When you come back tomorrow, set up against the same mark.

**Distance:** 5–15 cm is a useful range. Closer than 5 cm risks
off-axis rejection from a directional mic; further than ~20 cm
gives away signal-to-noise without much benefit.

## 10.3 Dealing with Background Noise

The Threshold slider is the first line of defence. Move it
**higher** (closer to 0 dB) to reject ambient noise; **lower**
(more negative) to catch quieter taps. The goal is to put
Threshold comfortably above the noise floor and comfortably below
your tap peak.

The detector also applies a **3 dB hysteresis margin**: after a
tap fires, the signal must drop 3 dB below Threshold before the
detector re-arms. This prevents the ring-out tail from
re-triggering as a second tap. The 3 dB value is fixed and is
appropriate for typical rooms.

**Practical target.** Keep your noise floor at least 10 dB below
Threshold; if it is closer, false triggers become likely.

**Plate and brace track the noise floor for you.** In Plate and
Brace modes Threshold is not used as a fixed level. The analyzer
measures the room's noise floor continuously and fires only on
signals rising at least 10 dB above it, with Threshold acting as
the upper bound. Material taps are quiet, and this is what keeps
them detectable in a room whose noise floor drifts — where a fixed
level would either sit under the noise (triggering constantly) or
over the tap (detecting nothing). Guitar mode is unchanged:
Threshold is an absolute level.

The floor is measured from the audio in the half-second **before**
detection begins, which is why the analyzer ignores taps struck the
instant you press New Tap: it is listening to the room first. Give
it that moment.

**Pausing to measure the noise floor.** Press **Pause** (§2.6),
leave the analyzer running, and watch the live spectrum for a few
seconds. Sustained noise peaks tell you where the noise floor
sits; pick Threshold a comfortable margin above them.

**Worst offenders.** HVAC fans, refrigerator compressors,
traffic, and computer fans. Plate and brace measurements that
need to compare cleanly across days are worth either silencing or
moving away from these sources.

**Plate/brace audio files need half a second before the first
tap.** Because the plate and brace detectors measure the room from
the audio ahead of the first tap (above), a file played back in
those modes must actually contain that audio — at least half a
second of room tone before the first strike. Recordings made by
Guitar Tap always do, so replaying a session you captured here
always works. A file recorded elsewhere may not: if its first tap
falls inside that opening half-second, the tap is treated as part
of the settling period, is not detected, and nothing is captured.
Re-record with a moment of silence in front of the first tap.
Guitar files are unaffected — guitar detection uses the absolute
Threshold and needs no lead-in.

## 10.4 Decoupling the Top from the Air Mode

A normal tap of the guitar body excites the air (Helmholtz) mode
and the top mode together, and the two are coupled — the
displayed top frequency is pulled away from the wood's true value
by the coupling.

To read the top resonance without that bias, block the air
cavity before tapping: **stuff a rag, foam, or other soft fill
into the sound hole** so air cannot pump in and out. With the
cavity blocked the Helmholtz resonance disappears from the
spectrum, and the top peak shifts to the position it would have
without air coupling.

Tap, capture, and read the top frequency. Remove the fill before
returning to normal use.

## 10.5 Ring-Out and Decay Time

Ring-out (decay time) is the time, in seconds, for the tap's
amplitude envelope to fall to 1/e (~37%) of its peak. It is a
direct read on structural damping.

- **Higher decay time** → lower damping → more sustain.
- **Lower decay time** → more damping → energy is being absorbed
  faster.

**Typical soundboard ranges:**

- **> 1.5 s** — excellent.
- **1.0–1.5 s** — good.
- **< 0.8 s** — worth investigating; may indicate over-drying or
  excessive internal friction.

**Before-and-after.** A top plate before bracing typically has a
higher decay time than after bracing. Measuring at each stage
quantifies how much the bracing is damping the resonance — a
useful data point for tracking your own bracing pattern's
behaviour over multiple builds.

Decay time is computed from the tap capture. In a multi-tap
sequence the averaged-capture decay is reported.

## 10.6 Multi-Tap Averaging Strategy

The right tap count depends on what you are measuring:

- **Guitar body survey** — 1–3 taps. The body resonances are
  stable; averaging mainly reduces the impact of an occasional
  noisy or missed tap.
- **Plate or brace material measurement** — 3–5 taps. Averaging
  reduces variance from finger noise and small position
  differences, which matters for the absolute E_L value.
- **Diagonal (fLC) tap (plate mode)** — 1–3 taps. The diagonal
  resonance is weaker, so position consistency matters more than
  averaging. Tapping it repeatedly with imperfect positioning can
  *increase* variance rather than reduce it.

**When averaging helps least.** Very quiet room, experienced
tapper, firm bouncy-ball implement: single-tap is usually
sufficient.

**Sanity check.** For a new piece of stock or a new technique,
take a single tap and a 5-tap average of the same blank and
compare the frequencies. If they agree to within 1 Hz you can
trust single-tap measurements for that piece going forward.

**Pause within a sequence.** Press Pause after any captured tap
to reposition your hand or settle the room; Resume re-arms the
detector for the next tap.

## 10.7 Common Problems

| Problem | Likely cause | Fix |
|---|---|---|
| No tap detected | Threshold too high | Lower the Threshold slider (§2.6). |
| Plate / brace: playing an audio file recorded elsewhere detects nothing | The file has less than half a second of room tone before the first tap, so the tap falls inside the noise-floor settling period | Re-record with a moment of silence before the first tap (§10.3). Files recorded by Guitar Tap always contain it. |
| False detections | Threshold too low, or noisy room | Raise Threshold; verify the noise floor with Pause (§10.3). |
| Peaks missing on the chart | Peak Min too high | Lower the Peak Min slider (§2.7). |
| Unknown peaks everywhere | Modes fall outside the standard windows, or Show Unknown Modes is on | Pick the guitar type whose windows fit your instrument (§3.1); turn off **Show Unknown Modes** (§8.5) to hide the rest, or assign modes manually (§3.7). |
| Spectrum doesn't update | Microphone permission not granted | iOS / iPadOS: Settings → Guitar Tap → Microphone. macOS: System Settings → Privacy & Security → Microphone. Windows: Settings → Privacy & Security → Microphone. Linux: check `pavucontrol` (§2.2). |
| Status bar shows **No audio input — check the microphone connection** and the level reads −∞ dB, although the microphone is connected | The microphone's **input volume** is set to zero in the system's sound settings, so the system delivers silence. Other recording apps hear nothing from it either. | macOS: System Settings → Sound → Input → select the microphone and raise **Input volume**; the level meter there should move when you speak. Windows: Settings → System → Sound → select the microphone → **Volume**. Linux: raise the input level in `pavucontrol`. |
| Plate calculation missing | Dimensions not entered | Settings → Measurement Type → Plate; fill in Length / Width / Thickness / Mass (§4.3, §8.3). |
| Gore thickness shows "G_LC assumed 0" | Diagonal (fLC) tap not captured | Enable **Measure Diagonal (fLC) Tap** in Settings and re-run the plate sequence (§4.8). |
| Analysis Results panel not visible (desktop) | Window too narrow | Widen the window. |
| Plate / brace stuck waiting for next phase | Accept not pressed | Look for **Accept** (green checkmark) in the tap controls — it replaces Pause during the review phase (§4.5). |
| Plate / brace: need to redo a phase already accepted | Phase locked in | Press **New Tap** to restart the whole sequence. Per-phase redo is only available before that phase is accepted. |
| Compare button does not appear | Fewer than 2, more than 5, or a plate / brace measurement is in the selection | Select 2–5 guitar measurements only (§3.9). |
| Threshold / Taps differ from your Settings after loading a measurement | Loaded measurement's settings are active | The status bar shows a **Loaded settings** notice (§7.3 and §9.7). Change Settings, or press **New Tap** to start fresh with your own values. |
| Linux: a microphone plugged in while the app is running doesn't appear | Linux builds do not detect microphones connected or disconnected while Guitar Tap is running | Open Settings → Audio Input and select it, or restart Guitar Tap (§2.3). Automatic on iOS, macOS and Windows. |
| Windows: taps barely register, even with Threshold at its lowest, and the chart is unnaturally silent between taps | Windows **Audio enhancements** ("Device default effects" or "Voice clarity") process the microphone for voice calls and suppress taps as noise. This can affect USB microphones too. | Settings → System → Sound → select the microphone → set **Audio enhancements** to **Off**. Also turn off any noise-reduction app from the laptop maker (for example Acer PurifiedVoice or Realtek Audio Console). |
| Imported file: input device warning after import | Mic named in the file isn't on this system | The import succeeded; a fallback device is in use. Reconnect the original mic, or pick a current one in Settings → Audio Input (§7.9). |
| Web build: the Metrics panel shows a different sample rate than your microphone's (e.g. 44 100 Hz from a 48 000 Hz microphone), or loading a measurement warns that the sample rate differs | The browser captures at the **default output** device's rate, not the microphone's | Set the default output device to the same rate as the microphone (§8.2) — on macOS in Audio MIDI Setup — then reload the page. The browser does not pick up the new rate until the page is reloaded. |
| Loaded measurement: warning about a different calibration and/or sample rate | The recorded microphone matches, but the active calibration or the OS sample rate differs from when the measurement was made | Informational only — the saved data is unaffected. A **newly captured** tap will not match the saved one until they agree. Match the sample rate in your OS audio settings (§8.2) and reselect the calibration in Settings → Audio Input. |
| A fresh tap of the same instrument doesn't match a saved measurement | Microphone, calibration, or sample rate changed since the measurement was saved | These determine the captured spectrum. Reproduce the original microphone, calibration, and sample rate (§8.2); the load-time warning tells you which one differs. |
