//
//  BufferWatchdogTests.swift
//  GuitarTapTests
//
//  The buffer watchdog's tick and recovery, against the shared cases in `buffer-watchdog.json`
//  (BW1–BW14), the same as Python and the web: the start-up grace, the guards, a recovery for no
//  buffers or for buffers with no signal, the backoff between restarts, giving up while still
//  watching, a restart that observes no signal, a failed restart retrying, and a healthy tick
//  clearing it all. The engine runs on a wall clock moved by hand, with a stand-in for the
//  recovery's restart; the tick runs at each whole second, as the 1 s timer does.
//
//  Mirrors: tests/test_buffer_watchdog.py · test/buffer-watchdog.test.ts
//
// @parity test/buffer-watchdog

import Testing
import Foundation
@testable import GuitarTap

private final class BufferWatchdogAnchor {}

@Suite("BufferWatchdog", .serialized)
@MainActor
struct BufferWatchdogTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: BufferWatchdogAnchor.self).url(forResource: "buffer-watchdog", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids() -> [String] {
        (data["cases"] as! [[String: Any]]).filter { $0["only"] as? String != "web" }.map { $0["id"] as! String }
    }

    /// Exact in binary, so every time the cases reach is exact in every edition.
    static let step: TimeInterval = 0.5

    struct RestartFailed: Error {}

    /// One case's engine, clock and restart stand-in.
    final class Run {
        let clock = ManualWallClock()
        let sut = RealtimeFFTAnalyzer.forTesting()
        var restartFails = false
        var restartTimes: [TimeInterval] = []

        init() {
            sut.wallClock = clock
            // The test host may not be authorized for the microphone (a CI runner is not).
            sut.microphoneAuthorized = { true }
            // The stand-in for `start()`: on success, what `start()` does for the watchdog — the engine
            // running again, and the watchdog re-armed as a recovery (`isRecoveringEngine` is still true).
            sut.watchdogRestart = { [unowned self] in
                restartTimes.append(clock.now())
                if restartFails { throw RestartFailed() }
                sut.isRunning = true
                sut.engineStartFailed = false
                sut.startBufferWatchdog(isRecovery: sut.isRecoveringEngine)
            }
        }

        func run(_ seconds: TimeInterval, _ input: String) {
            for _ in 0..<Int((seconds / BufferWatchdogTests.step).rounded()) {
                clock.advance(by: BufferWatchdogTests.step)
                if input != "none" { sut.lastBufferTime = clock.now() }
                if input == "signal" { sut.lastSignalTime = clock.now() }
                if clock.now().truncatingRemainder(dividingBy: 1) == 0 { sut.checkBufferWatchdog() }
            }
        }

        func check(_ fields: [String: Any], _ id: String) {
            for (field, want) in fields {
                let msg = Comment(rawValue: "\(id) \(field)")
                switch field {
                case "attempts": #expect(sut.watchdogRecoveryAttempts == want as? Int, msg)
                case "recovering": #expect(sut.isRecoveringEngine == want as? Bool, msg)
                case "givenUp": #expect(sut.watchdogRecoveryExhausted == want as? Bool, msg)
                case "inputDead": #expect(sut.inputAppearsDead == want as? Bool, msg)
                case "couldNotRestart": #expect(sut.inputCouldNotRestart == want as? Bool, msg)
                case "inputUnavailable": #expect(sut.inputUnavailable == want as? Bool, msg)
                case "permissionDenied": #expect(sut.microphonePermissionDenied == want as? Bool, msg)
                case "restarts": #expect(restartTimes.count == want as? Int, msg)
                case "restartTimes":
                    #expect(restartTimes == (want as! [Double]), "\(id) \(field): \(restartTimes)")
                default: Issue.record("\(id): unknown field \(field)")
                }
            }
        }
    }

    @Test(arguments: ids())
    func bufferWatchdog(_ id: String) {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let run = Run()
        defer { run.sut.stopBufferWatchdog() }
        for step in row["steps"] as! [[String: Any]] {
            if step["start"] as? Bool == true {
                run.sut.isRunning = true
                run.sut.startBufferWatchdog(isRecovery: false)
            } else if let seconds = step["run"] as? Double {
                run.run(seconds, step["input"] as! String)
            } else if let restart = step["restart"] as? String {
                run.restartFails = restart == "fails"
            } else if step["authorized"] as? Bool == false {
                run.sut.microphoneAuthorized = { false }
            } else if step["permissionDenied"] as? Bool == true {
                run.sut.microphonePermissionDenied = true
            } else if step["playFile"] as? Bool == true {
                run.sut.isPlayingFile = true
            } else if step["stop"] as? Bool == true {
                run.sut.isRunning = false
            } else if let fields = step["check"] as? [String: Any] {
                run.check(fields, id)
            } else {
                Issue.record("\(id): unknown step \(step)")
            }
        }
        run.check(row["expect"] as! [String: Any], id)
    }
}
