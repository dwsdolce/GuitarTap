//
//  MeasurementFileExporter.swift
//  GuitarTap
//
//  Created by David Smith on 2/9/26.
//
import SwiftUI
internal import UniformTypeIdentifiers

struct MeasurementFileExporter {

    // MARK: - PDF Report Export

    /// Export a PDF report using the same share/save pattern as JSON export.
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

                var topController = rootViewController
                while let presented = topController.presentedViewController {
                    topController = presented
                }

                let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)

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

    /// Export only the JSON measurement file.
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

    // MARK: - Spectrum Image Export

    /// Export the spectrum PNG image for a saved measurement.
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
    private static func exportJSONMacOS(json: String, measurement: TapToneMeasurement, completion: @escaping () -> Void) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.guitarTapMeasurement]
        savePanel.nameFieldStringValue = "\(measurement.baseFilename).guitartap"
        savePanel.canCreateDirectories = true
        savePanel.message = "Save Measurement JSON"
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try json.write(to: url, atomically: true, encoding: .utf8)
                    print("✅ Saved measurement JSON to: \(url.path)")
                } catch {
                    print("❌ Failed to save JSON: \(error)")
                }
            }
            completion()
        }
    }

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
    #endif

    #if os(iOS)
    private static func exportiOS(json: String, measurement: TapToneMeasurement, completion: @escaping () -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuitarTap-Export-\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            let basename = measurement.baseFilename
            let jsonURL = tempDir.appendingPathComponent("\(basename).guitartap")
            try json.write(to: jsonURL, atomically: true, encoding: .utf8)
            
            var itemsToShare: [URL] = [jsonURL]
            
            if let imageData = measurement.chartImageData {
                let imageURL = tempDir.appendingPathComponent("\(basename).png")
                try imageData.write(to: imageURL)
                itemsToShare.append(imageURL)
            }
            
            // Use UIActivityViewController (share sheet) like Export Spectrum does
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first(where: { $0.isKeyWindow }),
                   let rootViewController = window.rootViewController {
                    
                    // Find the topmost presented view controller
                    var topController = rootViewController
                    while let presented = topController.presentedViewController {
                        topController = presented
                    }
                    
                    let activityVC = UIActivityViewController(activityItems: itemsToShare, applicationActivities: nil)
                    
                    // For iPad - set source for popover
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
        } catch {
            print("Failed to export: \(error)")
            completion()
        }
    }
    #endif
    
}
