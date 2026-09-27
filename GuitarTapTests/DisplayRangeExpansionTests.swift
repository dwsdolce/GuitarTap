//
//  DisplayRangeExpansionTests.swift
//  GuitarTapTests
//
// @parity test/display-range
//
// The chart widens its frequency axis onto a newly identified material peak.
//
// A plate or brace scans a wide band (brace: 100–1200 Hz) and the display range is
// per-measurement-type and persisted, so the fL / fC / fFLC a measurement just produced can land
// off the edge of the chart. All three editions widen the axis, so the same measurement shows the
// peak on every edition.
//
// The rule lives in DisplayRange rather than a SwiftUI View extension, so it can be tested here.

import Testing
@testable import GuitarTap

@Suite("DisplayRangeExpansion")
struct DisplayRangeExpansionTests {

    @Test func peakAboveTheRange_widensTheMaximumWithPadding() {
        let r = DisplayRange.expanded(toInclude: 1000, min: 100, max: 800)
        #expect(r.max == 1100, "1000 Hz + 10% padding")
        #expect(r.min == 100, "the minimum is untouched")
    }

    @Test func peakBelowTheRange_widensTheMinimumWithPadding() {
        let r = DisplayRange.expanded(toInclude: 50, min: 100, max: 800)
        #expect(r.min == 45, "50 Hz - 10% padding")
        #expect(r.max == 800, "the maximum is untouched")
    }

    @Test func peakInsideTheRange_leavesItAlone() {
        let r = DisplayRange.expanded(toInclude: 400, min: 100, max: 800)
        #expect(r.min == 100)
        #expect(r.max == 800, "a range is never NARROWED to fit — that would hide other peaks")
    }

    @Test func aVeryLowPeak_isClampedAtTheFloor() {
        let r = DisplayRange.expanded(toInclude: 0.5, min: 100, max: 800)
        #expect(r.min == DisplayRange.floorHz, "never below 1 Hz — there is nothing to draw there")
    }

    @Test func peakExactlyAtTheBoundary_changesNothing() {
        let r = DisplayRange.expanded(toInclude: 800, min: 100, max: 800)
        #expect(r.max == 800, "already visible")
        let r2 = DisplayRange.expanded(toInclude: 100, min: 100, max: 800)
        #expect(r2.min == 100, "already visible")
    }
}
