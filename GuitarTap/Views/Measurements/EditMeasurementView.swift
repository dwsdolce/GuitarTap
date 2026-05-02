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
/// - SeeAlso: `MeasurementsListView`, `MeasurementDetailView`,
///   `TapToneAnalyzer.updateMeasurement(at:measurementName:notes:)`

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

    private func save() {
        analyzer.updateMeasurement(
            at: index,
            measurementName: measurementName.isEmpty ? nil : measurementName,
            notes: notes.isEmpty ? nil : notes
        )
        dismiss()
    }
}
