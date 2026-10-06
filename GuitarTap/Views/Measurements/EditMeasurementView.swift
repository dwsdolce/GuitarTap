//
//  EditMeasurementView.swift
//  GuitarTap
//

/// # EditMeasurementView
///
/// A modal sheet for editing the `measurementName` and `notes` fields of an
/// existing saved `TapToneMeasurement`.
///
/// Pre-populates the fields from the measurement passed in and calls
/// `analyzer.updateMeasurement(at:measurementName:notes:)` on Save. The index
/// into `savedMeasurements` is used rather than `id` matching so that
/// duplicate imports (which share the same `id`) are treated independently.
///
/// Save is disabled until the name or notes actually differ from the stored values. A saved edit
/// mints a new measurement `id` — an amended measurement is a different dataset — so a Save that
/// changes nothing must not be reachable, or unchanged content would get a new identity. With the
/// button disabled, saving an untouched form and cancelling it are the same action.
///
/// - SeeAlso: `MeasurementsListView`, `MeasurementDetailView`,
///   `TapToneAnalyzer.updateMeasurement(at:measurementName:notes:)`

// @parity view/edit-sheet
import SwiftUI

struct EditMeasurementView: View {
    @Environment(\.dismiss) var dismiss
    let index: Int
    let measurement: TapToneMeasurement
    @ObservedObject var analyzer: TapToneAnalyzer

    @State private var measurementName: String
    @State private var notes: String

    init(index: Int, measurement: TapToneMeasurement, analyzer: TapToneAnalyzer) {
        self.index = index
        self.measurement = measurement
        self.analyzer = analyzer
        self._measurementName = State(initialValue: measurement.measurementName ?? "")
        self._notes = State(initialValue: measurement.notes ?? "")
    }

    /// The values Save would write, normalized by the model's own rules — the same ones the save
    /// path uses — so the change test compares against what would actually be stored.
    private var normalizedName: String? { TapToneMeasurement.normalizedName(measurementName) }
    private var normalizedNotes: String? { TapToneMeasurement.normalizedNotes(notes) }

    /// Whether Save would change anything — the gate on the Save button. The rule itself lives on
    /// the model (``TapToneMeasurement/isAmended(measurementName:notes:)``) so all three platforms
    /// and their tests share one definition; this view only supplies the normalized values.
    private var hasChanges: Bool {
        measurement.isAmended(measurementName: normalizedName, notes: normalizedNotes)
    }

    var body: some View {
        #if os(macOS)
        formContent
            .frame(minWidth: 450, idealWidth: 500, minHeight: 250, idealHeight: 350)
            .navigationTitle("Edit Measurement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!hasChanges)
                }
            }
        #else
        NavigationView {
            formContent
                .navigationTitle("Edit Measurement")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(!hasChanges)
                    }
                }
        }
        #endif
    }

    @ViewBuilder
    private var formContent: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Measurement")
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

    private func save() {
        analyzer.updateMeasurement(
            at: index,
            measurementName: normalizedName,
            notes: normalizedNotes
        )
        dismiss()
    }
}
