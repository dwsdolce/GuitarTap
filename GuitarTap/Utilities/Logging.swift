import Foundation
import OSLog
import QuartzCore

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

// Off, as in Python: when on, every gtLog call is written to the debug log file, which
// grows for the whole session. Turn it on to diagnose a problem, and off again after.
private let _gtLogEnabled = false
private let _tapDebugEnabled = false

private let _logger = Logger(subsystem: "com.dolcesfogato.guitar-tap", category: "general")

// MARK: - File logger

private let _fileLogger = FileLogger()

private final class FileLogger: @unchecked Sendable {
    private let fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.dolcesfogato.guitar-tap.filelog")

    /// Wall-clock stamp, ISO 8601 UTC with milliseconds.
    private static let stampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Monotonic origin for the `t=` column.
    private let logStart = CACurrentMediaTime()

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
    /// The log deliberately does **not** follow the user-settable WAV folder:
    /// it is plumbing, not a user artifact.
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
        // Never write the shared debug log from a test run.
        //
        // The file is a FIELD diagnostic: it is what the user sends after a failure,
        // and every session in it should be a session of the app. A test run appends
        // hundreds of construct/teardown cycles that look exactly like app activity,
        // which makes a real log unreadable — while chasing the silent-input bug, two
        // `xcodebuild test` runs in this file were initially misread as an app defect.
        // Mirrors the same XCTest check that already redirects `measurementsFileURL`
        // and `TapDisplaySettings`. OSLog output is unaffected, so test diagnostics are
        // still available in Console.app; only the shared file is left alone.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            fileHandle = nil
            return
        }

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

    /// Writes one stamped line.
    ///
    /// Every line carries BOTH a wall clock and a monotonic elapsed time, because the
    /// pair is what makes a SLEEP visible. `CACurrentMediaTime()` is suspended while the
    /// machine sleeps; `Date()` is not. So a line whose wall-clock gap far exceeds its
    /// `t=` gap is the first line after a wake — which is otherwise invisible in a log
    /// and is exactly the event under investigation for the silent-input failure.
    /// Ordinary gaps (an idle app, a long capture) move both clocks together.
    ///
    /// Both are sampled at CALL time rather than when the queue drains, so the stamps
    /// reflect when something happened, not when the writer got around to it.
    func write(_ message: String) {
        guard let handle = fileHandle else { return }
        let wall = FileLogger.stampFormatter.string(from: Date())
        let mono = CACurrentMediaTime() - logStart
        queue.async {
            let body = message.hasSuffix("\n") ? String(message.dropLast()) : message
            let line = String(format: "%@ t=%9.3f %@\n", wall, mono, body)
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
