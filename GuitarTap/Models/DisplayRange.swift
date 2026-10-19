//
//  DisplayRange.swift
//  GuitarTap
//
//  The rule for widening the chart's frequency axis so a newly identified peak is visible.
//
// @parity presentation/display-range tests=test/display-range,test/comparison

import Foundation

/// How the displayed frequency range grows to reveal a peak that falls outside it.
///
/// A plate or brace identifies fL / fC / fFLC by scanning a wide band (brace: 100–1200 Hz), and the
/// display range is per-measurement-type and persisted — so the peak a measurement just produced
/// can easily land off the edge of the chart. When that happens the chart's range widens to show it;
/// the saved range is not changed.
enum DisplayRange {

    /// Ten percent of the peak's frequency, so the peak is not flush against the axis edge.
    static let paddingFraction: Float = 0.10

    // MARK: - The chart's limits — one set for Settings, zoom, pan and widening

    /// The frequencies the chart may show. Above 5 kHz there is no useful tap-tone data.
    static let frequencyBounds: ClosedRange<Float> = 1...5000

    /// The magnitudes the chart may show (dB).
    static let magnitudeBounds: ClosedRange<Float> = -120...20

    /// The narrowest frequency range the chart may show (Hz); a range exactly this wide is allowed.
    static let minFrequencySpan: Float = 10

    /// The narrowest magnitude range the chart may show (dB); a range exactly this wide is allowed.
    static let minMagnitudeSpan: Float = 10

    /// The lowest frequency the axis may show.
    static var floorHz: Float { frequencyBounds.lowerBound }

    /// `(minFreq, maxFreq)` widened so `frequency` is inside it, or unchanged if it already was.
    ///
    /// Only ever widens — a peak near the middle of the range leaves it alone, and a range is never
    /// narrowed to fit, because that would hide peaks the user is already looking at.
    static func expanded(
        toInclude frequency: Float,
        min minFreq: Float,
        max maxFreq: Float
    ) -> (min: Float, max: Float) {
        let padding = frequency * paddingFraction
        var lo = minFreq
        var hi = maxFreq
        if frequency > hi { hi = Swift.min(frequencyBounds.upperBound, frequency + padding) }
        if frequency < lo { lo = Swift.max(floorHz, frequency - padding) }
        return (lo, hi)
    }

    /// The chart range to show once a peak at `frequency` is identified: for a plate or brace, widened
    /// onto it (``expanded(toInclude:min:max:)``); unchanged for a guitar — a guitar's range is the
    /// user's analysis window and is not widened for them — and for a peak restored by a load, which
    /// shows the range it was saved with.
    static func widened(
        onto frequency: Float,
        for type: MeasurementType,
        fromLoad: Bool,
        min minFreq: Float,
        max maxFreq: Float
    ) -> (min: Float, max: Float) {
        guard !type.isGuitar, !fromLoad else { return (minFreq, maxFreq) }
        return expanded(toInclude: frequency, min: minFreq, max: maxFreq)
    }

    // MARK: - When the chart's range moves
    //
    // The chart's range is each measurement type's saved view to start with, and moves only when the
    // user moves it, when the app must show something (a loaded measurement's range; a newly
    // identified plate or brace peak), or on a measurement-type switch. These are the decisions the
    // view applies.

    /// The chart's four bounds. Codable as a saved comparison's `comparisonRange`, with the keys a
    /// spectrum snapshot gives its range.
    struct ChartRange: Equatable, Codable {
        var minFreq: Float
        var maxFreq: Float
        var minDB: Float
        var maxDB: Float
    }

    /// The chart range when Settings is closed with Done: the saved range if it changed, or if the
    /// measurement type changed (the chart moves to that type's saved view); `nil` — the chart stays
    /// where it is — otherwise.
    static func onSettingsDone(saved: ChartRange, previouslySaved: ChartRange, typeChanged: Bool) -> ChartRange? {
        typeChanged || saved != previouslySaved ? saved : nil
    }

    /// The chart range when a new measurement starts (New Tap, Play File): the saved range if the chart
    /// is still showing a loaded measurement's range (`loaded`, as widened) — the user has not moved it
    /// since the load; `nil` — the chart stays where it is — otherwise.
    static func onNewMeasurement(current: ChartRange, loaded: ChartRange?, saved: ChartRange) -> ChartRange? {
        loaded != nil && current == loaded ? saved : nil
    }

    /// The loaded range to remember after the chart widens onto a peak: the widened range if the chart
    /// was showing the loaded range (widening is the app, not the user); unchanged otherwise.
    static func loadedAfterWidening(loaded: ChartRange?, before: ChartRange, after: ChartRange) -> ChartRange? {
        loaded != nil && before == loaded ? after : loaded
    }

    /// The value of a Settings range field when Done is pressed: the stored value, exactly, if the field
    /// still shows it (`text` is its display at `decimals`) — an untouched field never rounds what was
    /// saved; otherwise the number typed, or `nil` if it is not a number.
    static func enteredValue(_ text: String, stored: Float, decimals: Int) -> Float? {
        text == FieldPrecision.string(stored, decimals) ? stored : Float(text)
    }

    /// The indices of the spectrum points to draw for `[minFreq, maxFreq]` (`frequencies` ascending):
    /// every point inside it plus the one just beyond each edge, so the segments that cross an edge are
    /// drawn and the plot area clips them — the line reaches both edges.
    static func drawnIndices(of frequencies: [Float], min minFreq: Float, max maxFreq: Float) -> Range<Int> {
        let firstInside = frequencies.firstIndex(where: { $0 >= minFreq }) ?? frequencies.count
        let firstBeyond = frequencies.firstIndex(where: { $0 > maxFreq }) ?? frequencies.count
        let lo = Swift.max(0, firstInside - 1)
        let hi = Swift.min(frequencies.count, firstBeyond + 1)
        return lo < hi ? lo..<hi : lo..<lo
    }

    /// The range that spans every one of `snapshots` — the lowest of their lower bounds and the highest of
    /// their upper ones — or nil for none. A comparison with no range of its own shows this, and a saved
    /// comparison's or multi-tap's image from the measurements list spans its spectra.
    static func spanning(_ snapshots: [SpectrumSnapshot]) -> ChartRange? {
        guard let minFreq = snapshots.map(\.minFreq).min(), let maxFreq = snapshots.map(\.maxFreq).max(),
              let minDB = snapshots.map(\.minDB).min(), let maxDB = snapshots.map(\.maxDB).max() else { return nil }
        return ChartRange(minFreq: minFreq, maxFreq: maxFreq, minDB: minDB, maxDB: maxDB)
    }

    /// One zoom step of an axis `[lo, hi]` about `anchor` (`scale` > 1 zooms in), kept within `bounds`:
    /// the new range, or nil — the step is refused — if it would leave the range narrower than `minSpan`.
    static func zoomed(_ lo: Float, _ hi: Float, about anchor: Float, scale: Float,
                       within bounds: ClosedRange<Float>, minSpan: Float) -> (lo: Float, hi: Float)? {
        let newLo = Swift.max(bounds.lowerBound, anchor - (anchor - lo) / scale)
        let newHi = Swift.min(bounds.upperBound, anchor + (hi - anchor) / scale)
        return newHi - newLo >= minSpan ? (newLo, newHi) : nil
    }

    /// An axis `[lo, hi]` moved by `delta`, kept within `bounds`: a move past a bound stops there, the
    /// span kept.
    static func panned(_ lo: Float, _ hi: Float, by delta: Float,
                       within bounds: ClosedRange<Float>) -> (lo: Float, hi: Float) {
        var newLo = lo + delta
        var newHi = hi + delta
        if newLo < bounds.lowerBound {
            newHi += bounds.lowerBound - newLo
            newLo = bounds.lowerBound
        }
        if newHi > bounds.upperBound {
            newLo -= newHi - bounds.upperBound
            newHi = bounds.upperBound
        }
        return (Swift.max(bounds.lowerBound, newLo), Swift.min(bounds.upperBound, newHi))
    }
}

