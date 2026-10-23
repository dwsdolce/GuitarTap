//
//  ButtonEnablementTests.swift
//  GuitarTapTests
//
//  The Pause / New Tap / Cancel enablement rule — `buttonRule`, the production function TapToneAnalysisView
//  calls — against the shared case file `button-enablement.json` (B1–B16), the same cases the Python and web
//  suites run; and the analyzer's Save / export rule, which drives a live analyzer.
//
// @parity test/button-enablement

import Foundation
import Testing
@testable import GuitarTap

private final class ButtonEnablementTestsAnchor {}

@Suite("ButtonEnablement", .serialized)
@MainActor
struct ButtonEnablementTests {

    // nonisolated: @Test(arguments:) reads the case table outside the main actor, the target's default;
    // (unsafe) because `Any` cannot be Sendable — the table is immutable once loaded.
    nonisolated(unsafe) static let cases: [[String: Any]] = {
        let url = Bundle(for: ButtonEnablementTestsAnchor.self).url(forResource: "button-enablement", withExtension: "json")!
        let data = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return data["buttonRule"] as! [[String: Any]]
    }()

    static let detection: [String: DetectionState] = ["idle": .idle, "listening": .listening, "paused": .paused]
    static let phases: [String: MaterialTapPhase] = [
        "notStarted": .notStarted, "capturingLongitudinal": .capturingLongitudinal,
        "reviewingLongitudinal": .reviewingLongitudinal, "capturingCross": .capturingCross,
        "reviewingCross": .reviewingCross, "waitingForFlcTap": .waitingForFlcTap, "capturingFlc": .capturingFlc,
        "reviewingFlc": .reviewingFlc, "complete": .complete,
    ]

    /// A case's state: the fields it sets, the rest left at ButtonState's defaults.
    static func state(_ s: [String: Any]) -> ButtonState {
        var state = ButtonState(detectionState: detection[s["detectionState"] as! String]!,
                                isMeasurementComplete: s["isMeasurementComplete"] as! Bool,
                                displayMode: s["displayMode"] as! String == "comparison" ? .comparison : .live)
        if let v = s["isReadyForDetection"] as? Bool { state.isReadyForDetection = v }
        if let v = s["fftIsRunning"] as? Bool { state.fftIsRunning = v }
        if let v = s["measurementType"] as? String { state.measurementType = MeasurementType.allCases.first { "\($0)" == v }! }
        if let v = s["materialTapPhase"] as? String { state.materialTapPhase = phases[v]! }
        if let v = s["numberOfTaps"] as? Int { state.numberOfTaps = v }
        if let v = s["isPlayingFile"] as? Bool { state.isPlayingFile = v }
        return state
    }

    @Test(arguments: cases.map { $0["id"] as! String })
    func buttonRule_case(_ id: String) {
        let row = Self.cases.first { $0["id"] as! String == id }!
        let out = buttonRule(Self.state(row["state"] as! [String: Any]))
        let expect = row["expect"] as! [String: Bool]
        if let v = expect["pauseEnabled"] { #expect(out.pauseEnabled == v, "\(id) pause") }
        if let v = expect["newTapDisabled"] { #expect(out.newTapDisabled == v, "\(id) new tap") }
        if let v = expect["cancelEnabled"] { #expect(out.cancelEnabled == v, "\(id) cancel") }
        if let v = expect["typeMenuEnabled"] { #expect(out.typeMenuEnabled == v, "\(id) type menu") }
    }

    // Save and the exports: enabled only when there is something to save or export — a complete
    // measurement or a comparison. One analyzer rule, read by the Save and export buttons and the menu.
    @Test func hasResultToSaveOrExport_onlyForACompleteMeasurementOrAComparison() {
        let sut = TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting())
        #expect(!sut.hasResultToSaveOrExport, "nothing to save or export while live")
        sut.isMeasurementComplete = true
        #expect(sut.hasResultToSaveOrExport, "a complete measurement")
        sut.isMeasurementComplete = false
        sut.displayMode = .comparison
        #expect(sut.hasResultToSaveOrExport, "a comparison")
    }
}
