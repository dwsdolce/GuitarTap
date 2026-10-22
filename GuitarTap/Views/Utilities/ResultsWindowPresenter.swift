// @parity none — macOS shows the results in a free-floating window of their own; Python and the web show them in the
// main window.
/// # ResultsWindowPresenter
///
/// Manages a free-floating, non-modal `NSWindow` that hosts
/// `TapAnalysisResultsView` on macOS.
///
/// Unlike a sheet (which is modal and attached to the presenting window),
/// the results window floats independently so the user can interact with the
/// main analysis view and the results side-by-side.
///
/// ## Lifecycle
///
/// ```
/// let presenter = ResultsWindowPresenter()
/// presenter.onClose = { /* handle dismiss */ }
/// presenter.show(analyzer: ..., fftAnalyzer: ..., ...)   // open or refresh
/// presenter.close()                                       // programmatic close
/// ```
///
/// Calling `show(...)` while the window is already visible refreshes its
/// content in place and brings it to front, rather than opening a second window.
/// Setting `isRestorable = false` prevents macOS from saving and restoring this
/// auxiliary window across app launches.
///
/// - Note: This type is macOS-only (`#if os(macOS)`).
/// - SeeAlso: `TapAnalysisResultsView`, `TapToneAnalysisView`
#if os(macOS)
import AppKit
import SwiftUI

/// Manages a single free-floating `NSWindow` that hosts `TapAnalysisResultsView`.
///
/// Call `show(...)` to open or refresh the window, and `close()` to dismiss it
/// programmatically.  The `onClose` closure is invoked whenever the user or
/// code closes the window.
@MainActor
final class ResultsWindowPresenter: NSObject, NSWindowDelegate {

    // MARK: - Properties

    /// The managed window, or `nil` if it has never been opened.
    private var window: NSWindow?

    /// Called when the window is closed (by the user or programmatically).
    var onClose: (() -> Void)?

    // MARK: - Public Interface

    /// Opens or refreshes the results window with updated analyzer state.
    ///
    /// If the window is already visible, its SwiftUI content is replaced with
    /// a new hosting view built from the supplied parameters, and the window is
    /// brought to the front.  If the window does not exist or has been closed,
    /// a new `NSWindow` is created and positioned to the right of the main
    /// window (or centred on screen if no main window is available).
    ///
    /// - Parameters:
    ///   - analyzer: The tap-tone analyzer whose results are displayed.
    ///   - fftAnalyzer: The FFT analyzer providing live spectrum data.
    ///   - minFreq: Lower bound of the displayed frequency range, in Hz.
    ///   - maxFreq: Upper bound of the displayed frequency range, in Hz.
    ///   - onExportSpectrum: Callback invoked when the user requests spectrum export.
    ///   - onExportPDFReport: Callback invoked when the user requests PDF export.
    func show(
        analyzer: TapToneAnalyzer,
        fftAnalyzer: RealtimeFFTAnalyzer,
        minFreq: Float,
        maxFreq: Float,
        onExportSpectrum: @escaping () -> Void,
        onExportPDFReport: @escaping () -> Void
    ) {
        if let existing = window, existing.isVisible {
            // Update content and bring to front
            existing.contentView = makeHostingView(
                analyzer: analyzer,
                fftAnalyzer: fftAnalyzer,
                minFreq: minFreq,
                maxFreq: maxFreq,
                onExportSpectrum: onExportSpectrum,
                onExportPDFReport: onExportPDFReport
            )
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hostingView = makeHostingView(
            analyzer: analyzer,
            fftAnalyzer: fftAnalyzer,
            minFreq: minFreq,
            maxFreq: maxFreq,
            onExportSpectrum: onExportSpectrum,
            onExportPDFReport: onExportPDFReport
        )

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Analysis Results"
        win.contentView = hostingView
        win.delegate = self
        win.isReleasedWhenClosed = false
        win.isRestorable = false   // Prevent macOS from saving/restoring this window across launches
        win.minSize = NSSize(width: 400, height: 400)

        // Position to the right of the main window, aligned at the top
        if let mainWindow = NSApp.mainWindow {
            let mainFrame = mainWindow.frame
            let x = mainFrame.maxX + 20
            let y = mainFrame.maxY - 600
            win.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            win.center()
        }

        window = win
        win.makeKeyAndOrderFront(nil)
    }

    /// Closes the results window programmatically.
    ///
    /// If the window is not open, this is a no-op.
    func close() {
        window?.close()
    }

    // MARK: - NSWindowDelegate

    /// Notifies the presenter that the user has closed the window, triggering
    /// the `onClose` callback.
    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    // MARK: - Private

    /// Builds an `NSHostingView` wrapping `TapAnalysisResultsView` inside a
    /// `NavigationStack`.
    ///
    /// - Parameters:
    ///   - analyzer: Tap-tone analyzer to pass to the results view.
    ///   - fftAnalyzer: FFT analyzer to pass to the results view.
    ///   - minFreq: Minimum displayed frequency, in Hz.
    ///   - maxFreq: Maximum displayed frequency, in Hz.
    ///   - onExportSpectrum: Spectrum export action callback.
    ///   - onExportPDFReport: PDF report export action callback.
    /// - Returns: A configured `NSView` suitable for use as a window's
    ///   `contentView`.
    private func makeHostingView(
        analyzer: TapToneAnalyzer,
        fftAnalyzer: RealtimeFFTAnalyzer,
        minFreq: Float,
        maxFreq: Float,
        onExportSpectrum: @escaping () -> Void,
        onExportPDFReport: @escaping () -> Void
    ) -> NSView {
        let content = NavigationStack {
            TapAnalysisResultsView(
                analyzer: analyzer,
                fftAnalyzer: fftAnalyzer,
                minFreq: minFreq,
                maxFreq: maxFreq,
                onExportSpectrum: onExportSpectrum,
                onExportPDFReport: onExportPDFReport
            )
            .paletteSurface(.backgroundWindow)
            .navigationTitle("Analysis Results")
        }
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = .minSize
        return hosting
    }
}
#endif
