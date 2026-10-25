//
//  SavedMeasurementMenu.swift
//  GuitarTap
//
// @parity view/saved-measurement-menu tests=test/saved-measurement-menu
//
// A saved measurement's menu — from its ⋯ or a right-click in Saved Measurements: what each item does, says and
// shows. The list builds the menu from these groups; the same groups are in every edition and in the shared
// saved-measurement-menu.json.

/// One item of a saved measurement's menu.
struct SavedMeasurementMenuEntry: Equatable {
    /// What the item does.
    enum Action: String {
        case load, details, edit, exportMeasurement, saveToDisk, exportSpectrum, exportPDF, delete
    }

    let action: Action
    let title: String
    let symbol: String
    /// The item only the Mac edition has.
    var macOSOnly = false
}

enum SavedMeasurementMenu {
    /// A saved measurement's menu, in the groups a separator divides. Save Measurement to Disk… is the Mac's only: it
    /// saves the file through a save dialog, which Export Measurement's share sheet does not offer there.
    static let groups: [[SavedMeasurementMenuEntry]] = [
        [
            SavedMeasurementMenuEntry(action: .load, title: "Load into View", symbol: "arrow.down.doc"),
        ],
        [
            SavedMeasurementMenuEntry(action: .details, title: "View Details", symbol: "eye"),
            SavedMeasurementMenuEntry(action: .edit, title: "Edit Name & Notes", symbol: "pencil"),
            SavedMeasurementMenuEntry(action: .exportMeasurement, title: "Export Measurement", symbol: "doc.badge.arrow.up"),
            SavedMeasurementMenuEntry(action: .saveToDisk, title: "Save Measurement to Disk…", symbol: "arrow.down.doc",
                                      macOSOnly: true),
            SavedMeasurementMenuEntry(action: .exportSpectrum, title: "Export Spectrum", symbol: "chart.line.uptrend.xyaxis"),
            SavedMeasurementMenuEntry(action: .exportPDF, title: "Export PDF Report", symbol: "doc.richtext"),
        ],
        [
            SavedMeasurementMenuEntry(action: .delete, title: "Delete", symbol: "trash"),
        ],
    ]
}
