import Foundation
import OSLog

// Debug logging utility.
//
// Mirrors Python GuitarTap/utilities/logging.py.
//
// gtLog  — general-purpose debug logging. Replace print() calls with this.
//           To disable all gtLog output after beta, set _gtLogEnabled = false.
//
// TAP_DEBUG — tap-detection specific logging, controlled by _tapDebugEnabled.
//
// Both write to the APP'S Documents/GuitarTap — which under the sandbox is the CONTAINER's
// Documents, not the user's ~/Documents (nothing may be written there without the user
// selecting the folder):
//   macOS : ~/Library/Containers/<bundle-id>/Data/Documents/GuitarTap/GuitarTap-debug.log
//   iOS   : Files app → On My iPhone → GuitarTap → GuitarTap-debug.log
// and to the unified log (Console.app, subsystem: com.dolcesfogato.guitar-tap)
// during development.

private let _gtLogEnabled = false
private let _tapDebugEnabled = false

private let _logger = Logger(subsystem: "com.dolcesfogato.guitar-tap", category: "general")

// MARK: - File logger

private let _fileLogger = FileLogger()

private final class FileLogger: @unchecked Sendable {
    private let fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.dolcesfogato.guitar-tap.filelog")

    /// The app's `Documents/GuitarTap/GuitarTap-debug.log`.
    ///
    /// Under App Sandbox that is the **container's** Documents
    /// (`~/Library/Containers/<bundle-id>/Data/Documents/GuitarTap/`) — which is what "the app's
    /// Documents" means on a sandboxed platform. It is NOT the user's `~/Documents`, and it cannot
    /// be: nothing may be written there without the user selecting the folder.
    ///
    /// iOS: the container's `Documents/` — reachable in Files → On My iPhone → GuitarTap
    /// (`UIFileSharingEnabled`).
    ///
    /// The log deliberately does **not** follow the user-settable WAV folder
    /// (FILE-PATHS-AND-NAMES-SPEC §4c): it is plumbing, not a user artifact.
    static var logFileURL: URL? {
        #if os(macOS)
        // homeDirectoryForCurrentUser returns the CONTAINER home under the sandbox — as does
        // NSHomeDirectory(). (An earlier comment here claimed this "bypasses the sandbox container
        // redirect" and wrote to the real ~/Documents. It does not, and never did.)
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/GuitarTap")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("GuitarTap-debug.log")
        #else
        guard let docsDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first
        else { return nil }
        return docsDir.appendingPathComponent("GuitarTap-debug.log")
        #endif
    }

    init() {
        guard let url = FileLogger.logFileURL else {
            fileHandle = nil
            return
        }
        let fm = FileManager.default
        // Documents directory always exists; no need to create it.
        // Create the log file if it doesn't exist; append if it does.
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
        fileHandle = handle
        let banner = "=== GuitarTap session started \(ISO8601DateFormatter().string(from: Date())) ===\n"
        write(banner)
    }

    deinit {
        try? fileHandle?.close()
    }

    func write(_ message: String) {
        guard let handle = fileHandle else { return }
        queue.async {
            let line = message.hasSuffix("\n") ? message : message + "\n"
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
        }
    }
}

// MARK: - Public logging functions

public func gtLog(_ message: @autoclosure () -> String) {
    if _gtLogEnabled {
        let msg = message()
        _logger.debug("\(msg, privacy: .public)")
        _fileLogger.write(msg)
    }
}

public func TAP_DEBUG(_ category: String, _ message: @autoclosure () -> String) {
    if _tapDebugEnabled {
        let msg = message()
        _logger.debug("TAP_DEBUG \(category, privacy: .public): \(msg, privacy: .public)")
        _fileLogger.write("TAP_DEBUG \(category): \(msg)")
    }
}
