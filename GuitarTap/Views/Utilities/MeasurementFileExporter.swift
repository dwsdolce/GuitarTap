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

    // MARK: - JSON + Image Export

    static func exportJSONAndImage(
        json: String,
        measurement: TapToneMeasurement,
        completion: @escaping () -> Void
    ) {
        #if os(iOS)
        exportiOS(json: json, measurement: measurement, completion: completion)
        #elseif os(macOS)
        exportMacOS(json: json, measurement: measurement, completion: completion)
        #endif
    }
    
    #if os(iOS)
    private static func exportiOS(json: String, measurement: TapToneMeasurement, completion: @escaping () -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuitarTap-Export-\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            let basename = measurement.baseFilename
            let jsonURL = tempDir.appendingPathComponent("\(basename).json")
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
    
    #if os(macOS)
    private static func exportMacOS(json: String, measurement: TapToneMeasurement, completion: @escaping () -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Select a folder to save measurement and image"
        panel.prompt = "Export Here"
        
        panel.begin { response in
            if response == .OK, let directoryURL = panel.url {
                do {
                    let basename = measurement.baseFilename
                    let jsonURL = directoryURL.appendingPathComponent("\(basename).json")
                    try json.write(to: jsonURL, atomically: true, encoding: .utf8)
                    
                    if let imageData = measurement.chartImageData {
                        let imageURL = directoryURL.appendingPathComponent("\(basename).png")
                        try imageData.write(to: imageURL)
                    }
                    
                    print("✅ Exported measurement to: \(directoryURL.path)")
                } catch {
                    print("Failed to save files: \(error)")
                }
            }
            completion()
        }
    }
    #endif
}
