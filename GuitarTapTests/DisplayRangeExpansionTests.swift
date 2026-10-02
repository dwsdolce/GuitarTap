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
// off the edge of the chart. The chart's range widens to show it; a guitar's does not. The view only
// applies DisplayRange.widened to its range, so the whole decision is tested here; the analyzer's
// announcing each peak is tested in MaterialPeakAnnouncementTests.

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

    @Test func aPeakAboveTheChartsLimit_widensOnlyToTheLimit() {
        let r = DisplayRange.expanded(toInclude: 4900, min: 100, max: 800)
        #expect(r.max == DisplayRange.frequencyBounds.upperBound, "never beyond 5 kHz")
    }

    @Test func peakExactlyAtTheBoundary_changesNothing() {
        let r = DisplayRange.expanded(toInclude: 800, min: 100, max: 800)
        #expect(r.max == 800, "already visible")
        let r2 = DisplayRange.expanded(toInclude: 100, min: 100, max: 800)
        #expect(r2.min == 100, "already visible")
    }

    // MARK: - The decision: plate and brace widen, guitar does not

    @Test func materialPeakOutsideTheRange_widensIt() {
        for type in [MeasurementType.plate, .brace] {
            let r = DisplayRange.widened(onto: 1000, for: type, fromLoad: false, min: 100, max: 800)
            #expect(r.min == 100 && r.max == 1100, "\(type)")
        }
    }

    @Test func materialPeakInsideTheRange_leavesItAlone() {
        let r = DisplayRange.widened(onto: 400, for: .plate, fromLoad: false, min: 100, max: 800)
        #expect(r.min == 100 && r.max == 800)
    }

    @Test func guitarPeakOutsideTheRange_leavesItAlone() {
        for type in [MeasurementType.generic, .acoustic, .classical, .flamenco] {
            let r = DisplayRange.widened(onto: 1000, for: type, fromLoad: false, min: 100, max: 800)
            #expect(r.min == 100 && r.max == 800, "\(type): a guitar's range is the user's analysis window")
        }
    }

    @Test func materialPeakRestoredByALoad_leavesTheRange() {
        let r = DisplayRange.widened(onto: 1000, for: .plate, fromLoad: true, min: 100, max: 800)
        #expect(r.min == 100 && r.max == 800, "a load shows the range it was saved with")
    }

    // MARK: - When the chart's range moves

    private let saved = DisplayRange.ChartRange(minFreq: 20, maxFreq: 200, minDB: -100, maxDB: 0)
    private let loaded = DisplayRange.ChartRange(minFreq: 50, maxFreq: 300, minDB: -90, maxDB: -10)
    private let zoomed = DisplayRange.ChartRange(minFreq: 60, maxFreq: 120, minDB: -90, maxDB: -10)

    @Test func settingsDone_withNothingChanged_leavesTheChart() {
        #expect(DisplayRange.onSettingsDone(saved: saved, previouslySaved: saved, typeChanged: false) == nil)
    }

    @Test func settingsDone_withAChangedFrequencyRange_movesToIt() {
        var before = saved; before.maxFreq = 250
        #expect(DisplayRange.onSettingsDone(saved: saved, previouslySaved: before, typeChanged: false) == saved)
    }

    @Test func settingsDone_withAChangedMagnitudeRange_movesToIt() {
        var before = saved; before.minDB = -80
        #expect(DisplayRange.onSettingsDone(saved: saved, previouslySaved: before, typeChanged: false) == saved)
    }

    @Test func settingsDone_withAChangedType_movesToItsSavedView() {
        #expect(DisplayRange.onSettingsDone(saved: saved, previouslySaved: saved, typeChanged: true) == saved)
    }

    @Test func newMeasurement_withNoLoad_leavesTheChart() {
        #expect(DisplayRange.onNewMeasurement(current: zoomed, loaded: nil, saved: saved) == nil)
    }

    @Test func newMeasurement_whileShowingTheLoad_returnsToTheSavedView() {
        #expect(DisplayRange.onNewMeasurement(current: loaded, loaded: loaded, saved: saved) == saved)
    }

    @Test func newMeasurement_afterTheUserMovedTheChart_leavesIt() {
        #expect(DisplayRange.onNewMeasurement(current: zoomed, loaded: loaded, saved: saved) == nil)
    }

    @Test func wideningWhileShowingTheLoad_remembersTheWidenedRange() {
        var widened = loaded; widened.maxFreq = 1100
        #expect(DisplayRange.loadedAfterWidening(loaded: loaded, before: loaded, after: widened) == widened)
    }

    @Test func wideningAfterTheUserMovedTheChart_keepsTheLoadedRange() {
        var widened = zoomed; widened.maxFreq = 1100
        #expect(DisplayRange.loadedAfterWidening(loaded: loaded, before: zoomed, after: widened) == loaded)
    }
}
