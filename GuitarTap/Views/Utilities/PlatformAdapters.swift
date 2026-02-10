//
//  PlatformAdapters.swift
//  GuitarTap
//
//  Created on 2/9/26.
//

import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
internal import UniformTypeIdentifiers

// MARK: - Platform-Agnostic Image Type

/// A type alias that provides a unified interface for images across platforms
#if os(macOS)
typealias PlatformImage = NSImage
#elseif os(iOS)
typealias PlatformImage = UIImage
#endif

// MARK: - Image Rendering Helpers

extension ImageRenderer {
    /// Get platform-specific image from the renderer
    var platformImage: PlatformImage? {
        #if os(macOS)
        return self.nsImage
        #elseif os(iOS)
        return self.uiImage
        #endif
    }
    
    /// Get PNG data from the rendered image
    func pngData() -> Data? {
        #if os(macOS)
        guard let nsImage = self.nsImage,
              let tiffData = nsImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData
        #elseif os(iOS)
        return self.uiImage?.pngData()
        #endif
    }
}

// MARK: - File Export Helpers

struct FileExportHelper {
    /// Present a save dialog (macOS) or share sheet (iOS) for exporting data
    static func exportFile(
        data: Data,
        filename: String,
        contentType: UTType,
        completion: @escaping (Bool) -> Void
    ) {
        #if os(macOS)
        exportFileMacOS(data: data, filename: filename, contentType: contentType, completion: completion)
        #elseif os(iOS)
        exportFileIOS(data: data, filename: filename, contentType: contentType, completion: completion)
        #endif
    }
    
    #if os(macOS)
    private static func exportFileMacOS(
        data: Data,
        filename: String,
        contentType: UTType,
        completion: @escaping (Bool) -> Void
    ) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [contentType]
        savePanel.nameFieldStringValue = filename
        savePanel.canCreateDirectories = true
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try data.write(to: url)
                    completion(true)
                } catch {
                    print("❌ Failed to save file: \(error)")
                    completion(false)
                }
            } else {
                completion(false)
            }
        }
    }
    #endif
    
    #if os(iOS)
    private static func exportFileIOS(
        data: Data,
        filename: String,
        contentType: UTType,
        completion: @escaping (Bool) -> Void
    ) {
        // Write to temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: tempURL)
            
            // Present share sheet
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                rootViewController.present(activityVC, animated: true)
                completion(true)
            } else {
                completion(false)
            }
        } catch {
            print("❌ Failed to prepare file for export: \(error)")
            completion(false)
        }
    }
    #endif
}

// MARK: - Toolbar Placement Helpers

extension ToolbarItemPlacement {
    /// Platform-appropriate placement for primary action buttons
    static var primaryAction: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #elseif os(iOS)
        return .navigationBarTrailing
        #endif
    }
    
    /// Platform-appropriate placement for cancel/dismiss buttons
    static var cancelAction: ToolbarItemPlacement {
        #if os(macOS)
        return .cancellationAction
        #elseif os(iOS)
        return .navigationBarLeading
        #endif
    }
}

// MARK: - Sheet Presentation Modifiers

extension View {
    /// Present a sheet with platform-appropriate styling
    func platformSheet<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        return self.sheet(isPresented: isPresented) {
            content()
                .frame(minWidth: 400, minHeight: 300)
        }
        #elseif os(iOS)
        return self.sheet(isPresented: isPresented) {
            NavigationView {
                content()
            }
        }
        #endif
    }
}

// MARK: - Cursor Management (macOS Only)

#if os(macOS)
extension View {
    /// Set cursor type when hovering over a view (macOS only)
    func cursor(_ cursor: NSCursor) -> some View {
        self.onContinuousHover { phase in
            switch phase {
            case .active:
                cursor.set()
            case .ended:
                NSCursor.arrow.set()
            }
        }
    }
}
#else
extension View {
    /// No-op cursor modifier for iOS (maintains API compatibility)
    func cursor(_ cursor: Any) -> some View {
        return self
    }
}
#endif

// MARK: - Split View Helpers

/// A unified split view that adapts to platform conventions
struct PlatformSplitView<Primary: View, Secondary: View>: View {
    let primary: Primary
    let secondary: Secondary
    let secondaryWidth: CGFloat
    
    init(
        secondaryWidth: CGFloat = 350,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.primary = primary()
        self.secondary = secondary()
        self.secondaryWidth = secondaryWidth
    }
    
    var body: some View {
        #if os(macOS)
        HSplitView {
            primary
                .frame(minWidth: 600)
            
            secondary
                .frame(minWidth: 300, idealWidth: secondaryWidth, maxWidth: 450)
        }
        #elseif os(iOS)
        HStack(spacing: 0) {
            primary
                .frame(maxWidth: .infinity)
            
            Divider()
            
            secondary
                .frame(width: secondaryWidth)
        }
        #endif
    }
}

// MARK: - Context Menu Helpers

extension View {
    /// Add a platform-appropriate context menu with consistent styling
    func platformContextMenu<MenuItems: View>(
        @ViewBuilder menuItems: () -> MenuItems
    ) -> some View {
        #if os(macOS)
        return self.contextMenu {
            menuItems()
        }
        #elseif os(iOS)
        return self.contextMenu {
            menuItems()
        }
        #endif
    }
}
