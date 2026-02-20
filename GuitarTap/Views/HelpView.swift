//
//  HelpView.swift
//  GuitarTap
//

import SwiftUI

struct HelpView: View {
    var body: some View {
        List {
            Section {
                Text("Guitar Tap uses your device's microphone to capture the sound of a tap on a guitar top, back, or wood sample, then performs a Fast Fourier Transform (FFT) to reveal the resonant frequencies.")
                    .font(.body)
            } header: {
                Label("How It Works", systemImage: "waveform.path.ecg")
            }

            Section {
                helpRow(
                    title: "Start / Stop",
                    body: "Tap the play button to start the microphone and live spectrum. Tap stop to freeze the display."
                )
                helpRow(
                    title: "Tap the Wood",
                    body: "Tap the guitar top, back, side, or wood sample firmly with a knuckle while the analyzer is running. The spectrum will freeze automatically when a tap is detected."
                )
                helpRow(
                    title: "Reading Peaks",
                    body: "Colored markers on the spectrum indicate detected resonant peaks. Each peak is classified into a mode (Air, Top, Back, Dipole, Ring) based on its frequency."
                )
                helpRow(
                    title: "Saving Measurements",
                    body: "After a tap is detected, use the Save button to store the measurement with a location label and optional notes."
                )
            } header: {
                Label("Basic Operation", systemImage: "hand.tap")
            }

            Section {
                helpRow(
                    title: "Measurement Type",
                    body: "Choose the guitar type (Classical, Steel String, Archtop) to apply the correct mode frequency ranges, or choose Material to measure a wood sample's stiffness properties."
                )
                helpRow(
                    title: "Display Range",
                    body: "Adjust the frequency and magnitude ranges to zoom in on the part of the spectrum you care about."
                )
                helpRow(
                    title: "Analysis Range",
                    body: "Sets the frequency window used for peak detection. Peaks outside this range are ignored."
                )
                helpRow(
                    title: "Peak Threshold",
                    body: "The minimum magnitude (in dB) a peak must reach to be detected. Raise this value to filter out weak or noisy peaks."
                )
            } header: {
                Label("Settings", systemImage: "gearshape")
            }

            Section {
                helpRow(
                    title: "Multi-Tap Averaging",
                    body: "Set the tap count to 2 or more to average several taps together for a more stable result."
                )
                helpRow(
                    title: "Auto-Scale dB",
                    body: "The auto-scale button adjusts the magnitude axis to fit the current signal, making peaks easier to see."
                )
                helpRow(
                    title: "Calibration",
                    body: "Import a calibration file from a measurement microphone to correct for its frequency response and get more accurate results."
                )
            } header: {
                Label("Tips", systemImage: "lightbulb")
            }
        }
        .navigationTitle("Help")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func helpRow(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(body)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
