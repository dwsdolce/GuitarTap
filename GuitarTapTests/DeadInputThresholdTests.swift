//
//  DeadInputThresholdTests.swift
//  GuitarTapTests
//
//  @parity dead-input-threshold — paired with web test/dead-input-threshold.test.ts and
//  Python tests/test_dead_input_threshold.py. All three pin the SAME calibration table.
//
//  Why this test exists: the dead-input watchdog decides "the stream is dead" from a
//  level threshold, and that threshold is a field calibration, not a derivation. Set it
//  too low and a genuinely dead stream (measured at ~-100 dBFS, NOT digital zero) is
//  never detected; too high and a quiet room is mistaken for a dead input and the engine
//  is restarted mid-measurement. The UMIK-1 is an unusually quiet microphone and can sit
//  near -90 dBFS in a silent room, which is what makes the upper bound real.
//
//  Source of the numbers: hub docs/AUDIO-WATCHDOG-SILENT-STREAM.md (incidents 2026-07-16).
//

import XCTest
@testable import GuitarTap

final class DeadInputThresholdTests: XCTestCase {

    /// Amplitude (linear RMS) for a level in dBFS.
    private func amp(_ dbfs: Float) -> Float { pow(10, dbfs / 20) }

    private func carriesSignal(_ rms: Float, _ sut: RealtimeFFTAnalyzer) -> Bool {
        rms > sut.deadInputRMSThreshold
    }

    func testDeadStreamCarriesNoSignal() {
        let sut = RealtimeFFTAnalyzer(forTesting: true)
        XCTAssertFalse(carriesSignal(0, sut), "digital silence must read as no signal")
        XCTAssertFalse(carriesSignal(amp(-120), sut), "far below anything real")
        XCTAssertFalse(carriesSignal(amp(-100), sut), "the measured dead-device level")
    }

    func testQuietUMIK1InASilentRoomCarriesSignal() {
        // The regression this test exists for: -90 dBFS is quiet, not dead.
        let sut = RealtimeFFTAnalyzer(forTesting: true)
        XCTAssertTrue(carriesSignal(amp(-90), sut), "a quiet UMIK-1 must not be called dead")
        XCTAssertTrue(carriesSignal(amp(-95), sut))
    }

    func testRoomFloorAndTapCarrySignal() {
        let sut = RealtimeFFTAnalyzer(forTesting: true)
        XCTAssertTrue(carriesSignal(amp(-70), sut), "room noise floor")
        XCTAssertTrue(carriesSignal(amp(-63), sut), "UMIK-1 Air peak")
        XCTAssertTrue(carriesSignal(amp(-20), sut), "a tap")
    }

    func testKeepsAtLeast10dBMarginUnderTheQuietRoomLevel() {
        // Guards against someone "tightening" the threshold back up toward -90 dBFS.
        let sut = RealtimeFFTAnalyzer(forTesting: true)
        XCTAssertLessThanOrEqual(sut.deadInputRMSThreshold, amp(-100))
        XCTAssertGreaterThanOrEqual(amp(-90) / sut.deadInputRMSThreshold, 3.16)
    }

    func testDwellIsLongEnoughToOutlastAQuietPassage() {
        // A short dwell would let an ordinary silent moment between taps trip the
        // watchdog. The recorded incidents persisted for minutes, so patience is free.
        let sut = RealtimeFFTAnalyzer(forTesting: true)
        XCTAssertGreaterThanOrEqual(sut.watchdogDeadInputThreshold, 10.0)
        XCTAssertGreaterThan(sut.watchdogDeadInputThreshold, sut.watchdogSilenceThreshold)
    }
}
