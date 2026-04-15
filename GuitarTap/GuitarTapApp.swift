//
//  GuitarTapApp.swift
//  GuitarTap
//

/// # GuitarTapApp
///
/// Application entry point and macOS menu-command definitions.
///
/// ## App Structure
///
/// - **macOS**: Uses a single `Window` scene (not `WindowGroup`) to prevent
///   multiple instances. A separate `Window` with id `"help"` is declared for
///   the Help panel opened via `⌘?`.
/// - **iOS**: Uses a standard `WindowGroup`.
///
/// Both platforms handle `onOpenURL` by posting
/// `Notification.Name.openMeasurementFile` so that `MeasurementsListView`
/// can import the file regardless of which view is currently on screen.
///
/// ## Debug Log Redirection (macOS only)
///
/// `redirectOutputToFile()` runs at app init. When no debugger is attached it
/// redirects `stdout` and `stderr` to
/// `~/Library/Logs/GuitarTap-debug.log` (sandbox-relative) using
/// `dup2`, enabling post-mortem log inspection after force restarts. Each
/// launch appends an ISO 8601 timestamp separator so successive runs are easy
/// to distinguish. When Xcode is attached the function is a no-op.
///
/// ## Global Constants
///
/// | Constant | Value |
/// |---|---|
/// | `appVersion` | `CFBundleShortVersionString` + `_` + `CFBundleVersion` |
/// | `appTitle` | `CFBundleDisplayName` (or `CFBundleName`) + `appVersion` |
///
/// - SeeAlso: `TapToneAnalysisView`, `HelpView`, `MeasurementsListView`

import SwiftUI
import Foundation

extension Notification.Name {
    /// Posted when the OS asks the app to open a measurement file.
    /// The `object` is the file `URL`.
    static let openMeasurementFile = Notification.Name("GuitarTap.openMeasurementFile")
}

#if os(macOS)
/// Returns `true` when a debugger (e.g. Xcode) is attached to this process.
///
/// Used to skip `stdout`/`stderr` redirection so Xcode's console still
/// receives output during development. Implemented via `sysctl` and the
/// `P_TRACED` process flag.
private func isDebuggerAttached() -> Bool {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    sysctl(&mib, 4, &info, &size, nil, 0)
    return (info.kp_proc.p_flag & P_TRACED) != 0
}

private func redirectOutputToFile() {
    // When running under Xcode, keep stdout/stderr on the console as normal.
    guard !isDebuggerAttached() else { return }

    // The app is sandboxed — write inside the container's Library/Logs directory
    guard let containerLibrary = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
    let logDir = containerLibrary.appendingPathComponent("Logs")
    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    let logFile = logDir.appendingPathComponent("GuitarTap-debug.log")
    // Append mode so successive restarts don't overwrite each other
    if FileManager.default.fileExists(atPath: logFile.path) == false {
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
    }
    if let fd = fopen(logFile.path, "a") {
        // Timestamp separator so restarts are easy to spot
        let ts = ISO8601DateFormatter().string(from: Date())
        fputs("\n\n=== GuitarTap launched \(ts) ===\n", fd)
        fflush(fd)
        dup2(fileno(fd), STDOUT_FILENO)
        dup2(fileno(fd), STDERR_FILENO)
        fclose(fd)
        setbuf(stdout, nil)   // unbuffered so writes appear immediately
    }
}
#endif

let appVersion: String = {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    return "\(version)_\(build)"
}()
let appTitle: String = {
    let name = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? "Guitar Tap"
    return "\(name) \(appVersion)"
}()

#if os(macOS)
// MARK: - Focused Scene Values

/// Keys that `TapToneAnalysisView` publishes into the focused scene so that
/// `AppCommands` can drive them from the menu bar without a direct view reference.
private struct SaveMeasurementKey: FocusedValueKey { typealias Value = () -> Void }
private struct ExportSpectrumKey: FocusedValueKey { typealias Value = () -> Void }
private struct ExportPDFKey: FocusedValueKey { typealias Value = () -> Void }
private struct AutoScaleDBKey: FocusedValueKey { typealias Value = () -> Void }
private struct CycleAnnotationsKey: FocusedValueKey { typealias Value = () -> Void }
private struct ShowMetricsKey: FocusedValueKey { typealias Value = () -> Void }
private struct ShowMeasurementsKey: FocusedValueKey { typealias Value = () -> Void }
private struct ShowSettingsKey: FocusedValueKey { typealias Value = () -> Void }

extension FocusedValues {
    var saveMeasurement: (() -> Void)? {
        get { self[SaveMeasurementKey.self] }
        set { self[SaveMeasurementKey.self] = newValue }
    }
    var exportSpectrum: (() -> Void)? {
        get { self[ExportSpectrumKey.self] }
        set { self[ExportSpectrumKey.self] = newValue }
    }
    var exportPDF: (() -> Void)? {
        get { self[ExportPDFKey.self] }
        set { self[ExportPDFKey.self] = newValue }
    }
    var autoScaleDB: (() -> Void)? {
        get { self[AutoScaleDBKey.self] }
        set { self[AutoScaleDBKey.self] = newValue }
    }
    var cycleAnnotations: (() -> Void)? {
        get { self[CycleAnnotationsKey.self] }
        set { self[CycleAnnotationsKey.self] = newValue }
    }
    var showMetrics: (() -> Void)? {
        get { self[ShowMetricsKey.self] }
        set { self[ShowMetricsKey.self] = newValue }
    }
    var showMeasurements: (() -> Void)? {
        get { self[ShowMeasurementsKey.self] }
        set { self[ShowMeasurementsKey.self] = newValue }
    }
    var showSettings: (() -> Void)? {
        get { self[ShowSettingsKey.self] }
        set { self[ShowSettingsKey.self] = newValue }
    }
}

// MARK: - macOS Menu Commands

/// macOS menu bar command definitions for GuitarTap.
///
/// Removes the default "New Window" item (the app uses a single `Window` scene)
/// and replaces the standard Help menu entry with a button that opens the
/// dedicated Help window (`id: "help"`) via the `openWindow` environment action.
///
/// File and View menu items delegate to the focused scene via `@FocusedValue`
/// so they always target the active `TapToneAnalysisView`.
struct AppCommands: Commands {
    @FocusedValue(\.saveMeasurement) private var saveMeasurement
    @FocusedValue(\.exportSpectrum) private var exportSpectrum
    @FocusedValue(\.exportPDF) private var exportPDF
    @FocusedValue(\.autoScaleDB) private var autoScaleDB
    @FocusedValue(\.cycleAnnotations) private var cycleAnnotations
    @FocusedValue(\.showMetrics) private var showMetrics
    @FocusedValue(\.showMeasurements) private var showMeasurements
    @FocusedValue(\.showSettings) private var showSettings

    var body: some Commands {
        // Remove the "New Window" menu command while preserving the standard app menu
        CommandGroup(replacing: .newItem) {}

        // App menu — Settings item with standard ⌘, shortcut
        CommandGroup(after: .appInfo) {
            Button("Settings…") {
                showSettings?()
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(showSettings == nil)
        }

        // File menu — Save and Export actions
        CommandGroup(after: .saveItem) {
            Button("Save Measurement…") {
                saveMeasurement?()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(saveMeasurement == nil)

            Divider()

            Button("Export Spectrum Image…") {
                exportSpectrum?()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(exportSpectrum == nil)

            Button("Export PDF Report…") {
                exportPDF?()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(exportPDF == nil)
        }

        // View menu — inject display controls after the sidebar group so they
        // appear in the existing View menu rather than creating a duplicate.
        CommandGroup(after: .sidebar) {
            Divider()

            Button("Auto dB") {
                autoScaleDB?()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(autoScaleDB == nil)

            Button("Cycle Annotations") {
                cycleAnnotations?()
            }
            .keyboardShortcut("`", modifiers: .command)
            .disabled(cycleAnnotations == nil)

            Divider()

            Button("Show Metrics") {
                showMetrics?()
            }
            .keyboardShortcut("m", modifiers: .command)
            .disabled(showMetrics == nil)

            Button("Show Measurements") {
                showMeasurements?()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(showMeasurements == nil)
        }

        // Remove Edit menu groups that have no use in GuitarTap (no undo/redo
        // support, no document editing, find, spell-check, or text transformations).
        CommandGroup(replacing: .undoRedo) {}
        CommandGroup(replacing: .textEditing) {}

        // Keep the default Help menu as-is; the system Help menu item
        // is sufficient and the search field works for menu navigation.
    }
}
#endif

// MARK: - App Entry Point
@main
struct GuitarTapApp: App {
    init() {
        #if os(macOS)
        redirectOutputToFile()
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        // On macOS, use Window instead of WindowGroup to prevent multiple instances
        Window(appTitle, id: "main") {
            TapToneAnalysisView()
                .onOpenURL { url in
                    NotificationCenter.default.post(
                        name: .openMeasurementFile,
                        object: url
                    )
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands { AppCommands() }

        // Help window - opened via the Help menu item.
        // .commandsRemoved() prevents SwiftUI from adding a "Help" entry to
        // the Window menu for this scene.
        Window("Help", id: "help") {
            NavigationStack {
                HelpView()
            }
            .onAppear {
                // Prevent the Help window from being restored on next launch.
                NSApp.windows.first { $0.title == "Help" }?.isRestorable = false
            }
        }
        .defaultSize(width: 520, height: 620)
        .commandsRemoved()
        #else
        // On iOS, WindowGroup is appropriate
        WindowGroup {
            TapToneAnalysisView()
                .onOpenURL { url in
                    NotificationCenter.default.post(
                        name: .openMeasurementFile,
                        object: url
                    )
                }
        }
        #endif
    }
}
