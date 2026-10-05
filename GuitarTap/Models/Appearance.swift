//
//  Appearance.swift
//  GuitarTap
//
// @parity model/appearance tests=test/theme
//
// The Appearance setting — follow the operating system, or always Light, or always Dark — and the scheme it
// resolves to. Every colour the app draws is chosen by the resolved scheme.

import Foundation

/// The colour scheme the app is drawn in.
enum Scheme: String, CaseIterable {
    case light, dark
}

/// The user's Appearance setting.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    /// The label shown in Settings.
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// The scheme drawn when the operating system reports `os` (`nil` when it reports none): the setting when
    /// Light or Dark, else the operating system's, with none taken as Light.
    func resolved(os: Scheme?) -> Scheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return os ?? .light
        }
    }
}
