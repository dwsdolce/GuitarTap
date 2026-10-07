// @parity view/material-peak-role
import SwiftUI

/// The role an identified plate or brace peak plays — its name, colour and badge wherever a peak is
/// shown by its role: the results panel's fL / fC / fLC badges and Measurement Details.
enum MaterialPeakRole: CaseIterable {
    case longitudinal
    case cross
    case flc

    var displayName: String {
        switch self {
        case .longitudinal: return "Longitudinal"
        case .cross:        return "Cross-grain"
        case .flc:          return "Diagonal"
        }
    }

    /// The badge's text — the frequency the role measures.
    var badgeLabel: String {
        switch self {
        case .longitudinal: return "fL"
        case .cross:        return "fC"
        case .flc:          return "fLC"
        }
    }

    /// fLC is wider for its third letter.
    var badgeWidth: CGFloat { self == .flc ? 42 : 36 }

    var paletteRole: Palette.Role {
        switch self {
        case .longitudinal: return .materialLongitudinal
        case .cross:        return .materialCross
        case .flc:          return .materialFlc
        }
    }
}

/// A role's badge: filled in its colour with white text when active, grey otherwise.
struct MaterialPhaseBadge: View {
    let role: MaterialPeakRole
    var active: Bool = true

    var body: some View {
        Text(role.badgeLabel)
            .font(.system(size: 8, weight: .bold))
            .frame(width: role.badgeWidth, height: 32)
            .background(active ? Palette.color(role.paletteRole) : Palette.color(.materialPhaseInactive))
            .foregroundColor(Palette.color(active ? .textOnColor : .textPrimary))
            .cornerRadius(6)
    }
}
