//
//  SaveMeasurementSheet.swift
//  GuitarTap
//
//  Created by David Smith on 2/9/26.
//
import SwiftUI

struct SaveMeasurementSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var tapLocation: String
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
        Form {
            Section {
                TextField("Tap Location", text: $tapLocation, prompt: Text("Bridge, Soundhole, Upper Bout..."))
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Tap Location (Optional)")
                    .font(.headline)
            }
            
            Section {
                TextEditor(text: $notes)
                    .frame(minHeight: 80, idealHeight: 120)
                    .font(.body)
                    #if os(macOS)
                    .background(Color(NSColor.textBackgroundColor))
                    #endif
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
    }
}
