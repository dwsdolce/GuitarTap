//
//  FrequencyFormatTests.swift
//  GuitarTapTests
//
//  A frequency for display, the range line built from it, and whole hertz grouped by the locale, against the
//  shared case file `frequency-format.json` — the same cases the Python and web suites run.
//
// @parity test/frequency-format

import Foundation
import Testing
@testable import GuitarTap

private final class FrequencyFormatTestsAnchor {}

@Suite("FrequencyFormat")
struct FrequencyFormatTests {

    static let data: [String: Any] = {
        let url = Bundle(for: FrequencyFormatTestsAnchor.self).url(forResource: "frequency-format", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    @Test func formattedAsFrequency() {
        for row in Self.data["formattedAsFrequency"] as! [[Any]] {
            #expect(Float(row[0] as! Double).formattedAsFrequency() == (row[1] as! String), "\(row[0])")
        }
    }

    @Test func displayRangeLabel() {
        for row in Self.data["displayRangeLabel"] as! [[Any]] {
            let label = GuitarTap.displayRangeLabel(minFreq: Float(row[0] as! Double), maxFreq: Float(row[1] as! Double))
            #expect(label == (row[2] as! String), "\(row[0]) \(row[1])")
        }
    }

    @Test func formattedAsWholeHertz() {
        for row in Self.data["formattedAsWholeHertz"] as! [[Any]] {
            let text = GuitarTap.formattedAsWholeHertz(row[0] as! Double, locale: Locale(identifier: row[1] as! String))
            #expect(text == (row[2] as! String), "\(row[0]) \(row[1])")
        }
    }
}
