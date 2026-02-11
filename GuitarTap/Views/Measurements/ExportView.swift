//
//  ExportView.swift
//  GuitarTap
//
//  Created by David Smith on 2/9/26.
//
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
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try self.text.write(to: url, atomically: true, encoding: .utf8)
                    self.showingSaveConfirmation = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.showingSaveConfirmation = false
                    }
                } catch {
                    print("Failed to save file: \(error)")
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

