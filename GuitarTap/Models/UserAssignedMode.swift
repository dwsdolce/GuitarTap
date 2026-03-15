//
//  UserAssignedMode.swift
//  GuitarTap
//
//  Represents a user's optional override of the auto-detected GuitarMode label for a peak.
//

/// # UserAssignedMode
///
/// Controls whether a peak's displayed mode label comes from the automatic ``GuitarMode``
/// classifier or from a user-supplied string.
///
/// The underlying ``GuitarMode`` classification — which governs the peak's colour, icon, and
/// in-range indicator — is **never** altered by a `UserAssignedMode` override; only the text
/// shown in the annotation and results table is changed.
///
/// ## Persistence
///
/// `.auto` is serialised as `{"type":"auto"}`.  `.assigned` is serialised as
/// `{"type":"assigned","label":"<user string>"}`.  The custom label is therefore a stable,
/// version-independent string stored in the measurement JSON.
///
/// ## Label Stability
///
/// `.assigned` labels are literal strings and survive app updates unchanged.  `.auto` labels
/// are **re-evaluated at display time** by calling ``GuitarMode/classify(frequency:)``, so
/// they may change if classification boundaries shift in a future release.  Peaks near a
/// boundary (e.g. the ~195 Hz Air/Top boundary) carry the highest risk of reclassification.
/// For long-term stability, prefer `.assigned`.
import Foundation

/// Represents whether a peak's mode label is auto-detected or manually overridden by the user.
///
/// The underlying ``GuitarMode`` classification (used for colour, icon, and frequency-range
/// checks) is never altered — only the displayed text string can be overridden.
///
/// - SeeAlso: ``TapToneAnalyzer`` for the three-layer peak-selection system that consults this type.
enum UserAssignedMode: Codable, Equatable, Hashable {

    /// Use the auto-detected label produced by ``GuitarMode/classify(frequency:)`` at display time.
    ///
    /// - Warning: This label is not stored and may differ from what was shown when the measurement
    ///   was originally saved if classification boundaries change in a future app version.
    ///   Peaks near a mode boundary are most at risk.
    case auto

    /// Display the user-supplied string instead of the auto-detected label.
    ///
    /// The string is stored verbatim in the JSON measurement file and is fully stable
    /// across app versions.
    case assigned(String)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, label
    }

    /// Encodes the mode as `{"type":"auto"}` or `{"type":"assigned","label":"<string>"}`.
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

    /// Decodes from the keyed JSON format produced by ``encode(to:)``.
    ///
    /// Unknown `type` values are treated as `.auto` to maintain forward compatibility.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "assigned":
            let label = try container.decode(String.self, forKey: .label)
            self = .assigned(label)
        default:
            // Treat any unknown type string as .auto for forward compatibility.
            self = .auto
        }
    }

    // MARK: - Suggestion Lists

    /// Standard guitar tap-tone mode label strings, matching ``GuitarMode/displayName`` values.
    ///
    /// Presented as the primary choices in the mode-override picker.
    static let guitarTapModes: [String] = [
        "Air (Helmholtz)", "Top", "Back", "Dipole", "Ring Mode", "Upper Modes", "Unknown"
    ]

    /// Extended mode label strings using acoustical physics notation.
    ///
    /// Presented as secondary choices for users who prefer the T(m,n) mode designation system.
    static let additionalModes: [String] = [
        "Helmholtz T(1,1)_1", "Top T(1,1)_2", "Back T(1,1)_3",
        "Cross Dipole T(2,1)", "Long Dipole T(1,2)", "Quadrapole T(2,2)", "Cross Tripole T(3,1)"
    ]

    /// All suggestion strings presented in the override picker, combining ``guitarTapModes``
    /// and ``additionalModes``.
    static var allSuggestions: [String] { guitarTapModes + additionalModes }

    /// The longest predefined label string, used to size the mode label column in
    /// ``CombinedPeakModeRowView`` so it scales correctly with the system font.
    static let longestPredefinedLabel: String =
        allSuggestions.max(by: { $0.count < $1.count }) ?? "Air (Helmholtz)"
}
