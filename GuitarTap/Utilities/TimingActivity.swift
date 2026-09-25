//
//  TimingActivity.swift
//  GuitarTap
//
//  Holds off the operating system's timer throttling while the app does something time-critical.
//
//  macOS throttles the timers of an app it considers idle — App Nap. Measured in the Python edition's
//  test process (#19): after ~30–35 s a one-chunk (21.3 ms) sleep took 56–98 ms, so paced file playback
//  ran 2–4× slower than real time. Only a LATENCY-CRITICAL activity lifted it; a user-initiated one did
//  not. File playback is paced by such sleeps, so it holds one of these for its whole run.
//
//  Mirrors Python guitar_tap/utilities/timing_activity.py. The web has no equivalent: a browser offers
//  no way to exempt a page from background-tab timer throttling.
//
// @parity util/timing-activity

import Foundation

/// Begins an activity that keeps the OS from throttling this process's timers. Pass the token to
/// ``releaseTimingActivity(_:)`` when the time-critical work ends.
func holdTimingActivity(_ reason: String) -> NSObjectProtocol {
    ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: reason)
}

/// Ends an activity begun by ``holdTimingActivity(_:)``.
func releaseTimingActivity(_ token: NSObjectProtocol) {
    ProcessInfo.processInfo.endActivity(token)
}
