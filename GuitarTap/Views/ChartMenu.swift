//
//  ChartMenu.swift
//  GuitarTap
//
// @parity view/chart-menu tests=test/chart-menu
//
// The chart's menu — from its ⋯ and from a right-click, on every device — and a peak label's own menu: what each
// item does, says and shows. The views build their menus from these lists; the same lists are in every edition and
// in the shared chart-menu.json.

/// One item of the chart's menu, or of a peak label's.
struct ChartMenuEntry: Equatable {
    /// What the item does.
    enum Action: String {
        case resetBothToSaved, resetFrequencyToSaved, resetMagnitudeToSaved
        case resetBothToDefaults, resetFrequencyToDefaults, resetMagnitudeToDefaults
        case resetBothToComparison, resetFrequencyToComparison, resetMagnitudeToComparison
        case resetLabels, resetPosition
    }

    let action: Action
    let title: String
    let symbol: String
}

enum ChartMenu {
    /// The chart's menu, in the groups a separator divides. "Reset Labels" can act only while a label has been moved.
    static let groups: [[ChartMenuEntry]] = [
        [
            ChartMenuEntry(action: .resetBothToSaved, title: "Reset Both Axes to Saved", symbol: "arrow.counterclockwise"),
            ChartMenuEntry(action: .resetFrequencyToSaved, title: "Reset Frequency Axis to Saved", symbol: "arrow.counterclockwise"),
            ChartMenuEntry(action: .resetMagnitudeToSaved, title: "Reset Magnitude Axis to Saved", symbol: "arrow.counterclockwise"),
        ],
        [
            ChartMenuEntry(action: .resetBothToDefaults, title: "Reset Both Axes to Defaults", symbol: "arrow.counterclockwise.circle"),
            ChartMenuEntry(action: .resetFrequencyToDefaults, title: "Reset Frequency Axis to Defaults", symbol: "arrow.counterclockwise.circle"),
            ChartMenuEntry(action: .resetMagnitudeToDefaults, title: "Reset Magnitude Axis to Defaults", symbol: "arrow.counterclockwise.circle"),
        ],
        [
            ChartMenuEntry(action: .resetLabels, title: "Reset Labels", symbol: "arrow.uturn.backward"),
        ],
    ]

    /// The chart's menu while a comparison measurement is shown, in place of ``groups``: Settings' range and the
    /// app's defaults mean nothing for measurements of many guitars, so it resets to the comparison range — the span
    /// of the compared measurements' saved views, the range a comparison opens at.
    static let comparisonGroups: [[ChartMenuEntry]] = [
        [
            ChartMenuEntry(action: .resetBothToComparison, title: "Reset Both Axes to Comparison Range", symbol: "arrow.counterclockwise"),
            ChartMenuEntry(action: .resetFrequencyToComparison, title: "Reset Frequency Axis to Comparison Range", symbol: "arrow.counterclockwise"),
            ChartMenuEntry(action: .resetMagnitudeToComparison, title: "Reset Magnitude Axis to Comparison Range", symbol: "arrow.counterclockwise"),
        ],
    ]

    /// A peak label's menu: it can act only while the label has been moved.
    static let labelMenu: [ChartMenuEntry] = [
        ChartMenuEntry(action: .resetPosition, title: "Reset Position", symbol: "arrow.counterclockwise"),
    ]
}
