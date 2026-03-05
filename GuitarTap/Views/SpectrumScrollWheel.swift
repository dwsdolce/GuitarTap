//
//  SpectrumScrollWheel.swift
//  GuitarTap
//
//  macOS scroll wheel event monitoring infrastructure for SpectrumView.
//

#if os(macOS)
import SwiftUI
import AppKit

// MARK: - macOS Scroll Wheel Support

/// A view modifier that captures scroll wheel events using event monitoring
private struct ScrollWheelModifier: ViewModifier {
    let onScrollWheel: (NSEvent) -> Void

    func body(content: Content) -> some View {
        content.background(
            ScrollWheelMonitorView(onScrollWheel: onScrollWheel)
        )
    }
}

/// NSView that uses local event monitoring to capture scroll wheel events
private struct ScrollWheelMonitorView: NSViewRepresentable {
    let onScrollWheel: (NSEvent) -> Void

    func makeNSView(context: Context) -> ScrollWheelHostView {
        let view = ScrollWheelHostView()
        view.scrollHandler = onScrollWheel
        return view
    }

    func updateNSView(_ nsView: ScrollWheelHostView, context: Context) {
        nsView.scrollHandler = onScrollWheel
    }
}

/// Host view that monitors scroll events when mouse is within its bounds
class ScrollWheelHostView: NSView {
    var scrollHandler: ((NSEvent) -> Void)?
    private var eventMonitor: Any?
    private var isMouseInside = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupEventMonitor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupEventMonitor() {
        // Monitor scroll wheel events at the application level
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, self.isMouseInside else {
                return event  // Pass through if mouse not in our view
            }

            // Check if the event's window is our window
            guard event.window == self.window else {
                return event
            }

            // Handle the scroll event
            self.scrollHandler?(event)

            // Return nil to prevent further propagation (consume the event)
            return nil
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Remove old tracking areas
        trackingAreas.forEach { removeTrackingArea($0) }

        // Add new tracking area
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
    }

    // Return nil to be transparent to hit testing (allows SwiftUI gestures to work)
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

extension View {
    /// Adds scroll wheel event handling on macOS
    func onScrollWheel(_ handler: @escaping (NSEvent) -> Void) -> some View {
        self.modifier(ScrollWheelModifier(onScrollWheel: handler))
    }
}

#endif
