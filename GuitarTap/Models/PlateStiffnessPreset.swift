//
//  PlateStiffnessPreset.swift
//  GuitarTap
//
//  Created on 1/25/26.
//
// @parity model/material-measurement-inputs

/// Named vibrational stiffness (f_vs) presets for Gore Equation 4.5-7.
///
/// The Gore target thickness formula requires a vibrational stiffness
/// parameter that varies by instrument type and plate role.  The `.custom`
/// case defers to the `TapDisplaySettings.customPlateStiffness` value.
///
/// Reference values (f_vs):
/// - Steel-string top: 75
/// - Steel-string back: 55
/// - Classical top: 60
/// - Classical back: 50
///
/// - SeeAlso: ``PlateProperties/goreTargetThickness(bodyLengthMm:bodyWidthMm:vibrationalStiffness:)``
import Foundation

enum PlateStiffnessPreset: String, CaseIterable, Identifiable, Codable {
    case steelStringTop = "Steel String Top"
    case steelStringBack = "Steel String Back"
    case classicalTop = "Classical Top"
    case classicalBack = "Classical Back"
    case custom = "Custom"

    var id: String { rawValue }

    /// The vibrational stiffness value (f_vs) for this preset.
    ///
    /// Returns `0` for `.custom`; callers should use `TapDisplaySettings.customPlateStiffness`
    /// in that case (or `TapDisplaySettings.plateStiffness` which handles the fallback automatically).
    var value: Float {
        switch self {
        case .steelStringTop:  return 75
        case .steelStringBack: return 55
        case .classicalTop:    return 60
        case .classicalBack:   return 50
        case .custom:          return 0
        }
    }

    /// Compact name used in the settings picker.
    var shortName: String {
        switch self {
        case .steelStringTop:  return "SS Top (75)"
        case .steelStringBack: return "SS Back (55)"
        case .classicalTop:    return "Classical Top (60)"
        case .classicalBack:   return "Classical Back (50)"
        case .custom:          return "Custom"
        }
    }
}
