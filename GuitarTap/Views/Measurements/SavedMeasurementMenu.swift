//
//  SavedMeasurementMenu.swift
//  GuitarTap
//
// @parity view/saved-measurement-menu tests=test/saved-measurement-menu
//
// A saved measurement's menu — from its ⋯, a right-click or a long press in Saved Measurements: what each item does,
// says and shows on each platform. The list builds the menu from these groups; the same groups are in every edition
// and in the shared saved-measurement-menu.json.

/// What an item of a saved measurement's menu does.
enum SavedMeasurementAction: String {
    case load, details, edit
    case shareMeasurement, shareSpectrum, sharePDF
    case exportMeasurement, exportSpectrum, exportPDF
    case delete
}

/// One item of a saved measurement's menu as a platform shows it.
typealias SavedMeasurementMenuEntry = MenuEntry<SavedMeasurementAction>

enum SavedMeasurementMenu {
    /// The menu on every platform, in the groups a separator divides. Share opens the share sheet; Export writes the
    /// file through a save dialog, which only the Mac has — on iOS and iPadOS saving is the share sheet's Save to
    /// Files. "…" as style guide S9: on the Mac, not on iOS.
    static let definition: [[MenuItemDefinition<SavedMeasurementAction>]] = [
        [
            MenuItemDefinition(action: .load, mac: "Load into View", ios: "Load into View", symbol: "arrow.down.doc"),
        ],
        [
            MenuItemDefinition(action: .details, mac: "View Details", ios: "View Details", symbol: "eye"),
            MenuItemDefinition(action: .edit, mac: "Edit Name & Notes", ios: "Edit Name & Notes", symbol: "pencil"),
        ],
        [
            MenuItemDefinition(action: .exportMeasurement, mac: "Export Measurement…", ios: nil,
                               symbol: "doc.badge.arrow.up"),
            MenuItemDefinition(action: .exportSpectrum, mac: "Export Spectrum…", ios: nil,
                               symbol: "chart.line.uptrend.xyaxis"),
            MenuItemDefinition(action: .exportPDF, mac: "Export PDF Report…", ios: nil, symbol: "doc.richtext"),
        ],
        [
            MenuItemDefinition(action: .shareMeasurement, mac: "Share Measurement…", ios: "Share Measurement",
                               symbol: "doc.badge.arrow.up"),
            MenuItemDefinition(action: .shareSpectrum, mac: "Share Spectrum…", ios: "Share Spectrum",
                               symbol: "chart.line.uptrend.xyaxis"),
            MenuItemDefinition(action: .sharePDF, mac: "Share PDF Report…", ios: "Share PDF Report",
                               symbol: "doc.richtext"),
        ],
        [
            MenuItemDefinition(action: .delete, mac: "Delete", ios: "Delete", symbol: "trash"),
        ],
    ]

    /// The menu as `platform` shows it.
    static func groups(for platform: MenuPlatform) -> [[SavedMeasurementMenuEntry]] {
        menuGroups(definition, for: platform)
    }

    /// The menu as this build shows it.
    static var groups: [[SavedMeasurementMenuEntry]] { groups(for: .current) }
}
