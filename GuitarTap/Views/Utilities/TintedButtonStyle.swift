import SwiftUI

/// The tinted bordered button — the native `.bordered` button in its `.tint(…)`, with a light wash of
/// the tint while the pointer is over it, as the Python and web editions show hover. The button stays
/// the platform's own; only the hover fill is added. Touch has no hover, so it never shows there.
struct TintedBorderedButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(.bordered)
            .pointerHoverFill()
    }
}

extension PrimitiveButtonStyle where Self == TintedBorderedButtonStyle {
    /// `.bordered` with a hover fill in the button's tint.
    static var tintedBordered: TintedBorderedButtonStyle { TintedBorderedButtonStyle() }
}

/// A 10 % wash of the environment's tint behind the view while the pointer is over it.
private struct PointerHoverFill: ViewModifier {
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.tint.opacity(hovering && isEnabled ? 0.10 : 0))
            )
            .onHover { hovering = $0 }
    }
}

extension View {
    /// The hover wash on its own — for a two-state `Toggle` drawn as a button, whose on state the
    /// platform draws.
    func pointerHoverFill() -> some View {
        modifier(PointerHoverFill())
    }
}
