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
    /// The FFT analyzer. Not observed here: it publishes on every frame, and this view (its rows and their menus) must not be
    /// redrawn that often. Only `AnalyzerRunningIndicator` watches it.
    let fftAnalyzer: RealtimeFFTAnalyzer
    
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

    /// The width the plate/brace instruction block asks for when the macOS panel sizes itself
    /// (the panel is `.fixedSize`, so it takes its content's ideal width). Asking for only this
    /// much keeps the instructions from widening the panel; once the panel's width is set, the
    /// block fills its box and the text wraps at the box's edge. Scales with the system font size.
    /// On iOS the sheet's width is not set by its content, so no ideal width is needed.
    #if os(macOS)
    @ScaledMetric(relativeTo: .caption2) private var instructionIdealWidthMac: CGFloat = 240
    private var instructionIdealWidth: CGFloat? { instructionIdealWidthMac }
    #else
    private var instructionIdealWidth: CGFloat? { nil }
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
    
    /// Built inside a ``PeaksReader``, so the detected peaks redraw the panel. Behind `AnyView`, which ends the
    /// panel's type there, so the main view's type stays shallow enough to decode on an iPhone's stack.
    var body: some View {
        PeaksReader(peaks: analyzer.peaks) { _ in AnyView(content) }
    }

    private var content: some View {
        ScrollViewReader { scrollProxy in
            VStack(alignment: .leading, spacing: 0) {
                // Fixed header
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Analysis Results")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(Palette.color(.textPrimary))

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
                            Toggle(isOn: Binding(
                                get: { analyzer.showingMultiTapComparison },
                                set: { show in
                                    analyzer.applyMultiTapComparisonOverlays(enabled: show)
                                })
                            ) {
                                Label("Taps", systemImage: analyzer.showingMultiTapComparison
                                      ? "waveform.path.badge.minus" : "waveform.path.badge.plus")
                                    .font(.caption)
                            }
                            .toggleStyle(.tinted(analyzer.showingMultiTapComparison ? .resultsTapsActive : .accent))
                            .controlSize(.mini)
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
                                .background(Palette.color(.badgeComparison))
                                .cornerRadius(4)
                        } else {
                            Text(measurementType.shortName)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Palette.color(measurementType.isGuitar ? .badgeGuitar : .badgeMaterial))
                                .cornerRadius(4)
                        }
                    }

                    // Device name + Re-analyze — hidden in the compact landscape side panel so the
                    // peak list gets the full height (Re-analyze stays available in portrait / iPad).
                    if !compactLandscape {
                        HStack {
                            // The microphone the result was captured with: the input for a live result,
                            // the recorded one — or "unknown" — for a played file or a loaded measurement.
                            // None for a comparison: it has no microphone of its own.
                            if !analyzer.isSavedMeasurementComparison,
                               let deviceName = analyzer.captureMicrophoneName
                                ?? (analyzer.resultProvenance != nil ? "unknown" : nil) {
                                Text(deviceName)
                                    .font(.caption)
                                    .foregroundColor(Palette.color(.textSecondary))
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
                            .buttonStyle(.tinted(.textSecondary))
                            .controlSize(.mini)
                            .disabled(!analyzer.canReanalyze)
                            .help("Re-analyze peaks from the spectrum using the current settings")
                        }
                    }

                    HStack {
                        Text(displayRangeLabel(minFreq: minFreq, maxFreq: maxFreq))
                            .font(.caption)
                            .foregroundColor(Palette.color(.textSecondary))

                        Spacer()

                        // Select None / Reset to Auto buttons.
                        // Hidden during multi-tap comparison (the table shows per-tap data, not
                        // the averaged peak list, so individual peak selection is not applicable).
                        //
                        // There is deliberately no "Select All": Air, Top and Back can each have only
                        // ONE definitive (selected) peak, so selecting everything is not a state the
                        // model can hold. Select None remains — no definitive peaks is legitimate.
                        // Never for a plate or brace, where peak selection has no purpose.
                        if measurementType.isGuitar && !sortedPeaksWithModes.isEmpty
                            && !analyzer.showingMultiTapComparison {
                            HStack(spacing: 8) {
                                Button {
                                    analyzer.selectNoPeaks()
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .font(.caption)
                                }
                                .buttonStyle(.tinted(.textSecondary))
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
                                    .buttonStyle(.tinted(.textSecondary))
                                    .controlSize(.mini)
                                    .disabled(!analyzer.userHasModifiedPeakSelection)
                                    .help("Reset to automatic mode selection")
                                }


                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)

                headerFooterDivider

                // What is not an item stays fixed above the list: a comparison table's heading, or the
                // empty list's message.
                fixedAboveList

                // Scrollable peaks list (plus plate/brace properties which can be long)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        peaksAndModesSection

                        // Plate/brace properties scroll with the peaks since they can be tall
                        if analyzer.displayMode != .comparison {
                            if measurementType == .plate && analyzer.isMeasurementComplete {
                                // Sample dimensions first — the measurement's own L/W/T/M, editable
                                // above the derived results; all plate calculations recompute from these.
                                sectionDivider
                                sampleDimensionsSection

                                // Body dimensions + panel stiffness (f_vs) — the Gore-only inputs, kept
                                // separate from the sample and shown just before the target they feed.
                                sectionDivider
                                plateBodyDimensionsSection

                                // Gore Target Thickness — the end result of the body inputs above
                                sectionDivider
                                goreThicknessSectionView

                                // Plate Properties and other calculations (GLC lives here, among the moduli)
                                sectionDivider
                                platePropertiesSection

                                // Process instructions at the end — reference only after measurement
                                sectionDivider
                                plateProcessInstructionsSection
                            } else if measurementType == .brace && analyzer.isMeasurementComplete {
                                // Sample dimensions first — editable inputs above the derived results.
                                sectionDivider
                                sampleDimensionsSection

                                sectionDivider
                                bracePropertiesSection

                                // Process instructions at the end
                                sectionDivider
                                braceProcessInstructionsSection
                            } else if measurementType == .plate {
                                // Live plate capture: Measurement Process always visible; the
                                // Plate Properties stay hidden until all phases are complete.
                                sectionDivider
                                plateProcessInstructionsSection
                            } else if measurementType == .brace {
                                // Live brace capture: Measurement Process always visible; brace
                                // Properties stay hidden until fL is captured.
                                sectionDivider
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

                headerFooterDivider

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
                                .buttonStyle(.appPlain)
                                .controlSize(.small)
                                .disabled(!analyzer.hasResultToSaveOrExport)
                            }
                            if let exportPDF = onExportPDFReport {
                                Button {
                                    exportPDF()
                                } label: {
                                    Label("Export PDF", systemImage: "doc.richtext")
                                        .fixedSize()
                                }
                                .buttonStyle(.appPlain)
                                .controlSize(.small)
                                .disabled(!analyzer.hasResultToSaveOrExport)
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
        VStack(alignment: .leading, spacing: 4) {
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
            VStack(alignment: .leading, spacing: 4) {
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

    /// The part of the peaks list that is not an item, fixed above it: the heading of the table of taps or of
    /// compared spectra, or the message an empty list shows. The same cases as ``peaksAndModesSection``.
    @ViewBuilder
    private var fixedAboveList: some View {
        if analyzer.showingMultiTapComparison && !analyzer.tapEntries.isEmpty {
            MultiTapComparisonResultsView(
                tapEntries: analyzer.tapEntries,
                averagedModes: analyzer.definitiveModeInfo(),
                guitarType: TapDisplaySettings.guitarType,
                part: .heading
            )
            .padding(.horizontal)
            .padding(.top, 8)
        } else if !measurementType.isGuitar && analyzer.displayMode != .comparison {
            EmptyView()
        } else if sortedPeaksWithModes.isEmpty {
            if analyzer.displayMode == .comparison {
                ComparisonResultsView(spectra: analyzer.comparisonSpectra, part: .heading)
                    .padding(.horizontal)
                    .padding(.top, 8)
            } else {
                Text("No peaks detected in visible range")
                    .foregroundColor(Palette.color(.textSecondary))
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }

    private var peaksAndModesSection: some View {
        // No box: the rows carry their own tints, as in the other editions.
        VStack(alignment: .leading, spacing: 0) {
            // Multi-tap comparison view: shown when the toggle is active for a completed
            // guitar multi-tap sequence. Replaces the normal averaged peak list.
            // NOTE: displayMode may be .comparison here (needed for chart rendering) — we use
            // showingMultiTapComparison as the authoritative gate for the Results panel content.
            if analyzer.showingMultiTapComparison && !analyzer.tapEntries.isEmpty {
                MultiTapComparisonResultsView(
                    tapEntries: analyzer.tapEntries,
                    averagedModes: analyzer.definitiveModeInfo(),
                    guitarType: TapDisplaySettings.guitarType,
                    part: .rows
                )
                .padding(.bottom, 4)
            } else if !measurementType.isGuitar && analyzer.displayMode != .comparison {
                // Material (plate/brace): the identified L/C/FLC are the peaks — fixed slot rows
                // during capture, then the identified peaks once complete.
                materialPeakRows
            } else if sortedPeaksWithModes.isEmpty {
                // The heading, or the empty list's message, is fixed above the list (`fixedAboveList`).
                if analyzer.displayMode == .comparison {
                    ComparisonResultsView(spectra: analyzer.comparisonSpectra, part: .rows)
                        .padding(.bottom, 4)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
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
                                .strokeBorder(Palette.color(item.mode), lineWidth: analyzer.highlightedPeakID == item.peak.id ? 2 : 0)
                        )
                        .background(
                            analyzer.highlightedPeakID == item.peak.id
                                ? Palette.color(item.mode).opacity(Palette.opacity(.peakRowHighlight))
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
                    .foregroundColor(Palette.color(.textSecondary))
                if let decayTime = analyzer.currentDecayTime {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(FieldPrecision.string(decayTime, FieldPrecision.decayTimeS))s")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(Palette.color(.textPrimary))
                        Text(decayTime.decayQuality)
                            .font(.caption)
                            .foregroundColor(decayTime.decayQualityColor)
                    }
                    Text("–\(Int(analyzer.decayThreshold)) dB")
                        .font(.caption2)
                        .foregroundColor(Palette.color(.textSecondary))
                } else {
                    Text("Waiting…")
                        .font(.caption)
                        .foregroundColor(Palette.color(.textSecondary))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PaletteDivider()
                .frame(height: 36)

            // Tap tone ratio
            VStack(alignment: .leading, spacing: 2) {
                Text("Tap Ratio")
                    .font(.caption2)
                    .foregroundColor(Palette.color(.textSecondary))
                if let ratio = analyzer.calculateTapToneRatio() {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(FieldPrecision.string(ratio, FieldPrecision.decayRatio)):1")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(Palette.color(.textPrimary))
                        Text(ratio.tapToneRatioQuality)
                            .font(.caption)
                            .foregroundColor(ratio.tapToneRatioQualityColor)
                    }
                    Text("Ideal: 1.9–2.1")
                        .font(.caption2)
                        .foregroundColor(Palette.color(.textSecondary))
                } else {
                    Text("Need Air & Top")
                        .font(.caption)
                        .foregroundColor(Palette.color(.textSecondary))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Palette.color(.backgroundSubtle))
        .cornerRadius(8)
    }

    private var statusIndicator: some View {
        AnalyzerRunningIndicator(fftAnalyzer: fftAnalyzer)
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
    /// The plate's properties, once it has its peaks and dimensions — which a completed plate always has.
    @ViewBuilder
    private var platePropertiesSection: some View {
        if let props = calculatedPlateProperties {
            materialSection("Plate Properties") {
                VStack(alignment: .leading, spacing: 6) {
                    // Speed of Sound
                    // (fL / fC / fLC are inputs, shown in the peak list above — not repeated here.)
                    propertyRow(
                        title: "Speed of Sound",
                        longValue: "\(FieldPrecision.string(props.speedOfSoundLong, FieldPrecision.speedOfSoundMS)) m/s",
                        crossValue: "\(FieldPrecision.string(props.speedOfSoundCross, FieldPrecision.speedOfSoundMS)) m/s"
                    )
                    
                    // Young's Modulus (E_L and E_C) plus shear modulus GLC if available
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Young's Modulus (E)")
                            .font(MaterialType.bodyBold)
                        HStack {
                            Text("L: \(FieldPrecision.string(props.youngsModulusLongGPa, FieldPrecision.youngsModulusGPa)) GPa")
                                .font(MaterialType.body)
                            Spacer()
                            Text("C: \(FieldPrecision.string(props.youngsModulusCrossGPa, FieldPrecision.youngsModulusGPa)) GPa")
                                .font(MaterialType.body)
                        }
                        .foregroundColor(Palette.color(.textSecondary))
                        if let glc = props.goreShearModulus {
                            HStack {
                                Text("GLC (Shear): \(FieldPrecision.string(glc / 1.0e9, FieldPrecision.shearModulusGPa)) GPa")
                                    .font(MaterialType.body)
                                    .foregroundColor(Palette.color(.textSecondary))
                                Spacer()
                            }
                        }
                    }
                    
                    // Specific Modulus (E/ρ) - the key metric
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Specific Modulus (E/ρ)")
                            .font(MaterialType.bodyBold)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Longitudinal:")
                                    .font(MaterialType.body)
                                    .foregroundColor(Palette.color(.textSecondary))
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(FieldPrecision.string(props.specificModulusLong, FieldPrecision.specificModulus))
                                        .font(MaterialType.value)
                                        .fontWeight(.bold)
                                        .foregroundColor(Palette.color(props.spruceQualityLong))
                                    Text("GPa/(g/cm³)")
                                        .font(MaterialType.body)
                                        .foregroundColor(Palette.color(.textSecondary))
                                }
                                Text(props.spruceQualityLong.rawValue)
                                    .font(MaterialType.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(Palette.color(props.spruceQualityLong))
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Cross-grain:")
                                    .font(MaterialType.body)
                                    .foregroundColor(Palette.color(.textSecondary))
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(FieldPrecision.string(props.specificModulusCross, FieldPrecision.specificModulus))
                                        .font(MaterialType.value)
                                        .fontWeight(.bold)
                                        .foregroundColor(Palette.color(props.spruceQualityCross))
                                    Text("GPa/(g/cm³)")
                                        .font(MaterialType.body)
                                        .foregroundColor(Palette.color(.textSecondary))
                                }
                                Text(props.spruceQualityCross.rawValue)
                                    .font(MaterialType.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(Palette.color(props.spruceQualityCross))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(Palette.color(.backgroundSubtle))
                    .cornerRadius(8)
                    
                    // Radiation Ratio
                    propertyRow(
                        title: "Radiation Ratio (R)",
                        longValue: FieldPrecision.string(props.radiationRatioLong, FieldPrecision.radiationRatio),
                        crossValue: FieldPrecision.string(props.radiationRatioCross, FieldPrecision.radiationRatio)
                    )
                    
                    // Cross/Long Ratio
                    HStack {
                        Text("Cross/Long Ratio:")
                            .font(MaterialType.body)
                        Spacer()
                        Text(FieldPrecision.string(props.crossLongRatio, FieldPrecision.crossLongRatio))
                            .font(MaterialType.bodyBold)
                        Text("(typical: 0.04–0.08)")
                            .font(MaterialType.body)
                            .foregroundColor(Palette.color(.textSecondary))
                    }

                    // Long/Cross Ratio
                    HStack {
                        Text("Long/Cross Ratio:")
                            .font(MaterialType.body)
                        Spacer()
                        Text(FieldPrecision.string(props.longCrossRatio, FieldPrecision.longCrossRatio))
                            .font(MaterialType.bodyBold)
                        Text("(typical: 12–25)")
                            .font(MaterialType.body)
                            .foregroundColor(Palette.color(.textSecondary))
                    }

                    // Overall Quality Assessment
                    HStack {
                        Text("Overall Quality:")
                            .font(MaterialType.bodyBold)
                        Spacer()
                        Text(props.overallQuality.rawValue)
                            .font(MaterialType.bodyBold)
                            .fontWeight(.bold)
                            .foregroundColor(Palette.color(props.overallQuality))
                    }

                }
            }
        }
    }
    
    // MARK: - Gore Thickness Section (standalone, shown immediately after peaks)

    /// Gore Target Thickness as a standalone section, shown immediately after the peak list.
    @ViewBuilder
    private var goreThicknessSectionView: some View {
        if let props = calculatedPlateProperties {
            materialSection("Gore Target Thickness", boxed: false) {
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
            materialSection("Sample Dimensions") {
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
            materialSection("Body Dimensions") {
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
    
    /// The brace's properties, once it has its peak and dimensions — which a completed brace always has.
    @ViewBuilder
    private var bracePropertiesSection: some View {
        if let props = calculatedBraceProperties {
            materialSection("Brace Properties") {
                VStack(alignment: .leading, spacing: 6) {
                    // Speed of Sound
                    // (fL is an input, shown in the peak list above — not repeated here.)
                    HStack {
                        Text("Speed of Sound:")
                            .font(MaterialType.body)
                        Spacer()
                        Text("\(FieldPrecision.string(props.speedOfSoundLong, FieldPrecision.speedOfSoundMS)) m/s")
                            .font(MaterialType.bodyBold)
                    }
                    
                    // Young's Modulus
                    HStack {
                        Text("Young's Modulus (E):")
                            .font(MaterialType.body)
                        Spacer()
                        Text("\(FieldPrecision.string(props.youngsModulusLongGPa, FieldPrecision.youngsModulusGPa)) GPa")
                            .font(MaterialType.bodyBold)
                    }
                    
                    // Specific Modulus — highlighted as the key metric
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Specific Modulus (E/ρ)")
                            .font(MaterialType.bodyBold)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(FieldPrecision.string(props.specificModulusLong, FieldPrecision.specificModulus))
                                .font(MaterialType.value)
                                .fontWeight(.bold)
                                .foregroundColor(Palette.color(props.spruceQuality))
                            Text("GPa/(g/cm³)")
                                .font(MaterialType.body)
                                .foregroundColor(Palette.color(.textSecondary))
                        }
                        Text(props.spruceQuality.rawValue)
                            .font(MaterialType.body)
                            .fontWeight(.medium)
                            .foregroundColor(Palette.color(props.spruceQuality))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(Palette.color(.backgroundSubtle))
                    .cornerRadius(8)
                    
                    // Radiation Ratio
                    HStack {
                        Text("Radiation Ratio (R):")
                            .font(MaterialType.body)
                        Spacer()
                        Text(FieldPrecision.string(props.radiationRatioLong, FieldPrecision.radiationRatio))
                            .font(MaterialType.bodyBold)
                    }
                }
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
                Text(FieldPrecision.string(hd, FieldPrecision.goreThicknessMM))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(Palette.color(.accentText))
                Text("mm")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.color(.textSecondary))
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Palette.color(.materialGoreBox))
            .cornerRadius(8)
        }
    }

    // MARK: - Measurement Process Instructions

    /// Plate tap instructions content — shared between inline (in-progress) and
    /// end-of-scroll (post-completion) placements.
    @ViewBuilder
    private var plateMeasurementInstructions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(includesFlcTap ? "Three-Tap Measurement Process:" : "Two-Tap Measurement Process:")
                .font(MaterialType.smallBold)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(Palette.color(.materialLongitudinal))
                        .frame(width: 8, height: 8)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("**1. Longitudinal (fL) Tap**")
                            .font(MaterialType.small)
                        Text("Hold plate at 22% from one end along the length, near one long edge (not at the width node). Tap center.")
                            .font(MaterialType.small)
                            .foregroundColor(Palette.color(.textSecondary))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(Palette.color(.materialCross))
                        .frame(width: 8, height: 8)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("**2. Cross-grain (fC) Tap**")
                            .font(MaterialType.small)
                        Text("Rotate 90°. Hold plate at 22% from one end along the width, near one short edge (not at the length node). Tap center.")
                            .font(MaterialType.small)
                            .foregroundColor(Palette.color(.textSecondary))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if includesFlcTap {
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(Palette.color(.materialFlc))
                            .frame(width: 8, height: 8)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("**3. Diagonal (fLC) Tap**")
                                .font(MaterialType.small)
                            Text("Hold plate at the midpoint of one long edge. Tap near the opposite corner (~22% from both the end and the side). Measures shear stiffness.")
                                .font(MaterialType.small)
                                .foregroundColor(Palette.color(.textSecondary))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(minWidth: 0, idealWidth: instructionIdealWidth, maxWidth: .infinity, alignment: .leading)

            Text("The strongest peak from each tap is auto-selected. Redo if needed.")
                .font(MaterialType.small)
                .foregroundColor(Palette.color(.textSecondary))
                .italic()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
        .frame(minWidth: 0, idealWidth: instructionIdealWidth, maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    /// Brace tap instructions content — shared between inline and end-of-scroll placements.
    @ViewBuilder
    private var braceMeasurementInstructions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Single-Tap Measurement (fL only):")
                .font(MaterialType.smallBold)

            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(Palette.color(.materialLongitudinal))
                    .frame(width: 8, height: 8)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("**1. Longitudinal (fL) Tap**")
                        .font(MaterialType.small)
                    Text("Hold brace at 22% from one end along the length. Tap center.")
                        .font(MaterialType.small)
                        .foregroundColor(Palette.color(.textSecondary))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("The strongest peak is auto-selected. Redo if needed.")
                .font(MaterialType.small)
                .foregroundColor(Palette.color(.textSecondary))
                .italic()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
        .frame(minWidth: 0, idealWidth: instructionIdealWidth, maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    /// Process instructions shown at the end of the scroll view after a plate measurement is complete.
    private var plateProcessInstructionsSection: some View {
        materialSection("Measurement Process") {
            plateMeasurementInstructions
        }
    }

    /// Process instructions shown at the end of the scroll view after a brace measurement is complete.
    private var braceProcessInstructionsSection: some View {
        materialSection("Measurement Process") {
            braceMeasurementInstructions
        }
    }

    // MARK: - Helper Views

    /// The plate / brace panel's type, the same in every edition: 10 pt for text and values, bold for
    /// section and property titles, 14 pt bold for the specific modulus, 9 pt for the process steps.
    private enum MaterialType {
        static let body = Font.system(size: 10)
        static let bodyBold = Font.system(size: 10, weight: .bold)
        static let value = Font.system(size: 14, weight: .bold)
        static let small = Font.system(size: 9)
        static let smallBold = Font.system(size: 9, weight: .bold)
    }

    /// The line between the plate / brace panel's sections — divider.section, plain enough to group
    /// the sections without competing with them.
    private var sectionDivider: some View {
        Rectangle()
            .fill(Palette.color(.dividerSection))
            .frame(height: 1)
    }

    /// The line under the header and above the footer — brighter than the section lines, so the
    /// header, the scrolling body and the footer read as three parts. Inset to the panel's text, as
    /// the section lines.
    private var headerFooterDivider: some View {
        Rectangle()
            .fill(Palette.color(.dividerHeaderFooter))
            .frame(height: 1)
            .padding(.horizontal)
    }

    /// A plate / brace section: its title — bold, at the panel's text size, flush with the panel's
    /// edge — over its content in a grey box, as the other editions draw it.
    /// `boxed: false` for a section whose content is its own box (the Gore result).
    private func materialSection<Content: View>(_ title: String, boxed: Bool = true,
                                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(MaterialType.bodyBold)
                .foregroundColor(Palette.color(.textPrimary))
            if boxed {
                content()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.color(.backgroundSubtle))
                    .cornerRadius(8)
            } else {
                content()
            }
        }
    }

    private func propertyRow(title: String, longValue: String, crossValue: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(MaterialType.bodyBold)
            HStack {
                Text("L: \(longValue)")
                    .font(MaterialType.body)
                Spacer()
                Text("C: \(crossValue)")
                    .font(MaterialType.body)
            }
            .foregroundColor(Palette.color(.textSecondary))
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
        HStack(spacing: 8) {
            // Selection toggle — interactive in guitar mode, informational in plate/brace.
            if let toggleAction = onToggleSelection {
                Button {
                    toggleAction()
                } label: {
                    Image(systemName: isSelected ? "star.fill" : "star")
                        .foregroundColor(Palette.color(isSelected ? .peakSelectedStar : .peakUnselectedStar))
                        .font(.system(size: 14))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(isSelected ? "Deselect peak" : "Select peak")
            } else {
                Image(systemName: isSelected ? "star.fill" : "star")
                    .foregroundColor(Palette.color(isSelected ? .peakSelectedStar : .peakUnselectedStar))
                    .font(.system(size: 14))
                    .frame(width: 24, height: 24)
            }

            // Frequency and magnitude — dashes until this phase's peak is captured.
            VStack(alignment: .leading, spacing: 0) {
                Text(peak.map { $0.frequency.formattedAsFrequency() } ?? "—")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Palette.color(peak == nil ? .textSecondary : .textPrimary))

                Text(peak.map { "\(FieldPrecision.string($0.magnitude, FieldPrecision.peakMagnitudeDB)) dB" } ?? "—")
                    .font(.system(size: 9))
                    .foregroundColor(Palette.color(.textSecondary))
            }

            Spacer()

            // Phase identification badges — display only, not interactive.
            // Colored when this peak was auto-identified for that phase.
            HStack(spacing: 8) {
                MaterialPhaseBadge(role: .longitudinal, active: isLongitudinal)

                if showCrossButton {
                    MaterialPhaseBadge(role: .cross, active: isCross)
                }

                if showFlcButton {
                    MaterialPhaseBadge(role: .flc, active: isFlc)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// "Analyzing" or "Stopped" with its dot — the one part of the results that follows the analyzer, kept in its own
/// view so that only it is redrawn when the analyzer publishes.
private struct AnalyzerRunningIndicator: View {
    @ObservedObject var fftAnalyzer: RealtimeFFTAnalyzer

    var body: some View {
        HStack {
            Circle()
                .fill(Palette.color(fftAnalyzer.isRunning ? .statusRunning : .statusStopped))
                .frame(width: 8, height: 8)

            Text(fftAnalyzer.isRunning ? "Analyzing" : "Stopped")
                .font(.caption)
                .foregroundColor(Palette.color(.textSecondary))
        }
    }
}
