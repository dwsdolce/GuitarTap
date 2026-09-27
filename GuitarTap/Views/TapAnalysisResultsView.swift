//
//  TapAnalysisResultsView.swift
//  GuitarTap
//

/// # TapAnalysisResultsView
///
/// Scrollable results panel displaying tap tone analysis for the current
/// measurement. This view is presented as a sheet (iOS) or in a separate
/// `NSWindow` via `ResultsWindowPresenter` (macOS).
///
/// ## Content Sections
///
/// The body adapts to the active `MeasurementType`:
///
/// | Section | Guitar | Plate | Brace |
/// |---|---|---|---|
/// | Detected Peaks & Modes | ✓ | ✓ (unfiltered) | ✓ (unfiltered) |
/// | Ring-Out Time | ✓ | — | — |
/// | Tap Tone Ratio | ✓ | — | — |
/// | Plate Properties | — | ✓ | — |
/// | Brace Properties | — | — | ✓ |
/// | Status Indicator | ✓ | ✓ | ✓ |
/// | Export Buttons | optional | optional | optional |
///
/// ## Guitar Peak Table
///
/// `peaksAndModesSection` lists all `peaksAbovePeakMin` sorted by frequency.
/// Each row shows the guitar mode color chip, frequency, magnitude, Q-factor,
/// pitch note and cents deviation, and a mode-override picker. Unknown modes
/// can be hidden via `TapDisplaySettings.showUnknownModes`. Peaks are selected
/// individually — at most one may be the definitive Air, Top or Back — with
/// Select None and Reset to Auto in the section header.
///
/// ## Plate / Brace Properties
///
/// `platePropertiesSection` and `bracePropertiesSection` compute
/// `PlateProperties` / `BraceProperties` from the peak frequencies and the
/// current `MaterialDimensions`. Results are formatted with color-coded
/// quality indicators from `WoodQuality`.
///
/// ## Export
///
/// Optional `onExportSpectrum` and `onExportPDFReport` closures are provided
/// by `TapToneAnalysisView`. When non-nil they activate the corresponding
/// export buttons at the bottom of the scroll view.
///
/// - SeeAlso: `TapToneAnalysisView+Export`, `ResultsWindowPresenter`,
///   `PlateProperties`, `BraceProperties`

import SwiftUI
import Charts

/// Results panel presenting peaks, mode classifications, material properties,
/// and export controls for the most recently captured tap tone measurement.
///
/// - SeeAlso: `TapAnalysisResultsView` file overview for section details.
struct TapAnalysisResultsView: View {
    /// The tap-tone analyzer supplying peaks, decay time, and material data.
    @ObservedObject var analyzer: TapToneAnalyzer
    /// The FFT analyzer (read-only here; used for metrics display).
    @ObservedObject var fftAnalyzer: RealtimeFFTAnalyzer
    
    /// Lower bound of the displayed frequency range (Hz). Used to filter
    /// guitar peaks to the visible spectrum window.
    var minFreq: Float
    /// Upper bound of the displayed frequency range (Hz).
    var maxFreq: Float
    
    /// Called when the user taps "Export Spectrum". Pass `nil` to hide the button.
    var onExportSpectrum: (() -> Void)? = nil

    /// Called when the user taps "Export PDF Report". Pass `nil` to hide the button.
    var onExportPDFReport: (() -> Void)? = nil

    /// When true (the iPhone landscape side panel), hides the device-name row and the Ring-Out /
    /// Tap-Ratio summary so the peak list gets the full height. Default false → the iPad panel and
    /// the portrait sheet are unchanged.
    var compactLandscape: Bool = false

    /// Maximum width for instruction text blocks in plate/brace mode (macOS only).
    /// Provides a finite width inside the .fixedSize panel so text wraps rather than
    /// expanding the panel. Scales with the system font size. On iOS the sheet has
    /// unconstrained width so no cap is needed.
    #if os(macOS)
    @ScaledMetric(relativeTo: .caption2) private var instructionTextMaxWidth: CGFloat = 240
    #else
    private var instructionTextMaxWidth: CGFloat { .infinity }
    #endif
    
    // Current measurement type
    private var measurementType: MeasurementType {
        TapDisplaySettings.measurementType
    }
    
    /// Effective longitudinal peak ID — reads directly from the analyzer model
    private var effectiveLongitudinalPeakID: UUID? {
        analyzer.effectiveLongitudinalPeakID
    }
    
    /// Effective cross-grain peak ID — reads directly from the analyzer model
    private var effectiveCrossPeakID: UUID? {
        analyzer.effectiveCrossPeakID
    }
    
    /// Effective FLC peak ID — reads directly from the analyzer model
    private var effectiveFlcPeakID: UUID? {
        analyzer.effectiveFlcPeakID
    }
    
    /// Whether an FLC measurement was performed (its identified peak exists, live or loaded)
    private var hasFlcMeasurement: Bool {
        analyzer.selectedFlcPeak != nil
    }

    /// Whether this plate measurement includes (or will include) the FLC tap.
    /// During a live measurement in progress: reflects the `measureFlc` setting.
    /// After completion or when loaded: reflects actual measurement data.
    private var includesFlcTap: Bool {
        analyzer.isMeasurementComplete ? hasFlcMeasurement : TapDisplaySettings.measureFlc
    }
    
    var body: some View {
        ScrollViewReader { scrollProxy in
            VStack(alignment: .leading, spacing: 0) {
                // Fixed header
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Analysis Results")
                            .font(.headline)
                            .fontWeight(.bold)

                        Spacer()

                        // Multi-tap comparison toggle: shown only for completed guitar multi-tap sequences.
                        // Uses showingMultiTapComparison as the gate — NOT displayMode — because
                        // displayMode is set to .comparison when overlays are active so the chart renders them.
                        // Also suppressed during saved-measurement comparison (displayMode == .comparison &&
                        // !showingMultiTapComparison), where tapEntries belong to a loaded measurement
                        // and the chart is already showing the comparison overlays.
                        // Multi-tap toggle: shown whenever it could ever be useful (guitar
                        // context), enabled only when there's a completed >1-tap sequence to
                        // compare (or it's already open). Hidden in material / saved-measurement
                        // comparison, where it can never do anything — so it enables/disables in
                        // place instead of appearing and disappearing (all 3 platforms).
                        let inSavedComparison = analyzer.displayMode == .comparison
                            && !analyzer.showingMultiTapComparison
                        if measurementType.isGuitar && !inSavedComparison {
                            let multiTapUsable = (analyzer.isMeasurementComplete
                                && !analyzer.tapEntries.isEmpty)
                                || analyzer.showingMultiTapComparison
                            Button {
                                let show = !analyzer.showingMultiTapComparison
                                analyzer.showingMultiTapComparison = show
                                analyzer.applyMultiTapComparisonOverlays(enabled: show)
                            } label: {
                                Label("Taps", systemImage: analyzer.showingMultiTapComparison
                                      ? "waveform.path.badge.minus" : "waveform.path.badge.plus")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .tint(analyzer.showingMultiTapComparison ? .orange : .accentColor)
                            .disabled(!multiTapUsable)
                            .help(analyzer.showingMultiTapComparison
                                  ? "Show averaged result only" : "Compare individual taps")
                        }

                        // Show "Comparison" badge only for saved-measurement comparisons,
                        // not for the multi-tap comparison view (which is still a guitar measurement).
                        if analyzer.displayMode == .comparison && !analyzer.showingMultiTapComparison {
                            Text("Comparison")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.2))
                                .cornerRadius(4)
                        } else {
                            Text(measurementType.shortName)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(measurementType.isGuitar ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }

                    // Device name + Re-analyze — hidden in the compact landscape side panel so the
                    // peak list gets the full height (Re-analyze stays available in portrait / iPad).
                    if !compactLandscape {
                        HStack {
                            if let deviceName = fftAnalyzer.selectedInputDevice?.name {
                                Text(deviceName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            // Re-analyze: re-run findPeaks() on the frozen spectrum
                            // using the current analysis settings (Peak Min, analysis range, guitar
                            // type) — lets the user retune a saved measurement without re-tapping.
                            // Enabled exactly when the peaks on screen are NOT the auto-found peaks
                            // for the current settings — see TapToneAnalyzer.canReanalyze, which owns
                            // the rule so all three platforms answer it identically.
                            Button {
                                analyzer.reanalyzePeaks()
                            } label: {
                                Image(systemName: "arrow.trianglehead.2.counterclockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(!analyzer.canReanalyze)
                            .help("Re-analyze peaks from the spectrum using the current settings")
                        }
                    }

                    HStack {
                        Text("Showing \(minFreq.formattedAsFrequency()) - \(maxFreq.formattedAsFrequency())")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        // Select None / Reset to Auto buttons.
                        // Hidden during multi-tap comparison (the table shows per-tap data, not
                        // the averaged peak list, so individual peak selection is not applicable).
                        //
                        // There is deliberately no "Select All": Air, Top and Back can each have only
                        // ONE definitive (selected) peak, so selecting everything is not a state the
                        // model can hold. Select None remains — no definitive peaks is legitimate.
                        if !sortedPeaksWithModes.isEmpty && !analyzer.showingMultiTapComparison {
                            HStack(spacing: 8) {
                                Button {
                                    analyzer.selectNoPeaks()
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .disabled(!measurementType.isGuitar || analyzer.selectedPeakIDs.isEmpty)
                                .help(measurementType.isGuitar ? "Deselect all peaks" : "Peak selection is fixed during plate/brace measurements")

                                if measurementType.isGuitar {
                                    Button {
                                        analyzer.resetToAutoSelection()
                                    } label: {
                                        Image(systemName: "wand.and.stars")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .disabled(!analyzer.userHasModifiedPeakSelection)
                                    .help("Reset to automatic mode selection")
                                }


                            }
                        }
                    }
                }
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

                Divider()

                // Scrollable peaks list (plus plate/brace properties which can be long)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        peaksAndModesSection

                        // Plate/brace properties scroll with the peaks since they can be tall
                        if analyzer.displayMode != .comparison {
                            if measurementType == .plate && analyzer.isMeasurementComplete {
                                // Sample dimensions first — the measurement's own L/W/T/M, editable
                                // above the derived results; all plate calculations recompute from these.
                                Divider()
                                sampleDimensionsSection

                                // Body dimensions + panel stiffness (f_vs) — the Gore-only inputs, kept
                                // separate from the sample and shown just before the target they feed.
                                Divider()
                                plateBodyDimensionsSection

                                // Gore Target Thickness — the end result of the body inputs above
                                Divider()
                                goreThicknessSectionView

                                // Plate Properties and other calculations (GLC lives here, among the moduli)
                                Divider()
                                platePropertiesSection

                                // Process instructions at the end — reference only after measurement
                                Divider()
                                plateProcessInstructionsSection
                            } else if measurementType == .brace && analyzer.isMeasurementComplete {
                                // Sample dimensions first — editable inputs above the derived results.
                                Divider()
                                sampleDimensionsSection

                                Divider()
                                bracePropertiesSection

                                // Process instructions at the end
                                Divider()
                                braceProcessInstructionsSection
                            } else if measurementType == .plate {
                                // Live plate capture: Measurement Process always visible; the
                                // Plate Properties stay hidden until all phases are complete.
                                Divider()
                                plateProcessInstructionsSection
                            } else if measurementType == .brace {
                                // Live brace capture: Measurement Process always visible; brace
                                // Properties stay hidden until fL is captured.
                                Divider()
                                braceProcessInstructionsSection
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                #if os(macOS)
                .onChange(of: analyzer.highlightedPeakID) { _, newID in
                    if let id = newID {
                        withAnimation {
                            scrollProxy.scrollTo("peak-row-\(id)", anchor: .center)
                        }
                    }
                }
                #endif

                Divider()

                // Fixed footer: compact analysis summary + export buttons
                VStack(alignment: .leading, spacing: 8) {
                    // Guitar-specific compact summary (hidden during saved-measurement comparison
                    // or for plate/brace; shown during multi-tap comparison since it's still guitar).
                    if measurementType.isGuitar
                        && (analyzer.displayMode != .comparison || analyzer.showingMultiTapComparison) {
                        // Hidden in the compact landscape side panel — peaks get the full height.
                        if !compactLandscape {
                            guitarAnalysisSummary
                        }
                    }

                    // Status indicator + export buttons
                    if onExportSpectrum != nil || onExportPDFReport != nil {
                        HStack {
                            statusIndicator
                            Spacer()
                            if let exportSpectrum = onExportSpectrum {
                                Button {
                                    exportSpectrum()
                                } label: {
                                    Label("Export Spectrum", systemImage: "chart.line.uptrend.xyaxis")
                                        .fixedSize()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            if let exportPDF = onExportPDFReport {
                                Button {
                                    exportPDF()
                                } label: {
                                    Label("Export PDF", systemImage: "doc.richtext")
                                        .fixedSize()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    } else {
                        statusIndicator
                    }
                }
                .padding([.horizontal, .bottom])
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    /// Combined peaks with mode classifications, filtered to the current frequency range and sorted by frequency.
    /// Returns empty when a comparison overlay is active (peaks belong to the previous measurement, not the comparison).
    /// Optionally filters out unknown modes based on user setting (guitar mode only).
    ///
    /// Uses ``GuitarMode/classifyAll(_:guitarType:)`` for guitar measurements so that peaks
    /// in overlapping mode ranges (e.g. classical Top 170–230 Hz / Back 190–280 Hz) are
    /// assigned distinct modes rather than both being labeled "Top".
    private var sortedPeaksWithModes: [(peak: ResonantPeak, mode: GuitarMode)] {
        // Return empty during saved-measurement comparison, but NOT during multi-tap comparison
        // (where displayMode is also .comparison but the averaged peaks are still relevant).
        guard analyzer.displayMode != .comparison || analyzer.showingMultiTapComparison else { return [] }
        return analyzer.peaksAbovePeakMin
            .filter { peak in
                // For plate/brace mode, don't filter by display range — the selected peaks
                // must always appear in results regardless of the current zoom level.
                // For guitar mode, filter to the displayed frequency range.
                measurementType.isGuitar
                    ? (peak.frequency >= minFreq && peak.frequency <= maxFreq)
                    : true
            }
            .map { peak in
                // Use the analyzer's identifiedModes (computed via classifyAll) so that
                // overlapping ranges (e.g. classical Top/Back) show distinct labels.
                (peak: peak, mode: analyzer.peakMode(for: peak))
            }
            .filter { item in
                // Plate/brace show every peak. Guitar hides unknown-mode peaks unless the setting is
                // on — using the one shared predicate, so a peak the user has NAMED keeps its row
                // here exactly as it keeps its dot and its badge.
                !measurementType.isGuitar
                    || TapDisplaySettings.showUnknownModes
                    || !analyzer.isUnknown(item.peak)
            }
            .sorted { $0.peak.frequency < $1.peak.frequency }
    }
    
    // MARK: - Subviews

    /// Fixed per-phase slot rows (L, C, [FLC] for plate; fL for brace) shown during a LIVE
    /// material capture: the row layout matches the final display, but freq/mag show a dash
    /// until each phase's peak is captured, and each row's bubble is selected only once found.
    @ViewBuilder
    private var materialSlotRows: some View {
        let lPeak = analyzer.selectedLongitudinalPeak
        VStack(alignment: .leading, spacing: 12) {
            if measurementType == .brace {
                MaterialPeakRowView(peak: lPeak, isLongitudinal: lPeak != nil, isCross: false,
                                    showCrossButton: false, isSelected: lPeak != nil)
            } else {
                MaterialPeakRowView(peak: lPeak, isLongitudinal: lPeak != nil, isCross: false,
                                    showFlcButton: includesFlcTap, isSelected: lPeak != nil)
                let cPeak = analyzer.selectedCrossPeak
                MaterialPeakRowView(peak: cPeak, isLongitudinal: false, isCross: cPeak != nil,
                                    showFlcButton: includesFlcTap, isSelected: cPeak != nil)
                if includesFlcTap {
                    let flcPeak = analyzer.selectedFlcPeak
                    MaterialPeakRowView(peak: flcPeak, isLongitudinal: false, isCross: false,
                                        isFlc: flcPeak != nil, showFlcButton: true, isSelected: flcPeak != nil)
                }
            }
        }
    }

    /// The material results rows: the fixed per-phase slot rows during capture, then the identified
    /// L/C/FLC peaks (in frequency order) once the measurement is complete. The identified peaks are
    /// the measurement's peaks, so every one is marked selected.
    @ViewBuilder
    private var materialPeakRows: some View {
        if analyzer.isMeasurementComplete {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(analyzer.materialIdentifiedPeaks.sorted { $0.frequency < $1.frequency }, id: \.id) { peak in
                    MaterialPeakRowView(
                        peak: peak,
                        isLongitudinal: effectiveLongitudinalPeakID == peak.id,
                        isCross: effectiveCrossPeakID == peak.id,
                        isFlc: effectiveFlcPeakID == peak.id,
                        showCrossButton: measurementType == .plate,
                        showFlcButton: measurementType == .plate && includesFlcTap,
                        isSelected: true
                    )
                }
            }
        } else {
            materialSlotRows
        }
    }

    private var peaksAndModesSection: some View {
        GroupBox {
            // Multi-tap comparison view: shown when the toggle is active for a completed
            // guitar multi-tap sequence. Replaces the normal averaged peak list.
            // NOTE: displayMode may be .comparison here (needed for chart rendering) — we use
            // showingMultiTapComparison as the authoritative gate for the Results panel content.
            if analyzer.showingMultiTapComparison && !analyzer.tapEntries.isEmpty {
                MultiTapComparisonResultsView(
                    tapEntries: analyzer.tapEntries,
                    averagedModes: analyzer.definitiveModeInfo(),
                    guitarType: TapDisplaySettings.guitarType
                )
                .padding(.vertical, 4)
            } else if !measurementType.isGuitar && analyzer.displayMode != .comparison {
                // Material (plate/brace): the identified L/C/FLC are the peaks — fixed slot rows
                // during capture, then the identified peaks once complete.
                materialPeakRows
            } else if sortedPeaksWithModes.isEmpty {
                if analyzer.displayMode == .comparison {
                    ComparisonResultsView(spectra: analyzer.comparisonSpectra)
                        .padding(.vertical, 4)
                } else {
                    Text("No peaks detected in visible range")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sortedPeaksWithModes, id: \.peak.id) { item in
                        CombinedPeakModeRowView(
                            peak: item.peak,
                            mode: item.mode,
                            autoDetectedMode: analyzer.autoDetectedMode(for: item.peak),
                            effectiveModeLabel: analyzer.effectiveModeLabel(for: item.peak),
                            isManualOverride: analyzer.hasManualOverride(for: item.peak.id),
                            isSelected: analyzer.selectedPeakIDs.contains(item.peak.id),
                            onToggleSelection: {
                                analyzer.togglePeakSelection(item.peak.id)
                            },
                            onSetModeOverride: { label in
                                analyzer.setModeOverride(label, for: item.peak.id)
                            },
                            onResetModeOverride: {
                                analyzer.resetModeOverride(for: item.peak.id)
                            }
                        )
                        #if os(macOS)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(item.mode.color, lineWidth: analyzer.highlightedPeakID == item.peak.id ? 2 : 0)
                        )
                        .background(
                            analyzer.highlightedPeakID == item.peak.id
                                ? item.mode.color.opacity(0.12)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if analyzer.highlightedPeakID == item.peak.id {
                                analyzer.highlightedPeakID = nil
                            } else {
                                analyzer.highlightedPeakID = item.peak.id
                            }
                        }
                        #endif
                        .id("peak-row-\(item.peak.id)")
                    }
                }
            }
        }
    }
    
    /// Compact horizontal summary of ring-out time and tap tone ratio for the guitar footer.
    // @parity view/guitar-summary — Ring-Out + Tap-Ratio bar (Python: inline guitar-summary in
    // tap_tone_analysis_view; web: AnalysisResults.tsx). Quality logic in decayQuality / tapToneRatioQuality.
    private var guitarAnalysisSummary: some View {
        HStack(spacing: 12) {
            // Ring-out time
            VStack(alignment: .leading, spacing: 2) {
                Text("Ring-Out")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let decayTime = analyzer.currentDecayTime {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.2fs", decayTime))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(decayTime.decayQuality)
                            .font(.caption)
                            .foregroundColor(decayTime.decayQualityColor)
                    }
                    Text("–\(Int(analyzer.decayThreshold)) dB")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Waiting…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 36)

            // Tap tone ratio
            VStack(alignment: .leading, spacing: 2) {
                Text("Tap Ratio")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let ratio = analyzer.calculateTapToneRatio() {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.2f:1", ratio))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(ratio.tapToneRatioQuality)
                            .font(.caption)
                            .foregroundColor(ratio.tapToneRatioQualityColor)
                    }
                    Text("Ideal: 1.9–2.1")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Need Air & Top")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.07))
        .cornerRadius(8)
    }

    private var statusIndicator: some View {
        HStack {
            Circle()
                .fill(fftAnalyzer.isRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            Text(fftAnalyzer.isRunning ? "Analyzing" : "Stopped")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Plate Properties Section
    
    /// Computed plate properties based on selected peaks and dimensions
    private var calculatedPlateProperties: PlateProperties? {
        // The identified peaks, live or loaded.
        guard let longPeak = analyzer.selectedLongitudinalPeak,
              let crossPeak = analyzer.selectedCrossPeak else {
            return nil
        }
        let flcFreq: Float? = analyzer.selectedFlcPeak?.frequency

        // Store B — the measurement's own dimensions, never the live Settings defaults.
        guard let inputs = analyzer.materialInputs else { return nil }
        return PlateProperties(
            dimensions: inputs.dimensions,
            fundamentalFrequencyLong: longPeak.frequency,
            fundamentalFrequencyCross: crossPeak.frequency,
            fundamentalFrequencyFlc: flcFreq
        )
    }
    
    // @parity view/material-results
    private var platePropertiesSection: some View {
        GroupBox("Plate Properties") {
            if let props = calculatedPlateProperties {
                VStack(alignment: .leading, spacing: 16) {
                    // Speed of Sound
                    // (fL / fC / fLC are inputs, shown in the peak list above — not repeated here.)
                    propertyRow(
                        title: "Speed of Sound",
                        longValue: String(format: "%.0f m/s", props.speedOfSoundLong),
                        crossValue: String(format: "%.0f m/s", props.speedOfSoundCross)
                    )
                    
                    // Young's Modulus (E_L and E_C) plus shear modulus GLC if available
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Young's Modulus (E)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        HStack {
                            Text("L: \(String(format: "%.2f GPa", props.youngsModulusLongGPa))")
                                .font(.caption)
                            Spacer()
                            Text("C: \(String(format: "%.2f GPa", props.youngsModulusCrossGPa))")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                        if let glc = props.goreShearModulus {
                            HStack {
                                Text("GLC (Shear): \(String(format: "%.3f GPa", glc / 1.0e9))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    }
                    
                    // Specific Modulus (E/ρ) - the key metric
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Specific Modulus (E/ρ)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Longitudinal:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(String(format: "%.1f", props.specificModulusLong))
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(props.spruceQualityLong.color)
                                    Text("GPa/(g/cm³)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(props.spruceQualityLong.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(props.spruceQualityLong.color)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Cross-grain:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(String(format: "%.1f", props.specificModulusCross))
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(props.spruceQualityCross.color)
                                    Text("GPa/(g/cm³)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(props.spruceQualityCross.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(props.spruceQualityCross.color)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Radiation Ratio
                    propertyRow(
                        title: "Radiation Ratio (R)",
                        longValue: String(format: "%.1f", props.radiationRatioLong),
                        crossValue: String(format: "%.1f", props.radiationRatioCross)
                    )
                    
                    // Cross/Long Ratio
                    HStack {
                        Text("Cross/Long Ratio:")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.3f", props.crossLongRatio))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("(typical: 0.04–0.08)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Long/Cross Ratio
                    HStack {
                        Text("Long/Cross Ratio:")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1f", props.longCrossRatio))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("(typical: 12–25)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Overall Quality Assessment
                    HStack {
                        Text("Overall Quality:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text(props.overallQuality.rawValue)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(props.overallQuality.color)
                    }
                    .padding(.vertical, 4)

                }
            } else {
                VStack(spacing: 12) {
                    if effectiveLongitudinalPeakID == nil && effectiveCrossPeakID == nil {
                        Text("Select peaks above to calculate properties")
                            .foregroundColor(.secondary)
                    } else if effectiveLongitudinalPeakID == nil {
                        Text("Select a longitudinal (L) peak")
                            .foregroundColor(.orange)
                    } else {
                        Text("Select a cross-grain (C) peak")
                            .foregroundColor(.orange)
                    }
                    
                    Text("Tip: The longitudinal mode is typically the higher frequency peak")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }
    
    // MARK: - Gore Thickness Section (standalone, shown immediately after peaks)

    /// Gore Target Thickness as a standalone section, shown immediately after the peak list.
    @ViewBuilder
    private var goreThicknessSectionView: some View {
        if let props = calculatedPlateProperties {
            GroupBox("Gore Target Thickness") {
                goreThicknessView(for: props)
            }
        }
    }

    /// Binding to the completed measurement's own inputs (Store B). Falls back to the Settings
    /// defaults only if `materialInputs` is somehow nil (the sections gate on non-nil before use).
    private var materialInputsBinding: Binding<MaterialMeasurementInputs> {
        Binding(
            get: { analyzer.materialInputs ?? .fromSettings(for: TapDisplaySettings.measurementType) },
            set: { analyzer.materialInputs = $0 }
        )
    }

    /// Editable sample dimensions (Store B) — the measurement's own L/W/T/M, shown as its own section
    /// BEFORE the derived-property sections for both plate and brace (inputs above results). Editing
    /// writes `materialInputs` live so every calculation recomputes; it never touches the Settings
    /// defaults.
    @ViewBuilder
    private var sampleDimensionsSection: some View {
        if analyzer.materialInputs != nil {
            GroupBox("Sample Dimensions") {
                MaterialDimensionsEditor(inputs: materialInputsBinding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        }
    }

    /// Editable Gore body settings (Store B) for a completed plate — the finished-guitar body
    /// dimensions (a, b) and panel stiffness (f_vs). Kept separate from the sample dimensions and
    /// shown just before the Gore Target Thickness they feed. Editing recomputes only the Gore target.
    @ViewBuilder
    private var plateBodyDimensionsSection: some View {
        if analyzer.materialInputs != nil {
            GroupBox("Body Dimensions") {
                PlateBodyDimensionsEditor(inputs: materialInputsBinding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Brace Properties Section
    
    /// Computed brace properties based on the selected fL peak and dimensions
    private var calculatedBraceProperties: BraceProperties? {
        guard let longPeak = analyzer.selectedLongitudinalPeak else {
            return nil
        }
        
        // Store B — the measurement's own dimensions, never the live Settings defaults.
        guard let inputs = analyzer.materialInputs else { return nil }
        return BraceProperties(
            dimensions: inputs.dimensions,
            fundamentalFrequencyLong: longPeak.frequency
        )
    }
    
    private var bracePropertiesSection: some View {
        GroupBox("Brace Properties") {
            if let props = calculatedBraceProperties {
                VStack(alignment: .leading, spacing: 16) {
                    // Speed of Sound
                    // (fL is an input, shown in the peak list above — not repeated here.)
                    HStack {
                        Text("Speed of Sound:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text(String(format: "%.0f m/s", props.speedOfSoundLong))
                            .font(.subheadline)
                    }
                    
                    // Young's Modulus
                    HStack {
                        Text("Young's Modulus (E):")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text(String(format: "%.2f GPa", props.youngsModulusLongGPa))
                            .font(.subheadline)
                    }
                    
                    // Specific Modulus — highlighted as the key metric
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Specific Modulus (E/ρ)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.1f", props.specificModulusLong))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(props.spruceQuality.color)
                            Text("GPa/(g/cm³)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(props.spruceQuality.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(props.spruceQuality.color)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Radiation Ratio
                    HStack {
                        Text("Radiation Ratio (R):")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text(String(format: "%.1f", props.radiationRatioLong))
                            .font(.subheadline)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Text("Select the fL (L) peak above to calculate properties")
                        .foregroundColor(.secondary)
                    Text("Tip: The dominant peak is auto-selected after tapping")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }
    
    // MARK: - Gore Thickness View

    /// Displays the Gore target thickness result — just the number. The inputs that feed it (body
    /// dimensions + f_vs) live in the Body Dimensions section above, and GLC is shown among the plate
    /// moduli in Plate Properties, so this box is deliberately compact: it's only the end result.
    @ViewBuilder
    private func goreThicknessView(for props: PlateProperties) -> some View {
        // Store B — the measurement's own Gore inputs (body dims + f_vs), never the live Settings.
        let inputs     = analyzer.materialInputs
        let bodyLength = inputs?.bodyLengthMM ?? TapDisplaySettings.guitarBodyLength
        let bodyWidth  = inputs?.bodyWidthMM ?? TapDisplaySettings.guitarBodyWidth
        let fvs        = inputs?.stiffness ?? TapDisplaySettings.plateStiffness

        if let hd = props.goreTargetThickness(
            bodyLengthMm: bodyLength,
            bodyWidthMm: bodyWidth,
            vibrationalStiffness: fvs) {

            // Prominent thickness result — the sole content of this box.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.2f", hd))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.accentColor)
                Text("mm")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color.accentColor.opacity(0.08))
            .cornerRadius(8)
        }
    }

    // MARK: - Measurement Process Instructions

    /// Plate tap instructions content — shared between inline (in-progress) and
    /// end-of-scroll (post-completion) placements.
    @ViewBuilder
    private var plateMeasurementInstructions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .padding(.vertical, 4)

            Text(includesFlcTap ? "Three-Tap Measurement Process:" : "Two-Tap Measurement Process:")
                .font(.caption)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("**1. Longitudinal (fL) Tap**")
                            .font(.caption2)
                        Text("Hold plate at 22% from one end along the length, near one long edge (not at the width node). Tap center.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: instructionTextMaxWidth, alignment: .leading)
                }

                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("**2. Cross-grain (fC) Tap**")
                            .font(.caption2)
                        Text("Rotate 90°. Hold plate at 22% from one end along the width, near one short edge (not at the length node). Tap center.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: instructionTextMaxWidth, alignment: .leading)
                }

                if includesFlcTap {
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 8, height: 8)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("**3. Diagonal (fLC) Tap**")
                                .font(.caption2)
                            Text("Hold plate at the midpoint of one long edge. Tap near the opposite corner (~22% from both the end and the side). Measures shear stiffness.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: instructionTextMaxWidth, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: instructionTextMaxWidth)

            Text("The strongest peak from each tap is auto-selected. Redo if needed.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .italic()
                .frame(maxWidth: instructionTextMaxWidth, alignment: .leading)
                .padding(.top, 2)
        }
        .frame(maxWidth: instructionTextMaxWidth)
        .padding(.top, 4)
    }

    /// Brace tap instructions content — shared between inline and end-of-scroll placements.
    @ViewBuilder
    private var braceMeasurementInstructions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .padding(.vertical, 4)

            Text("Single-Tap Measurement (fL only):")
                .font(.caption)
                .fontWeight(.semibold)

            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("**1. Longitudinal (fL) Tap**")
                        .font(.caption2)
                    Text("Hold brace at 22% from one end along the length. Tap center.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: instructionTextMaxWidth, alignment: .leading)
            }

            Text("The strongest peak is auto-selected. Redo if needed.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .italic()
                .frame(maxWidth: instructionTextMaxWidth, alignment: .leading)
                .padding(.top, 2)
        }
        .frame(maxWidth: instructionTextMaxWidth)
        .padding(.top, 4)
    }

    /// Process instructions shown at the end of the scroll view after a plate measurement is complete.
    private var plateProcessInstructionsSection: some View {
        GroupBox("Measurement Process") {
            plateMeasurementInstructions
        }
    }

    /// Process instructions shown at the end of the scroll view after a brace measurement is complete.
    private var braceProcessInstructionsSection: some View {
        GroupBox("Measurement Process") {
            braceMeasurementInstructions
        }
    }

    // MARK: - Helper Views

    private func propertyRow(title: String, longValue: String, crossValue: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            HStack {
                Text("L: \(longValue)")
                    .font(.caption)
                Spacer()
                Text("C: \(crossValue)")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
    }
    

}

// MARK: - Plate/Brace Peak Row View

/// A single row in the plate/brace peak list.
///
/// The L/C/FLC badges are display-only indicators of which peak was auto-identified
/// for each phase. They are not interactive — if the wrong peak was identified,
/// the user should press Redo to re-capture that phase.
struct MaterialPeakRowView: View {
    /// The captured peak for this slot, or `nil` for an as-yet-uncaptured phase (renders dashes).
    let peak: ResonantPeak?
    let isLongitudinal: Bool
    let isCross: Bool
    var isFlc: Bool = false
    var showCrossButton: Bool = true
    var showFlcButton: Bool = false
    var isSelected: Bool = true
    var onToggleSelection: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Selection toggle — interactive in guitar mode, informational in plate/brace.
            if let toggleAction = onToggleSelection {
                Button {
                    toggleAction()
                } label: {
                    Image(systemName: isSelected ? "star.fill" : "star")
                        .foregroundColor(isSelected ? .blue : .secondary)
                        .font(.body)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(isSelected ? "Deselect peak" : "Select peak")
            } else {
                Image(systemName: isSelected ? "star.fill" : "star")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.body)
                    .frame(width: 24, height: 24)
            }

            // Frequency and magnitude — dashes until this phase's peak is captured.
            VStack(alignment: .leading, spacing: 2) {
                Text(peak.map { $0.frequency.formattedAsFrequency() } ?? "—")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(peak == nil ? .secondary : .primary)

                Text(peak.map { String(format: "%.1f dB", Double($0.magnitude)) } ?? "—")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Phase identification badges — display only, not interactive.
            // Colored when this peak was auto-identified for that phase.
            HStack(spacing: 8) {
                phaseBadge("fL", active: isLongitudinal, color: .blue, width: 36)

                if showCrossButton {
                    phaseBadge("fC", active: isCross, color: .orange, width: 36)
                }

                if showFlcButton {
                    phaseBadge("fLC", active: isFlc, color: .purple, width: 42)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func phaseBadge(_ label: String, active: Bool, color: Color, width: CGFloat) -> some View {
        Text(label)
            .font(label.count <= 1 ? .headline : .subheadline)
            .fontWeight(.bold)
            .frame(width: width, height: 36)
            .background(active ? color : Color.secondary.opacity(0.2))
            .foregroundColor(active ? .white : .primary)
            .cornerRadius(8)
    }
}
