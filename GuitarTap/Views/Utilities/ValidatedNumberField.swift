//
//  ValidatedNumberField.swift
//  GuitarTap
//
// @parity view/validated-number-field

/// A numeric text field that rejects an over-precise keystroke *before* it is displayed, so the
/// disallowed character never appears (a 2-dp field accepts "29.35" but not "29.356"; a 0-dp field
/// rejects the decimal point entirely). Validity is decided by `FieldPrecision.decimalsWithin`.
///
/// SwiftUI's plain `TextField` can only reject a value *after* the character is shown — the binding's
/// setter runs a render pass too late, so the character flashes in and out. AppKit and UIKit text
/// fields expose a pre-display veto, which this wraps:
///   - iOS: `UITextField` + `textField(_:shouldChangeCharactersIn:replacementString:)`.
///   - macOS: `NSTextField` + a `Formatter` whose `isPartialStringValid` gates each edit.
///
/// The three editions share this validated numeric field as the `view/validated-number-field` parity
/// group, each using its framework's pre-display veto: this UITextField/NSTextField delegate on Swift,
/// a `QRegularExpressionValidator` on Python (`ValidatedNumberField`), and a synchronous `onChange`
/// revert on web (`NumberField`). The shared *precision policy* is a separate group, `FieldPrecision`
/// (`util/field-precision`); these widgets are its per-platform input adapters.

import SwiftUI

#if os(iOS)
import UIKit

struct ValidatedNumberField: UIViewRepresentable {
    @Binding var text: String
    let decimals: Int
    var placeholder: String = ""
    /// Negative values (e.g. dB) need the minus key, which `.decimalPad` lacks.
    var allowsNegative: Bool = false

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.borderStyle = .roundedRect
        field.keyboardType = allowsNegative ? .numbersAndPunctuation : .decimalPad
        field.textAlignment = .right
        field.font = UIFont.preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.placeholder = placeholder
        field.text = text
        field.delegate = context.coordinator
        field.addTarget(context.coordinator,
                        action: #selector(Coordinator.editingChanged(_:)),
                        for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text { uiView.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ValidatedNumberField
        init(_ parent: ValidatedNumberField) { self.parent = parent }

        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }
            let proposed = current.replacingCharacters(in: swiftRange, with: string)
            return FieldPrecision.decimalsWithin(proposed, parent.decimals)
        }

        @objc func editingChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
    }
}

#elseif os(macOS)
import AppKit

struct ValidatedNumberField: NSViewRepresentable {
    @Binding var text: String
    let decimals: Int
    var placeholder: String = ""
    /// Accepted on macOS for call-site parity with iOS; the keyboard has no relevance here.
    var allowsNegative: Bool = false

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.isEditable = true
        field.isSelectable = true
        field.drawsBackground = true
        field.alignment = .right
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.placeholderString = placeholder
        field.formatter = context.coordinator.formatter
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.formatter.decimals = decimals
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ValidatedNumberField
        let formatter: DecimalsFormatter

        init(_ parent: ValidatedNumberField) {
            self.parent = parent
            self.formatter = DecimalsFormatter(decimals: parent.decimals)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

/// A pass-through string formatter that only gates *partial* edits: `isPartialStringValid` vetoes any
/// keystroke that would exceed the field's precision, so the character is never shown.
final class DecimalsFormatter: Formatter {
    var decimals: Int

    init(decimals: Int) {
        self.decimals = decimals
        super.init()
    }

    required init?(coder: NSCoder) {
        self.decimals = 0
        super.init(coder: coder)
    }

    override func string(for obj: Any?) -> String? { obj as? String }

    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
                                 for string: String,
                                 errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        obj?.pointee = string as NSString
        return true
    }

    override func isPartialStringValid(_ partialString: String,
                                       newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
                                       errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        FieldPrecision.decimalsWithin(partialString, decimals)
    }
}
#endif
