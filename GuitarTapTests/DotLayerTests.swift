//
//  DotLayerTests.swift
//  GuitarTapTests
//
//  Pins the CHART DOT LIST rule — GuitarMode.peaksInDisplayRange(...), the rule behind
//  SpectrumView.allPeaksInRange.
//
//  Why this suite exists: the dot list and the annotation list are DIFFERENT sets, and
//  conflating them is a bug that actually shipped (on the web, dots followed the selection —
//  with mode=selected only the chosen peaks were dotted). Swift and Python were correct, but
//  nothing pinned the rule anywhere, so the drift was invisible. These tests, plus their
//  Python and web twins, make the difference provable on all three platforms:
//
//    dot list        = every peak in the visible frequency range   (annotation-independent)
//    annotation list = visiblePeaks — narrowed by all/selected/none (drives badges + report)
//
//  Test plan coverage: DL1–DL7
//
// @parity view/dot-layer

import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Fixture
// ---------------------------------------------------------------------------
//
// Generic guitar bands (GuitarType.modeRanges): air 70–135, top 140–260,
// back 180–300, dipole 310–460, ring 580–880, upper 880+.
// A display range of 75–350 Hz therefore gives us, deliberately:
//
//   60 Hz  — BELOW the range                    → excluded by range
//   75 Hz  — exactly the low edge, in air       → included (boundary)
//  100 Hz  — in air                             → known, included
//  200 Hz  — in top/back                        → known, included
//  305 Hz  — IN range but in NO band (300<305<310) → the "unknown frequency" case
//  350 Hz  — exactly the high edge, in dipole   → included (boundary)
//  400 Hz  — in dipole but ABOVE the range      → excluded (range beats known)

private let kMinFreq: Float = 75
private let kMaxFreq: Float = 350

private func peak(_ f: Float, _ mag: Float = -30) -> ResonantPeak {
    ResonantPeak(frequency: f, magnitude: mag)
}

private func dots(
    _ peaks: [ResonantPeak],
    isGuitar: Bool = true,
    showUnknownModes: Bool = false
) -> [Float] {
    GuitarMode.peaksInDisplayRange(
        peaks,
        minFreq: kMinFreq,
        maxFreq: kMaxFreq,
        isGuitar: isGuitar,
        showUnknownModes: showUnknownModes,
        guitarType: .generic
    ).map(\.frequency)
}

// ---------------------------------------------------------------------------
// MARK: - Range filtering  (DL1–DL2)
// ---------------------------------------------------------------------------

@Suite("DotLayerRange")
struct DotLayerRangeTests {

    // DL1: peaks outside the visible range get no dot — even a peak that IS in a named
    // band (400 Hz is dipole). Range wins over "known".
    @Test func excludesOutOfRangePeaks() {
        let result = dots([peak(60), peak(100), peak(200), peak(400)])

        #expect(result == [100, 200], "Only in-range peaks should be dotted, got \(result)")
    }

    // DL2: the range bounds are inclusive on both edges.
    @Test func rangeBoundsAreInclusive() {
        let result = dots([peak(kMinFreq), peak(200), peak(kMaxFreq)])

        #expect(result == [75, 200, 350], "Both edges should be included, got \(result)")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Unknown-mode filtering  (DL3–DL5)
// ---------------------------------------------------------------------------

@Suite("DotLayerUnknownModes")
struct DotLayerUnknownModeTests {

    // DL3: an in-range peak that falls in NO band is dropped when unknown modes are hidden.
    @Test func hidesUnknownFrequencyWhenSettingOff() {
        let result = dots([peak(100), peak(305), peak(200)], showUnknownModes: false)

        #expect(result == [100, 200], "305 Hz is in no band and should be hidden, got \(result)")
    }

    // DL4: the same peak is kept when the user asks to see unknown modes.
    @Test func showsUnknownFrequencyWhenSettingOn() {
        let result = dots([peak(100), peak(305), peak(200)], showUnknownModes: true)

        #expect(result == [100, 305, 200], "showUnknownModes should keep 305 Hz, got \(result)")
    }

    // DL5: material (plate/brace) has no mode bands — the unknown filter never applies,
    // so an in-range peak is dotted regardless of the setting.
    @Test func materialSkipsUnknownFilter() {
        let result = dots([peak(100), peak(305)], isGuitar: false, showUnknownModes: false)

        #expect(result == [100, 305], "Material must not apply the guitar unknown filter, got \(result)")
    }
}

// ---------------------------------------------------------------------------
// MARK: - The dot list is NOT the annotation list  (DL6–DL7)
// ---------------------------------------------------------------------------

@Suite("DotLayerVsAnnotationList", .serialized)
@MainActor
struct DotLayerVsAnnotationListTests {

    // DL6: THE regression guard. Cycling annotation visibility all → selected → none changes
    // visiblePeaks (the badges) but must leave the dot list completely untouched.
    @Test func dotListIsIndependentOfAnnotationModeAndSelection() {
        let savedType = TapDisplaySettings.measurementType
        let savedUnknown = TapDisplaySettings.showUnknownModes
        TapDisplaySettings.measurementType = .generic
        TapDisplaySettings.showUnknownModes = false
        defer {
            TapDisplaySettings.measurementType = savedType
            TapDisplaySettings.showUnknownModes = savedUnknown
        }

        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer())
        let p1 = peak(100), p2 = peak(200), p3 = peak(250)
        sut.currentPeaks = [p1, p2, p3]
        sut.selectedPeakIDs = [p2.id]          // only ONE peak selected

        let expectedDots: [Float] = [100, 200, 250]

        for mode in [AnnotationVisibilityMode.all, .selected, .none] {
            sut.annotationVisibilityMode = mode

            #expect(dots(sut.currentPeaks) == expectedDots,
                    "Dot list must not change with annotation mode \(mode), got \(dots(sut.currentPeaks))")
        }

        // …while the annotation list genuinely does vary. If this half ever stops varying,
        // the test above has become vacuous.
        sut.annotationVisibilityMode = .all
        #expect(sut.visiblePeaks.count == 3)
        sut.annotationVisibilityMode = .selected
        #expect(sut.visiblePeaks.count == 1, "selected → only the one selected peak is annotated")
        sut.annotationVisibilityMode = .none
        #expect(sut.visiblePeaks.isEmpty, "none → no annotations")
    }

    // DL7: the dot list is POSITIONAL — it asks "is this frequency in a band?", not "what mode
    // did the classifier assign?". A freeform mode override makes peakMode(for:) report
    // .unknown, but the peak keeps its dot because its frequency is still in a band.
    // This is the distinction the web got wrong (it filtered dots by assigned mode).
    @Test func dotListIgnoresModeOverrides() {
        let savedType = TapDisplaySettings.measurementType
        TapDisplaySettings.measurementType = .generic
        defer { TapDisplaySettings.measurementType = savedType }

        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer())
        let p = peak(200)                       // squarely inside top/back
        sut.currentPeaks = [p]
        sut.setModeOverride(.assigned("My Custom Label"), for: p.id)

        // The assigned mode is now .unknown (freeform labels have no GuitarMode)…
        #expect(sut.peakMode(for: p).normalized == .unknown,
                "A freeform override should report .unknown as the assigned mode")

        // …but the dot layer still dots it, because 200 Hz is in a band.
        #expect(dots(sut.currentPeaks) == [200],
                "A freeform override must not remove the peak's dot")
    }
}