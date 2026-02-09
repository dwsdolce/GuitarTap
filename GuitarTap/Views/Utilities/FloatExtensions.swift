//
//  FloatExtensions.swift
//  GuitarTap
//
//  Created by David Smith on 2/9/26.
//

import SwiftUI

extension Float {
    var tapToneRatioQuality: String {
        switch self {
        case 1.9...2.1: return "Excellent"
        case 1.7...1.9, 2.1...2.3: return "Good"
        case 1.5...1.7, 2.3...2.5: return "Fair"
        default: return "Needs Adjustment"
        }
    }
    
    var tapToneRatioQualityColor: Color {
        switch self {
        case 1.9...2.1: return .green
        case 1.7...1.9, 2.1...2.3: return .blue
        case 1.5...1.7, 2.3...2.5: return .orange
        default: return .red
        }
    }
    
    var decayQuality: String {
        switch self {
        case 0..<0.5: return "Very Short"
        case 0.5..<1.0: return "Short"
        case 1.0..<2.0: return "Good"
        case 2.0..<3.0: return "Excellent"
        default: return "Very Long"
        }
    }
    
    var decayQualityColor: Color {
        switch self {
        case 0..<0.5: return .red
        case 0.5..<1.0: return .orange
        case 1.0..<2.0: return .green
        case 2.0..<3.0: return .blue
        default: return .purple
        }
    }
    
    func formattedAsFrequency() -> String {
        if self >= 1000 {
            return String(format: "%.1fk Hz", self / 1000)
        } else {
            return String(format: "%.0f Hz", self)
        }
    }
}
