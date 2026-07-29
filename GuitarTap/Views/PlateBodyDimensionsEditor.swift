//
//  PlateBodyDimensionsEditor.swift
//  GuitarTap
//

import SwiftUI

/// Editable display of a completed plate measurement's own Gore body settings — the finished-guitar
/// body dimensions (a, b) and the panel vibrational stiffness (f_vs) — stored per-measurement in
/// ``MaterialMeasurementInputs`` (Store B). These feed only the Gore target thickness; editing a field
/// updates the measurement's `materialInputs` live so the target recomputes, and never touches the
/// Settings defaults (Store A). Shown only when the plate measurement is complete (its container gates
/// on that). See GuitarTapWeb/Development/MEASUREMENT-DIMENSIONS-SPEC.md.
struct PlateBodyDimensionsEditor: View {
    @Binding var inputs: MaterialMeasurementInputs

    @State private var bodyLengthText = ""
    @State private var bodyWidthText = ""
    @State private var customStiffnessText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            dimRow("Body Length (a)", text: $bodyLengthText,
                   decimals: FieldPrecision.bodyDimensionMM, unit: "mm") {
                inputs.bodyLengthMM = $0
            }
            dimRow("Lower Bout Width (b)", text: $bodyWidthText,
                   decimals: FieldPrecision.bodyDimensionMM, unit: "mm") {
                inputs.bodyWidthMM = $0
            }

            HStack {
                Text("Panel Stiffness (f_vs):")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $inputs.stiffnessPreset) {
                    ForEach(PlateStiffnessPreset.allCases) { preset in
                        Text(preset.shortName).tag(preset)
                    }
                }
                .labelsHidden()
                #if os(iOS)
                .pickerStyle(.menu)
                #endif
            }

            if inputs.stiffnessPreset == .custom {
                dimRow("Custom f_vs", text: $customStiffnessText,
                       decimals: FieldPrecision.stiffness, unit: "") {
                    inputs.customStiffness = $0
                }
            }
        }
        .onAppear(perform: seed)
        // Re-seed when the measurement itself changes (a new load / capture completes), NOT on a live
        // edit — seedField skips a field whose text already parses to the value, so typing isn't reset.
        .onChange(of: inputs) { _, _ in seed() }
    }

    private func seed() {
        seedField(&bodyLengthText, inputs.bodyLengthMM, FieldPrecision.bodyDimensionMM)
        seedField(&bodyWidthText, inputs.bodyWidthMM, FieldPrecision.bodyDimensionMM)
        seedField(&customStiffnessText, inputs.customStiffness, FieldPrecision.stiffness)
    }

    private func seedField(_ text: inout String, _ value: Float, _ decimals: Int) {
        if Float(text) != value {
            text = FieldPrecision.string(value, decimals)
        }
    }

    @ViewBuilder
    private func dimRow(_ label: String, text: Binding<String>, decimals: Int, unit: String,
                        commit: @escaping (Float) -> Void) -> some View {
        HStack {
            Text("\(label):")
                .font(.subheadline)
            Spacer()
            ValidatedNumberField(text: text, decimals: decimals)
                .frame(width: 80)
                .onChange(of: text.wrappedValue) { _, newText in
                    if let v = Float(newText) {
                        commit(FieldPrecision.rounded(v, decimals))
                    }
                }
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
