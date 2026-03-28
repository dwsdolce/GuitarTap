//
//  TapToneMeasurement.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

/// # TapToneMeasurement
///
/// The complete, serialisable record of a single tap-tone analysis session.
///
/// A measurement captures everything needed to reproduce the original analysis view:
///
/// - The detected ``ResonantPeak`` array and the ``SpectrumSnapshot`` (or per-phase snapshots for
///   plate/brace) that back the spectrum chart.
/// - Display ranges and analysis settings so the chart re-opens at the correct zoom level.
/// - Annotation positions and peak selections so the user's layout is preserved exactly.
/// - Per-peak ``UserAssignedMode`` overrides for any labels the user customised.
/// - Microphone and calibration metadata for provenance.
///
/// ## Persistence Format
///
/// Measurements are serialised to JSON in the app's Documents directory.  The JSON file
/// is self-contained: all spectrum data needed to recreate the chart is embedded in the
/// ``spectrumSnapshot`` (guitar) or per-phase snapshots (plate/brace).  There are no
/// external sidecar files.  This makes the format suitable for exchange with other
/// applications (e.g. a Python analysis tool) without any dependency on GuitarTap's
/// internal file layout.
///
/// ## Measurement Types
///
/// | Type | Fields populated |
/// |------|-----------------|
/// | Guitar (classical / flamenco / acoustic) | `spectrumSnapshot`, `peaks`, `decayTime` |
/// | Plate | `longitudinalSnapshot`, `crossSnapshot`, optional `flcSnapshot`; `selectedLongitudinalPeakID`, `selectedCrossPeakID`, optional `selectedFlcPeakID` |
/// | Brace | `longitudinalSnapshot`, `selectedLongitudinalPeakID` |
import SwiftUI

/// A complete record of a tap-tone measurement session, including spectrum data, peaks,
/// display state, and all analysis settings active at the time of capture.
///
/// - SeeAlso: ``SpectrumSnapshot`` for the spectrum data container.
/// - SeeAlso: ``ResonantPeak`` for individual peak records.
/// - SeeAlso: ``UserAssignedMode`` for per-peak label overrides.
struct TapToneMeasurement: Identifiable, Codable {

    // MARK: - Identity & Timestamps

    /// Stable unique identifier for this measurement.
    let id: UUID

    /// Wall-clock time at which the measurement was saved.
    let timestamp: Date

    // MARK: - Analysis Results

    /// All resonant peaks detected during this measurement session.
    ///
    /// For guitar measurements these are the peaks from the averaged multi-tap spectrum.
    /// For plate/brace measurements this array combines peaks from all captured phases.
    let peaks: [ResonantPeak]

    /// Time for the tap transient to decay to the configured threshold, in seconds.
    ///
    /// `nil` for plate/brace measurements (decay is not meaningful for material analysis)
    /// or if decay tracking was not active.
    let decayTime: Float?

    // MARK: - User Metadata

    /// Descriptive label for the tap location, e.g. `"Bridge"`, `"Soundhole"`, `"Upper Bout"`.
    let tapLocation: String?

    /// Free-form notes entered by the user at save time.
    let notes: String?

    // MARK: - Guitar Spectrum

    /// The averaged frequency spectrum for guitar-mode measurements.
    ///
    /// Contains the full chart display settings needed to restore the spectrum plot.
    /// `nil` for plate/brace measurements, which use the per-phase snapshots instead.
    let spectrumSnapshot: SpectrumSnapshot?

    // MARK: - Annotation State

    /// Custom screen-space offsets for draggable peak annotation labels, keyed by peak UUID.
    ///
    /// Allows the user's manual label layout to survive a save/load cycle.
    let peakAnnotationOffsets: [UUID: CGPoint]?

    /// UUIDs of peaks the user marked as significant results (deselected peaks are dimmed).
    ///
    /// `nil` means all peaks are considered selected (backward-compatible default).
    let selectedPeakIDs: [UUID]?

    /// Frequencies (Hz) of the selected peaks, parallel to ``selectedPeakIDs``.
    ///
    /// Used to re-match selections after `findPeaks()` re-runs with a new threshold
    /// (which generates new UUIDs). Frequencies are stable across re-analysis;
    /// UUIDs are not.
    let selectedPeakFrequencies: [Float]?

    /// The annotation visibility mode (show all / show selected / hide all) that was active
    /// when the measurement was saved.
    let annotationVisibilityMode: AnnotationVisibilityMode?

    // MARK: - Analysis Settings

    /// The tap-detection threshold (dB above noise floor) configured at save time.
    let tapDetectionThreshold: Float?

    /// The hysteresis margin (dB) used to prevent re-triggering after a tap, at save time.
    let hysteresisMargin: Float?

    /// The number of taps that were averaged to produce the final spectrum.
    let numberOfTaps: Int?

    /// The minimum peak magnitude (dBFS) that the peak-finder accepted, at save time.
    let peakThreshold: Float?

    // MARK: - Material Measurement Peak Selections

    /// UUID of the peak selected as the longitudinal (along-grain) resonance in a plate/brace measurement.
    ///
    /// Used to look up the correct peak in ``peaks`` when reloading material property calculations.
    let selectedLongitudinalPeakID: UUID?

    /// UUID of the peak selected as the cross-grain resonance in a plate measurement.
    let selectedCrossPeakID: UUID?

    /// UUID of the peak selected as the FLC (diagonal / shear) resonance.
    ///
    /// Only present when the optional third tap was performed and ``SpectrumSnapshot/measureFlc``
    /// was `true`.
    let selectedFlcPeakID: UUID?

    // MARK: - Per-Phase Spectra (Plate / Brace)

    /// Averaged FFT spectrum from the longitudinal (along-grain) tap orientation.
    ///
    /// Populated for plate and brace measurements.  `nil` for guitar measurements.
    let longitudinalSnapshot: SpectrumSnapshot?

    /// Averaged FFT spectrum from the cross-grain tap orientation.
    ///
    /// Populated for plate measurements only.  `nil` for guitar and brace measurements.
    let crossSnapshot: SpectrumSnapshot?

    /// Averaged FFT spectrum from the FLC (45°-diagonal) tap orientation.
    ///
    /// Populated only when the optional third tap was performed.
    let flcSnapshot: SpectrumSnapshot?

    // MARK: - Mode Overrides

    /// Per-peak user mode label overrides, keyed by peak UUID.
    ///
    /// `nil` means all peaks use automatic classification on load (backward-compatible default).
    /// - SeeAlso: ``UserAssignedMode``
    let peakModeOverrides: [UUID: UserAssignedMode]?

    // MARK: - Microphone Provenance

    /// Human-readable name of the microphone (input device) used for this measurement.
    let microphoneName: String?

    /// Unique device identifier (UID) of the microphone, used to match a device on reload.
    let microphoneUID: String?

    /// Name of the active calibration profile applied during this measurement, if any.
    let calibrationName: String?

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id, timestamp, peaks, decayTime, tapLocation, notes
        case spectrumSnapshot, peakAnnotationOffsets
        case tapDetectionThreshold, hysteresisMargin, numberOfTaps, peakThreshold
        case selectedLongitudinalPeakID, selectedCrossPeakID, selectedFlcPeakID
        case longitudinalSnapshot, crossSnapshot, flcSnapshot
        case selectedPeakIDs, selectedPeakFrequencies, annotationVisibilityMode
        case peakModeOverrides
        case microphoneName, microphoneUID, calibrationName
        // Encode-only convenience fields for external consumers
        case measurementType, guitarType
    }

    /// A serialisable annotation offset in data-space coordinates.
    ///
    /// Stores the user's drag delta for a peak annotation label as physical units
    /// rather than screen pixels, making the value meaningful to external consumers.
    ///
    /// - `hzOffset`: horizontal displacement from the default label position, in Hz.
    /// - `dbOffset`: vertical displacement from the default label position, in dB.
    struct PeakAnnotationOffset: Codable {
        let hzOffset: Double
        let dbOffset: Double
    }

    /// CodingKeys for the per-peak export container that injects a resolved `modeLabel`.
    private enum PeakExportCodingKeys: String, CodingKey {
        case id, frequency, magnitude, quality, bandwidth, timestamp
        case pitchNote, pitchCents, pitchFrequency
        case modeLabel
    }

    // MARK: - Initializer

    /// Creates a new `TapToneMeasurement` with a fresh UUID and the current timestamp.
    ///
    /// All parameters except `peaks` have sensible defaults of `nil` so callers only need to
    /// supply the fields relevant to their measurement type.
    ///
    /// - Parameters:
    ///   - peaks: Detected resonant peaks for this measurement.
    ///   - decayTime: Ring-out decay time in seconds, if measured.
    ///   - tapLocation: User-supplied location label, e.g. `"Bridge"`.
    ///   - notes: Free-form notes.
    ///   - spectrum: Guitar-mode averaged spectrum snapshot.
    ///   - annotationOffsets: Custom label positions keyed by peak UUID.
    ///   - tapDetectionThreshold: Detection threshold in dB at save time.
    ///   - hysteresisMargin: Hysteresis margin in dB at save time.
    ///   - numberOfTaps: Number of taps averaged.
    ///   - peakThreshold: Minimum accepted peak magnitude in dBFS.
    ///   - selectedLongitudinalPeakID: UUID of the selected longitudinal peak (plate/brace).
    ///   - selectedCrossPeakID: UUID of the selected cross-grain peak (plate).
    ///   - selectedFlcPeakID: UUID of the selected FLC peak (plate, optional third tap).
    ///   - longitudinalSnapshot: Longitudinal-phase spectrum (plate/brace).
    ///   - crossSnapshot: Cross-grain-phase spectrum (plate).
    ///   - flcSnapshot: FLC-phase spectrum (plate, optional third tap).
    ///   - selectedPeakIDs: UUIDs of user-marked significant peaks.
    ///   - annotationVisibilityMode: Which annotations were visible when saved.
    ///   - peakModeOverrides: Per-peak label overrides keyed by peak UUID.
    ///   - microphoneName: Human-readable device name at time of recording.
    ///   - microphoneUID: Device UID at time of recording.
    ///   - calibrationName: Active calibration profile name, if any.
    init(peaks: [ResonantPeak],
         decayTime: Float? = nil,
         tapLocation: String? = nil,
         notes: String? = nil,
         spectrum: SpectrumSnapshot? = nil,
         annotationOffsets: [UUID: CGPoint]? = nil,
         tapDetectionThreshold: Float? = nil,
         hysteresisMargin: Float? = nil,
         numberOfTaps: Int? = nil,
         peakThreshold: Float? = nil,
         selectedLongitudinalPeakID: UUID? = nil,
         selectedCrossPeakID: UUID? = nil,
         selectedFlcPeakID: UUID? = nil,
         longitudinalSnapshot: SpectrumSnapshot? = nil,
         crossSnapshot: SpectrumSnapshot? = nil,
         flcSnapshot: SpectrumSnapshot? = nil,
         selectedPeakIDs: [UUID]? = nil,
         selectedPeakFrequencies: [Float]? = nil,
         annotationVisibilityMode: AnnotationVisibilityMode? = nil,
         peakModeOverrides: [UUID: UserAssignedMode]? = nil,
         microphoneName: String? = nil,
         microphoneUID: String? = nil,
         calibrationName: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.peaks = peaks
        self.decayTime = decayTime
        self.tapLocation = tapLocation
        self.notes = notes
        self.spectrumSnapshot = spectrum
        self.peakAnnotationOffsets = annotationOffsets
        self.tapDetectionThreshold = tapDetectionThreshold
        self.hysteresisMargin = hysteresisMargin
        self.numberOfTaps = numberOfTaps
        self.peakThreshold = peakThreshold
        self.selectedLongitudinalPeakID = selectedLongitudinalPeakID
        self.selectedCrossPeakID = selectedCrossPeakID
        self.selectedFlcPeakID = selectedFlcPeakID
        self.longitudinalSnapshot = longitudinalSnapshot
        self.crossSnapshot = crossSnapshot
        self.flcSnapshot = flcSnapshot
        self.selectedPeakIDs = selectedPeakIDs
        self.selectedPeakFrequencies = selectedPeakFrequencies
        self.annotationVisibilityMode = annotationVisibilityMode
        self.peakModeOverrides = peakModeOverrides
        self.microphoneName = microphoneName
        self.microphoneUID = microphoneUID
        self.calibrationName = calibrationName
    }

    // MARK: - Computed Properties

    /// The Top-to-Air frequency ratio, a key quality indicator for guitar tap-tone analysis.
    ///
    /// Computed as `f_Top / f_Air` where each frequency is taken from the first peak whose
    /// auto-classified mode normalises to `.top` or `.air` respectively.
    ///
    /// An ideal ratio is approximately **2.0**, meaning the main top-plate resonance sits
    /// one octave above the Helmholtz air resonance.  Ratios below ~1.7 or above ~2.4
    /// typically indicate the instrument is outside optimal tonal balance.
    ///
    /// Returns `nil` when either an Air or a Top peak cannot be found in ``peaks``.
    var tapToneRatio: Float? {
        let modeMap = GuitarMode.classifyAll(peaks)
        guard let airPeak = peaks.first(where: { (modeMap[$0.id] ?? .unknown).normalized == .air }),
              let topPeak = peaks.first(where: { (modeMap[$0.id] ?? .unknown).normalized == .top }) else {
            return nil
        }
        return topPeak.frequency / airPeak.frequency
    }

    /// Base filename (without extension) derived from the tap location and Unix timestamp.
    ///
    /// Spaces and slashes in ``tapLocation`` are replaced with hyphens and the string is
    /// lowercased, producing a filesystem-safe component such as `"bridge-1771351833"`.
    /// Falls back to `"measurement"` when ``tapLocation`` is `nil`.
    var baseFilename: String {
        let locationPart = tapLocation?.replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .lowercased() ?? "measurement"
        let timestampPart = Int(timestamp.timeIntervalSince1970)
        return "\(locationPart)-\(timestampPart)"
    }

    // MARK: - Decoding

    /// Synthesized-equivalent `init(from:)` required because we provide a custom `encode(to:)`.
    ///
    /// All stored properties are decoded from their standard keys.  The encode-only convenience
    /// keys (`measurementType`, `guitarType`, `modeLabel`) are ignored during decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id               = try container.decode(UUID.self,   forKey: .id)
        timestamp        = try container.decode(Date.self,   forKey: .timestamp)
        decayTime        = try container.decodeIfPresent(Float.self,  forKey: .decayTime)
        tapLocation      = try container.decodeIfPresent(String.self, forKey: .tapLocation)
        notes            = try container.decodeIfPresent(String.self, forKey: .notes)
        spectrumSnapshot = try container.decodeIfPresent(SpectrumSnapshot.self, forKey: .spectrumSnapshot)
        // Decode as named-field struct (hzOffset/dbOffset) and convert to CGPoint for in-memory use.
        // Also accepts legacy CGPoint encoding ({x:, y:}) from files written before this change.
        // Try the new named format (hzOffset/dbOffset) first; fall back to legacy CGPoint {x:,y:}.
        let namedOffsets = (try? container.decodeIfPresent([UUID: PeakAnnotationOffset].self, forKey: .peakAnnotationOffsets)) ?? nil
        if let named = namedOffsets {
            peakAnnotationOffsets = named.mapValues { CGPoint(x: $0.hzOffset, y: $0.dbOffset) }
        } else {
            peakAnnotationOffsets = try container.decodeIfPresent([UUID: CGPoint].self, forKey: .peakAnnotationOffsets)
        }
        tapDetectionThreshold = try container.decodeIfPresent(Float.self, forKey: .tapDetectionThreshold)
        hysteresisMargin = try container.decodeIfPresent(Float.self, forKey: .hysteresisMargin)
        numberOfTaps     = try container.decodeIfPresent(Int.self,   forKey: .numberOfTaps)
        peakThreshold    = try container.decodeIfPresent(Float.self, forKey: .peakThreshold)
        selectedLongitudinalPeakID = try container.decodeIfPresent(UUID.self, forKey: .selectedLongitudinalPeakID)
        selectedCrossPeakID        = try container.decodeIfPresent(UUID.self, forKey: .selectedCrossPeakID)
        selectedFlcPeakID          = try container.decodeIfPresent(UUID.self, forKey: .selectedFlcPeakID)
        longitudinalSnapshot = try container.decodeIfPresent(SpectrumSnapshot.self, forKey: .longitudinalSnapshot)
        crossSnapshot        = try container.decodeIfPresent(SpectrumSnapshot.self, forKey: .crossSnapshot)
        flcSnapshot          = try container.decodeIfPresent(SpectrumSnapshot.self, forKey: .flcSnapshot)
        selectedPeakIDs          = try container.decodeIfPresent([UUID].self,  forKey: .selectedPeakIDs)
        selectedPeakFrequencies  = try container.decodeIfPresent([Float].self, forKey: .selectedPeakFrequencies)
        annotationVisibilityMode = try container.decodeIfPresent(AnnotationVisibilityMode.self, forKey: .annotationVisibilityMode)
        peakModeOverrides    = try container.decodeIfPresent([UUID: UserAssignedMode].self, forKey: .peakModeOverrides)
        microphoneName       = try container.decodeIfPresent(String.self, forKey: .microphoneName)
        microphoneUID        = try container.decodeIfPresent(String.self, forKey: .microphoneUID)
        calibrationName      = try container.decodeIfPresent(String.self, forKey: .calibrationName)
        // Decode peaks as [ResonantPeak]; the extra modeLabel key in each entry is
        // silently ignored by ResonantPeak's synthesized Decodable conformance.
        peaks = try container.decode([ResonantPeak].self, forKey: .peaks)
    }

    // MARK: - Custom Encoding

    /// Encodes all stored fields plus three convenience additions for external consumers:
    ///
    /// - `measurementType`: top-level string (e.g. `"Acoustic Guitar"`) so consumers don't
    ///   need to dig into the nested snapshot to discover the measurement kind.
    /// - `guitarType`: top-level string (e.g. `"Acoustic"`) or absent for plate/brace.
    /// - `modeLabel`: resolved human-readable label added to each peak entry, incorporating
    ///   any user override from ``peakModeOverrides``.
    ///
    /// Decoding uses the synthesized `init(from:)` — the added keys are unknown to the stored
    /// properties and are silently ignored, keeping round-trips lossless.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Standard stored properties (mirrors synthesized encoding order)
        try container.encode(id,                        forKey: .id)
        try container.encode(timestamp,                 forKey: .timestamp)
        try container.encodeIfPresent(decayTime,        forKey: .decayTime)
        try container.encodeIfPresent(tapLocation,      forKey: .tapLocation)
        try container.encodeIfPresent(notes,            forKey: .notes)
        try container.encodeIfPresent(spectrumSnapshot, forKey: .spectrumSnapshot)
        // Encode offsets as named fields (hzOffset/dbOffset) rather than raw CGPoint {x:, y:}
        // so that external consumers (e.g. Python) can interpret the values correctly.
        let namedOffsets = peakAnnotationOffsets?.mapValues {
            PeakAnnotationOffset(hzOffset: Double($0.x), dbOffset: Double($0.y))
        }
        try container.encodeIfPresent(namedOffsets, forKey: .peakAnnotationOffsets)
        try container.encodeIfPresent(tapDetectionThreshold, forKey: .tapDetectionThreshold)
        try container.encodeIfPresent(hysteresisMargin, forKey: .hysteresisMargin)
        try container.encodeIfPresent(numberOfTaps,     forKey: .numberOfTaps)
        try container.encodeIfPresent(peakThreshold,    forKey: .peakThreshold)
        try container.encodeIfPresent(selectedLongitudinalPeakID, forKey: .selectedLongitudinalPeakID)
        try container.encodeIfPresent(selectedCrossPeakID,        forKey: .selectedCrossPeakID)
        try container.encodeIfPresent(selectedFlcPeakID,          forKey: .selectedFlcPeakID)
        try container.encodeIfPresent(longitudinalSnapshot, forKey: .longitudinalSnapshot)
        try container.encodeIfPresent(crossSnapshot,    forKey: .crossSnapshot)
        try container.encodeIfPresent(flcSnapshot,      forKey: .flcSnapshot)
        try container.encodeIfPresent(selectedPeakIDs,         forKey: .selectedPeakIDs)
        try container.encodeIfPresent(selectedPeakFrequencies, forKey: .selectedPeakFrequencies)
        try container.encodeIfPresent(annotationVisibilityMode, forKey: .annotationVisibilityMode)
        try container.encodeIfPresent(peakModeOverrides, forKey: .peakModeOverrides)
        try container.encodeIfPresent(microphoneName,   forKey: .microphoneName)
        try container.encodeIfPresent(microphoneUID,    forKey: .microphoneUID)
        try container.encodeIfPresent(calibrationName,  forKey: .calibrationName)

        // Convenience: top-level measurementType and guitarType for external consumers
        let resolvedMeasurementType = spectrumSnapshot?.measurementType
            ?? longitudinalSnapshot?.measurementType
        let resolvedGuitarType = spectrumSnapshot?.guitarType
            ?? longitudinalSnapshot?.guitarType
        try container.encodeIfPresent(resolvedMeasurementType, forKey: .measurementType)
        try container.encodeIfPresent(resolvedGuitarType,      forKey: .guitarType)

        // Encode peaks with a resolved modeLabel injected into each peak entry
        let mt = resolvedMeasurementType ?? TapDisplaySettings.measurementType
        let gt = resolvedGuitarType ?? TapDisplaySettings.guitarType
        // Compute context-aware mode map once so overlapping ranges resolve correctly
        let exportModeMap: [UUID: GuitarMode] = mt.isGuitar ? GuitarMode.classifyAll(peaks, guitarType: gt) : [:]
        var peaksContainer = container.nestedUnkeyedContainer(forKey: .peaks)
        for peak in peaks {
            var peakContainer = peaksContainer.nestedContainer(keyedBy: PeakExportCodingKeys.self)
            try peakContainer.encode(peak.id,        forKey: .id)
            try peakContainer.encode(peak.frequency, forKey: .frequency)
            try peakContainer.encode(peak.magnitude, forKey: .magnitude)
            try peakContainer.encode(peak.quality,   forKey: .quality)
            try peakContainer.encode(peak.bandwidth, forKey: .bandwidth)
            try peakContainer.encode(peak.timestamp, forKey: .timestamp)
            try peakContainer.encodeIfPresent(peak.pitchNote,      forKey: .pitchNote)
            try peakContainer.encodeIfPresent(peak.pitchCents,     forKey: .pitchCents)
            try peakContainer.encodeIfPresent(peak.pitchFrequency, forKey: .pitchFrequency)

            // Resolve the mode label: user override > auto-classify > plate/brace role
            let label: String
            if mt.isGuitar {
                switch peakModeOverrides?[peak.id] ?? .auto {
                case .auto:
                    label = (exportModeMap[peak.id] ?? .unknown).displayName
                case .assigned(let customLabel):
                    label = customLabel
                }
            } else {
                if peak.id == selectedLongitudinalPeakID      { label = "Longitudinal" }
                else if peak.id == selectedCrossPeakID        { label = "Cross-grain" }
                else if peak.id == selectedFlcPeakID          { label = "FLC" }
                else                                          { label = "Peak" }
            }
            try peakContainer.encode(label, forKey: .modeLabel)
        }
    }
}
