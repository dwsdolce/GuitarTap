//
//  MaterialDimensionsEditor.swift
//  GuitarTap
//
// @parity view/material-dimensions-editor

import SwiftUI

/// Editable display of a completed material measurement's own dimensions — Store B
/// (``MaterialMeasurementInputs``) — shown in the Results panel's Plate/Brace Properties. Editing a
/// field updates the measurement's `materialInputs` live, so every derived property recomputes; it
/// never touches the Settings defaults (Store A). Shown only when the measurement is complete (its
/// container gates on that).
struct MaterialDimensionsEditor: View {
    @Binding var inputs: MaterialMeasurementInputs

    @State private var lengthText = ""
    @State private var widthText = ""
    @State private var thicknessText = ""
    @State private var massText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            dimRow("Length", text: $lengthText, decimals: FieldPrecision.linearDimensionMM, unit: "mm") {
                inputs.lengthMM = $0
            }
            dimRow("Width", text: $widthText, decimals: FieldPrecision.linearDimensionMM, unit: "mm") {
                inputs.widthMM = $0
            }
            dimRow("Thickness", text: $thicknessText, decimals: FieldPrecision.linearDimensionMM, unit: "mm") {
                inputs.thicknessMM = $0
            }
            dimRow("Mass", text: $massText, decimals: FieldPrecision.massG, unit: "g") {
                inputs.massG = $0
            }

            // Derived, read-only — recomputes as the dimensions above change.
            HStack {
                Text("Calculated Density:")
                    .font(.system(size: 10))
                    .foregroundColor(Palette.color(.textSecondary))
                Spacer()
                Text("\(FieldPrecision.string(inputs.dimensions.densityGPerCm3, FieldPrecision.densityGPerCm3)) g/cm³")
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .onAppear(perform: seed)
        // Re-seed when the measurement itself changes (a new load / capture completes), NOT on a live
        // edit — seedField skips a field whose text already parses to the value, so typing isn't reset.
        .onChange(of: inputs) { _, _ in seed() }
    }

    private func seed() {
        seedField(&lengthText, inputs.lengthMM, FieldPrecision.linearDimensionMM)
        seedField(&widthText, inputs.widthMM, FieldPrecision.linearDimensionMM)
        seedField(&thicknessText, inputs.thicknessMM, FieldPrecision.linearDimensionMM)
        seedField(&massText, inputs.massG, FieldPrecision.massG)
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
                .font(.system(size: 10))
            Spacer()
            ValidatedNumberField(text: text, decimals: decimals, fontSize: 10)
                .frame(width: 70)
                .onChange(of: text.wrappedValue) { _, newText in
                    if let v = Float(newText) {
                        commit(FieldPrecision.rounded(v, decimals))
                    }
                }
            // A fixed-width unit column, so "g" and "mm" leave the fields above one another.
            Text(unit)
                .font(.system(size: 10))
                .foregroundColor(Palette.color(.textSecondary))
                .frame(width: 20, alignment: .leading)
        }
    }
}
