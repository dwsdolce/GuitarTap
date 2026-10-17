//
//  StateNotificationTests.swift
//  GuitarTapTests
//
//  A device change and the settle after it, against the shared cases in `notification.json` (N1–N18),
//  the same as Python and the web: detection stands down and New Tap greys out — and the view is told,
//  which Swift does with `@Published` (observed here through `objectWillChange`), Python with a signal
//  and the web with its snapshot and `notify()`, each of which an ordinary edit can break — a live
//  chart is blanked, and once 3 s of audio have passed since the last change and the next frame has
//  arrived, the latch is re-anchored, readiness and listening come back and the status is put back.
//
//  Mirrors: tests/test_state_notification.py · test/state-notification.test.ts
//
// @parity test/notification

import Testing
import Foundation
import Combine
@testable import GuitarTap

private final class StateNotificationAnchor {}

@Suite("StateNotification", .serialized)
@MainActor
struct StateNotificationTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: StateNotificationAnchor.self).url(forResource: "notification", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    nonisolated static func ids() -> [String] {
        (data["cases"] as! [[String: Any]]).map { $0["id"] as! String }
    }

    /// What a case's run keeps between steps.
    final class Run {
        var notedStatus: String?
        var notedPeaks: [UUID] = []
        var readinessNotified = false
        var watch: AnyCancellable?
    }

    static func check(_ fields: [String: Any], _ sut: TapToneAnalyzer, _ run: Run, _ id: String) {
        for (field, want) in fields {
            let msg = Comment(rawValue: "\(id) \(field)")
            switch field {
            case "ready": #expect(sut.isReadyForDetection == want as? Bool, msg)
            case "readinessNotified": #expect(run.readinessNotified == want as? Bool, msg)
            case "settling": #expect(sut.isSettling == want as? Bool, msg)
            case "statusMessage": #expect(sut.statusMessage == want as? String, "\(id) \(field): \(sut.statusMessage)")
            case "statusAsNoted": #expect((sut.statusMessage == run.notedStatus) == want as? Bool, "\(id) \(field): \(sut.statusMessage) vs \(run.notedStatus ?? "nil")")
            case "statusBeforeSettleAsNoted":
                #expect((sut.statusBeforeSettle == run.notedStatus) == want as? Bool, "\(id) \(field): \(sut.statusBeforeSettle ?? "nil")")
            case "statusIsArmedPrompt": #expect((sut.statusMessage == sut.armedPrompt()) == want as? Bool, msg)
            case "detecting": #expect(sut.isDetecting == want as? Bool, msg)
            case "paused": #expect(sut.isDetectionPaused == want as? Bool, msg)
            case "complete": #expect(sut.isMeasurementComplete == want as? Bool, msg)
            case "phase": #expect(sut.materialTapPhase.rawValue == want as? String, "\(id) \(field): \(sut.materialTapPhase)")
            case "aboveThreshold": #expect(sut.isAboveThreshold == want as? Bool, msg)
            case "hasPeaks": #expect(!sut.allPeaks.isEmpty == want as? Bool, "\(id) \(field): \(sut.allPeaks.count)")
            case "peaksAsNoted": #expect((sut.allPeaks.map(\.id) == run.notedPeaks) == want as? Bool, msg)
            default: Issue.record("\(id): unknown field \(field)")
            }
        }
    }

    @Test(arguments: ids())
    func notification(_ id: String) {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let saved = (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc)
        defer { (TapDisplaySettings.measurementType, TapDisplaySettings.measureFlc) = saved }
        TapDisplaySettings.measurementType = .generic

        let sut = makeStepsAnalyzer()
        let run = Run()
        for step in row["steps"] as! [[String: Any]] {
            if step["note"] as? Bool == true {
                run.notedStatus = sut.statusMessage
                run.notedPeaks = sut.allPeaks.map(\.id)
            } else if step["watchNotifications"] as? Bool == true {
                run.watch = sut.objectWillChange.sink { _ in run.readinessNotified = true }
            } else if let clipping = step["clipping"] as? Bool {
                sut.fftAnalyzer.level.isClipping = clipping
                sut.applyStatusOverrides()
            } else if let dead = step["inputDead"] as? Bool {
                sut.fftAnalyzer.inputAppearsDead = dead
                sut.applyStatusOverrides()
            } else if let fields = step["check"] as? [String: Any] {
                Self.check(fields, sut, run, id)
            } else {
                #expect(runAnalyzerStep(step, on: sut), "\(id): unknown step \(step)")
            }
        }
        Self.check(row["expect"] as! [String: Any], sut, run, id)
    }
}
