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
/// `peaksAndModesSection` lists all `currentPeaks` sorted by frequency.
/// Each row shows the guitar mode color chip, frequency, magnitude, Q-factor,
/// pitch note and cents deviation, and a mode-override picker. Unknown modes
/// can be hidden via `TapDisplaySettings.showUnknownModes`. Rows can be
/// hidden/shown individually; Select All / Select None batch controls
/// are available in the section header.
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
    
    /// Whether FLC measurement was performed (live: has FLC peaks; loaded: has a restored FLC peak selection)
    private var hasFlcMeasurement: Bool {
        !analyzer.flcPeaks.isEmpty
            || analyzer.autoSelectedFlcPeakID != nil
            || analyzer.selectedFlcPeak != nil
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Analysis Results")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    HStack {
                        Text("Showing \(minFreq.formattedAsFrequency()) - \(maxFreq.formattedAsFrequency())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(measurementType.shortName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(measurementType.isGuitar ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                // Current peaks display
                peaksAndModesSection
                
                // Plate/brace-specific sections
                if measurementType == .plate {
                    Divider()
                    platePropertiesSection
                } else if measurementType == .brace {
                    Divider()
                    bracePropertiesSection
                } else {
                    // Guitar-specific sections
                    Divider()
                    
                    // Ring-out time (decay)
                    ringOutSection
                    
                    Divider()
                    
                    // Tap tone ratio
                    ratioSection
                }
                
                // Status indicator
                statusIndicator

                // Export buttons
                if onExportSpectrum != nil || onExportPDFReport != nil {
                    Divider()
                    if let exportSpectrum = onExportSpectrum {
                        Button {
                            exportSpectrum()
                        } label: {
                            Label("Export Spectrum", systemImage: "chart.line.uptrend.xyaxis")
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                    if let exportPDF = onExportPDFReport {
                        Button {
                            exportPDF()
                        } label: {
                            Label("Export PDF Report", systemImage: "doc.richtext")
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Computed Properties
    
    /// Combined peaks with mode classifications, filtered to the current frequency range and sorted by frequency
    /// Optionally filters out unknown modes based on user setting (guitar mode only)
    private var sortedPeaksWithModes: [(peak: ResonantPeak, mode: GuitarMode)] {
        analyzer.currentPeaks
            .filter { peak in
                // For plate/brace mode, don't filter by display range — the selected peaks
                // must always appear in results regardless of the current zoom level.
                // For guitar mode, filter to the displayed frequency range.
                measurementType.isGuitar
                    ? (peak.frequency >= minFreq && peak.frequency <= maxFreq)
                    : true
            }
            .map { peak in
                (peak: peak, mode: GuitarMode.classify(frequency: peak.frequency))
            }
            .filter { item in
                // For plate/brace mode, show all peaks (don't filter by guitar mode)
                // For guitar mode, optionally filter out unknown modes
                !measurementType.isGuitar || TapDisplaySettings.showUnknownModes || item.mode.normalized != .unknown
            }
            .sorted { $0.peak.frequency < $1.peak.frequency }
    }
    
    // MARK: - Subviews
    
    private var peaksAndModesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                // Header with visibility controls
                HStack {
                    Text(!measurementType.isGuitar ? "Detected Peaks" : "Detected Peaks & Modes")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    // Select All / Select None / Reset to Auto buttons
                    if !sortedPeaksWithModes.isEmpty {
                        HStack(spacing: 8) {
                            Button {
                                analyzer.selectAllPeaks()
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(analyzer.selectedPeakIDs.count == analyzer.currentPeaks.count)
                            .help("Select all peaks")

                            Button {
                                analyzer.selectNoPeaks()
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(analyzer.selectedPeakIDs.isEmpty)
                            .help("Deselect all peaks")

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
                
                Divider()
            }
            
            if sortedPeaksWithModes.isEmpty {
                Text("No peaks detected in visible range")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // For plate measurements, show selectable peaks
                    if measurementType == .plate {
                        ForEach(sortedPeaksWithModes, id: \.peak.id) { item in
                            MaterialPeakRowView(
                                peak: item.peak,
                                isLongitudinal: effectiveLongitudinalPeakID == item.peak.id,
                                isCross: effectiveCrossPeakID == item.peak.id,
                                isFlc: effectiveFlcPeakID == item.peak.id,
                                showFlcButton: hasFlcMeasurement,
                                isSelected: analyzer.selectedPeakIDs.contains(item.peak.id),
                                onSelectLongitudinal: {
                                    if effectiveLongitudinalPeakID == item.peak.id {
                                        analyzer.userSelectedLongitudinalPeakID = nil
                                        analyzer.selectedLongitudinalPeak = nil
                                    } else {
                                        analyzer.userSelectedLongitudinalPeakID = item.peak.id
                                        if effectiveCrossPeakID == item.peak.id {
                                            analyzer.userSelectedCrossPeakID = nil
                                            analyzer.selectedCrossPeak = nil
                                        }
                                        if effectiveFlcPeakID == item.peak.id {
                                            analyzer.userSelectedFlcPeakID = nil
                                            analyzer.selectedFlcPeak = nil
                                        }
                                    }
                                },
                                onSelectCross: {
                                    if effectiveCrossPeakID == item.peak.id {
                                        analyzer.userSelectedCrossPeakID = nil
                                        analyzer.selectedCrossPeak = nil
                                    } else {
                                        analyzer.userSelectedCrossPeakID = item.peak.id
                                        if effectiveLongitudinalPeakID == item.peak.id {
                                            analyzer.userSelectedLongitudinalPeakID = nil
                                            analyzer.selectedLongitudinalPeak = nil
                                        }
                                        if effectiveFlcPeakID == item.peak.id {
                                            analyzer.userSelectedFlcPeakID = nil
                                            analyzer.selectedFlcPeak = nil
                                        }
                                    }
                                },
                                onSelectFlc: {
                                    if effectiveFlcPeakID == item.peak.id {
                                        analyzer.userSelectedFlcPeakID = nil
                                        analyzer.selectedFlcPeak = nil
                                    } else {
                                        analyzer.userSelectedFlcPeakID = item.peak.id
                                        if effectiveLongitudinalPeakID == item.peak.id {
                                            analyzer.userSelectedLongitudinalPeakID = nil
                                            analyzer.selectedLongitudinalPeak = nil
                                        }
                                        if effectiveCrossPeakID == item.peak.id {
                                            analyzer.userSelectedCrossPeakID = nil
                                            analyzer.selectedCrossPeak = nil
                                        }
                                    }
                                },
                                onToggleSelection: {
                                    analyzer.togglePeakSelection(item.peak.id)
                                }
                            )
                        }
                        
                        // Instructions and guidance
                        // fixedSize allows text to wrap at the panel width instead of
                        // expanding the panel to the ideal (single-line) text width.
                        VStack(alignment: .leading, spacing: 6) {
                            Divider()
                                .padding(.vertical, 4)
                            
                            Text(hasFlcMeasurement ? "Three-Tap Measurement Process:" : "Two-Tap Measurement Process:")
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 6) {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("**1. Longitudinal (L) Tap**")
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
                                        Text("**2. Cross-grain (C) Tap**")
                                            .font(.caption2)
                                        Text("Rotate 90°. Hold plate at 22% from one end along the width, near one short edge (not at the length node). Tap center.")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: instructionTextMaxWidth, alignment: .leading)
                                }

                                if hasFlcMeasurement {
                                    HStack(alignment: .top, spacing: 6) {
                                        Circle()
                                            .fill(Color.purple)
                                            .frame(width: 8, height: 8)
                                            .padding(.top, 2)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("**3. FLC (Diagonal) Tap**")
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

                            Text("The strongest peak from each tap is auto-selected. Adjust selections above if needed.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .italic()
                                .frame(maxWidth: instructionTextMaxWidth, alignment: .leading)
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: instructionTextMaxWidth)
                        .padding(.top, 4)
                    } else if measurementType == .brace {
                        // Brace mode — fL selection only
                        ForEach(sortedPeaksWithModes, id: \.peak.id) { item in
                            MaterialPeakRowView(
                                peak: item.peak,
                                isLongitudinal: effectiveLongitudinalPeakID == item.peak.id,
                                isCross: false,
                                showCrossButton: false,
                                isSelected: analyzer.selectedPeakIDs.contains(item.peak.id),
                                onSelectLongitudinal: {
                                    if effectiveLongitudinalPeakID == item.peak.id {
                                        analyzer.userSelectedLongitudinalPeakID = nil
                                        analyzer.selectedLongitudinalPeak = nil
                                    } else {
                                        analyzer.userSelectedLongitudinalPeakID = item.peak.id
                                    }
                                },
                                onSelectCross: {},
                                onToggleSelection: {
                                    analyzer.togglePeakSelection(item.peak.id)
                                }
                            )
                        }
                        
                        // Brace instructions
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
                            
                            Text("The strongest peak is auto-selected. Adjust if needed.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .italic()
                                .frame(maxWidth: instructionTextMaxWidth, alignment: .leading)
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: instructionTextMaxWidth)
                        .padding(.top, 4)
                    } else {
                        // Standard guitar mode display
                        ForEach(sortedPeaksWithModes, id: \.peak.id) { item in
                            CombinedPeakModeRowView(
                                peak: item.peak,
                                mode: item.mode,
                                effectiveModeLabel: analyzer.effectiveModeLabel(for: item.peak),
                                isManualOverride: analyzer.hasManualOverride(for: item.peak.id),
                                isSelected: analyzer.selectedPeakIDs.contains(item.peak.id),
                                onToggleSelection: {
                                    analyzer.togglePeakSelection(item.peak.id)
                                },
                                onSetModeOverride: { label in
                                    analyzer.setModeOverride(.assigned(label), for: item.peak.id)
                                },
                                onResetModeOverride: {
                                    analyzer.resetModeOverride(for: item.peak.id)
                                }
                            )
                        }
                    }
                }
            }
        }
    }
    
    private var ringOutSection: some View {
        GroupBox("Ring-Out Time") {
            if let decayTime = analyzer.currentDecayTime {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(decayTime, specifier: "%.2f") seconds")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Time to decay \(Int(analyzer.decayThreshold)) dB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text(decayTime.decayQuality)
                            .font(.headline)
                            .foregroundColor(decayTime.decayQualityColor)
                        
                        Text("Sustain quality")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("Waiting for decay measurement...")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }
    
    private var ratioSection: some View {
        GroupBox("Tap Tone Ratio") {
            if let ratio = analyzer.calculateTapToneRatio() {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(ratio, specifier: "%.2f") : 1")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Top / Air")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text(ratio.tapToneRatioQuality)
                            .font(.headline)
                            .foregroundColor(ratio.tapToneRatioQualityColor)
                        
                        Text("Ideal: 1.9 - 2.1")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("Need both Air and Top modes")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
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
        guard let longPeakID = effectiveLongitudinalPeakID,
              let crossPeakID = effectiveCrossPeakID else {
            return nil
        }

        // Search phase-specific arrays first (live measurement), then fall back to
        // currentPeaks (loaded/saved measurements where phase arrays are not populated).
        let longPeak: ResonantPeak? =
            analyzer.longitudinalPeaks.first(where: { $0.id == longPeakID })
            ?? sortedPeaksWithModes.first(where: { $0.peak.id == longPeakID })?.peak

        let crossPeak: ResonantPeak? =
            analyzer.crossPeaks.first(where: { $0.id == crossPeakID })
            ?? sortedPeaksWithModes.first(where: { $0.peak.id == crossPeakID })?.peak

        guard let longPeak, let crossPeak else { return nil }

        // Resolve FLC peak frequency: check flcPeaks first (from its own tap),
        // then fall back to combined currentPeaks for saved measurements
        let flcFreq: Float? = {
            guard let flcPeakID = effectiveFlcPeakID else { return nil }
            return analyzer.flcPeaks.first(where: { $0.id == flcPeakID })?.frequency
                ?? sortedPeaksWithModes.first(where: { $0.peak.id == flcPeakID })?.peak.frequency
        }()

        let dimensions = MaterialDimensions(
            lengthMM: TapDisplaySettings.plateLength,
            widthMM: TapDisplaySettings.plateWidth,
            thicknessMM: TapDisplaySettings.plateThickness,
            massGrams: TapDisplaySettings.plateMass
        )

        return PlateProperties(
            dimensions: dimensions,
            fundamentalFrequencyLong: longPeak.frequency,
            fundamentalFrequencyCross: crossPeak.frequency,
            fundamentalFrequencyFlc: flcFreq
        )
    }
    
    private var platePropertiesSection: some View {
        GroupBox("Plate Properties") {
            if let props = calculatedPlateProperties {
                VStack(alignment: .leading, spacing: 16) {
                    // Frequencies used
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("fL (Longitudinal): \(props.fundamentalFrequencyLong, specifier: "%.1f") Hz")
                                .font(.caption)
                            Text("fC (Cross-grain): \(props.fundamentalFrequencyCross, specifier: "%.1f") Hz")
                                .font(.caption)
                            if let fLC = props.fundamentalFrequencyFlc {
                                Text("fLC (Diagonal): \(fLC, specifier: "%.1f") Hz")
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    Divider()
                    
                    // Speed of Sound
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
                                        .foregroundColor(qualityColor(for: props.spruceQualityLong))
                                    Text("GPa/(g/cm³)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(props.spruceQualityLong.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(qualityColor(for: props.spruceQualityLong))
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
                                        .foregroundColor(qualityColor(for: props.spruceQualityCross))
                                    Text("GPa/(g/cm³)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(props.spruceQualityCross.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(qualityColor(for: props.spruceQualityCross))
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
                        Text("(typical: 0.04-0.08)")
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
                        Text("(typical: 12-25)")
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
                            .foregroundColor(qualityColor(for: props.overallQuality))
                    }
                    .padding(.vertical, 4)

                    // Gore Target Thickness
                    goreThicknessView(for: props)
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
    
    // MARK: - Brace Properties Section
    
    /// Computed brace properties based on the selected fL peak and dimensions
    private var calculatedBraceProperties: BraceProperties? {
        guard let longPeakID = effectiveLongitudinalPeakID,
              let longPeak = sortedPeaksWithModes.first(where: { $0.peak.id == longPeakID })?.peak else {
            return nil
        }
        
        let dimensions = MaterialDimensions(
            lengthMM: TapDisplaySettings.braceLength,
            widthMM: TapDisplaySettings.braceWidth,
            thicknessMM: TapDisplaySettings.braceThickness,
            massGrams: TapDisplaySettings.braceMass
        )
        
        return BraceProperties(
            dimensions: dimensions,
            fundamentalFrequencyLong: longPeak.frequency
        )
    }
    
    private var bracePropertiesSection: some View {
        GroupBox("Brace Properties") {
            if let props = calculatedBraceProperties {
                VStack(alignment: .leading, spacing: 16) {
                    // Frequency used
                    HStack {
                        Text("Longitudinal (fL): \(props.fundamentalFrequencyLong, specifier: "%.1f") Hz")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    Divider()
                    
                    // Speed of Sound
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
                                .foregroundColor(qualityColor(for: props.spruceQuality))
                            Text("GPa/(g/cm³)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(props.spruceQuality.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(qualityColor(for: props.spruceQuality))
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

    /// Displays the Gore target thickness result
    @ViewBuilder
    private func goreThicknessView(for props: PlateProperties) -> some View {
        let bodyLength = TapDisplaySettings.guitarBodyLength
        let bodyWidth  = TapDisplaySettings.guitarBodyWidth
        let fvs        = TapDisplaySettings.plateStiffness
        let preset     = TapDisplaySettings.plateStiffnessPreset

        Divider()

        VStack(alignment: .leading, spacing: 10) {
            Text("Gore Target Thickness")
                .font(.subheadline)
                .fontWeight(.semibold)

            if let hd = props.goreTargetThickness(
                bodyLengthMm: bodyLength,
                bodyWidthMm: bodyWidth,
                vibrationalStiffness: fvs) {

                // Prominent thickness display
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.2f", hd))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)
                    Text("mm")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                // GLC shear modulus (or note that it was assumed zero)
                if let glc = props.goreShearModulus {
                    HStack {
                        Text("Shear Modulus (GLC):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.3f GPa", glc / 1.0e9))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                } else {
                    Label {
                        Text("GLC assumed 0 — enable FLC tap for a more accurate result")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                }

                // Parameters used
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Body: \(String(format: "%.0f", bodyLength)) × \(String(format: "%.0f", bodyWidth)) mm")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        let presetLabel = preset == .custom
                            ? String(format: "f_vs = %.0f (custom)", fvs)
                            : "f_vs = \(Int(fvs)) (\(preset.rawValue))"
                        Text(presetLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(8)
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
    
    private func qualityColor(for quality: WoodQuality) -> Color {
        switch quality {
        case .excellent: return .green
        case .veryGood: return .mint
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        }
    }
}

// MARK: - Plate/Brace Peak Row View

/// A row view for displaying a peak with plate/brace mode selection buttons
struct MaterialPeakRowView: View {
    let peak: ResonantPeak
    let isLongitudinal: Bool
    let isCross: Bool
    var isFlc: Bool = false
    var showCrossButton: Bool = true
    var showFlcButton: Bool = false
    var isSelected: Bool = true
    let onSelectLongitudinal: () -> Void
    let onSelectCross: () -> Void
    var onSelectFlc: (() -> Void)? = nil
    var onToggleSelection: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Selection toggle button
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
            }
            
            // Frequency and magnitude
            VStack(alignment: .leading, spacing: 2) {
                Text(peak.frequency.formattedAsFrequency())
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("\(peak.magnitude, specifier: "%.1f") dB")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Mode selection buttons
            HStack(spacing: 8) {
                Button(action: onSelectLongitudinal) {
                    Text("L")
                        .font(.headline)
                        .fontWeight(.bold)
                        .frame(width: 36, height: 36)
                        .background(isLongitudinal ? Color.blue : Color.secondary.opacity(0.2))
                        .foregroundColor(isLongitudinal ? .white : .primary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                if showCrossButton {
                    Button(action: onSelectCross) {
                        Text("C")
                            .font(.headline)
                            .fontWeight(.bold)
                            .frame(width: 36, height: 36)
                            .background(isCross ? Color.orange : Color.secondary.opacity(0.2))
                            .foregroundColor(isCross ? .white : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                
                if showFlcButton {
                    Button(action: { onSelectFlc?() }) {
                        Text("FLC")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .frame(width: 42, height: 36)
                            .background(isFlc ? Color.purple : Color.secondary.opacity(0.2))
                            .foregroundColor(isFlc ? .white : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
