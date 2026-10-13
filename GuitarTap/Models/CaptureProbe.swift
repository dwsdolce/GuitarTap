//  CaptureProbe.swift
//  Diagnostic for cross-edition capture-window alignment.
//
//  Places a cross-edition difference in what reaches the FFT in one of three places by
//  fingerprinting the two buffers on either side of the alignment step:
//
//      buffer differs                  -> the editions are not capturing the same samples
//      buffer same, window differs     -> the alignment picks a different onset
//      both same, spectrum differs     -> the arithmetic differs, not the input
//
//  Inert unless `enabled` is set. The probe test switches it on for a replay. The app switches it
//  on only in a build made with `liveProbe` set, and then only while Dump Capture Audio is on: each
//  measurement's records are written beside its session recording, where the first samples of each
//  capture buffer place it in that recording.
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
        /// Whether this capture survived to become a tap, or was dropped downstream.
        var accepted: Bool
        /// capturedTaps.count as this capture entered, and after it appended (-1 if it
        /// never did). A drop shows as accepted=false; a RESET shows as a count that went
        /// backwards between consecutive captures.
        /// Which TapToneAnalyzer produced it. The test bundle is hosted inside the app, so
        /// the app's own analyzer is alive alongside the test's and can complete its own
        /// gated capture mid-test — two objects, two capturedTaps arrays, one static probe.
        let instance: String
        let tapsBefore: Int
        var tapsAfter: Int
        /// First 1024 samples of the buffer, as hex bit patterns. Enough to locate the buffer's
        /// start offset inside the source file by search, which is what says whether the
        /// editions begin accumulating at the same sample.
        let bufferHead: [String]
    }

    /// Whether the app itself records captures — a developer switch, `false` in every released
    /// build (a release build refuses to compile the app with it on). Set it to `true` for a
    /// diagnostic build; the probe then runs for each measurement made with Dump Capture Audio on.
    static let liveProbe = false

    /// A file of records: one edition's captures for one replayed case or one live measurement.
    struct Document: Codable {
        let edition: String
        let os: String
        let arch: String
        /// The replayed case, or the name of the live measurement's session recording.
        let caseName: String
        let records: [Record]
    }

    static var enabled = false
    /// Whether a measurement in the app is recording captures (`beginLiveSession`). Separate from
    /// `enabled`, which a test or tool owns: a session that begins must not switch that off.
    static var liveSession = false
    /// Whether captures are being recorded, for either reason.
    static var isRecording: Bool { enabled || liveSession }
    static var records: [Record] = []
    /// Ordered event log — capture appends interleaved with capturedTaps resets, so the
    /// sequence can be read rather than reconstructed from counts.
    static var events: [String] = []

    static func note(_ text: String) {
        guard isRecording else { return }
        events.append(text)
    }

    static func reset() {
        records = []
        events = []
    }

    /// A measurement begins in the app: start a fresh set of records, when the app is recording
    /// them at all. Does nothing unless `liveProbe`.
    ///
    /// - Parameter recording: Whether this measurement's audio is being recorded (Dump Capture Audio).
    static func beginLiveSession(recording: Bool) {
        guard liveProbe else { return }
        liveSession = recording
        if recording { reset() }
    }

    /// A measurement's session recording was written: write its records beside it, as
    /// `<recording name>-capture-probe.json`. Does nothing unless `liveProbe` and a session is on.
    ///
    /// - Parameter wav: Where the session recording was written.
    static func writeLiveRecords(beside wav: URL) {
        guard liveProbe, liveSession else { return }
        let name = wav.deletingPathExtension().lastPathComponent
        let url = wav.deletingLastPathComponent().appendingPathComponent("\(name)-capture-probe.json")
        do {
            try encoded(caseName: name, records: records).write(to: url)
            gtLog("📦 Capture probe: \(url.path) (\(records.count) captures)")
        } catch {
            gtLog("⚠️ Capture probe not written: \(error.localizedDescription)")
        }
    }

    /// The records as a document for this edition and platform, in the form every edition writes.
    static func encoded(caseName: String, records: [Record]) throws -> Data {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        #if os(macOS)
        let system = "darwin"
        #else
        let system = "ios"
        #endif
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Document(edition: "swift", os: system, arch: arch,
                                           caseName: caseName, records: records))
    }

    /// Mark the most recent capture as having been appended to capturedTaps. Anything left
    /// unmarked reached the FFT and was then discarded — which is the case worth explaining.
    static func markAccepted(_ index: Int, tapsAfter: Int) {
        guard isRecording, records.indices.contains(index) else { return }
        records[index].accepted = true
        records[index].tapsAfter = tapsAfter
        note("capture#\(index + 1) appended, capturedTaps=\(tapsAfter)")
    }

    @discardableResult
    static func record(buffer: [Float], window: [Float], tapsBefore: Int, instance: String) -> Int {
        guard isRecording else { return -1 }
        note("capture#\(records.count + 1) enters, analyzer=\(instance) capturedTaps=\(tapsBefore)")
        records.append(Record(bufferCount: buffer.count,
                              bufferHash: fingerprint(buffer),
                              windowCount: window.count,
                              windowHash: fingerprint(window),
                              accepted: false,
                              instance: instance,
                              tapsBefore: tapsBefore,
                              tapsAfter: -1,
                              bufferHead: buffer.prefix(1024).map { String(format: "%08x", $0.bitPattern) }))
        return records.count - 1
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
