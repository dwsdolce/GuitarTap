//
//  ChartHelp.swift
//  GuitarTap
//
// @parity view/chart-help tests=test/chart-help
//
// The chart's help (its ⓘ): its lines, and which of them the device in use can do. The view shows these; the same
// lines are in every edition and in the shared chart-help.json.

#if os(iOS)
import GameController
import UIKit
#endif

/// One line of the chart's help: a gesture, what it does, and what the device needs for it to work.
struct ChartHelpLine: Equatable {
    enum Need: String { case pointer, keyboard, pinch }

    /// The gesture, with Apple's key symbols.
    let gesture: String
    /// The gesture's words on a system that is not Apple's, where they differ.
    var otherKeys: String? = nil
    let effect: String
    var needs: Set<Need> = []
}

enum ChartHelp {
    static let title = "Zoom & Pan Controls"

    /// The help's lines, in the groups a separator divides.
    static let groups: [[ChartHelpLine]] = [
        [
            ChartHelpLine(gesture: "Scroll over plot", effect: "Zoom both axes around cursor", needs: [.pointer]),
            ChartHelpLine(gesture: "Scroll over freq axis", effect: "Zoom frequency only", needs: [.pointer]),
            ChartHelpLine(gesture: "Scroll over mag axis", effect: "Zoom magnitude only", needs: [.pointer]),
            ChartHelpLine(gesture: "⇧ + Scroll", otherKeys: "Shift + Scroll", effect: "Pan frequency axis", needs: [.pointer, .keyboard]),
            ChartHelpLine(gesture: "⌥ + Scroll", otherKeys: "Alt + Scroll", effect: "Pan magnitude axis", needs: [.pointer, .keyboard]),
            ChartHelpLine(gesture: "⌘/⌃ + Scroll", otherKeys: "Ctrl + Scroll", effect: "Zoom both axes", needs: [.pointer, .keyboard]),
        ],
        [
            ChartHelpLine(gesture: "Pinch over plot", effect: "Zoom both axes", needs: [.pinch]),
            ChartHelpLine(gesture: "Pinch over freq axis", effect: "Zoom frequency only", needs: [.pinch]),
            ChartHelpLine(gesture: "Pinch over mag axis", effect: "Zoom magnitude only", needs: [.pinch]),
        ],
        [
            ChartHelpLine(gesture: "Drag over plot", effect: "Pan both axes"),
            ChartHelpLine(gesture: "Drag over freq axis", effect: "Pan frequency only"),
            ChartHelpLine(gesture: "Drag over mag axis", effect: "Pan magnitude only"),
            ChartHelpLine(gesture: "Right-click", effect: "Chart menu", needs: [.pointer]),
        ],
    ]

    /// What a device has, for its help.
    struct Device {
        var pointer: Bool
        var keyboard: Bool
        var pinch: Bool
        var appleKeys: Bool
    }

    /// The lines a device's help shows — (gesture, effect) — by group, empty groups left out.
    static func shown(on device: Device) -> [[(gesture: String, effect: String)]] {
        groups.compactMap { group in
            let lines = group.filter { line in
                line.needs.allSatisfy { need in
                    switch need {
                    case .pointer: device.pointer
                    case .keyboard: device.keyboard
                    case .pinch: device.pinch
                    }
                }
            }.map { (gesture: device.appleKeys ? $0.gesture : ($0.otherKeys ?? $0.gesture), effect: $0.effect) }
            return lines.isEmpty ? nil : lines
        }
    }

    /// The device in use: a Mac has a pointer, a keyboard and a trackpad; an iPad has touch, and a pointer or a
    /// keyboard while one is connected; an iPhone has touch, and a keyboard while one is connected — an iPhone does
    /// not use a mouse (no cursor, no buttons), though iOS still reports one connected, so it has no pointer.
    static var current: Device {
        #if os(macOS)
        Device(pointer: true, keyboard: true, pinch: true, appleKeys: true)
        #else
        Device(pointer: UIDevice.current.userInterfaceIdiom == .pad && !GCMouse.mice().isEmpty,
               keyboard: GCKeyboard.coalesced != nil, pinch: true, appleKeys: true)
        #endif
    }
}
