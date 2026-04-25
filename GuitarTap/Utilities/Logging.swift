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
// Both write to the unified log (Console.app, subsystem: com.dolcesfogato.guitar-tap)
// and appear in the Xcode console during development.

private let _gtLogEnabled = true
private let _tapDebugEnabled = true

private let _logger = Logger(subsystem: "com.dolcesfogato.guitar-tap", category: "general")
private let _tapLogger = Logger(subsystem: "com.dolcesfogato.guitar-tap", category: "tap-detection")

public func gtLog(_ message: @autoclosure () -> String) {
    if _gtLogEnabled {
        let msg = message()
        _logger.debug("\(msg, privacy: .public)")
    }
}

public func TAP_DEBUG(_ category: String, _ message: @autoclosure () -> String) {
    if _tapDebugEnabled {
        let msg = message()
        _tapLogger.debug("TAP_DEBUG \(category, privacy: .public): \(msg, privacy: .public)")
    }
}
