//
//  PointerScroll.swift
//  GuitarTap
//
// @parity none — iOS only: scrolling with a mouse or trackpad, which macOS has natively.

#if os(iOS)
import SwiftUI
import UIKit

/// A transparent layer that takes only scrolling from a connected mouse or trackpad — a wheel or a two-finger swipe —
/// and hands each step on with the modifier keys held and where the pointer is. Touches pass through it, so a drag,
/// a pinch and the crosshair beneath are untouched.
struct PointerScroll: UIViewRepresentable {
    let onScroll: (ScrollWheelEvent, CGPoint) -> Void

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateUIView(_ view: CatcherView, context: Context) {
        view.onScroll = onScroll
    }

    final class CatcherView: UIView {
        var onScroll: ((ScrollWheelEvent, CGPoint) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            let scroll = UIPanGestureRecognizer(target: self, action: #selector(scrolled(_:)))
            scroll.allowedScrollTypesMask = .all
            scroll.allowedTouchTypes = []
            addGestureRecognizer(scroll)
        }

        required init?(coder: NSCoder) { nil }

        /// Only a scroll lands here; touches and clicks go to the view beneath.
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard event?.type == .scroll else { return nil }
            return super.hitTest(point, with: event)
        }

        @objc private func scrolled(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .changed else { return }
            let step = recognizer.translation(in: self)
            recognizer.setTranslation(.zero, in: self)
            let flags = recognizer.modifierFlags
            var keys: ScrollModifiers = []
            if flags.contains(.shift) { keys.insert(.shift) }
            if flags.contains(.alternate) { keys.insert(.option) }
            if flags.contains(.command) { keys.insert(.command) }
            if flags.contains(.control) { keys.insert(.control) }
            // UIKit's scroll moves the opposite way to AppKit's scroll deltas: negated, the same gesture zooms and pans
            // the same way on both.
            onScroll?(ScrollWheelEvent(deltaX: -step.x, deltaY: -step.y, modifierFlags: keys), recognizer.location(in: self))
        }
    }
}
#endif
