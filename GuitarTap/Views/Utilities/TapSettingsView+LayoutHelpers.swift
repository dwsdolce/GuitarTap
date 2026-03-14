//
//  TapSettingsView+LayoutHelpers.swift
//  GuitarTap
//

/// # TapSettingsView+LayoutHelpers
///
/// Reusable layout helpers shared across multiple form sections in
/// `TapSettingsView`.
///
/// ## Helper Views
///
/// | Helper | Description |
/// |---|---|
/// | `compactFrequencyRangeView` | Stacked (vertical) min/max pair for compact (iPhone) layout |
/// | `regularFrequencyRangeView` | Horizontal min/max pair for iPad and macOS layouts |
/// | `modeRangeRow` | Single row showing a guitar mode label and its Hz range |
///
/// `compactFrequencyRangeView` and `regularFrequencyRangeView` display
/// identical data; the caller decides which to use based on `isCompact`.
///
/// - SeeAlso: `TapSettingsView`, `TapSettingsView+Sections`, `TapSettingsView+Actions`

import SwiftUI

extension TapSettingsView {

    // MARK: - Layout Helpers

    /// Compact layout for iPhone — stacked vertically.
    @ViewBuilder
    func compactFrequencyRangeView(
        title: String,
        minBinding: Binding<String>,
        maxBinding: Binding<String>,
        unit: String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)

            VStack(spacing: 8) {
                HStack {
                    Text("Minimum:")
                        .frame(width: 80, alignment: .leading)
                        .foregroundColor(.secondary)
                    TextField("Min", text: minBinding)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(unit == "dB" ? .numbersAndPunctuation : .decimalPad)
                        #endif
                    Text(unit)
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .leading)
                }

                HStack {
                    Text("Maximum:")
                        .frame(width: 80, alignment: .leading)
                        .foregroundColor(.secondary)
                    TextField("Max", text: maxBinding)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(unit == "dB" ? .numbersAndPunctuation : .decimalPad)
                        #endif
                    Text(unit)
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .leading)
                }
            }

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    /// Regular layout for iPad and macOS — horizontal.
    @ViewBuilder
    func regularFrequencyRangeView(
        title: String,
        minBinding: Binding<String>,
        maxBinding: Binding<String>,
        unit: String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)

            HStack(spacing: 12) {
                TextField("Min", text: minBinding)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(unit == "dB" ? .numbersAndPunctuation : .decimalPad)
                    #endif
                    .frame(maxWidth: 100)

                Text("to")
                    .foregroundColor(.secondary)

                TextField("Max", text: maxBinding)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(unit == "dB" ? .numbersAndPunctuation : .decimalPad)
                    #endif
                    .frame(maxWidth: 100)

                Text(unit)
                    .foregroundColor(.secondary)
                    .font(.body)
            }

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helper Views

    /// A single row showing a guitar mode label and its classification frequency range.
    ///
    /// Used in the Measurement Type section to display the Hz bounds for each
    /// mode (Air, Top, Back, Dipole, Ring) for the selected guitar type.
    ///
    /// - Parameters:
    ///   - label: Short mode name displayed in a fixed-width leading column (e.g. `"Air:"`).
    ///   - range: The classification frequency range for the mode, in Hz.
    @ViewBuilder
    func modeRangeRow(_ label: String, range: ClosedRange<Float>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)
            Text("\(Int(range.lowerBound))-\(Int(range.upperBound)) Hz")
                .foregroundColor(.primary)
        }
    }
}
