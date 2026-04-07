// MARK: - AnnotationVisibilityMode

/// Controls which peak annotations are rendered on the spectrum chart.
///
/// This is a transient display preference — it does not affect which peaks are stored
/// in ``TapToneAnalyzer/selectedPeakIDs`` or exported in measurements.
///
/// - SeeAlso: ``TapToneAnalyzer/cycleAnnotationVisibility()`` to advance through the cycle.
enum AnnotationVisibilityMode: String, Codable, CaseIterable {

    /// Render annotations for every detected peak.
    case all

    /// Render annotations only for peaks the user has marked as selected results.
    case selected

    /// Render no annotations.
    case none

    /// The next mode in the cycle: `all → selected → none → all`.
    var next: AnnotationVisibilityMode {
        switch self {
        case .all:      return .selected
        case .selected: return .none
        case .none:     return .all
        }
    }

    /// SF Symbols icon name representing this visibility state.
    var iconName: String {
        switch self {
        case .all:      return "eye"
        case .selected: return "star.fill"
        case .none:     return "eye.slash"
        }
    }

    /// Short display label for toolbar buttons and pickers.
    var label: String {
        switch self {
        case .all:      return "All"
        case .selected: return "Selected"
        case .none:     return "None"
        }
    }
}
