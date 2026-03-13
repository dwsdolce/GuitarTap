//
//  GuitarMode.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

/// # GuitarMode
///
/// Guitar resonance mode classification using luthier-friendly terminology.
///
/// Each case represents one of the principal low-frequency resonances of a completed guitar body.
/// The frequency boundaries for each mode depend on the guitar type (classical, flamenco, acoustic)
/// and are defined in ``GuitarType/ModeRanges``.
///
/// ## Mode Map (classical / flamenco defaults)
///
/// | Mode | Approx. range | Physical description |
/// |------|--------------|----------------------|
/// | Air  | 80–200 Hz    | Helmholtz air resonance of the sound-hole cavity |
/// | Top  | 170–260 Hz   | Main monopole resonance of the top plate |
/// | Back | 210–310 Hz   | Main monopole resonance of the back plate |
/// | Dipole | 280–420 Hz | T(1,2) anti-symmetric bending mode |
/// | Ring Mode | 380–550 Hz | Higher structural mode |
/// | Upper Modes | 500–1 000 Hz | Cluster of higher-order modes |
///
/// ## Legacy Cases
///
/// Four legacy raw values are retained for backward compatibility with measurements saved
/// under older naming conventions.  They are mapped to their modern equivalents by
/// ``normalized`` and ``displayName``.
import Foundation

/// A resonance mode classification for a completed guitar body.
///
/// Use ``classify(frequency:)`` or ``classify(frequency:guitarType:)`` to map a detected
/// peak frequency to the appropriate mode.  The ``normalized`` property converts any legacy
/// case to its modern equivalent for programmatic comparisons.
///
/// - SeeAlso: ``GuitarType`` for the frequency-band definitions used during classification.
/// - SeeAlso: ``UserAssignedMode`` for overriding the displayed label without changing the mode.
enum GuitarMode: String, Codable {

    // MARK: - Current Cases

    /// Helmholtz resonance of the air cavity, combined with the coupled air/top mode.
    ///
    /// Corresponds to T(1,1)₁ in the acoustic physics literature.
    case air = "Air (Helmholtz)"

    /// Main top-plate monopole resonance (formerly called the long-grain mode).
    ///
    /// Corresponds to T(1,1)₂.
    case top = "Top"

    /// Main back-plate monopole resonance (formerly called the monopole mode).
    ///
    /// Corresponds to T(1,1)₃.
    case back = "Back"

    /// Anti-symmetric dipole bending mode, T(1,2).
    case dipole = "Dipole"

    /// Higher structural ring mode.
    case ringMode = "Ring Mode"

    /// Cluster of higher-order modes above the ring mode.
    case upperModes = "Upper Modes"

    /// Frequency falls outside all defined mode ranges.
    case unknown = "Unknown"

    // MARK: - Legacy Cases (Backward Compatibility)

    /// Legacy name for the ``air`` mode.
    ///
    /// - Warning: This case exists only for decoding measurements saved under the old naming
    ///   convention.  Use ``air`` for all new code.  ``normalized`` maps this to `.air`.
    case helmholtz = "Helmholtz (Air)"

    /// Legacy name for the ``air`` mode (cross-grain coupling variant).
    ///
    /// - Warning: Retained for backward compatibility only.  ``normalized`` maps this to `.air`.
    case crossGrain = "Cross-Grain"

    /// Legacy name for the ``top`` mode.
    ///
    /// - Warning: Retained for backward compatibility only.  ``normalized`` maps this to `.top`.
    case longGrain = "Long-Grain"

    /// Legacy name for the ``back`` mode.
    ///
    /// - Warning: Retained for backward compatibility only.  ``normalized`` maps this to `.back`.
    case monopole = "Monopole"

    // MARK: - Classification

    /// Classifies a frequency into a guitar mode using the currently selected guitar type.
    ///
    /// The guitar type is read from ``TapDisplaySettings/guitarType`` at call time.
    ///
    /// - Parameter frequency: The peak frequency to classify, in Hz.
    /// - Returns: The ``GuitarMode`` whose ``GuitarType/ModeRanges`` band contains `frequency`,
    ///   or ``unknown`` if no band matches.
    static func classify(frequency: Float) -> GuitarMode {
        return classify(frequency: frequency, guitarType: TapDisplaySettings.guitarType)
    }

    /// Classifies a frequency into a guitar mode for a specific guitar type.
    ///
    /// - Parameters:
    ///   - frequency: The peak frequency to classify, in Hz.
    ///   - guitarType: The guitar type whose mode-range bands are used for classification.
    /// - Returns: The matching ``GuitarMode``, or ``unknown`` if no band matches.
    static func classify(frequency: Float, guitarType: GuitarType) -> GuitarMode {
        let ranges = guitarType.modeRanges

        switch frequency {
        case ranges.air:        return .air
        case ranges.top:        return .top
        case ranges.back:       return .back
        case ranges.dipole:     return .dipole
        case ranges.ringMode:   return .ringMode
        case ranges.upperModes: return .upperModes
        default:                return .unknown
        }
    }

    // MARK: - Frequency Ranges

    /// The ideal (target) frequency range for this mode using the current guitar type setting.
    ///
    /// - SeeAlso: ``idealRange(for:)`` for a guitar-type–specific variant.
    var idealRange: ClosedRange<Float> {
        return idealRange(for: TapDisplaySettings.guitarType)
    }

    /// The ideal (target) frequency range for this mode for a specific guitar type.
    ///
    /// Ideal ranges are the narrower "target" bands used for quality assessment, as opposed
    /// to the wider detection bands in ``GuitarType/ModeRanges`` which define what counts as
    /// belonging to a mode at all.
    ///
    /// - Parameter guitarType: The guitar type whose ideal-range table is consulted.
    /// - Returns: A closed range in Hz.  Returns `0...20000` for ``unknown`` and for
    ///   any unrecognised future cases.
    func idealRange(for guitarType: GuitarType) -> ClosedRange<Float> {
        let ranges = guitarType.idealRanges
        switch self.normalized {
        case .air:        return ranges.air
        case .top:        return ranges.top
        case .back:       return ranges.back
        case .dipole:     return ranges.dipole
        case .ringMode:   return ranges.ringMode
        case .upperModes: return ranges.upperModes
        case .unknown:    return 0...20000
        default:          return 0...20000
        }
    }

    // MARK: - Display

    /// The human-readable mode name shown in the UI.
    ///
    /// All legacy cases are mapped to their modern display string so that measurements
    /// saved under the old naming convention render correctly after an upgrade.
    var displayName: String {
        switch self {
        case .air, .helmholtz, .crossGrain: return "Air (Helmholtz)"
        case .top, .longGrain:              return "Top"
        case .back, .monopole:              return "Back"
        case .dipole:                       return "Dipole"
        case .ringMode:                     return "Ring Mode"
        case .upperModes:                   return "Upper Modes"
        case .unknown:                      return "Unknown"
        }
    }

    // MARK: - Normalisation

    /// Converts any legacy case to its current equivalent for programmatic comparisons.
    ///
    /// Use this property whenever you need to compare two `GuitarMode` values for semantic
    /// equality, since e.g. `.helmholtz == .air` is `false` as raw-value enums but
    /// `.helmholtz.normalized == .air.normalized` is `true`.
    ///
    /// Current cases are returned unchanged.
    var normalized: GuitarMode {
        switch self {
        case .helmholtz, .crossGrain: return .air
        case .longGrain:              return .top
        case .monopole:               return .back
        default:                      return self
        }
    }
}
