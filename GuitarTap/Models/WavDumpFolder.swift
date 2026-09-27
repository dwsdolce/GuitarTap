//
//  WavDumpFolder.swift
//  GuitarTap
//
//  The folder "Dump Capture Audio" writes session WAVs to.
//
// @parity model/wav-dump-folder tests=test/wav-dump-folder
//
// Shared capability with Python (models/wav_dump_folder.py): default folder, current folder,
// has-custom, reachability check, choose, use-default, reveal. The STORAGE differs by platform —
// a security-scoped bookmark here (App Sandbox), a plain stored path in Python (not sandboxed) —
// but the interface and method names match. The web has no counterpart (a browser page can only
// download to its Downloads folder), so this slug is Swift + Python only.

import Foundation
#if os(macOS)
import AppKit
#endif

/// Where Dump Capture Audio saves its per-measurement session WAVs.
///
/// **Default** = the app's `Documents/GuitarTap` — the sandbox container on macOS/iOS, which needs
/// no authorization. On **macOS** the user may *Change…* to any folder; that grant is persisted as a
/// **security-scoped bookmark**, together with the **path the user chose**.
///
/// **The folder must stay where you put it.** A chosen folder is treated as a *path*, not an opaque
/// identity: on every check the bookmark must resolve **to the chosen path**. If the folder is
/// renamed, moved, trashed, or deleted, the resolved path no longer matches (or the bookmark won't
/// resolve at all) and it is reported **unreachable** — the user must Change Location or Turn Off
/// Saving. This deliberately overrides macOS's silent bookmark-follows-the-folder behaviour, which
/// would otherwise write captures into a renamed or trashed folder without telling anyone.
///
/// The debug log deliberately does **not** use this — it stays in the app's Documents.
enum WavDumpFolder {

    /// The app's `Documents/GuitarTap` (the container under the sandbox). Always writable. Under test, a
    /// per-process temp folder instead, like the measurements file — a test that turns dumps on never
    /// writes into the user's folder.
    static var defaultFolder: URL {
        if TestSandbox.isActive {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent(TestSandbox.name("com.guitartap.tests"))
                .appendingPathComponent("GuitarTap")
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("GuitarTap")
    }

    #if os(macOS)
    private static let bookmarkKey = "GuitarTap.wavDumpFolderBookmark"
    private static let pathKey = "GuitarTap.wavDumpFolderPath"

    /// Whether the user has chosen a custom folder (a bookmark is stored). Never under test: the stored
    /// bookmark is the real app's, and a test must not write into the user's chosen folder.
    static var hasCustomFolder: Bool {
        !TestSandbox.isActive && UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// The path the user chose — the "name" they care about. Shown in Settings and the dialog, so it
    /// can be named even when the folder is gone. Reading it does **not** resolve the bookmark, so
    /// the display is instant (no slow resolve of a dead bookmark on the main thread).
    static var chosenPath: String { UserDefaults.standard.string(forKey: pathKey) ?? "" }

    /// Resolve the bookmark to an access-held URL — **only if the folder is still at the chosen
    /// path**. Returns `nil` if the bookmark can't resolve (deleted) or resolves elsewhere (renamed
    /// / moved / trashed). Caller must `stopAccessingSecurityScopedResource()` on the returned URL.
    /// Re-mints a benign-stale bookmark that still points at the chosen path.
    private static func resolveAtChosenPath() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &isStale) else { return nil }
        guard url.path == chosenPath else { return nil }   // moved / renamed / trashed → not the same name
        guard url.startAccessingSecurityScopedResource() else { return nil }
        if isStale, let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                      includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url   // access held — caller releases
    }
    #endif

    /// The folder currently in effect, for **display** (Settings / the dialog): the chosen path if a
    /// custom folder is set (shown as-is, no resolve), else the default.
    static var currentFolder: URL {
        #if os(macOS)
        if hasCustomFolder { return URL(fileURLWithPath: chosenPath, isDirectory: true) }
        #endif
        return defaultFolder
    }

    /// Acquire the folder to write a dump into, plus a `release` closure — or `nil` to **skip** the
    /// write (a custom folder is set but no longer at its chosen path). The arm-time ``isReachable``
    /// check gates arming, so `nil` is defensive; the recording of a folder that vanished mid-measure
    /// is skipped rather than silently redirected. No custom folder → the default container.
    static func acquireDumpFolder() -> (folder: URL, release: () -> Void)? {
        #if os(macOS)
        if hasCustomFolder {
            guard let url = resolveAtChosenPath() else { return nil }
            return (url, { url.stopAccessingSecurityScopedResource() })
        }
        #endif
        return (defaultFolder, {})
    }

    /// Whether the configured dump folder can be written to **right now** — checked at New Tap / at
    /// launch auto-arm. No custom folder → true (the default is always reachable).
    /// A custom folder is reachable only if the bookmark resolves **to the chosen path** and is
    /// writable; a rename / move / trash / delete makes it false, and the user must fix it.
    static var isReachable: Bool {
        #if os(macOS)
        guard hasCustomFolder else { return true }
        guard let url = resolveAtChosenPath() else { return false }
        defer { url.stopAccessingSecurityScopedResource() }
        return (try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)) != nil
        #else
        return true
        #endif
    }

    #if os(macOS)
    /// Present an `NSOpenPanel` to choose a dump folder; persist the security-scoped bookmark **and
    /// the chosen path**. Opens at the real `~/Documents/GuitarTap`. Returns `true` if a folder was
    /// chosen.
    @MainActor static func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the folder Guitar Tap saves captured audio (WAV files) to"
        panel.directoryURL = MeasurementFileExporter.startDirectory
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? url.bookmarkData(options: .withSecurityScope,
                                               includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return false }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        UserDefaults.standard.set(url.path, forKey: pathKey)
        return true
    }

    /// Forget the custom folder — revert to the default container folder.
    static func useDefaultFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: pathKey)
    }

    /// Reveal the current dump folder in Finder (the custom folder if reachable, else the default).
    @MainActor static func revealInFinder() {
        if let (folder, release) = acquireDumpFolder() {
            defer { release() }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } else {
            // Custom folder is set but unreachable — nothing to reveal there; show the default.
            try? FileManager.default.createDirectory(at: defaultFolder, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([defaultFolder])
        }
    }
    #endif
}