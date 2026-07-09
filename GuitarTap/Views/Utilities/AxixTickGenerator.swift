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
import Foundation

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

    /// Formats a single tick value as a display string.
    ///
    /// - Parameters:
    ///   - value: The tick value to format.
    ///   - precision: Optional override for decimal places.
    /// - Returns: A human-readable label string.
    static func formatTickLabel(
        _ value: Double,
        precision: Int? = nil
    ) -> String {
        formatLinearLabel(value, precision: precision)
    }

    /// Formats a set of tick values together, automatically increasing precision
    /// when the default formatting would produce duplicate labels (e.g. two ticks both
    /// showing \"1.2 kHz\" in a narrow zoom window).
    ///
    /// - Parameters:
    ///   - values: The tick values to format (Hz).
    /// - Returns: A dictionary mapping each tick value to its label string.
    static func formatTickLabels(_ values: [Double]) -> [Double: String] {
        guard !values.isEmpty else { return [:] }

        // Try formatting with increasing decimal places until all labels are unique.
        // For values < 1000 Hz we use plain Hz; for >= 1000 Hz we use kHz.
        for extraDecimals in 0...3 {
            var labels: [Double: String] = [:]
            for value in values {
                labels[value] = formatFrequencyLabel(value, kHzDecimals: 1 + extraDecimals)
            }
            let labelValues = Array(labels.values)
            if Set(labelValues).count == labelValues.count {
                return labels
            }
        }

        // Fallback: use raw Hz with full precision
        var labels: [Double: String] = [:]
        for value in values {
            labels[value] = String(format: "%.1f Hz", value)
        }
        return labels
    }

    /// Formats a single frequency value (Hz) with the specified number of decimal
    /// places for the kHz representation (e.g. `kHzDecimals: 1` → \"1.2 kHz\").
    /// Values below 1000 Hz are always shown in whole Hz.
    private static func formatFrequencyLabel(_ value: Double, kHzDecimals: Int) -> String {
        if value >= 1000 {
            return String(format: "%.\(kHzDecimals)f kHz", value / 1000)
        } else {
            return String(format: "%.0f Hz", value)
        }
    }

    /// Formats a linear-scale tick value using compact notation.
    ///
    /// - Values ≥ 1000: shown as `"1.2k"` (one decimal, k suffix).
    /// - Values ≥ 10: shown as whole numbers.
    /// - Values ≥ 0.1: shown with one decimal place.
    /// - Smaller values: shown with two decimal places.
    ///
    /// - Parameters:
    ///   - value: The tick value.
    ///   - precision: Optional override for decimal places.
    /// - Returns: A compact label string.
    private static func formatLinearLabel(_ value: Double, precision: Int?) -> String {
        if let precision = precision {
            return String(format: "%.\(precision)f", value)
        }

        let absValue = abs(value)
        if absValue == 0 {
            return "0"
        } else if absValue >= 1000 {
            return String(format: "%.1fk", value / 1000)
        } else if absValue >= 10 {
            return String(format: "%.0f", value)
        } else if absValue >= 0.1 {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
}