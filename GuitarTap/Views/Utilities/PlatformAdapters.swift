/// # PlatformAdapters
///
/// Cross-platform type aliases, view modifiers, and UI helpers that abstract
/// over macOS/iOS differences in the SwiftUI and UIKit/AppKit APIs.
///
/// ## Platform matrix
///
/// | Feature                  | macOS                          | iOS                                  |
/// |--------------------------|--------------------------------|--------------------------------------|
/// | `PlatformImage`          | `NSImage`                      | `UIImage`                            |
/// | `ImageRenderer.platformImage` | `.nsImage`                | `.uiImage`                           |
/// | `FileExportHelper`       | `NSSavePanel`                  | `UIActivityViewController`           |
/// | `ToolbarItemPlacement.primaryAction` | `.automatic`   | `.navigationBarTrailing`             |
/// | `ToolbarItemPlacement.cancelAction`  | `.cancellationAction` | `.navigationBarLeading`      |
/// | `View.platformSheet`     | `.sheet` (min 400×300 pt)      | `.sheet` inside `NavigationView`     |
/// | `View.cursor(_:)`        | `NSCursor` on hover            | No-op                                |
/// | `PlatformSplitView`      | `HSplitView`                   | `HStack` with `Divider`              |
/// | `DocumentPicker`         | Not available                  | `UIDocumentPickerViewController`     |
///
/// All macOS-only APIs are guarded with `#if os(macOS)`. iOS stubs are provided
/// where necessary to keep call sites free of conditional compilation.
///
/// - SeeAlso: `MeasurementFileExporter`, `TapToneAnalysisView+Export`
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
internal import UniformTypeIdentifiers

// MARK: - Platform-Agnostic Image Type

/// Platform-unified image type.
///
/// Use `PlatformImage` whenever code must handle both `NSImage` (macOS) and
/// `UIImage` (iOS) without conditional compilation at every call site.
#if os(macOS)
typealias PlatformImage = NSImage
#elseif os(iOS)
typealias PlatformImage = UIImage
#endif

// MARK: - Image Rendering Helpers

extension ImageRenderer {
    /// The rendered image as a `PlatformImage`, or `nil` if rendering failed.
    ///
    /// Wraps `.nsImage` on macOS and `.uiImage` on iOS behind a single property.
    var platformImage: PlatformImage? {
        #if os(macOS)
        return self.nsImage
        #elseif os(iOS)
        return self.uiImage
        #endif
    }
    
    /// Returns PNG data for the rendered image.
    ///
    /// On macOS, the NSImage is converted via TIFF intermediate representation.
    /// On iOS, `UIImage.pngData()` is called directly.
    ///
    /// - Returns: PNG-encoded `Data`, or `nil` if rendering or encoding failed.
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

/// Static helpers for exporting a `Data` blob to a user-chosen file location.
///
/// Provides a single cross-platform entry point (`exportFile(...)`) that
/// dispatches to an `NSSavePanel` on macOS or a `UIActivityViewController`
/// share sheet on iOS.
struct FileExportHelper {
    /// Presents the platform-appropriate export UI for `data`.
    ///
    /// On macOS, an `NSSavePanel` is shown pre-configured with `contentType`
    /// and `filename` as the default name.  The `completion` closure receives
    /// `true` if the file was written successfully, `false` otherwise.
    ///
    /// On iOS, the data is first written to `FileManager.temporaryDirectory`
    /// as `filename`, then a `UIActivityViewController` share sheet is
    /// presented.  `completion` is called with `true` after the sheet is
    /// presented, or `false` if the root view controller could not be located.
    ///
    /// - Parameters:
    ///   - data: Raw bytes to export.
    ///   - filename: Default file name (including extension) for the saved file.
    ///   - contentType: UTType of the file; used to filter the save panel on macOS.
    ///   - completion: Called on the main thread with `true` on success,
    ///     `false` on failure or user cancellation.
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
    /// macOS implementation: presents `NSSavePanel` and writes `data` to the
    /// chosen URL on OK, or calls `completion(false)` on cancel.
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
    /// iOS implementation: writes `data` to a temporary file, then presents
    /// `UIActivityViewController` from the topmost view controller.
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
            
            // Present share sheet on main thread
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first(where: { $0.isKeyWindow }),
                   let rootViewController = window.rootViewController {
                    
                    // Find the topmost presented view controller
                    var topController = rootViewController
                    while let presented = topController.presentedViewController {
                        topController = presented
                    }
                    
                    let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                    
                    // For iPad - set source for popover
                    if let popover = activityVC.popoverPresentationController {
                        popover.sourceView = topController.view
                        popover.sourceRect = CGRect(x: topController.view.bounds.midX,
                                                    y: topController.view.bounds.midY,
                                                    width: 0, height: 0)
                        popover.permittedArrowDirections = []
                    }
                    
                    topController.present(activityVC, animated: true)
                    completion(true)
                } else {
                    completion(false)
                }
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
    /// Platform-appropriate placement for primary action toolbar buttons.
    ///
    /// - macOS: `.automatic` (Xcode chooses the best location in the toolbar)
    /// - iOS: `.navigationBarTrailing`
    static var primaryAction: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #elseif os(iOS)
        return .navigationBarTrailing
        #endif
    }
    
    /// Platform-appropriate placement for cancel or dismiss toolbar buttons.
    ///
    /// - macOS: `.cancellationAction`
    /// - iOS: `.navigationBarLeading`
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
    /// Presents a sheet with platform-appropriate sizing and navigation wrapping.
    ///
    /// On macOS, the sheet is presented with a minimum size of 400×300 pt.
    /// On iOS, the content is wrapped in a `NavigationView` for a title bar and
    /// dismiss button.
    ///
    /// - Parameters:
    ///   - isPresented: Binding that controls the sheet's presentation state.
    ///   - content: A view builder producing the sheet content.
    /// - Returns: The view with a sheet modifier attached.
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
    /// Changes the cursor to `cursor` while the pointer hovers over this view
    /// (macOS only).
    ///
    /// Uses `onContinuousHover` to push and pop the cursor on enter/exit.
    /// Restores `NSCursor.arrow` when the hover ends.
    ///
    /// - Parameter cursor: The `NSCursor` to display on hover.
    /// - Returns: The view with a cursor-tracking modifier applied.
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
    /// No-op cursor modifier on iOS; maintains API compatibility with macOS call sites.
    ///
    /// - Parameter cursor: Ignored on iOS.
    /// - Returns: The view unchanged.
    func cursor(_ cursor: Any) -> some View {
        return self
    }
}
#endif

// MARK: - Split View Helpers

/// A two-pane split view that adapts to platform conventions.
///
/// On macOS, uses `HSplitView` with a minimum primary width of 600 pt and a
/// constrained secondary panel (300–450 pt ideal `secondaryWidth`).
/// On iOS, uses an `HStack` with a fixed-width secondary panel separated by a
/// `Divider`.
///
/// - SeeAlso: `TapToneAnalysisView+Layouts`
struct PlatformSplitView<Primary: View, Secondary: View>: View {
    /// The primary (main) pane content.
    let primary: Primary
    /// The secondary (side) pane content.
    let secondary: Secondary
    /// Preferred/fixed width of the secondary pane, in points.
    let secondaryWidth: CGFloat
    
    /// Creates a platform-adaptive split view.
    ///
    /// - Parameters:
    ///   - secondaryWidth: Preferred width for the secondary pane (default 350 pt).
    ///   - primary: View builder for the primary pane.
    ///   - secondary: View builder for the secondary pane.
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
    /// Attaches a platform-appropriate context menu to a view.
    ///
    /// Both platforms use `.contextMenu`, but this wrapper keeps call sites
    /// consistent and allows future platform-specific divergence without
    /// changing callers.
    ///
    /// - Parameter menuItems: A view builder producing the context menu items.
    /// - Returns: The view with a context menu attached.
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

// MARK: - Document Picker for iOS

#if os(iOS)
/// A SwiftUI wrapper around `UIDocumentPickerViewController` for importing files
/// from the iOS Files app or iCloud Drive.
///
/// Use this view to present the system document browser and receive a single
/// selected file URL via the `onPick` callback.  The picker is automatically
/// dismissed after selection or cancellation.
///
/// ```swift
/// DocumentPicker(isPresented: $showPicker) { url in
///     // handle selected URL
/// }
/// ```
///
/// - Note: This type is iOS-only.  On macOS, use `NSSavePanel` or
///   `NSOpenPanel` directly.
struct DocumentPicker: UIViewControllerRepresentable {
    /// Binding that controls whether the picker is shown; set to `false`
    /// to dismiss it programmatically.
    @Binding var isPresented: Bool

    /// Called with the URL of the file the user selected, or not called
    /// if the user cancelled.
    let onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onPick: onPick)
    }
    
    /// Coordinator that bridges `UIDocumentPickerDelegate` callbacks into
    /// SwiftUI state updates.
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        /// Binding to `DocumentPicker.isPresented`; set to `false` on dismiss.
        @Binding var isPresented: Bool
        /// Callback forwarded from `documentPicker(_:didPickDocumentsAt:)`.
        let onPick: (URL) -> Void
        
        init(isPresented: Binding<Bool>, onPick: @escaping (URL) -> Void) {
            _isPresented = isPresented
            self.onPick = onPick
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            isPresented = false
            if let url = urls.first {
                onPick(url)
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            isPresented = false
        }
    }
}
#endif
