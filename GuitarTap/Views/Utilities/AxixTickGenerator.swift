/// # AxisTickGenerator
///
/// Generates human-readable axis tick marks for frequency spectrum charts on a
/// linear scale.
///
/// ## Linear tick generation
///
/// `generateTicks(min:max:maxTicks:)` uses a \"nice number\" algorithm that
/// snaps the computed tick interval to the nearest value in {1, 2, 5} × 10ⁿ,
/// guaranteeing evenly spaced labels that are easy to read regardless of zoom level.
///
/// ## Label formatting
///
/// `formatTickLabels(_:)` returns a dictionary mapping each tick value to
/// its display string, automatically increasing decimal precision until all labels
/// in the set are unique (preventing e.g. two ticks both labelled \"1.0 kHz\").
///
/// - SeeAlso: `SpectrumView`, `ExportableSpectrumChart`
// @parity view/axis-ticks tests=test/axis-ticks
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - AxisTickGenerator

/// Generates tick mark positions and formatted labels for spectrum chart axes.
struct AxisTickGenerator {

    // MARK: - Main Generation Method

    /// Generates tick marks for a given data range.
    ///
    /// - Parameters:
    ///   - min: Lower bound of the visible range (Hz).
    ///   - max: Upper bound of the visible range (Hz).
    ///   - maxTicks: Approximate maximum number of ticks to generate.  Defaults to 10.
    /// - Returns: An array of tick positions in ascending order.
    static func generateTicks(
        min: Double,
        max: Double,
        maxTicks: Int = 10
    ) -> [Double] {
        guard min < max else { return [min] }
        return generateLinearTicks(min: min, max: max, maxTicks: maxTicks)
    }

    /// The magnitude axis's tick spacing (dB) for a visible range of `range` dB: the smallest of 1, 2, 5, 10, 20
    /// and 50 that gives no more than 8 ticks.
    static func magnitudeStride(range: Double) -> Double {
        for stride in [1.0, 2.0, 5.0, 10.0, 20.0, 50.0] where range / stride <= 8 {
            return stride
        }
        return 50.0
    }

    // MARK: - Linear Scale

    /// Generates evenly-spaced tick positions using the \"nice number\" algorithm.
    ///
    /// The raw interval `range / (maxTicks - 1)` is passed to `getNiceNumber`
    /// (with `round: false`) to snap it to the nearest {1, 2, 5} × 10ⁿ value.
    /// The axis bounds are then extended outward to the nearest multiples of that
    /// interval so tick values are always round numbers.
    ///
    /// - Parameters:
    ///   - min: Lower bound of the range (Hz).
    ///   - max: Upper bound of the range (Hz).
    ///   - maxTicks: Approximate maximum number of tick marks.
    /// - Returns: Tick positions in ascending order.
    private static func generateLinearTicks(
        min: Double,
        max: Double,
        maxTicks: Int
    ) -> [Double] {
        let range = max - min

        if range == 0 {
            return [min]
        }

        // Calculate rough spacing
        let roughSpacing = range / Double(maxTicks - 1)

        // Find "nice" spacing: round up to {1, 2, 5} × 10ⁿ
        let niceSpacing = getNiceNumber(roughSpacing, round: false)

        // Extend axis bounds outward to nice multiples
        let niceMin = floor(min / niceSpacing) * niceSpacing
        let niceMax = ceil(max / niceSpacing) * niceSpacing

        // Enumerate tick marks
        var ticks: [Double] = []
        var currentTick = niceMin

        // Small tolerance (1% of interval) handles floating-point drift at the upper bound
        while currentTick <= niceMax + niceSpacing * 0.01 {
            ticks.append(currentTick)
            currentTick += niceSpacing
        }

        return ticks
    }

    // MARK: - Nice Number Utility

    /// Rounds `x` to the nearest \"nice\" value ({1, 2, 5} × 10ⁿ).
    ///
    /// When `round` is `true` the result is the *nearest* nice number;
    /// when `false` it is rounded *up* (ceiling) to the next nice number.
    ///
    /// - Parameters:
    ///   - x: The value to round.
    ///   - round: `true` for nearest, `false` for ceiling.
    /// - Returns: A nice number ≥ `x` (when `round` is `false`).
    private static func getNiceNumber(_ x: Double, round: Bool) -> Double {
        let exponent = floor(log10(x))
        let fraction = x / pow(10, exponent)

        let niceFraction: Double
        if round {
            if fraction < 1.5 {
                niceFraction = 1
            } else if fraction < 3 {
                niceFraction = 2
            } else if fraction < 7 {
                niceFraction = 5
            } else {
                niceFraction = 10
            }
        } else {
            if fraction <= 1 {
                niceFraction = 1
            } else if fraction <= 2 {
                niceFraction = 2
            } else if fraction <= 5 {
                niceFraction = 5
            } else {
                niceFraction = 10
            }
        }

        return niceFraction * pow(10, exponent)
    }

    // MARK: - Formatting

    /// The frequency ticks' labels — the same on screen and in the exported image: whole hertz below 1 kHz and
    /// thousands with a k above (`1.2k`), the axis title carrying the unit, as charts conventionally do; with more
    /// decimals until every label is different.
    static func formatTickLabels(_ values: [Double]) -> [Double: String] {
        guard !values.isEmpty else { return [:] }
        for extraDecimals in 0...3 {
            var labels: [Double: String] = [:]
            for value in values {
                labels[value] = formatFrequencyLabel(value, thousandsDecimals: 1 + extraDecimals)
            }
            if Set(labels.values).count == labels.count {
                return labels
            }
        }
        // Fallback: tenths of a hertz
        var labels: [Double: String] = [:]
        for value in values {
            labels[value] = String(format: "%.1f", value)
        }
        return labels
    }

    private static func formatFrequencyLabel(_ value: Double, thousandsDecimals: Int) -> String {
        value >= 1000 ? String(format: "%.\(thousandsDecimals)fk", value / 1000) : String(format: "%.0f", value)
    }

    /// The ticks whose label fits inside the plot. Each label is centred on its tick; one that would reach past
    /// the plot's left or right edge is left out, and its grid line stays. With no plot width yet, every label shows.
    static func ticksWithLabelRoom(_ labels: [Double: String], min: Double, max: Double,
                                   plotWidth: CGFloat, fontSize: CGFloat) -> Set<Double> {
        guard plotWidth > 0, max > min else { return Set(labels.keys) }
        let font = PlatformFont.systemFont(ofSize: fontSize)
        return Set(labels.filter { tick, label in
            let half = (label as NSString).size(withAttributes: [.font: font]).width / 2
            let x = (tick - min) / (max - min) * plotWidth
            return x - half >= 0 && x + half <= plotWidth
        }.keys)
    }
}
