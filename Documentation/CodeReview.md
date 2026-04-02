# GuitarTap — Code Review

## 1. Dead Code

**`trackDecay(peakMagnitude:)` — `TapToneAnalyzer+DecayTracking.swift:94`**
This method is a documented no-op. Its only content is a comment explaining it does nothing. It is called every FFT frame from `analyzeMagnitudes`, wasting a dispatch call 10+ times per second. Safe to delete; remove the call site as well.

**`baseURL` parameter — `importMeasurements(from:baseURL:)` in `+MeasurementManagement.swift`**
The parameter is documented as unused. Remove it and update the call site. A dead parameter in a public API creates false API surface and confuses callers.

---

## 2. Bugs / Behavioral Inconsistencies

**`importMeasurements(json:)` silently skips `persistMeasurements()` — `+MeasurementManagement.swift`**
The `Data` overload calls `persistMeasurements()` after importing; the `String`/JSON overload (used by the share-sheet import path) does not. Imports via that path are lost on next launch.

**`New Tap` button disabled logic is inconsistent — `+Controls.swift`**
`compactTapControls` (line ~689) and `landscapeTapControls` (~434) both correctly allow the button when `displayMode == .comparison` so the user can exit comparison mode:
```swift
.disabled(tap.displayMode != .comparison && (!fft.isRunning || !tap.isReadyForDetection || tap.isDetecting))
```
`regularTapControlsWide` (~847) is missing the comparison-mode guard entirely:
```swift
.disabled(!fft.isRunning || !tap.isReadyForDetection || tap.isDetecting)
```
On the wide layout (the most common iPad/macOS layout), pressing New Tap to exit comparison mode may be disabled when the FFT engine is not running, trapping the user in comparison mode with no obvious exit.

---

## 3. Duplication

### Model layer

**Peak construction block — `+PeakAnalysis.swift` (2 sites, ~14 lines each)**
The code that builds a `ResonantPeak` from bin index + magnitude arrays is duplicated between the mode-scan pass and the unknown-scan pass. Extract a private `makePeak(at:magnitudes:frequencies:) -> ResonantPeak` helper.

**`recalculateFrozenPeaksIfNeeded` dual paths — `+PeakAnalysis.swift` (~50 lines each)**
The loaded-measurement path and the live-tap path both perform: annotation remapping → mode-override remapping → selection carry-forward. The two paths share the same structure with only the peak source differing. A shared private helper that accepts the input peaks and returns classified/remapped peaks would eliminate the duplication.

**Non-gated legacy handlers mirror gated handlers — `+TapDetection.swift`**
`handleLongitudinalTapProgress`, `handleCrossTapProgress`, `handleFlcTapProgress` are documented as "Used only when the gated-FFT path is unavailable." If the gated path is truly always active, these handlers are dead. If they are reachable, the ~6-line `DispatchQueue.asyncAfter` transition blocks inside them are copy-pasted. At minimum, extract the transition block into a private method; ideally verify and remove the fallback entirely.

**Selected-peaks builder (`var sel`) — `+SpectrumCapture.swift`**
`handleCrossGatedProgress` and `handleFlcGatedProgress` both build an array of selected peaks by appending the preferred peak (user-selected → auto-selected → dominant) for each tap type. The pattern is:
```swift
var sel: [ResonantPeak] = []
if let p = selectedLongitudinalPeak { sel.append(p) } else if let p = longitudinalPeaks.first { sel.append(p) }
sel.append(selectedXxxPeak ?? dominantPeak)
```
This is a clear candidate for a `func resolvedSelectedPeaks(for phase: MaterialTapPhase) -> [ResonantPeak]` helper.

**Route change handler — `+DeviceManagement.swift`**
The `.newDeviceAvailable` and `.oldDeviceUnavailable` `AVAudioSession` route change cases have identical bodies. Extract a private helper.

### View layer

**macOS header button variants — `+Controls.swift`**
`macosWideHeaderButtons`, `macosMediumHeaderButtons`, `macosNarrowHeaderButtons` each declare the same six buttons with only label text and inter-button spacing differences — approximately 200 lines of near-identical SwiftUI code. This should be a single view that accepts `compact: Bool` and `showLabels: Bool` parameters, or similar. `ViewThatFits` at the call site already selects which variant to use.

**Threshold reset buttons — `+Controls.swift`**
The tap-detection-threshold reset button (sets threshold back to default) and peak-minimum reset button each appear three times: in `compactTapControls`, `regularTapControlsWide`, and `regularTapControlsNarrow`. Any change to the reset logic must be applied in all three places. Extract each as a small `@ViewBuilder` computed property or sub-view.

**`SpectrumView(...)` macOS vs iOS call — `+SpectrumViews.swift`**
The two platform branches differ by exactly one parameter (`crosshairMode: $crosshairMode`, iOS only). All other 15+ parameters are identical. Consider making `crosshairMode` an optional binding with a `.constant(false)` default so the divergence disappears.

**`LoadingOverlay` in macOS and iOS layouts — `+Layouts.swift:123–131` and `+Layouts.swift:237–244`**
Both platform layouts have an identical `.overlay { if isExportingSpectrum ... else if isSavingMeasurement ... else if isGeneratingReport ... }` block. Since `mainContentView` is shared, the overlay could be applied there once instead of in each platform layout.

---

## 4. Access Control

Several properties in `TapToneAnalyzer.swift` are `var` with no access modifier, making them writable from anywhere:

| Property | Appropriate access |
|---|---|
| `userHasModifiedPeakSelection` | `private(set)` — written only by `togglePeakSelection`, `resetToAutoSelection`, etc. |
| `loadedMeasurementPeaks` | `private` — only used internally during `loadMeasurement` |
| `selectedPeakFrequencies` | `private` — written only in `loadMeasurement` for state restoration |
| `isLoadingMeasurement` | `private` — internal guard flag |
| `cancellables` | `internal` in test (`sut.cancellables.removeAll()`) so `private` would break tests — but the test workaround itself is a smell |

In `RealtimeFFTAnalyzer.swift`:

| Property | Appropriate access |
|---|---|
| `isApplyingDeviceSwitch` | `private` |
| `hardwareListenerBlock` | `private` |
| `sampleRateListenerBlock` | `private` |

---

## 5. Documentation / Comment Accuracy

**`setupSubscriptions()` comment says "Three subscriptions" — `TapToneAnalyzer.swift`**
There are four subscriptions (the fast `$inputLevelDB` subscription was added for decay tracking but the comment was not updated).

**Non-gated handler documentation — `+TapDetection.swift`**
`handleLongitudinalTapProgress` et al are documented "Used only when the gated-FFT path is unavailable." It is never made clear under what circumstances the gated path would be unavailable — and looking at `detectTap`, the gated path is enabled unconditionally for plate/brace measurements. The comment should either explain the specific condition or these should be removed.

**`stopDecayTracking()` — `+DecayTracking.swift:74`**
The method body consists only of cleanup lines followed by "Debug output removed." The empty look of the body after the cleanup is misleading — a brief comment explaining that the timer fires, stops tracking, and intentionally does nothing else would help.

**`start()` recursive call — `+EngineControl.swift`**
The macOS permission-grant handler calls `try? self.start()` recursively. This is intentional but completely undocumented. A `// Re-enter start() now that permission is granted` comment would prevent future confusion.

---

## 6. Code Partitioning / File Placement

**`setCalibrationWithoutSavingDeviceMapping` — `RealtimeFFTAnalyzer.swift`**
This workaround method is defined in the main file. Its name and function clearly belong in `+DeviceManagement.swift` alongside the calibration-save logic it bypasses. Moving it would make the main file a pure property/subscription declaration file.

**`getPortTypeDescription()` — `+DeviceManagement.swift`**
This is a translation helper from `AVAudioSession.Port` to a display string. It has no dependency on `RealtimeFFTAnalyzer` state — it could be a free function, an extension on `AVAudioSession.Port`, or a static method in a utilities file. As an instance method on the analyzer it pollutes the device management namespace.

**`TapAnalysisResultsView.swift` — 1,227 lines**
The plate `MaterialPeakRowView` callback closures (lines ~329–380) contain 40+ lines of peak-selection toggle logic that mutates `analyzer` properties directly from inside the view. This logic arguably belongs in `TapToneAnalyzer+AnnotationManagement` (or a new `+PeakSelectionManagement`) as named methods (`selectLongitudinalPeak(_:)`, `selectCrossPeak(_:)`, `selectFlcPeak(_:)`) that encapsulate the mutual-exclusion logic. The view becomes 3-line call sites.

---

## 7. Magic Constants

| Value | Location | Suggested named constant |
|---|---|---|
| `2.0` Hz | `removeDuplicatePeaks` in `+PeakAnalysis.swift` | `peakProximityHz` |
| `2.0` Hz | `buildAllPeaks` in `+SpectrumCapture.swift` | same |
| `5.0` Hz | `combinePlatePeaks` in `+TapDetection.swift` | `platePeakMatchToleranceHz` |
| `10` samples | `trackDecayFast` minimum history guard | `minimumDecayHistoryCount` |
| `5.0` seconds | decay history window in `trackDecayFast` | `decayHistoryWindowSeconds` |

The two `2.0` Hz values in different files should share a single constant — if the proximity tolerance is ever tuned, both files need updating.

---

## 8. Method Length

These are the longest methods in the project. None are immediately blocking, but they warrant a note if the file is ever touched:

| Method | File | Lines | Note |
|---|---|---|---|
| `start()` | `+EngineControl.swift` | ~360 | Platform-gated audio setup; could be split into `configureAudioSession()`, `configureInputDevice()`, `installTap()` |
| `loadMeasurement(_:)` | `+MeasurementManagement.swift` | ~274 | Restores all state from a saved measurement; 6–8 logical phases that could each be a private helper |
| `detectTap(...)` | `+TapDetection.swift` | ~140 | Sequential state machine; readable but long |

---

## 9. Test Coverage Observations

The test suite is well-structured and uses Swift Testing (`@Suite`, `@Test`, `#expect`) appropriately. A few gaps:

**`trackDecay` / `measureDecayTime`** — no tests. Given the `measureDecayTime` algorithm has edge cases (signal never peaks, never decays far enough, empty history), unit tests covering those branches would be valuable and are straightforward to write since the method is pure.

**`importMeasurements(json:)` persistence** — the missing `persistMeasurements()` call (bug §2) has no test catching it.

**Non-gated plate handlers** — `handleLongitudinalTapProgress`, `handleCrossTapProgress`, `handleFlcTapProgress` have no test coverage, consistent with the uncertainty about whether they are reachable.

**`recalculateFrozenPeaksIfNeeded`** — `FrozenPeakRecalculationTests.swift` exists, which is good. Verify it exercises both the loaded-measurement path and the live-tap path through the duplicated code (§3).

---

## Summary by Priority

**Fix now (bugs):**
1. `importMeasurements(json:)` missing `persistMeasurements()` call
2. `regularTapControlsWide` New Tap button missing comparison-mode guard

**Clean up (dead code):**
3. Delete `trackDecay(peakMagnitude:)` and its call site
4. Remove `baseURL` parameter from `importMeasurements(from:baseURL:)`

**Reduce duplication (high value):**
5. macOS header button triple-declaration (~200 lines)
6. `recalculateFrozenPeaksIfNeeded` dual paths
7. Plate peak-selection closures in `TapAnalysisResultsView` → named analyzer methods
8. Threshold reset buttons (3 sites)

**Access control / hygiene:**
9. Add `private`/`private(set)` to internal properties listed in §4
10. Fix `setupSubscriptions()` "Three subscriptions" comment

**Nice to have:**
11. Named constants for magic Hz values
12. Move `setCalibrationWithoutSavingDeviceMapping` to `+DeviceManagement`
13. Document recursive `start()` call
