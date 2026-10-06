//
//  LoadingOverlay.swift
//  GuitarTap
//

/// # LoadingOverlay
///
/// A full-screen dimmed overlay with a centered spinner and message label.
///
/// Placed using `.overlay` on the root content view to block interaction
/// during asynchronous operations: spectrum export, PDF report generation,
/// and measurement save. The overlay ignores safe-area insets so it covers
/// the entire window.
///
/// - SeeAlso: `TapToneAnalysisView+Layouts`

import SwiftUI

struct LoadingOverlay: View {
    let message: String
    
    var body: some View {
        ZStack {
            Palette.color(.scrim)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text(message)
                    .font(.headline)
                    .foregroundColor(Palette.color(.textOnColor))
            }
            .padding(30)
            .background(Palette.color(.overlayCard))
            .cornerRadius(12)
        }
    }
}
