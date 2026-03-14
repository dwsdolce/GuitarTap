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
/// On iOS, temporary files are written to a UUID-named subdirectory of
/// `FileManager.temporaryDirectory` and presented via the system share sheet.
/// Callers are responsible for deleting these temp files when done if needed,
/// though they are cleared by the OS periodically.
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

    // MARK: - PDF Report Export

    /// Exports a PDF report using the platform share/save pattern.
    ///
    /// On iOS, the PDF is written to a temporary file and presented via
    /// `UIActivityViewController` (share sheet).  On macOS, an `NSSavePanel`
    /// prompts the user to choose a save location.
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
    /// iOS implementation: writes `data` to `tmp/<basename>.pdf` then presents
    /// the system share sheet.
    private static func exportPDFiOS(data: Data, basename: String, completion: @escaping () -> Void) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(basename).pdf")

        do {
            try data.write(to: tempURL)
        } catch {
            print("❌ Failed to write PDF to temp: \(error)")
            completion()
            return
        }

        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first(where: { $0.isKeyWindow }),
               let rootViewController = window.rootViewController {

                // Walk the presented-controller chain to reach the topmost controller
                var topController = rootViewController
                while let presented = topController.presentedViewController {
                    topController = presented
                }

                let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)

                // On iPad, the activity view controller requires a source rect for the popover
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
    /// macOS implementation: presents an `NSSavePanel` pre-configured for PDF.
    private static func exportPDFMacOS(data: Data, basename: String, completion: @escaping () -> Void) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "\(basename).pdf"
        savePanel.canCreateDirectories = true
        savePanel.message = "Save PDF Report"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try data.write(to: url)
                    print("✅ Saved PDF report to: \(url.path)")
                } catch {
                    print("❌ Failed to save PDF: \(error)")
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
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try json.write(to: url, atomically: true, encoding: .utf8)
                    print("✅ Saved measurement to: \(url.path)")
                } catch {
                    print("❌ Failed to save measurement: \(error)")
                }
            }
            completion()
        }
    }
    #endif

    // MARK: - Spectrum Image Export

    /// Exports the spectrum PNG image associated with a saved measurement.
    ///
    /// On iOS, the PNG is written to a temporary file and shared via the system
    /// share sheet.  On macOS, an `NSSavePanel` prompts the user to choose a
    /// location.  If the measurement has no `chartImageData`, the completion
    /// handler is called immediately and no sheet is presented.
    ///
    /// - Parameters:
    ///   - measurement: The saved measurement whose `chartImageData` is exported.
    ///   - completion: Called on the main thread after the operation completes
    ///     (whether or not a file was actually exported).
    static func exportSpectrumImage(
        measurement: TapToneMeasurement,
        completion: @escaping () -> Void
    ) {
        #if os(iOS)
        exportSpectrumImageiOS(measurement: measurement, completion: completion)
        #elseif os(macOS)
        exportSpectrumImageMacOS(measurement: measurement, completion: completion)
        #endif
    }

    
    #if os(iOS)
    /// iOS implementation: writes JSON to `tmp/<UUID>/<basename>.guitartap`
    /// then presents the share sheet.
    private static func exportJSONiOS(json: String, measurement: TapToneMeasurement, completion: @escaping () -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuitarTap-Export-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let jsonURL = tempDir.appendingPathComponent("\(measurement.baseFilename).guitartap")
            try json.write(to: jsonURL, atomically: true, encoding: .utf8)
            presentShareSheet(items: [jsonURL], completion: completion)
        } catch {
            print("Failed to export JSON: \(error)")
            completion()
        }
    }

    /// iOS implementation: writes the spectrum PNG to a temporary file then
    /// presents the share sheet.
    private static func exportSpectrumImageiOS(measurement: TapToneMeasurement, completion: @escaping () -> Void) {
        guard let imageData = measurement.chartImageData else {
            print("No spectrum image available for this measurement")
            completion()
            return
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuitarTap-Export-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let imageURL = tempDir.appendingPathComponent("\(measurement.baseFilename).png")
            try imageData.write(to: imageURL)
            presentShareSheet(items: [imageURL], completion: completion)
        } catch {
            print("Failed to export spectrum image: \(error)")
            completion()
        }
    }

    /// Presents `UIActivityViewController` for the given file URLs, walking
    /// the controller hierarchy to reach the topmost presented controller.
    ///
    /// On iPad, the popover is anchored to the centre of the root view with no
    /// preferred arrow direction.
    ///
    /// - Parameters:
    ///   - items: File URLs to share.
    ///   - completion: Called immediately after `present(_:animated:)` is invoked.
    private static func presentShareSheet(items: [URL], completion: @escaping () -> Void) {
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
            print("❌ Failed to prepare measurement for sharing: \(error)")
            completion()
        }
    }

    /// macOS implementation: presents an `NSSavePanel` for the spectrum PNG.
    private static func exportSpectrumImageMacOS(measurement: TapToneMeasurement, completion: @escaping () -> Void) {
        guard let imageData = measurement.chartImageData else {
            print("No spectrum image available for this measurement")
            completion()
            return
        }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "\(measurement.baseFilename).png"
        savePanel.canCreateDirectories = true
        savePanel.message = "Save Spectrum Image"
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try imageData.write(to: url)
                    print("✅ Saved spectrum image to: \(url.path)")
                } catch {
                    print("❌ Failed to save spectrum image: \(error)")
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
