# GuitarTap Manual Test Checklist

Tester: ___________________    Date: ____________    Build: ____________

Platform(s) tested: `[ ]` iPhone   `[ ]` iPad   `[ ]` macOS

---

## F — FFT Pipeline (Manual)

### F21 — Live FFT renders in real time
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App running with microphone permission granted.

- [ ] Launch the app (recording begins automatically)
- [ ] Verify the spectrum chart updates periodically (expected ~0.7 Hz — roughly once per 1.5 s)
- [ ] Confirm the display does not freeze permanently or show obviously stale data
- [ ] Note: the low update rate is by design — the large FFT window needed for high frequency resolution requires ~1.5 s of audio per frame

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### F22 — Silence floor is plausible
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App recording in a quiet environment.

- [ ] Launch the app in a quiet environment (recording begins automatically)
- [ ] Observe the noise floor level displayed in the spectrum
- [ ] Confirm the noise floor is visible and stable near −70 to −90 dB
- [ ] Confirm the floor is not jumping or showing false peaks

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### F23 — Pure tone visible at correct frequency
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** A 220 Hz reference tone source is available (e.g. tuning app, online tone generator). In Settings, confirm the mode is set to a Guitar tap mode (not a Material tap mode), so that 220 Hz falls within the displayed frequency range.

- [ ] Launch the app (recording begins automatically)
- [ ] Play a 220 Hz tone near the device microphone
- [ ] Verify a peak appears in the spectrum chart near 220 Hz (within ±5 Hz)

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

## T — Tap Detection (Manual)

### T9 — Tap detected on physical knock
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App running and recording. Tap count set to 1. Acoustic measurement mode. Microphone (built-in or external) positioned close to the guitar body.

- [ ] Confirm spectrum is animating (recording starts automatically on launch)
- [ ] Knock the guitar top firmly once
- [ ] Verify the tap indicator flashes green
- [ ] Verify `Tap count: 1/1` appears in the status bar
- [ ] Verify the spectrum freezes and displays the captured response

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### T10 — Minimum inter-tap interval enforced
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App running and recording. Tap count set to 3.

- [ ] Knock the guitar twice in very rapid succession (<0.3 s apart)
- [ ] Verify only one tap is counted
- [ ] Confirm the second knock within the cooldown window is silently rejected

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### T11 — Background noise does not false-trigger
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App running and recording. Tap count set to 1. Device in a quiet room with no intentional taps.

- [ ] Leave recording with no intentional taps for 30 s
- [ ] Confirm the status message remains "Tap the guitar..." throughout
- [ ] Confirm the indicator does not flash green

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### T12 — Threshold setting affects sensitivity
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** App running. Default threshold value set in Settings.

- [ ] Perform a light tap — confirm it is **not** detected at the default threshold
- [ ] Reduce the threshold using the Threshold slider until the threshold line on the chart is below the peak of the previous tap
- [ ] Perform the same light tap — confirm it **is** now detected
- [ ] Raise the threshold back above the tap peak — confirm light taps are missed again

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

## A — Averaging (Manual)

### A3 — Multi-tap accumulation and progress bar
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App running. Tap count set to 3.

- [ ] Knock the guitar once; verify progress bar advances to 1/3
- [ ] Knock again; verify progress bar advances to 2/3
- [ ] Knock a third time; verify progress bar reaches 3/3
- [ ] Confirm the averaged spectrum is displayed after the third tap

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### A4 — Averaged spectrum is more consistent than a single tap
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** App running. A real guitar is available.

- [ ] Set tap count to 1; capture one tap; note the positions of the prominent peaks
- [ ] Tap **Reset**
- [ ] Set tap count to 5; capture five taps, deliberately varying tap position and force slightly between each
- [ ] Compare the two spectra — confirm the prominent peaks appear at the same frequencies (averaging reduces variation due to tap position and force, not spectral smoothness)

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### A5 — New Tap clears previous capture
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App running and recording. One or more taps have been captured (spectrum is frozen).

- [ ] Tap the **New Tap** button
- [ ] Verify the frozen spectrum clears
- [ ] Verify the status message returns to "Tap the guitar..."
- [ ] If a multi-tap sequence was in progress, confirm the progress bar also disappears

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

## S — Audio Stack (Manual)

### S1 — First launch: microphone permission prompt
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** Permission must be in the "not determined" state. Toggling the microphone switch off in System Settings is **not** sufficient — that sets the status to "denied" and does not re-trigger the system prompt. To reset to "not determined":
- **iOS/iPadOS:** Delete and reinstall the app, or use **System Settings → General → Transfer or Reset iPhone → Reset → Reset Location & Privacy**.
- **macOS:** Run `tccutil reset Microphone` in Terminal (resets all apps), then relaunch GuitarTap.

- [ ] Launch GuitarTap
- [ ] Verify the OS permission dialog "GuitarTap would like to access the microphone" appears
- [ ] Confirm the app does not crash
- [ ] Confirm the app does not start recording before the user responds

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### S2 — Permission denied: graceful degradation
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** Microphone permission previously denied (by tapping "Don't Allow" in S1, or by toggling off in System Settings). App running.

**Note (macOS):** Toggling the slider off in System Settings causes macOS to force-restart GuitarTap. The app checks permission on launch, so the alert appears automatically on restart — no need to press Start first.

- [ ] Launch GuitarTap (the app attempts to start recording automatically; the alert will appear at launch)
- [ ] Verify the app does not crash
- [ ] Verify recording does not start
- [ ] Confirm an alert titled "Microphone Access Required" appears
- [ ] Tap/click **Open Settings** and verify it navigates to System Settings → Privacy & Security → Microphone

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### S3 — Permission granted after denial
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** Microphone permission was previously denied.

- [ ] Open **System Settings → Privacy & Security → Microphone → GuitarTap** and enable it
- [ ] **iOS/iPadOS:** Return to GuitarTap (no relaunch needed on iOS 14+) — recording restarts automatically
- [ ] **macOS:** GuitarTap is force-restarted automatically; recording begins on relaunch
- [ ] Verify recording begins and the spectrum starts animating
- [ ] Verify the green running indicator appears

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### S4 — Microphone-in-use indicator active
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App running on a real device.

- [ ] Launch the app (recording begins automatically)
- [ ] **iOS/iPadOS:** Confirm the orange microphone indicator appears in the status bar
- [ ] **macOS:** Confirm the orange microphone indicator appears in the menu bar (top-right area); note that it persists until the app is quit — this is normal macOS behavior

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### S5 — Session interrupted by incoming call
**Platforms:** iOS    **Priority:** High

**Preconditions:** App recording on a real iPhone.

- [ ] Confirm spectrum is animating (recording starts automatically on launch)
- [ ] Have another phone call the device
- [ ] Let the call ring for 5 s then decline (do not answer)
- [ ] While the call rings, verify recording stops cleanly (no crash, no freeze)
- [ ] After declining, verify the app is in a consistent state

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### S6 — Session interrupted by another audio app
**Platforms:** iOS · iPadOS    **Priority:** Medium

**Preconditions:** App recording on iPhone or iPad.

**Note:** Does not apply to macOS — CoreAudio allows simultaneous audio access by multiple apps, so a playback app does not interrupt GuitarTap's microphone input.

- [ ] Confirm spectrum is animating (recording starts automatically on launch)
- [ ] Swipe to the Home screen
- [ ] Open Music or Spotify and start playback
- [ ] Return to GuitarTap
- [ ] Verify GuitarTap is in a stopped state
- [ ] Verify the app recovers when focus returns

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### S7 — Input device selection (macOS)
**Platforms:** macOS    **Priority:** High

**Preconditions:** Two microphone sources available on the Mac (e.g. built-in + USB headset).

- [ ] Launch GuitarTap (recording begins automatically)
- [ ] Open GuitarTap **Settings → Audio Input & Calibration → Audio Input Device** and select the alternative device
- [ ] Within 2 s, verify the spectrum updates to reflect audio from the new device
- [ ] Confirm no crash occurs

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

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

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### S9 — 48 kHz sample rate accepted
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** App recording on any platform.

- [ ] Launch the app (recording begins automatically)
- [ ] Tap **Metrics** to open the metrics overlay
- [ ] Verify **Sample Rate** shows "48000 Hz" (or the device's actual rate)
- [ ] Confirm the value is not "0 Hz", "—", or empty

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### S10 — Non-48 kHz device accepted
**Platforms:** macOS    **Priority:** Low

**Preconditions:** A microphone whose sample rate can be changed in **Audio MIDI Setup** (Applications → Utilities) — the built-in microphone works.

- [ ] Open Audio MIDI Setup and set the device to 44100 Hz
- [ ] Launch GuitarTap and select that device in **GuitarTap Settings → Audio Input & Calibration → Audio Input Device**
- [ ] Confirm recording starts automatically
- [ ] Verify the spectrum chart appears and animates normally
- [ ] Confirm **Sample Rate** in Metrics reads "44100 Hz"
- [ ] While still recording, switch the device back to 48000 Hz in Audio MIDI Setup
- [ ] Verify recording stops briefly then restarts automatically
- [ ] Confirm **Sample Rate** in Metrics now reads "48000 Hz"
- [ ] Confirm the app does not crash or show an error dialog

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

## C — Chart Interaction (Manual)

### C9 — Pinch-to-zoom narrows frequency range
**Platforms:** iOS · iPadOS    **Priority:** High

**Preconditions:** App running with a frozen or live spectrum.

- [ ] Place two fingers near the centre of the spectrum chart
- [ ] Pinch inward (bring fingers together)
- [ ] Verify the frequency axis zooms in and the visible range narrows
- [ ] Confirm axis tick labels update accordingly

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### C10 — Spread-to-zoom widens frequency range
**Platforms:** iOS · iPadOS    **Priority:** High

**Preconditions:** Frequency axis is already zoomed in (range < 1000 Hz).

- [ ] Place two fingers near the centre of the chart
- [ ] Spread fingers apart
- [ ] Verify the frequency axis zooms out and the range widens
- [ ] Confirm the range cannot exceed 0–5000 Hz (linear scale) or 20–5000 Hz (logarithmic scale)

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### C11 — Drag pans frequency axis
**Platforms:** iOS · iPadOS    **Priority:** High

**Preconditions:** Frequency axis is zoomed in to a sub-range.

- [ ] Press and drag the chart to the left; verify frequency axis shifts left
- [ ] Release; confirm position is maintained and zoom span has not changed
- [ ] Drag back to the right; verify frequency axis shifts right

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### C12 — Scroll wheel pans magnitude axis (macOS)
**Platforms:** macOS    **Priority:** High

**Preconditions:** App running on macOS with a trackpad or scroll wheel.

- [ ] Position cursor over the chart
- [ ] Scroll up (no modifier keys)
- [ ] Verify dB axis shifts upward (higher dB values come into view)
- [ ] Confirm frequency axis does not change

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### C13 — Shift+scroll pans frequency axis (macOS)
**Platforms:** macOS    **Priority:** High

**Preconditions:** App running on macOS.

- [ ] Hold **Shift** and scroll left/right
- [ ] Verify frequency axis pans left or right
- [ ] Confirm dB axis does not change

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### C14 — Cmd+scroll zooms both axes (macOS)
**Platforms:** macOS    **Priority:** High

**Preconditions:** App running on macOS. Cursor positioned over a peak.

- [ ] Hold **Cmd** and scroll up (zoom in)
- [ ] Verify both frequency and dB axes zoom in simultaneously
- [ ] Confirm the point under the cursor remains approximately fixed

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### C15 — Option+scroll zooms frequency only (macOS)
**Platforms:** macOS    **Priority:** Medium

**Preconditions:** App running on macOS.

- [ ] Hold **Option** and scroll up
- [ ] Verify frequency axis zooms in
- [ ] Confirm dB axis does not change

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### C16 — Ctrl+scroll zooms magnitude only (macOS)
**Platforms:** macOS    **Priority:** Medium

**Preconditions:** App running on macOS.

- [ ] Hold **Ctrl** and scroll up
- [ ] Verify dB axis zooms in
- [ ] Confirm frequency axis does not change

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### C17 — Zoom anchors to cursor position (macOS)
**Platforms:** macOS    **Priority:** Medium

**Preconditions:** App with a visible peak at a known frequency (e.g. 200 Hz).

- [ ] Position the cursor exactly over the 200 Hz peak
- [ ] Hold **Cmd** and scroll in to zoom
- [ ] Verify the 200 Hz peak remains under the cursor as the axes zoom in

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### C18 — Reset axes to defaults (macOS/iOS/iPadOS)
**Platforms:** macOS · iOS · iPadOS    **Priority:** Medium

**Preconditions:** Frequency and/or dB axes have been panned or zoomed away from defaults.

**macOS:**
- [ ] Right-click the chart area to open the context menu
- [ ] Select **Reset Axes to Defaults**
- [ ] Verify both axes return to the saved default values (as stored in Settings)

**iOS/iPadOS:**
- [ ] Tap the **info icon** on the chart
- [ ] Tap **Reset Axes to Defaults**
- [ ] Verify both axes return to the saved default values (as stored in Settings)

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### C19 — Settings axis ranges preserved on restart
**Platforms:** iOS · iPadOS · macOS    **Priority:** Low

**Preconditions:** App running on any platform.

- [ ] Open Settings and set non-default values for Min Frequency, Max Frequency, Min dB, and Max dB (e.g. 100–500 Hz, −100 to −20 dB)
- [ ] Close Settings and confirm the chart reflects the new ranges
- [ ] Quit the app fully (swipe up on iOS/iPadOS; Cmd+Q on macOS)
- [ ] Relaunch GuitarTap
- [ ] Verify the chart opens with the frequency and dB ranges set in Settings
- [ ] Note: gesture-based pan/zoom is intentionally not persisted and will revert to Settings values on restart

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

## D — Draggable Peak Annotations (Manual)

### D11 — Annotation draggable on screen
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** A measurement has been captured and peak annotations are visible.

- [ ] Press and drag (iOS/iPadOS) or click-and-drag (macOS) a peak label
- [ ] Drag it to a new position
- [ ] Release
- [ ] Verify the label is at the new position and stays there

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### D12 — Annotation position persists after zoom/pan
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** D11 completed; a label has been dragged to a non-default position.

- [ ] Pinch to zoom (iOS/iPadOS) or scroll with Command/Option/Control modifier (macOS) to zoom the chart
- [ ] Pan the chart
- [ ] Verify the annotation label stays attached to its peak at the correct chart position
- [ ] Confirm the label does not jump back to the default position

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### D13 — Annotation reset to default position
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** A label has been dragged to a non-default position (D11).

- [ ] iOS/iPadOS: Double-tap the label; macOS: right-click and choose "Reset Position"
- [ ] Verify the label snaps back to its default (zero-offset) position relative to the peak marker

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### D14 — Annotations hidden in None visibility mode
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** A measurement is captured and annotations are visible.

- [ ] Tap the **Annotations** button until the icon/tooltip indicates "None"
- [ ] Verify all peak annotation labels disappear from the chart

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### D15 — Selected mode shows only Results-panel-selected labels
**Platforms:** iOS · iPadOS · macOS    **Priority:** Low

**Preconditions:** Multiple peaks are visible and at least one peak is not selected in the Results panel.

- [ ] In the Results panel, confirm some peaks are selected and some are not
- [ ] Cycle the Annotations button to the **Selected** mode
- [ ] Verify only the labels for Results-panel-selected peaks are visible
- [ ] Verify labels for unselected peaks are hidden

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### D16 — Guitar mode auto-selects one peak per mode on freeze
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App in guitar measurement mode. A real guitar (or tone source covering multiple mode frequencies) available.

- [ ] Capture a tap so the spectrum freezes
- [ ] Open the Results panel
- [ ] Verify that at most one peak per mode (Air, Top, Back, Dipole, Ring Mode, Upper Modes) is selected (checkmark shown)
- [ ] Verify that if two mode ranges overlap and a peak falls in both, the peak is assigned to the lower-frequency mode
- [ ] Verify that peaks with mode "Unknown" are **not** auto-selected (no checkmark)
- [ ] Confirm the **Reset to Auto** wand button (⌛) in the Results panel header is disabled (already in auto state)

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### D17 — Peak Min recalculates frozen guitar spectrum; selections update correctly
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** A guitar tap has been captured and the spectrum is frozen with at least two annotated peaks.

**Part A — Auto state (no manual changes):**
- [ ] Without touching any selection checkboxes, move the Peak Min slider to the right (raise threshold)
- [ ] Verify peaks that fall below the new threshold disappear from the chart and Results panel
- [ ] Verify the remaining auto-selected peaks update (wand button stays disabled — still in auto state)
- [ ] Move the slider back left; verify the previously hidden peaks reappear and auto-selection re-runs

**Part B — Manual state:**
- [ ] Toggle any peak's checkmark in the Results panel (select or deselect it)
- [ ] Confirm the **Reset to Auto** wand button is now enabled
- [ ] Move the Peak Min slider
- [ ] Verify peaks that survive the threshold carry their selection state forward (a peak you selected stays selected; one you deselected stays deselected)
- [ ] Verify peaks removed by the threshold are simply gone (no crash, no stale IDs)

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### D18 — Reset to Auto restores mode-priority selection
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** A guitar tap is frozen and the user has made at least one manual selection change (D17 Part B).

- [ ] Confirm the **Reset to Auto** wand button (⌛) in the Results panel header is enabled
- [ ] Tap/click the wand button
- [ ] Verify the selection reverts to auto-selection (one best peak per mode, lowest-first)
- [ ] Verify the wand button becomes disabled again
- [ ] Verify moving the Peak Min slider now re-runs auto-selection (not carry-forward)

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

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

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### R8 — Export Measurement round-trip — export and re-import matches original
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** A measurement with peaks is saved.

- [ ] Open the Measurements list; right-click (macOS) or long-press (iOS/iPadOS) the row and choose **View Details**; note the name, date, location/notes, and all peaks in the Results panel
- [ ] Right-click (macOS) or long-press (iOS/iPadOS) the same row and choose **Save Measurement to Disk…** (macOS) or **Export Measurement** (iOS/iPadOS); save the `.guitartap` file
- [ ] Import the file using the **Import** toolbar button (macOS) or ellipsis → **Import Measurement** (iOS/iPadOS)
- [ ] Right-click (macOS) or long-press (iOS/iPadOS) the newly imported row and choose **View Details**
- [ ] Verify the name, date, and location/notes match the original
- [ ] Verify the Results panel shows the same peaks with the same frequencies, magnitudes, and mode assignments
- [ ] Verify the spectrum chart appearance matches the original

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

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

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### R10 — Cross-device transfer via export/import
**Platforms:** iOS · iPadOS · macOS    **Priority:** Low

> **Note:** No automatic iCloud sync — cross-device transfer requires manual export/import.

**Preconditions:** Two devices with GuitarTap installed. A measurement is saved on device A.

- [ ] On device A: choose **Export Measurement** (iOS/iPadOS, or macOS for share sheet) or **Save Measurement to Disk…** (macOS for save to disk); send the `.guitartap` file to device B via AirDrop, Files/iCloud Drive, or email; AirDrop will route the file directly to GuitarTap on the receiving device
- [ ] On device B: import the file using **Import** toolbar button (macOS) or ellipsis → **Import Measurement** (iOS/iPadOS); legacy `.json` files are also accepted
- [ ] Verify the measurement appears in the list on device B

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

## CP — Comparison Mode (Manual)

### CP1 — Enter and exit compare mode
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** At least 2 saved guitar measurements exist in the Measurements list.

- [ ] Open the **Measurements** list
- [ ] Tap/click **Compare**
- [ ] Verify the list enters selection mode (checkboxes appear, Import and Delete All are disabled)
- [ ] Tap/click **Cancel** (or the Compare button again if applicable)
- [ ] Verify the list returns to normal mode

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### CP2 — Plate/brace measurements not selectable in compare mode
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** The Measurements list contains at least one plate or brace measurement and at least one guitar measurement.

- [ ] Enter compare mode (tap **Compare**)
- [ ] Tap a plate or brace measurement row
- [ ] Verify it does not become selected (no checkmark appears)
- [ ] Verify the **Compare Selected** button does not activate for plate/brace-only selection

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### CP3 — Compare Selected loads overlay on main chart
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** At least 2 saved guitar measurements with spectrum snapshots exist.

- [ ] Enter compare mode
- [ ] Select exactly 2 guitar measurements
- [ ] Verify **Compare Selected (2)** button is now enabled
- [ ] Tap/click **Compare Selected (2)**
- [ ] Verify the Measurements list closes and the main view reappears
- [ ] Verify the main chart shows 2 coloured curves (not the normal red curve)
- [ ] Verify a legend is visible (either on the chart or in the status bar area)
- [ ] Verify the status bar shows "Comparing 2 measurements" and "Press New Tap to exit comparison"

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### CP4 — Compare up to 5 measurements
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** At least 5 saved guitar measurements with spectrum snapshots exist.

- [ ] Enter compare mode and select 5 guitar measurements
- [ ] Confirm **Compare Selected (5)** is enabled
- [ ] Tap/click **Compare Selected (5)**
- [ ] Verify 5 coloured curves appear on the chart, each in a distinct colour (blue, orange, green, purple, teal)

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### CP5 — New Tap exits comparison mode
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** Comparison mode is active (CP3 completed).

- [ ] Confirm the chart shows multiple coloured comparison curves
- [ ] Press/click **New Tap**
- [ ] Verify the chart returns to the normal single red curve (or live spectrum)
- [ ] Verify the status bar returns to tap detection state
- [ ] Verify the Results panel no longer shows "Comparing N measurements"

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### CP6 — Comparison mode disables Save and Annotations
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** Comparison mode is active.

- [ ] Verify the **Save** button is visually disabled (greyed out)
- [ ] Verify the **Annotations** button is visually disabled
- [ ] Attempt to click/tap Save — confirm nothing happens and no sheet appears
- [ ] Press **New Tap** to exit; verify both buttons re-enable

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### CP7 — Results panel during comparison
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** Comparison mode is active.

- [ ] Open the **Results** panel
- [ ] Verify the header badge shows "Comparison" (purple) instead of the measurement type (e.g. "Classical")
- [ ] Verify the peaks list shows "Comparing N measurements" instead of individual peak rows
- [ ] Verify Ring-Out Time and Tap Tone Ratio sections are **not** shown
- [ ] Verify **Export PDF Report** button is **not** shown
- [ ] Verify **Export Spectrum** button **is** shown

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### CP8 — Export Spectrum in comparison mode
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** Comparison mode is active with 2+ measurements.

- [ ] Open the Results panel (or use the export action from the main view)
- [ ] Tap/click **Export Spectrum**
- [ ] Open the saved PNG image
- [ ] Verify the image shows all comparison curves (one per selected measurement)
- [ ] Verify the image shows a legend with coloured line swatches and measurement labels (not "Guitar Modes")
- [ ] Verify no peak annotation boxes appear on the image
- [ ] Verify the header says "Comparing N measurements" (not "Detected Peaks: 0")

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### CP9 — Auto dB in comparison mode
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** Comparison mode is active. The comparison curves are partially off-screen.

- [ ] Tap/click the **Auto dB** button
- [ ] Verify the dB axis adjusts so all comparison curves are visible within the chart bounds
- [ ] Confirm no curve is clipped at the top or bottom of the chart

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### CP10 — Cursor/crosshair works during comparison
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** Comparison mode is active with 2+ curves visible.

- [ ] Move the cursor over the chart (macOS) or enable and drag the crosshair (iOS/iPadOS)
- [ ] Verify a vertical cursor line appears that snaps to the nearest comparison curve
- [ ] Verify a frequency and magnitude readout is displayed
- [ ] Confirm no crash occurs

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

## U — Cross-Platform UI (Manual)

### U1 — All primary controls present on iPhone
**Platforms:** iOS    **Priority:** High

**Preconditions:** iPhone with compact horizontal size class (iPhone SE, iPhone 15, etc.).

- [ ] Launch GuitarTap on iPhone in portrait
- [ ] Verify nav bar left: Results
- [ ] Verify nav bar right: Metrics, Settings
- [ ] Verify header button bar: Auto dB, Crosshair, Annotations, Save, Measurements (icon-only bordered buttons)
- [ ] Rotate to landscape
- [ ] Verify nav bar left: Results, Auto dB, Crosshair
- [ ] Verify nav bar right: Annotations, Save, Measurements, Metrics, Settings
- [ ] Confirm no button is clipped, hidden, or missing in either orientation

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### U2 — All primary controls present on iPad
**Platforms:** iPadOS    **Priority:** High

**Preconditions:** iPad in landscape or portrait orientation.

- [ ] Launch GuitarTap on iPad
- [ ] Verify the two-row header layout shows full-label buttons
- [ ] Confirm both rows are fully visible without horizontal scrolling
- [ ] Confirm all buttons have text labels

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### U3 — All primary controls present on macOS (wide window)
**Platforms:** macOS    **Priority:** High

**Preconditions:** macOS, window at ≥900 px wide.

- [ ] Launch GuitarTap
- [ ] Verify the single-row button layout shows (right-justified): Auto dB, Annotations, Save, Measurements, Metrics, Settings
- [ ] Confirm all buttons have full text labels and are visible in one row

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### U4 — macOS icon-only layout at narrow window
**Platforms:** macOS    **Priority:** Medium

**Preconditions:** macOS.

- [ ] Drag the window to a narrow width (~500 px)
- [ ] Verify `ViewThatFits` switches to the icon-only two-row layout
- [ ] Confirm no button labels are truncated
- [ ] Confirm no button falls off-screen

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### U5 — Status bar correct on iPhone
**Platforms:** iOS    **Priority:** Medium

**Preconditions:** App running on iPhone.

- [ ] Launch the app (recording begins automatically)
- [ ] Verify the compact status bar (28 px tall) shows the tap indicator
- [ ] Verify it shows the dB reading
- [ ] Verify it shows the running dot indicator

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### U6 — Status bar correct on iPad/macOS
**Platforms:** iPadOS · macOS    **Priority:** Medium

**Preconditions:** App running on iPad or macOS.

- [ ] Launch the app (recording begins automatically); perform at least one tap
- [ ] Verify the full status bar shows the progress bar
- [ ] Verify it shows the "Tap Detected!" label
- [ ] Verify it shows the bin count
- [ ] Verify it shows the frozen indicator

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### U7 — Settings sheet opens, changes persist
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** App running on any platform.

- [ ] Tap **Settings**
- [ ] Change the threshold value
- [ ] Dismiss the settings sheet
- [ ] Reopen **Settings**
- [ ] Verify the threshold value matches what was entered

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### U8 — Results sheet opens and closes
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** At least one tap has been captured.

- [ ] Tap **Results**
- [ ] Verify the peaks table appears
- [ ] Dismiss the sheet
- [ ] Confirm the sheet closes cleanly

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### U9 — Save sheet accepts name and saves
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** At least one tap has been captured.

- [ ] Tap **Save**
- [ ] Type a name for the measurement
- [ ] Confirm the save
- [ ] Open **Measurements**
- [ ] Verify the new measurement appears in the list

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### U10 — Measurements list shows saved items
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** At least one measurement has been previously saved.

- [ ] Open **Measurements**
- [ ] Verify saved items are listed with name and date

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

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

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

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

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

## K — Regression Smoke Tests (Manual)

### K1 — App launches without crash
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** Device restarted (cold launch).

- [ ] Tap the GuitarTap icon
- [ ] Verify the main view appears within 3 s
- [ ] Confirm no crash occurs
- [ ] Confirm no "GuitarTap quit unexpectedly" dialog appears

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### K2 — Chart renders with a saved measurement
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** At least one measurement has been saved using the **Save** button during a previous tap tone session (see R8).

- [ ] Export the saved measurement to a `.guitartap` file using **Export Measurement** (iOS/iPadOS share sheet) or **Save Measurement to Disk…** (macOS)
- [ ] Re-import it using **Import Measurement** (iOS/iPadOS) or the **Import** toolbar button (macOS)
- [ ] Open the imported measurement from the Measurements list
- [ ] Verify the spectrum chart renders with peaks annotated
- [ ] Confirm no blank chart or decode error

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### K3 — Recording starts automatically on launch
**Platforms:** iOS · iPadOS · macOS    **Priority:** High

**Preconditions:** Microphone permission granted.

- [ ] Launch the app
- [ ] Verify the green running indicator appears within 3 s
- [ ] Confirm the app does not freeze or crash

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### K4 — Memory stable during extended recording
**Platforms:** iOS · iPadOS · macOS    **Priority:** Medium

**Preconditions:** Xcode Instruments available. App running on a physical device.

- [ ] Profile the app with the Allocations instrument in Xcode
- [ ] Launch the app (recording begins automatically)
- [ ] Record continuously for 2 minutes
- [ ] Verify memory usage grows during FFT initialisation and then plateaus
- [ ] Confirm there is no unbounded growth over the 2-minute period
- [ ] Confirm net growth is less than 10 MB from the plateau

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### K5 — App returns from background correctly
**Platforms:** iOS · iPadOS    **Priority:** High

**Preconditions:** App recording on iPhone or iPad.

- [ ] Confirm spectrum is animating (recording starts automatically on launch)
- [ ] Press the Home button (or swipe up to go home)
- [ ] Wait 10 s
- [ ] Return to GuitarTap by tapping its icon
- [ ] Verify the app is either still recording (indicator green) or in a clean stopped state
- [ ] Confirm the UI is not frozen
- [ ] Confirm no crash has occurred

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

### K6 — Rotation does not break layout
**Platforms:** iOS · iPadOS    **Priority:** Medium

**Preconditions:** App running on iPhone or iPad.

- [ ] Hold the device in portrait; confirm the spectrum is visible and animating (recording starts automatically on launch)
- [ ] Rotate the device to landscape
- [ ] Verify the chart, header buttons, and status bar reflow without truncation or overlap
- [ ] Rotate back to portrait
- [ ] Verify the layout is still correct

- [ ] **Pass**   - [ ] **Fail**     Notes: _______________________________________

---

## Summary

| Area | Total Manual Tests | Pass | Fail | Skipped |
|---|---|---|---|---|
| F — FFT Pipeline | 3 | | | |
| T — Tap Detection | 4 | | | |
| A — Averaging | 3 | | | |
| S — Audio Stack | 10 | | | |
| C — Chart Interaction | 11 | | | |
| D — Draggable Annotations | 8 | | | |
| R — Persistence & Export | 4 | | | |
| CP — Comparison Mode | 10 | | | |
| U — Cross-Platform UI | 12 | | | |
| K — Regression Smoke | 6 | | | |
| **Total** | **71** | | | |

**Overall result:** Pass / Fail / Partial      **Sign-off:** _______________________________
