//
//  GuitarMode.swift
//  GuitarTap
//
//  Created on 1/25/26.
//
// @parity dsp/guitar-modes tests=test/classify
// @parity model/guitar-mode-classify tests=test/classify
// @parity model/mode-colors tests=test/mode-colors

/// # GuitarMode
///
/// Guitar resonance mode classification using luthier-friendly terminology.
///
/// Each case represents one of the principal low-frequency resonances of a completed guitar body.
/// The frequency boundaries for each mode depend on the guitar type (classical, flamenco, acoustic)
/// and are defined in ``GuitarType/ModeRanges``.
///
/// ## Mode Map (approximate detection ranges, guitar-type-dependent)
///
/// | Mode | Generic (default) | Classical | Flamenco | Acoustic | Physical description |
/// |------|-------------------|-----------|----------|----------|----------------------|
/// | Air  | 70–135 Hz | 80–110 Hz | 85–115 Hz | 90–120 Hz | Helmholtz air resonance of the sound-hole cavity |
/// | Top  | 140–260 Hz | 170–230 Hz | 180–220 Hz | 150–210 Hz | Main monopole resonance of the top plate |
/// | Back | 180–300 Hz | 190–280 Hz | 200–250 Hz | 210–290 Hz | Main monopole resonance of the back plate |
/// | Dipole | 310–460 Hz | 330–430 Hz | 350–450 Hz | 360–460 Hz | T(1,2) anti-symmetric bending mode |
/// | Ring Mode | 580–880 Hz | 580–820 Hz | 600–850 Hz | 620–880 Hz | Higher structural mode |
/// | Upper Modes | 880+ Hz | 820+ Hz | 850+ Hz | 880+ Hz | Cluster of higher-order modes |
///
/// Exact boundaries are defined in ``GuitarType/modeRanges``.
///
/// ## Legacy Cases
///
/// Four legacy raw values are retained for backward compatibility with measurements saved
/// under older naming conventions.  They are mapped to their modern equivalents by
/// ``normalized`` and ``displayName``.
import SwiftUI

/// A resonance mode classification for a completed guitar body.
///
/// Use ``classifyAll(_:guitarType:)`` to map detected peaks to the appropriate modes.  The
/// ``normalized`` property converts any legacy
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

    // MARK: - Current Case Enumeration

    /// All current (non-legacy) cases in display order.
    ///
    /// Use this instead of `CaseIterable` to exclude the legacy backward-compatibility cases
    /// from pickers, suggestion lists, and anywhere the full canonical set is needed.
    static let currentCases: [GuitarMode] = [.air, .top, .back, .dipole, .ringMode, .upperModes, .unknown]

    /// Extended mode label strings using acoustical physics (T(m,n)) notation.
    ///
    /// Presented as secondary choices in the mode-override picker for users who prefer
    /// the academic designation system over the luthier-friendly names in ``currentCases``.
    static let additionalModeLabels: [String] = [
        "Helmholtz T(1,1)_1", "Top T(1,1)_2", "Back T(1,1)_3",
        "Cross Dipole T(2,1)", "Long Dipole T(1,2)", "Quadrapole T(2,2)", "Cross Tripole T(3,1)"
    ]

    // MARK: - Classification

    /// Classifies a frequency into a guitar mode for a specific guitar type.
    ///
    /// - Parameters:
    ///   - frequency: The peak frequency to classify, in Hz.
    ///   - guitarType: The guitar type whose mode-range bands are used for classification.
    /// - Returns: The matching ``GuitarMode``, or ``unknown`` if no band matches.
    private static func classify(frequency: Float, guitarType: GuitarType) -> GuitarMode {
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

    /// Classifies a set of peaks into guitar modes using a context-aware claiming algorithm.
    ///
    /// Unlike `classify(frequency:guitarType:)`, which maps each frequency independently,
    /// this method processes all peaks together so that overlapping mode ranges (e.g. the
    /// Top/Back overlap zone for classical guitar) resolve correctly: the first peak
    /// claimed by a lower-frequency mode cannot be re-claimed by a higher-frequency mode.
    ///
    /// **Algorithm:**
    /// 1. Sorts the canonical modes (Air, Top, Back, Dipole, Ring, Upper) by ascending
    ///    lower-bound of their frequency range for the given guitar type.
    /// 2. For each mode in that order, picks the highest-magnitude unclaimed peak whose
    ///    frequency lies within the mode's range, then marks that peak as claimed.
    ///    Back is additionally constrained to lie strictly above the claimed Top
    ///    frequency (the back plate resonance is always higher than the top plate's),
    ///    so an overlapping Back range cannot claim a peak below Top.
    /// 3. Any remaining unclaimed peaks are classified via the per-frequency
    ///    `classify(frequency:guitarType:)` lookup — except that a peak above the
    ///    claimed Top frequency and within the Back range resolves to `.back` (not the
    ///    earlier/lower mode the switch would pick), preserving the Top-below-Back
    ///    ordering. Peaks outside all mode ranges resolve to `.unknown`.
    ///
    /// - Parameters:
    ///   - peaks: The detected peaks to classify.
    ///   - guitarType: The guitar type whose mode-range bands are used. Defaults to
    ///     ``TapDisplaySettings/guitarType`` when omitted.
    /// - Returns: A dictionary mapping each peak's `UUID` to its ``GuitarMode``.
    static func classifyAll(
        _ peaks: [ResonantPeak],
        guitarType: GuitarType = TapDisplaySettings.guitarType
    ) -> [UUID: GuitarMode] {
        let orderedModes: [GuitarMode] = [.air, .top, .back, .dipole, .ringMode, .upperModes]
            .sorted { $0.modeRange(for: guitarType).lowerBound < $1.modeRange(for: guitarType).lowerBound }

        var result: [UUID: GuitarMode] = [:]
        var claimedIDs = Set<UUID>()
        // Track the frequency of the claimed Top peak so Back is constrained to be above it.
        // Physically, the back plate resonance is always higher in frequency than the top plate
        // resonance. Without this guard, Back can claim a peak lower than Top when the two
        // mode ranges overlap (which they do for all guitar types, and especially for Generic).
        var claimedTopFrequency: Float? = nil

        for mode in orderedModes {
            let range = mode.modeRange(for: guitarType)

            // Back must be strictly above the already-claimed Top frequency.
            let effectiveLowerBound: Float
            if mode == .back, let topFreq = claimedTopFrequency {
                effectiveLowerBound = max(range.lowerBound, topFreq + 1.0)
            } else {
                effectiveLowerBound = range.lowerBound
            }

            if let best = peaks
                .filter({
                    $0.frequency >= effectiveLowerBound
                    && range.contains($0.frequency)
                    && !claimedIDs.contains($0.id)
                })
                .max(by: { $0.magnitude < $1.magnitude }) {
                result[best.id] = mode
                claimedIDs.insert(best.id)
                if mode == .top {
                    claimedTopFrequency = best.frequency
                }
            }
        }

        // Classify any unclaimed peaks using the standard per-frequency lookup.
        // Special case: if Top was already claimed, peaks in the Top/Back overlap
        // zone that are above the claimed Top frequency should be classified as
        // Back rather than Top.  The naive classify(frequency:) checks Top before
        // Back, so without this guard overlap-zone peaks always land on Top.
        for peak in peaks where result[peak.id] == nil {
            if let topFreq = claimedTopFrequency {
                let backRange = GuitarMode.back.modeRange(for: guitarType)
                if peak.frequency > topFreq && backRange.contains(peak.frequency) {
                    result[peak.id] = .back
                    continue
                }
            }
            result[peak.id] = classify(frequency: peak.frequency, guitarType: guitarType)
        }

        return result
    }

    /// Returns `true` if `frequency` falls within any named mode range for the given guitar type.
    ///
    /// Use this for filtering peaks by visibility (the "hide unknown modes" setting) instead of
    /// calling `classify(frequency:guitarType:)` and comparing against `.unknown`. This avoids
    /// any ambiguity around the overlap zone: a frequency in the Top/Back overlap is always
    /// "known" regardless of which mode `classifyAll` ultimately assigns it to.
    ///
    /// - Parameters:
    ///   - frequency: The peak frequency to test, in Hz.
    ///   - guitarType: The guitar type whose mode-range bands are used.
    static func isKnown(frequency: Float, guitarType: GuitarType = TapDisplaySettings.guitarType) -> Bool {
        let r = guitarType.modeRanges
        return r.air.contains(frequency) || r.top.contains(frequency) || r.back.contains(frequency)
            || r.dipole.contains(frequency) || r.ringMode.contains(frequency) || r.upperModes.contains(frequency)
    }

    /// The peaks the chart draws a **dot** for: every peak inside the visible frequency range,
    /// **independent of annotation-visibility mode and of peak selection**.
    ///
    /// This is the "dot list" (the always-visible layer), deliberately NOT the annotation list:
    /// ``TapToneAnalyzer/visiblePeaks`` narrows by `AnnotationVisibilityMode` (all / selected /
    /// none) and drives the badges, while every peak in range keeps its dot regardless. Gating dots
    /// on the annotation mode is a bug — it shipped on the web once, where dots followed the
    /// selection — which is why this rule now carries a paired 3-platform test.
    ///
    /// **A peak the user has named is known.** The unknown-mode filter is positional —
    /// ``isKnown(frequency:guitarType:)``, *does the frequency fall in a band* — **except** for peaks
    /// carrying a manual mode label, which are always kept. Pass those in `overriddenPeakIDs`.
    ///
    /// The positional test alone is equivalent to the analyzer's assigned-mode test for every peak
    /// *without* an override, because ``classifyAll(_:guitarType:)`` falls back to a per-frequency
    /// lookup for peaks its one-per-mode claiming pass did not take. The two differ only under a
    /// user override.
    ///
    /// - Note: This function previously applied the positional test unconditionally, on the argument
    ///   that a chart layer should be positional. That was wrong: it discarded the user's own
    ///   identification, so a peak labelled "Wolf note" lost its table row while keeping its dot (or
    ///   lost both, if it sat outside every band). One predicate now governs the results table, this
    ///   dot layer and the annotation badges — see ``TapToneAnalyzer/isUnknown(_:)``, of which this
    ///   is the static, analyzer-free form.
    ///
    /// Callers pass the **display/viewport** range, which follows pan and zoom — not the analysis
    /// range used by peak detection.
    ///
    /// - Parameters:
    ///   - peaks: Candidate peaks (typically the current/frozen peak set).
    ///   - minFreq: Low edge of the visible frequency range, in Hz (inclusive).
    ///   - maxFreq: High edge of the visible frequency range, in Hz (inclusive).
    ///   - isGuitar: Whether this is a guitar measurement; material types skip the unknown filter.
    ///   - showUnknownModes: When `true`, in-range peaks outside every band are kept.
    ///   - overriddenPeakIDs: Peaks the user has given a manual mode label. Kept regardless of
    ///     position. A `Set` rather than a closure or an analyzer reference so this stays static and
    ///     pure, and ports to Python and TypeScript unchanged.
    ///   - guitarType: The guitar type whose mode-range bands are used.
    /// - Returns: The in-range peaks, input order preserved.
    static func peaksInDisplayRange(
        _ peaks: [ResonantPeak],
        minFreq: Float,
        maxFreq: Float,
        isGuitar: Bool,
        showUnknownModes: Bool,
        overriddenPeakIDs: Set<UUID> = [],
        guitarType: GuitarType = TapDisplaySettings.guitarType
    ) -> [ResonantPeak] {
        let inRange = peaks.filter { $0.frequency >= minFreq && $0.frequency <= maxFreq }
        guard isGuitar, !showUnknownModes else { return inRange }
        return inRange.filter {
            overriddenPeakIDs.contains($0.id)
                || isKnown(frequency: $0.frequency, guitarType: guitarType)
        }
    }

    // MARK: - Frequency Ranges

    /// The classification frequency range for this mode using the current guitar type setting.
    ///
    /// - SeeAlso: ``modeRange(for:)`` for a guitar-type–specific variant.
    var modeRange: ClosedRange<Float> {
        return modeRange(for: TapDisplaySettings.guitarType)
    }

    /// The classification frequency range for this mode for a specific guitar type.
    ///
    /// - Parameter guitarType: The guitar type whose ``GuitarType/modeRanges`` table is consulted.
    /// - Returns: A closed range in Hz.  Returns `0...20000` for ``unknown`` and for
    ///   any unrecognised future cases.
    func modeRange(for guitarType: GuitarType) -> ClosedRange<Float> {
        let ranges = guitarType.modeRanges
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
// MARK: - Display Properties

extension GuitarMode {

    /// Display colour for a guitar mode, as an absolute sRGB hex, derived from `self.normalized`.
    ///
    /// Legacy enum cases are collapsed to their canonical equivalents via `normalized` first, so
    /// all historical variants of e.g. `.air` share one colour.
    ///
    /// ## Why absolute, and not `.cyan` / `.green` / `.orange` / …
    ///
    /// These were SwiftUI's semantic system colours until the #17 sweep, for the same reason
    /// `WoodQuality.color` was, and with the same consequence: a semantic colour is resolved by the
    /// OS, so what GuitarTap draws moves when Apple revises the palette, and a port pinning hex
    /// cannot follow. The values below are what this app rendered on macOS 26; they are now fixed,
    /// and Python carries the same table.
    ///
    /// The hue is not meaningful — it only has to tell seven modes apart and be the same in every
    /// edition. The web keeps its own brightened variants where its dark chart genuinely needs
    /// them (Top, Back, Dipole, and the two greys) and follows these values where the difference
    /// was never about the background (Air, Ring). See SLUG-SWEEP.md F9.
    var hex: String {
        switch self.normalized {
        case .air:        return "#00C0E8"
        case .top:        return "#34C759"
        case .back:       return "#FF8D28"
        case .dipole:     return "#FF383C"
        case .ringMode:   return "#CB30E0"
        case .upperModes: return "#8E8E93"
        case .unknown:    return "#808080"
        default:          return "#808080"
        }
    }

    /// Display colour for a guitar mode. Derived from ``hex`` so there is one place the value lives.
    ///
    /// `.unknown` was `.secondary` — black at 50% alpha, which composites to `#808080` on the
    /// white chart. It is now that value outright, so it no longer changes with what is behind it.
    var color: Color { Color(sRGBHex: hex) }

    /// Short mode abbreviation for compact UI display (e.g., "Air", "DP").
    var abbreviation: String {
        switch self.normalized {
        case .air:        return "Air"
        case .top:        return "Top"
        case .back:       return "Back"
        case .dipole:     return "DP"
        case .ringMode:   return "Ring"
        case .upperModes: return "Upper"
        case .unknown:    return "?"
        default:          return "?"
        }
    }

    /// Human-readable description of the acoustic mode, suitable for tooltips and detail views.
    var description: String {
        switch self.normalized {
        case .air:        return "Air resonance (Helmholtz) - the 'breathing' of the guitar body"
        case .top:        return "Main top plate resonance"
        case .back:       return "Back plate resonance"
        case .dipole:     return "Top plate moving out of phase (dipole)"
        case .ringMode:   return "Higher frequency body resonances"
        case .upperModes: return "Upper harmonic modes"
        case .unknown:    return "Unclassified frequency"
        default:          return "Unclassified frequency"
        }
    }

    /// SF Symbols name representing this guitar mode visually.
    var icon: String {
        switch self.normalized {
        case .air:        return "wind"
        case .top:        return "arrow.up.and.down"
        case .back:       return "square.fill"
        case .dipole:     return "circle.lefthalf.filled"
        case .ringMode:   return "circle.dashed"
        case .upperModes: return "waveform"
        case .unknown:    return "questionmark.circle"
        default:          return "questionmark.circle"
        }
    }

    // MARK: - User-Defined Mode Styling

    /// Display color for peaks with a freeform user-defined mode label
    /// that does not match any predefined ``GuitarMode``.
    static let userDefinedColor: Color = .teal

    /// SF Symbols icon for peaks with a freeform user-defined mode label.
    static let userDefinedIcon: String = "tag.fill"

    // MARK: - Reverse Lookup

    /// Returns the ``GuitarMode`` whose ``displayName`` matches the given string,
    /// or `nil` if no predefined mode matches.
    ///
    /// Checks both ``currentCases`` display names (e.g. "Back") and
    /// ``additionalModeLabels`` (e.g. "Cross Dipole T(2,1)").
    ///
    /// - Parameter name: A display-name string, typically from a ``UserAssignedMode/assigned(_:)`` label.
    static func fromDisplayName(_ name: String) -> GuitarMode? {
        // Check canonical display names first.
        if let match = currentCases.first(where: { $0.displayName == name }) {
            return match
        }
        // Additional mode labels map to specific modes by convention.
        let additionalMap: [String: GuitarMode] = [
            "Helmholtz T(1,1)_1": .air,
            "Top T(1,1)_2":       .top,
            "Back T(1,1)_3":      .back,
            "Cross Dipole T(2,1)": .dipole,
            "Long Dipole T(1,2)": .dipole,
            "Quadrapole T(2,2)":  .ringMode,
            "Cross Tripole T(3,1)": .ringMode,
        ]
        return additionalMap[name]
    }

    /// The **effective** mode of a peak: a user override wins over auto-classification.
    ///
    /// The single definition of "what mode is this peak, really." A resolvable override label
    /// (one that ``fromDisplayName(_:)`` recognises) yields that mode; a freeform label yields
    /// ``unknown`` (the user named it something that is not a mode); with no override the
    /// auto-classified `auto` value stands.
    ///
    /// Every surface that answers "which peak is the Air / Top / Back" routes through this so they
    /// cannot disagree: the analyzer's ``TapToneAnalyzer/peakMode(for:)``, the saved
    /// ``TapToneMeasurement``'s ratio and per-tap resolution, and the static
    /// ``TapToneAnalyzer/resolvedModePeaks(peaks:overrides:guitarType:)``.
    static func effectiveMode(override: UserAssignedMode?, auto: GuitarMode) -> GuitarMode {
        if case .assigned(let label) = override {
            return GuitarMode.fromDisplayName(label) ?? .unknown
        }
        return auto
    }
}

