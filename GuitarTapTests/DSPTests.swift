//
//  DSPTests.swift
//  GuitarTapTests
//
//  The DSP under peak finding and the live spectrum, against the shared case file, `dsp.json` — the same
//  cases the Python and web suites run: parabolic interpolation and the Q factor (TapToneAnalyzer), and
//  signals through RealtimeFFTAnalyzer's gated FFT, live FFT, live peak and per-chunk levels.
//
//  Silence is -inf in every bin and on the readout, not a finite floor: -100 dB is a REAL reading (a quiet
//  UMIK-1 reaches it, and it is the dead-input watchdog's threshold), so "no microphone at all" must not
//  look like "a very quiet microphone". Detection keeps -100 on silence.
//
// @parity test/dsp

import Foundation
import Testing
@testable import GuitarTap

private final class DSPTestsAnchor {}

@Suite("DSP")
struct DSPTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: DSPTestsAnchor.self).url(forResource: "dsp", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()
    nonisolated static func rows(_ key: String) -> [[String: Any]] { data[key] as! [[String: Any]] }
    static func row(_ key: String, _ id: String) -> [String: Any] { rows(key).first { $0["id"] as! String == id }! }

    /// A number from the file: NaN and the infinities are written as strings.
    static func number(_ value: Any?) -> Float {
        switch value as? String {
        case "NaN": return .nan
        case "Infinity": return .infinity
        case "-Infinity": return -.infinity
        default: return (value as! NSNumber).floatValue
        }
    }
    static func numbers(_ value: Any?) -> [Float] { (value as! [Any]).map(number) }

    /// `|actual − expected| ≤ relative·|expected| + absolute`; equal infinities match.
    static func close(_ actual: Float, _ expected: Any?) -> Bool {
        let e = number(expected)
        if e.isInfinite || actual.isInfinite { return actual == e }
        let tol = data["tolerance"] as! [String: Double]
        return abs(Double(actual) - Double(e)) <= tol["relative"]! * abs(Double(e)) + tol["absolute"]!
    }

    /// A case's spectrum: inline, or named in `spectra`.
    static func spectrum(_ row: [String: Any]) -> (magnitudes: [Float], frequencies: [Float]) {
        if let name = row["spectrum"] as? String {
            let s = (data["spectra"] as! [String: Any])[name] as! [String: Any]
            return (numbers(s["magnitudes"]), numbers(s["frequencies"]))
        }
        return (numbers(row["magnitudes"]), numbers(row["frequencies"]))
    }

    /// A case's signal: silence, a constant (DC), an alternating ±amplitude (Nyquist), a constant plus an
    /// alternating, or a tone; a count of "fftSize" is the analyzer's FFT size.
    static func signal(_ row: [String: Any], fftSize: Int) -> [Float] {
        let s = row["signal"] as! [String: Any]
        let n = (s["count"] as? String) == "fftSize" ? fftSize : (s["count"] as! Int)
        let value = s["value"].map { number($0) } ?? 0
        let alternating = s["alternating"].map { number($0) } ?? 0
        switch s["kind"] as! String {
        case "silence": return [Float](repeating: 0, count: n)
        case "constant": return (0..<n).map { value + ($0 % 2 == 0 ? alternating : -alternating) }
        default: break
        }
        // Computed in Double and rounded to Float per sample: Float's sin loses phase at the large
        // arguments a 65536-sample tone reaches.
        let amp = Double(number(s["amplitude"])), hz = Double(number(s["frequency"])), rate = Double(number(s["sampleRate"]))
        return (0..<n).map { Float(amp * sin(2 * Double.pi * hz * Double($0) / rate)) }
    }

    /// Drains the main queue, where the analyzer publishes.
    private func drainMain() async {
        for _ in 0..<10 { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    @Test(arguments: rows("parabolicInterpolate").map { $0["id"] as! String })
    func parabolicInterpolate(_ id: String) {
        let row = Self.row("parabolicInterpolate", id)
        let (m, f) = Self.spectrum(row)
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        let r = sut.parabolicInterpolate(magnitudes: m, frequencies: f, peakIndex: row["peakIndex"] as! Int)
        let e = row["expect"] as! [String: Any]
        #expect(Self.close(r.frequency, e["frequency"]), "\(id): frequency \(r.frequency)")
        #expect(Self.close(r.magnitude, e["magnitude"]), "\(id): magnitude \(r.magnitude)")
    }

    @Test(arguments: rows("calculateQFactor").map { $0["id"] as! String })
    func calculateQFactor(_ id: String) {
        let row = Self.row("calculateQFactor", id)
        let (m, f) = Self.spectrum(row)
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        let r = sut.calculateQFactor(magnitudes: m, frequencies: f, peakIndex: row["peakIndex"] as! Int,
                                     peakMagnitude: Self.number(row["peakMagnitude"]))
        let e = row["expect"] as! [String: Any]
        #expect(Self.close(r.quality, e["quality"]), "\(id): quality \(r.quality)")
        #expect(Self.close(r.bandwidth, e["bandwidth"]), "\(id): bandwidth \(r.bandwidth)")
    }

    @Test(arguments: rows("signals").map { $0["id"] as! String })
    func signal(_ id: String) async {
        let row = Self.row("signals", id)
        let e = row["expect"] as! [String: Any]
        let fft = RealtimeFFTAnalyzer.forTesting()
        let samples = Self.signal(row, fftSize: fft.fftSize)

        func checkSpectrum(_ m: [Float], _ f: [Float]) {
            if let count = e["binCount"] as? Int { #expect(m.count == count, "\(id): bin count \(m.count)") }
            if e["bin0"] != nil { #expect(Self.close(m[0], e["bin0"]), "\(id): bin 0 \(m[0])") }
            if e["lastBin"] != nil { #expect(Self.close(m[m.count - 1], e["lastBin"]), "\(id): last bin \(m[m.count - 1])") }
            if e["bin0"] != nil { return }
            if let allNegInf = e["allNegativeInfinity"] as? Bool {
                #expect(!m.isEmpty && m.allSatisfy { $0 == -.infinity } == allNegInf, "\(id): every bin -inf")
            } else {
                let i = m.enumerated().max(by: { $0.element < $1.element })!.offset
                #expect(Self.close(f[i], e["peakFrequency"]), "\(id): peak frequency \(f[i])")
                #expect(Self.close(m[i], e["peakMagnitude"]), "\(id): peak magnitude \(m[i])")
            }
        }

        switch row["path"] as! String {
        case "gatedFFT":
            let s = row["signal"] as! [String: Any]
            let (m, f) = fft.computeGatedFFT(samples: samples, sampleRate: Double(Self.number(s["sampleRate"] ?? 48000)))
            checkSpectrum(m, f)
        case "computeFFT":
            let m = fft.computeFFT(on: samples)
            checkSpectrum(m, (0..<m.count).map { Float($0) * 48000 / Float(fft.fftSize) })
        case "performFFT":
            fft.actualSampleRate = 48000
            fft.updateFrequencyBins()
            await drainMain()
            fft.performFFT(on: samples)
            await drainMain()
            #expect(Self.close(fft.peakFrequency, e["peakFrequency"]), "\(id): peakFrequency \(fft.peakFrequency)")
            #expect(Self.close(fft.peakMagnitude, e["peakMagnitude"]), "\(id): peakMagnitude \(fft.peakMagnitude)")
        case "processRawSamples":
            fft.processRawSamples(samples)
            await drainMain()
            #expect(Self.close(fft.inputLevelDB, e["inputLevelDB"]), "\(id): inputLevelDB \(fft.inputLevelDB)")
            #expect(Self.close(fft.readoutLevelDB, e["readoutLevelDB"]), "\(id): readoutLevelDB \(fft.readoutLevelDB)")
        default:
            Issue.record("\(id): unknown path \(row["path"]!)")
        }
    }
}
