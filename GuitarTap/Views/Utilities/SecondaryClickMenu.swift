//
//  SecondaryClickMenu.swift
//  GuitarTap
//
// @parity none — iOS only: a menu on the secondary mouse button, as macOS has natively.

#if os(iOS)
import SwiftUI
import UIKit

/// A transparent layer that catches only a secondary (right) click from a mouse or trackpad and opens a menu at
/// the click. Touches and the primary button pass through it, so a long press and a drag on the view beneath are
/// untouched — which `.contextMenu` would not allow, since it also opens on a long press.
struct SecondaryClickMenu: UIViewRepresentable {
    /// The menu, built when it opens.
    let menu: () -> UIMenu
    /// Whether a click at this point belongs to something on top with a menu of its own (a peak label): it is let
    /// through to it.
    var passesThrough: (CGPoint) -> Bool = { _ in false }

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.menuProvider = menu
        view.passesThrough = passesThrough
        return view
    }

    func updateUIView(_ view: CatcherView, context: Context) {
        view.menuProvider = menu
        view.passesThrough = passesThrough
    }

    final class CatcherView: UIView, UIEditMenuInteractionDelegate {
        var menuProvider: (() -> UIMenu)?
        var passesThrough: ((CGPoint) -> Bool)?
        private var editMenu: UIEditMenuInteraction?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            let interaction = UIEditMenuInteraction(delegate: self)
            addInteraction(interaction)
            editMenu = interaction
            let click = UITapGestureRecognizer(target: self, action: #selector(secondaryClick(_:)))
            click.buttonMaskRequired = UIEvent.ButtonMask.secondary
            addGestureRecognizer(click)
        }

        required init?(coder: NSCoder) { nil }

        /// Only a secondary-button event lands here; everything else goes to the view beneath.
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard let event, event.buttonMask.contains(UIEvent.ButtonMask.secondary),
                  passesThrough?(point) != true else { return nil }
            return super.hitTest(point, with: event)
        }

        @objc private func secondaryClick(_ recognizer: UITapGestureRecognizer) {
            let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: recognizer.location(in: self))
            editMenu?.presentEditMenu(with: configuration)
        }

        func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                                 menuFor configuration: UIEditMenuConfiguration,
                                 suggestedActions: [UIMenuElement]) -> UIMenu? {
            menuProvider?()
        }
    }
}
#endif
