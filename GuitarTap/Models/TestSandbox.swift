//
//  TestSandbox.swift
//  GuitarTap
//
//  Where persistent state lives under test: a PER-PROCESS sandbox, never a shared one.
//
//  Mirrors Python's models/settings_scope.py.
//

import Foundation

/// The per-process test sandbox discriminator.
///
/// Under XCTest, `TapDisplaySettings` redirects UserDefaults to an isolated suite and
/// `measurementsFileURL` redirects to a temp directory, so a test run never touches real user data.
/// Both names carry the PROCESS ID, and that is the point.
///
/// They used to be the fixed `com.guitartap.tests`: one UserDefaults suite and one directory shared
/// by every process. The suite is wiped on first access ("so every test run starts with factory
/// defaults"), so a second `xcodebuild test` wiped the settings of a run already in flight. The
/// victim carried on with defaults — a different measurement type, hence different guitar mode
/// bands, hence different peak classification.
///
/// Verified 2026-09-20: writing a probe key into
/// `~/Library/Containers/com.dolcesfogato.GuitarTap/Data/Library/Preferences/com.guitartap.tests.plist`
/// from another process and then running the suite deleted it. The identical defect in Python cost
/// a long investigation — it reproduces only when two test processes overlap, so never in
/// isolation, never under load, and independent of test order. Keep the id.
///
/// Not an application concern: a real app is one process with its own domain.
enum TestSandbox {
    /// The discriminator, or `nil` when running as the real app.
    ///
    /// `XCTestConfigurationFilePath` is set by the test runner and never on a normal launch — the
    /// same signal `GuitarTapApp` uses to render nothing while hosting tests.
    nonisolated static let id: String? = {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil else {
            return nil
        }
        return String(ProcessInfo.processInfo.processIdentifier)
    }()

    /// Whether this process is running under test.
    nonisolated static var isActive: Bool { id != nil }

    /// `base` when running for real, `base.<pid>` under test.
    nonisolated static func name(_ base: String) -> String {
        guard let id else { return base }
        return "\(base).\(id)"
    }

    /// Delete sandbox suites left behind by test processes that are no longer running.
    ///
    /// Per-process names fix the wiping, but they would otherwise leave one plist per run forever.
    /// An `atexit` hook is registered too, and in practice it does not always land — the runner may
    /// terminate the host, and `removePersistentDomain` is flushed asynchronously by `cfprefsd`. So
    /// cleanup does not depend on exit: every run reaps its dead predecessors, which is self-healing
    /// even after a crash or a killed run.
    nonisolated static func reapStaleSandboxes(base: String) {
        guard isActive else { return }
        let fm = FileManager.default
        guard let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let prefs = library.appendingPathComponent("Preferences")
        guard let entries = try? fm.contentsOfDirectory(atPath: prefs.path) else { return }

        let prefix = "\(base)."
        let mine = ProcessInfo.processInfo.processIdentifier
        for entry in entries where entry.hasPrefix(prefix) && entry.hasSuffix(".plist") {
            let middle = entry.dropFirst(prefix.count).dropLast(".plist".count)
            guard let pid = Int32(middle), pid != mine else { continue }
            // kill(pid, 0) succeeds only while that process still exists.
            guard kill(pid, 0) != 0 else { continue }
            let suite = "\(base).\(pid)"
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? fm.removeItem(at: prefs.appendingPathComponent(entry))
        }
    }
}
