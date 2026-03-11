//
//  UserAssignedMode.swift
//  GuitarTap
//
//  Represents a user's optional override of the auto-detected GuitarMode label for a peak.
//

import Foundation

/// Represents whether a peak's mode label is auto-detected or manually overridden by the user.
///
/// The underlying `GuitarMode` classification (used for color, icon, and range checks) is
/// never altered — only the displayed text string can be overridden.
///
/// - Note: **Label stability caveat.** `.assigned` labels are stored as literal strings in JSON
///   and are fully stable across app versions. `.auto` labels are *not* stored — they are
///   re-evaluated at display time by calling `GuitarMode.classify(frequency:)`. This means
///   that if classification boundaries change in a future version, a saved peak with `.auto`
///   may display a different mode name than it did when the measurement was recorded.
///   Peaks that sit near a boundary (e.g. ~195 Hz Air/Top boundary) are most at risk.
///   If long-term label stability is required, assign an explicit label via `.assigned`.
enum UserAssignedMode: Codable, Equatable, Hashable {

    /// Use the auto-detected label from `GuitarMode.classify(frequency:)`.
    /// See stability caveat in the type-level documentation above.
    case auto

    /// Show the user-supplied string instead of the auto-detected label.
    case assigned(String)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, label
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .auto:
            try container.encode("auto", forKey: .type)
        case .assigned(let label):
            try container.encode("assigned", forKey: .type)
            try container.encode(label, forKey: .label)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "assigned":
            let label = try container.decode(String.self, forKey: .label)
            self = .assigned(label)
        default:
            self = .auto
        }
    }

    // MARK: - Suggestion Lists

    /// Standard guitar tap-tone mode labels (matches GuitarMode.displayName values).
    static let guitarTapModes: [String] = [
        "Air (Helmholtz)", "Top", "Back", "Dipole", "Ring Mode", "Upper Modes", "Unknown"
    ]

    /// Additional mode labels for extended analysis.
    static let additionalModes: [String] = [
        "Helmholtz T(1,1)_1", "Top T(1,1)_2", "Back T(1,1)_3", "Cross Dipole T(2,1)", "Long Dipole T(1,2)", "Quadrapole T(2,2)", "Cross Tripole T(3,1)"
    ]

    /// All suggestion strings presented in the picker Menu.
    static var allSuggestions: [String] { guitarTapModes + additionalModes }
}
