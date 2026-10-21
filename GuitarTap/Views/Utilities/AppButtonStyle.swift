//
//  AppButtonStyle.swift
//  GuitarTap
//
// @parity view/button-style tests=test/button-style
//
// The buttons the app draws itself, in every edition the same: four kinds, each in theme roles and opacities.
//
// - plain: an action with no particular meaning — `text.primary` on `background.control`, a `separator` border, an
//   accent wash at `button.plainHover` under the pointer;
// - tinted: a role names its colour — the label in the role on the role at `button.tintFill`; hover, pressed, on and
//   on + hover at their `button.tint…` opacities;
// - prominent: the main action of a sheet — filled with its role, the label in `text.onColor`, the fill at
//   `button.prominentHover` under the pointer; one that cannot act is drawn as a plain button;
// - icon: an icon in its role, no frame and no fill; under the pointer the plain button's wash on a patch behind it
//   (`Palette.ButtonShape.iconPadding`).
//
// A button that cannot act is drawn at `control.dimmed`, whole. The corner radius and padding are
// `Palette.ButtonShape`. A toggle drawn as a button is a tinted button with an on state (`AppToggleStyle`).

import SwiftUI

/// The kind of button the app draws.
enum AppButtonKind {
    case plain
    case tinted(Palette.Role)
    case prominent(Palette.Role)
    case icon(Palette.Role)
}

/// A button the app draws: see the file comment.
struct AppButtonStyle: ButtonStyle {
    let kind: AppButtonKind
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        AppButtonBody(label: configuration.label, isPressed: configuration.isPressed, kind: kind, isOn: isOn)
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    /// An action with no particular meaning.
    static var appPlain: AppButtonStyle { AppButtonStyle(kind: .plain) }
    /// A button whose colour is `role`'s; `isOn` for a toggle that is on.
    static func tinted(_ role: Palette.Role, isOn: Bool = false) -> AppButtonStyle {
        AppButtonStyle(kind: .tinted(role), isOn: isOn)
    }
    /// The main action of a sheet, filled with `role`.
    static func prominent(_ role: Palette.Role = .accent) -> AppButtonStyle { AppButtonStyle(kind: .prominent(role)) }
    /// An icon in `role`, no frame.
    static func icon(_ role: Palette.Role = .textSecondary) -> AppButtonStyle { AppButtonStyle(kind: .icon(role)) }
}

/// A toggle drawn as a tinted button: on, the fill at `button.tintOn`.
struct AppToggleStyle: ToggleStyle {
    let role: Palette.Role

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: { configuration.label }
            .buttonStyle(.tinted(role, isOn: configuration.isOn))
    }
}

extension ToggleStyle where Self == AppToggleStyle {
    /// A toggle drawn as a button tinted by `role`.
    static func tinted(_ role: Palette.Role) -> AppToggleStyle { AppToggleStyle(role: role) }
}

/// A button's state, for its look.
enum AppButtonState { case rest, hover, pressed, on, onHover, cannotAct }

/// What a button the app draws looks like in a state — the one rule the drawing follows.
struct AppButtonLook: Equatable {
    var text: Palette.Role
    /// The fill; nil for none (an icon button).
    var fill: Palette.Role?
    var fillOpacity: Palette.Opacity?
    var washRole: Palette.Role?
    var washOpacity: Palette.Opacity?
    var border: Palette.Role?
    var drawnAt: Palette.Opacity?
    var prominentPadding = false

    static func of(_ kind: AppButtonKind, _ state: AppButtonState) -> AppButtonLook {
        let dimmed: Palette.Opacity? = state == .cannotAct ? .controlDimmed : nil
        let plain = AppButtonLook(text: .textPrimary, fill: .backgroundControl, fillOpacity: nil,
                                  washRole: state == .hover ? .accent : nil,
                                  washOpacity: state == .hover ? .buttonPlainHover : nil,
                                  border: .separator, drawnAt: dimmed)
        switch kind {
        case .plain:
            return plain
        case .tinted(let role):
            let fill: Palette.Opacity = switch state {
            case .hover: .buttonTintHover
            case .pressed: .buttonTintPressed
            case .on: .buttonTintOn
            case .onHover: .buttonTintOnHover
            case .rest, .cannotAct: .buttonTintFill
            }
            return AppButtonLook(text: role, fill: role, fillOpacity: fill, border: nil, drawnAt: dimmed)
        case .prominent(let role):
            // A prominent button that cannot act is drawn as a plain one, dimmed.
            if state == .cannotAct { var look = plain; look.prominentPadding = true; return look }
            return AppButtonLook(text: .textOnColor, fill: role,
                                 fillOpacity: state == .hover ? .buttonProminentHover : nil,
                                 border: nil, drawnAt: nil, prominentPadding: true)
        case .icon(let role):
            return AppButtonLook(text: role, fill: nil, fillOpacity: nil, washRole: plain.washRole,
                                 washOpacity: plain.washOpacity, border: nil, drawnAt: dimmed)
        }
    }
}

private struct AppButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let kind: AppButtonKind
    let isOn: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var state: AppButtonState {
        if !isEnabled { return .cannotAct }
        if isOn { return hovering ? .onHover : .on }
        if isPressed { return .pressed }
        return hovering ? .hover : .rest
    }

    var body: some View {
        drawn
            .contentShape(RoundedRectangle(cornerRadius: Palette.ButtonShape.cornerRadius))
            .onHover { hovering = $0 }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Palette.ButtonShape.cornerRadius, style: .continuous)
    }

    private var drawn: some View {
        let look = AppButtonLook.of(kind, state)
        let padding: (vertical: CGFloat, horizontal: CGFloat) = if case .icon = kind {
            Palette.ButtonShape.iconPadding
        } else if look.prominentPadding {
            Palette.ButtonShape.prominentPadding
        } else {
            Palette.ButtonShape.padding
        }
        return label
            .foregroundStyle(Palette.color(look.text))
            .padding(.vertical, padding.vertical)
            .padding(.horizontal, padding.horizontal)
            .background(shape.fill(look.fill.map { Palette.color($0).opacity(look.fillOpacity.map { Palette.opacity($0) } ?? 1) }
                                   ?? Color.clear))
            .overlay(shape.fill(look.washRole.map { Palette.color($0).opacity(look.washOpacity.map { Palette.opacity($0) } ?? 0) }
                                ?? Color.clear))
            .overlay(shape.stroke(look.border.map { Palette.color($0) } ?? Color.clear, lineWidth: look.border == nil ? 0 : 1))
            .opacity(look.drawnAt.map { Palette.opacity($0) } ?? 1)
    }
}
