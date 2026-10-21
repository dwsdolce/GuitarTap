//
//  MeasurementDetailView.swift
//  GuitarTap
//
// @parity view/measurement-detail

/// # MeasurementDetailView
///
/// Detail panel for a single saved `TapToneMeasurement`. Read-only: Load, Edit, Export and the PDF
/// report are on the measurement row's menu in `MeasurementsListView`.
///
/// ## Platform Differences
///
/// - **macOS**: Rendered bare (`contentView` without a `NavigationView`),
///   presented in a dedicated `NSWindowController` opened from
///   `MeasurementsListView`.
/// - **iOS**: Wrapped in a `NavigationView`.
///
/// - SeeAlso: `MeasurementsListView`

import SwiftUI

struct MeasurementDetailView: View {
    let index: Int
    @State var measurement: TapToneMeasurement
    @ObservedObject var analyzer: TapToneAnalyzer
    @Environment(\.dismiss) var dismiss
    @State private var chartImage: Image?
    @State private var showingEdit = false
    
    var body: some View {
        // The detail view is read-only.  Load / Edit / Export / PDF Report
        // are all reachable from the popup menu on the row in the
        // Measurements list (MeasurementsListView), so no duplicate
        // controls are presented here.
        #if os(macOS)
        // On macOS in a separate window. A Done at the bottom right closes it, as every form has — the
        // platform's button, as a dialog's are; it only closes, so it is not the default. Esc does the same.
        contentView
            .frame(minWidth: 600, minHeight: 500)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    PaletteDivider()
                    HStack {
                        Spacer()
                        Button("Done") { NSApp.keyWindow?.performClose(nil) }
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .background(Palette.color(.backgroundPanel))
            }
            .paletteSurface(.backgroundWindow)
        #else
        // On iOS, NavigationLink provides the navigation context.  Keep
        // only the Done button as the cancellation action.
        contentView
            .paletteSurface(.backgroundWindow)
            .navigationTitle("Measurement Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        #endif
    }
    
    /// Single Settings-vocabulary type word for the Details pane:
    /// Acoustic / Classical / Flamenco / Generic / Plate / Brace / Comparison.
    @ViewBuilder
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Info
                GroupBox("Measurement Info") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let measurementName = measurement.measurementName {
                                HStack {
                                    Text("Measurement Name:")
                                        .font(.caption)
                                        .foregroundColor(Palette.color(.textSecondary))
                                    Text(measurementName)
                                        .font(.body)
                                        .fontWeight(.medium)
                                }
                            }
                            
                            HStack {
                                Text("Date:")
                                    .font(.caption)
                                    .foregroundColor(Palette.color(.textSecondary))
                                Text(DateDisplay.string(measurement.timestamp))
                                    .font(.body)
                            }
                            
                            HStack {
                                Text("Measurement Type:")
                                    .font(.caption)
                                    .foregroundColor(Palette.color(.textSecondary))
                                Text(measurement.measurementTypeShortName)
                                    .font(.body)
                            }

                            if let taps = measurement.numberOfTaps {
                                HStack {
                                    Text("Number of Taps:")
                                        .font(.caption)
                                        .foregroundColor(Palette.color(.textSecondary))
                                    Text("\(taps)")
                                        .font(.body)
                                }
                            }

                            // No recorded microphone means it is unknown (a played file, say). A comparison
                            // has no microphone of its own.
                            if !measurement.isComparison {
                                HStack {
                                    Text("Microphone:")
                                        .font(.caption)
                                        .foregroundColor(Palette.color(.textSecondary))
                                    Text(measurement.microphoneName ?? "unknown")
                                        .font(.body)
                                }
                            }

                            if let cal = measurement.calibrationName {
                                HStack {
                                    Text("Calibration:")
                                        .font(.caption)
                                        .foregroundColor(Palette.color(.textSecondary))
                                    Text(cal)
                                        .font(.body)
                                }
                            }

                            if let notes = measurement.notes, !notes.isEmpty {
                                PaletteDivider()
                                Text("Notes:")
                                    .font(.caption)
                                    .foregroundColor(Palette.color(.textSecondary))
                                Text(notes)
                                    .font(.body)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                .groupBoxStyle(.palette)
                    
                    // Comparison records show the per-spectrum Air/Top/Back table; everything
                    // else shows the identified (selected) peaks only.
                    if let entries = measurement.comparisonEntries {
                        GroupBox("Compared Spectra (\(entries.count))") {
                            ComparisonResultsView(spectra: entries.enumerated().map { index, entry in
                                let color = Palette.comparisonColor(index: index, label: entry.label)
                                return (magnitudes: entry.snapshot.magnitudes,
                                        frequencies: entry.snapshot.frequencies,
                                        color: color,
                                        label: entry.label,
                                        peaks: entry.peaks,
                                        guitarType: entry.guitarType,
                                        modeIDs: entry.modePeakIDs ?? [:])
                            })
                            .padding(.vertical, 4)
                        }
                        .groupBoxStyle(.palette)
                    } else {
                        // Identified Peaks = the selected peaks only, sorted by frequency.
                        // Plate/brace skip guitar-mode classification.
                        let isMaterialMeasurement = measurement.isMaterial
                        let selectedIDs = measurement.effectiveSelectedPeakIDs
                        let shownPeaks = measurement.peaks
                            .filter { selectedIDs.contains($0.id) }
                            .sorted(by: { $0.frequency < $1.frequency })
                        // The measurement's own modes and labels — classified among all its peaks, as
                        // the file is written and the live view showed them, not among the shown ones.
                        let modeMap = measurement.autoModes
                        let labels = measurement.peakModeLabels

                        GroupBox("Identified Peaks") {
                            if shownPeaks.isEmpty {
                                Text("No identified peaks")
                                    .foregroundColor(Palette.color(.textSecondary))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(shownPeaks) { peak in
                                        let mode = modeMap[peak.id] ?? .unknown
                                        let materialRole: MaterialPeakRole? = {
                                            guard isMaterialMeasurement else { return nil }
                                            if peak.id == measurement.selectedLongitudinalPeakID { return .longitudinal }
                                            if peak.id == measurement.selectedCrossPeakID { return .cross }
                                            if peak.id == measurement.selectedFlcPeakID { return .flc }
                                            return nil
                                        }()
                                        let effectiveLabel = labels[peak.id] ?? mode.displayName
                                        let isOverridden = !isMaterialMeasurement
                                            && measurement.peakModeOverrides?[peak.id] != nil
                                        CombinedPeakModeRowView(
                                            peak: peak,
                                            mode: mode,
                                            effectiveModeLabel: effectiveLabel,
                                            isManualOverride: isOverridden,
                                            isSelected: true,
                                            materialRole: materialRole
                                        )
                                    }
                                }
                            }
                        }
                        .groupBoxStyle(.palette)
                    }
                }
                .padding()
            }
    }
}
