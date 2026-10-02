//
//  FrequencyFormatTests.swift
//  GuitarTapTests
//
//  A frequency for display (one decimal, kHz from 1000 Hz) and the range line above the guitar peak
//  list built from it.
//
// @parity test/frequency-format

import Testing
@testable import GuitarTap

@Suite("FrequencyFormat")
struct FrequencyFormatTests {

    @Test func belowOneKilohertz_isHertzWithOneDecimal() {
        #expect(Float(440).formattedAsFrequency() == "440.0 Hz")
        #expect(Float(25.37).formattedAsFrequency() == "25.4 Hz")
        #expect(Float(999.9).formattedAsFrequency() == "999.9 Hz")
    }

    @Test func fromOneKilohertz_isKilohertzWithOneDecimal() {
        #expect(Float(1000).formattedAsFrequency() == "1.0 kHz")
        #expect(Float(2500).formattedAsFrequency() == "2.5 kHz")
    }

    @Test func rangeLabel_showsBothBounds() {
        #expect(displayRangeLabel(minFreq: 25, maxFreq: 45) == "Showing 25.0 Hz - 45.0 Hz")
    }

    @Test func rangeLabel_keepsAZoomedRangesFraction() {
        #expect(displayRangeLabel(minFreq: 25.37, maxFreq: 44.81) == "Showing 25.4 Hz - 44.8 Hz")
    }

    @Test func rangeLabel_crossingOneKilohertz_mixesUnits() {
        #expect(displayRangeLabel(minFreq: 800, maxFreq: 1200) == "Showing 800.0 Hz - 1.2 kHz")
    }
}
