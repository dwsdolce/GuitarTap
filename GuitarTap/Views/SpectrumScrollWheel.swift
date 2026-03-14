/// # SpectrumScrollWheel
///
/// macOS scroll wheel event monitoring infrastructure for `SpectrumView`.
///
/// SwiftUI's built-in gesture system does not expose modifier-key-aware scroll
/// wheel events, which `SpectrumView` needs for zoom and pan operations that
/// behave differently depending on whether Command, Shift, Option, or Control
/// is held.  This file provides a thin AppKit bridge that captures
/// `NSEvent.scrollWheel` events at the application level and routes them to
/// a Swift closure.
///
/// ## Component roles
///
/// | Type | Role |
/// |------|------|
/// | `ScrollWheelModifier` | `ViewModifier` that places `ScrollWheelMonitorView` in the background |
/// | `ScrollWheelMonitorView` | `NSViewRepresentable` wrapper for `ScrollWheelHostView` |
/// | `ScrollWheelHostView` | `NSView` that installs/removes a local `NSEvent` monitor and tracks mouse entry/exit |
/// | `View.onScrollWheel(_:)` | Public API; applies `ScrollWheelModifier` to any view |
///
/// The monitor is local (application-scope), so it only fires when the app
/// is the active application.  Events are consumed (the monitor returns `nil`)
/// only when the mouse is inside the host view's bounds and inside the same
/// window, leaving all other scroll targets unaffected.
///
/// The host view returns `nil` from `hitTest(_:)` so it is transparent to
/// SwiftUI's own gesture recognisers.
///
/// - Note: This entire file is compiled only on macOS (`#if os(macOS)`).
/// - SeeAlso: `SpectrumView+GestureHandlers`
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

/// A view modifier that places a `ScrollWheelMonitorView` in the background of
/// any SwiftUI view to capture scroll wheel events with modifier key support.
private struct ScrollWheelModifier: ViewModifier {
    /// The handler to invoke when a scroll wheel event is captured.
    let onScrollWheel: (NSEvent) -> Void

    func body(content: Content) -> some View {
        content.background(
            ScrollWheelMonitorView(onScrollWheel: onScrollWheel)
        )
    }
}

/// `NSViewRepresentable` that creates a `ScrollWheelHostView` and keeps its
/// handler closure current as the SwiftUI state changes.
private struct ScrollWheelMonitorView: NSViewRepresentable {
    /// The closure forwarded to the `ScrollWheelHostView`'s event monitor.
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

/// `NSView` that installs a local `NSEvent` monitor for scroll wheel events and
/// forwards them to `scrollHandler` only while the mouse is inside its bounds
/// and in the same window.
///
/// The monitor is installed in `setupEventMonitor()` during `init` and removed
/// in `deinit`.  A tracking area covering the full bounds triggers
/// `mouseEntered` / `mouseExited` to gate event delivery.
///
/// - Note: `hitTest(_:)` returns `nil` so the view is invisible to AppKit's
///   normal hit-testing, leaving SwiftUI gesture recognisers unaffected.
class ScrollWheelHostView: NSView {
    /// Closure called when a qualifying scroll wheel event is captured.
    var scrollHandler: ((NSEvent) -> Void)?
    /// The registered local event monitor token; retained until `deinit`.
    private var eventMonitor: Any?
    /// `true` while the mouse cursor is inside this view's bounds.
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
    /// Attaches a scroll wheel event handler to a view on macOS.
    ///
    /// The handler receives the raw `NSEvent` so callers can inspect
    /// `scrollingDeltaX`, `scrollingDeltaY`, and `modifierFlags` to
    /// implement modifier-key-aware zoom/pan behaviour.
    ///
    /// Events are only delivered when the mouse is inside the view and in the
    /// same window; they are consumed and not propagated further.
    ///
    /// - Parameter handler: Closure invoked with each captured scroll wheel event.
    /// - Returns: The view with scroll wheel monitoring installed.
    func onScrollWheel(_ handler: @escaping (NSEvent) -> Void) -> some View {
        self.modifier(ScrollWheelModifier(onScrollWheel: handler))
    }
}

#endif
