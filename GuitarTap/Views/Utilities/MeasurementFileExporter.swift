/// # MeasurementFileExporter
///
/// Platform-adaptive file export helpers for GuitarTap measurements.
///
/// All export operations are static methods that dispatch to platform-specific
/// implementations at compile time via `#if os(iOS)` / `#if os(macOS)` guards:
///
/// | Platform | PDF export       | JSON/guitartap export  | Spectrum PNG export |
/// |----------|------------------|------------------------|---------------------|
/// | iOS      | Share sheet via `UIActivityViewController` | Share sheet | Share sheet |
/// | macOS    | `NSSavePanel`    | `NSSharingServicePicker` (AirDrop etc.) | `NSSavePanel` |
///
/// On iOS, all three export types write to a UUID-named subdirectory of
/// `FileManager.temporaryDirectory` and present the resulting file URL via the
/// share sheet, so "Save to Files" and other destinations receive the correct
/// suggested file name and extension.  The multiple-instance problem that
/// previously caused `-10814` LaunchServices failures is addressed by the
/// `handlesExternalEvents` modifier in GuitarTapApp, which routes incoming
/// document URLs to the existing scene rather than spawning a new app instance.
///
/// On macOS, PDF and spectrum PNG files are saved directly to a user-chosen
/// location via `NSSavePanel`.  JSON measurement files are shared via
/// `NSSharingServicePicker` (which includes AirDrop, Mail, Messages, etc.),
/// or can be saved directly to disk using `saveMeasurementToDisk(...)`.
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
    /// Starting directory for the export Save panel.
    ///
    /// ⚠️ Under App Sandbox `homeDirectoryForCurrentUser` returns the **container** home, so this is
    /// the container's `Documents/GuitarTap`, **not** the user's `~/Documents/GuitarTap`. The panel
    /// still opens there and the user can navigate out (a powerbox panel may display directories the
    /// app cannot read), but the first-run default is the wrong place. FILE-PATHS-AND-NAMES-SPEC §1b
    /// / Step 5 replaces this with the real home via `getpwuid`.
    private static var defaultSaveDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/GuitarTap")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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

    // MARK: - PDF Report Export

    /// Exports a PDF report using the platform share/save pattern.
    ///
    /// On iOS, the PDF data is passed directly to `UIActivityViewController`
    /// (no temp file) to avoid LaunchServices failures when multiple app
    /// instances are running.  On macOS, an `NSSavePanel` prompts the user
    /// to choose a save location.
    ///
    /// - Parameters:
    ///   - data: Raw PDF data, typically produced by `PDFReportGenerator.generate(data:)`.
    ///   - basename: Filename stem (without extension) for the saved file.
    ///   - completion: Called on the main thread after the share sheet is
    ///     presented or the save panel is dismissed.
    static func exportPDF(
        data: Data,
        basename: String,
        completion: @escaping () -> Void
    ) {
        #if os(iOS)
        exportPDFiOS(data: data, basename: basename, completion: completion)
        #elseif os(macOS)
        exportPDFMacOS(data: data, basename: basename, completion: completion)
        #endif
    }

    #if os(iOS)
    /// iOS implementation: writes `data` to a temporary file then presents
    /// the system share sheet.
    ///
    /// A temp file URL is used so that the share sheet (and "Save to Files"
    /// in particular) receives the correct suggested file name.  The
    /// multiple-instance problem that previously caused `-10814` failures is
    /// addressed by `handlesExternalEvents` in GuitarTapApp, not by avoiding
    /// file URLs here.
    private static func exportPDFiOS(data: Data, basename: String, completion: @escaping () -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuitarTap-Export-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempURL = tempDir.appendingPathComponent("\(basename).pdf")
            try data.write(to: tempURL)
            presentShareSheet(items: [tempURL], completion: completion)
        } catch {
            gtLog("❌ Failed to write PDF to temp: \(error)")
            completion()
        }
    }
    #endif

    #if os(macOS)
    /// macOS implementation: presents an `NSSavePanel` pre-configured for PDF.
    private static func exportPDFMacOS(data: Data, basename: String, completion: @escaping () -> Void) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "\(basename).pdf"
        savePanel.canCreateDirectories = true
        savePanel.message = "Save PDF Report"
        savePanel.directoryURL = startDirectory

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                lastUsedDirectory = url.deletingLastPathComponent()
                do {
                    // Write atomically via a temp file so that if the destination is
                    // already open in another application (e.g. Acrobat) the write
                    // either succeeds cleanly or throws a meaningful error.
                    try data.write(to: url, options: .atomic)
                    gtLog("✅ Saved PDF report to: \(url.path)")
                } catch {
                    gtLog("❌ Failed to save PDF: \(error)")
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = "Could Not Save PDF"
                        alert.informativeText = "The file may be open in another application. Close it and try again.\n\n\(error.localizedDescription)"
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
            completion()
        }
    }
    #endif

    // MARK: - JSON Export

    /// Exports a measurement file via the platform share/save mechanism.
    ///
    /// On iOS the measurement is written to a temporary `.guitartap` file and
    /// shared via `UIActivityViewController`.  On macOS it is shared via
    /// `NSSharingServicePicker`, which includes AirDrop, Mail, and other
    /// system services.  To save directly to disk on macOS, use
    /// `saveMeasurementToDisk(json:measurement:completion:)` instead.
    ///
    /// - Parameters:
    ///   - json: JSON string encoding of the measurement.
    ///   - measurement: The `TapToneMeasurement` whose `baseFilename` is used
    ///     for the exported file name.
    ///   - completion: Called on the main thread after export is initiated.
    static func exportJSON(
        json: String,
        measurement: TapToneMeasurement,
        completion: @escaping () -> Void
    ) {
        #if os(iOS)
        exportJSONiOS(json: json, measurement: measurement, completion: completion)
        #elseif os(macOS)
        exportJSONMacOS(json: json, measurement: measurement, completion: completion)
        #endif
    }

    /// Share a `.guitartap` file with an explicit base name (no single measurement). Used by
    /// Export All — writes the library JSON to a temp `<suggestedName>.guitartap` and shares it
    /// (iOS share sheet / macOS sharing picker), reusing the same plumbing as the single export.
    static func exportJSON(
        json: String,
        suggestedName: String,
        completion: @escaping () -> Void
    ) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuitarTap-Export-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let fileURL = tempDir.appendingPathComponent("\(suggestedName).guitartap")
            try json.write(to: fileURL, atomically: true, encoding: .utf8)
            #if os(iOS)
            presentShareSheet(items: [fileURL], completion: completion)
            #elseif os(macOS)
            presentSharingPicker(items: [fileURL], completion: completion)
            #endif
        } catch {
            gtLog("Failed to export measurements: \(error)")
            completion()
        }
    }

    #if os(macOS)
    /// Saves the measurement JSON directly to a user-chosen location on disk.
    ///
    /// Presents an `NSSavePanel` pre-configured with the `.guitartap` custom
    /// content type and the measurement's `baseFilename` as the default name.
    ///
    /// - Parameters:
    ///   - json: JSON string encoding of the measurement.
    ///   - measurement: The measurement being saved; its `baseFilename` is used
    ///     for the default file name.
    ///   - completion: Called on the main thread after the panel is dismissed.
    static func saveMeasurementToDisk(
        json: String,
        measurement: TapToneMeasurement,
        completion: @escaping () -> Void
    ) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.guitarTapMeasurement]
        savePanel.nameFieldStringValue = "\(measurement.baseFilename).guitartap"
        savePanel.canCreateDirectories = true
        savePanel.message = "Save Measurement to Disk"
        savePanel.directoryURL = startDirectory
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                lastUsedDirectory = url.deletingLastPathComponent()
                do {
                    try json.write(to: url, atomically: true, encoding: .utf8)
                    gtLog("\u{2705} Saved measurement to: \(url.path)")
                } catch {
                    gtLog("\u{274C} Failed to save measurement: \(error)")
                }
            }
            completion()
        }
    }

    /// macOS Save-to-Disk for the whole library (a chosen base name, no single measurement).
    /// Mirrors saveMeasurementToDisk(json:measurement:) but names the file from suggestedName.
    static func saveMeasurementsToDisk(
        json: String,
        suggestedName: String,
        completion: @escaping () -> Void
    ) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.guitarTapMeasurement]
        savePanel.nameFieldStringValue = "\(suggestedName).guitartap"
        savePanel.canCreateDirectories = true
        savePanel.message = "Save Measurements to Disk"
        savePanel.directoryURL = startDirectory
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                lastUsedDirectory = url.deletingLastPathComponent()
                do {
                    try json.write(to: url, atomically: true, encoding: .utf8)
                    gtLog("\u{2705} Saved measurements to: \(url.path)")
                } catch {
                    gtLog("\u{274C} Failed to save measurements: \(error)")
                }
            }
            completion()
        }
    }
    #endif

    // MARK: - Spectrum Image Export

    /// Exports a spectrum PNG image via the platform share/save mechanism.
    ///
    /// On iOS, the PNG is written to a temporary file and shared via the system
    /// share sheet.  On macOS, an `NSSavePanel` prompts the user to choose a
    /// location.  If `imageData` is `nil`, the completion handler is called
    /// immediately and no sheet is presented.
    ///
    /// - Parameters:
    ///   - imageData: PNG-encoded spectrum image data to export.
    ///   - basename: Filename stem (without extension) for the saved file.
    ///   - completion: Called on the main thread after the operation completes
    ///     (whether or not a file was actually exported).
    static func exportSpectrumImage(
        imageData: Data?,
        basename: String,
        completion: @escaping () -> Void
    ) {
        #if os(iOS)
        exportSpectrumImageiOS(imageData: imageData, basename: basename, completion: completion)
        #elseif os(macOS)
        exportSpectrumImageMacOS(imageData: imageData, basename: basename, completion: completion)
        #endif
    }

    
    #if os(iOS)
    /// iOS implementation: writes JSON to `tmp/<UUID>/<basename>.guitartap`
    /// then presents the share sheet.
    ///
    /// A temp file URL is used so that the share sheet receives the correct
    /// suggested file name and the system recognises the `.guitartap` extension.
    private static func exportJSONiOS(json: String, measurement: TapToneMeasurement, completion: @escaping () -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuitarTap-Export-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let jsonURL = tempDir.appendingPathComponent("\(measurement.baseFilename).guitartap")
            try json.write(to: jsonURL, atomically: true, encoding: .utf8)
            presentShareSheet(items: [jsonURL], completion: completion)
        } catch {
            gtLog("Failed to export JSON: \(error)")
            completion()
        }
    }

    /// iOS implementation: writes the spectrum PNG to a temporary file then
    /// presents the share sheet.
    ///
    /// A temp file URL is used so that "Save to Files" receives the correct
    /// suggested file name (e.g. "bridge-2024-01-15.png").
    private static func exportSpectrumImageiOS(imageData: Data?, basename: String, completion: @escaping () -> Void) {
        guard let imageData = imageData else {
            gtLog("No spectrum image available for this measurement")
            completion()
            return
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuitarTap-Export-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let imageURL = tempDir.appendingPathComponent("\(basename).png")
            try imageData.write(to: imageURL)
            presentShareSheet(items: [imageURL], completion: completion)
        } catch {
            gtLog("Failed to export spectrum image: \(error)")
            completion()
        }
    }

    /// Presents `UIActivityViewController` for the given items, walking
    /// the controller hierarchy to reach the topmost presented controller.
    ///
    /// Items may be file URLs (for PDFs, `.guitartap` files, and spectrum PNGs).
    /// On iPad, the popover is anchored to the centre of
    /// the root view with no preferred arrow direction.
    ///
    /// - Parameters:
    ///   - items: Items to share.
    ///   - completion: Called immediately after `present(_:animated:)` is invoked.
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

    #if os(macOS)
    /// macOS implementation: writes JSON to a temporary `.guitartap` file then
    /// presents `NSSharingServicePicker` centred in the key window.
    private static func exportJSONMacOS(json: String, measurement: TapToneMeasurement, completion: @escaping () -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuitarTap-Export-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let fileURL = tempDir.appendingPathComponent("\(measurement.baseFilename).guitartap")
            try json.write(to: fileURL, atomically: true, encoding: .utf8)
            presentSharingPicker(items: [fileURL], completion: completion)
        } catch {
            gtLog("❌ Failed to prepare measurement for sharing: \(error)")
            completion()
        }
    }

    /// macOS implementation: presents an `NSSavePanel` for the spectrum PNG.
    private static func exportSpectrumImageMacOS(imageData: Data?, basename: String, completion: @escaping () -> Void) {
        guard let imageData = imageData else {
            gtLog("No spectrum image available for this measurement")
            completion()
            return
        }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "\(basename).png"
        savePanel.canCreateDirectories = true
        savePanel.message = "Save Spectrum Image"
        savePanel.directoryURL = startDirectory
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                lastUsedDirectory = url.deletingLastPathComponent()
                do {
                    try imageData.write(to: url)
                    gtLog("✅ Saved spectrum image to: \(url.path)")
                } catch {
                    gtLog("❌ Failed to save spectrum image: \(error)")
                }
            }
            completion()
        }
    }

    /// Presents `NSSharingServicePicker` centred on the key window's content view.
    ///
    /// The picker retains itself until it is dismissed; callers do not need to
    /// hold a strong reference to it.  The completion handler is called
    /// immediately after `show(relativeTo:of:preferredEdge:)` returns.
    ///
    /// - Parameters:
    ///   - items: Items to share (typically file URLs).
    ///   - completion: Called on the main thread after the picker is shown.
    private static func presentSharingPicker(items: [Any], completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.keyWindow,
                  let contentView = window.contentView else {
                completion()
                return
            }
            let picker = NSSharingServicePicker(items: items)
            // Show centred on the content view; picker retains itself until dismissed
            let centre = CGRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 0, height: 0)
            picker.show(relativeTo: centre, of: contentView, preferredEdge: .minY)
            completion()
        }
    }
    #endif
}
