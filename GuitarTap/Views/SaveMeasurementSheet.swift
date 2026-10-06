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
    /// Sheet-local edit state, seeded once at init from the loaded measurement's name/notes (or "").
    /// The sheet never writes back into shared view state — it hands the values to `onSave` on Save —
    /// so a re-armed measurement (New Tap) can't inherit a stale name/notes. Mirrors Python's ephemeral
    /// SaveMeasurementDialog (its QLineEdit/QTextEdit hold the edit; the view field is set only on Save)
    /// and the web SaveSheet (local `useState(defaultName)`, remounted per open).
    @State private var measurementName: String
    @State private var notes: String
    /// Invoked with the entered (name, notes) when the user confirms Save.
    let onSave: (String, String) -> Void

    /// Seeds the sheet's local fields at init — the loaded measurement's name/notes when re-saving one,
    /// else "". Mirrors the web SaveSheet's defaultName.
    init(defaultName: String = "", defaultNotes: String = "", onSave: @escaping (String, String) -> Void) {
        _measurementName = State(initialValue: defaultName)
        _notes = State(initialValue: defaultNotes)
        self.onSave = onSave
    }

    /// A name must be entered before Save is allowed. Owned by the model so all three agree.
    private var canSave: Bool { TapToneMeasurement.isValidName(measurementName) }

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
                        onSave(measurementName, notes)
                        dismiss()
                    }
                    .disabled(!canSave)
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
                            onSave(measurementName, notes)
                            dismiss()
                        }
                        .disabled(!canSave)
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
                    .background(Palette.color(.backgroundControl))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Palette.color(.separator), lineWidth: 0.5)
                    )
                Text("Add any observations about this measurement")
                    .font(.caption)
                    .foregroundColor(Palette.color(.textSecondary))
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
                    .foregroundColor(Palette.color(.textSecondary))
            }
        }
        .formStyle(.grouped)
        #endif
    }
}
