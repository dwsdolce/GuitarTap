//  CaptureProbe.swift
//  Diagnostic for the capture-window alignment family (project issues #7, #3, #5).
//
//  The editions disagree on the guitar path by 0.0004-0.003 dB, and the cause is known to
//  be at least partly that Swift aligns the guitar FFT window to the sample-level tap onset
//  while Python and web do not. Adding that alignment to Python closes only 6-52% of the
//  gap, so something else still differs in what reaches the FFT.
//
//  This narrows that "something else" to one of three places by fingerprinting the two
//  buffers on either side of the alignment step:
//
//      buffer differs                  -> the editions are not capturing the same samples
//      buffer same, window differs     -> the alignment picks a different onset
//      both same, spectrum differs     -> the arithmetic differs, not the input
//
//  Inert unless `enabled` is set. Nothing in the app switches it on; the probe test does.
//  @parity models/capture-probe

import Foundation

/// Fingerprints of the capture buffers, recorded per tap while `enabled`.
@MainActor
enum CaptureProbe {
    struct Record: Codable {
        /// Samples handed to the capture, before onset alignment.
        let bufferCount: Int
        let bufferHash: String
        /// The exact fftSize window handed to the FFT, after alignment and padding.
        let windowCount: Int
        let windowHash: String
    }

    static var enabled = false
    static var records: [Record] = []

    static func reset() {
        records = []
    }

    static func record(buffer: [Float], window: [Float]) {
        guard enabled else { return }
        records.append(Record(bufferCount: buffer.count,
                              bufferHash: fingerprint(buffer),
                              windowCount: window.count,
                              windowHash: fingerprint(window)))
    }

    /// FNV-1a over the little-endian IEEE-754 bit patterns of the samples.
    ///
    /// Deliberately not a checksum of the decimal text: the editions must be comparing the
    /// same bits, and any formatting step would hide a difference in the low bits — which is
    /// the size of difference this is chasing. The Python probe implements the same function
    /// so the two hex strings are directly comparable.
    static func fingerprint(_ samples: [Float]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for sample in samples {
            var bits = sample.bitPattern
            for _ in 0..<4 {
                hash ^= UInt64(bits & 0xff)
                hash = hash &* 0x100_0000_01b3
                bits >>= 8
            }
        }
        return String(format: "%016llx", hash)
    }
}
