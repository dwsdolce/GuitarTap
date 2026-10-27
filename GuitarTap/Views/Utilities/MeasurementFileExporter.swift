// @parity view/file-exporter tests=test/export-directory
/// # MeasurementFileExporter
///
/// Hands a file — a measurement file, a spectrum image, a PDF report — to the user, one of two ways:
///
/// | | macOS | iOS / iPadOS |
/// |---|---|---|
/// | ``FileDelivery/export`` | a save dialog (`NSSavePanel`); the file is written where the user chooses | — (saving is the share sheet's Save to Files) |
/// | ``FileDelivery/share`` | the share picker (`NSSharingServicePicker`: AirDrop, Mail, Messages…) | the share sheet (`UIActivityViewController`) |
///
/// To share, the file is written to a UUID-named folder in `FileManager.temporaryDirectory` under its own
/// name, so the destination receives the right name and extension. The multiple-instance problem that once
/// caused `-10814` LaunchServices failures is addressed by `handlesExternalEvents` in GuitarTapApp.
///
/// All completion handlers are called on the main thread.
///
/// - SeeAlso: `PDFReportGenerator`, `TapToneAnalysisView+Export`
import SwiftUI
internal import UniformTypeIdentifiers

/// Static helpers for exporting measurements, PDF reports, and spectrum images
/// to platform-appropriate destinations.
struct MeasurementFileExporter {

    // MARK: - Default Save Directory

    #if os(macOS)
    /// First-run starting directory for the export Save panel: the user's real
    /// `~/Documents/GuitarTap`.
    ///
    /// Resolved via `getpwuid(getuid())`, **not** `FileManager.homeDirectoryForCurrentUser` /
    /// `NSHomeDirectory()`, which under App Sandbox return the *container* home
    /// (`~/Library/Containers/…/Data`). The Save panel is a **powerbox** panel, so it may display and
    /// navigate a directory the app itself cannot read — the user's selection is what grants access.
    ///
    /// Does **not** create the directory: the app has no write access there until the user picks it,
    /// so a `createDirectory` would just fail silently. If the folder does not exist yet, the panel
    /// opens at the nearest existing ancestor.
    ///
    /// Not `private` so the live-view export path (`PlatformAdapters`) shares this one definition
    /// rather than keeping its own copy.
    static var defaultSaveDirectory: URL {
        let home: String
        if let pw = getpwuid(getuid()) {
            home = String(cString: pw.pointee.pw_dir)
        } else {
            home = NSHomeDirectory()   // fallback (container) — getpwuid should never fail
        }
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Documents/GuitarTap")
    }

    /// UserDefaults key for the bookmark data of the last-used export/import directory.
    private static let lastUsedDirectoryKey = "GuitarTap.lastUsedExportDirectory"

    /// The directory the user last saved to or opened from, persisted across launches
    /// as a plain path string in UserDefaults.  Used only as a starting location hint
    /// for NSSavePanel / fileImporter — the panel itself grants access, so no
    /// security-scoped bookmark is needed here.
    static var lastUsedDirectory: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: lastUsedDirectoryKey) else { return nil }
            let url = URL(fileURLWithPath: path, isDirectory: true)
            // Verify the directory still exists before using it as a hint.
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return url
        }
        set {
            if let path = newValue?.path {
                UserDefaults.standard.set(path, forKey: lastUsedDirectoryKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastUsedDirectoryKey)
            }
        }
    }

    /// Returns `lastUsedDirectory` if set, otherwise `defaultSaveDirectory`.
    static var startDirectory: URL {
        lastUsedDirectory ?? defaultSaveDirectory
    }
    #endif

    // MARK: - Export and Share

    /// Hands `data` to the user as `filename`: written where they choose (``FileDelivery/export``, the Mac's
    /// save dialog) or given to the share sheet (``FileDelivery/share``). iOS has no save dialog — saving
    /// there is the share sheet's Save to Files — so an export there shares.
    ///
    /// - Parameters:
    ///   - data: The file's bytes.
    ///   - filename: Its name, with its extension.
    ///   - contentType: Its type; the save dialog offers it.
    ///   - delivery: Export or share.
    ///   - completion: Called on the main thread once the dialog is dismissed or the share sheet shown.
    static func deliver(
        _ data: Data,
        filename: String,
        contentType: UTType,
        as delivery: FileDelivery,
        completion: @escaping () -> Void
    ) {
        #if os(macOS)
        switch delivery {
        case .export: save(data, filename: filename, contentType: contentType, completion: completion)
        case .share: share(data, filename: filename, completion: completion)
        }
        #else
        share(data, filename: filename, completion: completion)
        #endif
    }

    /// Writes `data` to a temporary file named `filename` and shows the platform's share UI for it.
    private static func share(_ data: Data, filename: String, completion: @escaping () -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuitarTap-Export-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let fileURL = tempDir.appendingPathComponent(filename)
            try data.write(to: fileURL)
            #if os(iOS)
            presentShareSheet(items: [fileURL], completion: completion)
            #elseif os(macOS)
            presentSharingPicker(items: [fileURL], completion: completion)
            #endif
        } catch {
            gtLog("❌ Failed to prepare \(filename) for sharing: \(error)")
            completion()
        }
    }

    #if os(macOS)
    /// Shows a save dialog for `filename` and writes `data` where the user chooses. A write that fails —
    /// the file open in another application, a folder it may not write to — says so in an alert.
    private static func save(_ data: Data, filename: String, contentType: UTType, completion: @escaping () -> Void) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [contentType]
        savePanel.nameFieldStringValue = filename
        savePanel.canCreateDirectories = true
        savePanel.directoryURL = startDirectory
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                lastUsedDirectory = url.deletingLastPathComponent()
                do {
                    // Atomically, so a destination open in another application is either replaced cleanly or
                    // left as it was with an error.
                    try data.write(to: url, options: .atomic)
                    gtLog("✅ Saved \(url.path)")
                } catch {
                    gtLog("❌ Failed to save \(url.path): \(error)")
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Could Not Save \(url.lastPathComponent)"
                    alert.informativeText = "The file may be open in another application. Close it and try again.\n\n\(error.localizedDescription)"
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
            completion()
        }
    }

    /// Presents `NSSharingServicePicker` centred on the key window's content view. The picker retains itself
    /// until it is dismissed; `completion` is called once it is shown.
    private static func presentSharingPicker(items: [Any], completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.keyWindow,
                  let contentView = window.contentView else {
                completion()
                return
            }
            let picker = NSSharingServicePicker(items: items)
            let centre = CGRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 0, height: 0)
            picker.show(relativeTo: centre, of: contentView, preferredEdge: .minY)
            completion()
        }
    }
    #endif

    #if os(iOS)
    /// Presents `UIActivityViewController` for `items` from the topmost presented controller; on iPad its
    /// popover is anchored at the centre of that controller's view. `completion` is called once it is presented.
    private static func presentShareSheet(items: [Any], completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first(where: { $0.isKeyWindow }),
               let rootViewController = window.rootViewController {
                var topController = rootViewController
                while let presented = topController.presentedViewController {
                    topController = presented
                }
                let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = topController.view
                    popover.sourceRect = CGRect(x: topController.view.bounds.midX,
                                                y: topController.view.bounds.midY,
                                                width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                topController.present(activityVC, animated: true)
            }
            completion()
        }
    }
    #endif
}

/// How a file reaches the user: ``export`` writes it where they choose (a save dialog), ``share`` gives it to
/// the share sheet. The words on the menus are the same (style guide S9 for their "…").
enum FileDelivery {
    case export, share
}
