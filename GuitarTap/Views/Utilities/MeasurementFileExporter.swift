//
//  MeasurementFileExporter.swift
//  GuitarTap
//
//  Created by David Smith on 2/9/26.
//
import SwiftUI

struct MeasurementFileExporter {
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
            
            if let imageData = measurement.chartImageData {
                let imageURL = tempDir.appendingPathComponent("\(basename).png")
                try imageData.write(to: imageURL)
            }
            
            let documentPicker = UIDocumentPickerViewController(forExporting: [tempDir], asCopy: true)
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(documentPicker, animated: true)
            }
        } catch {
            print("Failed to export: \(error)")
        }
        
        completion()
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
