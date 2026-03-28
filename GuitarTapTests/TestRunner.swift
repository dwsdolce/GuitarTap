// TestRunner.swift
// GuitarTapTests
//
// A minimal XCTestCase subclass that acts as the test runner entry point
// on iPhone. Without at least one XCTestCase in the bundle, the XCTest
// runner on iPhone silently discovers zero tests, and none of the Swift
// Testing (@Test) functions run.
//
// This file has no test methods of its own; its sole purpose is to cause
// the XCTest runner to initialise properly so that all Swift Testing tests
// are discovered and executed.
//
// It also redirects TapDisplaySettings to an isolated UserDefaults suite so
// that test runs can never read from or write to the real user's settings.

import XCTest
@testable import GuitarTap

private let testSuiteName = "com.guitartap.tests"

final class TestRunner: XCTestCase {

    /// Runs once before any test in the bundle. Redirects TapDisplaySettings
    /// to an isolated UserDefaults suite and wipes any leftover state from
    /// previous runs so every test starts from a clean slate.
    override class func setUp() {
        super.setUp()
        let isolated = UserDefaults(suiteName: testSuiteName)!
        isolated.removePersistentDomain(forName: testSuiteName)
        TapDisplaySettings.defaults = isolated
    }
}
