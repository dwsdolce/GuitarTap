//
//  FrameReader.swift
//  GuitarTap
//
// @parity model/live-frame tests=test/live-frame
//

import SwiftUI

/// The views that draw a live frame — the spectrum, the status bar's readouts — built inside this reader, which
/// alone observes the frame: a frame redraws what it wraps and nothing around it.
struct FrameReader<Content: View>: View {
    @ObservedObject var frame: LiveFrame
    @ViewBuilder let content: (LiveFrame) -> Content

    var body: some View { content(frame) }
}
