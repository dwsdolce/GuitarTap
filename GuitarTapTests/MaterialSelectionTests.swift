//
//  MaterialSelectionTests.swift
//  GuitarTapTests
//
//  Locks the material (plate/brace) selection HEAL against the real iPad save-corruption bug.
//  Fixture `plate-umik-1-3-tap-swift-ipad-1784314709.guitartap` is a genuine iPad-saved plate whose
//  `selectedPeakIDs` aggregate was clobbered to just the cross peak (the intermittent iPad Release
//  glitch), while `peaks[]` correctly holds all three (L ≈ 67, C ≈ 117, FLC ≈ 36 Hz). Material has no
//  per-peak selection, so `effectiveSelectedPeakIDs` must ignore the corrupt aggregate and resolve to
//  all three — healing the file at render time. Python + web pin the same fixture in this parity group.
//
// @parity test/material-selection

import Testing
import Foundation
@testable import GuitarTap

// Anchors Bundle(for:) to the GuitarTapTests bundle so the fixture loads on every destination
// (iPad/iPhone too), not just the macOS host — #filePath points at the build machine's source tree,
// which does not exist on a device. The synchronized GuitarTapTests folder already bundles the fixture.
private final class FixtureAnchor {}

@Suite("MaterialSelection")
struct MaterialSelectionTests {

    @Test func corruptIpadPlate_effectiveSelectionHealsToAllThree() throws {
        let url = try #require(Bundle(for: FixtureAnchor.self)
            .url(forResource: "plate-umik-1-3-tap-swift-ipad-1784314709", withExtension: "guitartap"))
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let m = try #require(try decoder.decode([TapToneMeasurement].self, from: data).first)

        // Preconditions: a material measurement, all three peaks present, but the corrupt aggregate
        // holds only the cross peak — the exact iPad glitch this heals.
        #expect(m.isMaterial)
        #expect(m.peaks.count == 3)
        #expect(m.selectedPeakIDs?.count == 1)

        // The heal: the corrupt aggregate is ignored for material → all three peaks resolve.
        #expect(m.effectiveSelectedPeakIDs == Set(m.peaks.map { $0.id }))
        #expect(m.effectiveSelectedPeakIDs.count == 3)
    }
}