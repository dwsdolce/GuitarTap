# GuitarTap Manual Test Checklist

Tester: _____________________________    Date: _____________________________    Build: _____________________________

Platform(s) tested: `[ ]` iPhone   `[ ]` iPad   `[ ]` macOS

---

## F — FFT Pipeline (Manual)

### F21 — Live FFT renders in real time
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App running with microphone permission granted.

- [ ] Tap **Start** to begin recording
- [ ] Verify the spectrum chart animates continuously
- [ ] Confirm frame rate appears to be ≥10 fps (smooth, not choppy)

**Pass / Fail:** _______    Notes: _______________________________________

---

### F22 — Silence floor is plausible
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App recording in a quiet environment.

- [ ] Tap **Start** with no sound being produced
- [ ] Observe the noise floor level displayed in the spectrum
- [ ] Confirm the noise floor is visible and stable near −70 to −90 dB
- [ ] Confirm the floor is not jumping or showing false peaks

**Pass / Fail:** _______    Notes: _______________________________________

---

### F23 — Pure tone visible at correct frequency
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** A 440 Hz reference tone source is available (e.g. tuning app, online tone generator).

- [ ] Tap **Start** to begin recording
- [ ] Play a 440 Hz tone near the device microphone
- [ ] Verify a peak appears in the spectrum chart near 440 Hz (within ±5 Hz)

**Pass / Fail:** _______    Notes: _______________________________________

---

## T — Tap Detection (Manual)

### T9 — Tap detected on physical knock
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App running and recording. Tap count set to 1. Acoustic measurement mode. Device held or placed on guitar body.

- [ ] Tap **Start** and confirm spectrum is animating
- [ ] Knock the guitar top firmly once
- [ ] Verify the tap indicator flashes green
- [ ] Verify `Tap count: 1/1` appears in the status bar
- [ ] Verify the spectrum freezes and displays the captured response

**Pass / Fail:** _______    Notes: _______________________________________

---

### T10 — Minimum inter-tap interval enforced
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App running and recording. Tap count set to 3.

- [ ] Knock the guitar twice in very rapid succession (<0.3 s apart)
- [ ] Verify only one tap is counted
- [ ] Confirm the second knock within the cooldown window is silently rejected

**Pass / Fail:** _______    Notes: _______________________________________

---

### T11 — Background noise does not false-trigger
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App running and recording. Tap count set to 1. Device in a quiet room with no intentional taps.

- [ ] Leave the device recording with no intentional taps for 30 s
- [ ] Verify tap count remains at 0
- [ ] Confirm the indicator does not flash green

**Pass / Fail:** _______    Notes: _______________________________________

---

### T12 — Threshold setting affects sensitivity
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** App running. Default threshold value set in Settings.

- [ ] Note the current threshold value in Settings
- [ ] Perform a light tap — confirm it is **not** detected at the default threshold
- [ ] Reduce the threshold by 10 dB in Settings
- [ ] Perform the same light tap — confirm it **is** now detected
- [ ] Restore the threshold to the original value — confirm light taps are missed again

**Pass / Fail:** _______    Notes: _______________________________________

---

## A — Averaging (Manual)

### A3 — Multi-tap accumulation and progress bar
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App running. Tap count set to 3.

- [ ] Knock the guitar once; verify progress bar advances to 1/3
- [ ] Knock again; verify progress bar advances to 2/3
- [ ] Knock a third time; verify progress bar reaches 3/3
- [ ] Confirm the averaged spectrum is displayed after the third tap

**Pass / Fail:** _______    Notes: _______________________________________

---

### A4 — Averaged spectrum is smoother than a single tap
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** App running. A real guitar is available.

- [ ] Set tap count to 1; capture one tap; note the spectrum appearance
- [ ] Tap **Reset**
- [ ] Set tap count to 5; capture five taps of the same note
- [ ] Compare the two spectra — confirm the 5-tap version is visibly smoother (less high-frequency noise)

**Pass / Fail:** _______    Notes: _______________________________________

---

### A5 — Reset clears display
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App running with one or more taps captured.

- [ ] Tap the **Reset** button
- [ ] Verify the spectrum clears to the noise floor
- [ ] Verify tap count returns to 0
- [ ] Verify the progress bar disappears

**Pass / Fail:** _______    Notes: _______________________________________

---

## S — Audio Stack (Manual)

### S1 — First launch: microphone permission prompt
**Platforms:** iOS · iPadOS    **Priority:** High

**Preconditions:** Fresh install or permissions reset via Settings → Privacy → Microphone → GuitarTap → remove. iOS 16+.

- [ ] Launch GuitarTap for the first time
- [ ] Tap **Start**
- [ ] Verify the iOS permission dialog "GuitarTap would like to access the microphone" appears
- [ ] Confirm the app does not crash
- [ ] Confirm the app does not start recording before the user responds

**Pass / Fail:** _______    Notes: _______________________________________

---

### S2 — Permission denied: graceful degradation
**Platforms:** iOS · iPadOS    **Priority:** High

**Preconditions:** Microphone permission denied (via Settings or by tapping "Don't Allow" in S1). App running.

- [ ] Tap **Start**
- [ ] Verify the app does not crash
- [ ] Verify recording does not start (`isRunning` indicator stays red)
- [ ] Confirm the app remains in a usable state

**Pass / Fail:** _______    Notes: _______________________________________

---

### S3 — Permission granted after denial
**Platforms:** iOS · iPadOS    **Priority:** Medium

**Preconditions:** Microphone permission was previously denied.

- [ ] Open **Settings → Privacy & Security → Microphone → GuitarTap** and enable it
- [ ] Return to GuitarTap (no relaunch needed on iOS 14+)
- [ ] Tap **Start**
- [ ] Verify recording begins and the spectrum starts animating
- [ ] Verify the green running indicator appears

**Pass / Fail:** _______    Notes: _______________________________________

---

### S4 — AVAudioSession category active
**Platforms:** iOS · iPadOS    **Priority:** High

**Preconditions:** App running on a real iPhone or iPad.

- [ ] Tap **Start**
- [ ] Look at the iOS status bar
- [ ] Confirm the orange microphone indicator appears, confirming the `.record` session category is active

**Pass / Fail:** _______    Notes: _______________________________________

---

### S5 — Session interrupted by incoming call
**Platforms:** iOS    **Priority:** High

**Preconditions:** App recording on a real iPhone.

- [ ] Tap **Start** and confirm spectrum is animating
- [ ] Have another phone call the device
- [ ] Let the call ring for 5 s then decline (do not answer)
- [ ] While the call rings, verify recording stops cleanly (no crash, no freeze)
- [ ] After declining, verify the app is in a stopped state
- [ ] Tap **Start** again and verify recording can be restarted

**Pass / Fail:** _______    Notes: _______________________________________

---

### S6 — Session interrupted by another audio app
**Platforms:** iOS · iPadOS    **Priority:** Medium

**Preconditions:** App recording on iPhone or iPad.

- [ ] Tap **Start** and confirm spectrum is animating
- [ ] Swipe to the Home screen
- [ ] Open Music or Spotify and start playback
- [ ] Return to GuitarTap
- [ ] Verify GuitarTap is in a stopped state
- [ ] Tap **Start** to confirm recording can be restarted

**Pass / Fail:** _______    Notes: _______________________________________

---

### S7 — Input device selection (macOS)
**Platforms:** macOS    **Priority:** High

**Preconditions:** Two microphone sources available on the Mac (e.g. built-in + USB headset).

- [ ] Launch GuitarTap and tap **Start**
- [ ] Open **Settings → Input device** and select the alternative device
- [ ] Within 2 s, verify the spectrum updates to reflect audio from the new device
- [ ] Confirm no crash occurs

**Pass / Fail:** _______    Notes: _______________________________________

---

### S8 — External device plug/unplug (macOS)
**Platforms:** macOS    **Priority:** Medium

**Preconditions:** App recording on macOS.

- [ ] Plug in a USB microphone
- [ ] Confirm it appears in the device list in Settings
- [ ] Select it; confirm recording continues
- [ ] Unplug the USB microphone
- [ ] Verify the app does not crash
- [ ] Verify the device list updates
- [ ] Verify recording either falls back to the built-in mic or stops cleanly

**Pass / Fail:** _______    Notes: _______________________________________

---

### S9 — 48 kHz sample rate displayed
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** App recording on any platform.

- [ ] Tap **Start**
- [ ] Tap **Metrics** to open the metrics overlay
- [ ] Verify a sample rate is shown (e.g. "48000 Hz")
- [ ] Confirm the value is not "0 Hz" or empty

**Pass / Fail:** _______    Notes: _______________________________________

---

### S10 — Non-48 kHz device: resampling transparent
**Platforms:** macOS    **Priority:** Low

**Preconditions:** A microphone that reports a native sample rate of 44100 Hz is available. Use **Audio MIDI Setup** (Applications → Utilities) to confirm or force the rate.

- [ ] Open Audio MIDI Setup and set the USB/built-in device to 44100 Hz
- [ ] Launch GuitarTap and select that device in **Settings → Input device**
- [ ] Tap **Start**
- [ ] Verify the spectrum chart appears and animates normally
- [ ] Confirm the app does not crash or show an error
- [ ] Note: the displayed sample rate may still read 48000 Hz (the engine's internal rate) — this is expected

**Pass / Fail:** _______    Notes: _______________________________________

---

## C — Chart Interaction (Manual)

### C9 — Pinch-to-zoom narrows frequency range
**Platforms:** iOS · iPadOS    **Priority:** High

**Preconditions:** App running with a frozen or live spectrum.

- [ ] Place two fingers near the centre of the spectrum chart
- [ ] Pinch inward (bring fingers together)
- [ ] Verify the frequency axis zooms in and the visible range narrows
- [ ] Confirm axis tick labels update accordingly

**Pass / Fail:** _______    Notes: _______________________________________

---

### C10 — Spread-to-zoom widens frequency range
**Platforms:** iOS · iPadOS    **Priority:** High

**Preconditions:** Frequency axis is already zoomed in (range < 1000 Hz).

- [ ] Place two fingers near the centre of the chart
- [ ] Spread fingers apart
- [ ] Verify the frequency axis zooms out and the range widens
- [ ] Confirm the range cannot exceed 20–20000 Hz

**Pass / Fail:** _______    Notes: _______________________________________

---

### C11 — Drag pans frequency axis
**Platforms:** iOS · iPadOS    **Priority:** High

**Preconditions:** Frequency axis is zoomed in to a sub-range.

- [ ] Press and drag the chart to the left; verify frequency axis shifts left
- [ ] Release; confirm position is maintained and zoom span has not changed
- [ ] Drag back to the right; verify frequency axis shifts right

**Pass / Fail:** _______    Notes: _______________________________________

---

### C12 — Scroll wheel pans magnitude axis (macOS)
**Platforms:** macOS    **Priority:** High

**Preconditions:** App running on macOS with a trackpad or scroll wheel.

- [ ] Position cursor over the chart
- [ ] Scroll up (no modifier keys)
- [ ] Verify dB axis shifts upward (higher dB values come into view)
- [ ] Confirm frequency axis does not change

**Pass / Fail:** _______    Notes: _______________________________________

---

### C13 — Shift+scroll pans frequency axis (macOS)
**Platforms:** macOS    **Priority:** High

**Preconditions:** App running on macOS.

- [ ] Hold **Shift** and scroll left/right
- [ ] Verify frequency axis pans left or right
- [ ] Confirm dB axis does not change

**Pass / Fail:** _______    Notes: _______________________________________

---

### C14 — Cmd+scroll zooms both axes (macOS)
**Platforms:** macOS    **Priority:** High

**Preconditions:** App running on macOS. Cursor positioned over a peak.

- [ ] Hold **Cmd** and scroll up (zoom in)
- [ ] Verify both frequency and dB axes zoom in simultaneously
- [ ] Confirm the point under the cursor remains approximately fixed

**Pass / Fail:** _______    Notes: _______________________________________

---

### C15 — Option+scroll zooms frequency only (macOS)
**Platforms:** macOS    **Priority:** Medium

**Preconditions:** App running on macOS.

- [ ] Hold **Option** and scroll up
- [ ] Verify frequency axis zooms in
- [ ] Confirm dB axis does not change

**Pass / Fail:** _______    Notes: _______________________________________

---

### C16 — Ctrl+scroll zooms magnitude only (macOS)
**Platforms:** macOS    **Priority:** Medium

**Preconditions:** App running on macOS.

- [ ] Hold **Ctrl** and scroll up
- [ ] Verify dB axis zooms in
- [ ] Confirm frequency axis does not change

**Pass / Fail:** _______    Notes: _______________________________________

---

### C17 — Zoom anchors to cursor position (macOS)
**Platforms:** macOS    **Priority:** Medium

**Preconditions:** App with a visible peak at a known frequency (e.g. 500 Hz).

- [ ] Position the cursor exactly over the 500 Hz peak
- [ ] Hold **Cmd** and scroll in to zoom
- [ ] Verify the 500 Hz peak remains under the cursor as the axes zoom in

**Pass / Fail:** _______    Notes: _______________________________________

---

### C18 — Double-tap resets axes
**Platforms:** iOS · iPadOS    **Priority:** Medium

**Preconditions:** Frequency and/or dB axes have been panned or zoomed away from defaults.

- [ ] Double-tap the chart area
- [ ] Verify both axes return to the saved default values (as stored in Settings)

**Pass / Fail:** _______    Notes: _______________________________________

---

### C19 — Log/linear scale toggle preserved on restart
**Platforms:** iOS · iPadOS · macOS    **Priority:** Low

**Preconditions:** App running on any platform.

- [ ] Tap the log/linear scale toggle to change it from its current state
- [ ] Note the new state
- [ ] Quit the app fully (swipe up on iOS/iPadOS; Cmd+Q on macOS)
- [ ] Relaunch GuitarTap
- [ ] Verify the scale toggle is in the same state as when the app was quit
- [ ] Confirm the chart renders using that scale immediately on launch

**Pass / Fail:** _______    Notes: _______________________________________

---

## D — Draggable Peak Annotations (Manual)

### D11 — Annotation draggable on screen
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** A measurement has been captured and peak annotations are visible.

- [ ] Long-press (iOS/iPadOS) or click-and-drag (macOS) a peak label
- [ ] Drag it to a new position
- [ ] Release
- [ ] Verify the label is at the new position and stays there

**Pass / Fail:** _______    Notes: _______________________________________

---

### D12 — Annotation position persists after zoom/pan
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** D11 completed; a label has been dragged to a non-default position.

- [ ] Pinch/scroll to zoom the chart
- [ ] Pan the chart
- [ ] Verify the annotation label stays attached to its peak at the correct chart position
- [ ] Confirm the label does not jump back to the default position

**Pass / Fail:** _______    Notes: _______________________________________

---

### D13 — Double-tap annotation resets position
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** A label has been dragged to a non-default position (D11).

- [ ] Double-tap the label
- [ ] Verify the label snaps back to its default (zero-offset) position relative to the peak marker

**Pass / Fail:** _______    Notes: _______________________________________

---

### D14 — Annotations hidden in None visibility mode
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** A measurement is captured and annotations are visible.

- [ ] Tap the **Annotations** button until the icon/tooltip indicates "None"
- [ ] Verify all peak annotation labels disappear from the chart

**Pass / Fail:** _______    Notes: _______________________________________

---

### D15 — Selected mode shows only tapped labels
**Platforms:** iOS · iPadOS · macOS    **Priority:** Low

**Preconditions:** Multiple peaks are visible.

- [ ] Cycle the Annotations button to the **Selected** mode
- [ ] Tap one annotation label
- [ ] Verify only the tapped label is visible and all others are hidden

**Pass / Fail:** _______    Notes: _______________________________________

---

## R — Persistence & Export (Manual)

### R7 — Saved measurement persists across relaunch
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** At least one tap has been captured.

- [ ] Tap **Save**; enter a name (e.g. "Test spruce"); confirm
- [ ] Force-quit the app (swipe up from app switcher or Cmd+Q on macOS)
- [ ] Relaunch GuitarTap
- [ ] Open **Measurements**
- [ ] Verify the saved measurement appears in the list with the correct name and date

**Pass / Fail:** _______    Notes: _______________________________________

---

### R8 — Export JSON is valid
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** A measurement is saved.

- [ ] Open the measurement in the detail view
- [ ] Tap **Export → JSON**
- [ ] Share or save the file to Files / Finder
- [ ] Open the file in a JSON viewer or text editor
- [ ] Confirm the file opens without parse errors
- [ ] Verify the file contains fields: `timestamp`, `peaks`, `annotationOffsets`, `guitarType`

**Pass / Fail:** _______    Notes: _______________________________________

---

### R9 — Export PDF renders correctly
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** A measurement with at least one peak is saved.

- [ ] Open the measurement detail view
- [ ] Tap **Export → PDF**
- [ ] Open the PDF in Preview (macOS) or Files (iOS)
- [ ] Verify the PDF contains the spectrum chart image
- [ ] Verify the PDF contains a table of peaks (frequency, dB, Q, mode)
- [ ] Verify the PDF contains measurement metadata (name, date, guitar type)
- [ ] Confirm there are no blank pages or missing images

**Pass / Fail:** _______    Notes: _______________________________________

---

### R10 — iCloud sync between two devices
**Platforms:** iOS · iPadOS    **Priority:** Low

**Preconditions:** iPhone and iPad signed into the same iCloud account. iCloud Drive enabled.

- [ ] Save a measurement on the iPhone
- [ ] Wait up to 30 s
- [ ] Open Measurements on the iPad
- [ ] Verify the measurement saved on the iPhone appears in the list on the iPad

**Pass / Fail:** _______    Notes: _______________________________________

---

## U — Cross-Platform UI (Manual)

### U1 — All primary controls present on iPhone
**Platforms:** iOS    **Priority:** High

**Preconditions:** iPhone with compact horizontal size class (iPhone SE, iPhone 15, etc.).

- [ ] Launch GuitarTap on iPhone
- [ ] Verify these controls are visible or accessible via toolbar: Start/Stop, Results, Save, Settings, Measurements
- [ ] Verify secondary controls are accessible: Export Spectrum, Auto dB, Crosshair, Annotations
- [ ] Confirm no required button is clipped, hidden under another element, or missing

**Pass / Fail:** _______    Notes: _______________________________________

---

### U2 — All primary controls present on iPad
**Platforms:** iPadOS    **Priority:** High

**Preconditions:** iPad in landscape or portrait orientation.

- [ ] Launch GuitarTap on iPad
- [ ] Verify the two-row header layout shows full-label buttons
- [ ] Confirm both rows are fully visible without horizontal scrolling
- [ ] Confirm all buttons have text labels

**Pass / Fail:** _______    Notes: _______________________________________

---

### U3 — All primary controls present on macOS (wide window)
**Platforms:** macOS    **Priority:** High

**Preconditions:** macOS, window at ≥900 px wide.

- [ ] Launch GuitarTap
- [ ] Verify the single-row button layout shows: Start, Results, Metrics, Save, Export Spectrum, Auto dB, Annotations, Measurements, Settings
- [ ] Confirm all buttons have full text labels and are visible in one row

**Pass / Fail:** _______    Notes: _______________________________________

---

### U4 — macOS icon-only layout at narrow window
**Platforms:** macOS    **Priority:** Medium

**Preconditions:** macOS.

- [ ] Drag the window to a narrow width (~500 px)
- [ ] Verify `ViewThatFits` switches to the icon-only two-row layout
- [ ] Confirm no button labels are truncated
- [ ] Confirm no button falls off-screen

**Pass / Fail:** _______    Notes: _______________________________________

---

### U5 — Status bar correct on iPhone
**Platforms:** iOS    **Priority:** Medium

**Preconditions:** App running on iPhone.

- [ ] Start recording
- [ ] Verify the compact status bar (28 px tall) shows the tap indicator
- [ ] Verify it shows the dB reading
- [ ] Verify it shows the running dot indicator

**Pass / Fail:** _______    Notes: _______________________________________

---

### U6 — Status bar correct on iPad/macOS
**Platforms:** iPadOS · macOS    **Priority:** Medium

**Preconditions:** App running on iPad or macOS.

- [ ] Start recording and perform at least one tap
- [ ] Verify the full status bar shows the progress bar
- [ ] Verify it shows the "Tap Detected!" label
- [ ] Verify it shows the bin count
- [ ] Verify it shows the frozen indicator

**Pass / Fail:** _______    Notes: _______________________________________

---

### U7 — Settings sheet opens, changes persist
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App running on any platform.

- [ ] Tap **Settings**
- [ ] Change the threshold value
- [ ] Dismiss the settings sheet
- [ ] Reopen **Settings**
- [ ] Verify the threshold value matches what was entered

**Pass / Fail:** _______    Notes: _______________________________________

---

### U8 — Results sheet opens and closes
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** At least one tap has been captured.

- [ ] Tap **Results**
- [ ] Verify the peaks table appears
- [ ] Dismiss the sheet
- [ ] Confirm the sheet closes cleanly

**Pass / Fail:** _______    Notes: _______________________________________

---

### U9 — Save sheet accepts name and saves
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** At least one tap has been captured.

- [ ] Tap **Save**
- [ ] Type a name for the measurement
- [ ] Confirm the save
- [ ] Open **Measurements**
- [ ] Verify the new measurement appears in the list

**Pass / Fail:** _______    Notes: _______________________________________

---

### U10 — Measurements list shows saved items
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** At least one measurement has been previously saved.

- [ ] Open **Measurements**
- [ ] Verify saved items are listed with name and date

**Pass / Fail:** _______    Notes: _______________________________________

---

### U11 — Dark mode: no invisible text
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** System dark mode enabled.

- [ ] Launch GuitarTap
- [ ] Review the main view — confirm all text is legible
- [ ] Review the status bar — confirm all text is legible
- [ ] Open and review the settings sheet — confirm all text is legible
- [ ] Open and review the measurement detail view — confirm all text is legible
- [ ] Confirm chart axis labels and peak annotations remain readable
- [ ] Confirm no white-on-white or black-on-black combinations

**Pass / Fail:** _______    Notes: _______________________________________

---

### U12 — Dynamic Type: large text accessible
**Platforms:** iOS · iPadOS    **Priority:** Low

**Preconditions:** Accessibility text size set to the largest option via **Settings → Accessibility → Display & Text Size → Larger Text** (drag slider to maximum).

- [ ] Launch GuitarTap
- [ ] Inspect all buttons in the header and toolbar — confirm no label is clipped or truncated
- [ ] Open the **Settings** sheet and inspect all labels and controls
- [ ] Open the **Measurements** list and inspect row labels
- [ ] Verify all labels and controls remain usable
- [ ] Confirm the layout may reflow but must not hide or overlap any interactive element

**Pass / Fail:** _______    Notes: _______________________________________

---

## K — Regression Smoke Tests (Manual)

### K1 — App launches without crash
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** Device restarted (cold launch).

- [ ] Tap the GuitarTap icon
- [ ] Verify the main view appears within 3 s
- [ ] Confirm no crash occurs
- [ ] Confirm no "GuitarTap quit unexpectedly" dialog appears

**Pass / Fail:** _______    Notes: _______________________________________

---

### K2 — Chart renders with a saved measurement
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** The `chris-1771351833.json` fixture file is available (included in the repo at `GuitarTapTests/`).

- [ ] Use Files (iOS) or Finder (macOS) to import `chris-1771351833.json` into GuitarTap
- [ ] Open the imported measurement from the Measurements list
- [ ] Verify the spectrum chart renders with peaks annotated
- [ ] Confirm no blank chart or decode error

**Pass / Fail:** _______    Notes: _______________________________________

---

### K3 — Recording session starts and stops cleanly
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** Microphone permission granted.

- [ ] Tap **Start**
- [ ] Observe the green running indicator for 5 s
- [ ] Tap **Stop**
- [ ] Verify indicator goes green on Start and red on Stop
- [ ] Confirm the app does not freeze or crash

**Pass / Fail:** _______    Notes: _______________________________________

---

### K4 — Memory stable during extended recording
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** Xcode Instruments available. App running on a physical device.

- [ ] Profile the app with the Allocations instrument in Xcode
- [ ] Tap **Start**
- [ ] Record continuously for 2 minutes
- [ ] Tap **Stop**
- [ ] Verify memory usage grows during FFT initialisation and then plateaus
- [ ] Confirm there is no unbounded growth over the 2-minute period
- [ ] Confirm net growth is less than 10 MB from the plateau

**Pass / Fail:** _______    Notes: _______________________________________

---

### K5 — App returns from background correctly
**Platforms:** iOS · iPadOS    **Priority:** High

**Preconditions:** App recording on iPhone or iPad.

- [ ] Tap **Start**; confirm spectrum is animating
- [ ] Press the Home button (or swipe up to go home)
- [ ] Wait 10 s
- [ ] Return to GuitarTap by tapping its icon
- [ ] Verify the app is either still recording (indicator green) or in a clean stopped state
- [ ] Confirm the UI is not frozen
- [ ] Confirm no crash has occurred

**Pass / Fail:** _______    Notes: _______________________________________

---

### K6 — Rotation does not break layout
**Platforms:** iOS · iPadOS    **Priority:** Medium

**Preconditions:** App running on iPhone or iPad.

- [ ] Hold the device in portrait; confirm the spectrum is visible
- [ ] Tap **Start** and confirm spectrum is animating
- [ ] Rotate the device to landscape
- [ ] Verify the chart, header buttons, and status bar reflow without truncation or overlap
- [ ] Rotate back to portrait
- [ ] Verify the layout is still correct

**Pass / Fail:** _______    Notes: _______________________________________

---

## Summary

| Area | Total Manual Tests | Pass | Fail | Skipped |
|---|---|---|---|---|
| F — FFT Pipeline | 3 | | | |
| T — Tap Detection | 4 | | | |
| A — Averaging | 3 | | | |
| S — Audio Stack | 10 | | | |
| C — Chart Interaction | 11 | | | |
| D — Draggable Annotations | 5 | | | |
| R — Persistence & Export | 4 | | | |
| U — Cross-Platform UI | 12 | | | |
| K — Regression Smoke | 6 | | | |
| **Total** | **58** | | | |

**Overall result:** Pass / Fail / Partial      **Sign-off:** _______________________________
