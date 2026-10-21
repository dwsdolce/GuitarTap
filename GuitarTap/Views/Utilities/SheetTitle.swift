//
//  SheetTitle.swift
//  GuitarTap
//

import SwiftUI

#if os(macOS)
extension View {
    /// A macOS sheet's title — a sheet has no title bar, so the title sits at its top: the headline at the
    /// left with a line under it, on an opaque background so content scrolls under it. Every sheet uses it,
    /// so all their titles look the same.
    func sheetTitle(_ title: String) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                PaletteDivider()
            }
            .background(Palette.color(.backgroundPanel))
        }
    }
}
#endif
