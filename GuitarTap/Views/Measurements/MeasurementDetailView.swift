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
        // On macOS in a separate window — the window's own close button
        // dismisses the view; no in-view Close control is needed.
        contentView
            .frame(minWidth: 600, minHeight: 500)
        #else
        // On iOS, NavigationLink provides the navigation context.  Keep
        // only the Done button as the cancellation action.
        contentView
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
                                        .foregroundColor(.secondary)
                                    Text(measurementName)
                                        .font(.body)
                                        .fontWeight(.medium)
                                }
                            }
                            
                            HStack {
                                Text("Date:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(DateDisplay.string(measurement.timestamp))
                                    .font(.body)
                            }
                            
                            HStack {
                                Text("Measurement Type:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(measurement.measurementTypeShortName)
                                    .font(.body)
                            }

                            if let taps = measurement.numberOfTaps {
                                HStack {
                                    Text("Number of Taps:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
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
                                        .foregroundColor(.secondary)
                                    Text(measurement.microphoneName ?? "unknown")
                                        .font(.body)
                                }
                            }

                            if let cal = measurement.calibrationName {
                                HStack {
                                    Text("Calibration:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(cal)
                                        .font(.body)
                                }
                            }

                            if let notes = measurement.notes, !notes.isEmpty {
                                Divider()
                                Text("Notes:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(notes)
                                    .font(.body)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Comparison records show the per-spectrum Air/Top/Back table; everything
                    // else shows the identified (selected) peaks only.
                    if let entries = measurement.comparisonEntries {
                        GroupBox("Compared Spectra (\(entries.count))") {
                            ComparisonResultsView(spectra: entries.map { entry in
                                let c = entry.colorComponents
                                let color = Color(
                                    red: c.indices.contains(0) ? c[0] : 0,
                                    green: c.indices.contains(1) ? c[1] : 0,
                                    blue: c.indices.contains(2) ? c[2] : 1,
                                    opacity: c.indices.contains(3) ? c[3] : 1
                                )
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
                    } else {
                        // Identified Peaks = the selected peaks only, sorted by frequency.
                        // Plate/brace skip guitar-mode classification.
                        let isMaterialMeasurement = measurement.longitudinalSnapshot != nil || measurement.selectedLongitudinalPeakID != nil
                        let selectedIDs = measurement.effectiveSelectedPeakIDs
                        let shownPeaks = measurement.peaks
                            .filter { selectedIDs.contains($0.id) }
                            .sorted(by: { $0.frequency < $1.frequency })
                        // Context-aware mode map so overlapping ranges (e.g. classical Top/Back) show distinct labels.
                        let modeMap: [UUID: GuitarMode] = isMaterialMeasurement ? [:] : GuitarMode.classifyAll(shownPeaks)

                        GroupBox("Identified Peaks") {
                            if shownPeaks.isEmpty {
                                Text("No identified peaks")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(shownPeaks) { peak in
                                        let mode = modeMap[peak.id] ?? .unknown
                                        let effectiveLabel: String = {
                                            if isMaterialMeasurement {
                                                if peak.id == measurement.selectedLongitudinalPeakID { return "Longitudinal" }
                                                if peak.id == measurement.selectedCrossPeakID { return "Cross-grain" }
                                                if peak.id == measurement.selectedFlcPeakID { return "Diagonal" }
                                                return "Peak"
                                            }
                                            return measurement.peakModeOverrides?[peak.id] ?? mode.displayName
                                        }()
                                        let isOverridden = !isMaterialMeasurement
                                            && measurement.peakModeOverrides?[peak.id] != nil
                                        CombinedPeakModeRowView(
                                            peak: peak,
                                            mode: mode,
                                            effectiveModeLabel: effectiveLabel,
                                            isManualOverride: isOverridden,
                                            isSelected: true
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
    }
}
