//
//  EmptyStateView.swift
//  GuitarTap
//

/// # EmptyStateView
///
/// A centered placeholder view displayed when a list or content area is empty.
///
/// Shows a large SF Symbol, a bold title, and a secondary descriptive message.
/// Used in `MeasurementsListView` when no saved measurements exist.
///
/// - SeeAlso: `MeasurementsListView`

import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(Palette.color(.textSecondary))
            
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.body)
                .foregroundColor(Palette.color(.textSecondary))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
