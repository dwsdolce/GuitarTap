// @parity none — the iPad's About sheet, from its menu bar: macOS shows its own About panel, and Python's About is a
// message box in its main window; the words are Python's, and the version is the title's.
//
//  AboutView.swift
//  GuitarTap
//

import SwiftUI

/// About Guitar Tap: the icon, the name, the version and build, what the app does, and the copyright — the iPad's
/// counterpart of the Mac's About panel, opened from the menu bar's application menu.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image("AboutIcon")
                    .resizable()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
                Text("Guitar Tap")
                    .font(.title2.bold())
                Text("Version \(appVersion)")
                    .foregroundStyle(Palette.color(.textSecondary))
                Text("An acoustic analysis tool for guitar makers.\n\nTap-tone analysis using real-time FFT to identify resonant frequencies of guitar top and back plates.")
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                Text(copyright)
                    .font(.footnote)
                    .foregroundStyle(Palette.color(.textSecondary))
                    .padding(.top, 8)
            }
            .padding(32)
            .frame(maxWidth: 420)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .paletteSurface(.backgroundPanel)
    }
}
