//
//  PeaksReader.swift
//  GuitarTap
//
// @parity model/detected-peaks tests=test/detected-peaks
//

import SwiftUI

/// The views that show the detected peaks — the chart, the controls that need peaks — built inside this reader,
/// which alone observes them: new peaks redraw what it wraps and nothing around it.
struct PeaksReader<Content: View>: View {
    @ObservedObject var peaks: DetectedPeaks
    @ViewBuilder let content: (DetectedPeaks) -> Content

    var body: some View { content(peaks) }
}

/// Disables a control while `isDisabled` holds, checked again whenever the detected peaks change — for the
/// controls that need peaks, so the view around them need not observe the peaks.
struct DisabledByPeaks: ViewModifier {
    @ObservedObject var peaks: DetectedPeaks
    let isDisabled: () -> Bool

    func body(content: Content) -> some View { content.disabled(isDisabled()) }
}
