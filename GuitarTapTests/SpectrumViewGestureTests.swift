//
//  SpectrumViewGestureTests.swift
//  GuitarTapTests
//
//  Unit tests for the pure zoom/pan math in SpectrumView+GestureHandlers.swift.
//  These tests exercise applyFrequencyZoom, applyMagnitudeZoom, and handlePan
//  by constructing a minimal SpectrumView with bindings backed by a reference-type
//  state holder, then calling the methods directly — no SwiftUI rendering required.
//
//  Covered: C1–C8
//

import Testing
import SwiftUI
@testable import GuitarTap

// MARK: - Helper

/// A class-based state holder so that Binding closures can capture a reference
/// and mutate the state in-place. A struct would not work here because
/// `Binding(get:set:)` closures capture `self` by value for structs, making
/// the setter a no-op (it would mutate a copy, not the original).
private final class GestureState {
    var minFreq: Float
    var maxFreq: Float
    var minDB: Float
    var maxDB: Float

    init(minFreq: Float, maxFreq: Float, minDB: Float, maxDB: Float) {
        self.minFreq = minFreq
        self.maxFreq = maxFreq
        self.minDB = minDB
        self.maxDB = maxDB
    }

    /// Returns a SpectrumView wired to this state object's properties.
    var view: SpectrumView {
        SpectrumView(
            frequencies: [],
            magnitudes: [],
            minFreq: Binding(get: { self.minFreq }, set: { self.minFreq = $0 }),
            maxFreq: Binding(get: { self.maxFreq }, set: { self.maxFreq = $0 }),
            minDB:   Binding(get: { self.minDB   }, set: { self.minDB   = $0 }),
            maxDB:   Binding(get: { self.maxDB   }, set: { self.maxDB   = $0 })
        )
    }
}

// MARK: - C1–C3  Frequency Zoom

@Suite("FrequencyZoom")
struct FrequencyZoomTests {

    // C1 — scale > 1 narrows the visible frequency range
    @Test func scaleIn_narrowsRange() {
        let s = GestureState(minFreq: 100, maxFreq: 1000, minDB: -80, maxDB: 0)
        let before = s.maxFreq - s.minFreq
        s.view.applyFrequencyZoom(scale: 2.0, anchorFreq: 550)
        let after = s.maxFreq - s.minFreq
        #expect(after < before, "Zoom-in should narrow the frequency range")
        #expect(s.minFreq >= 0, "minFreq should stay ≥ 0 Hz")
        #expect(s.maxFreq <= 5000, "maxFreq should stay ≤ 5 kHz")
    }

    // C2 — scale < 1 widens the visible frequency range, clamped to valid bounds
    @Test func scaleOut_widensRange() {
        let s = GestureState(minFreq: 400, maxFreq: 800, minDB: -80, maxDB: 0)
        let before = s.maxFreq - s.minFreq
        s.view.applyFrequencyZoom(scale: 0.5, anchorFreq: 600)
        let after = s.maxFreq - s.minFreq
        #expect(after > before, "Zoom-out should widen the frequency range")
        #expect(s.minFreq >= 0)
        #expect(s.maxFreq <= 5000)
    }

    // C3 — zooming in past the minimum 50 Hz span is rejected
    @Test func minimumRange_enforced() {
        // Start with an already very narrow range
        let s = GestureState(minFreq: 490, maxFreq: 510, minDB: -80, maxDB: 0)
        let beforeMin = s.minFreq
        let beforeMax = s.maxFreq
        // Aggressive zoom-in: result would be < 50 Hz, so it should be rejected
        s.view.applyFrequencyZoom(scale: 100.0, anchorFreq: 500)
        let after = s.maxFreq - s.minFreq
        #expect(after >= 50 || (s.minFreq == beforeMin && s.maxFreq == beforeMax),
                "Zoom-in past minimum range should be rejected")
    }

    // Anchor frequency is preserved under zoom-in
    @Test func anchorFrequency_staysFixed() {
        let s = GestureState(minFreq: 100, maxFreq: 1000, minDB: -80, maxDB: 0)
        let anchor: Float = 500
        s.view.applyFrequencyZoom(scale: 2.0, anchorFreq: anchor)
        // The anchor should lie within the new (narrower) range
        #expect(s.minFreq <= anchor, "minFreq should be ≤ anchor after zoom-in")
        #expect(s.maxFreq >= anchor, "maxFreq should be ≥ anchor after zoom-in")
    }

    // Scale = 1 is a no-op
    @Test func identityScale_noChange() {
        let s = GestureState(minFreq: 200, maxFreq: 1800, minDB: -80, maxDB: 0)
        let beforeMin = s.minFreq
        let beforeMax = s.maxFreq
        s.view.applyFrequencyZoom(scale: 1.0, anchorFreq: 1000)
        #expect(s.minFreq == beforeMin)
        #expect(s.maxFreq == beforeMax)
    }
}

// MARK: - C4–C5  Magnitude Zoom

@Suite("MagnitudeZoom")
struct MagnitudeZoomTests {

    // C4 — scale > 1 narrows the dB range
    @Test func scaleIn_narrowsRange() {
        let s = GestureState(minFreq: 100, maxFreq: 1000, minDB: -100, maxDB: 0)
        let before = s.maxDB - s.minDB
        s.view.applyMagnitudeZoom(scale: 2.0, anchorDB: -50)
        let after = s.maxDB - s.minDB
        #expect(after < before, "Zoom-in should narrow the dB range")
        #expect(s.minDB >= -120)
        #expect(s.maxDB <= 20)
    }

    // C5 — zooming in past the minimum 10 dB span is rejected
    @Test func minimumRange_enforced() {
        // Range is already at 11 dB — aggressive zoom should be rejected
        let s = GestureState(minFreq: 100, maxFreq: 1000, minDB: -55, maxDB: -44)
        s.view.applyMagnitudeZoom(scale: 100.0, anchorDB: -50)
        let after = s.maxDB - s.minDB
        #expect(after >= 10, "Zoom-in past 10 dB minimum range should be rejected")
    }

    // Scale = 1 is a no-op
    @Test func identityScale_noChange() {
        let s = GestureState(minFreq: 100, maxFreq: 1000, minDB: -80, maxDB: -10)
        let beforeMin = s.minDB
        let beforeMax = s.maxDB
        s.view.applyMagnitudeZoom(scale: 1.0, anchorDB: -40)
        #expect(s.minDB == beforeMin)
        #expect(s.maxDB == beforeMax)
    }
}

// MARK: - C6–C8  Pan

@Suite("Pan")
struct PanTests {

    // C6 — panning left past 0 Hz stops at 0 Hz and preserves the span
    @Test func frequency_clampsAt0Hz() {
        let s = GestureState(minFreq: 50, maxFreq: 300, minDB: -80, maxDB: 0)
        let span = s.maxFreq - s.minFreq
        // Large left-pan (positive width shifts the view window to the left)
        s.view.handlePan(translation: CGSize(width: 10000, height: 0))
        #expect(s.minFreq >= 0, "minFreq should not go below 0 Hz")
        let newSpan = s.maxFreq - s.minFreq
        #expect(abs(newSpan - span) < 1, "Frequency span should be preserved after clamped pan")
    }

    // C7 — panning right past 5 kHz stops at 5 kHz and preserves the span
    @Test func frequency_clampsAt5kHz() {
        let s = GestureState(minFreq: 4000, maxFreq: 4800, minDB: -80, maxDB: 0)
        let span = s.maxFreq - s.minFreq
        // Large right-pan (negative width)
        s.view.handlePan(translation: CGSize(width: -10000, height: 0))
        #expect(s.maxFreq <= 5000, "maxFreq should not exceed 5 kHz")
        let newSpan = s.maxFreq - s.minFreq
        #expect(abs(newSpan - span) < 1, "Frequency span should be preserved after clamped pan")
    }

    // C8 — panning down past −120 dB stops at −120 dB and preserves the dB span
    @Test func magnitude_clampsAt120dB() {
        let s = GestureState(minFreq: 100, maxFreq: 1000, minDB: -115, maxDB: -60)
        let span = s.maxDB - s.minDB
        // Large downward pan (positive height shifts dB upward, showing lower dB values)
        s.view.handlePan(translation: CGSize(width: 0, height: 10000))
        #expect(s.minDB >= -120, "minDB should not go below −120 dB")
        let newSpan = s.maxDB - s.minDB
        #expect(abs(newSpan - span) < 1, "dB span should be preserved after clamped pan")
    }

    // Pan in the zero-translation direction is a no-op
    @Test func zeroTranslation_noChange() {
        let s = GestureState(minFreq: 200, maxFreq: 800, minDB: -80, maxDB: -10)
        let beforeMinFreq = s.minFreq; let beforeMaxFreq = s.maxFreq
        let beforeMinDB = s.minDB;     let beforeMaxDB = s.maxDB
        s.view.handlePan(translation: .zero)
        #expect(s.minFreq == beforeMinFreq)
        #expect(s.maxFreq == beforeMaxFreq)
        #expect(s.minDB == beforeMinDB)
        #expect(s.maxDB == beforeMaxDB)
    }
}
