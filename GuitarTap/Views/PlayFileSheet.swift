//
//  PlayFileSheet.swift
//  GuitarTap
//

/// # PlayFileSheet
///
/// A modal sheet for selecting an audio file and an optional microphone
/// calibration file before file playback.
///
/// The user must select an audio file (WAV, AIFF, etc.) and may optionally
/// provide a calibration file (.txt, .cal) that was active when the recording
/// was made.  Without the correct calibration, magnitude values from file
/// playback may differ from the original interactive measurement.
///
/// ## Platform layout
///
/// - **macOS**: no `NavigationView` wrapper; the sheet receives a fixed
///   minimum size.
/// - **iOS**: wrapped in a `NavigationView` so the nav-bar toolbar items
///   (Cancel / Play) are visible.
///
/// - SeeAlso: `SaveMeasurementSheet`, `TapToneAnalysisView`

import SwiftUI
internal import UniformTypeIdentifiers

struct PlayFileSheet: View {
    @Environment(\.dismiss) var dismiss

    @State private var audioURL: URL? = nil
    @State private var calibrationURL: URL? = nil
    @State private var showingAudioPicker = false
    @State private var showingCalibrationPicker = false

    let onPlay: (URL, URL?) -> Void

    var body: some View {
        #if os(macOS)
        formContent
            .frame(minWidth: 450, idealWidth: 500, minHeight: 200, idealHeight: 250)
            .navigationTitle("Play Audio File")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Play") {
                        guard let url = audioURL else { return }
                        onPlay(url, calibrationURL)
                        dismiss()
                    }
                    .disabled(audioURL == nil)
                }
            }
        #else
        NavigationView {
            formContent
                .navigationTitle("Play Audio File")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Play") {
                            guard let url = audioURL else { return }
                            onPlay(url, calibrationURL)
                            dismiss()
                        }
                        .disabled(audioURL == nil)
                    }
                }
        }
        #endif
    }

    @ViewBuilder
    private var formContent: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            Text("Play Audio File")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .center)

            // Audio file row
            VStack(alignment: .leading, spacing: 6) {
                Text("Audio File")
                    .font(.headline)
                HStack {
                    Text(audioURL?.lastPathComponent ?? "No file selected")
                        .foregroundColor(audioURL == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Browse\u{2026}") { showingAudioPicker = true }
                }
            }
            .fileImporter(
                isPresented: $showingAudioPicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    audioURL = url
                }
            }

            // Calibration file row
            VStack(alignment: .leading, spacing: 6) {
                Text("Calibration File (Optional)")
                    .font(.headline)
                HStack {
                    Text(calibrationURL?.lastPathComponent ?? "None")
                        .foregroundColor(calibrationURL == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if calibrationURL != nil {
                        Button("Clear") { calibrationURL = nil }
                    }
                    Button("Browse\u{2026}") { showingCalibrationPicker = true }
                }
                Text("Select the calibration file that was active when the recording was made")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .fileImporter(
                isPresented: $showingCalibrationPicker,
                allowedContentTypes: [.text, .plainText, .commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    calibrationURL = url
                }
            }

            Spacer()
        }
        .padding(20)
        #else
        Form {
            Section {
                HStack {
                    Text(audioURL?.lastPathComponent ?? "No file selected")
                        .foregroundColor(audioURL == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Browse\u{2026}") { showingAudioPicker = true }
                }
            } header: {
                Text("Audio File")
                    .font(.headline)
            }
            .fileImporter(
                isPresented: $showingAudioPicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    audioURL = url
                }
            }

            Section {
                HStack {
                    Text(calibrationURL?.lastPathComponent ?? "None")
                        .foregroundColor(calibrationURL == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if calibrationURL != nil {
                        Button("Clear") { calibrationURL = nil }
                    }
                    Button("Browse\u{2026}") { showingCalibrationPicker = true }
                }
            } header: {
                Text("Calibration File (Optional)")
                    .font(.headline)
            } footer: {
                Text("Select the calibration file that was active when the recording was made")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .fileImporter(
                isPresented: $showingCalibrationPicker,
                allowedContentTypes: [.text, .plainText, .commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    calibrationURL = url
                }
            }
        }
        .formStyle(.grouped)
        #endif
    }
}
