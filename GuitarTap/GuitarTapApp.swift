//
//  guitar_tap_App.swift
//  GuitarTap
//
//  Created by David Smith on 12/31/25.
//
import SwiftUI
import Foundation

#if os(macOS)
/// Redirects stdout and stderr to a file so print() output is captured even when
/// the app is force-restarted by macOS outside of Xcode's debugger.
/// The log file is at ~/Library/Logs/GuitarTap/debug.log
/// Returns true when a debugger (e.g. Xcode) is attached to this process.
/// Used to skip file redirection so Xcode's console still receives output.
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
