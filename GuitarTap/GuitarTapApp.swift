//
//  guitar_tap_App.swift
//  GuitarTap
//
//  Created by David Smith on 12/31/25.
//
import SwiftUI

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
// MARK: - macOS Menu Commands
struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Remove the "New Window" menu command while preserving the standard app menu
        CommandGroup(replacing: .newItem) {}

        // Replace the default Help menu with one that opens our Help window
        CommandGroup(replacing: .help) {
            Button("\(appTitle) Help") {
                openWindow(id: "help")
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}
#endif

// MARK: - App Entry Point
@main
struct GuitarTapApp: App {
    var body: some Scene {
        #if os(macOS)
        // On macOS, use Window instead of WindowGroup to prevent multiple instances
        Window(appTitle, id: "main") {
            TapToneAnalysisView()
        }
        .commands { AppCommands() }

        // Help window - opened from the Help menu
        Window("Help", id: "help") {
            NavigationStack {
                HelpView()
            }
        }
        .defaultSize(width: 520, height: 620)
        #else
        // On iOS, WindowGroup is appropriate
        WindowGroup {
            TapToneAnalysisView()  
        }
        #endif
    }
}
