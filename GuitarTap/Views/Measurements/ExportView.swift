//
//  ExportView.swift
//  GuitarTap
//

/// # ExportView
///
/// A modal sheet that displays a measurement's raw JSON content and provides
/// Copy and Save controls.
///
/// ## Usage
///
/// `ExportView` is presented by `MeasurementsListView` and
/// `MeasurementDetailView` when the user requests a JSON text export. The
/// caller passes the pre-rendered JSON string; `ExportView` renders it in a
/// monospaced, selectable `ScrollView` with:
///
/// - **Copy** — writes the text to the system pasteboard and shows a transient
///   "Copied" confirmation banner.
/// - **Save / Share** — calls `MeasurementFileExporter.exportJSON` which routes
///   to `NSSavePanel` on macOS or `UIActivityViewController` on iOS.
///
/// Confirmation banners auto-dismiss after 2 s using a `Task.sleep` delay.
///
/// - SeeAlso: `MeasurementFileExporter`, `MeasurementsListView`

import SwiftUI
internal import UniformTypeIdentifiers

struct ExportView: View {
    let text: String
    @Environment(\.dismiss) var dismiss
    @State private var showingCopyConfirmation = false
    @State private var showingSaveConfirmation = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Info banner
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Measurement Data (JSON)")
                            .font(.headline)
                    }
                    
                    Text("This data can be imported into analysis tools, spreadsheets, or shared with other users.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                
                Divider()
                
                // JSON content
                ScrollView {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Confirmation overlays
                if showingCopyConfirmation {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                            Text("Copied to clipboard")
                                .foregroundColor(.white)
                                .font(.subheadline)
                        }
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                        .padding()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                if showingSaveConfirmation {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                            Text("File saved successfully")
                                .foregroundColor(.white)
                                .font(.subheadline)
                        }
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                        .padding()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Export Data")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: saveToFile) {
                            Label("Save to Files", systemImage: "folder")
                        }
                        
                        Button(action: copyToClipboard) {
                            Label("Copy to Clipboard", systemImage: "doc.on.doc")
                        }
                        
                        ShareLink(item: createTemporaryFile(), preview: SharePreview("measurements.json")) {
                            Label("Share File", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button(action: saveToFile) {
                        Label("Save File", systemImage: "square.and.arrow.down")
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: copyToClipboard) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
                #endif
            }
        }
        .animation(.easeInOut, value: showingCopyConfirmation)
        .animation(.easeInOut, value: showingSaveConfirmation)
    }
    
    private func saveToFile() {
        #if os(iOS)
        // On iOS, use UIDocumentPickerViewController to let user choose save location
        let tempURL = createTemporaryFile()
        let documentPicker = UIDocumentPickerViewController(forExporting: [tempURL], asCopy: true)
        
        // Set up delegate to detect when save completes
        let coordinator = DocumentPickerCoordinator(onCompletion: {
            DispatchQueue.main.async {
                self.showingSaveConfirmation = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.showingSaveConfirmation = false
                }
            }
        })
        documentPicker.delegate = coordinator
        
        // Store coordinator to keep it alive
        objc_setAssociatedObject(
            documentPicker,
            "coordinator",
            coordinator,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(documentPicker, animated: true)
        }
        #elseif os(macOS)
        // On macOS, use NSSavePanel
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "measurements-\(Date().timeIntervalSince1970).json"
        savePanel.canCreateDirectories = true
        savePanel.directoryURL = MeasurementFileExporter.lastUsedDirectory ?? {
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/GuitarTap")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }()

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                MeasurementFileExporter.lastUsedDirectory = url.deletingLastPathComponent()
                do {
                    try self.text.write(to: url, atomically: true, encoding: .utf8)
                    self.showingSaveConfirmation = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.showingSaveConfirmation = false
                    }
                } catch {
                    gtLog("Failed to save file: \(error)")
                }
            }
        }
        #endif
    }
    
    private func createTemporaryFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "measurements-\(Date().timeIntervalSince1970).json"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
        
        return fileURL
    }
    
    private func copyToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        
        showingCopyConfirmation = true
        
        // Hide confirmation after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showingCopyConfirmation = false
        }
    }
}
// MARK: - Document Picker Delegate

#if os(iOS)
import UIKit

/// Coordinator to handle UIDocumentPickerViewController delegate callbacks
private class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    let onCompletion: () -> Void
    
    init(onCompletion: @escaping () -> Void) {
        self.onCompletion = onCompletion
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        // User completed the export
        onCompletion()
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // User cancelled - no action needed
    }
}
#endif

