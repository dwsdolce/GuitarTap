//
//  AudioClockFeed.swift
//  GuitarTapTests
//
//  Advances the analyzer's AUDIO clock the way audio does: chunk by chunk through the production
//  entry point, `onChunkLevel(_:audioTime:)`. The tap lifecycle's rests, the FLC hold and the
//  capture window run on that clock, so a test feeds the audio a delay covers rather than sleeping
//  through it — the same path playback and the microphone take. And a wall clock a test moves by
//  hand, for the capture's safety timeout, which runs on the wall clock.
//
//  Mirrors Python tests/audio_clock_feed.py and web test/audioClockFeed.ts.
//
// @parity tooling/audio-clock-feed

import Foundation
@testable import GuitarTap

/// One chunk's duration at the app's 1024-sample chunk and 48 kHz.
let audioFeedChunkSeconds: Double = 1024.0 / 48000.0

/// Feeds quiet chunks until the analyzer's audio clock has advanced exactly `seconds` past where it
/// is, so an action due at that moment runs on the last chunk. The level is below every detection
/// threshold, so feeding it cannot itself start a tap.
@MainActor
func advanceAudio(_ sut: TapToneAnalyzer, by seconds: Double, level: Float = -90) {
    let target = sut.lastAudioTime + seconds
    var t = sut.lastAudioTime
    while t < target {
        t = min(t + audioFeedChunkSeconds, target)
        sut.onChunkLevel(level, audioTime: t)
    }
}

/// A wall clock a test moves by hand: time stands still until ``advance(by:)``, which runs each action
/// as its time comes, in time order — including one an action schedules within the advance.
final class ManualWallClock: WallClock {
    private var time: TimeInterval = 0
    private var pending: [(due: TimeInterval, order: Int, action: () -> Void)] = []
    private var scheduled = 0

    func now() -> TimeInterval { time }

    func after(_ seconds: TimeInterval, _ action: @escaping () -> Void) {
        scheduled += 1
        pending.append((due: time + seconds, order: scheduled, action: action))
    }

    /// Moves the time on by `seconds`, running every action due by then.
    func advance(by seconds: TimeInterval) {
        let target = time + seconds
        while let next = pending.filter({ $0.due <= target }).min(by: { ($0.due, $0.order) < ($1.due, $1.order) }) {
            pending.removeAll { $0.order == next.order }
            time = next.due
            next.action()
        }
        time = target
    }
}
