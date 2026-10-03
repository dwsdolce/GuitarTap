//
//  SpectrumExportTests.swift
//  GuitarTapTests
//
//  The exported spectrum image's size: every Export Spectrum PNG is 2928 pixels wide — 2376 high with the
//  peak summary, 2138 without — and states 144 pixels per inch, so a viewer that honours the figure shows
//  it at 1464 points wide. Python test_spectrum_export.py and the web's spectrum-export.test.ts have the
//  same cases.
//
// @parity test/spectrum-export

import Foundation
import Testing
@testable import GuitarTap

private final class SpectrumExportTestsAnchor {}

@Suite("SpectrumExport", .serialized)
@MainActor
struct SpectrumExportTests {

    /// The shared cases: each fixture and the image it exports — pixels wide and high, and pixels per inch.
    static let cases: [(fixture: String, width: Int, height: Int, ppi: Int)] = {
        let url = Bundle(for: SpectrumExportTestsAnchor.self).url(forResource: "spectrum-export", withExtension: "json")!
        let data = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return (data["cases"] as! [[Any]]).map { ($0[0] as! String, $0[1] as! Int, $0[2] as! Int, $0[3] as! Int) }
    }()

    @Test(arguments: cases)
    func export_sizeAndPixelsPerInch(_ c: (fixture: String, width: Int, height: Int, ppi: Int)) throws {
        let bundle = Bundle(for: SpectrumExportTestsAnchor.self)
        let url = try #require(bundle.url(forResource: c.fixture, withExtension: "guitartap"))
        let measurement = try #require(try TapToneAnalyzer.decodeMeasurements(Data(contentsOf: url)).first)
        // As the measurement list's Export Spectrum: a comparison through its own renderer.
        let png = try #require(measurement.isComparison
            ? renderSpectrumImageForComparison(measurement)
            : renderSpectrumImageForMeasurement(measurement))
        let found = Self.sizeAndPixelsPerInch(png)
        #expect(found.width == c.width && found.height == c.height && found.ppi == c.ppi,
                "\(c.fixture): \(found.width) × \(found.height) at \(String(describing: found.ppi)) ppi")
    }

    /// A PNG's pixels wide and high (IHDR) and the pixels per inch it states (pHYs, per metre).
    static func sizeAndPixelsPerInch(_ png: Data) -> (width: Int, height: Int, ppi: Int?) {
        let bytes = [UInt8](png)
        func u32(_ at: Int) -> Int { bytes[at..<at + 4].reduce(0) { $0 << 8 | Int($1) } }
        var ppi: Int?
        var at = 8
        while at + 8 <= bytes.count {
            let length = u32(at)
            if String(bytes: bytes[at + 4..<at + 8], encoding: .ascii) == "pHYs", bytes[at + 16] == 1 {
                ppi = Int((Double(u32(at + 8)) * 0.0254).rounded())
            }
            at += 12 + length
        }
        return (u32(16), u32(20), ppi)
    }
}
