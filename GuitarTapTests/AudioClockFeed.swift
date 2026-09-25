//
//  AudioClockFeed.swift
//  GuitarTapTests
//
//  Advances the analyzer's AUDIO clock the way audio does: chunk by chunk through the production
//  entry point, `onRmsLevelChanged(_:audioTime:)`. The tap lifecycle's rests, the FLC hold and the
//  capture window run on that clock (#19), so a test that used to sleep through a wall-clock delay
//  now feeds the audio that delay covers — the same path playback and the microphone take.
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
        sut.onRmsLevelChanged(level, audioTime: t)
    }
}
