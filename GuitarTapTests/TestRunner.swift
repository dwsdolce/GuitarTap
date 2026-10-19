// TestRunner.swift
// GuitarTapTests
//
// A minimal XCTestCase subclass that acts as the test runner entry point
// on iPhone. Without at least one XCTestCase in the bundle, the XCTest
// runner on iPhone silently discovers zero tests, and none of the Swift
// Testing (@Test) functions run.
//
// TapDisplaySettings.defaults is now redirected to an isolated UserDefaults
// suite at its declaration site (in TapDisplaySettings.swift) using a
// ProcessInfo environment check. No further setup is needed here.
//
// @parity none — the XCTest entry point Swift Testing needs on the iPad and iPhone; the other editions'
// runners need none.

import XCTest
import Testing
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - XCTest entry point (required for Swift Testing on iPhone)
// ---------------------------------------------------------------------------

final class TestRunner: XCTestCase {
    // This stub test method is required on iPad/iPhone: without at least one
    // XCTestCase test method in the bundle, the XCTest runner does not
    // bootstrap the Swift Testing runner and no @Test functions execute.
    func testRunnerBootstrap() { }
}
