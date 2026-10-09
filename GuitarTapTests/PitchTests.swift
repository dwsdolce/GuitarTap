//
//  PitchTests.swift
//  GuitarTapTests
//
//  Equal-temperament pitch against the shared case file, `pitch.json` — the same cases the Python and web
//  suites run. Pitch is a general package: pitchRange, formattedNote and isInTune have no call site in the
//  app, and are tested because the package's API is the contract.
//
// @parity test/pitch

import Foundation
import Testing
@testable import GuitarTap

private final class PitchTestsAnchor {}

@Suite("Pitch")
struct PitchTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: PitchTestsAnchor.self).url(forResource: "pitch", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func rows(_ key: String) -> [[String: Any]] { data[key] as! [[String: Any]] }
    static func row(_ key: String, _ id: String) -> [String: Any] { rows(key).first { $0["id"] as! String == id }! }
    static let tolerance = data["tolerance"] as! Double

    /// A number from the file: NaN and the infinities are written as strings.
    static func number(_ value: Any) -> Double {
        switch value as? String {
        case "NaN": return .nan
        case "Infinity": return .infinity
        case "-Infinity": return -.infinity
        default: return (value as! NSNumber).doubleValue
        }
    }

    static func close(_ actual: Double, _ expected: Any) -> Bool {
        abs(actual - number(expected)) <= tolerance
    }

    @Test(arguments: rows("frequencies").map { $0["id"] as! String })
    func frequency(_ id: String) {
        let row = Self.row("frequencies", id)
        let e = row["expect"] as! [String: Any]
        let p = Pitch(a4: Self.number(row["a4"]!))
        let f = Self.number(row["frequency"]!)
        let pitch = p.pitch(frequency: f)
        let expectedPitch = e["pitch"] as! [String: Int]
        let range = p.pitchRange(frequency: f)
        let expectedRange = e["pitchRange"] as! [String: Any]
        #expect(p.hasPitch(f) == e["hasPitch"] as! Bool, "\(id): hasPitch")
        #expect(pitch.note == expectedPitch["note"] && pitch.octave == expectedPitch["octave"], "\(id): pitch \(pitch)")
        #expect(p.note(frequency: f) == e["note"] as! String, "\(id): note")
        #expect(Self.close(p.cents(frequency: f), e["cents"]!), "\(id): cents \(p.cents(frequency: f))")
        #expect(Self.close(p.freq0(frequency: f), e["freq0"]!), "\(id): freq0 \(p.freq0(frequency: f))")
        #expect(Self.close(range.upper, expectedRange["upper"]!), "\(id): pitchRange upper \(range.upper)")
        #expect(Self.close(range.lower, expectedRange["lower"]!), "\(id): pitchRange lower \(range.lower)")
        #expect(p.formattedNote(frequency: f) == e["formattedNote"] as! String, "\(id): formattedNote")
        #expect(p.isInTune(frequency: f) == e["isInTune"] as! Bool, "\(id): isInTune")
    }

    @Test(arguments: rows("isInTune").map { $0["id"] as! String })
    func isInTune(_ id: String) {
        let row = Self.row("isInTune", id)
        let p = Pitch(a4: Self.number(row["a4"]!))
        let inTune = p.isInTune(frequency: Self.number(row["frequency"]!), threshold: Self.number(row["threshold"]!))
        #expect(inTune == row["expect"] as! Bool, "\(id)")
    }

    @Test(arguments: rows("isInTuneAtOwnCents").map { $0["id"] as! String })
    func isInTuneAtOwnCents(_ id: String) {
        let row = Self.row("isInTuneAtOwnCents", id)
        let p = Pitch(a4: Self.number(row["a4"]!))
        let f = Self.number(row["frequency"]!)
        let cents = p.cents(frequency: f)
        #expect(Self.close(cents, row["cents"]!), "\(id): cents \(cents)")
        #expect(p.isInTune(frequency: f, threshold: cents) == row["expectAtCents"] as! Bool, "\(id): at its cents")
        #expect(p.isInTune(frequency: f, threshold: cents - 1e-9) == row["expectJustUnder"] as! Bool, "\(id): just under")
    }

    @Test(arguments: rows("freq").map { $0["id"] as! String })
    func freq(_ id: String) {
        let row = Self.row("freq", id)
        let p = Pitch(a4: Self.number(row["a4"]!))
        let f = p.freq(note: row["note"] as! Int, octave: row["octave"] as! Int)
        #expect(Self.close(f, row["expect"]!), "\(id): \(f)")
    }

    @Test func formatCents() {
        for row in Self.rows("formatCents") {
            let cents = Self.number(row["cents"]!)
            #expect(Pitch.formatCents(cents) == row["expect"] as! String, "\(cents)")
        }
    }
}
