// ResultsWindowPresenter.swift
// GuitarTap
//
// Presents TapAnalysisResultsView in a free-floating, movable NSWindow on macOS
// instead of a modal sheet.

#if os(macOS)
import AppKit
import SwiftUI

/// Manages a single free-floating NSWindow that hosts TapAnalysisResultsView.
/// Call `show(...)` to open/update it and `close()` to dismiss it.
@MainActor
final class ResultsWindowPresenter: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    var onClose: (() -> Void)?

    func show(
        analyzer: TapToneAnalyzer,
        fftAnalyzer: RealtimeFFTAnalyzer,
        minFreq: Float,
        maxFreq: Float,
        onExportPDFReport: @escaping () -> Void
    ) {
        if let existing = window, existing.isVisible {
            // Update content and bring to front
            existing.contentView = makeHostingView(
                analyzer: analyzer,
                fftAnalyzer: fftAnalyzer,
                minFreq: minFreq,
                maxFreq: maxFreq,
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
        win.minSize = NSSize(width: 400, height: 400)

        // Position near the main window
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

    func close() {
        window?.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    // MARK: - Private

    private func makeHostingView(
        analyzer: TapToneAnalyzer,
        fftAnalyzer: RealtimeFFTAnalyzer,
        minFreq: Float,
        maxFreq: Float,
        onExportPDFReport: @escaping () -> Void
    ) -> NSView {
        let content = NavigationStack {
            TapAnalysisResultsView(
                analyzer: analyzer,
                fftAnalyzer: fftAnalyzer,
                minFreq: minFreq,
                maxFreq: maxFreq,
                onExportPDFReport: onExportPDFReport
            )
            .navigationTitle("Analysis Results")
        }
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = .minSize
        return hosting
    }
}
#endif
