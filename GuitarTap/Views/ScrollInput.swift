//
//  ScrollInput.swift
//  GuitarTap
//
// @parity view/spectrum-gestures
//
// A scroll over the chart from a mouse or trackpad, on either platform: its deltas and the modifier keys held. macOS
// reads it from AppKit's scroll events (SpectrumScrollWheel), iOS from UIKit's (PointerScroll); the chart handles it
// the same way on both (handleScrollWheel).

import CoreGraphics

/// The modifier keys held during a scroll.
struct ScrollModifiers: OptionSet {
    let rawValue: Int
    static let shift = ScrollModifiers(rawValue: 1 << 0)
    static let option = ScrollModifiers(rawValue: 1 << 1)
    static let command = ScrollModifiers(rawValue: 1 << 2)
    static let control = ScrollModifiers(rawValue: 1 << 3)
}

/// The coalesced values of one or more scroll events.
struct ScrollWheelEvent {
    /// Accumulated horizontal scroll delta (positive = right).
    let deltaX: CGFloat
    /// Accumulated vertical scroll delta (positive = down).
    let deltaY: CGFloat
    /// The modifier keys held at the most recent contributing event.
    let modifierFlags: ScrollModifiers
}
