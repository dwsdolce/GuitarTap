/// # AxisTickGenerator
///
/// Generates human-readable axis tick marks for frequency spectrum charts,
/// supporting both linear and logarithmic scales.
///
/// ## Linear tick generation
///
/// `generateTicks(min:max:maxTicks:scale:)` uses a \"nice number\" algorithm that
/// snaps the computed tick interval to the nearest value in {1, 2, 5} × 10ⁿ,
/// guaranteeing evenly spaced labels that are easy to read regardless of zoom level.
///
/// ## Logarithmic tick generation
///
/// In logarithmic mode, ticks are placed at decade boundaries (powers of the base).
/// When the visible range spans many decades a stride is applied so the count
/// stays within `maxTicks`; `generateLogMinorTicks` provides the 2–9× sub-decade
/// positions for denser grids.
///
/// ## Label formatting
///
/// `formatTickLabels(_:scale:)` returns a dictionary mapping each tick value to
/// its display string, automatically increasing decimal precision until all labels
/// in the set are unique (preventing e.g. two ticks both labelled \"1.0 kHz\").
///
/// - SeeAlso: `SpectrumView`, `ExportableSpectrumChart`
import Foundation

// MARK: - Axis Scale

/// Describes the scale type used for tick generation.
///
/// Pass an `AxisScale` to `AxisTickGenerator.generateTicks(min:max:maxTicks:scale:)`
/// to control whether ticks are placed at linearly or logarithmically spaced
/// positions.
enum AxisScale {
    /// Linear (evenly spaced) axis scale.
    case linear
    /// Logarithmic axis scale. The associated value is the logarithm base;
    /// defaults to 10 for standard audio frequency displays.
    ///
    /// Call as `AxisScale.logarithmic()` to use the default base-10 scale,
    /// or `AxisScale.logarithmic(base: 2)` for a binary logarithm.
    case logarithmic(base: Double = 10)
}

// MARK: - AxisTickGenerator

/// Generates tick mark positions and formatted labels for spectrum chart axes.
struct AxisTickGenerator {

    // MARK: - Main Generation Method

    /// Generates tick marks for a given data range with the specified scale.
    ///
    /// - Parameters:
    ///   - min: Lower bound of the visible range (Hz).
    ///   - max: Upper bound of the visible range (Hz).
    ///   - maxTicks: Approximate maximum number of ticks to generate.  Defaults to 10.
    ///   - scale: The axis scale (`.linear` or `.logarithmic(base:)`).
    /// - Returns: An array of tick positions in ascending order.
    static func generateTicks(
        min: Double,
        max: Double,
        maxTicks: Int = 10,
        scale: AxisScale = .linear
    ) -> [Double] {
        guard min < max else { return [min] }

        switch scale {
        case .linear:
            return generateLinearTicks(min: min, max: max, maxTicks: maxTicks)
        case .logarithmic(let base):
            return generateLogTicks(min: min, max: max, maxTicks: maxTicks, base: base)
        }
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

    // MARK: - Logarithmic Scale

    /// Generates tick positions at powers of `base` within the given range.
    ///
    /// When the range spans more decades than `maxTicks`, a stride is applied so
    /// only every Nth decade is labelled.
    ///
    /// - Parameters:
    ///   - min: Lower bound of the range (Hz). Must be positive.
    ///   - max: Upper bound of the range (Hz). Must be positive.
    ///   - maxTicks: Approximate maximum tick count.
    ///   - base: Logarithm base (typically 10).
    /// - Returns: Tick positions in ascending order.
    private static func generateLogTicks(
        min: Double,
        max: Double,
        maxTicks: Int,
        base: Double
    ) -> [Double] {
        guard min > 0 && max > 0 else {
            print("Warning: Logarithmic scale requires positive values")
            return generateLinearTicks(min: Swift.max(min, 0.001), max: max, maxTicks: maxTicks)
        }

        let logMin = log(min) / log(base)
        let logMax = log(max) / log(base)
        let logRange = logMax - logMin

        if logRange <= Double(maxTicks) {
            // Range fits within maxTicks — use every decade boundary
            return generateMajorLogTicks(min: min, max: max, base: base)
        } else {
            // Range is too wide — skip decades so the count stays reasonable
            return generateSparseMajorLogTicks(
                min: min,
                max: max,
                base: base,
                maxTicks: maxTicks
            )
        }
    }

    /// Returns one tick per decade boundary (power of `base`) within `[min, max]`.
    private static func generateMajorLogTicks(
        min: Double,
        max: Double,
        base: Double
    ) -> [Double] {
        let logMin = log(min) / log(base)
        let logMax = log(max) / log(base)

        let startDecade = floor(logMin)
        let endDecade = ceil(logMax)

        var ticks: [Double] = []
        var decade = startDecade

        while decade <= endDecade {
            let value = pow(base, decade)
            if value >= min && value <= max {
                ticks.append(value)
            }
            decade += 1
        }

        return ticks
    }

    /// Returns decade-boundary ticks with a stride large enough to stay within
    /// `maxTicks` when many decades are visible.
    private static func generateSparseMajorLogTicks(
        min: Double,
        max: Double,
        base: Double,
        maxTicks: Int
    ) -> [Double] {
        let logMin = log(min) / log(base)
        let logMax = log(max) / log(base)

        let startDecade = floor(logMin)
        let endDecade = ceil(logMax)
        let decadeCount = Int(endDecade - startDecade)

        // Stride ensures the total tick count is ≤ maxTicks
        let stride = Swift.max(1, Int(ceil(Double(decadeCount) / Double(maxTicks))))

        var ticks: [Double] = []
        var decade = startDecade

        while decade <= endDecade {
            let value = pow(base, decade)
            if value >= min && value <= max {
                ticks.append(value)
            }
            decade += Double(stride)
        }

        return ticks
    }

    /// Generates minor (sub-decade) tick positions for logarithmic axes.
    ///
    /// For each decade in the range, ticks are placed at 2×, 3×, … (base−1)×
    /// the decade value. These are typically rendered as unlabelled hairlines
    /// between the major decade labels.
    ///
    /// - Parameters:
    ///   - min: Lower bound of the range (Hz). Must be positive.
    ///   - max: Upper bound of the range (Hz). Must be positive.
    ///   - base: Logarithm base (typically 10).
    /// - Returns: Minor tick positions in ascending order.
    static func generateLogMinorTicks(
        min: Double,
        max: Double,
        base: Double = 10
    ) -> [Double] {
        guard min > 0 && max > 0 else { return [] }

        let logMin = log(min) / log(base)
        let logMax = log(max) / log(base)

        let startDecade = floor(logMin)
        let endDecade = ceil(logMax)

        var ticks: [Double] = []
        var decade = startDecade

        while decade <= endDecade {
            let decadeValue = pow(base, decade)

            // Add intermediate values: 2×, 3×, … (base−1)×
            for multiplier in 2..<Int(base) {
                let value = decadeValue * Double(multiplier)
                if value >= min && value <= max {
                    ticks.append(value)
                }
            }

            decade += 1
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
    ///   - scale: The axis scale, used to select the appropriate format.
    ///   - precision: Optional override for decimal places.
    /// - Returns: A human-readable label string.
    static func formatTickLabel(
        _ value: Double,
        scale: AxisScale = .linear,
        precision: Int? = nil
    ) -> String {
        switch scale {
        case .linear:
            return formatLinearLabel(value, precision: precision)
        case .logarithmic(let base):
            return formatLogLabel(value, base: base, precision: precision)
        }
    }

    /// Formats a set of tick values together, automatically increasing precision
    /// when the default formatting produces duplicate labels (e.g. two ticks both
    /// showing \"1.2 kHz\" in a narrow zoom window).
    ///
    /// - Parameters:
    ///   - values: The tick values to format (Hz).
    ///   - scale: The axis scale (linear or logarithmic).
    /// - Returns: A dictionary mapping each tick value to its label string.
    static func formatTickLabels(_ values: [Double], scale: AxisScale = .linear) -> [Double: String] {
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

    /// Formats a logarithmic-scale tick value.
    ///
    /// Values that are exact powers of `base` are shown as `"10^n"` (or `"1"`,
    /// `"10"` for small exponents). Other values fall back to compact numeric
    /// notation.
    ///
    /// - Parameters:
    ///   - value: The tick value.
    ///   - base: The logarithm base.
    ///   - precision: Optional override for decimal places.
    /// - Returns: A label string appropriate for a logarithmic axis.
    private static func formatLogLabel(_ value: Double, base: Double, precision: Int?) -> String {
        let logValue = log(value) / log(base)
        let isPowerOfBase = abs(logValue - round(logValue)) < 0.0001

        if isPowerOfBase && base == 10 {
            let exponent = Int(round(logValue))
            if exponent == 0 {
                return "1"
            } else if exponent == 1 {
                return "10"
            } else {
                return "10^\(exponent)"
            }
        } else if isPowerOfBase {
            let exponent = Int(round(logValue))
            return "\(Int(base))^\(exponent)"
        } else {
            if let precision = precision {
                return String(format: "%.\(precision)f", value)
            }
            if value >= 1 {
                return String(format: "%.0f", value)
            } else {
                return String(format: "%.2f", value)
            }
        }
    }
}
