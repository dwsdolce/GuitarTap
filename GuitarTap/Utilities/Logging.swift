import Foundation

// Debug logging utility.
//
// Mirrors Python GuitarTap/utilities/logging.py.
//
// To enable: set ENABLE_TAP_DEBUG=1 in the scheme's environment variables
// (Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables).

private let _tapDebugEnabled = ProcessInfo.processInfo.environment["ENABLE_TAP_DEBUG"] != nil

public func TAP_DEBUG(_ category: String, _ message: @autoclosure () -> String) {
    if _tapDebugEnabled {
        print("TAP_DEBUG [\(category)] \(message())")
    }
}
