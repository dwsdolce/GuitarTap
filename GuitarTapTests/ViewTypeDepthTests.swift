//
//  ViewTypeDepthTests.swift
//  GuitarTapTests
//
// @parity none — SwiftUI's generic view types and the depth the runtime decodes them at; Python's widgets and the
// web's components have no such type to measure.

import SwiftUI
import Testing
@testable import GuitarTap

/// How deeply a view's type nests. A SwiftUI body's type nests one generic per container and modifier; when it is
/// first drawn, the runtime decodes that type recursively, several stack frames per level. On an iPhone the main
/// thread's stack is about 1 MB (8 MB on the Mac and in the simulators), so a type that is too deep overflows it
/// there only — no simulator run can see it. These tests measure the depth instead, which does not depend on the
/// stack.
///
/// The Settings sheet overflowed an iPhone at about 51 levels: its sections nested into `body` from level 25. Each
/// section now sits behind `AnyView`, which ends its type there, so the runtime decodes `body` and each section
/// separately; Saved Measurements' list the same way. The limit leaves a wide margin under the depth that failed.
@MainActor
struct ViewTypeDepthTests {
    static let limit = 36

    /// The deepest generic nesting in a type's name: the count of unclosed `<` at its deepest point.
    static func depth(of type: Any.Type) -> Int {
        var level = 0, deepest = 0
        for c in String(reflecting: type) {
            if c == "<" { level += 1; deepest = max(deepest, level) } else if c == ">" { level -= 1 }
        }
        return deepest
    }

    @Test func settingsSheetIsShallowEnoughForAnIPhone() {
        let view = TapSettingsView(minFreq: .constant(75), maxFreq: .constant(350), minDB: .constant(-100),
                                   maxDB: .constant(0), peakMinThreshold: .constant(-60),
                                   fftAnalyzer: RealtimeFFTAnalyzer(forTesting: true))
        let parts: [(String, Any.Type)] = [
            ("body", type(of: view.body)),
            ("audioInputSection", type(of: view.audioInputSection)),
            ("measurementTypeSection", type(of: view.measurementTypeSection)),
            ("advancedRow", type(of: view.advancedRow)),
            ("displaySettingsSection", type(of: view.displaySettingsSection)),
            ("analysisSettingsSection", type(of: view.analysisSettingsSection)),
            ("aboutSection", type(of: view.aboutSection)),
        ]
        for (name, type) in parts {
            #expect(Self.depth(of: type) <= Self.limit, "\(name) nests \(Self.depth(of: type)) levels deep")
        }
    }

    @Test func savedMeasurementsIsShallowEnoughForAnIPhone() {
        let view = MeasurementsListView(analyzer: TapToneAnalyzer(fftAnalyzer: RealtimeFFTAnalyzer.forTesting()))
        for (name, type) in [("body", type(of: view.body)), ("contentView", type(of: view.contentView))] as [(String, Any.Type)] {
            #expect(Self.depth(of: type) <= Self.limit, "\(name) nests \(Self.depth(of: type)) levels deep")
        }
    }
}
