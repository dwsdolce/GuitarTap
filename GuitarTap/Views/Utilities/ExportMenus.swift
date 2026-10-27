//
//  ExportMenus.swift
//  GuitarTap
//
// @parity view/export-menus tests=test/export-menus
//
// The two menus besides a saved measurement's own that export or share: Saved Measurements' library menu and
// Analysis Results'. Each is one button whose word and items depend on the platform — on the Mac, Export with its
// Share… and Export… items; on iOS and iPadOS, Share with its Share items — the same in every edition and in the
// shared export-menus.json. The types here also carry a saved measurement's menu (`SavedMeasurementMenu`).

/// The platforms Swift's menus differ on.
enum MenuPlatform: CaseIterable {
    case mac, ios

    /// The platform this build runs on.
    static var current: MenuPlatform {
        #if os(macOS)
        .mac
        #else
        .ios
        #endif
    }
}

/// One item of a menu as a platform shows it.
struct MenuEntry<Action: Hashable>: Equatable {
    let action: Action
    let title: String
    /// Its SF Symbol; nil for an item drawn without an icon.
    let symbol: String?
}

/// One item of a menu on every platform: its words on each, or none where the item is not on that platform's menu.
struct MenuItemDefinition<Action: Hashable> {
    let action: Action
    let mac: String?
    let ios: String?
    var symbol: String? = nil

    func entry(for platform: MenuPlatform) -> MenuEntry<Action>? {
        let title = platform == .mac ? mac : ios
        return title.map { MenuEntry(action: action, title: $0, symbol: symbol) }
    }
}

/// A menu's groups as `platform` shows them: its items only, and no group left empty.
func menuGroups<Action>(_ groups: [[MenuItemDefinition<Action>]], for platform: MenuPlatform) -> [[MenuEntry<Action>]] {
    groups.map { $0.compactMap { $0.entry(for: platform) } }.filter { !$0.isEmpty }
}

/// A menu behind one button: the button's word on each platform, its icon, and its items' groups.
struct ExportMenu<Action: Hashable> {
    let mac: String
    let ios: String
    let symbol: String
    let groups: [[MenuItemDefinition<Action>]]

    func button(for platform: MenuPlatform) -> String { platform == .mac ? mac : ios }

    func entries(for platform: MenuPlatform) -> [[MenuEntry<Action>]] { menuGroups(groups, for: platform) }
}

enum ExportMenus {
    /// What an item of Saved Measurements' library menu does.
    enum PanelAction: String {
        case shareAll, shareSelected, exportAll, exportSelected
    }

    /// What an item of Analysis Results' menu does.
    enum ResultsAction: String {
        case shareSpectrum, sharePDF, exportSpectrum, exportPDF
    }

    /// Saved Measurements' library menu. Its items have icons as the Delete menu's do: Share's, Export's, and
    /// Selected's tick.
    static let panel = ExportMenu<PanelAction>(
        mac: "Export", ios: "Share", symbol: "square.and.arrow.up",
        groups: [
            [
                MenuItemDefinition(action: .exportAll, mac: "Export All…", ios: nil, symbol: "doc.badge.arrow.up"),
                MenuItemDefinition(action: .exportSelected, mac: "Export Selected…", ios: nil, symbol: "checkmark.circle"),
            ],
            [
                MenuItemDefinition(action: .shareAll, mac: "Share All…", ios: "Share All", symbol: "square.and.arrow.up"),
                MenuItemDefinition(action: .shareSelected, mac: "Share Selected…", ios: "Share Selected",
                                   symbol: "checkmark.circle"),
            ],
        ]
    )

    /// Analysis Results' menu: a saved measurement's menu's items for the spectrum and the report, with their icons.
    static let analysisResults = ExportMenu<ResultsAction>(
        mac: "Export", ios: "Share", symbol: "square.and.arrow.up",
        groups: [
            [
                MenuItemDefinition(action: .exportSpectrum, mac: "Export Spectrum…", ios: nil,
                                   symbol: "chart.line.uptrend.xyaxis"),
                MenuItemDefinition(action: .exportPDF, mac: "Export PDF Report…", ios: nil, symbol: "doc.richtext"),
            ],
            [
                MenuItemDefinition(action: .shareSpectrum, mac: "Share Spectrum…", ios: "Share Spectrum",
                                   symbol: "chart.line.uptrend.xyaxis"),
                MenuItemDefinition(action: .sharePDF, mac: "Share PDF Report…", ios: "Share PDF Report",
                                   symbol: "doc.richtext"),
            ],
        ]
    )
}
