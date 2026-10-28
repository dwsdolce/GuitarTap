//
//  DimmingTests.swift
//  GuitarTapTests
//
//  How a control that cannot be used shows it, against the shared case file `dimming.json`: the whole group is
//  disabled and drawn at the theme opacity its case names — `disabledDimmed` for one that cannot act now,
//  `notApplicableDimmed` for one that has no meaning here. The same cases the Python and web suites run.
//
//  A probe view draws an opaque square, black while its environment is enabled and red while it is disabled, on
//  white; rendered, its pixel says both whether the modifier disabled it (red) and at what opacity it is drawn (how
//  far the colour is from white).
//
// @parity test/dimming

import Foundation
import SwiftUI
import Testing
@testable import GuitarTap

private final class DimmingTestsAnchor {}

@Suite("Dimming")
@MainActor
struct DimmingTests {

    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: DimmingTestsAnchor.self).url(forResource: "dimming", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids() -> [String] {
        (data["cases"] as! [[String: Any]]).map { $0["id"] as! String }
    }

    /// Black while enabled, red while disabled — the environment the modifier leaves.
    private struct Probe: View {
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            Rectangle().fill(isEnabled ? Color(red: 0, green: 0, blue: 0) : Color(red: 1, green: 0, blue: 0))
        }
    }

    @ViewBuilder
    private func probe(_ kind: String) -> some View {
        switch kind {
        case "cannotActNow": Probe().disabledDimmed(true)
        case "doesNotApply": Probe().notApplicableDimmed(true)
        default: Probe().disabledDimmed(false).notApplicableDimmed(false)
        }
    }

    /// The probe's centre pixel, drawn on white, as 0–1 components.
    ///
    /// The white behind the probe is opaque, so a drawn pixel always is: one that is not means the renderer gave back
    /// an image with nothing in it — as a simulator's renderer does when it times out building its GPU pipeline — and
    /// it is drawn again, up to five times, before the test fails.
    private func pixel(_ view: some View) throws -> (r: Double, g: Double, b: Double) {
        for _ in 1...5 {
            let renderer = ImageRenderer(content: ZStack { Rectangle().fill(Color(red: 1, green: 1, blue: 1)); view }
                .frame(width: 8, height: 8))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            var bytes = [UInt8](repeating: 0, count: 4)
            let context = try #require(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8,
                                                 bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: -4, y: -4, width: image.width, height: image.height))
            if bytes[3] == 255 {
                return (Double(bytes[0]) / 255, Double(bytes[1]) / 255, Double(bytes[2]) / 255)
            }
        }
        throw RenderError.nothingDrawn
    }

    private enum RenderError: Error, CustomStringConvertible {
        case nothingDrawn
        var description: String { "the renderer drew nothing, five times" }
    }

    @Test(arguments: ids())
    func dimming(_ id: String) throws {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let p = try pixel(probe(row["kind"] as! String))
        let enabled = row["enabled"] as! Bool
        // Disabled: the probe drew red — full red, green and blue lifted only by the white showing through.
        #expect((p.r > 0.99 && p.g < p.r) == !enabled, "\(id): enabled \(p)")
        // The opacity: the blue channel is the white behind showing through, 1 − opacity.
        let want = (row["opacity"] as? String).map { Palette.opacity(Palette.Opacity(rawValue: $0)!) } ?? 1
        #expect(abs((1 - p.b) - want) < 0.02, "\(id): drawn at \(1 - p.b), want \(want)")
    }
}
