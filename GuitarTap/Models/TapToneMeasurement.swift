//
//  TapToneMeasurement.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

// @parity model/measurement-codable tests=test/measurement-codable,test/peak-heal,test/peak-selection-persistence

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
    /// All resonant peaks detected in this tap's spectrum, found once at capture at the
    /// detection floor (`peakDetectionFloor`) and never re-derived — Peak Min does not touch them.
    var peaks: [ResonantPeak]
    /// UUIDs of the auto-selected peaks for this tap (one per guitar mode where found),
    /// chosen once at capture alongside `peaks`.
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
    /// override data (which is not in this file). Absent (`nil`) on files that predate this field;
    /// those are healed on decode and re-saved.
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

    // MARK: - Name Validation
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

    /// The notes to store: trimmed, or `nil` if blank.
    ///
    /// The two user-entered text fields normalize the same way, so "has this been edited" means
    /// the same thing for both, as in both ports. Every path that stores notes — save and edit
    /// alike — goes through here, so they cannot disagree.
    static func normalizedNotes(_ notes: String) -> String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Guitar Spectrum
    // @parity model/measurement-codable tests=test/measurement-codable,test/peak-heal,test/peak-selection-persistence

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

    /// Frequencies (Hz) of the selected peaks, parallel to ``selectedPeakIDs``. Written for a program
    /// reading the file that wants the selected peaks' frequencies without resolving the IDs or repeating
    /// the selection; GuitarTap itself does not read it back.
    let selectedPeakFrequencies: [Float]?

    /// Whether the saved peak selection was hand-modified by the user (vs the automatic
    /// mode-priority selection). Restored on load, so a loaded measurement offers Reset to automatic
    /// selection as it did when saved. `nil` in files saved before this field — those default to
    /// `true` (manual). Never touches `peakModeOverrides` (user-assigned mode labels), which are
    /// persisted and restored independently.
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
    let peakModeOverrides: [UUID: String]?

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

    /// A saved comparison's chart range when it was saved — loading it shows this range, as loading a
    /// measurement shows its own. Comparisons saved before this field existed have none; loading one
    /// spans its entries' ranges, as a new comparison does.
    let comparisonRange: DisplayRange.ChartRange?

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
        case comparisonRange
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
    ///   - comparisonRange: A saved comparison's chart range when it was saved.
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
         peakModeOverrides: [UUID: String]? = nil,
         microphoneName: String? = nil,
         microphoneUID: String? = nil,
         calibrationName: String? = nil,
         sampleRate: Double? = nil,
         comparisonEntries: [ComparisonEntry]? = nil,
         comparisonRange: DisplayRange.ChartRange? = nil,
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
        self.comparisonRange = comparisonRange
        self.tapEntries = tapEntries
    }

    // @parity model/measurement-amend tests=test/measurement-amend

    /// Whether the supplied values differ from what this measurement stores — the gate on the edit
    /// sheet's Save button.
    ///
    /// Both arguments must already be normalized (``normalizedName(_:)`` / ``normalizedNotes(_:)``)
    /// so the comparison is against what would actually be written. Amending mints a new ``id``, so
    /// a Save that changes nothing must not be reachable — it would give unchanged content a new
    /// identity. Single source of truth so all three platforms, and their tests, agree; a view
    /// binds its Save button to this and never re-implements it, exactly as it does for
    /// ``isValidName(_:)``.
    func isAmended(measurementName: String?, notes: String?) -> Bool {
        measurementName != self.measurementName || notes != self.notes
    }

    /// Returns a copy of the measurement with `measurementName` and `notes` replaced and a
    /// **new** ``id``.
    ///
    /// Name and notes are part of a measurement's data, not annotations on top of it, so an
    /// amended measurement is a different dataset and must carry a different identity. That is
    /// what makes ``id`` mean *same content* rather than *same act of saving*: two entries share
    /// an id exactly when they hold identical data — the state a duplicate import produces, and
    /// which editing either one correctly ends.
    ///
    /// ``timestamp`` is preserved. It records when the tap was captured, and amending a name does
    /// not change when it was captured.
    ///
    /// This is the *amend* operation, so callers must only reach it when something actually
    /// differs. `EditMeasurementView` enforces that by disabling Save until the normalized name or
    /// notes differ from the stored values; calling it with identical values would give unchanged
    /// content a new identity and break the rule above.
    func with(measurementName: String?, notes: String?) -> TapToneMeasurement {
        return TapToneMeasurement(
            id: UUID(),
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
            comparisonRange: comparisonRange,
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
    /// Selection is unique per Air/Top/Back, so there is at most one definitive holder; `max` guards
    /// a legacy file that selected several.
    func definitivePeak(for mode: GuitarMode) -> ResonantPeak? {
        let autoMap = autoModes
        let selected = effectiveSelectedPeakIDs
        return peaks
            .filter {
                selected.contains($0.id)
                    && GuitarMode.effectiveMode(override: peakModeOverrides?[$0.id],
                                                auto: autoMap[$0.id] ?? .unknown) == mode
            }
            .max(by: { $0.magnitude < $1.magnitude })
    }

    /// The guitar type this measurement's peaks are classified with: the type its snapshot records,
    /// otherwise Generic — never the app's current setting, so a saved measurement's modes are the
    /// same whatever the app is set to.
    var classificationGuitarType: GuitarType {
        spectrumSnapshot?.guitarType ?? longitudinalSnapshot?.guitarType ?? .generic
    }

    /// Each peak's automatic mode, classified among ALL of the measurement's peaks with
    /// ``classificationGuitarType`` — the rule the live analyzer applies (`reclassifyPeaks`). The Top
    /// and Back bands overlap and peaks compete for them, so classifying a subset (the selected
    /// peaks, the peaks on screen) can turn a Back into a Top. Empty for a material measurement.
    var autoModes: [UUID: GuitarMode] {
        isMaterial ? [:] : GuitarMode.classifyAll(peaks, guitarType: classificationGuitarType)
    }

    /// The label each peak is shown and written with: for a guitar, its override, otherwise its
    /// automatic mode (``autoModes``); for plate/brace, the role it fills. The one rule for the file's
    /// `modeLabel` and the Details pane, so the two cannot disagree.
    var peakModeLabels: [UUID: String] {
        if isMaterial {
            var labels: [UUID: String] = [:]
            for peak in peaks {
                if peak.id == selectedLongitudinalPeakID      { labels[peak.id] = "Longitudinal" }
                else if peak.id == selectedCrossPeakID        { labels[peak.id] = "Cross-grain" }
                else if peak.id == selectedFlcPeakID          { labels[peak.id] = "Diagonal" }
                else                                          { labels[peak.id] = "Peak" }
            }
            return labels
        }
        let modes = autoModes
        var labels: [UUID: String] = [:]
        for peak in peaks {
            labels[peak.id] = peakModeOverrides?[peak.id] ?? (modes[peak.id] ?? .unknown).displayName
        }
        return labels
    }

    /// The definitive Air / Top / Back for this measurement, each with a flag for whether it is the
    /// user's manual override — for the multi-tap Averaged row, on screen and in the PDF, where an
    /// overridden value must be marked so it is not read as the averaged spectrum's auto peak.
    func definitiveModeInfo() -> [GuitarMode: (frequency: Float, isOverride: Bool)] {
        var out: [GuitarMode: (frequency: Float, isOverride: Bool)] = [:]
        for mode in [GuitarMode.air, .top, .back] {
            guard let p = definitivePeak(for: mode) else { continue }
            let isOverride: Bool
            isOverride = peakModeOverrides?[p.id] != nil
            out[mode] = (p.frequency, isOverride)
        }
        return out
    }

    /// A multi-tap measurement as a comparison: one entry per tap — "Tap N", the tap's own spectrum
    /// and its selected peaks — and last "Averaged", the measurement's own spectrum and selected
    /// peaks. Empty when the measurement has no taps. The one builder of these entries: the on-screen
    /// tap comparison, its chart and the report's comparison page read it, live and saved alike.
    var multiTapComparisonEntries: [ComparisonEntry] {
        guard let tapEntries, !tapEntries.isEmpty else { return [] }
        var entries: [ComparisonEntry] = tapEntries.enumerated().map { index, entry in
            let selectedIDs = Set(entry.selectedPeakIDs)
            return ComparisonEntry(id: UUID(), label: "Tap \(entry.tapIndex)",
                colorComponents: Palette.storedComponents(Palette.series(index)), snapshot: entry.snapshot,
                peaks: entry.peaks.filter { selectedIDs.contains($0.id) },
                guitarType: entry.snapshot.guitarType, sourceMeasurementID: nil)
        }
        if let averaged = spectrumSnapshot {
            let selectedIDs = effectiveSelectedPeakIDs
            entries.append(ComparisonEntry(id: UUID(), label: "Averaged",
                colorComponents: Palette.storedComponents(Palette.seriesAverage), snapshot: averaged,
                peaks: peaks.filter { selectedIDs.contains($0.id) },
                guitarType: averaged.guitarType, sourceMeasurementID: nil))
        }
        return entries
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
    // @parity model/measurement-codable tests=test/measurement-codable,test/peak-heal,test/peak-selection-persistence

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

    /// The keys of a UUID-keyed map as the file holds it — the flat `[key, value, …]` array Swift writes,
    /// or the `{key: value}` object older writers used — each checked as a UUID. A key that is not one
    /// fails the decode; the values are read, or dropped as a legacy form, by the map's own reader.
    private static func checkUUIDKeys(in container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws {
        guard container.contains(key), try !container.decodeNil(forKey: key) else { return }
        if var flat = try? container.nestedUnkeyedContainer(forKey: key) {
            var index = 0
            while !flat.isAtEnd {
                if index.isMultiple(of: 2) {
                    let id = try flat.decode(String.self)
                    guard UUID(uuidString: id) != nil else { throw InvalidIDError(value: id, field: key.stringValue) }
                } else {
                    _ = try flat.decode(SkippedValue.self)
                }
                index += 1
            }
        } else if let object = try? container.nestedContainer(keyedBy: MapKey.self, forKey: key) {
            for id in object.allKeys where UUID(uuidString: id.stringValue) == nil {
                throw InvalidIDError(value: id.stringValue, field: key.stringValue)
            }
        }
    }

    /// A map value passed over while its key is checked.
    private struct SkippedValue: Decodable {
        init(from decoder: Decoder) throws {}
    }

    /// A key of a `{key: value}` map, whatever it is.
    private struct MapKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
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
        // Every id is a UUID, the map keys included: the readers below drop a legacy VALUE they cannot
        // convert, but a key that is not a UUID fails the decode, as every other id does.
        try Self.checkUUIDKeys(in: container, forKey: .peakAnnotationOffsets)
        try Self.checkUUIDKeys(in: container, forKey: .peakModeOverrides)
        // Decode as named-field struct (absFreqHz/absDB) and convert to CGPoint for in-memory use.
        // Also accepts legacy CGPoint encoding ({x:, y:}) from files written before this change.
        // Try the new named format (absFreqHz/absDB) first; fall back to legacy formats.
        let namedOffsets = (try? container.decodeIfPresent([UUID: PeakAnnotationOffset].self, forKey: .peakAnnotationOffsets)) ?? nil
        var decodedOffsets: [UUID: CGPoint]?
        if let named = namedOffsets {
            decodedOffsets = named.mapValues { CGPoint(x: $0.absFreqHz, y: $0.absDB) }
        } else {
            // Legacy: raw CGPoint or old hzOffset/dbOffset fields — treat as no position saved.
            // Annotation labels will fall back to their default positions (annotationCentre(for:)).
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
        // The wire shape stays `{"type":"assigned","label":…}` per entry; in memory this is the label
        // alone, matching Python `{uuid: label}` and web `Map<number, string>`. An `auto` entry
        // carries no label and means "no override", so it is DROPPED on read — both ports do the
        // same. That is why nothing in the app can hold a "no override" override.
        var decodedOverrides: [UUID: String]?
        if let native = try? container.decodeIfPresent([UUID: UserAssignedMode].self, forKey: .peakModeOverrides) {
            decodedOverrides = native.compactMapValues { if case .assigned(let l) = $0 { return l } else { return nil } }
        } else if let legacy = try? container.decodeIfPresent([String: UserAssignedMode].self, forKey: .peakModeOverrides) {
            decodedOverrides = Dictionary(uniqueKeysWithValues: legacy.compactMap { key, value in
                guard case .assigned(let l) = value, let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, l)
            })
        } else {
            decodedOverrides = nil
        }
        microphoneName       = try container.decodeIfPresent(String.self, forKey: .microphoneName)
        microphoneUID        = try container.decodeIfPresent(String.self, forKey: .microphoneUID)
        calibrationName      = try container.decodeIfPresent(String.self, forKey: .calibrationName)
        sampleRate           = try container.decodeIfPresent(Double.self, forKey: .sampleRate)
        comparisonRange      = try container.decodeIfPresent(DisplayRange.ChartRange.self, forKey: .comparisonRange)
        var decodedComparisonEntries = try container.decodeIfPresent([ComparisonEntry].self, forKey: .comparisonEntries)
        var decodedTapEntries = try container.decodeIfPresent([TapEntry].self, forKey: .tapEntries)
        // Decode peaks as [ResonantPeak]; the extra modeLabel key in each entry is
        // silently ignored by ResonantPeak's synthesized Decodable conformance.
        var decodedPeaks = try container.decode([ResonantPeak].self, forKey: .peaks)

        // --- Heal duplicate peaks written by the pre-fix findPeaks ---
        // Every read path reaches this initialiser: `.guitartap` import and the
        // saved-measurements store both go through decodeLibrary(_:).
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
        // Selection is unique per Air/Top/Back, and every derived value reads that definitive peak.
        // A legacy file can break that two ways:
        //   • no selection saved  → nil, which reads as "all selected" — every Air/Top/Back at once,
        //     which is exactly what the invariant forbids;
        //   • an older selection  → can hold two selected Tops.
        // Repair both here, at the one initialiser every read path reaches, so the on-screen state,
        // the saved-list ratio and the file itself all agree. Guitar only — material has no per-peak
        // selection (`effectiveSelectedPeakIDs` already returns all peaks for it) — and only with peaks: a
        // record without any (a comparison) has nothing to select. This sets the same
        // `healed` flag as the duplicate-peak repair, so the library re-saves identically (and a
        // `.guitartap` opened from disk is healed in memory until the user saves).
        let isMaterialAtDecode = (spectrumSnapshot?.measurementType ?? longitudinalSnapshot?.measurementType)
            .map { !$0.isGuitar } ?? (longitudinalSnapshot != nil || selectedLongitudinalPeakID != nil)
        if !isMaterialAtDecode && !decodedPeaks.isEmpty {
            // The same guitar type as ``classificationGuitarType``: the snapshot's, otherwise Generic.
            let gt = spectrumSnapshot?.guitarType ?? longitudinalSnapshot?.guitarType ?? .generic
            let autoMap = GuitarMode.classifyAll(decodedPeaks, guitarType: gt)
            func effMode(_ p: ResonantPeak) -> GuitarMode {
                GuitarMode.effectiveMode(override: decodedOverrides?[p.id], auto: autoMap[p.id] ?? .unknown)
            }
            let singleHolder: Set<GuitarMode> = [.air, .top, .back]

            if decodedSelectedPeakIDs == nil {
                // No saved selection: establish the auto set — the strongest peak per effective mode.
                var chosen: [GuitarMode: ResonantPeak] = [:]
                for p in decodedPeaks {
                    let m = effMode(p)
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
                    let m = effMode(p)
                    guard singleHolder.contains(m) else { continue }
                    if let cur = strongestByMode[m], p.magnitude <= cur.magnitude { continue }
                    strongestByMode[m] = p
                }
                let winners = Set(strongestByMode.values.map { $0.id })
                let pruned = decodedSelectedPeakIDs!.filter { id in
                    guard let p = decodedPeaks.first(where: { $0.id == id }) else { return false }
                    let m = effMode(p)
                    return !singleHolder.contains(m) || winners.contains(id)
                }
                if pruned.count != decodedSelectedPeakIDs!.count {
                    decodedSelectedPeakIDs = pruned
                    healed = true
                }
            }
        }

        // --- Heal legacy comparison entries: fill the definitive mode→peak map ---
        // A comparison entry with no `modePeakIDs` has no stored Air/Top/Back. Compute it once here
        // from the entry's own selected peaks. Override-BLIND (such a file carries no source
        // overrides, so nothing better is recoverable), and it makes the file self-describing.
        // Flagged for re-save.
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

        // A measurement without its spectrum has nothing to show or compare, so it is not read: it
        // needs a comparison of at least two entries, or a guitar spectrum or a plate/brace's
        // longitudinal one. A spectrum with no points — or with frequencies and magnitudes that
        // differ in number — is no spectrum, a comparison entry's included.
        let holdsSpectrum = { (snapshot: SpectrumSnapshot?) -> Bool in
            guard let snapshot else { return false }
            return !snapshot.frequencies.isEmpty && snapshot.frequencies.count == snapshot.magnitudes.count
        }
        let hasSpectrum = comparisonEntries.map { $0.count >= 2 && $0.allSatisfy { holdsSpectrum($0.snapshot) } }
            ?? (holdsSpectrum(spectrumSnapshot) || holdsSpectrum(longitudinalSnapshot))
        guard hasSpectrum else { throw NoSpectrumError() }
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
        // Re-wrap each label as `.assigned` so the on-disk shape is unchanged (see the decoder).
        try container.encodeIfPresent(peakModeOverrides?.mapValues { UserAssignedMode.assigned($0) },
                                      forKey: .peakModeOverrides)
        try container.encodeIfPresent(microphoneName,    forKey: .microphoneName)
        try container.encodeIfPresent(microphoneUID,     forKey: .microphoneUID)
        try container.encodeIfPresent(calibrationName,   forKey: .calibrationName)
        try container.encodeIfPresent(sampleRate, forKey: .sampleRate)
        try container.encodeIfPresent(comparisonEntries, forKey: .comparisonEntries)
        try container.encodeIfPresent(comparisonRange,   forKey: .comparisonRange)
        try container.encodeIfPresent(tapEntries,        forKey: .tapEntries)

        // Convenience: top-level measurementType and guitarType for external consumers
        let resolvedMeasurementType = spectrumSnapshot?.measurementType
            ?? longitudinalSnapshot?.measurementType
        let resolvedGuitarType = spectrumSnapshot?.guitarType
            ?? longitudinalSnapshot?.guitarType
        try container.encodeIfPresent(resolvedMeasurementType, forKey: .measurementType)
        try container.encodeIfPresent(resolvedGuitarType,      forKey: .guitarType)

        // Encode peaks with their label (``peakModeLabels``) injected into each peak entry
        let labels = peakModeLabels
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

            try peakContainer.encode(labels[peak.id] ?? GuitarMode.unknown.displayName, forKey: .modeLabel)
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

    // @parity model/measurement-type tests=test/measurement-type-name
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
    /// - Guitar: the user's saved selection (``selectedPeakIDs``) — empty for Select None — or all
    ///   ``peaks`` when a legacy file saved none.
    /// - Material: **always all of ``peaks``.** Plate/brace have no per-peak selection, and the saved
    ///   `selectedPeakIDs` aggregate can be corrupted by an intermittent phase-transition write
    ///   (an iPad-only Release glitch), so it is ignored on read. This heals existing corrupt files
    ///   at render time — the same rule the web and Python ports apply.
    var effectiveSelectedPeakIDs: Set<UUID> {
        if isMaterial { return Set(peaks.map { $0.id }) }
        return Set(selectedPeakIDs ?? peaks.map { $0.id })
    }
}

// MARK: - A measurement with no spectrum

/// A measurement in a file with no spectrum — no guitar spectrum, no plate/brace longitudinal one, or a
/// comparison of fewer than two entries; a spectrum with no points is none. The entry cannot be read; the
/// rest of its file can. Mirrors Python and web `NoSpectrumError`.
struct NoSpectrumError: Error, CustomStringConvertible {
    var description: String { "no spectrum" }
}

// MARK: - An id that is not a UUID

/// An id in a file that is missing or not a UUID: the file cannot be read. Names the field the way every
/// edition names it (`peaks[].id`, `tapEntries[].selectedPeakIDs` …) and the value, so the import's
/// message says which id it was. Mirrors Python and web `InvalidIdError`.
struct InvalidIDError: Error, CustomStringConvertible {
    let value: Any?
    let field: String

    var description: String {
        guard let value else { return "\(field) is missing" }
        return "\"\(value)\" in \(field) is not a UUID"
    }

    /// The fields that hold ids, named as every edition names them.
    static let idFields: Set<String> = [
        "id", "peaks[].id", "selectedPeakIDs", "selectedLongitudinalPeakID", "selectedCrossPeakID",
        "selectedFlcPeakID", "tapEntries[].id", "tapEntries[].peaks[].id", "tapEntries[].selectedPeakIDs",
        "comparisonEntries[].id", "comparisonEntries[].peaks[].id", "comparisonEntries[].sourceMeasurementID",
        "comparisonEntries[].modePeakIDs",
    ]

    /// The decoder's failure on an id field, as an `InvalidIDError` — its field named from the coding path
    /// and its value read from `data` — or nil when the failure is not about an id.
    static func from(_ error: DecodingError, in data: Data) -> InvalidIDError? {
        let path: [CodingKey]
        switch error {
        case .dataCorrupted(let context), .typeMismatch(_, let context), .valueNotFound(_, let context):
            path = context.codingPath
        case .keyNotFound(let key, let context):
            path = context.codingPath + [key]
        @unknown default:
            return nil
        }
        let field = fieldName(path)
        guard idFields.contains(field) else { return nil }
        return InvalidIDError(value: rawValue(at: path, in: data), field: field)
    }

    /// `peaks[].id` for `[0, "peaks", 3, "id"]`: an array index marks its key `[]`; the file's own array
    /// index, a trailing index into a list of ids and a key into `modePeakIDs` are left out.
    private static func fieldName(_ path: [CodingKey]) -> String {
        var name = ""
        for (i, key) in path.enumerated() {
            if key.intValue != nil {
                if i > 0 { name += "[]" }
            } else if name.hasSuffix("modePeakIDs") {
                break
            } else {
                name += (name.isEmpty ? "" : ".") + key.stringValue
            }
        }
        return name.hasSuffix("[]") ? String(name.dropLast(2)) : name
    }

    /// The value at `path` in the file, or nil when there is none.
    private static func rawValue(at path: [CodingKey], in data: Data) -> Any? {
        var node: Any? = try? JSONSerialization.jsonObject(with: data)
        for key in path {
            if let index = key.intValue, let array = node as? [Any] {
                node = index < array.count ? array[index] : nil
            } else {
                node = (node as? [String: Any])?[key.stringValue]
            }
        }
        return node is NSNull ? nil : node
    }
}

