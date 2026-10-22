//
//  SnapInterpolationTests.swift
//  GuitarTapTests
//
// @parity test/snap-interpolation
//
// The crosshair's snap to a curve against the shared case file `snap-interpolation.json` — the same cases the
// Python and web suites run: the point on a curve at the pointer's frequency, interpolated between the two bins
// either side, and which of several curves the crosshair follows.

import CoreGraphics
import Foundation
import Testing
@testable import GuitarTap

private final class SnapInterpolationTestsAnchor {}

@Suite("SnapInterpolation")
struct SnapInterpolationTests {

    static let data: [String: Any] = {
        let url = Bundle(for: SnapInterpolationTestsAnchor.self).url(forResource: "snap-interpolation", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    static func floats(_ v: Any?) -> [Float] { (v as! [Double]).map(Float.init) }

    @Test func snapToWaveform() {
        for c in Self.data["snapToWaveform"] as! [[String: Any]] {
            let r = SpectrumView.snapToWaveform(targetHz: Float(c["targetHz"] as! Double),
                                                magnitudes: Self.floats(c["magnitudes"]),
                                                frequencies: Self.floats(c["frequencies"]))
            if let expect = c["expect"] as? [Double] {
                #expect(r != nil, "\(c["id"]!)")
                if let r {
                    #expect(abs(Double(r.frequency) - expect[0]) < 1e-3 && abs(Double(r.magnitude) - expect[1]) < 1e-3,
                            "\(c["id"]!): \(r)")
                }
            } else {
                #expect(r == nil, "\(c["id"]!)")
            }
        }
    }

    @Test func lockedSeries() {
        for c in Self.data["lockedSeries"] as! [[String: Any]] {
            let candidates = (c["candidates"] as! [[Double]]).map { (index: Int($0[0]), dist: CGFloat($0[1])) }
            let r = SpectrumView.lockedSeries(candidates: candidates, lockedIndex: c["locked"] as! Int)
            #expect(r == c["expect"] as! Int, "\(c["id"]!)")
        }
    }
}
