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
// Both write to:
//   macOS : ~/Documents/GuitarTap/GuitarTap-debug.log  (alongside saved measurements)
//   iOS   : Files app → On My iPhone → GuitarTap → GuitarTap-debug.log
// and to the unified log (Console.app, subsystem: com.dolcesfogato.guitar-tap)
// during development.

private let _gtLogEnabled = true
private let _tapDebugEnabled = true

private let _logger = Logger(subsystem: "com.dolcesfogato.guitar-tap", category: "general")

// MARK: - File logger

private let _fileLogger = FileLogger()

private final class FileLogger: @unchecked Sendable {
    private let fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.dolcesfogato.guitar-tap.filelog")

    /// macOS: ~/Documents/GuitarTap/GuitarTap-debug.log (same folder as saved measurements)
    /// iOS:   Documents/GuitarTap-debug.log (visible in Files app → GuitarTap)
    static var logFileURL: URL? {
        #if os(macOS)
        // Use homeDirectoryForCurrentUser to bypass the sandbox container redirect
        // and write to the real ~/Documents/GuitarTap alongside saved measurements.
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
