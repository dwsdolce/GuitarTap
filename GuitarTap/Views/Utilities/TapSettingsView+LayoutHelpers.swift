//
//  TapSettingsView+LayoutHelpers.swift
//  GuitarTap
//

/// # TapSettingsView+LayoutHelpers
///
/// The building blocks of the Settings sheet's own layout — the same in every edition: a section
/// is an icon and a bold title, its rows in a grey rounded box with no lines between them, and a
/// note under the box; a group inside a section is a plain bold title over its own box; a row is a
/// label on the left and its value or control right-aligned.
///
/// ## Helpers
///
/// | Helper | Description |
/// |---|---|
/// | `settingsSection` | Icon + title, the box, an optional note |
/// | `settingsGroup` | A plain title over a box |
/// | `settingsRow` | Label left, control right |
/// | `settingsToggleRow` | Label and description left, a checkbox right |
/// | `settingsActionButtons` | A row of tinted action buttons (stacks when narrow) |
/// | `settingsLinkRow` | An icon, a title and a trailing icon — a row that opens something |
/// | `rangeRow` | A title with "min to max unit" fields, right-aligned, and a description |
/// | `dimensionRow`, `densityRow`, `modeRangeRow` | The material and guitar rows |
///
/// - SeeAlso: `TapSettingsView`, `TapSettingsView+Sections`, `TapSettingsView+Actions`

import SwiftUI

/// The Settings sheet's type, the same in every edition: 13 pt rows and titles, 11 pt notes.
enum SettingsType {
    static let body = Font.system(size: 13)
    static let title = Font.system(size: 13, weight: .bold)
    static let caption = Font.system(size: 11)
}

extension TapSettingsView {

    /// The width of a number field: narrower on an iPhone so a range's two fields fit beside its title.
    var settingsFieldWidth: CGFloat { isCompact ? 64 : 80 }

    // MARK: - Sections and groups

    /// A section: an icon and a bold title, its rows in a grey box with no lines between them, and
    /// an optional note under the box.
    func settingsSection<Content: View>(_ title: String, icon: String, note: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(SettingsType.title)
                .foregroundColor(Palette.color(.textPrimary))
                .padding(.leading, 2)
            settingsBox(content: content)
            if let note {
                Text(note)
                    .font(SettingsType.caption)
                    .foregroundColor(Palette.color(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }

    /// A group inside a section: a plain bold title over its own box.
    func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(SettingsType.title)
                .foregroundColor(Palette.color(.textPrimary))
                .padding(.leading, 2)
            settingsBox(content: content)
        }
    }

    /// The grey rounded box a section's or group's rows sit in.
    func settingsBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .font(SettingsType.body)
        .foregroundColor(Palette.color(.textPrimary))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.color(.backgroundSubtle))
        .cornerRadius(8)
    }

    // MARK: - Rows

    /// A label on the left, its value or control right-aligned.
    func settingsRow<Control: View>(_ label: String, secondary: Bool = false,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundColor(Palette.color(secondary ? .textSecondary : .textPrimary))
            Spacer(minLength: 8)
            control()
        }
        .frame(minHeight: 28)
    }

    /// A description under a row, in the secondary colour.
    func settingsDescription(_ text: String) -> some View {
        Text(text)
            .font(SettingsType.caption)
            .foregroundColor(Palette.color(.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 2)
    }

    /// A setting that is on or off: its label and description on the left, a checkbox right-aligned
    /// (a switch on iOS, which has no checkbox).
    func settingsToggleRow(_ label: String, description: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let description {
                    Text(description)
                        .font(SettingsType.caption)
                        .foregroundColor(Palette.color(.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                #if os(macOS)
                .toggleStyle(.checkbox)
                #else
                .toggleStyle(.switch)
                #endif
        }
        .frame(minHeight: 28)
    }

    /// A row of tinted action buttons; on a narrow screen they stack rather than wrap their text.
    func settingsActionButtons<Buttons: View>(@ViewBuilder buttons: () -> Buttons) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                buttons()
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                buttons()
            }
        }
        .buttonStyle(.tinted(.accent))
        .padding(.vertical, 4)
    }

    /// A row that opens something: the icon in the accent, the title in the text colour, and a
    /// trailing icon (a chevron for a page, open-in-new for an outside link) in the secondary colour.
    func settingsLinkRow(_ title: String, icon: String, trailingIcon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(Palette.color(.accentText))
            Text(title)
                .foregroundColor(Palette.color(.textPrimary))
            Spacer()
            Image(systemName: trailingIcon)
                .font(SettingsType.caption)
                .foregroundColor(Palette.color(.textSecondary))
        }
        .frame(minHeight: 28)
        .contentShape(Rectangle())
    }

    /// A range: its title on the left, "min to max unit" right-aligned, its description below.
    @ViewBuilder
    func rangeRow(title: String, minBinding: Binding<String>, maxBinding: Binding<String>,
                  decimals: Int, unit: String, description: String) -> some View {
        settingsRow(title) {
            ValidatedNumberField(text: minBinding, decimals: decimals,
                                 placeholder: "Min", allowsNegative: unit == "dB")
                .frame(width: settingsFieldWidth)
            Text("to")
                .font(SettingsType.caption)
                .foregroundColor(Palette.color(.textSecondary))
            ValidatedNumberField(text: maxBinding, decimals: decimals,
                                 placeholder: "Max", allowsNegative: unit == "dB")
                .frame(width: settingsFieldWidth)
            unitLabel(unit)
        }
        settingsDescription(description)
    }

    /// A unit in a fixed column, so the fields line up whatever the unit.
    func unitLabel(_ unit: String) -> some View {
        Text(unit)
            .font(SettingsType.caption)
            .foregroundColor(Palette.color(.textSecondary))
            .frame(width: 20, alignment: .leading)
    }

    /// A dimension: its label (and an optional note under it), the field, and its unit.
    @ViewBuilder
    func dimensionRow(_ label: String, text: Binding<String>, decimals: Int, unit: String,
                      note: String? = nil) -> some View {
        settingsRow(label) {
            ValidatedNumberField(text: text, decimals: decimals)
                .frame(width: settingsFieldWidth)
            unitLabel(unit)
        }
        if let note {
            settingsDescription(note)
        }
    }

    /// The sample's density from the four fields, once all are valid.
    @ViewBuilder
    func densityRow(length: String, width: String, thickness: String, mass: String) -> some View {
        if let l = Float(length), let w = Float(width), let t = Float(thickness), let m = Float(mass),
           l > 0, w > 0, t > 0, m > 0 {
            let dims = MaterialDimensions(lengthMM: l, widthMM: w, thicknessMM: t, massGrams: m)
            settingsRow("Calculated Density", secondary: true) {
                Text("\(FieldPrecision.string(dims.densityGPerCm3, FieldPrecision.densityGPerCm3)) g/cm³")
                    .fontWeight(.semibold)
            }
        }
    }

    /// A single row showing a guitar mode label and its classification frequency range.
    ///
    /// - Parameters:
    ///   - label: Short mode name displayed in a fixed-width leading column (e.g. `"Air:"`).
    ///   - range: The classification frequency range for the mode, in Hz.
    @ViewBuilder
    func modeRangeRow(_ label: String, range: ClosedRange<Float>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundColor(Palette.color(.textSecondary))
                .frame(width: 50, alignment: .leading)
            Text("\(Int(range.lowerBound))-\(Int(range.upperBound)) Hz")
                .foregroundColor(Palette.color(.textPrimary))
        }
    }
}
