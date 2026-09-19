//  CaptureProbeTests.swift
//  Writes this edition's capture-window fingerprints for the REG-G2 per-tap case.
//
//  Gated: does nothing unless CAPTURE_PROBE=1 (TEST_RUNNER_CAPTURE_PROBE=1 when driven by
//  xcodebuild, which does not forward the plain environment to a hosted test runner).
//
//      TEST_RUNNER_CAPTURE_PROBE=1 xcodebuild test -project GuitarTap.xcodeproj \
//        -scheme guitar_tap -destination 'platform=macOS,arch=arm64' \
//        -only-testing:GuitarTapTests/CaptureProbeTests
//
//  It prints CAPTURE_PROBE_WROTE <path>, the same contract mint-oracle.sh relies on: the
//  sandboxed test host cannot write where the shell would choose, so the test picks the
//  path and says where it went.
//
//  Compare against the Python edition's file (guitar_tap Tooling/capture-probe.py) with
//  guitar-tap-project/tooling/compare-capture-probes.py.
//  @parity test/capture-probe

import Foundation
import Testing
@testable import GuitarTap

@Suite(.serialized)
struct CaptureProbeTests {

    private static var enabled: Bool {
        ProcessInfo.processInfo.environment["CAPTURE_PROBE"] == "1"
    }

    private static var outputURL: URL {
        if let out = ProcessInfo.processInfo.environment["CAPTURE_PROBE_OUT"], !out.isEmpty {
            return URL(fileURLWithPath: out)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("capture-probe-swift.json")
    }

    @Test @MainActor
    func writeCaptureFingerprints() async throws {
        guard Self.enabled else { return }

        let caseName = "REG-G2"
        let spec = ParityOracle.playback(caseName)
        let url = ParityOracle.fixtureURL(caseName)
        let taps = spec.settings.numberOfTaps ?? 1

        CaptureProbe.reset()
        CaptureProbe.enabled = true
        defer { CaptureProbe.enabled = false }

        // Same setup the REG-G2 regression test uses — the point is to fingerprint the
        // windows that case actually produces, so any divergence here would measure
        // something nothing else runs.
        let sut = TapToneAnalyzer.forTesting()
        if let peakMin = spec.settings.peakMinThreshold {
            sut.peakMinThreshold = peakMin
        }
        sut.tapDetectionThreshold = spec.settings.tapDetectionThreshold
        try await sut.playFileForTesting(url: url, measurementType: .generic, numberOfTaps: taps)

        // NOT an expectation: the capture count is itself data. Swift produces NINE captures
        // for this eight-tap file where Python produces eight, which is a finding to record
        // rather than a failure to trip over — a diagnostic that goes red tells you less than
        // one that reports.
        print("CAPTURE_PROBE_SELF analyzer=\(String(UInt(bitPattern: ObjectIdentifier(sut).hashValue) % 10000))")
        print("CAPTURE_PROBE_COUNTS capturedTaps=\(sut.capturedTaps.count) "
              + "tapEntries=\(sut.tapEntries.count) numberOfTaps=\(taps) "
              + "complete=\(sut.isMeasurementComplete)")

        // Only this analyzer's captures. The test bundle is HOSTED IN THE APP, so the app's
        // own TapToneAnalyzer is alive alongside this one and occasionally completes its own
        // gated capture mid-test. A static probe pools both, which reads as a phantom ninth
        // capture in an eight-tap measurement — it is a second object, not a defect.
        let selfID = String(UInt(bitPattern: ObjectIdentifier(sut).hashValue) % 10000)
        let foreign = CaptureProbe.records.filter { $0.instance != selfID }
        if !foreign.isEmpty {
            print("CAPTURE_PROBE_NOTE ignored \(foreign.count) capture(s) from another analyzer instance")
        }
        let records = CaptureProbe.records.filter { $0.instance == selfID }
        #expect(records.count == taps,
                "this analyzer should capture exactly one window per tap")

        struct Document: Codable {
            let edition: String
            let os: String
            let arch: String
            let caseName: String
            let records: [CaptureProbe.Record]
        }
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
        let data = try encoder.encode(Document(edition: "swift", os: system, arch: arch,
                                               caseName: caseName, records: records))
        try data.write(to: Self.outputURL)
        print("CAPTURE_PROBE_WROTE \(Self.outputURL.path)")
        for (index, record) in records.enumerated() {
            let aligned = record.bufferHash == record.windowHash ? "NO-ONSET" : "aligned "
            print("  capture \(index + 1): \(record.accepted ? "ACCEPTED" : "DROPPED ") \(aligned)"
                  + "  taps \(record.tapsBefore)->\(record.tapsAfter)"
                  + "  buffer \(record.bufferHash.prefix(8))  window \(record.windowHash.prefix(8))")
        }
    }
}
