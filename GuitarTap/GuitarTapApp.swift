// @parity app/entry
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
/// ## Global Constants
///
/// | Constant | Value |
/// |---|---|
/// | `appVersion` | `CFBundleShortVersionString` + ` (` + `CFBundleVersion` + `)` |
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



let appVersion: String = {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    return "\(version) (\(build))"
}()
let appTitle: String = {
    let name = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? "Guitar Tap"
    return "\(name) \(appVersion)"
}()

#if os(macOS)
// MARK: - Menu Actions (stable class reference for FocusedValue)

/// Holds all menu-driven action closures as mutable properties on a single
/// class instance.  Because a class has stable reference identity, SwiftUI's
/// `@FocusedValue` machinery sees the *same* object on every render of
/// `TapToneAnalysisView` and does not mark the focused value as changed.
/// This prevents `AppCommands.body` from re-evaluating on every audio frame,
/// which was the root cause of the Edit-menu flickering.
@Observable
final class MenuActions {
    var openAudioFile: (() -> Void)?
    var saveMeasurement: (() -> Void)?
    var exportSpectrum: (() -> Void)?
    var exportPDF: (() -> Void)?
    var autoScaleDB: (() -> Void)?
    var cycleAnnotations: (() -> Void)?
    var showMetrics: (() -> Void)?
    var showMeasurements: (() -> Void)?
    var showSettings: (() -> Void)?
    /// Mirrors the analyzer's `hasResultToSaveOrExport`: Save and the exports are enabled only when there
    /// is something to save or export. Observed, so the menu updates when it changes.
    var hasResultToSaveOrExport = false
    /// Mirrors the engine's `isRunning`: a file plays only while the audio engine runs.
    var isRunning = false
}

// MARK: - Focused Scene Value

private struct MenuActionsKey: FocusedValueKey { typealias Value = MenuActions }

extension FocusedValues {
    var menuActions: MenuActions? {
        get { self[MenuActionsKey.self] }
        set { self[MenuActionsKey.self] = newValue }
    }
}

// MARK: - macOS Menu Commands

/// Static menu command replacements that have no focused-value dependencies.
///
/// Separating these from `AppCommands` is intentional: `AppCommands` holds
/// `@FocusedValue` properties that SwiftUI re-evaluates on every audio-driven
/// state change (the FFT publishes `magnitudes` at ~2 Hz while running). When
/// the `replacing:` groups were inside `AppCommands`, every re-evaluation
/// caused SwiftUI to reconstruct the Edit menu's NSMenu items, producing
/// continuous `didChangeImage` mismatches and visible menu flickering.
///
/// By isolating the stable `replacing:` groups here — with no dynamic
/// dependencies — SwiftUI only evaluates this struct once and never tears
/// down the resulting NSMenu items.
struct StaticCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Remove the "New Window" menu command while preserving the standard app menu
        CommandGroup(replacing: .newItem) {}

        // Remove Edit menu groups that have no use in GuitarTap (no undo/redo
        // support, no document editing, find, spell-check, or text transformations).
        CommandGroup(replacing: .undoRedo) {}
        CommandGroup(replacing: .textEditing) {}

        // Replace the default Help menu item with one that opens the in-app Help window.
        CommandGroup(replacing: .help) {
            Button("Quick Start Guide") {
                openWindow(id: "help")
            }
            .keyboardShortcut("?", modifiers: .command)

            Button("User Manual") {
                if let url = DocumentationLinks.userManual {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

/// Dynamic menu command additions that delegate to the focused scene.
///
/// File and View menu items delegate to the focused scene via `@FocusedValue`
/// so they always target the active `TapToneAnalysisView`. This struct
/// re-evaluates whenever a focused value changes, but because it only
/// *adds* items (never replaces), rebuilding it does not disturb the
/// NSMenu items created by `StaticCommands`.
struct AppCommands: Commands {
    @FocusedValue(\.menuActions) private var menuActions

    var body: some Commands {
        // App menu — Settings item with standard ⌘, shortcut
        CommandGroup(after: .appInfo) {
            Button("Settings…") {
                menuActions?.showSettings?()
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(menuActions?.showSettings == nil)
        }

        // File menu — Play File, Save and Export actions
        CommandGroup(after: .saveItem) {
            Button("Play Audio File…") {
                menuActions?.openAudioFile?()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
            .disabled(menuActions?.openAudioFile == nil || menuActions?.isRunning != true)

            Divider()

            Button("Save Measurement…") {
                menuActions?.saveMeasurement?()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(menuActions?.saveMeasurement == nil || menuActions?.hasResultToSaveOrExport != true)

            Divider()

            Button("Export Spectrum Image…") {
                menuActions?.exportSpectrum?()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(menuActions?.exportSpectrum == nil || menuActions?.hasResultToSaveOrExport != true)

            Button("Export PDF Report…") {
                menuActions?.exportPDF?()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(menuActions?.exportPDF == nil || menuActions?.hasResultToSaveOrExport != true)
        }

        // View menu — inject display controls after the sidebar group so they
        // appear in the existing View menu rather than creating a duplicate.
        CommandGroup(after: .sidebar) {
            Divider()

            Button("Auto dB") {
                menuActions?.autoScaleDB?()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(menuActions?.autoScaleDB == nil)

            Button("Cycle Annotations") {
                menuActions?.cycleAnnotations?()
            }
            .keyboardShortcut("`", modifiers: .command)
            .disabled(menuActions?.cycleAnnotations == nil)

            Divider()

            Button("Show Metrics") {
                menuActions?.showMetrics?()
            }
            .keyboardShortcut("m", modifiers: .command)
            .disabled(menuActions?.showMetrics == nil)

            Button("Show Measurements") {
                menuActions?.showMeasurements?()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(menuActions?.showMeasurements == nil)
        }
    }
}
#endif

#if os(macOS)
/// macOS app delegate.
///
/// Guitar Tap is a single-window utility on macOS, so it quits when the main
/// window is closed — the Apple-sanctioned behavior for single-window apps
/// (App Store Guideline 4). Without this, closing the window leaves the app
/// running with no way to reopen it. This is macOS-only: iOS apps must never
/// terminate themselves.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif

// MARK: - App Entry Point
@main
struct GuitarTapApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    /// True when this process was launched only to HOST a test bundle.
    ///
    /// `GuitarTapTests` is a hosted bundle, so running the tests launches this app —
    /// which would otherwise build the full UI, construct a live `TapToneAnalyzer`,
    /// open the microphone, and run 65 536-point FFTs on room audio alongside the
    /// suite being measured. That instance shares the process with the tests: the same
    /// isolated `TapDisplaySettings` suite, the same CPU, and the same static
    /// diagnostics.
    ///
    /// `XCTestConfigurationFilePath` is set by the test runner and never on a normal
    /// launch — the same signal `TapDisplaySettings` already uses to redirect storage.
    private static let isHostingTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// The app's real UI, or nothing at all when hosting tests.
    ///
    /// Tests build their own analyzers via `forTesting()` and never reach for the
    /// app's, so suppressing this costs them nothing.
    @ViewBuilder
    private var rootView: some View {
        if Self.isHostingTests {
            Color.clear
        } else {
            TapToneAnalysisView()
                .onAppear { Palette.apply(TapDisplaySettings.appearance) }
        }
    }

    var body: some Scene {
        #if os(macOS)
        // On macOS, use Window instead of WindowGroup to prevent multiple instances
        Window(appTitle, id: "main") {
            rootView
                .onOpenURL { url in
                    NotificationCenter.default.post(
                        name: .openMeasurementFile,
                        object: url
                    )
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands { StaticCommands() }
        .commands { AppCommands() }

        // Help window - opened via the Help menu item.
        // .commandsRemoved() prevents SwiftUI from adding a "Help" entry to
        // the Window menu for this scene.
        Window("Quick Start Guide", id: "help") {
            NavigationStack {
                HelpView()
            }
            .onAppear {
                // Prevent the Help window from being restored on next launch.
                NSApp.windows.first { $0.title == "Quick Start Guide" }?.isRestorable = false
            }
        }
        .defaultSize(width: 520, height: 620)
        .commandsRemoved()
        #else
        // On iOS, WindowGroup is appropriate.
        // `handlesExternalEvents(matching:)` on the scene prevents iOS from
        // spawning a new app instance for each incoming document URL (e.g.
        // AirDrop imports).  Without this, every received .guitartap file
        // opens a fresh copy of the app.  The wildcard set routes all URLs
        // to the existing scene when one is already running.
        WindowGroup {
            rootView
                .onOpenURL { url in
                    NotificationCenter.default.post(
                        name: .openMeasurementFile,
                        object: url
                    )
                }
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["*"])
        #endif
    }
}
