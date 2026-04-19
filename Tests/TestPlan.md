# GuitarTap Test Plan

---

## Part 1 — Test Plan

### 1.1 Scope and rationale

GuitarTap has four testability tiers:

| Tier | Examples | Strategy |
|---|---|---|
| Pure logic | DSP math, tap detection, material properties, pitch, codable | Automated unit tests — fast, deterministic, no hardware |
| In-memory state | Annotation offsets, mode overrides, peak selection | Automated unit tests with `@MainActor` isolation |
| Audio / OS integration | AVAudioSession, microphone permissions, interruptions | Manual tests on real device; simulator cannot inject audio |
| UI / interaction | Chart pan/zoom, annotation drag, cross-platform layout | Manual tests with step-by-step procedures |

---

### 1.2 Test catalogue

Each row specifies: **ID · Name · Type · Platforms · Priority · Description**

Legend — Type: **U** = unit, **I** = integration, **M** = manual
Legend — Platform: **iOS** = iPhone, **iPadOS** = iPad, **mac** = macOS

---

#### F — FFT Pipeline

| ID | Name | Type | Platforms | Priority | Description |
|---|---|---|---|---|---|
| F1 | `symmetricPeak_returnsZeroOffset` | U | iOS iPadOS mac | High | Symmetric bins → parabolic offset ≈ 0, frequency ≈ centre bin |
| F2 | `leftLeaningPeak_shiftedLeft` | U | iOS iPadOS mac | High | Left neighbour larger → offset < 0 |
| F3 | `rightLeaningPeak_shiftedRight` | U | iOS iPadOS mac | High | Right neighbour larger → offset > 0 |
| F4 | `edgeBinIndex0_returnsRawValues` | U | iOS iPadOS mac | Medium | Edge bin (index 0) → raw values returned without interpolation |
| F4b | `edgeBinLastIndex_returnsRawValues` | U | iOS iPadOS mac | Medium | Edge bin (last index, no right neighbour) → raw values returned without crash; interpolated location stays within array bounds |
| F5 | `flatTopDenomNearZero_noNaNorInf` | U | iOS iPadOS mac | High | Flat-top peak (denominator ≈ 0) → no NaN or infinity in output |
| F6 | `interpolatedMagnitude_betweenNeighbours` | U | iOS iPadOS mac | Medium | Interpolated magnitude is between the peak bin and its neighbour |
| F7 | `sharpPeak_returnsHighQ` | U | iOS iPadOS mac | High | Sharp peak (halfWidth=20 Hz) has higher Q than broad peak |
| F8 | `broadPeak_returnsLowQ` | U | iOS iPadOS mac | Medium | Broad peak → 0 < Q < 15 |
| F9 | `allBinsAboveThreshold_returnsZeroQ` | U | iOS iPadOS mac | Medium | Flat spectrum → Q = 0 (no −3 dB crossing found) |
| F10 | `singlePureTone_returnsOnePeak` | U | iOS iPadOS mac | High | Single synthetic tone at 1000 Hz → ≥1 peak within 2 bins |
| F11 | `silenceSpectrum_returnsEmpty` | U | iOS iPadOS mac | High | All-silence spectrum → no peaks returned |
| F12 | `clippedSpectrum_returnsEmpty` | U | iOS iPadOS mac | Medium | Flat (fully clipped) spectrum → no strict local maxima |
| F13 | `multipleTones_detectsAll` | U | iOS iPadOS mac | High | Three synthetic tones at 400/700/1000 Hz → ≥3 peaks detected |
| F14 | `allBelowThreshold_returnsEmpty` | U | iOS iPadOS mac | High | All bins below `peakThreshold` → empty result |
| F15 | `wellSeparatedPeaks_keepsBoth` | U | iOS iPadOS mac | High | Peaks 100 Hz apart → both retained after duplicate removal |
| F16 | `nearDuplicates_keepsStronger` | U | iOS iPadOS mac | High | Peaks within tolerance → weaker removed |
| F17 | `powerDomainAveraging_correctResult` | U | iOS iPadOS mac | High | Two spectra averaged → matches manual power-domain calculation |
| F18 | `singleTap_returnsItself` | U | iOS iPadOS mac | Medium | Single-tap input → output equals input |
| F19 | `emptyInput_returnsEmpty` | U | iOS iPadOS mac | Medium | Empty tap array → empty output |
| F20 | `twoIdenticalSpectra_returnsIdentical` | U | iOS iPadOS mac | Medium | Two identical spectra → average equals input |
| F21 | Live FFT renders in real time | M | iOS iPadOS mac | High | Launch app; verify spectrum updates periodically (expected ~0.7 Hz; display does not freeze) |
| F22 | Silence floor is plausible | M | iOS iPadOS mac | High | With no sound, noise floor is visible and stable near −70 to −90 dB |
| F23 | Pure tone visible at correct frequency | M | iOS iPadOS mac | Medium | Play 220 Hz tone from reference; verify peak appears within ±5 Hz |

---

#### T — Tap Trigger Detection

| ID | Name | Type | Platforms | Priority | Description |
|---|---|---|---|---|---|
| T1 | `aboveThreshold_setsTapDetected` | U | iOS iPadOS mac | High | Signal above threshold → `tapDetected = true` |
| T1b | `aboveThreshold_setsLastTapTime` | U | iOS iPadOS mac | High | `lastTapTime` is populated on detection |
| T2 | `belowThreshold_doesNotDetect` | U | iOS iPadOS mac | High | Signal below threshold → `tapDetected = false` |
| T3 | `duringWarmup_suppressesDetection` | U | iOS iPadOS mac | High | Detection suppressed while warmup guard is active |
| T4 | `duringCooldown_suppressesDetection` | U | iOS iPadOS mac | High | Second tap within cooldown window is rejected |
| T5 | `hysteresis_preventsBouncingOnFallingEdge` | U | iOS iPadOS mac | High | Signal between falling and rising thresholds does not re-fire |
| T5b | `hysteresis_signalBelowFallingThreshold_resetsAboveThreshold` | U | iOS iPadOS mac | Medium | Signal below falling threshold clears `isAboveThreshold` flag |
| T6 | `materialMode_usesRelativeNoiseFloor` | U | iOS iPadOS mac | High | In `.material` mode, threshold = noiseFloor + headroom |
| T7 | `noiseFloorEMA_convergesWithRepeatedBelowThresholdFrames` | U | iOS iPadOS mac | Medium | Noise floor EMA drifts toward ambient level over 50 frames |
| T8 | `justExitedWarmup_syncsThenSkips` | U | iOS iPadOS mac | Medium | First frame after warmup syncs state but does not fire a tap |
| T9 | Tap detected on physical knock | M | iOS iPadOS mac | High | Tap guitar top firmly once; verify green indicator flashes and tap count increments |
| T10 | Minimum inter-tap interval enforced | M | iOS iPadOS mac | High | Knock twice in rapid succession (<0.3 s apart); verify only one tap is counted |
| T11 | Background noise does not false-trigger | M | iOS iPadOS mac | High | With quiet ambient audio, verify status message remains "Tap the guitar..." and indicator does not flash for ≥30 s |
| T12 | Threshold setting affects sensitivity | M | iOS iPadOS mac | Medium | Reduce threshold in Settings; verify softer taps are now detected |

---

#### A — Averaging

| ID | Name | Type | Platforms | Priority | Description |
|---|---|---|---|---|---|
| A1 | `powerDomainAveraging_correctResult` (= F17) | U | iOS iPadOS mac | High | (see F17) |
| A2 | `reset_clearsCapturedTapsAndCount` | U | iOS iPadOS mac | High | `reset()` empties `capturedTaps` and zeroes `currentTapCount` |
| A3 | Multi-tap accumulation visible | M | iOS iPadOS mac | High | Set tap count to 3; perform 3 taps; verify progress bar advances 1/3, 2/3, 3/3 |
| A4 | Averaged spectrum is more consistent than single tap | M | iOS iPadOS mac | Medium | Capture 1-tap then 5-tap spectra varying position and force; verify prominent peaks align at the same frequencies — averaging reduces variation, not spectral smoothness |
| A5 | Reset clears display | M | iOS iPadOS mac | High | After capturing taps, tap "Reset"; verify spectrum clears and count returns to 0 |

---

#### S — Audio Stack

| ID | Name | Type | Platforms | Priority | Description |
|---|---|---|---|---|---|
| S1 | First launch — microphone permission prompt | M | iOS iPadOS | High | Fresh install; launch app; verify OS permission dialog appears on first run |
| S2 | Permission denied — graceful degradation | M | iOS iPadOS | High | Deny permission; verify app does not crash; recording does not start; alert shown |
| S3 | Permission granted after denial | M | iOS iPadOS macOS | Medium | Deny then grant permission in System Settings; on macOS app force-restarts; verify recording starts automatically |
| S4 | Microphone-in-use indicator active | M | iOS iPadOS macOS | High | Launch app; verify orange mic indicator appears in status bar (iOS/iPadOS) or menu bar (macOS) |
| S5 | Session interrupted by phone call (iOS) | M | iOS | High | With app recording; receive incoming call; verify recording stops cleanly; after call ends, verify app is in a consistent state |
| S6 | Session interrupted by another audio app | M | iOS iPadOS | Medium | With app recording; launch Spotify/Music and play; verify GuitarTap stops; return to GuitarTap; verify app recovers |
| S7 | Input device selection (macOS) | M | mac | High | Open GuitarTap Settings → Audio Input & Calibration → Audio Input Device; change to a different microphone; verify spectrum updates within 2 s |
| S8 | External device plug/unplug (macOS) | M | mac | Medium | Plug in USB microphone while recording; verify device list updates; unplug; verify app does not crash |
| S9 | 48 kHz sample rate accepted | M | iOS iPadOS mac | Medium | Start recording; open Metrics overlay; verify Sample Rate shown is 48000 Hz |
| S10 | Non-48 kHz device accepted | M | mac | Low | Set device to 44100 Hz in Audio MIDI Setup; start recording; verify spectrum appears and Sample Rate reads 44100 Hz; change back to 48000 Hz while running; verify auto-restart and Sample Rate updates |

---

#### C — Chart Interaction State

| ID | Name | Type | Platforms | Priority | Description |
|---|---|---|---|---|---|
| C1 | `applyFrequencyZoom_scaleIn_narrowsRange` | U | iOS iPadOS mac | High | `applyFrequencyZoom(scale:anchorFreq:)` with scale > 1 reduces `maxFreq − minFreq` |
| C2 | `applyFrequencyZoom_scaleOut_widensRange` | U | iOS iPadOS mac | High | Scale < 1 widens range, clamped to 20–20000 Hz |
| C3 | `applyFrequencyZoom_minimumRange_enforced` | U | iOS iPadOS mac | High | Zoom-in past minimum range (50 Hz) is rejected |
| C4 | `applyMagnitudeZoom_scaleIn_narrowsRange` | U | iOS iPadOS mac | High | `applyMagnitudeZoom(scale:anchorDB:)` with scale > 1 reduces `maxDB − minDB` |
| C5 | `applyMagnitudeZoom_minimumRange_enforced` | U | iOS iPadOS mac | High | Zoom-in past minimum 10 dB range is rejected |
| C6 | `handlePan_frequency_clampsAt20Hz` | U | iOS iPadOS mac | High | Pan left past 20 Hz stops at 20 Hz without changing span |
| C7 | `handlePan_frequency_clampsAt20kHz` | U | iOS iPadOS mac | High | Pan right past 20 kHz stops at 20 kHz without changing span |
| C8 | `handlePan_magnitude_clampsAt120dB` | U | iOS iPadOS mac | Medium | Pan past −120 dB stops at boundary |
| C9 | Pinch-to-zoom narrows frequency range (iOS/iPadOS) | M | iOS iPadOS | High | With a spectrum visible, pinch inward on the chart; verify frequency axis zooms in, anchored near the gesture midpoint |
| C10 | Spread-to-zoom widens frequency range (iOS/iPadOS) | M | iOS iPadOS | High | Spread fingers on the chart; verify frequency axis zooms out |
| C11 | Drag pans frequency axis (iOS/iPadOS) | M | iOS iPadOS | High | Drag chart left/right; verify frequency labels shift accordingly; release and verify position is maintained |
| C12 | Scroll wheel pans magnitude axis (macOS) | M | mac | High | Scroll without modifiers; verify dB axis shifts up/down |
| C13 | Shift+scroll pans frequency axis (macOS) | M | mac | High | Hold Shift and scroll; verify frequency axis pans horizontally |
| C14 | Cmd+scroll zooms both axes (macOS) | M | mac | High | Hold Cmd and scroll; verify both axes zoom around cursor position |
| C15 | Option+scroll zooms frequency only (macOS) | M | mac | Medium | Hold Option and scroll; verify only frequency axis changes |
| C16 | Ctrl+scroll zooms magnitude only (macOS) | M | mac | Medium | Hold Ctrl and scroll; verify only dB axis changes |
| C17 | Zoom anchors to cursor position (macOS) | M | mac | Medium | Position cursor over a peak and Cmd+scroll in; verify the peak stays under cursor |
| C18 | Reset axes to defaults (macOS/iOS/iPadOS) | M | iOS iPadOS mac | Medium | After panning/zooming, reset axes via RMB context menu (macOS) or info icon (iOS/iPadOS); verify axes return to saved defaults |
| C19 | Settings axis ranges preserved on restart | M | iOS iPadOS mac | Low | Set non-default frequency and dB ranges in Settings; quit and relaunch; verify the chart opens with those ranges |

---

#### D — Draggable Peak Annotations

| ID | Name | Type | Platforms | Priority | Description |
|---|---|---|---|---|---|
| D1 | `updateAnnotationOffset_storesOffsetByID` | U | iOS iPadOS mac | High | `updateAnnotationOffset` stores `CGPoint` keyed by peak UUID |
| D2 | `updateAnnotationOffset_overwritesPreviousOffset` | U | iOS iPadOS mac | High | Second write replaces first offset for the same peak |
| D3 | `togglePeakSelection_insertsThenRemoves` | U | iOS iPadOS mac | High | Toggle adds then removes peak UUID from `selectedPeakIDs` |
| D4 | `selectNoPeaks_clearsAll` | U | iOS iPadOS mac | High | `selectNoPeaks()` empties the selection set |
| D5 | `selectedMode_filtersToSelectedPeaks` | U | iOS iPadOS mac | High | `.selected` visibility returns only selected peaks |
| D6 | `noneMode_returnsEmpty` | U | iOS iPadOS mac | High | `.none` visibility returns empty array |
| D7 | `noOverride_returnsAutoLabel` | U | iOS iPadOS mac | High | No override → label from `GuitarMode.classify` |
| D8 | `setModeOverride_assigned_hasManualOverride` | U | iOS iPadOS mac | High | `.assigned` override is recognised as manual |
| D9 | `clearOverride_revertsToAutoLabel` | U | iOS iPadOS mac | High | Setting `.auto` reverts to auto-classification |
| D10 | `cycleAnnotationVisibility_traversesAllModes` | U | iOS iPadOS mac | High | `.cycle()` visits all → selected → none → all in order |
| D11 | Annotation draggable on screen | M | iOS iPadOS mac | High | Perform a measurement; drag a peak label; verify it moves and stays at new position |
| D12 | Annotation position persists after zoom/pan | M | iOS iPadOS mac | Medium | Drag a label; zoom the chart; verify label remains at its new relative position |
| D13 | Annotation reset to default position | M | iOS iPadOS mac | Medium | Drag a label; double-tap it (iOS/iPadOS) or right-click and choose Reset Position (macOS); verify it snaps back to its default position |
| D14 | Annotations hidden in `.none` visibility mode | M | iOS iPadOS mac | Medium | Tap Annotations button to cycle to None; verify all labels disappear |
| D15 | `.selected` mode shows only Results-panel-selected labels | M | iOS iPadOS mac | Low | Ensure not all peaks are selected in Results panel; cycle Annotations to Selected; verify only selected-peak labels are visible |
| PS1 | `selectLongitudinalPeak_selectsNewPeak` | U | iOS iPadOS mac | High | `selectLongitudinalPeak(_:)` sets `userSelectedLongitudinalPeakID` to the given UUID |
| PS2 | `selectLongitudinalPeak_deselectsCurrentPeak` | U | iOS iPadOS mac | High | Calling `selectLongitudinalPeak(_:)` with the already-selected ID clears the selection |
| PS3 | `selectLongitudinalPeak_clearsCrossConflict` | U | iOS iPadOS mac | High | Selecting a peak as longitudinal when it is already the cross peak clears `userSelectedCrossPeakID` |
| PS4 | `selectLongitudinalPeak_clearsFlcConflict` | U | iOS iPadOS mac | High | Selecting a peak as longitudinal when it is already the Flc peak clears `userSelectedFlcPeakID` |
| PS5 | `selectCrossPeak_clearsLongitudinalConflict` | U | iOS iPadOS mac | High | Selecting a peak as cross when it is already the longitudinal peak clears `userSelectedLongitudinalPeakID` |
| PS6 | `selectFlcPeak_clearsCrossConflict` | U | iOS iPadOS mac | High | Selecting a peak as Flc when it is already the cross peak clears `userSelectedCrossPeakID` |

---

#### G — Guitar Mode Classification

| ID | Name | Type | Platforms | Priority | Description |
|---|---|---|---|---|---|
| G1–G6 | `acoustic_*Range_classifiesAs*` | U | iOS iPadOS mac | High | Each frequency range classifies correctly for `.acoustic` guitar |
| G7 | `acoustic_betweenRanges_classifiesAsUnknown` | U | iOS iPadOS mac | Medium | Gap frequency → `.unknown` |
| G8–G9 | `classical_*`, `flamenco_*` | U | iOS iPadOS mac | Medium | Air range correct for other guitar types |
| G10 | `helmholtz_normalizesToAir` | U | iOS iPadOS mac | Low | Legacy `.helmholtz` normalises to `.air` |
| G11 | `displayName_nonEmpty` | U | iOS iPadOS mac | Low | `displayName` returns non-empty string for every case |
| G12 | `modeRange_classicalAir_matchesModeRanges`, `modeRange_acousticTop_matchesModeRanges` | U | iOS iPadOS mac | Medium | `modeRange(for:)` returns the same range as `modeRanges.<mode>` for each guitar type |
| G13 | `annotationVisibilityCycle_allToSelectedToNoneToAll` | U | iOS iPadOS mac | Medium | Cycle visits all three states in order |
| G14 | `classical_twoOverlapPeaks_getDistinctTopAndBackLabels` | U | iOS iPadOS mac | High | Two peaks in the classical Top/Back overlap zone (190–230 Hz) are assigned different labels; the stronger-magnitude peak claims Top, the weaker gets Back |
| G15 | `classical_overlapZone_weakerPeakIsBack_evenIfInsideTopRange` | U | iOS iPadOS mac | High | The weaker overlap-zone peak receives Back even though its frequency also falls inside the Top range — claiming prevents double-assignment |
| G16 | `classical_singleOverlapPeak_isTop` | U | iOS iPadOS mac | Medium | A single peak in the overlap zone defaults to Top (first mode claimed), not Back |
| G17 | `classifyAll_unknownPeak_fallsBackToClassify` | U | iOS iPadOS mac | Medium | A peak outside all mode ranges is labelled `.unknown` via the per-frequency fallback |
| G18 | `classifyAll_nonOverlappingPeaks_classifyCorrectly` | U | iOS iPadOS mac | Medium | For peaks in non-overlapping ranges, `classifyAll` assigns the expected mode label to each peak |
| G19 | `classifyAll_emptyInput_returnsEmptyMap` | U | iOS iPadOS mac | Low | Empty peak list returns an empty map without crashing |
| G20 | `classifyAll_secondPeakInSameRange_stillClassifiedCorrectly` | U | iOS iPadOS mac | Medium | When two peaks share a non-overlapping range, the weaker (unclaimed) one falls to step 3 of the algorithm where the private `classify()` path is exercised — it still resolves to the correct mode, not `.unknown` |

---

#### P — Pitch

| ID | Name | Type | Platforms | Priority | Description |
|---|---|---|---|---|---|
| P1 | `a4_exactFrequency_returnsA4` | U | iOS iPadOS mac | High | 440 Hz → A4, 0 cents |
| P2 | `middleC_returnsC4` | U | iOS iPadOS mac | High | 261.63 Hz → C4 |
| P3–P4 | `a5_returnsA5`, `a3_returnsA3` | U | iOS iPadOS mac | Medium | Octave boundary cases |
| P5 | `halfSemitoneOffset_isAbout50Cents` | U | iOS iPadOS mac | Medium | Frequency halfway between semitones → ≈50 cents |
| P6 | `freq0_a4_returns440` | U | iOS iPadOS mac | Medium | `frequency(for:referencePitch:)` round-trip |
| P7 | `exactPitch_isInTune` / `tenCentsSharp_isInTune` / `elevenCentsSharp_isNotInTune` | U | iOS iPadOS mac | High | `isInTune` sharp threshold (≤10 cents sharp → in tune; >10 cents sharp → out of tune) |
| P7b | `eightCentsFlat_isInTune` / `fifteenCentsFlat_isNotInTune` | U | iOS iPadOS mac | High | `isInTune` flat threshold — symmetric: ≤10 cents flat → in tune; >10 cents flat → out of tune |
| P8 | `a4Tuning432_shiftsNoteNames` | U | iOS iPadOS mac | Low | Non-standard reference pitch shifts note assignments |

---

#### M — Material Properties

| ID | Name | Type | Platforms | Priority | Description |
|---|---|---|---|---|---|
| M1 | `volume_correctForTypicalPlate` | U | iOS iPadOS mac | High | Volume = L×W×T in m³ |
| M2 | `density_sprucePlate_inExpectedRange` | U | iOS iPadOS mac | High | ρ in 300–600 kg/m³ for spruce |
| M3 | `densityGPerCm3_correctConversion` | U | iOS iPadOS mac | Medium | kg/m³ → g/cm³ conversion |
| M4 | `zeroThickness_densityIsZero` | U | iOS iPadOS mac | Medium | Guard against divide-by-zero |
| M5 | `youngsModulusLong_sprucePlate_physicallyPlausible` | U | iOS iPadOS mac | High | EL in 5–20 GPa for fL=85 Hz |
| M6 | `youngsModulusLong_zeroThickness_returnsZero` | U | iOS iPadOS mac | Medium | Guard against divide-by-zero |
| M7 | `youngsModulusLong_higherFrequency_higherModulus` | U | iOS iPadOS mac | Medium | E ∝ f² |
| M8 | `youngsModulusLong_doubleLength_sixteenXModulus` | U | iOS iPadOS mac | Medium | E ∝ L⁴ at constant density |
| M9 | `speedOfSoundLong_spruce_inExpectedRange` | U | iOS iPadOS mac | High | c in 3000–8000 m/s |
| M10 | `speedOfSoundLong_proportionalToFrequency` | U | iOS iPadOS mac | Medium | c ∝ f |
| M11 | `specificModulusLong_matchesManualCalc` | U | iOS iPadOS mac | Medium | E/ρ matches manual calculation |
| M12 | `goreThickness_spruceTop_isPlausible` | U | iOS iPadOS mac | High | Gore thickness in 1.5–6 mm |
| M13 | `goreThickness_zeroBodyLength_returnsNil` | U | iOS iPadOS mac | Medium | Nil for degenerate input |
| M14 | `goreThickness_higherTarget_thickerPlate` | U | iOS iPadOS mac | Medium | Monotonically increasing with vibrational stiffness target |
| M15 | `youngsModulusLong_gpaPropertyIsCorrect` | U | iOS iPadOS mac | Medium | `youngsModulusLongGPa` computed property equals `youngsModulusLong / 1e9` for `PlateProperties` |
| M16 | `youngsModulusCross_gpaPropertyIsCorrect` | U | iOS iPadOS mac | Medium | `youngsModulusCrossGPa` computed property equals `youngsModulusCross / 1e9` for `PlateProperties` |
| M17 | `speedOfSoundLong_equalsSquareRootOfEOverRho` | U | iOS iPadOS mac | Medium | `speedOfSoundLong` equals √(youngsModulusLong / density) for `PlateProperties` |
| M18 | `spruceQualityLong_excellent_forHighSpecificModulus` | U | iOS iPadOS mac | High | High specific modulus (EL/ρ ≥ excellent threshold) → `spruceQualityLong` returns `.excellent` |
| M19 | `spruceQualityLong_returnsWoodQualityValue` | U | iOS iPadOS mac | Medium | `spruceQualityLong` returns a valid `WoodQuality` enum case for typical spruce properties |
| M20 | `overallQuality_usesWeightedNumericScore` | U | iOS iPadOS mac | Medium | `overallQuality` combines component quality scores using the weighted formula and returns the expected composite quality |
| M21 | `braceYoungsModulusLong_gpaPropertyIsCorrect` | U | iOS iPadOS mac | Medium | `youngsModulusLongGPa` computed property equals `youngsModulusLong / 1e9` for `BraceProperties` |
| M22 | `braceSpeedOfSoundLong_equalsSquareRootOfEOverRho` | U | iOS iPadOS mac | Medium | `speedOfSoundLong` equals √(youngsModulusLong / density) for `BraceProperties` |

---

#### PR — Frozen Peak Recalculation

| ID | Name | Type | Platforms | Priority | Description |
|---|---|---|---|---|---|
| PR1 | `isLoadingMeasurement_suppressesRecalculation` | U | iOS iPadOS mac | High | While `isLoadingMeasurement` is `true`, calling `recalculateFrozenPeaksIfNeeded()` returns immediately without modifying `currentPeaks` |
| PR1b | `afterLoadingCompletes_recalculationRuns` | U | iOS iPadOS mac | High | After `isLoadingMeasurement` returns to `false`, recalculation proceeds and peaks above threshold survive |
| PR2a | `loadedPeaks_aboveThreshold_areKept` | U | iOS iPadOS mac | High | Peaks in `loadedMeasurementPeaks` at or above `peakThreshold` appear in `currentPeaks`; peaks below are excluded |
| PR2b | `loadedPeaks_allBelowThreshold_clearsBothCollections` | U | iOS iPadOS mac | High | When all saved peaks fall below threshold, both `currentPeaks` and `identifiedModes` are cleared |
| PR2c | `loadedPath_usesSavedPeaks_notFrozenSpectrum` | U | iOS iPadOS mac | High | When `loadedMeasurementPeaks` is set, the saved peaks are used directly rather than re-running `findPeaks()` on the frozen spectrum |
| PR3a | `loadedPath_annotationOffset_remappedByFrequency` | U | iOS iPadOS mac | Medium | Annotation offsets stored for saved-peak UUIDs are transferred to the matching peaks in `currentPeaks` by frequency proximity (±5 Hz) |
| PR3b | `loadedPath_offsetForFilteredOutPeak_isDropped` | U | iOS iPadOS mac | Medium | Annotation offsets for peaks that drop below the threshold are removed from `peakAnnotationOffsets` |
| PR4 | `loadedPath_modeOverride_remappedByFrequency` | U | iOS iPadOS mac | Medium | User-assigned mode overrides are remapped to the surviving peaks by frequency proximity |
| PR4b | `loadedPath_overrideForFilteredOutPeak_isDropped` | U | iOS iPadOS mac | Medium | Mode overrides for peaks that drop below the threshold are removed from `peakModeOverrides` |
| PR5a | `loadedPath_manualSelection_carriedForwardByFrequency` | U | iOS iPadOS mac | High | When `userHasModifiedPeakSelection` is `true`, previously-selected frequencies are re-selected in the new peak set by proximity; unselected peaks remain unselected |
| PR5b | `loadedPath_autoSelection_reRunsWhenNotModified` | U | iOS iPadOS mac | High | When `userHasModifiedPeakSelection` is `false`, auto-selection is re-run from scratch via `guitarModeSelectedPeakIDs(from:)` |
| PR6 | `liveTapPath_emptyPeaks_preservesSelectedPeakIDs` | U | iOS iPadOS mac | High | On the live-tap path, when all peaks fall below threshold `currentPeaks` and `identifiedModes` are cleared but `selectedPeakIDs` is preserved so selections can be remapped when the threshold is lowered again |
| PR7 | `liveTapPath_annotationOffset_remappedByFrequency` | U | iOS iPadOS mac | Medium | On the live-tap path, annotation offsets are remapped to the new UUIDs produced by a fresh `findPeaks()` pass using frequency proximity |

---

#### R — Persistence / Codable

| ID | Name | Type | Platforms | Priority | Description |
|---|---|---|---|---|---|
| R1 | `resonantPeak_roundTrip_preservesAllFields` | U | iOS iPadOS mac | High | All `ResonantPeak` fields survive JSON encode/decode |
| R2 | `resonantPeak_nilPitchFields_roundTrip` | U | iOS iPadOS mac | High | Nil optional fields round-trip as absent JSON keys |
| R3 | `fullMeasurement_roundTrip_preservesAllFields` | U | iOS iPadOS mac | High | Full `TapToneMeasurement` JSON round-trip |
| R4 | `chartImageData_isNotEncoded` | U | iOS iPadOS mac | High | Transient image data excluded from JSON |
| R5 | `annotationOffsets_roundTrip_preserved` | U | iOS iPadOS mac | Medium | `annotationOffsets` dictionary survives round-trip |
| R6 | `realFixture_decodesWithoutError` | U | iOS iPadOS mac | High | Real fixture file decodes without error |
| R7 | Save measurement persists across relaunch | M | iOS iPadOS mac | High | Save a measurement; force-quit and relaunch; verify it appears in the list |
| R8 | Export Measurement round-trip — export and re-import matches original | M | iOS iPadOS mac | High | Save a measurement; export as .guitartap file; import the file; open both in the detail view and verify all fields match |
| R9 | Export PDF — file renders correctly | M | iOS iPadOS mac | Medium | Export PDF; open in Preview/Files; verify spectrum image, peaks table, and metadata are present |
| R10 | Cross-device transfer via export/import | M | iOS iPadOS mac | Low | Export measurement as .guitartap file on one device; import on a second device; verify measurement appears |
| R11 | `tapToneRatio_overlapZonePeaks_computesCorrectRatio` | U | iOS iPadOS mac | High | Classical guitar with Air at 95 Hz and Top at 210 Hz (overlap zone) — `tapToneRatio` finds both peaks via `classifyAll` and returns 210/95 |
| R12 | `tapToneRatio_twoOverlapPeaks_usesSingleTopPeak` | U | iOS iPadOS mac | High | When two peaks are in the overlap zone, the ratio uses the stronger (Top-claiming) peak, not the weaker (Back-claiming) one |
| R13 | `exportedJSON_overlapZonePeaks_haveDistinctModeLabels` | U | iOS iPadOS mac | High | Two overlap-zone peaks in an exported JSON measurement have different `modeLabel` values ("Top" and "Back"), not both "Top" |
| R14 | `exportedJSON_userOverrideTakesPriority` | U | iOS iPadOS mac | High | A user-assigned mode label overrides the `classifyAll` result in the exported JSON `modeLabel` field |
| R15 | `emptyAnnotationOffsets_roundTrip` | U | iOS iPadOS mac | Medium | `TapToneMeasurement` with no annotation offsets round-trips without error and offsets remain empty |
| R16 | `annotationOffsets_multiPeak_allPreserved` | U | iOS iPadOS mac | Medium | `annotationOffsets` dictionary with multiple UUID keys survives JSON round-trip with all entries intact (D1 multi-peak scenario) |
| R17 | `peakSelection_selectedPeakIDs_roundTrip` | U | iOS iPadOS mac | High | `selectedPeakIDs` set survives JSON encode/decode (D3 scenario) |
| R17b | `peakSelection_selectedPeakIDs_nilWhenEmpty` | U | iOS iPadOS mac | Medium | `selectedPeakIDs` encodes as absent key when empty; decodes back to empty set (D3b scenario) |
| R17c | `peakSelection_nil_decodesAsAll` | U | iOS iPadOS mac | Medium | Missing `selectedPeakIDs` key in JSON decodes as the full set of peak UUIDs (nil → all selected) |
| R18 | `annotationVisibilityMode_all_roundTrip` | U | iOS iPadOS mac | High | `.all` visibility mode survives JSON encode/decode (D4 scenario) |
| R18b | `annotationVisibilityMode_selected_roundTrip` | U | iOS iPadOS mac | Medium | `.selected` visibility mode survives JSON encode/decode (D5 scenario) |
| R18c | `annotationVisibilityMode_none_roundTrip` | U | iOS iPadOS mac | Medium | `.none` visibility mode survives JSON encode/decode (D6 scenario) |
| R18d | `annotationVisibilityMode_missingKey_defaultsToAll` | U | iOS iPadOS mac | Medium | Missing `annotationVisibilityMode` key in JSON decodes as `.all` (CI5 compatibility scenario) |
| R19 | `modeOverrides_assigned_roundTrip` | U | iOS iPadOS mac | High | `peakModeOverrides` with `.assigned` entries survives JSON encode/decode (D7 scenario) |
| R19b | `modeOverrides_auto_roundTrip` | U | iOS iPadOS mac | Medium | `peakModeOverrides` with `.auto` entries survives JSON encode/decode (D8 scenario) |
| R19c | `modeOverrides_empty_roundTrip` | U | iOS iPadOS mac | Medium | Empty `peakModeOverrides` dictionary round-trips without error |
| R19d | `modeOverrides_missingKey_decodesAsEmpty` | U | iOS iPadOS mac | Medium | Missing `peakModeOverrides` key decodes as empty dictionary (auto-type compatibility) |
| R20 | `peakSelectionTracking_longitudinal_roundTrip` | U | iOS iPadOS mac | High | `userSelectedLongitudinalPeakID` UUID survives JSON encode/decode (PS1 scenario) |
| R20b | `peakSelectionTracking_cross_roundTrip` | U | iOS iPadOS mac | High | `userSelectedCrossPeakID` UUID survives JSON encode/decode (PS2 scenario) |
| R20c | `peakSelectionTracking_flc_roundTrip` | U | iOS iPadOS mac | High | `userSelectedFlcPeakID` UUID survives JSON encode/decode (PS3 scenario) |
| R20d | `peakSelectionTracking_nil_roundTrip` | U | iOS iPadOS mac | Medium | Nil selection fields round-trip as absent JSON keys |
| R20e | `peakSelectionTracking_userModified_roundTrip` | U | iOS iPadOS mac | Medium | `userHasModifiedPeakSelection` bool survives JSON encode/decode |
| R20f | `peakSelectionTracking_missingKey_defaultsFalse` | U | iOS iPadOS mac | Medium | Missing `userHasModifiedPeakSelection` key decodes as `false` |
| R21 | `spectrumSnapshot_newMeasurement_isNil` | U | iOS iPadOS mac | High | A freshly created `TapToneMeasurement` has no `spectrumSnapshot` (field is nil/absent) |
| R21b | `spectrumSnapshot_withSnapshot_stored` | U | iOS iPadOS mac | High | A `spectrumSnapshot` assigned to a measurement survives JSON encode/decode intact |

---

#### DK — Decay Tracking

| ID | Name | Type | Platforms | Priority | Description |
|---|---|---|---|---|---|
| DK1 | `measureDecayTime_emptyHistory_returnsNil` | U | iOS iPadOS mac | High | Empty `peakMagnitudeHistory` → `measureDecayTime` returns `nil` |
| DK2 | `measureDecayTime_allSamplesBeforeTap_returnsNil` | U | iOS iPadOS mac | High | All history samples pre-date `tapTime` → post-tap slice is empty → `nil` |
| DK3 | `measureDecayTime_signalNeverDecays_returnsNil` | U | iOS iPadOS mac | High | Signal peak minus max drop < `decayThreshold` → threshold never crossed → `nil` |
| DK4 | `measureDecayTime_normalDecay_returnsPositiveTime` | U | iOS iPadOS mac | High | Signal drops past threshold → returns elapsed time ≈ expected interval |
| DK5 | `measureDecayTime_immediateDecay_returnsShortPositiveTime` | U | iOS iPadOS mac | Medium | Threshold crossed immediately after peak → returns short but positive time |
| DK6 | `trackDecayFast_notTracking_isNoOp` | U | iOS iPadOS mac | High | When `isTrackingDecay == false`, calling `trackDecayFast` does not modify `peakMagnitudeHistory` |
| DK7 | `trackDecayFast_tracking_noTapTime_accumulates` | U | iOS iPadOS mac | Medium | When `isTrackingDecay == true` but `lastTapTime` is nil, samples accumulate and `currentDecayTime` stays nil |

---

#### IP — Import Persistence

| ID | Name | Type | Platforms | Priority | Description |
|---|---|---|---|---|---|
| IP1 | `importMeasurementsJSON_persistsToDisk` | U | iOS iPadOS mac | High | `importMeasurements(json:)` writes `saved_measurements.json` to disk after a successful import |
| IP2 | `importMeasurementsData_persistsToDisk` | U | iOS iPadOS mac | High | `importMeasurements(from:)` writes `saved_measurements.json` to disk after a successful import |
| IP3 | `importMeasurementsJSON_appendsToExisting` | U | iOS iPadOS mac | Medium | Two successive calls to `importMeasurements(json:)` append to `savedMeasurements`, not replace |

---

#### MC — isMeasurementComplete Transitions

> These tests are the automated guard against the class of regression where a capture-completion
> path sets frozen spectrum data but fails to set `isMeasurementComplete = true` — causing the
> spectrum to keep painting live FFT frames instead of freezing.  See audit guidelines Rule 8.
>
> Swift tests live in `MeasurementCompleteTransitionTests.swift` (MC1–MC8).
> Python mirrors live in `test_measurement_complete_transitions.py` (paths 1–6, 13 tests).

| ID | Name | Type | Platforms | Priority | Description |
|---|---|---|---|---|---|
| MC1 | `processMultipleTaps_setsIsMeasurementComplete` | U | iOS iPadOS mac | High | After `processMultipleTaps()` with at least one tap, `isMeasurementComplete` must be `true` |
| MC2 | `processMultipleTaps_populatesFrozenSpectrum` | U | iOS iPadOS mac | High | After `processMultipleTaps()`, both `frozenMagnitudes` and `frozenFrequencies` are non-empty |
| MC3 | `processMultipleTaps_multiTap_setsIsMeasurementComplete` | U | iOS iPadOS mac | High | Two-tap average path still sets `isMeasurementComplete = true` |
| MC4 | `startTapSequence_clearsMeasurementComplete` | U | iOS iPadOS mac | High | `startTapSequence()` sets `isMeasurementComplete = false`; signal emitted |
| MC5 | `cancelTapSequence_clearsFrozenSpectrum` | U | iOS iPadOS mac | High | `cancelTapSequence()` clears `frozenMagnitudes` and `frozenFrequencies` to empty arrays (flag stays `true` until next `startTapSequence`) |
| MC6 | `processMultipleTaps_emptyTaps_doesNotComplete` | U | iOS iPadOS mac | High | Guard: `processMultipleTaps()` with empty `capturedTaps` must not set `isMeasurementComplete = true` |
| MC7 | `loadMeasurement_setsIsMeasurementComplete` | U | iOS iPadOS mac | High | `loadMeasurement(_:)` sets `isMeasurementComplete = true` |
| MC8 | `isMeasurementComplete_didSet_clearsSettingsWarning` | U | iOS iPadOS mac | Medium | When `isMeasurementComplete` becomes `true`, `showLoadedSettingsWarning` is cleared |

---

#### U — Cross-Platform UI

| ID | Name | Type | Platforms | Priority | Description |
|---|---|---|---|---|---|
| U1 | All primary controls present on iPhone (compact) | M | iOS | High | Portrait: Results (nav bar left), Metrics/Settings (nav bar right), Auto dB/Crosshair/Annotations/Save/Measurements (header button bar). Landscape: Results/Auto dB/Crosshair (nav bar left), Annotations/Save/Measurements/Metrics/Settings (nav bar right) |
| U2 | All primary controls present on iPad | M | iPadOS | High | On iPad: full-label two-row layout visible without scrolling |
| U3 | All primary controls present on macOS | M | mac | High | On macOS at 800 px wide: all buttons visible in one or two rows |
| U4 | macOS window narrows to icon-only layout | M | mac | Medium | Narrow the window to <600 px; verify `ViewThatFits` switches to icon-only layout without truncation |
| U5 | Status bar correct on iPhone | M | iOS | Medium | Compact status bar (28 px tall) shows tap indicator, dB reading, and running dot |
| U6 | Status bar correct on iPad/macOS | M | iPadOS mac | Medium | Full status bar shows progress bar, "Tap Detected!" label, bin count, and frozen indicator |
| U7 | Settings sheet opens and closes | M | iOS iPadOS mac | High | Tap Settings; change a value; dismiss; verify value is persisted |
| U8 | Results sheet opens and closes | M | iOS iPadOS mac | High | After a measurement, tap Results; verify peaks table appears; dismiss |
| U9 | Save sheet accepts name and saves | M | iOS iPadOS mac | High | Tap Save; type a name; confirm; verify measurement appears in list |
| U10 | Measurements list shows saved items | M | iOS iPadOS mac | High | Open Measurements; verify previously saved items are listed with name and date |
| U11 | Dark mode — no clipped or invisible text | M | iOS iPadOS mac | Medium | Switch to dark mode; verify all text and chart elements remain legible |
| U12 | Dynamic Type — large text accessible | M | iOS iPadOS | Low | Set Accessibility text size to XXL; verify buttons do not clip their labels |

---

#### K — Regression Smoke Tests

| ID | Name | Type | Platforms | Priority | Description |
|---|---|---|---|---|---|
| K1 | App launches without crash | M | iOS iPadOS mac | High | Cold launch; verify main view appears within 3 s with no crash |
| K2 | Chart renders with a saved measurement | M | iOS iPadOS mac | High | Load the `contreras-classical-1774731564.guitartap` fixture via Files/import; verify spectrum chart appears with peak annotations |
| K3 | Recording starts automatically on launch | M | iOS iPadOS mac | High | Launch app; verify `isRunning` indicator goes green within 3 s with no freeze |
| K4 | Memory stable during extended recording | M | iOS iPadOS mac | Medium | Record continuously for 2 min; verify in Xcode Instruments that memory usage is stable (no runaway growth) |
| K5 | App returns from background correctly | M | iOS iPadOS | High | Start recording; press Home; return to app; verify recording resumes or is in a consistent stopped state |
| K6 | Rotation does not break layout | M | iOS iPadOS | Medium | While recording, rotate device; verify chart and controls reflow without truncation or overlap |

---

### 1.3 Test IDs summary

| Prefix | Area | Test types |
|---|---|---|
| F | FFT / DSP / peak finding | U + M |
| T | Tap detection | U + M |
| A | Averaging | U + M |
| S | Audio stack | M |
| C | Chart interaction state | U + M |
| D | Draggable annotations / display state | U + M |
| PS | Plate peak selection (mutual-exclusion) | U |
| G | Guitar mode classification | U |
| P | Pitch | U |
| M | Material properties | U |
| PR | Frozen peak recalculation | U |
| R | Persistence / codable | U + M |
| DK | Decay tracking | U |
| IP | Import persistence | U |
| MC | isMeasurementComplete transitions (Rule 8 critical-flag guard) | U |
| U | Cross-platform UI | M |
| K | Regression smoke tests | M |

---

## Part 2 — Automated Test Implementation Plan

> All test IDs in this part refer to the catalogue in **Part 1, section 1.2**. Every automated test covers the U-type entries in that catalogue; M-type entries are out of scope for automation and are covered in **Part 3**.

### 2.1 Framework and conventions

- **Framework:** Swift Testing (`import Testing`). All test files use `@Suite` / `@Test` / `#expect`.
- **Test target:** `GuitarTapTests` (existing target, `PBXFileSystemSynchronizedRootGroup` — all
  `.swift` files in `GuitarTapTests/` are compiled automatically).
- **Parallelism:** The scheme sets `parallelizable = "NO"` to prevent separate test processes
  competing over `UserDefaults.standard` (used by `TapDisplaySettings`). Suites that mutate
  `TapDisplaySettings` are additionally marked `@Suite(.serialized)` and use `defer` to restore
  state.
- **`@MainActor` isolation:** Types that dispatch to the main thread (`TapToneMeasurement`,
  `ResonantPeak`, and the annotation/override management methods) require the test struct to be
  annotated `@MainActor` so calls are synchronous.

### 2.2 Refactoring / extraction needed to make code testable

| Component | Current state | What is needed |
|---|---|---|
| `SpectrumView` gesture state | `@State` vars (`minFreq`, `maxFreq`, `minDB`, `maxDB`) live directly in the view | Extract into a `SpectrumViewModel` (or plain struct) so `applyFrequencyZoom`, `applyMagnitudeZoom`, and `handlePan` can be called without SwiftUI |
| `RealtimeFFTAnalyzer` audio I/O | Concrete class with `AVAudioEngine` in `init` | Define `AudioAnalyzing` protocol; inject via init so tests can substitute a `MockAudioAnalyzer` |
| `AVAudioSession` (iOS) | Called directly in `TapToneAnalysisView+Actions.swift` | Wrap in a `AudioSessionConfiguring` protocol; inject so tests can verify configuration calls without real hardware |
| `TapDisplaySettings` | Global `UserDefaults.standard` singleton | Already mitigated with `.serialized` suites and `defer` restore; no structural change required |

### 2.3 Test infrastructure needed

| Infrastructure | Purpose | Notes |
|---|---|---|
| `MockAudioAnalyzer` | Stub for `AudioAnalyzing`; returns synthetic `magnitudes` and `frequencies` | Needed for chart state unit tests (C1–C8) once `SpectrumViewModel` is extracted |
| Synthetic PCM buffer factory | Generates `AVAudioPCMBuffer` with a known sine tone | Needed only if audio-pipeline integration tests are added in future; not required for current scope |
| Snapshot testing | Chart rendering regression | `swift-snapshot-testing` not present in the project; use `XCTAttachment` screenshots in manual test K2 instead |

### 2.4 Implemented test files

| File | Suites | IDs covered | Status |
|---|---|---|---|
| `TapDetectionTests.swift` | `TapDetection` (.serialized) | T1–T8 | ✅ Implemented |
| `DSPTests.swift` | `ParabolicInterpolation`, `QFactorCalculation` | F1–F4, F4b, F5–F9 | ✅ Implemented |
| `PeakFindingTests.swift` | `FindPeaks`, `RemoveDuplicatePeaks`, `SpectrumAveraging` | F10–F20, A2 | ✅ Implemented |
| `GuitarModeTests.swift` | `GuitarModeClassification`, `GuitarModeClassifyAll` | G1–G20 | ✅ Implemented |
| `PitchTests.swift` | `PitchTests` | P1–P8, P7b | ✅ Implemented |
| `PlatePropertiesTests.swift` | `MaterialDimensions`, `YoungModulus`, `SpeedOfSound`, `SpecificModulus`, `GoreTargetThickness`, `PlateQuality` | M1–M20 | ✅ Implemented |
| `BracePropertiesTests.swift` | `BraceDimensions`, `BraceYoungModulus`, `BraceSpeedOfSound` | M21–M22 | ✅ Implemented |
| `MeasurementCodableTests.swift` | `ResonantPeakCodable`, `TapToneMeasurementCodable`, `FixtureLoading`, `TapToneRatio`, `MeasurementExportModeLabel` (@MainActor), `AnnotationOffsetsCodable`, `PeakSelectionOnMeasurement`, `AnnotationVisibilityModeCodable`, `ModeOverridesCodable`, `PeakSelectionTrackingCodable`, `SpectrumSnapshotOnMeasurement` | R1–R6, R11–R21b | ✅ Implemented |
| `AnnotationStateTests.swift` | `AnnotationOffsets` (@MainActor), `PeakSelection`, `VisiblePeaks`, `ModeOverrides` (@MainActor, .serialized), `AnnotationVisibilityCycle`, `PlatePeakSelection` (@MainActor) | D1–D10, PS1–PS6 | ✅ Implemented |
| `SpectrumViewGestureTests.swift` | `FrequencyZoomTests`, `MagnitudeZoomTests`, `PanTests` | C1–C8 | ✅ Implemented (`TestHarness` pattern; no `SpectrumViewModel` extraction required) |
| `FrozenPeakRecalculationTests.swift` | `FrozenPeakRecalculation_LoadingGuardTests`, `FrozenPeakRecalculation_LoadedMeasurementPathTests`, `FrozenPeakRecalculation_OffsetRemappingTests`, `FrozenPeakRecalculation_OverrideRemappingTests`, `FrozenPeakRecalculation_SelectionCarryForwardTests`, `FrozenPeakRecalculation_EmptyPeaksGuardTests`, `FrozenPeakRecalculation_LiveTapPathTests` | PR1–PR7 | ✅ Implemented |
| `DecayTrackingTests.swift` | `DecayTracking` (@MainActor) | DK1–DK7 | ✅ Implemented |
| `ImportPersistenceTests.swift` | `ImportPersistence` (@MainActor, .serialized) | IP1–IP3 | ✅ Implemented |
| `MeasurementCompleteTransitionTests.swift` | `MeasurementCompleteTransitions` (@MainActor, .serialized) | MC1–MC8 | ✅ Implemented |
| `test_measurement_complete_transitions.py` *(Python)* | `TestGuitarSingleTapCompletion`, `TestGuitarMultiTapCompletion`, `TestStartTapSequenceResetsComplete`, `TestCancelTapSequenceResetsComplete`, `TestSetMeasurementCompleteDirectly`, `TestLoadMeasurementSetsComplete` | MC1–MC8 mirrors (13 tests) | ✅ Implemented |

### 2.5 Prioritised backlog

1. **Done — foundational unit tests** (DSP, tap detection, averaging, peak finding, material math, pitch, codable, annotation state)
2. **Done — chart state unit tests** (C1–C8): Used `TestHarness` pattern to test `applyFrequencyZoom` / `applyMagnitudeZoom` / `handlePan` directly via `Binding(get:set:)` closures; `SpectrumViewGestureTests.swift`
3. **Later — audio-stack integration tests** (S series): Requires `AudioAnalyzing` protocol and `MockAudioAnalyzer`; lower ROI than manual testing for this app
4. **Last — UI smoke tests**: Add `.accessibilityIdentifier()` to key controls; write a `GuitarTapUITests` target using `XCUIApplication`

### 2.6 Tests requiring a physical device (not simulator)

| ID | Reason |
|---|---|
| S1–S6, T9–T12 | Real microphone required |
| S7–S8 | macOS external USB audio device |
| K4 | Instruments profiling meaningless on simulator |
| R10 | iCloud sync requires two signed-in devices |

### 2.7 Known constraints and workarounds

**`RealtimeFFTAnalyzer` dealloc crash.** Fixed by capturing `[weak self]` in the two async
closures in `stop()` (`bufferAccessQueue.async` and `DispatchQueue.main.async`). The full test
suite now runs in ~5 s.

**`TapDisplaySettings` shared state.** `TapDisplaySettings` is backed by `UserDefaults.standard`.
Mitigations:
- Scheme: `parallelizable = "NO"` (no parallel processes).
- Suites that write `measurementType`: `@Suite(.serialized)` + `defer` restore.

**`@MainActor` dispatch.** Several model methods dispatch to the main thread asynchronously when
called off-main. Test structs that call these methods are annotated `@MainActor` so the dispatch
is synchronous. Methods using `DispatchQueue.main.async` (e.g. `reset()`) additionally require
`await Task.yield()` in the test body to drain the queue before asserting.

**Bin resolution constraint.** At 48 kHz / 2048 bins, bin width ≈ 11.7 Hz. Test spectra for
peak-finding and DSP tests must place peaks in mode ranges with enough bins (≥10) to be reliably
detected. Helmholtz (95–110 Hz, ~1 bin) is avoided; upperModes (900–2000 Hz, ~94 bins) is
preferred.

---

## Part 3 — Manual Test Procedures

> All test IDs in this part refer to the M-type entries in the catalogue in **Part 1, section 1.2**. Every procedure here corresponds to exactly one row in that catalogue. The ID in each heading is the canonical identifier from Part 1. Procedures are ordered by area, then by ID within the area.

Each procedure follows the format:

> **Preconditions** → **Steps** → **Expected result**

---

### FFT Pipeline

#### F21 — Live FFT renders in real time
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** F21
**Preconditions:** App running with microphone permission granted.
**Steps:**
1. Launch the app (recording begins automatically).
2. Observe the spectrum chart for several seconds.

**Expected result:** The spectrum chart updates periodically. The update rate is intentionally low (~0.7 Hz) because the large FFT window required for high frequency resolution means each analysis takes ~1.5 seconds of audio. The display should not freeze permanently or show stale data; it should update at least once per 2 seconds under normal conditions.

---

#### F22 — Silence floor is plausible
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** F22
**Preconditions:** App recording in a quiet environment with no deliberate sound.
**Steps:**
1. Launch the app in a quiet environment (recording begins automatically).
2. Observe the noise floor level in the spectrum chart.

**Expected result:** The noise floor is visible and stable near −70 to −90 dB. It does not jump or show false peaks. The chart is not blank.

---

#### F23 — Pure tone visible at correct frequency
**Platforms:** iOS · iPadOS · macOS · **Priority:** Medium · **Part 1 ref:** F23
**Preconditions:** A 220 Hz reference tone source is available (e.g. a tuning app or online tone generator). In Settings, confirm the mode is set to a Guitar tap mode (not a Material tap mode), so that 220 Hz falls within the displayed frequency range.
**Steps:**
1. Launch the app (recording begins automatically).
2. Play a 220 Hz tone near the device microphone.

**Expected result:** A clear peak appears in the spectrum chart within ±5 Hz of 220 Hz.

---

### Audio Stack

#### S1 — First launch: microphone permission prompt
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** S1
**Preconditions:** Permission must be in the "not determined" state. Toggling the microphone switch off in System Settings is **not** sufficient — that sets the status to "denied" and does not re-trigger the system prompt. To reset to "not determined":
- **iOS/iPadOS:** Delete and reinstall the app, or use **System Settings → General → Transfer or Reset iPhone → Reset → Reset Location & Privacy**.
- **macOS:** Run `tccutil reset Microphone` in Terminal (resets all apps), then relaunch GuitarTap.

**Steps:**
1. Launch GuitarTap.

**Expected result:** The OS permission dialog "GuitarTap would like to access the microphone" appears. The app does not crash and does not start recording before the user responds.

---

#### S2 — Permission denied: graceful degradation
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** S2
**Preconditions:** Microphone permission previously denied (by tapping "Don't Allow" in S1, or by toggling off in System Settings). App running.

**Note (macOS):** When the microphone slider is toggled off in System Settings, macOS prompts to restart GuitarTap and then force-relaunches it. The app checks permission status on launch, so the alert appears immediately without needing to press Start.

**Steps:**
1. Launch GuitarTap. The app attempts to start recording automatically; the alert will appear at launch.

**Expected result:** No crash. No recording starts. An alert titled "Microphone Access Required" appears with an **Open Settings** button that navigates to System Settings → Privacy & Security → Microphone.

---

#### S3 — Permission granted after denial
**Platforms:** iOS · iPadOS · macOS · **Priority:** Medium · **Part 1 ref:** S3
**Preconditions:** Microphone permission was previously denied.
**Steps:**
1. Open **System Settings → Privacy & Security → Microphone → GuitarTap** and enable it.
2. **iOS/iPadOS:** Return to GuitarTap (no relaunch needed on iOS 14+) — recording restarts automatically. **macOS:** GuitarTap is force-restarted automatically; recording begins on relaunch.

**Expected result:** Recording begins; spectrum starts animating; green running indicator appears.

---

#### S4 — Microphone-in-use indicator active
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** S4
**Preconditions:** App running on a real device.
**Steps:**
1. Launch the app (recording begins automatically).
2. **iOS/iPadOS:** Look at the status bar. **macOS:** Look at the menu bar (top-right area).

**Expected result:** An orange microphone indicator appears, confirming the system recognises that GuitarTap is actively capturing audio. On iOS/iPadOS this also confirms the `.record` AVAudioSession category is active; stopping the analyzer causes the indicator to disappear. On macOS the indicator persists until the app is quit — this is normal system behavior.

---

#### S5 — Session interrupted by incoming call
**Platforms:** iOS · **Priority:** High · **Part 1 ref:** S5
**Preconditions:** App recording on a real iPhone.
**Steps:**
1. Confirm the spectrum is animating (recording starts automatically on launch).
2. Have another phone call the device.
3. Let the call ring for 5 s (do not answer), then decline.

**Expected result:** While the call rings, recording stops cleanly (no crash, no freeze). After declining, the app is in a consistent state.

---

#### S6 — Session interrupted by another audio app
**Platforms:** iOS · iPadOS · **Priority:** Medium · **Part 1 ref:** S6
**Preconditions:** App recording on iPhone or iPad.
**Steps:**
1. Confirm the spectrum is animating (recording starts automatically on launch).
2. Swipe to the Home screen.
3. Open Music or Spotify and start playback.
4. Return to GuitarTap.

**Expected result:** GuitarTap is in a stopped state when the other app takes the audio session. The app recovers when focus returns.

**Note:** This test does not apply to macOS. On macOS, CoreAudio allows simultaneous audio access by multiple apps, so a playback app does not interrupt GuitarTap's microphone input.

---

#### S7 — Input device selection (macOS)
**Platforms:** macOS · **Priority:** High · **Part 1 ref:** S7
**Preconditions:** Two microphone sources available on the Mac (e.g. built-in + USB headset).
**Steps:**
1. Launch GuitarTap (recording begins automatically).
2. Open GuitarTap **Settings → Audio Input & Calibration → Audio Input Device** and select the alternative device.

**Expected result:** Within 2 s the spectrum updates to reflect audio from the new device. No crash.

---

#### S8 — External device plug/unplug (macOS)
**Platforms:** macOS · **Priority:** Medium · **Part 1 ref:** S8
**Preconditions:** App recording on macOS.
**Steps:**
1. Plug in a USB microphone.
2. Confirm it appears in the device list in Settings.
3. Select it; confirm recording continues.
4. Unplug the USB microphone.

**Expected result:** After unplugging, the app does not crash. The device list updates. Recording either falls back to the built-in mic or stops cleanly.

---

#### S9 — 48 kHz sample rate accepted
**Platforms:** iOS · iPadOS · macOS · **Priority:** Medium · **Part 1 ref:** S9
**Preconditions:** App recording on any platform.
**Steps:**
1. Tap **Start**.
2. Tap **Metrics** to open the metrics overlay.

**Expected result:** The **Sample Rate** field shows "48000 Hz" (or the device's actual rate). No "0 Hz", "—", or empty value.

---

#### S10 — Non-48 kHz device accepted
**Platforms:** macOS · **Priority:** Low · **Part 1 ref:** S10
**Preconditions:** A microphone is available whose sample rate can be changed in **Audio MIDI Setup** (Applications → Utilities) — the built-in microphone works.
**Steps:**
1. Open Audio MIDI Setup and set the device to 44100 Hz.
2. Launch GuitarTap and select that device in **GuitarTap Settings → Audio Input & Calibration → Audio Input Device**.
3. Tap **Start**.
4. Verify the spectrum appears and the **Sample Rate** in Metrics reads "44100 Hz".
5. While still recording, switch the device back to 48000 Hz in Audio MIDI Setup.
6. Observe GuitarTap.

**Expected result:**
- Steps 3–4: The spectrum chart appears and animates normally at 44100 Hz. The app does not crash.
- Step 6: Recording stops briefly and restarts automatically. After restart, the spectrum resumes and **Sample Rate** in Metrics reads "48000 Hz". No crash or error dialog.

---

### Tap Detection

#### T9 — Tap detected on physical knock
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** T9
**Preconditions:** App running and recording. Tap count set to 1. Acoustic measurement mode. Microphone (built-in or external) positioned close to the guitar body.
**Steps:**
1. Knock the guitar top firmly once.

**Expected result:** The tap indicator flashes green. `Tap count: 1/1` appears in the status bar. The spectrum freezes and displays the captured response.

---

#### T10 — Minimum inter-tap interval enforced
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** T10
**Preconditions:** App running and recording. Tap count set to 3.
**Steps:**
1. Knock the guitar twice in very rapid succession (less than 0.3 s apart).

**Expected result:** Only one tap is counted. The second knock within the cooldown window is silently rejected.

---

#### T11 — Background noise does not false-trigger
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** T11
**Preconditions:** App running and recording. Tap count set to 1. Place device in a quiet room.
**Steps:**
1. Leave the device recording with no intentional taps for 30 s.

**Expected result:** The status message remains "Tap the guitar..." throughout. The indicator does not flash green.

---

#### T12 — Threshold setting affects sensitivity
**Platforms:** iOS · iPadOS · macOS · **Priority:** Medium · **Part 1 ref:** T12
**Preconditions:** App running. Default threshold in Settings.
**Steps:**
1. Perform a light tap and confirm it is not detected at the default threshold.
2. Reduce the threshold using the Threshold slider until the threshold line on the chart is below the peak of the previous tap.
3. Perform the same light tap again.

**Expected result:** The lighter tap is now detected with the lower threshold. Increasing the threshold back to the original value causes light taps to be missed again.

---

### Averaging

#### A3 — Multi-tap accumulation and progress bar
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** A3
**Preconditions:** App running. Tap count set to 3.
**Steps:**
1. Knock the guitar once.
2. Wait for progress bar to show 1/3.
3. Knock again.
4. Wait for 2/3.
5. Knock a third time.

**Expected result:** Progress bar advances to 1/3 after each tap. After the third tap it reaches 3/3 and the averaged spectrum is displayed.

---

#### A4 — Averaged spectrum is more consistent than a single tap
**Platforms:** iOS · iPadOS · macOS · **Priority:** Medium · **Part 1 ref:** A4
**Preconditions:** App running. A real guitar is available.
**Steps:**
1. Set tap count to 1. Capture one tap. Note the positions of the prominent peaks.
2. Tap **Reset**.
3. Set tap count to 5. Capture five taps, deliberately varying tap position and force slightly between each.

**Expected result:** The prominent peaks in the 5-tap averaged spectrum appear at the same frequencies as in the single-tap spectrum. The purpose of averaging is to reduce variation caused by differences in tap position and force — the overall spectral shape may look similar to a single tap.

---

#### A5 — New Tap clears previous capture
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** A5
**Preconditions:** App running and recording. One or more taps have been captured (spectrum is frozen).
**Steps:**
1. Tap the **New Tap** button.

**Expected result:** The frozen spectrum clears and the status message returns to "Tap the guitar..." ready for a fresh capture sequence. If a multi-tap sequence was in progress, the progress bar also disappears.

---

### Chart Interaction

#### C9 — Pinch-to-zoom narrows frequency range (iOS/iPadOS)
**Platforms:** iOS · iPadOS · **Priority:** High · **Part 1 ref:** C9
**Preconditions:** App running with a frozen or live spectrum. iPad or iPhone.
**Steps:**
1. Place two fingers near the centre of the spectrum chart.
2. Pinch inward (bring fingers together).

**Expected result:** The frequency axis zooms in. The visible frequency range narrows (e.g. from 20–2000 Hz down to 400–1200 Hz). Axis tick labels update accordingly.

---

#### C10 — Spread-to-zoom widens frequency range (iOS/iPadOS)
**Platforms:** iOS · iPadOS · **Priority:** High · **Part 1 ref:** C10
**Preconditions:** Frequency axis is already zoomed in (range < 1000 Hz).
**Steps:**
1. Place two fingers near the centre of the chart.
2. Spread fingers apart.

**Expected result:** Frequency axis zooms out. Range widens. Cannot exceed 20–20000 Hz.

---

#### C11 — Drag pans frequency axis (iOS/iPadOS)
**Platforms:** iOS · iPadOS · **Priority:** High · **Part 1 ref:** C11
**Preconditions:** Frequency axis is zoomed in to a sub-range.
**Steps:**
1. Press and drag the chart to the left.
2. Release.
3. Drag back to the right.

**Expected result:** Frequency axis shifts left on left-drag and right on right-drag. The range span (zoom level) does not change. Position is maintained after release.

---

#### C12 — Scroll wheel pans magnitude axis (macOS)
**Platforms:** macOS · **Priority:** High · **Part 1 ref:** C12
**Preconditions:** App running on macOS with a trackpad or scroll wheel.
**Steps:**
1. Position cursor over the chart.
2. Scroll up (no modifier keys).

**Expected result:** dB axis shifts upward (higher dB values come into view). No frequency axis change.

---

#### C13 — Shift+scroll pans frequency axis (macOS)
**Platforms:** macOS · **Priority:** High · **Part 1 ref:** C13
**Preconditions:** App running on macOS.
**Steps:**
1. Hold **Shift** and scroll left/right.

**Expected result:** Frequency axis pans left or right. No dB axis change.

---

#### C14 — Cmd+scroll zooms both axes (macOS)
**Platforms:** macOS · **Priority:** High · **Part 1 ref:** C14
**Preconditions:** App running on macOS. Cursor positioned over a peak.
**Steps:**
1. Hold **Cmd** and scroll up (zoom in).

**Expected result:** Both frequency and dB axes zoom in simultaneously. The point under the cursor stays approximately fixed.

---

#### C15 — Option+scroll zooms frequency only (macOS)
**Platforms:** macOS · **Priority:** Medium · **Part 1 ref:** C15
**Preconditions:** App running on macOS.
**Steps:**
1. Hold **Option** and scroll up.

**Expected result:** Frequency axis zooms in. dB axis does not change.

---

#### C16 — Ctrl+scroll zooms magnitude only (macOS)
**Platforms:** macOS · **Priority:** Medium · **Part 1 ref:** C16
**Preconditions:** App running on macOS.
**Steps:**
1. Hold **Ctrl** and scroll up.

**Expected result:** dB axis zooms in. Frequency axis does not change.

---

#### C17 — Zoom anchors to cursor position (macOS)
**Platforms:** macOS · **Priority:** Medium · **Part 1 ref:** C17
**Preconditions:** App with a visible peak at a known frequency (e.g. 200 Hz).
**Steps:**
1. Position the cursor exactly over the 200 Hz peak.
2. Hold **Cmd** and scroll in to zoom.

**Expected result:** The 200 Hz peak remains under the cursor as the axes zoom in.

---

#### C18 — Reset axes to defaults (macOS/iOS/iPadOS)
**Platforms:** macOS · iOS · iPadOS · **Priority:** Medium · **Part 1 ref:** C18
**Preconditions:** Frequency and/or dB axes have been panned or zoomed away from defaults.
**Steps (macOS):**
1. Right-click the chart area to open the context menu.
2. Select **Reset Axes to Defaults**.

**Steps (iOS/iPadOS):**
1. Tap the **info icon** on the chart.
2. Tap **Reset Axes to Defaults**.

**Expected result:** Both axes return to the saved default values (as stored in Settings).

---

#### C19 — Settings axis ranges preserved on restart
**Platforms:** iOS · iPadOS · macOS · **Priority:** Low · **Part 1 ref:** C19
**Preconditions:** App running on any platform.
**Steps:**
1. Open Settings and set non-default values for Min Frequency, Max Frequency, Min dB, and Max dB (e.g. 100–500 Hz, −100 to −20 dB).
2. Close Settings and confirm the chart reflects the new ranges.
3. Quit the app fully (swipe up on iOS/iPadOS; Cmd+Q on macOS).
4. Relaunch GuitarTap.

**Expected result:** The chart opens with the frequency and dB ranges set in step 1. Note: ranges adjusted by panning or zooming gestures are intentionally not persisted and will revert to the Settings values on restart.

---

### Draggable Peak Annotations

#### D11 — Annotation draggable on screen
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** D11
**Preconditions:** A measurement has been captured and peak annotations are visible.
**Steps:**
1. Press and drag (iOS/iPadOS) or click-and-drag (macOS) a peak label.
2. Drag it to a new position.
3. Release.

**Expected result:** The label moves to the new position. It remains at that position after release.

---

#### D12 — Annotation position persists after zoom/pan
**Platforms:** iOS · iPadOS · macOS · **Priority:** Medium · **Part 1 ref:** D12
**Preconditions:** D11 completed; a label is at a non-default position.
**Steps:**
1. Pinch to zoom (iOS/iPadOS) or scroll with Command/Option/Control modifier (macOS) to zoom the chart.
2. Pan the chart.

**Expected result:** The annotation label stays attached to its peak at the correct chart position and does not jump back to the default position.

---

#### D13 — Annotation reset to default position
**Platforms:** iOS · iPadOS · macOS · **Priority:** Medium · **Part 1 ref:** D13
**Preconditions:** A label has been dragged to a non-default position (D11).
**Steps:**
1. iOS/iPadOS: Double-tap the label. macOS: Right-click the label and choose "Reset Position".

**Expected result:** The label snaps back to its default (zero-offset) position relative to the peak marker.

---

#### D14 — Annotations hidden in `.none` visibility mode
**Platforms:** iOS · iPadOS · macOS · **Priority:** Medium · **Part 1 ref:** D14
**Preconditions:** A measurement is captured and annotations are visible.
**Steps:**
1. Tap the **Annotations** button until the tooltip/icon indicates "None".

**Expected result:** All peak annotation labels disappear from the chart. Peak markers may remain.

---

#### D15 — `.selected` mode shows only Results-panel-selected labels
**Platforms:** iOS · iPadOS · macOS · **Priority:** Low · **Part 1 ref:** D15
**Preconditions:** Multiple peaks are visible and at least one peak is not selected in the Results panel.
**Steps:**
1. In the Results panel, confirm that some peaks are selected and some are not.
2. Cycle the Annotations button to the **Selected** mode.

**Expected result:** Only the labels for peaks that are selected in the Results panel are visible. Labels for unselected peaks are hidden.

---

### Persistence & Export

#### R7 — Saved measurement persists across relaunch
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** R7
**Preconditions:** At least one tap has been captured.
**Steps:**
1. Tap **Save**; enter a name (e.g. "Test spruce"); confirm.
2. Force-quit the app (swipe up from app switcher).
3. Relaunch GuitarTap.
4. Open **Measurements**.

**Expected result:** "Test spruce" appears in the list with the correct date.

---

#### R8 — Export Measurement round-trip — export and re-import matches original
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** R8
**Preconditions:** A measurement with peaks is saved.
**Steps:**
1. Open the Measurements list. Right-click (macOS) or long-press (iOS/iPadOS) the measurement row and choose **View Details**. Note the name, date, location/notes, and all peaks shown in the Results panel.
2. Right-click (macOS) or long-press (iOS/iPadOS) the same row and choose **Save Measurement to Disk…** (macOS) or **Export Measurement** (iOS/iPadOS). Save the `.guitartap` file.
3. Import the file using the **Import** toolbar button (macOS) or ellipsis → **Import Measurement** (iOS/iPadOS). A single-measurement import automatically loads it into the main view and adds it to the list.
4. Right-click (macOS) or long-press (iOS/iPadOS) the newly imported row and choose **View Details**.

**Expected result:** The imported measurement's detail view looks identical to the original — same name, date, location/notes, same peaks with the same frequencies, magnitudes, and mode assignments in the Results panel, and the same spectrum appearance.

> **Design note — auto label stability:** Mode labels stored as `.auto` (i.e. not manually overridden by the user) are re-evaluated at display time by `GuitarMode.classifyAll()`. If classification boundaries change in a future app version, an auto-labelled peak may display a different mode name than when it was saved. Manually assigned labels are stored as literal strings and are immune to this. Peaks near boundaries are most susceptible. This is expected behaviour, not a bug.

---

#### R9 — Export PDF renders correctly
**Platforms:** iOS · iPadOS · macOS · **Priority:** Medium · **Part 1 ref:** R9
**Preconditions:** A measurement with at least one peak is saved.
**Steps:**
1. Open the measurement detail view.
2. Tap **Export → PDF**.
3. Open the PDF in Preview (macOS) or Files (iOS).

**Expected result:** PDF contains the spectrum chart image, a table of peaks (frequency, dB, Q, mode), and the measurement metadata (name, date, guitar type). No blank pages or missing images.

---

#### R10 — Cross-device transfer via export/import
**Platforms:** iOS · iPadOS · macOS · **Priority:** Low · **Part 1 ref:** R10
**Preconditions:** Two devices (any combination of iPhone, iPad, Mac). A measurement is saved on device A.

> **Note:** Measurements are stored in the app's local document directory. There is no automatic iCloud or CloudKit sync — measurements do **not** automatically appear on other devices. Cross-device transfer requires manual export/import.

**Steps:**
1. On device A: right-click (macOS) or long-press (iOS/iPadOS) the measurement and choose **Export Measurement** (opens the share sheet — choose AirDrop to send directly to device B) or **Save Measurement to Disk…** (macOS only — save to disk then share via Finder). AirDrop will route the `.guitartap` file directly to GuitarTap on the receiving device.
2. On device B: use the **Import** toolbar button (macOS) or ellipsis → **Import Measurement** (iOS/iPadOS) to import the file. Legacy `.json` files are also accepted.

**Expected result:** The measurement appears in the list on device B.

---

### Cross-Platform UI

#### U1 — All primary controls present on iPhone
**Platforms:** iOS · **Priority:** High · **Part 1 ref:** U1
**Preconditions:** iPhone with a compact horizontal size class (iPhone SE, iPhone 15, etc.)
**Steps:**
1. Launch GuitarTap on iPhone in portrait.
2. Verify nav bar left contains: Results. Nav bar right contains: Metrics, Settings.
3. Verify the header button bar contains: Auto dB, Crosshair, Annotations, Save, Measurements (icon-only bordered buttons).
4. Rotate to landscape.
5. Verify nav bar left contains: Results, Auto dB, Crosshair. Nav bar right contains: Annotations, Save, Measurements, Metrics, Settings.

**Expected result:** All controls are present in both orientations with no clipping. Button order is consistent with iPad layout.

---

#### U2 — All primary controls present on iPad
**Platforms:** iPadOS · **Priority:** High · **Part 1 ref:** U2
**Preconditions:** iPad in landscape or portrait orientation.
**Steps:**
1. Launch GuitarTap on iPad.
2. Verify the two-row header layout shows full-label buttons.

**Expected result:** Both rows are fully visible without horizontal scrolling. All buttons have text labels.

---

#### U3 — All primary controls present on macOS (wide window)
**Platforms:** macOS · **Priority:** High · **Part 1 ref:** U3
**Preconditions:** macOS, window at ≥900 px wide.
**Steps:**
1. Launch GuitarTap.
2. Verify the single-row button layout shows: Auto dB, Annotations, Save, Measurements, Metrics, Settings (right-justified).

**Expected result:** All buttons with full text labels are visible in one row.

---

#### U4 — macOS icon-only layout at narrow window
**Platforms:** macOS · **Priority:** Medium · **Part 1 ref:** U4
**Preconditions:** macOS.
**Steps:**
1. Drag the window to a narrow width (≈500 px).

**Expected result:** `ViewThatFits` switches to the icon-only two-row layout. No button labels are truncated. No button falls off-screen.

---

#### U5 — Status bar correct on iPhone
**Platforms:** iOS · **Priority:** Medium · **Part 1 ref:** U5
**Preconditions:** App running on iPhone.
**Steps:**
1. Launch the app (recording begins automatically).
2. Observe the compact status bar (28 px tall area below the header).

**Expected result:** The compact status bar shows the tap indicator dot, a dB reading, and a running dot. No element is clipped or overlapping.

---

#### U6 — Status bar correct on iPad/macOS
**Platforms:** iPadOS · macOS · **Priority:** Medium · **Part 1 ref:** U6
**Preconditions:** App running on iPad or macOS.
**Steps:**
1. Launch the app (recording begins automatically).
2. Knock the guitar once to trigger a tap.
3. Observe the full status bar.

**Expected result:** The full status bar shows the progress bar, the "Tap Detected!" label, the bin count, and the frozen indicator. No element is clipped or missing.

---

#### U7 — Settings sheet opens, changes persist
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** U7
**Preconditions:** App running on any platform.
**Steps:**
1. Tap **Settings**.
2. Change the threshold value.
3. Dismiss the settings sheet.
4. Reopen Settings.

**Expected result:** The threshold value is the same as the one entered in step 2.

---

#### U8 — Results sheet opens and closes
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** U8
**Preconditions:** At least one tap has been captured and a spectrum is displayed.
**Steps:**
1. Tap **Results**.
2. Verify the peaks table is visible.
3. Dismiss the sheet (swipe down on iOS/iPadOS; close button on macOS).

**Expected result:** The peaks table appears with frequency, dB, Q, and mode columns populated. Dismissing the sheet returns the app to the main view cleanly.

---

#### U9 — Save sheet accepts name and saves
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** U9
**Preconditions:** At least one tap has been captured.
**Steps:**
1. Tap **Save**.
2. Type a name for the measurement (e.g. "Test spruce top").
3. Confirm the save.
4. Open **Measurements**.

**Expected result:** The new measurement appears in the Measurements list with the name entered and the correct date/time.

---

#### U10 — Measurements list shows saved items
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** U10
**Preconditions:** At least one measurement has been previously saved.
**Steps:**
1. Tap **Measurements** to open the list.

**Expected result:** Previously saved measurements are listed, each showing the measurement name and date. The list is scrollable if it contains many entries.

---

#### U11 — Dark mode: no invisible text
**Platforms:** iOS · iPadOS · macOS · **Priority:** Medium · **Part 1 ref:** U11
**Preconditions:** System dark mode enabled.
**Steps:**
1. Launch GuitarTap.
2. Scroll through the main view, status bar, settings sheet, and measurement detail.

**Expected result:** All text is legible. No white-on-white or black-on-black combinations. Chart axis labels and peak annotations remain readable.

---

#### U12 — Dynamic Type: large text accessible
**Platforms:** iOS · iPadOS · **Priority:** Low · **Part 1 ref:** U12
**Preconditions:** Accessibility text size set to the largest option via **Settings → Accessibility → Display & Text Size → Larger Text** (drag slider to maximum).
**Steps:**
1. Launch GuitarTap.
2. Inspect all buttons in the header and toolbar.
3. Open the **Settings** sheet and inspect all labels and controls.
4. Open the **Measurements** list and inspect row labels.

**Expected result:** No button label is clipped or truncated. All labels and controls remain usable. The layout may reflow but must not hide or overlap any interactive element.

---

### Regression Smoke Tests

#### K1 — App launches without crash
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** K1
**Preconditions:** Device restarted (cold launch).
**Steps:**
1. Tap the GuitarTap icon.

**Expected result:** Main view appears within 3 s. No crash. No "GuitarTap quit unexpectedly" dialog.

---

#### K2 — Chart renders with a saved measurement
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** K2
**Preconditions:** At least one measurement has been saved using the **Save** button during a previous tap tone session (see R8).
**Steps:**
1. Export that measurement to a `.guitartap` file using **Export Measurement** (iOS/iPadOS share sheet) or **Save Measurement to Disk…** (macOS).
2. Re-import it using **Import Measurement** (iOS/iPadOS) or the **Import** toolbar button (macOS).
3. Open the imported measurement from the Measurements list.

**Expected result:** The spectrum chart renders with the correct peaks annotated. No blank chart or decode error.

---

#### K3 — Recording starts automatically on launch
**Platforms:** iOS · iPadOS · macOS · **Priority:** High · **Part 1 ref:** K3
**Preconditions:** Microphone permission granted.
**Steps:**
1. Launch the app.
2. Observe the green running indicator within 3 s.

**Expected result:** Indicator goes green automatically. App does not freeze. No crash.

---

#### K4 — Memory stable during extended recording
**Platforms:** iOS · iPadOS · macOS · **Priority:** Medium · **Part 1 ref:** K4
**Preconditions:** Xcode Instruments available. App running on device.
**Steps:**
1. Profile the app with the Allocations instrument.
2. Launch the app (recording begins automatically).
3. Record continuously for 2 minutes.

**Expected result:** Memory usage grows during FFT initialisation and then plateaus. No unbounded growth over the 2-minute period. Net growth < 10 MB from the plateau.

---

#### K5 — App returns from background correctly
**Platforms:** iOS · iPadOS · **Priority:** High · **Part 1 ref:** K5
**Preconditions:** App recording on iPhone or iPad.
**Steps:**
1. Confirm the spectrum is animating (recording starts automatically on launch).
2. Press the Home button (or swipe up to go home).
3. Wait 10 s.
4. Return to GuitarTap by tapping its icon.

**Expected result:** The app is either still recording (indicator green) or in a clean stopped state. The UI is not frozen. No crash.

---

#### K6 — Rotation does not break layout
**Platforms:** iOS · iPadOS · **Priority:** Medium · **Part 1 ref:** K6
**Preconditions:** App running on iPhone or iPad.
**Steps:**
1. Launch the app in portrait and confirm the spectrum is visible (recording starts automatically).
2. Rotate device to landscape.
3. Rotate back to portrait.

**Expected result:** The chart, header buttons, and status bar reflow cleanly in both orientations. No controls overlap or are clipped.

---
