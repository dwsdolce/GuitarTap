//
//  DrawnPointsTests.swift
//  GuitarTapTests
//
//  The spectrum points the chart draws for its range: every point inside it plus the one just beyond
//  each edge, so the line reaches both edges and the plot area clips it.
//
// @parity none — Swift Charts (and the web's canvas) are given only the points near the range, so the
// edge segments must be included explicitly; Python's pyqtgraph is given the whole spectrum and clips
// it itself, so it has no such selection to test.

import Testing
@testable import GuitarTap

@Suite("DrawnPoints")
struct DrawnPointsTests {

    private let frequencies: [Float] = [10, 20, 30, 40, 50]

    @Test func includesThePointJustBeyondEachEdge() {
        #expect(DisplayRange.drawnIndices(of: frequencies, min: 25, max: 35) == 1..<4)
    }

    @Test func aRangeBetweenTwoPoints_drawsTheSegmentAcrossIt() {
        #expect(DisplayRange.drawnIndices(of: frequencies, min: 31, max: 39) == 2..<4)
    }

    @Test func aRangeWiderThanTheSpectrum_drawsEveryPoint() {
        #expect(DisplayRange.drawnIndices(of: frequencies, min: 5, max: 100) == 0..<5)
    }
}
