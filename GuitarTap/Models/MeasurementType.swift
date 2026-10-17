//
//  MeasurementType.swift
//  GuitarTap
//
//  Created on 1/25/26.
//
// @parity model/measurement-type tests=test/measurement-type-name

/// The kind of tap tone measurement being performed.
///
/// Guitar types (`.classical`, `.flamenco`, `.acoustic`, `.generic`) use guitar-body mode
/// classification (air, top, back, dipole, ring).  Material types (`.plate`,
/// `.brace`) use a multi-tap capture sequence and compute Young's modulus.
///
/// - SeeAlso: ``GuitarType`` for the guitar-specific subtype with frequency range definitions.
import Foundation

enum MeasurementType: String, Codable, CaseIterable, Identifiable {
    /// Broad ranges covering all guitar types — useful when the instrument does not
    /// fit neatly into one of the three specific types, or for initial exploration.
    case generic = "Generic Guitar"
    case acoustic = "Acoustic Guitar"
    case classical = "Classical Guitar"
    case flamenco = "Flamenco Guitar"
    case plate = "Material (Plate)"
    case brace = "Material (Brace)"

    var id: String { rawValue }

    /// Short name for display in compact UI contexts.
    var shortName: String {
        switch self {
        case .classical: return "Classical"
        case .flamenco: return "Flamenco"
        case .acoustic: return "Acoustic"
        case .generic: return "Generic"
        case .plate: return "Plate"
        case .brace: return "Brace"
        }
    }

    /// Human-readable description of the measurement type.
    var description: String {
        switch self {
        case .classical:
            return "Nylon string, fan-braced, deep body"
        case .flamenco:
            return "Nylon string, light bracing, shallow body"
        case .acoustic:
            return "Steel string, X-braced (Dreadnought, OM, etc.)"
        case .generic:
            return "Broad ranges covering all guitar types"
        case .plate:
            return "Rectangular wood plate for calculating stiffness and sound radiation"
        case .brace:
            return "Brace strip — measures longitudinal stiffness (fL only)"
        }
    }

    /// Whether this is a guitar measurement (as opposed to a plate or brace material measurement).
    var isGuitar: Bool {
        switch self {
        case .classical, .flamenco, .acoustic, .generic:
            return true
        case .plate, .brace:
            return false
        }
    }

    /// Whether this is a brace measurement (single longitudinal tap only).
    var isBrace: Bool {
        switch self {
        case .brace: return true
        default: return false
        }
    }

    /// The corresponding ``GuitarType``, or `nil` for plate/brace measurements.
    var guitarType: GuitarType? {
        switch self {
        case .classical: return .classical
        case .flamenco: return .flamenco
        case .acoustic: return .acoustic
        case .generic: return .generic
        case .plate, .brace: return nil
        }
    }

    /// Creates a ``MeasurementType`` from a ``GuitarType``.
    static func from(_ guitarType: GuitarType) -> MeasurementType {
        switch guitarType {
        case .classical: return .classical
        case .flamenco: return .flamenco
        case .acoustic: return .acoustic
        case .generic: return .generic
        }
    }
}
