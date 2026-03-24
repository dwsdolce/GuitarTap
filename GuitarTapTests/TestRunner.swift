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

import XCTest

final class TestRunner: XCTestCase {}
