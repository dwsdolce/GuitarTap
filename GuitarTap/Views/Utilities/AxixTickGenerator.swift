import Foundation

enum AxisScale {
    case linear
    case logarithmic(base: Double = 10)
}

struct AxisTickGenerator {
    
    // MARK: - Main Generation Method
    
    /// Generates tick marks for a given data range with specified scale
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
        
        // Find "nice" spacing
        let niceSpacing = getNiceNumber(roughSpacing, round: false)
        
        // Calculate nice bounds
        let niceMin = floor(min / niceSpacing) * niceSpacing
        let niceMax = ceil(max / niceSpacing) * niceSpacing
        
        // Generate tick marks
        var ticks: [Double] = []
        var currentTick = niceMin
        
        while currentTick <= niceMax + niceSpacing * 0.01 { // Small tolerance for floating point
            ticks.append(currentTick)
            currentTick += niceSpacing
        }
        
        return ticks
    }
    
    // MARK: - Logarithmic Scale
    
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
        
        // Determine if we should use major ticks only or include minor ticks
        if logRange <= Double(maxTicks) {
            // Use decade markers (powers of base)
            return generateMajorLogTicks(min: min, max: max, base: base)
        } else {
            // Use subset of decades
            return generateSparseMajorLogTicks(
                min: min,
                max: max,
                base: base,
                maxTicks: maxTicks
            )
        }
    }
    
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
        
        // Calculate stride to fit within maxTicks
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
    
    /// Generate minor tick marks for logarithmic scale (2, 3, 4, ... 9 between decades)
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
            
            // Add intermediate values (2x, 3x, 4x, ... 9x)
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
    
    private static func formatLinearLabel(_ value: Double, precision: Int?) -> String {
        if let precision = precision {
            return String(format: "%.\(precision)f", value)
        }
        
        let absValue = abs(value)
        if absValue == 0 {
            return "0"
        } else if absValue >= 1000 {
            return String(format: "%.1fk", value/1000)
        } else if absValue >= 10 {
            return String(format: "%.0f", value)
        } else if absValue >= 0.1 {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    private static func formatLogLabel(_ value: Double, base: Double, precision: Int?) -> String {
        // Check if value is a power of base
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
            // For minor ticks, use compact notation
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
