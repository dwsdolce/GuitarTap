//
//  GuitarModeExtensions.swift
//  GuitarTap
//
//  Created by David Smith on 2/9/26.
//
import SwiftUI

extension GuitarMode {
    var color: Color {
        switch self {
        case .helmholtz: return .cyan
        case .crossGrain: return .blue
        case .longGrain: return .green
        case .monopole: return .orange
        case .dipole: return .red
        case .ringMode: return .purple
        case .upperModes: return .gray
        case .unknown: return .secondary
        }
    }
    
    var icon: String {
        switch self {
        case .helmholtz: return "wind"
        case .crossGrain: return "arrow.left.and.right"
        case .longGrain: return "arrow.up.and.down"
        case .monopole: return "circle.fill"
        case .dipole: return "circle.lefthalf.filled"
        case .ringMode: return "circle.dashed"
        case .upperModes: return "waveform"
        case .unknown: return "questionmark.circle"
        }
    }
}
