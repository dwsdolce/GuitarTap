//
//  SaveMeasurementSheet.swift
//  GuitarTap
//
// @parity view/save-sheet

/// # SaveMeasurementSheet
///
/// A modal sheet for naming and saving the current tap tone measurement.
///
/// Provides optional free-text fields for measurement name (e.g., "Martin D-28",
/// "Ramirez 1975") and notes. The form is identical on both platforms; the
/// structural difference is:
///
/// - **macOS**: no `NavigationView` wrapper; the sheet receives a fixed
///   minimum size (`450 × 250 pt`).
/// - **iOS**: wrapped in a `NavigationView` so the nav-bar toolbar items
///   (Cancel / Save) are visible.
///
/// The `onSave` closure is called when the user confirms; the sheet then
/// dismisses itself.
///
/// - SeeAlso: `TapToneAnalysisView`, `TapToneAnalyzer.saveMeasurement`

import SwiftUI

struct SaveMeasurementSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var measurementName: String
    @Binding var notes: String
    let onSave: () -> Void
    
    var body: some View {
        #if os(macOS)
        // macOS layout without NavigationView wrapper
        formContent
            .frame(minWidth: 450, idealWidth: 500, minHeight: 250, idealHeight: 350)
            .navigationTitle("Save Measurement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        #else
        // iOS layout with NavigationView
        NavigationView {
            formContent
                .navigationTitle("Save Measurement")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave()
                            dismiss()
                        }
                    }
                }
        }
        #endif
    }
    
    @ViewBuilder
    private var formContent: some View {
        #if os(macOS)
        // Plain VStack layout — matches the iOS grouped form appearance
        // without macOS Form's label/value column behaviour.
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Measurement")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 6) {
                Text("Measurement Name")
                    .font(.headline)
                TextField("Measurement Name", text: $measurementName, prompt: Text("e.g. Martin 000-28, Spruce Top"))
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes (Optional)")
                    .font(.headline)
                TextEditor(text: $notes)
                    .font(.body)
                    .frame(minHeight: 80, idealHeight: 120)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
                Text("Add any observations about this measurement")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(20)
        #else
        Form {
            Section {
                TextField("Measurement Name", text: $measurementName, prompt: Text("e.g. Martin 000-28, Spruce Top"))
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Measurement Name")
                    .font(.headline)
            }

            Section {
                TextEditor(text: $notes)
                    .frame(minHeight: 80, idealHeight: 120)
                    .font(.body)
            } header: {
                Text("Notes (Optional)")
                    .font(.headline)
            } footer: {
                Text("Add any observations about this measurement")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        #endif
    }
}
