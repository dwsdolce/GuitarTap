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

// MARK: - TapEntry

/// One individual tap's spectrum and detected peaks within a multi-tap guitar sequence.
///
/// Stored in ``TapToneMeasurement/tapEntries`` so the per-tap comparison view can be
/// fully reconstructed after a save/reload cycle. Only populated for guitar-mode
/// measurements with `numberOfTaps > 1`; `nil` for single-tap, plate, and brace.
struct TapEntry: Codable, Identifiable {
    /// Stable unique identifier for this entry.
    let id: UUID
    /// 1-based display index ("Tap 1", "Tap 2", …).
    let tapIndex: Int
    /// Full spectrum snapshot for this individual tap.
    let snapshot: SpectrumSnapshot
    /// All resonant peaks detected in this tap's spectrum.
    /// Recomputed when the peak threshold changes so that the multi-tap comparison
    /// table reflects the current Peak Min slider setting.
    var peaks: [ResonantPeak]
    /// UUIDs of the auto-selected peaks for this tap (one per guitar mode where found).
    /// Recomputed alongside `peaks` when the peak threshold changes.
    var selectedPeakIDs: [UUID]

    /// Resolves the strongest peak per guitar mode from this tap's selected peaks.
    ///
    /// Filters `peaks` by `selectedPeakIDs`, classifies via `GuitarMode.classifyAll`,
    /// and returns the highest-magnitude peak per mode.  Used by the multi-tap
    /// comparison table, PDF export, and regression tests.
    ///
    /// - Parameter guitarType: Override guitar type for classification.
    ///   Defaults to the snapshot's stored guitar type.
    /// - Returns: A dictionary mapping each identified `GuitarMode` to its strongest `ResonantPeak`.
    func resolvedModePeaks(guitarType: GuitarType? = nil) -> [GuitarMode: ResonantPeak] {
        let selectedIDs = Set(selectedPeakIDs)
        let selected = peaks.filter { selectedIDs.contains($0.id) }
        return TapToneAnalyzer.resolvedModePeaks(
            peaks: selected,
            guitarType: guitarType ?? snapshot.guitarType
        )
    }
}

// MARK: - ComparisonEntry

/// A single spectrum entry within a saved comparison measurement.
///
/// Stores everything needed to restore one overlay in a comparison chart:
/// the full spectrum snapshot, selected peaks, guitar type, display label,
/// and chart color (as RGBA components, since `Color` is not `Codable`).
struct ComparisonEntry: Codable, Identifiable {
    /// Stable unique identifier for this entry.
    let id: UUID
    /// Display label for this spectrum (e.g. "Bridge", "Bridge (2)").
    let label: String
    /// Chart color stored as [red, green, blue, alpha], each 0.0–1.0.
    /// `Color` is not `Codable`; the fixed comparison palette makes this round-trip exact.
    let colorComponents: [Double]
    /// Full spectrum snapshot providing magnitudes, frequencies, and axis ranges.
    let snapshot: SpectrumSnapshot
    /// Selected peaks for this measurement at save time.
    let peaks: [ResonantPeak]
    /// Guitar type active when the source measurement was recorded, used for mode classification.
    let guitarType: GuitarType?
    /// UUID of the source `TapToneMeasurement` this entry was created from, if available.
    let sourceMeasurementID: UUID?

    /// The **definitive** Air / Top / Back for this overlaid spectrum, resolved once from the source
    /// measurement's own selection AND overrides, and stored as `{canonical mode name: peak UUID}`
    /// (the UUID references one of this entry's own ``peaks``).
    ///
    /// This makes a saved comparison **self-describing**: a reader reproduces the displayed table by
    /// looking each ID up in `peaks` — no need to re-run `classifyAll`, and no need for the source's
    /// override data (which is not in this file). Absent (`nil`) on files written before Phase 6b;
    /// those are healed on decode and re-saved. See Development/PEAK-LIFECYCLE-SPEC.md.
    var modePeakIDs: [String: UUID]? = nil

    /// Builds the `{mode name: peak id}` map for the three ratio-bearing modes from a resolved
    /// mode→peak dictionary. Keyed by ``GuitarMode`` raw value so Python/web read it directly.
    static func modeIDMap(from resolved: [GuitarMode: ResonantPeak]) -> [String: UUID] {
        var map: [String: UUID] = [:]
        for mode in [GuitarMode.air, .top, .back] where resolved[mode] != nil {
            map[mode.rawValue] = resolved[mode]!.id
        }
        return map
    }

    /// The frequency of this entry's definitive peak for `mode`, from ``modePeakIDs`` when present
    /// (self-describing), else re-derived positionally from ``peaks`` (legacy / in-memory fallback).
    func modeFrequency(_ mode: GuitarMode) -> Float? {
        if let id = modePeakIDs?[mode.rawValue], let p = peaks.first(where: { $0.id == id }) {
            return p.frequency
        }
        return TapToneAnalyzer.resolvedModePeaks(peaks: peaks, guitarType: guitarType)[mode]?.frequency
    }
}

// MARK: - TapToneMeasurement

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

    /// Descriptive name for the mesurement, e.g. `"Contreras"`, `"Gore"`, `"Ramirez"`.
    let measurementName: String?

    /// Free-form notes entered by the user at save time.
    let notes: String?

    // MARK: - Name Validation (FILE-PATHS-AND-NAMES-SPEC §3)
    // @parity model/measurement-name tests=test/measurement-name

    /// Whether `name` is acceptable to save: non-empty after trimming whitespace and newlines.
    /// The Save action is disabled until this holds. Single source of truth so all three platforms
    /// — and their tests — agree; a view must bind its Save button to this, never re-implement it.
    static func isValidName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The name to store: trimmed, or `nil` if blank. Blank is prevented at the UI by
    /// ``isValidName(_:)``, but the model stays tolerant so nameless files from older builds still
    /// read (the format keeps `measurementName` optional — this is a UI rule, not a format change).
    static func normalizedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Guitar Spectrum

    /// The averaged frequency spectrum for guitar-mode measurements.
    ///
    /// Contains the full chart display settings needed to restore the spectrum plot.
    /// `nil` for plate/brace measurements, which use the per-phase snapshots instead.
    let spectrumSnapshot: SpectrumSnapshot?

    // MARK: - Annotation State

    /// Absolute data-space positions for draggable peak annotation labels, keyed by peak UUID.
    ///
    /// Each `CGPoint` stores the label-center position in data-space: `x` = frequency in Hz,
    /// `y` = magnitude in dB. Allows the user's manual label layout to survive a save/load cycle.
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

    /// Whether the saved peak selection was hand-modified by the user (vs the automatic
    /// mode-priority selection). Restored on load so a loaded measurement behaves like a live one:
    /// an **automatic** selection re-runs auto-selection when Peak Min changes (so a peak revealed
    /// by lowering Peak Min is selected as its mode's winner), while a **manual** selection is
    /// carried forward. `nil` in files saved before this field — those default to `true` (manual),
    /// preserving prior behaviour exactly. Never touches `peakModeOverrides` (user-assigned mode
    /// labels), which are persisted and restored independently.
    let userModifiedSelection: Bool?

    /// The annotation visibility mode (show all / show selected / hide all) that was active
    /// when the measurement was saved.
    let annotationVisibilityMode: AnnotationVisibilityMode?

    // MARK: - Analysis Settings

    /// The tap-detection threshold (dB above noise floor) configured at save time.
    let tapDetectionThreshold: Float?

    /// The number of taps that were averaged to produce the final spectrum.
    let numberOfTaps: Int?

    /// The minimum peak magnitude (dBFS) that the peak-finder accepted, at save time.
    let peakMinThreshold: Float?

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

    /// Effective capture sample rate (Hz) used for this measurement, for reload
    /// provenance checks. `nil` for older files saved before this field existed.
    let sampleRate: Double?

    // MARK: - Comparison Record

    /// Non-nil when this measurement is a saved comparison rather than a single tap event.
    ///
    /// When present, each element represents one overlaid spectrum.  All other analysis
    /// fields (`peaks`, `spectrumSnapshot`, `decayTime`, etc.) are empty or nil and
    /// should not be read.  Use `isComparison` to detect this case.
    let comparisonEntries: [ComparisonEntry]?

    /// `true` when this record holds a saved comparison rather than a single tap measurement.
    var isComparison: Bool { comparisonEntries != nil }

    // MARK: - Per-Tap Spectra (Multi-Tap Guitar)

    /// Individual tap spectra and peaks from a multi-tap guitar sequence.
    ///
    /// Non-nil only for guitar measurements where `numberOfTaps > 1`. Each element
    /// corresponds to one raw tap capture before averaging. Allows the multi-tap
    /// comparison view to be reconstructed after save/reload.
    ///
    /// `nil` for single-tap guitar measurements, plate, brace, comparison records,
    /// and older saved measurements (backward-compatible default).
    let tapEntries: [TapEntry]?

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id, timestamp, peaks, decayTime, measurementName, tapLocation, notes
        case spectrumSnapshot, peakAnnotationOffsets
        case tapDetectionThreshold, numberOfTaps, peakMinThreshold
        // Legacy key used in files saved before the peakThreshold → peakMinThreshold rename
        case legacyPeakThreshold = "peakThreshold"
        case selectedLongitudinalPeakID, selectedCrossPeakID, selectedFlcPeakID
        case longitudinalSnapshot, crossSnapshot, flcSnapshot
        case selectedPeakIDs, selectedPeakFrequencies, userModifiedSelection, annotationVisibilityMode
        case peakModeOverrides
        case microphoneName, microphoneUID, calibrationName, sampleRate
        case comparisonEntries
        case tapEntries
        // Encode-only convenience fields for external consumers
        case measurementType, guitarType
    }

    /// A serialisable annotation position in absolute data-space coordinates.
    ///
    /// Stores the absolute label center position as physical units rather than
    /// screen pixels, making the value meaningful to external consumers and
    /// consistent across different chart sizes and platforms.
    ///
    /// - `absFreqHz`: label center frequency in Hz.
    /// - `absDB`: label center magnitude in dB.
    struct PeakAnnotationOffset: Codable {
        let absFreqHz: Double
        let absDB: Double
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
    ///   - id: Stable unique identifier; defaults to a fresh `UUID`.
    ///   - timestamp: Capture time; defaults to now.
    ///   - peaks: Detected resonant peaks for this measurement.
    ///   - decayTime: Ring-out decay time in seconds, if measured.
    ///   - measurementName: User-supplied measurement name label, e.g. `"Martin"`.
    ///   - notes: Free-form notes.
    ///   - spectrum: Guitar-mode averaged spectrum snapshot.
    ///   - annotationOffsets: Custom label positions keyed by peak UUID.
    ///   - tapDetectionThreshold: Detection threshold in dB at save time.
    ///   - numberOfTaps: Number of taps averaged.
    ///   - peakMinThreshold: Minimum accepted peak magnitude in dBFS.
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
    ///   - sampleRate: Capture sample rate in Hz, if recorded.
    ///   - comparisonEntries: Per-tap comparison rows for multi-tap measurements.
    ///   - tapEntries: Per-tap raw entries retained for the multi-tap breakdown.
    ///   - selectedPeakFrequencies: Frequencies (Hz) of user-marked significant peaks, a
    ///     format-stable fallback to `selectedPeakIDs`.
    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         peaks: [ResonantPeak],
         decayTime: Float? = nil,
         measurementName: String? = nil,
         notes: String? = nil,
         spectrum: SpectrumSnapshot? = nil,
         annotationOffsets: [UUID: CGPoint]? = nil,
         tapDetectionThreshold: Float? = nil,
         numberOfTaps: Int? = nil,
         peakMinThreshold: Float? = nil,
         selectedLongitudinalPeakID: UUID? = nil,
         selectedCrossPeakID: UUID? = nil,
         selectedFlcPeakID: UUID? = nil,
         longitudinalSnapshot: SpectrumSnapshot? = nil,
         crossSnapshot: SpectrumSnapshot? = nil,
         flcSnapshot: SpectrumSnapshot? = nil,
         selectedPeakIDs: [UUID]? = nil,
         selectedPeakFrequencies: [Float]? = nil,
         userModifiedSelection: Bool? = nil,
         annotationVisibilityMode: AnnotationVisibilityMode? = nil,
         peakModeOverrides: [UUID: UserAssignedMode]? = nil,
         microphoneName: String? = nil,
         microphoneUID: String? = nil,
         calibrationName: String? = nil,
         sampleRate: Double? = nil,
         comparisonEntries: [ComparisonEntry]? = nil,
         tapEntries: [TapEntry]? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.peaks = peaks
        self.decayTime = decayTime
        self.measurementName = measurementName
        self.notes = notes
        self.spectrumSnapshot = spectrum
        self.peakAnnotationOffsets = annotationOffsets
        self.tapDetectionThreshold = tapDetectionThreshold
        self.numberOfTaps = numberOfTaps
        self.peakMinThreshold = peakMinThreshold
        self.selectedLongitudinalPeakID = selectedLongitudinalPeakID
        self.selectedCrossPeakID = selectedCrossPeakID
        self.selectedFlcPeakID = selectedFlcPeakID
        self.longitudinalSnapshot = longitudinalSnapshot
        self.crossSnapshot = crossSnapshot
        self.flcSnapshot = flcSnapshot
        self.selectedPeakIDs = selectedPeakIDs
        self.selectedPeakFrequencies = selectedPeakFrequencies
        self.userModifiedSelection = userModifiedSelection
        self.annotationVisibilityMode = annotationVisibilityMode
        self.peakModeOverrides = peakModeOverrides
        self.microphoneName = microphoneName
        self.microphoneUID = microphoneUID
        self.calibrationName = calibrationName
        self.sampleRate = sampleRate
        self.comparisonEntries = comparisonEntries
        self.tapEntries = tapEntries
    }

    /// Returns a copy of the measurement with only `measurementName` and `notes` replaced.
    ///
    /// All other fields — including `id` and `timestamp` — are preserved exactly.
    func with(measurementName: String?, notes: String?) -> TapToneMeasurement {
        return TapToneMeasurement(
            id: id,
            timestamp: timestamp,
            peaks: peaks,
            decayTime: decayTime,
            measurementName: measurementName,
            notes: notes,
            spectrum: spectrumSnapshot,
            annotationOffsets: peakAnnotationOffsets,
            tapDetectionThreshold: tapDetectionThreshold,
            numberOfTaps: numberOfTaps,
            peakMinThreshold: peakMinThreshold,
            selectedLongitudinalPeakID: selectedLongitudinalPeakID,
            selectedCrossPeakID: selectedCrossPeakID,
            selectedFlcPeakID: selectedFlcPeakID,
            longitudinalSnapshot: longitudinalSnapshot,
            crossSnapshot: crossSnapshot,
            flcSnapshot: flcSnapshot,
            selectedPeakIDs: selectedPeakIDs,
            selectedPeakFrequencies: selectedPeakFrequencies,
            userModifiedSelection: userModifiedSelection,
            annotationVisibilityMode: annotationVisibilityMode,
            peakModeOverrides: peakModeOverrides,
            microphoneName: microphoneName,
            microphoneUID: microphoneUID,
            calibrationName: calibrationName,
            sampleRate: sampleRate,
            comparisonEntries: comparisonEntries,
            tapEntries: tapEntries
        )
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
        guard let air = definitivePeak(for: .air),
              let top = definitivePeak(for: .top) else {
            return nil
        }
        return top.frequency / air.frequency
    }

    /// The **definitive** peak for a mode — the same rule the live analyzer applies
    /// (``TapToneAnalyzer/getPeak(for:)``): the *selected* peak whose *effective* (override-aware)
    /// mode is that mode. Deselecting a peak, or relabelling it, removes it from consideration here
    /// exactly as it does on screen, so the saved-list ratio and the on-screen ratio cannot disagree.
    ///
    /// Selection uses ``effectiveSelectedPeakIDs`` (guitar: the saved selection, or all peaks when a
    /// legacy file saved none; material: all — but material has no Air/Top so the ratio is moot).
    /// By the Phase 5 invariant there is at most one definitive Air/Top/Back; `max` guards the legacy
    /// case where a pre-invariant file selected several.
    func definitivePeak(for mode: GuitarMode) -> ResonantPeak? {
        let autoMap = GuitarMode.classifyAll(peaks, guitarType: spectrumSnapshot?.guitarType ?? .acoustic)
        let selected = effectiveSelectedPeakIDs
        return peaks
            .filter {
                selected.contains($0.id)
                    && GuitarMode.effectiveMode(override: peakModeOverrides?[$0.id],
                                                auto: autoMap[$0.id] ?? .unknown).normalized == mode.normalized
            }
            .max(by: { $0.magnitude < $1.magnitude })
    }

    /// The definitive Air / Top / Back for this measurement, each with a flag for whether it is the
    /// user's manual override — for the multi-tap Averaged row, on screen and in the PDF, where an
    /// overridden value must be marked so it is not read as the averaged spectrum's auto peak.
    func definitiveModeInfo() -> [GuitarMode: (frequency: Float, isOverride: Bool)] {
        var out: [GuitarMode: (frequency: Float, isOverride: Bool)] = [:]
        for mode in [GuitarMode.air, .top, .back] {
            guard let p = definitivePeak(for: mode) else { continue }
            let isOverride: Bool
            if case .assigned = peakModeOverrides?[p.id] { isOverride = true } else { isOverride = false }
            out[mode] = (p.frequency, isOverride)
        }
        return out
    }

    /// Base filename (without extension) derived from the measurementName and Unix timestamp.
    ///
    /// Spaces and slashes in ``measurementName`` are replaced with hyphens and the string is
    /// lowercased, producing a filesystem-safe component such as `"ramirez-1975"`.
    /// Falls back to `"measurement"` when ``measurementName`` is `nil`.
    var baseFilename: String {
        ExportFilename.stem(name: measurementName, timestamp: timestamp, unnamed: "measurement")
    }

    // MARK: - Decoding

    /// Synthesized-equivalent `init(from:)` required because we provide a custom `encode(to:)`.
    ///
    /// All stored properties are decoded from their standard keys.  The encode-only convenience
    /// keys (`measurementType`, `guitarType`, `modeLabel`) are ignored during decode.
    // MARK: - Duplicate-Peak Heal

    /// `true` when decoding repaired duplicate peaks in this measurement.
    ///
    /// Transient and deliberately **not** encoded: it describes what happened during one
    /// decode, not a property of the file. The saved-measurements store reads it to force a
    /// save so the library repairs itself; a `.guitartap` file opened from disk is healed in
    /// memory and written in corrected form only if the user saves it.
    var wasHealed: Bool = false

    /// Collapses peaks that describe the same spectral feature.
    ///
    /// Files written before the `findPeaks` duplicate fix contain one bit-identical twin per
    /// capture (and one per tap entry in multi-tap files): the detector visited overlap bins
    /// once per overlapping mode range and minted a peak each time. Loaded peaks are
    /// authoritative and are never re-derived, so without this every existing file would show
    /// a phantom Analysis Results row forever.
    /// See Development/PEAK-FINDING-DUPLICATE-PEAKS.md in the GuitarTapWeb repo.
    ///
    /// Keeps, in order of preference: the peak in `selectedIDs` (the claimed mode winner),
    /// then the louder, then the first seen. `findPeaks` guarantees legitimately saved peaks
    /// are at least `peakProximityHz` apart, so any closer pair is corruption by definition.
    ///
    /// - Returns: the healed peaks and the ids that were dropped (empty when nothing changed).
    static func healDuplicatePeaks(
        _ peaks: [ResonantPeak],
        selectedIDs: Set<UUID>
    ) -> (peaks: [ResonantPeak], removed: Set<UUID>) {
        var kept: [ResonantPeak] = []
        var removed = Set<UUID>()

        for peak in peaks {
            guard let idx = kept.firstIndex(where: {
                abs($0.frequency - peak.frequency) < TapToneAnalyzer.peakProximityHz
            }) else {
                kept.append(peak)
                continue
            }

            let incumbent = kept[idx]
            let preferIncoming: Bool
            if selectedIDs.contains(peak.id) != selectedIDs.contains(incumbent.id) {
                preferIncoming = selectedIDs.contains(peak.id)
            } else {
                preferIncoming = peak.magnitude > incumbent.magnitude
            }

            if preferIncoming {
                removed.insert(incumbent.id)
                kept[idx] = peak
            } else {
                removed.insert(peak.id)
            }
        }

        return (kept, removed)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id               = try container.decode(UUID.self,   forKey: .id)
        timestamp        = try container.decode(Date.self,   forKey: .timestamp)
        decayTime        = try container.decodeIfPresent(Float.self,  forKey: .decayTime)
        // Fall back to legacy "tapLocation" key for files saved before the rename.
        measurementName  = try container.decodeIfPresent(String.self, forKey: .measurementName)
            ?? container.decodeIfPresent(String.self, forKey: .tapLocation)
        notes            = try container.decodeIfPresent(String.self, forKey: .notes)
        spectrumSnapshot = try container.decodeIfPresent(SpectrumSnapshot.self, forKey: .spectrumSnapshot)
        // Decode as named-field struct (absFreqHz/absDB) and convert to CGPoint for in-memory use.
        // Also accepts legacy CGPoint encoding ({x:, y:}) from files written before this change.
        // Try the new named format (absFreqHz/absDB) first; fall back to legacy formats.
        let namedOffsets = (try? container.decodeIfPresent([UUID: PeakAnnotationOffset].self, forKey: .peakAnnotationOffsets)) ?? nil
        var decodedOffsets: [UUID: CGPoint]?
        if let named = namedOffsets {
            decodedOffsets = named.mapValues { CGPoint(x: $0.absFreqHz, y: $0.absDB) }
        } else {
            // Legacy: raw CGPoint or old hzOffset/dbOffset fields — treat as no position saved.
            // Annotation labels will fall back to their default (70pt above peak) positions.
            decodedOffsets = nil
        }
        tapDetectionThreshold = try container.decodeIfPresent(Float.self, forKey: .tapDetectionThreshold)
        numberOfTaps     = try container.decodeIfPresent(Int.self,   forKey: .numberOfTaps)
        // Try new key first; fall back to legacy "peakThreshold" for files saved before rename.
        peakMinThreshold    = try container.decodeIfPresent(Float.self, forKey: .peakMinThreshold)
            ?? container.decodeIfPresent(Float.self, forKey: .legacyPeakThreshold)
        selectedLongitudinalPeakID = try container.decodeIfPresent(UUID.self, forKey: .selectedLongitudinalPeakID)
        selectedCrossPeakID        = try container.decodeIfPresent(UUID.self, forKey: .selectedCrossPeakID)
        selectedFlcPeakID          = try container.decodeIfPresent(UUID.self, forKey: .selectedFlcPeakID)
        longitudinalSnapshot = try container.decodeIfPresent(SpectrumSnapshot.self, forKey: .longitudinalSnapshot)
        crossSnapshot        = try container.decodeIfPresent(SpectrumSnapshot.self, forKey: .crossSnapshot)
        flcSnapshot          = try container.decodeIfPresent(SpectrumSnapshot.self, forKey: .flcSnapshot)
        var decodedSelectedPeakIDs = try container.decodeIfPresent([UUID].self,  forKey: .selectedPeakIDs)
        selectedPeakFrequencies  = try container.decodeIfPresent([Float].self, forKey: .selectedPeakFrequencies)
        userModifiedSelection    = try container.decodeIfPresent(Bool.self, forKey: .userModifiedSelection)
        annotationVisibilityMode = try container.decodeIfPresent(AnnotationVisibilityMode.self, forKey: .annotationVisibilityMode)
        // Canonical encoding is a flat [uuid, mode, uuid, mode, …] array — how
        // JSONEncoder serialises [UUID: UserAssignedMode] (UUID is not a string key).
        // GuitarTap Python 1.0.x instead wrote a {uuidString: mode} JSON object;
        // accept that legacy shape on import so those files remain loadable.
        var decodedOverrides: [UUID: UserAssignedMode]?
        if let native = try? container.decodeIfPresent([UUID: UserAssignedMode].self, forKey: .peakModeOverrides) {
            decodedOverrides = native
        } else if let legacy = try? container.decodeIfPresent([String: UserAssignedMode].self, forKey: .peakModeOverrides) {
            decodedOverrides = Dictionary(uniqueKeysWithValues: legacy.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
        } else {
            decodedOverrides = nil
        }
        microphoneName       = try container.decodeIfPresent(String.self, forKey: .microphoneName)
        microphoneUID        = try container.decodeIfPresent(String.self, forKey: .microphoneUID)
        calibrationName      = try container.decodeIfPresent(String.self, forKey: .calibrationName)
        sampleRate           = try container.decodeIfPresent(Double.self, forKey: .sampleRate)
        var decodedComparisonEntries = try container.decodeIfPresent([ComparisonEntry].self, forKey: .comparisonEntries)
        var decodedTapEntries = try container.decodeIfPresent([TapEntry].self, forKey: .tapEntries)
        // Decode peaks as [ResonantPeak]; the extra modeLabel key in each entry is
        // silently ignored by ResonantPeak's synthesized Decodable conformance.
        var decodedPeaks = try container.decode([ResonantPeak].self, forKey: .peaks)

        // --- Heal duplicate peaks written by the pre-fix findPeaks ---
        // Every read path reaches this initialiser: `.guitartap` import and the
        // saved-measurements store both go through decodeMeasurements(_:).
        var healed = false
        let (healedPeaks, removedIDs) = Self.healDuplicatePeaks(
            decodedPeaks, selectedIDs: Set(decodedSelectedPeakIDs ?? [])
        )
        if !removedIDs.isEmpty {
            decodedPeaks = healedPeaks
            // Drop dangling references so nothing points at a peak that no longer exists.
            decodedSelectedPeakIDs = decodedSelectedPeakIDs?.filter { !removedIDs.contains($0) }
            decodedOffsets = decodedOffsets?.filter { !removedIDs.contains($0.key) }
            decodedOverrides = decodedOverrides?.filter { !removedIDs.contains($0.key) }
            healed = true
        }

        // Multi-tap files carry a duplicate inside every tap entry as well; the Taps view and
        // the multi-tap PDF read those, so they need the same repair.
        if var entries = decodedTapEntries {
            var entryHealed = false
            for i in entries.indices {
                let (p, removed) = Self.healDuplicatePeaks(
                    entries[i].peaks, selectedIDs: Set(entries[i].selectedPeakIDs)
                )
                guard !removed.isEmpty else { continue }
                entries[i].peaks = p
                entries[i].selectedPeakIDs = entries[i].selectedPeakIDs.filter { !removed.contains($0) }
                entryHealed = true
            }
            if entryHealed {
                decodedTapEntries = entries
                healed = true
            }
        }

        // --- Heal peak selection so a guitar measurement has a DEFINITIVE Air / Top / Back ---
        //
        // Phase 5 made selection unique per Air/Top/Back; Phase 6 makes every derived value read that
        // definitive peak. Legacy files predate both:
        //   • no selection saved  → nil, which older load code treated as "all selected" — every
        //     Air/Top/Back at once, which is exactly what the invariant forbids;
        //   • a pre-Phase-5 selection → could hold two selected Tops.
        // Repair both here, at the one initialiser every read path reaches, so the on-screen state,
        // the saved-list ratio and the file itself all agree. Guitar only — material has no per-peak
        // selection (`effectiveSelectedPeakIDs` already returns all peaks for it). This sets the same
        // `healed` flag as the duplicate-peak repair, so the library re-saves identically (and a
        // `.guitartap` opened from disk is healed in memory until the user saves).
        let isMaterialAtDecode = (spectrumSnapshot?.measurementType ?? longitudinalSnapshot?.measurementType)
            .map { !$0.isGuitar } ?? (longitudinalSnapshot != nil || selectedLongitudinalPeakID != nil)
        if !isMaterialAtDecode {
            let gt = spectrumSnapshot?.guitarType
            let autoMap = gt.map { GuitarMode.classifyAll(decodedPeaks, guitarType: $0) }
                ?? GuitarMode.classifyAll(decodedPeaks)
            func effMode(_ p: ResonantPeak) -> GuitarMode {
                GuitarMode.effectiveMode(override: decodedOverrides?[p.id], auto: autoMap[p.id] ?? .unknown)
            }
            let singleHolder: Set<GuitarMode> = [.air, .top, .back]

            if decodedSelectedPeakIDs == nil {
                // No saved selection: establish the auto set — the strongest peak per effective mode.
                var chosen: [GuitarMode: ResonantPeak] = [:]
                for p in decodedPeaks {
                    let m = effMode(p).normalized
                    guard m != .unknown else { continue }
                    if let cur = chosen[m], p.magnitude <= cur.magnitude { continue }
                    chosen[m] = p
                }
                decodedSelectedPeakIDs = chosen.values.map { $0.id }
                healed = true
            } else {
                // A saved selection may pre-date the uniqueness rule: keep at most the strongest
                // selected peak per single-holder mode; leave cluster modes and unknowns untouched.
                let selectedSet = Set(decodedSelectedPeakIDs!)
                var strongestByMode: [GuitarMode: ResonantPeak] = [:]
                for p in decodedPeaks where selectedSet.contains(p.id) {
                    let m = effMode(p).normalized
                    guard singleHolder.contains(m) else { continue }
                    if let cur = strongestByMode[m], p.magnitude <= cur.magnitude { continue }
                    strongestByMode[m] = p
                }
                let winners = Set(strongestByMode.values.map { $0.id })
                let pruned = decodedSelectedPeakIDs!.filter { id in
                    guard let p = decodedPeaks.first(where: { $0.id == id }) else { return false }
                    let m = effMode(p).normalized
                    return !singleHolder.contains(m) || winners.contains(id)
                }
                if pruned.count != decodedSelectedPeakIDs!.count {
                    decodedSelectedPeakIDs = pruned
                    healed = true
                }
            }
        }

        // --- Heal legacy comparison entries: fill the definitive mode→peak map (Phase 6b) ---
        // Pre-6b saved comparisons stored no `modePeakIDs`, so their Air/Top/Back was re-derived
        // positionally at render — and could not reflect a source measurement's override. Compute it
        // once now from each entry's own selected peaks. Override-BLIND (an old file never wrote the
        // source's overrides, so nothing better is recoverable), but it freezes what the old app
        // showed and makes the file self-describing from here on. Flagged for re-save.
        if var entries = decodedComparisonEntries {
            var changed = false
            for i in entries.indices where entries[i].modePeakIDs == nil {
                let resolved = TapToneAnalyzer.resolvedModePeaks(
                    peaks: entries[i].peaks, guitarType: entries[i].guitarType)
                entries[i].modePeakIDs = ComparisonEntry.modeIDMap(from: resolved)
                changed = true
            }
            if changed {
                decodedComparisonEntries = entries
                healed = true
            }
        }

        peaks                 = decodedPeaks
        selectedPeakIDs       = decodedSelectedPeakIDs
        peakAnnotationOffsets = decodedOffsets
        peakModeOverrides     = decodedOverrides
        tapEntries            = decodedTapEntries
        comparisonEntries     = decodedComparisonEntries
        wasHealed             = healed
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
        try container.encodeIfPresent(measurementName,  forKey: .measurementName)
        try container.encodeIfPresent(notes,            forKey: .notes)
        try container.encodeIfPresent(spectrumSnapshot, forKey: .spectrumSnapshot)
        // Encode positions as named fields (absFreqHz/absDB) rather than raw CGPoint {x:, y:}
        // so that external consumers (e.g. Python) can interpret the values correctly.
        // Values are absolute data-space label-center positions (Hz, dB).
        let namedOffsets = peakAnnotationOffsets?.mapValues {
            PeakAnnotationOffset(absFreqHz: Double($0.x), absDB: Double($0.y))
        }
        try container.encodeIfPresent(namedOffsets, forKey: .peakAnnotationOffsets)
        try container.encodeIfPresent(tapDetectionThreshold, forKey: .tapDetectionThreshold)
        try container.encodeIfPresent(numberOfTaps,     forKey: .numberOfTaps)
        try container.encodeIfPresent(peakMinThreshold,    forKey: .peakMinThreshold)
        try container.encodeIfPresent(selectedLongitudinalPeakID, forKey: .selectedLongitudinalPeakID)
        try container.encodeIfPresent(selectedCrossPeakID,        forKey: .selectedCrossPeakID)
        try container.encodeIfPresent(selectedFlcPeakID,          forKey: .selectedFlcPeakID)
        try container.encodeIfPresent(longitudinalSnapshot, forKey: .longitudinalSnapshot)
        try container.encodeIfPresent(crossSnapshot,    forKey: .crossSnapshot)
        try container.encodeIfPresent(flcSnapshot,      forKey: .flcSnapshot)
        try container.encodeIfPresent(selectedPeakIDs,         forKey: .selectedPeakIDs)
        try container.encodeIfPresent(selectedPeakFrequencies, forKey: .selectedPeakFrequencies)
        try container.encodeIfPresent(userModifiedSelection,    forKey: .userModifiedSelection)
        try container.encodeIfPresent(annotationVisibilityMode, forKey: .annotationVisibilityMode)
        try container.encodeIfPresent(peakModeOverrides, forKey: .peakModeOverrides)
        try container.encodeIfPresent(microphoneName,    forKey: .microphoneName)
        try container.encodeIfPresent(microphoneUID,     forKey: .microphoneUID)
        try container.encodeIfPresent(calibrationName,   forKey: .calibrationName)
        try container.encodeIfPresent(sampleRate, forKey: .sampleRate)
        try container.encodeIfPresent(comparisonEntries, forKey: .comparisonEntries)
        try container.encodeIfPresent(tapEntries,        forKey: .tapEntries)

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
                else if peak.id == selectedFlcPeakID          { label = "Diagonal" }
                else                                          { label = "Peak" }
            }
            try peakContainer.encode(label, forKey: .modeLabel)
        }
    }
}

// MARK: - Material selection

extension TapToneMeasurement {

    /// The measurement type resolved from the stored snapshots (mirrors the resolution in
    /// ``encode(to:)``); `nil` for legacy files that predate the top-level type.
    var resolvedMeasurementType: MeasurementType? {
        spectrumSnapshot?.measurementType ?? longitudinalSnapshot?.measurementType
    }

    /// The measurement's type as the single word shown in the Details pane:
    /// Acoustic / Classical / Flamenco / Generic / Plate / Brace / Comparison — or "—" when no
    /// snapshot carries a type. The type lives ONLY in the snapshot (never a top-level field), so this
    /// resolves from the snapshot. Mirrors Python `_type_name` / web `measurementTypeName`.
    var measurementTypeShortName: String {
        isComparison ? "Comparison" : (resolvedMeasurementType?.shortName ?? "—")
    }

    /// `true` for a plate/brace (material) measurement.
    ///
    /// Material measurements have **no per-peak selection** — the identified L/C/FLC in ``peaks``
    /// *are* the peaks. Falls back to the presence of material-only fields for legacy files whose
    /// snapshot type cannot be resolved.
    var isMaterial: Bool {
        if let mt = resolvedMeasurementType { return !mt.isGuitar }
        return longitudinalSnapshot != nil || selectedLongitudinalPeakID != nil
    }

    // @parity model/material-selection tests=test/material-selection
    /// The set of peak IDs to render, annotate, and export for this measurement.
    ///
    /// - Guitar: the user's saved selection (``selectedPeakIDs``), or all ``peaks`` when none was saved.
    /// - Material: **always all of ``peaks``.** Plate/brace have no per-peak selection, and the saved
    ///   `selectedPeakIDs` aggregate can be corrupted by an intermittent phase-transition write
    ///   (an iPad-only Release glitch), so it is ignored on read. This heals existing corrupt files
    ///   at render time — the same rule the web and Python ports apply.
    var effectiveSelectedPeakIDs: Set<UUID> {
        if isMaterial { return Set(peaks.map { $0.id }) }
        return Set(selectedPeakIDs ?? peaks.map { $0.id })
    }
}
