//
//  WallClock.swift
//  GuitarTap
//
//  The wall clock the analyzer reads the time from and schedules on. The app uses the system's;
//  a test passes one it moves by hand. Mirrors Python `WallClock` in `models/wall_clock.py` and web
//  `WallClock` in `src/state/wallClock.ts`.
//
// @parity model/wall-clock tests=test/audio-clock-timers
//

import Foundation

/// A monotonic wall clock, in seconds, with a way to run an action later on the main thread.
///
/// The analyzer's timers mostly run on the AUDIO clock, which advances with the audio processed. The
/// capture's safety timeout cannot: it exists for when the audio stops, and the audio clock stops
/// with it. It runs on this clock instead.
protocol WallClock: AnyObject {
    /// The current time, in seconds since an arbitrary fixed point.
    func now() -> TimeInterval
    /// Runs `action` on the main thread `seconds` from now.
    func after(_ seconds: TimeInterval, _ action: @escaping () -> Void)
}

/// The system's wall clock: `ProcessInfo.systemUptime`, scheduled with `DispatchQueue.main.asyncAfter`.
final class SystemWallClock: WallClock {
    func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    func after(_ seconds: TimeInterval, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }
}
