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
/// Measurements are serialised to JSON in the app's Documents directory.  The companion
/// spectrum PNG (if present) is stored as a separate file with the name given by
/// ``chartImageFilename``.  The ``chartImageData`` property is **transient** — it is excluded
/// from JSON via ``CodingKeys`` and is loaded separately at runtime by
/// ``TapToneAnalyzer+MeasurementManagement``.
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

    // MARK: - Chart Image

    /// Filename (without directory path) of the companion PNG spectrum image.
    ///
    /// Stored alongside the JSON file in the Documents directory.
    /// `nil` if no image was captured when saving.
    let chartImageFilename: String?

    /// In-memory PNG image data for the spectrum chart.
    ///
    /// - Important: This property is **transient** and is excluded from JSON serialisation
    ///   via ``CodingKeys``.  It is loaded at runtime by reading the file named
    ///   ``chartImageFilename`` from the Documents directory.
    var chartImageData: Data?

    // MARK: - Annotation State

    /// Custom screen-space offsets for draggable peak annotation labels, keyed by peak UUID.
    ///
    /// Allows the user's manual label layout to survive a save/load cycle.
    let peakAnnotationOffsets: [UUID: CGPoint]?

    /// UUIDs of peaks the user marked as significant results (deselected peaks are dimmed).
    ///
    /// `nil` means all peaks are considered selected (backward-compatible default).
    let selectedPeakIDs: [UUID]?

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

    /// Explicit coding keys that exclude the transient ``chartImageData`` from JSON.
    enum CodingKeys: String, CodingKey {
        case id, timestamp, peaks, decayTime, tapLocation, notes
        case spectrumSnapshot, chartImageFilename, peakAnnotationOffsets
        case tapDetectionThreshold, hysteresisMargin, numberOfTaps, peakThreshold
        case selectedLongitudinalPeakID, selectedCrossPeakID, selectedFlcPeakID
        case longitudinalSnapshot, crossSnapshot, flcSnapshot
        case selectedPeakIDs, annotationVisibilityMode
        case peakModeOverrides
        case microphoneName, microphoneUID, calibrationName
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
    ///   - chartImageFilename: Filename of the companion PNG in the Documents directory.
    ///   - chartImageData: Transient in-memory PNG data (not persisted to JSON).
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
         chartImageFilename: String? = nil,
         chartImageData: Data? = nil,
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
        self.chartImageFilename = chartImageFilename
        self.chartImageData = chartImageData
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
        guard let airPeak = peaks.first(where: { GuitarMode.classify(frequency: $0.frequency).normalized == .air }),
              let topPeak = peaks.first(where: { GuitarMode.classify(frequency: $0.frequency).normalized == .top }) else {
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
}
