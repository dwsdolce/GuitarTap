// @parity view/spectrum-gestures
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

// MARK: - Scroll Event Value

extension ScrollModifiers {
    /// The modifier keys among AppKit's flags.
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.control) { insert(.control) }
    }
}

// MARK: - macOS Scroll Wheel Support

/// A view modifier that places a `ScrollWheelMonitorView` in the background of
/// any SwiftUI view to capture scroll wheel events with modifier key support.
private struct ScrollWheelModifier: ViewModifier {
    /// The handler to invoke when a scroll wheel event is captured.
    let onScrollWheel: (ScrollWheelEvent) -> Void
    /// Called with the current mouse position (in the view's coordinate space)
    /// on every mouse-moved event. Use this to keep the cursor shape current.
    var cursorHandler: ((NSPoint) -> Void)?

    func body(content: Content) -> some View {
        content.background(
            ScrollWheelMonitorView(onScrollWheel: onScrollWheel, cursorHandler: cursorHandler)
        )
    }
}

/// `NSViewRepresentable` that creates a `ScrollWheelHostView` and keeps its
/// handler closure current as the SwiftUI state changes.
private struct ScrollWheelMonitorView: NSViewRepresentable {
    /// The closure forwarded to the `ScrollWheelHostView`'s event monitor.
    let onScrollWheel: (ScrollWheelEvent) -> Void
    /// Called with the mouse position on every mouse-moved event while inside bounds.
    var cursorHandler: ((NSPoint) -> Void)?

    func makeNSView(context: Context) -> ScrollWheelHostView {
        let view = ScrollWheelHostView()
        view.scrollHandler = onScrollWheel
        view.cursorHandler = cursorHandler
        return view
    }

    func updateNSView(_ nsView: ScrollWheelHostView, context: Context) {
        nsView.scrollHandler = onScrollWheel
        nsView.cursorHandler = cursorHandler
    }
}

/// `NSView` that installs local `NSEvent` monitors for scroll wheel and mouse-moved
/// events and forwards them to handler closures only while the mouse is inside its
/// bounds and in the same window.
///
/// The monitors are installed during `init` and removed in `deinit`.  A tracking
/// area covering the full bounds triggers `mouseEntered` / `mouseExited` to gate
/// event delivery.
///
/// **Cursor management**: `cursorHandler` is called on every mouse-moved event
/// (and mouse-entered) while inside bounds.  This keeps the cursor shape correct
/// even when SwiftUI re-renders (e.g. after scroll-wheel zoom) reset the system
/// cursor — the next mouse-moved event immediately re-asserts the right cursor.
///
/// **Scroll coalescing**: Rapid scroll-wheel events (e.g. trackpad at 60–120 Hz)
/// are coalesced into one delivery per display frame (~16 ms).  Deltas and modifier
/// flags are accumulated across events in the window and flushed as a single
/// synthesised event, preventing the chart from queueing more re-renders than it
/// can service and keeping zoom feel smooth.
///
/// - Note: `hitTest(_:)` returns `nil` so the view is invisible to AppKit's
///   normal hit-testing, leaving SwiftUI gesture recognisers unaffected.
class ScrollWheelHostView: NSView {
    /// Closure called with each coalesced scroll wheel event.
    var scrollHandler: ((ScrollWheelEvent) -> Void)?
    /// Closure called with the current mouse position (in view coordinates,
    /// y=0 at top) on every mouse-moved event while inside bounds.
    var cursorHandler: ((NSPoint) -> Void)?

    /// The registered local event monitor tokens; retained until `deinit`.
    private var scrollMonitor: Any?
    private var mouseMovedMonitor: Any?
    /// `true` while the mouse cursor is inside this view's bounds.
    private var isMouseInside = false

    // MARK: - Scroll coalescing state

    /// Accumulated scroll deltas waiting to be flushed.
    private var pendingDeltaX: CGFloat = 0
    private var pendingDeltaY: CGFloat = 0
    /// Modifier flags from the most recent pending event.
    private var pendingModifiers: NSEvent.ModifierFlags = []
    /// The most recent event — used as the template when synthesising the coalesced event.
    private var pendingTemplate: NSEvent? = nil
    /// Pending flush work item; cancelled when a new event arrives in the same frame.
    private var pendingFlush: DispatchWorkItem? = nil

    /// Interval between coalesced flushes — one display frame (≈16.7 ms at 60 Hz).
    private static let coalesceInterval: TimeInterval = 1.0 / 60.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupEventMonitors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupEventMonitors() {
        // Monitor scroll wheel events at the application level.
        // Events are coalesced: deltas are accumulated and flushed once per display
        // frame so rapid trackpad events don't flood the chart with re-renders.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, self.isMouseInside else {
                return event  // Pass through if mouse not in our view
            }
            guard event.window == self.window else {
                return event
            }
            self.accumulateScroll(event)
            // Return nil to prevent further propagation (consume the event)
            return nil
        }

        // Monitor mouse-moved events to keep the cursor shape correct.
        // SwiftUI re-renders (e.g. after scroll-wheel zoom) reset the system cursor
        // to the default arrow. The next mouse-moved event re-asserts the right cursor
        // via cursorHandler, so the flicker window is at most one mouse-move tick.
        mouseMovedMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            guard let self = self, self.isMouseInside, event.window == self.window else {
                return event
            }
            // Convert screen-relative event location to our flipped view coordinates
            if let point = self.mousePositionInView() {
                self.cursorHandler?(point)
            }
            return event  // Don't consume mouse-moved events
        }
    }

    // MARK: - Scroll coalescing

    /// Accumulates a raw scroll-wheel event's delta into the pending batch and
    /// schedules a single flush after one display frame.  If a flush is already
    /// pending it is cancelled and rescheduled so the window always stays
    /// exactly one frame wide.
    private func accumulateScroll(_ event: NSEvent) {
        pendingDeltaX += event.scrollingDeltaX
        pendingDeltaY += event.scrollingDeltaY
        pendingModifiers = event.modifierFlags
        pendingTemplate = event

        // Cancel any previously scheduled flush and reschedule.
        pendingFlush?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.flushPendingScroll()
        }
        pendingFlush = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalesceInterval, execute: item)
    }

    /// Builds a `ScrollWheelEvent` from the accumulated deltas and dispatches
    /// it to `scrollHandler`, then resets the pending state.
    private func flushPendingScroll() {
        guard pendingTemplate != nil else { return }
        let dx = pendingDeltaX
        let dy = pendingDeltaY
        let mods = pendingModifiers

        // Reset before calling the handler (handler may trigger more events)
        pendingDeltaX = 0
        pendingDeltaY = 0
        pendingTemplate = nil
        pendingFlush = nil

        scrollHandler?(ScrollWheelEvent(deltaX: dx, deltaY: dy, modifierFlags: ScrollModifiers(mods)))
    }

    /// Returns the current mouse position in this view's coordinate space (y=0 at top).
    private func mousePositionInView() -> NSPoint? {
        guard let window = window else { return nil }
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        // Convert from AppKit's flipped-false window coords to our flipped view coords
        let viewPoint = convert(windowPoint, from: nil)
        return viewPoint
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
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
        // Re-assert cursor immediately on entry in case it reset during a re-render
        if let point = mousePositionInView() {
            cursorHandler?(point)
        }
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
    }

    /// Use flipped coordinates so positions match SwiftUI's coordinate space (y=0 at top).
    override var isFlipped: Bool { true }

    // Return nil to be transparent to hit testing (allows SwiftUI gestures to work)
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    deinit {
        if let monitor = scrollMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = mouseMovedMonitor { NSEvent.removeMonitor(monitor) }
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
    /// - Parameter cursorHandler: Optional closure invoked on every mouse-moved event
    ///   while the mouse is inside the view. Receives the position in the view's
    ///   coordinate space (y=0 at top). Use this to keep the cursor shape correct
    ///   after SwiftUI re-renders triggered by scroll-wheel zoom.
    /// - Returns: The view with scroll wheel monitoring installed.
    func onScrollWheel(_ handler: @escaping (ScrollWheelEvent) -> Void,
                       cursorHandler: ((NSPoint) -> Void)? = nil) -> some View {
        self.modifier(ScrollWheelModifier(onScrollWheel: handler, cursorHandler: cursorHandler))
    }
}

#endif
