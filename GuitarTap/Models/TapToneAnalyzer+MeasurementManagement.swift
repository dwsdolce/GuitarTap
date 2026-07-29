//
//  TapToneAnalyzer+MeasurementManagement.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

/// # TapToneAnalyzer+MeasurementManagement
///
/// Persistence, import/export, and full-state restoration for
/// ``TapToneMeasurement`` records.
///
/// ## Storage Layout
/// Measurements are persisted as a JSON array at:
/// ```
/// <Documents>/saved_measurements.json
/// ```
/// The JSON file is self-contained: all spectrum data needed to recreate the
/// chart is embedded in the snapshot fields.  There are no sidecar files.
///
/// ## Save / Load Contract
/// A saved measurement captures a complete snapshot of the analyser state at
/// the time of saving, including:
/// - All detected peaks with their UUIDs
/// - Per-phase spectra for plate/brace measurements
/// - Annotation offsets (dragged callout positions)
/// - Mode overrides (user-assigned peak labels)
/// - Display settings (frequency range, dB range, guitar type, etc.)
/// - Analysis settings (tap detection threshold, hysteresis, number of taps)
/// - Microphone UID and calibration name for reproducibility warnings
///
/// When ``loadMeasurement(_:)`` restores a measurement it:
/// 1. Restores all peaks, spectra, and derived state.
/// 2. Publishes `loaded*` properties that views observe to update their
///    controls without a new tap cycle.
/// 3. Disables tap detection so the UI enters a frozen "viewing" state.
/// 4. Auto-selects (or warns about) the recording microphone.
///
/// ## Microphone Warnings
/// On import/load, the UID of the recording microphone is compared against
/// `fftAnalyzer.availableInputDevices`. If the device is not connected,
/// `microphoneWarning` is set to a user-facing string. If it is connected,
/// the analyser automatically switches to it so calibration is applied.

import SwiftUI

extension TapToneAnalyzer {

    // MARK: - Measurement Persistence

    /// URL of the JSON file used for persisting all saved measurements.
    ///
    /// Located in the app's `Documents` directory, which is iCloud-backed on
    /// iOS and accessible via Files on macOS.
    ///
    /// When running under XCTest (`XCTestConfigurationFilePath` is set in the
    /// process environment) a temporary directory is used instead, so tests
    /// never read from or write to the user's real measurements file.
    static var measurementsFileURL: URL {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("com.guitartap.tests")
                .appendingPathComponent("saved_measurements.json")
        }
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("saved_measurements.json")
    }
    
    // MARK: - Measurement Codec

    /// The single JSON encoding of the measurement library.
    ///
    /// Every write path — persistence (`saved_measurements.json`), single-measurement
    /// export, and whole-library "Export All" — goes through this so the on-disk file
    /// and any exported `.guitartap` file are byte-for-byte the same form. The only
    /// things that differ between callers are *where* the bytes are written and *what*
    /// the file is named.
    ///
    /// Pretty-printed, sorted-key JSON with ISO-8601 dates.
    static func encodeMeasurements(_ measurements: [TapToneMeasurement]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(measurements)
    }

    /// The single JSON decoding of the measurement library.
    ///
    /// Every read path — loading `saved_measurements.json` and importing a `.guitartap`
    /// file or string — goes through this. Counterpart to ``encodeMeasurements(_:)``.
    static func decodeMeasurements(_ data: Data) throws -> [TapToneMeasurement] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TapToneMeasurement].self, from: data)
    }

    /// Loads all persisted measurements from disk.
    ///
    /// Reads `saved_measurements.json` from the Documents directory and decodes
    /// the `[TapToneMeasurement]` array with ISO-8601 date decoding.
    ///
    /// Populates `savedMeasurements` on the main thread. No-ops silently if
    /// the file does not yet exist.
    func loadPersistedMeasurements() {
        let fileURL = TapToneAnalyzer.measurementsFileURL
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            gtLog("📂 No persisted measurements file found")
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let measurements = try TapToneAnalyzer.decodeMeasurements(data)
            savedMeasurements = measurements
            gtLog("📂 Loaded \(measurements.count) persisted measurements")

            // Files written before the findPeaks duplicate fix carry one bit-identical twin
            // per capture; decoding repairs them in memory. The library is ours, so write the
            // corrected form back immediately — one save, once, and the corruption is gone.
            // A `.guitartap` opened from disk is NOT rewritten this way; it is healed on every
            // read until the user chooses to save it.
            let healedCount = measurements.filter(\.wasHealed).count
            if healedCount > 0 {
                gtLog("🩹 Healed duplicate peaks in \(healedCount) saved measurement(s) — forcing a save")
                persistMeasurements()
            }
        } catch {
            gtLog("❌ Failed to load persisted measurements: \(error)")
        }
    }
    
    /// Writes all saved measurements to `saved_measurements.json`.
    ///
    /// Uses pretty-printed, sorted-key JSON encoding with ISO-8601 dates.
    /// The JSON file is self-contained; all spectrum data is embedded in the
    /// snapshot fields.  There are no sidecar image files.
    ///
    /// Called automatically after every `saveMeasurement`, `deleteMeasurement`,
    /// and `importMeasurements` operation.
    func persistMeasurements() {
        let fileURL = TapToneAnalyzer.measurementsFileURL
        // Snapshot the array on the main thread; encoding + disk I/O run in background
        // to avoid blocking the UI (spectrum data can be several MB).
        let snapshot = savedMeasurements
        DispatchQueue.global(qos: .utility).async {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try TapToneAnalyzer.encodeMeasurements(snapshot)
                try data.write(to: fileURL, options: .atomic)
                gtLog("💾 Persisted \(snapshot.count) measurements to disk")
            } catch {
                gtLog("❌ Failed to persist measurements: \(error)")
            }
        }
    }

    // MARK: - Measurement Management
    
    /// Builds a per-phase ``SpectrumSnapshot`` from magnitude/frequency arrays.
    ///
    /// Mirrors Python's ``_make_phase_snapshot`` on the model. The helper is a
    /// model method (not a view-local function) because the model owns the
    /// per-phase spectrum data (`longitudinalSpectrum`, `crossSpectrum`,
    /// `flcSpectrum`) and builds all snapshots internally.
    ///
    /// - Parameters:
    ///   - magnitudes: dB magnitude array for this phase.
    ///   - frequencies: Hz frequency array for this phase.
    ///   - minFreq: Visible axis minimum frequency, from the view.
    ///   - maxFreq: Visible axis maximum frequency, from the view.
    ///   - minDB: Visible axis minimum dB, from the view.
    ///   - maxDB: Visible axis maximum dB, from the view.
    private func makePhaseSnapshot(
        magnitudes: [Float],
        frequencies: [Float],
        minFreq: Float,
        maxFreq: Float,
        minDB: Float,
        maxDB: Float
    ) -> SpectrumSnapshot {
        let measurementType = TapDisplaySettings.measurementType
        // Store B — the measurement's own material values drive the saved snapshot (measureFlc, a
        // capture setting, stays sourced from settings). Falls back to settings if unset (guitar).
        let mi = materialInputs
        return SpectrumSnapshot(
            frequencies: frequencies,
            magnitudes: magnitudes,
            minFreq: minFreq,
            maxFreq: maxFreq,
            minDB: minDB,
            maxDB: maxDB,
            isLogarithmic: false,
            showUnknownModes: TapDisplaySettings.showUnknownModes,
            guitarType: TapDisplaySettings.guitarType,
            measurementType: measurementType,
            plateLength: measurementType == .plate ? (mi?.lengthMM ?? TapDisplaySettings.plateLength) : nil,
            plateWidth: measurementType == .plate ? (mi?.widthMM ?? TapDisplaySettings.plateWidth) : nil,
            plateThickness: measurementType == .plate ? (mi?.thicknessMM ?? TapDisplaySettings.plateThickness) : nil,
            plateMass: measurementType == .plate ? (mi?.massG ?? TapDisplaySettings.plateMass) : nil,
            guitarBodyLength: measurementType == .plate ? (mi?.bodyLengthMM ?? TapDisplaySettings.guitarBodyLength) : nil,
            guitarBodyWidth: measurementType == .plate ? (mi?.bodyWidthMM ?? TapDisplaySettings.guitarBodyWidth) : nil,
            plateStiffnessPreset: measurementType == .plate ? (mi?.stiffnessPreset ?? TapDisplaySettings.plateStiffnessPreset) : nil,
            customPlateStiffness: measurementType == .plate ? (mi?.customStiffness ?? TapDisplaySettings.customPlateStiffness) : nil,
            measureFlc: measurementType == .plate ? TapDisplaySettings.measureFlc : nil,
            braceLength: measurementType == .brace ? (mi?.lengthMM ?? TapDisplaySettings.braceLength) : nil,
            braceWidth: measurementType == .brace ? (mi?.widthMM ?? TapDisplaySettings.braceWidth) : nil,
            braceThickness: measurementType == .brace ? (mi?.thicknessMM ?? TapDisplaySettings.braceThickness) : nil,
            braceMass: measurementType == .brace ? (mi?.massG ?? TapDisplaySettings.braceMass) : nil
        )
    }

    /// Captures the current analyser state into a new ``TapToneMeasurement``
    /// and appends it to `savedMeasurements`.
    ///
    /// For **guitar** measurements a combined `SpectrumSnapshot` is built from
    /// the frozen or live spectrum. For **plate/brace** measurements all three
    /// per-phase snapshots are built internally from `longitudinalSpectrum`,
    /// `crossSpectrum`, and `flcSpectrum` using `makePhaseSnapshot`.
    ///
    /// - Parameters:
    ///   - measurementName: A short label for where the measurement was taken,
    ///     e.g. `"Top — Bridge"`.
    ///   - notes: Free-text user notes to attach to the measurement.
    ///   - includeSpectrum: When `true`, spectrum snapshots are generated.
    ///   - spectrumSnapshot: Optional override for the guitar snapshot. If
    ///     `nil` and `includeSpectrum` is `true`, one is built from the
    ///     live/frozen FFT.
    ///   - annotationOffsets: Custom annotation drag offsets to persist. If
    ///     `nil`, `peakAnnotationOffsets` is used.
    ///   - selectedLongitudinalPeakID: UUID of the user/auto-selected
    ///     longitudinal peak (plate/brace only).
    ///   - selectedCrossPeakID: UUID of the user/auto-selected cross-grain
    ///     peak (plate only).
    ///   - selectedFlcPeakID: UUID of the user/auto-selected FLC peak (plate
    ///     only, FLC enabled).
    ///   - microphoneName: Display name of the recording microphone, for
    ///     re-connection warnings on load.
    ///   - microphoneUID: Persistent UID of the recording microphone, used
    ///     for device matching on load.
    ///   - calibrationName: Name of the active calibration profile, for
    ///     reference information.
    ///   - sampleRate: Capture sample rate in Hz; `nil` falls back to the engine's actual rate.
    ///   - minFreq: Lower bound of the saved display frequency range (Hz); `nil` uses `TapDisplaySettings.minFrequency`.
    ///   - maxFreq: Upper bound of the saved display frequency range (Hz); `nil` uses `TapDisplaySettings.maxFrequency`.
    ///   - minDB: Lower bound of the saved display magnitude range (dBFS); `nil` uses `TapDisplaySettings.minMagnitude`.
    ///   - maxDB: Upper bound of the saved display magnitude range (dBFS); `nil` uses `0.0`.
    /// The guitar peak set to persist: the full set detected down to the −100 dB display floor,
    /// not just those above the current Peak Min (Option 4; see PEAK-MIN-SEMANTICS.md in the
    /// GuitarTapWeb repo). Filtering the saved full set by Peak Min gives the same result as the
    /// live path re-detecting at that Peak Min — the local-maximum test is threshold-independent —
    /// so a reloaded measurement reveals peaks below its capture-time Peak Min exactly as the live
    /// one does.
    ///
    /// `peaksAbovePeakMin` (≥ Peak Min, carrying their UUIDs / selection / modes / annotations) are kept
    /// as-is; only the sub-Peak-Min peaks are appended, so nothing that is displayed or selected is
    /// disturbed. Applies to freshly captured guitar measurements only — a **loaded** measurement
    /// keeps its authoritative saved peaks (Re-analyze regenerates them from the spectrum), and
    /// material (plate/brace) has no full-set concept.
    /// **Now simply the stored set.** `allPeaks` IS the full −100 dB set (captured that way since the
    /// peak-lifecycle work), so the old "re-detect at −100 and append the sub-Peak-Min remainder"
    /// dance is redundant — and re-detecting minted throwaway UUIDs for the appended peaks, which is
    /// exactly the identity churn the lifecycle spec removes. Kept as a named function because the
    /// save path reads it and the intent ("save the whole set, not just what is displayed") is worth
    /// stating.
    func guitarFullSavePeaks() -> [ResonantPeak] {
        allPeaks
    }

    func saveMeasurement(
        measurementName: String? = nil,
        notes: String? = nil,
        includeSpectrum: Bool = true,
        spectrumSnapshot: SpectrumSnapshot? = nil,
        annotationOffsets: [UUID: CGPoint]? = nil,
        selectedLongitudinalPeakID: UUID? = nil,
        selectedCrossPeakID: UUID? = nil,
        selectedFlcPeakID: UUID? = nil,
        microphoneName: String? = nil,
        microphoneUID: String? = nil,
        calibrationName: String? = nil,
        sampleRate: Double? = nil,
        minFreq: Float? = nil,
        maxFreq: Float? = nil,
        minDB: Float? = nil,
        maxDB: Float? = nil
    ) {
        let measurementType = TapDisplaySettings.measurementType

        // Resolve axis range — fall back to TapDisplaySettings when not passed by view.
        // Mirrors Python: _min_freq = min_freq if min_freq is not None else TDS.min_frequency()
        let _minFreq = minFreq ?? TapDisplaySettings.minFrequency
        let _maxFreq = maxFreq ?? TapDisplaySettings.maxFrequency
        let _minDB   = minDB   ?? TapDisplaySettings.minMagnitude
        let _maxDB   = maxDB   ?? 0.0

        // Build guitar SpectrumSnapshot internally from frozen/live FFT.
        // Mirrors Python: guitar_snapshot = spectrum_snapshot or SpectrumSnapshot(...)
        let snapshot: SpectrumSnapshot?
        if includeSpectrum && measurementType.isGuitar {
            let freqs = isMeasurementComplete ? frozenFrequencies : fftAnalyzer.frequencies
            let mags  = isMeasurementComplete ? frozenMagnitudes  : fftAnalyzer.magnitudes
            snapshot = spectrumSnapshot ?? SpectrumSnapshot(
                frequencies: freqs,
                magnitudes: mags,
                minFreq: _minFreq,
                maxFreq: _maxFreq,
                minDB: _minDB,
                maxDB: _maxDB,
                isLogarithmic: false,
                showUnknownModes: TapDisplaySettings.showUnknownModes,
                guitarType: TapDisplaySettings.guitarType,
                measurementType: measurementType
            )
        } else {
            snapshot = nil
        }

        // Build per-phase snapshots internally from model state.
        // Mirrors Python: longitudinal_snapshot = self._make_phase_snapshot(...)
        let phaseArgs = (minFreq: _minFreq, maxFreq: _maxFreq, minDB: _minDB, maxDB: _maxDB)
        let longitudinalSnapshot: SpectrumSnapshot? = {
            guard includeSpectrum, !measurementType.isGuitar,
                  let spec = longitudinalSpectrum else { return nil }
            return makePhaseSnapshot(magnitudes: spec.magnitudes, frequencies: spec.frequencies,
                                     minFreq: phaseArgs.minFreq, maxFreq: phaseArgs.maxFreq,
                                     minDB: phaseArgs.minDB, maxDB: phaseArgs.maxDB)
        }()
        let crossSnapshot: SpectrumSnapshot? = {
            guard includeSpectrum, measurementType == .plate,
                  let spec = crossSpectrum else { return nil }
            return makePhaseSnapshot(magnitudes: spec.magnitudes, frequencies: spec.frequencies,
                                     minFreq: phaseArgs.minFreq, maxFreq: phaseArgs.maxFreq,
                                     minDB: phaseArgs.minDB, maxDB: phaseArgs.maxDB)
        }()
        let flcSnapshot: SpectrumSnapshot? = {
            guard includeSpectrum, measurementType == .plate,
                  let spec = flcSpectrum else { return nil }
            return makePhaseSnapshot(magnitudes: spec.magnitudes, frequencies: spec.frequencies,
                                     minFreq: phaseArgs.minFreq, maxFreq: phaseArgs.maxFreq,
                                     minDB: phaseArgs.minDB, maxDB: phaseArgs.maxDB)
        }()

        // Material (plate/brace) has no per-peak selection: persist the FULL identified peak set
        // (all of `allPeaks`), never the live `selectedPeakIDs` aggregate — that aggregate can
        // be corrupted by an intermittent phase-transition write, and material always shows all
        // peaks anyway. Guitar persists the user's actual selection. (RESPIN-1.0.2 selection design;
        // matches the web/Python save path.)
        //
        // `allPeaks` and not `peaksAbovePeakMin`: the two are equal for material (Peak Min is a
        // guitar-only control), but this is a question about the MEASUREMENT, so it reads the
        // durable set rather than relying on that equality holding forever.
        let persistedSelectedIDs: Set<UUID> = measurementType.isGuitar
            ? selectedPeakIDs
            : Set(allPeaks.map { $0.id })

        let measurement = TapToneMeasurement(
            peaks: guitarFullSavePeaks(),
            decayTime: currentDecayTime,
            measurementName: measurementName,
            notes: notes,
            spectrum: snapshot,
            annotationOffsets: annotationOffsets ?? peakAnnotationOffsets,
            tapDetectionThreshold: tapDetectionThreshold,
            numberOfTaps: numberOfTaps,
            peakMinThreshold: peakMinThreshold,
            // Include peak selections for plate and brace measurements
            selectedLongitudinalPeakID: !measurementType.isGuitar ? selectedLongitudinalPeakID : nil,
            selectedCrossPeakID: measurementType == .plate ? selectedCrossPeakID : nil,
            selectedFlcPeakID: measurementType == .plate ? selectedFlcPeakID : nil,
            longitudinalSnapshot: !measurementType.isGuitar ? longitudinalSnapshot : nil,
            crossSnapshot: measurementType == .plate ? crossSnapshot : nil,
            flcSnapshot: measurementType == .plate ? flcSnapshot : nil,
            selectedPeakIDs: persistedSelectedIDs.isEmpty ? nil : Array(persistedSelectedIDs),
            // Resolved over `allPeaks`: a selected peak sitting below Peak Min is still selected, and
            // its frequency must reach the file or the carry-forward cache is short on reload.
            selectedPeakFrequencies: persistedSelectedIDs.isEmpty ? nil : allPeaks
                .filter { persistedSelectedIDs.contains($0.id) }
                .map { $0.frequency },
            // Persist whether the guitar selection was hand-modified, so a reloaded measurement
            // re-runs auto-selection on Peak Min change (like live) when it was automatic, or
            // carries the selection forward when it was manual. Guitar only.
            userModifiedSelection: measurementType.isGuitar ? userHasModifiedPeakSelection : nil,
            annotationVisibilityMode: annotationVisibilityMode,
            peakModeOverrides: peakModeOverrides.isEmpty ? nil : peakModeOverrides,
            microphoneName: microphoneName,
            microphoneUID: microphoneUID,
            calibrationName: calibrationName,
            sampleRate: sampleRate,
            tapEntries: measurementType.isGuitar && !tapEntries.isEmpty ? tapEntries : nil
        )

        savedMeasurements.append(measurement)
        gtLog("💾 Saved measurement with \(peaksAbovePeakMin.count) peaks, type: \(measurementType.shortName)")

        // Persist to disk
        persistMeasurements()
    }
    
    /// Replaces the `measurementName` and `notes` fields of the measurement at a
    /// specific array index, preserving all other data unchanged.
    ///
    /// Uses the caller-supplied index rather than `id` matching so that
    /// duplicate imports (which share the same `id`) are treated independently.
    ///
    /// - Parameters:
    ///   - index: Position in `savedMeasurements` to update.
    ///   - measurementName: New measurement name label, or `nil` to clear it.
    ///   - notes: New free-form notes, or `nil` to clear them.
    func updateMeasurement(at index: Int,
                           measurementName: String?,
                           notes: String?) {
        guard savedMeasurements.indices.contains(index) else { return }
        savedMeasurements[index] = savedMeasurements[index].with(measurementName: measurementName, notes: notes)
        persistMeasurements()
    }

    /// Removes the measurement at the given index from `savedMeasurements` and persists the change.
    ///
    /// Using a positional index rather than id matching ensures that duplicate imports
    /// (which share the same id) are treated independently — only the specific entry
    /// at `index` is removed.
    ///
    /// - Parameter index: The position in `savedMeasurements` to delete.
    func deleteMeasurement(at index: Int) {
        guard savedMeasurements.indices.contains(index) else { return }
        savedMeasurements.remove(at: index)
        persistMeasurements()
    }
    
    /// Decodes a JSON data blob into ``TapToneMeasurement`` records and
    /// appends them to `savedMeasurements`.
    ///
    /// After import, the UID of each measurement's recording microphone is
    /// compared against `fftAnalyzer.availableInputDevices`. If any microphone
    /// is missing, `microphoneWarning` is set with a list of missing device
    /// names.
    ///
    /// - Parameters:
    ///   - jsonData: Raw JSON data containing an array of encoded
    ///     ``TapToneMeasurement`` values.
    /// - Returns: The array of newly decoded measurements.
    /// - Throws: A decoding error if `jsonData` is not a valid
    ///   `[TapToneMeasurement]` JSON array.
    func importMeasurements(from jsonData: Data) throws -> [TapToneMeasurement] {
        let measurements = try TapToneAnalyzer.decodeMeasurements(jsonData)
        
        // Add imported measurements
        savedMeasurements.append(contentsOf: measurements)
        
        // Persist to disk
        persistMeasurements()

        // Warn if any imported measurement's microphone is not currently available.
        // A device is considered available if its UID matches (Swift/CoreAudio measurements) OR
        // its name matches (Python companion app measurements, which store a "Name:SampleRate"
        // fingerprint as the UID rather than a CoreAudio UID).
        let availableUIDs  = Set(fftAnalyzer.availableInputDevices.map(\.uid))
        let availableNames = Set(fftAnalyzer.availableInputDevices.map(\.name))
        var missingNames: [String] = []
        for m in measurements {
            if let uid = m.microphoneUID {
                let foundByUID  = availableUIDs.contains(uid)
                let foundByName = !foundByUID && availableNames.contains(m.microphoneName ?? "")
                if !foundByUID && !foundByName {
                    let name = m.microphoneName ?? uid
                    if !missingNames.contains(name) {
                        missingNames.append(name)
                    }
                }
            }
        }
        if !missingNames.isEmpty {
            let list = missingNames.joined(separator: ", ")
            // Report UNKNOWN, not "unplugged": a no-match can equally mean the device is attached
            // under a different name on this platform (the same UMIK-1 is "Umik-1  Gain: 18dB" here
            // and "Microphone (Umik-1  Gain: 18dB)" on Windows). Impact stated so the reader can
            // judge — frequencies are essentially mic-independent; levels, trigger and faint peaks
            // are not. Mirrors the Python + web wording.
            microphoneWarning = "Recorded with \(list). No connected microphone matches that name — it may be unplugged, or attached under a different name on this platform. Peak frequencies should still be comparable; input levels, the tap threshold, and faint peaks (such as FLC) may differ."
        }

        gtLog("📥 Imported \(measurements.count) measurements")
        return measurements
    }
    
    /// Restores the full analyser state from a saved measurement, entering
    /// a frozen "viewing" mode.
    ///
    /// The restoration sequence:
    /// 1. Peaks, decay time, and per-phase spectra are restored.
    /// 2. Display and analysis settings are published via `loaded*` properties
    ///    so that bound UI controls update without triggering a new tap cycle.
    /// 3. Phase-specific peak selections (`selectedLongitudinalPeak`,
    ///    `selectedCrossPeak`, `selectedFlcPeak`) are resolved by UUID into
    ///    the restored peak array.
    /// 4. Annotation offsets, selected peak IDs, annotation visibility mode,
    ///    and mode overrides are all restored.
    /// 5. Tap detection is disabled (`isDetecting = false`, `currentTapCount = 0`).
    /// 6. The recording microphone is auto-selected if connected; otherwise
    ///    `microphoneWarning` is set.
    ///
    /// - Parameter measurement: The ``TapToneMeasurement`` to load.
    func loadMeasurement(_ measurement: TapToneMeasurement) {
        gtLog("🔄 Loading measurement...")

        // Comparison records: restore the overlay spectra directly from the saved entries
        // and return early — no peak/spectrum restoration needed for the regular path.
        if let entries = measurement.comparisonEntries {
            comparisonSpectra = entries.map { entry in
                let c = entry.colorComponents
                let color = Color(red: c.indices.contains(0) ? c[0] : 0,
                                  green: c.indices.contains(1) ? c[1] : 0,
                                  blue: c.indices.contains(2) ? c[2] : 1,
                                  opacity: c.indices.contains(3) ? c[3] : 1)
                return (magnitudes: entry.snapshot.magnitudes,
                        frequencies: entry.snapshot.frequencies,
                        color: color, label: entry.label,
                        peaks: entry.peaks, guitarType: entry.guitarType,
                        modeIDs: entry.modePeakIDs ?? [:])   // healed on decode; [:] only if truly absent
            }
            comparisonSnapshots = entries.map(\.snapshot)
            let snaps = entries.map(\.snapshot)
            if let minF = snaps.map(\.minFreq).min(), let maxF = snaps.map(\.maxFreq).max(),
               let minD = snaps.map(\.minDB).min(), let maxD = snaps.map(\.maxDB).max() {
                setLoadedAxisRange(minFreq: minF, maxFreq: maxF, minDB: minD, maxDB: maxD)
            }
            loadedMeasurementName = measurement.measurementName.flatMap { $0.isEmpty ? nil : $0 }
            loadedNotes = measurement.notes.flatMap { $0.isEmpty ? nil : $0 }
            // Clear any per-tap entries from a previously loaded multi-tap measurement so
            // the PDF export routing doesn't misidentify this as a multi-tap measurement.
            tapEntries = []
            showingMultiTapComparison = false
            displayMode = .comparison
            return
        }

        // Suppress recalculateFrozenPeaksIfNeeded() for the duration of the load.
        // The saved peaks are already correct; re-running findPeaks() would
        // generate wrong UUIDs and may classify with a stale guitar type.
        isLoadingMeasurement = true
        defer { isLoadingMeasurement = false }

        // Loading a new measurement exits comparison mode.
        // Clear the frozen spectrum immediately so there is no window where displayMode
        // is .frozen but frozenFrequencies/Magnitudes still hold the previous measurement's
        // data — that transient state causes a ghost spectrum artifact in the chart.
        comparisonSpectra = []
        comparisonSnapshots = []
        setFrozenSpectrum(frequencies: [], magnitudes: [])
        displayMode = .frozen

        // Track the original timestamp so the Results-panel PDF can use it
        sourceMeasurementTimestamp = measurement.timestamp

        // Expose the measurement name so the chart title can reflect it
        let name = measurement.measurementName.flatMap { $0.isEmpty ? nil : $0 }
        loadedMeasurementName = name

        // Expose the notes so re-saving the loaded measurement keeps them (R10).
        loadedNotes = measurement.notes.flatMap { $0.isEmpty ? nil : $0 }

        // Restore peaks
        allPeaks = measurement.peaks
        
        // Restore decay time
        currentDecayTime = measurement.decayTime
        
        // Determine if this is a plate/brace measurement with per-phase spectra
        let hasMaterialSpectra = measurement.longitudinalSnapshot != nil
        
        // Restore per-phase spectra for plate/brace measurements
        if let longSnap = measurement.longitudinalSnapshot {
            longitudinalSpectrum = (magnitudes: longSnap.magnitudes, frequencies: longSnap.frequencies)
            longitudinalPeaks = [] // peaks come from peaksAbovePeakMin
        } else {
            longitudinalSpectrum = nil
            longitudinalPeaks = []
        }
        if let crossSnap = measurement.crossSnapshot {
            crossSpectrum = (magnitudes: crossSnap.magnitudes, frequencies: crossSnap.frequencies)
            crossPeaks = []
        } else {
            crossSpectrum = nil
            crossPeaks = []
        }
        if let flcSnap = measurement.flcSnapshot {
            flcSpectrum = (magnitudes: flcSnap.magnitudes, frequencies: flcSnap.frequencies)
            flcPeaks = []
        } else {
            flcSpectrum = nil
            flcPeaks = []
        }
        
        // For plate/brace: use per-phase spectra for display (no frozen spectrum needed).
        // For guitar: restore the single frozen spectrum as before.
        // Use setFrozenSpectrum so both arrays update in one objectWillChange notification —
        // assigning them separately produces a transient length mismatch that causes
        // SwiftUI Charts to render spurious vertical line artifacts.
        if hasMaterialSpectra {
            setFrozenSpectrum(frequencies: [], magnitudes: [])
            materialTapPhase = .complete
        } else if let snapshot = measurement.spectrumSnapshot {
            setFrozenSpectrum(frequencies: snapshot.frequencies, magnitudes: snapshot.magnitudes)
            // A loaded measurement is complete. Mark the phase complete so the
            // displaySpectrum live-FFT race guard (frozenFrequencies.isEmpty &&
            // materialTapPhase != .complete) doesn't blank a guitar spectrum that
            // is loaded while the previous measurement type was plate/brace.
            materialTapPhase = .complete
        } else {
            setFrozenSpectrum(frequencies: [], magnitudes: [])
        }
        
        // Restore display settings from any available snapshot (prefer longitudinal for plate/brace)
        let settingsSnapshot = measurement.longitudinalSnapshot ?? measurement.spectrumSnapshot
        if let snapshot = settingsSnapshot {
            // Restore display ranges - use setLoadedAxisRange so all four bounds are
            // published in a single objectWillChange notification, preventing transient
            // mismatched-axis states that cause SwiftUI Charts rendering artifacts.
            gtLog("  📊 Publishing display ranges: \(snapshot.minFreq)-\(snapshot.maxFreq) Hz, \(snapshot.minDB)-\(snapshot.maxDB) dB")
            setLoadedAxisRange(minFreq: snapshot.minFreq, maxFreq: snapshot.maxFreq,
                               minDB: snapshot.minDB, maxDB: snapshot.maxDB)
            
            // Restore showUnknownModes setting if available
            if let showUnknown = snapshot.showUnknownModes {
                gtLog("  👁️ Publishing showUnknownModes: \(showUnknown)")
                loadedShowUnknownModes = showUnknown
            }
            
            // Restore guitarType setting if available.
            // Apply directly to TapDisplaySettings now (synchronous) so that
            // reclassifyPeaks() below uses the correct mode ranges.  Also
            // publish loadedGuitarType so the view's bound control updates.
            if let guitarType = snapshot.guitarType {
                gtLog("  🎸 Publishing guitarType: \(guitarType.rawValue)")
                TapDisplaySettings.guitarType = guitarType
                loadedGuitarType = guitarType
            }
            
            // Restore measurementType setting if available.
            // Apply directly so that reclassifyPeaks() uses the correct type.
            if let measurementType = snapshot.measurementType {
                gtLog("  📐 Publishing measurementType: \(measurementType.shortName)")
                TapDisplaySettings.measurementType = measurementType
                loadedMeasurementType = measurementType
            }
            
            // Store B ← the file's own material inputs (never the live Settings defaults). The calc,
            // Results panel, and Save all read this, so a loaded measurement's numbers come from the
            // file and loading never disturbs the Settings defaults (Store A). Replaces the old
            // loaded*-dimension → TapDisplaySettings writes that used to clobber the user's defaults.
            // See GuitarTapWeb/Development/MEASUREMENT-DIMENSIONS-SPEC.md.
            if let mt = snapshot.measurementType, !mt.isGuitar {
                let brace = mt.isBrace
                materialInputs = MaterialMeasurementInputs(
                    lengthMM:    (brace ? snapshot.braceLength    : snapshot.plateLength)    ?? 0,
                    widthMM:     (brace ? snapshot.braceWidth     : snapshot.plateWidth)     ?? 0,
                    thicknessMM: (brace ? snapshot.braceThickness : snapshot.plateThickness) ?? 0,
                    massG:       (brace ? snapshot.braceMass      : snapshot.plateMass)      ?? 0,
                    bodyLengthMM: snapshot.guitarBodyLength ?? TapDisplaySettings.guitarBodyLength,
                    bodyWidthMM:  snapshot.guitarBodyWidth  ?? TapDisplaySettings.guitarBodyWidth,
                    stiffnessPreset: snapshot.plateStiffnessPreset ?? TapDisplaySettings.plateStiffnessPreset,
                    customStiffness: snapshot.customPlateStiffness ?? TapDisplaySettings.customPlateStiffness
                )
            }
        } else {
            // Old-format measurement: no snapshot, so no axis range to restore.
            // Explicitly reset to TapDisplaySettings defaults so the view's @State
            // axis vars are always published when loading — without this, loading
            // an old measurement leaves the axis range from the *previous* measurement
            // in place, causing the next load (which does have a snapshot) to briefly
            // render its spectrum against a wrong axis range before onReceive fires.
            gtLog("  ⚠️ No spectrum snapshot in measurement — resetting axis range to defaults")
            setLoadedAxisRange(minFreq: TapDisplaySettings.minFrequency,
                               maxFreq: TapDisplaySettings.maxFrequency,
                               minDB: TapDisplaySettings.minMagnitude,
                               maxDB: TapDisplaySettings.maxMagnitude)
        }
        
        // Restore plate/brace peak selections directly into the model properties
        // that effectiveLongitudinalPeakID etc. read from. Resolved against the durable set: which
        // peak is L / C / FLC is a fact about the measurement, not a display question.
        selectedLongitudinalPeak = measurement.selectedLongitudinalPeakID
            .flatMap { id in allPeaks.first(where: { $0.id == id }) }
        selectedCrossPeak = measurement.selectedCrossPeakID
            .flatMap { id in allPeaks.first(where: { $0.id == id }) }
        selectedFlcPeak = measurement.selectedFlcPeakID
            .flatMap { id in allPeaks.first(where: { $0.id == id }) }
        userSelectedLongitudinalPeakID = nil
        userSelectedCrossPeakID = nil
        userSelectedFlcPeakID = nil
        gtLog("  🔵 Restored longitudinal peak: \(selectedLongitudinalPeak?.frequency ?? -1) Hz")
        gtLog("  🟠 Restored cross-grain peak: \(selectedCrossPeak?.frequency ?? -1) Hz")
        gtLog("  🟣 Restored FLC peak: \(selectedFlcPeak?.frequency ?? -1) Hz")
        
        // Stop tap detection when loading a measurement (frozen state).
        // Clear isDetectionPaused too — if a tap sequence was paused before loading,
        // the analyzeMagnitudes loop would otherwise keep overwriting peaksAbovePeakMin
        // with fresh live-audio peaks on every FFT frame.
        isDetecting = false
        isDetectionPaused = false
        isMeasurementComplete = true
        currentTapCount = 0
        tapProgress = 0.0
        statusMessage = "Loaded measurement (frozen). Press \u{2018}New Tap\u{2019} to start a new measurement."
        gtLog("  🧊 Spectrum frozen, tap detection disabled")
        
        // Restore annotation offsets
        if let offsets = measurement.peakAnnotationOffsets {
            peakAnnotationOffsets = offsets
            gtLog("  🏷️ Restored \(offsets.count) annotation offsets")
        }
        
        // Retain the original saved peaks so recalculateFrozenPeaksIfNeeded() can
        // remap selectedPeakIDs, peakAnnotationOffsets, and peakModeOverrides by
        // frequency when Peak Min changes generate new UUIDs.
        loadedMeasurementPeaks = measurement.peaks

        // Restore selected peak IDs; if none saved, default to selecting all peaks.
        // Material (plate/brace) has no per-peak selection: always restore ALL peaks, ignoring the
        // saved `selectedPeakIDs` aggregate (which can be corrupted by the phase-transition glitch).
        // This HEALS existing corrupt files on load. Guitar restores the user's saved selection.
        // (RESPIN-1.0.2; matches the web/Python read path.)
        if measurement.isMaterial {
            selectedPeakIDs = Set(measurement.peaks.map { $0.id })
        } else if let saved = measurement.selectedPeakIDs {
            selectedPeakIDs = Set(saved)
        } else {
            selectedPeakIDs = Set(measurement.peaks.map { $0.id })
        }
        // Restore whether the selection was user-modified. A manual selection uses
        // frequency-proximity carry-forward on Peak Min change; an automatic one re-runs
        // auto-selection (so a peak revealed by lowering Peak Min is selected as its mode winner,
        // matching a live measurement). Files saved before this field default to `true` (manual),
        // preserving prior behaviour exactly.
        userHasModifiedPeakSelection = measurement.userModifiedSelection ?? true
        // Seed the stable frequency cache from the loaded selection so that
        // recalculateFrozenPeaksIfNeeded() can carry forward selections even
        // after Peak Min is raised above all peaks (at which point selectedPeakIDs
        // holds stale UUIDs that no longer exist in the re-analyzed peak set).
        selectedPeakFrequencies = measurement.peaks
            .filter { selectedPeakIDs.contains($0.id) }
            .map { $0.frequency }
        gtLog("  ⭐ Restored \(selectedPeakIDs.count) selected peaks")

        // Restore annotation visibility mode; default to .all if not saved
        annotationVisibilityMode = measurement.annotationVisibilityMode ?? .all
        TapDisplaySettings.annotationVisibilityMode = annotationVisibilityMode
        gtLog("  👁️ Restored annotation visibility: \(annotationVisibilityMode.label)")

        // Restore per-peak mode overrides; nil / empty → all peaks auto-classify
        if let overrides = measurement.peakModeOverrides, !overrides.isEmpty {
            applyModeOverrides(overrides)
            gtLog("  🏷️ Restored \(overrides.count) mode overrides")
        } else {
            peakModeOverrides = [:]
        }

        // Rebuild identifiedModes from the restored peaks so that calculateTapToneRatio()
        // and other helpers work correctly immediately after load (without needing a new tap).
        // This must run after peakModeOverrides is set so reclassifyPeaks() can incorporate them.
        reclassifyPeaks()
        gtLog("  🔬 Reclassified \(identifiedModes.count) modes after load")
        
        // Restore analysis settings if available — set both internal and published values
        if let threshold = measurement.tapDetectionThreshold {
            gtLog("  🎯 Publishing tap threshold: \(threshold) dB")
            tapDetectionThreshold = threshold
            loadedTapDetectionThreshold = threshold
        } else {
            gtLog("  ⚠️ No tap threshold in measurement")
        }
        
        if let taps = measurement.numberOfTaps {
            gtLog("  🔢 Publishing number of taps: \(taps)")
            numberOfTaps = taps
            loadedNumberOfTaps = taps
        } else {
            gtLog("  ⚠️ No number of taps in measurement")
        }

        if let threshold = measurement.peakMinThreshold {
            gtLog("  📊 Publishing peak threshold: \(threshold) dB")
            peakMinThreshold = threshold
            loadedPeakThreshold = threshold
        } else {
            gtLog("  ⚠️ No peak threshold in measurement")
        }
        
        // Auto-select the recorded microphone if it is connected; warn if it is not.
        // UID match is tried first (Swift/CoreAudio measurements). If that fails, fall back to
        // name matching so that measurements saved by the Python companion app — which stores a
        // "Name:SampleRate" fingerprint rather than a CoreAudio UID — still resolve correctly.
        if let uid = measurement.microphoneUID {
            let name = measurement.microphoneName ?? uid
            let matchByUID  = fftAnalyzer.availableInputDevices.first(where: { $0.uid == uid })
            let matchByName = matchByUID == nil
                ? fftAnalyzer.availableInputDevices.first(where: { $0.name == measurement.microphoneName })
                : nil
            if let match = matchByUID ?? matchByName {
                // Device is connected — switch to it; its paired calibration loads automatically.
                if fftAnalyzer.selectedInputDevice?.uid != match.uid {
                    try? fftAnalyzer.setInputDevice(match)
                    gtLog("🎤 Auto-selected microphone '\(name)' for loaded measurement")
                }
                // Same microphone — but flag a calibration or sample-rate difference,
                // since a newly captured tap would then not match this saved measurement.
                var diffs: [String] = []
                if measurement.calibrationName != fftAnalyzer.activeCalibration?.name {
                    diffs.append("calibration")
                }
                if let recordedRate = measurement.sampleRate,
                   Int(recordedRate.rounded()) != Int(fftAnalyzer.actualSampleRate.rounded()) {
                    diffs.append("sample rate")
                }
                microphoneWarning = diffs.isEmpty
                    ? nil
                    : "This measurement was recorded with a different \(diffs.joined(separator: " and ")). A newly captured tap may not match the saved result."
            } else {
                // See the note at the missingNames warning above: a no-match cannot distinguish
                // "unplugged" from "attached under a different name on this platform".
                microphoneWarning = "Recorded with '\(name)'. No connected microphone matches that name — it may be unplugged, or attached under a different name on this platform. Peak frequencies should still be comparable; input levels, the tap threshold, and faint peaks (such as FLC) may differ."
            }
        }

        showLoadedSettingsWarning = true

        // Restore per-tap spectra so the multi-tap comparison toggle is available after reload.
        // tapEntries is nil for single-tap, plate/brace, and older saved measurements.
        tapEntries = measurement.tapEntries ?? []
        // Always start with the averaged view — the user can toggle to per-tap if desired.
        showingMultiTapComparison = false

        // The saved per-tap peaks are restored as-is and never re-detected. They are the
        // measurement's own record, exactly like `measurement.peaks` — see
        // Development/PEAK-LIFECYCLE-SPEC.md §5. This previously called
        // `recalculateTapEntryPeaks()` to "re-run findPeaks with the saved threshold", which
        // re-analysed a loaded measurement and then wrote the filtered result back into
        // `tapEntries` — truncating the saved full set on the next save.

        gtLog("✅ Loaded measurement with \(measurement.peaks.count) peaks (frozen)")
        if !tapEntries.isEmpty {
            gtLog("  📋 Restored \(tapEntries.count) per-tap entries for multi-tap comparison")
        }
    }

    /// Encodes a single measurement as a pretty-printed JSON string and
    /// delivers it to `completion` on the main thread.
    ///
    /// Encoding is done on a background queue to avoid blocking the main
    /// thread for large measurements with many peaks.
    ///
    /// - Parameters:
    ///   - measurement: The ``TapToneMeasurement`` to export.
    ///   - completion: Called on the main thread with the JSON string and the
    ///     original measurement.
    func exportMeasurement(_ measurement: TapToneMeasurement, completion: @escaping (String, TapToneMeasurement) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let data = try? TapToneAnalyzer.encodeMeasurements([measurement]),
               let json = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    completion(json, measurement)
                }
            }
        }
    }

    /// Encodes the whole library (`savedMeasurements`) as a `.guitartap` JSON array — the same
    /// form written to `saved_measurements.json` — for Export All / backup / migration.
    func exportAllMeasurements(completion: @escaping (String) -> Void) {
        let snapshot = savedMeasurements
        DispatchQueue.global(qos: .userInitiated).async {
            if let data = try? TapToneAnalyzer.encodeMeasurements(snapshot),
               let json = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    completion(json)
                }
            }
        }
    }
    
    /// Simple string-based JSON import for quick in-app sharing.
    ///
    /// Decodes a JSON string containing an array of ``TapToneMeasurement``
    /// values and appends them to `savedMeasurements`. No image files are
    /// loaded and no microphone warnings are generated.
    ///
    /// - Parameter json: UTF-8 JSON string representing `[TapToneMeasurement]`.
    /// - Returns: `true` if decoding succeeded and measurements were appended;
    ///   `false` otherwise.
    ///
    /// - SeeAlso: ``importMeasurements(from:)`` for the full import path with
    ///   image loading and microphone warning support.
    func importMeasurements(json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let measurements = try? TapToneAnalyzer.decodeMeasurements(data) else {
            return false
        }
        
        savedMeasurements.append(contentsOf: measurements)
        persistMeasurements()
        return true
    }

    // MARK: - Comparison Overlay

    /// Color palette for comparison overlays (cycles if more than 5 measurements).
    private static let multiTapPalette: [Color] = [.blue, .orange, .green, .purple, .teal]
    /// Averaged row color for multi-tap comparison charts and PDF exports.
    static let multiTapAvgColor: Color = Color(red: 1.0, green: 0.85, blue: 0.0)

    /// Short label for a measurement in the comparison legend.
    private func comparisonLabel(for measurement: TapToneMeasurement) -> String {
        if let measurementName = measurement.measurementName, !measurementName.isEmpty {
            return measurementName
        }
        return DateDisplay.compact(measurement.timestamp)
    }

    /// Loads the given guitar measurements as comparison overlays in the main chart.
    ///
    /// Only measurements with a `spectrumSnapshot` are included. The comparison
    /// spectra are shown via the main `SpectrumView`'s existing `materialSpectra`
    /// path; calling this does not affect the current tap/measurement state.
    ///
    /// Also updates `loadedMin/MaxFreq` and `loadedMin/MaxDB` to the union of all
    /// snapshot display ranges so the main view's axis state is adjusted automatically.
    ///
    /// - Parameter measurements: The guitar measurements to overlay.
    func loadComparison(measurements: [TapToneMeasurement]) {
        // Clear any active multi-tap comparison so the Taps button and per-tap table
        // are hidden when the saved-measurement comparison is displayed.
        tapEntries = []
        showingMultiTapComparison = false

        let withSnapshots = measurements.filter { $0.spectrumSnapshot != nil }

        // Build base labels, then disambiguate duplicates so Swift Charts treats each
        // series as distinct.  Without this, two measurements with the same measurement name
        // (or both with no measurement name) produce the same label and Charts collapses them
        // into a single series, making only one overlay visible.
        let baseLabels = withSnapshots.map { comparisonLabel(for: $0) }
        var labelCounts: [String: Int] = [:]
        var labelOccurrence: [String: Int] = [:]
        for label in baseLabels { labelCounts[label, default: 0] += 1 }
        let uniqueLabels = baseLabels.map { label -> String in
            guard labelCounts[label]! > 1 else { return label }
            labelOccurrence[label, default: 0] += 1
            return "\(label) (\(labelOccurrence[label]!))"
        }

        let spectraAndSnapshots: [(entry: (magnitudes: [Float], frequencies: [Float], color: Color, label: String, peaks: [ResonantPeak], guitarType: GuitarType?, modeIDs: [String: UUID]), snapshot: SpectrumSnapshot)] = withSnapshots.enumerated().map { index, measurement in
            let snap = measurement.spectrumSnapshot!
            let color = Self.multiTapPalette[index % Self.multiTapPalette.count]
            let selectedIDs = measurement.effectiveSelectedPeakIDs
            let selectedPeaks = measurement.peaks.filter { selectedIDs.contains($0.id) }
            // Resolve the definitive Air/Top/Back from the SOURCE measurement — its selection AND its
            // overrides — so the comparison shows what that measurement shows, and store it as
            // mode→peakID (self-describing; survives save/load without re-running classifyAll).
            var modeIDs: [String: UUID] = [:]
            for mode in [GuitarMode.air, .top, .back] where measurement.definitivePeak(for: mode) != nil {
                modeIDs[mode.rawValue] = measurement.definitivePeak(for: mode)!.id
            }
            let entry = (magnitudes: snap.magnitudes, frequencies: snap.frequencies,
                         color: color, label: uniqueLabels[index],
                         peaks: selectedPeaks, guitarType: snap.guitarType, modeIDs: modeIDs)
            return (entry: entry, snapshot: snap)
        }
        comparisonSpectra = spectraAndSnapshots.map(\.entry)
        comparisonSnapshots = spectraAndSnapshots.map(\.snapshot)
        loadedMeasurementName = nil
        loadedNotes = nil

        // Broadcast the union axis ranges — use setLoadedAxisRange so all four bounds
        // are published atomically, preventing transient axis mismatches.
        let snapshots = withSnapshots.compactMap { $0.spectrumSnapshot }
        if !snapshots.isEmpty,
           let minF = snapshots.map(\.minFreq).min(),
           let maxF = snapshots.map(\.maxFreq).max(),
           let minD = snapshots.map(\.minDB).min(),
           let maxD = snapshots.map(\.maxDB).max() {
            setLoadedAxisRange(minFreq: minF, maxFreq: maxF, minDB: minD, maxDB: maxD)
        }

        displayMode = comparisonSpectra.isEmpty ? .live : .comparison
    }

    /// Saves the current comparison as a first-class measurement record.
    ///
    /// Each entry in `comparisonSpectra` becomes a `ComparisonEntry` storing the full
    /// spectrum snapshot, selected peaks, guitar type, label, and chart color components.
    /// The resulting `TapToneMeasurement` is appended to `savedMeasurements` and persisted.
    ///
    /// - Parameters:
    ///   - measurementName: User-supplied name for the comparison (e.g. "Pre/Post Bracing").
    ///   - notes: Optional free-form notes.
    func saveComparison(measurementName: String? = nil, notes: String? = nil) {
        guard !comparisonSpectra.isEmpty,
              comparisonSnapshots.count == comparisonSpectra.count else { return }

        let entries: [ComparisonEntry] = comparisonSpectra.enumerated().map { index, entry in
            // Resolve Color → RGBA components using CGColor.
            // The fixed 5-color palette (blue/orange/green/purple/teal) round-trips exactly.
            let cgColor: CGColor = entry.color.cgColor ?? entry.color.resolve(in: .init()).cgColor
            let comps: [Double]
            if let components = cgColor.components, components.count >= 3 {
                comps = [Double(components[0]), Double(components[1]),
                         Double(components[2]), components.count >= 4 ? Double(components[3]) : 1.0]
            } else {
                // Fallback: default to blue with full opacity
                comps = [0.0, 0.0, 1.0, 1.0]
            }
            return ComparisonEntry(
                id: UUID(),
                label: entry.label,
                colorComponents: comps,
                snapshot: comparisonSnapshots[index],
                peaks: entry.peaks,
                guitarType: entry.guitarType,
                sourceMeasurementID: nil,
                modePeakIDs: entry.modeIDs   // persist the definitive modes — self-describing file
            )
        }

        let record = TapToneMeasurement(
            peaks: [],
            measurementName: measurementName,
            notes: notes,
            comparisonEntries: entries
        )
        savedMeasurements.append(record)
        persistMeasurements()
    }

    /// Removes all comparison overlay spectra from the main chart.
    func clearComparison() {
        comparisonSpectra = []
        comparisonSnapshots = []
        displayMode = .live
    }

    // MARK: - Multi-Tap Comparison Chart Overlays

    /// Activates or deactivates the per-tap spectrum overlays on the main chart.
    ///
    /// When `showingMultiTapComparison` is turned on, each `TapEntry` is converted to
    /// a `comparisonSpectra` entry (using the existing 5-color palette) and the averaged
    /// frozen spectrum is appended as the final entry with a bold yellow color.
    ///
    /// When turned off, `comparisonSpectra` is cleared and `displayMode` is restored to
    /// `.frozen` so the chart reverts to the averaged spectrum only.
    ///
    /// **Display mode note:** This method sets `displayMode = .comparison` while overlays
    /// are active so the chart's `materialSpectra` computed property feeds `comparisonSpectra`
    /// to the renderer. The Results panel is gated by `showingMultiTapComparison`, not
    /// `displayMode`, so the guitar summary footer and peak list remain visible and the
    /// "Comparison" mode badge is suppressed. Setting `.comparison` here is intentional and
    /// does not conflict with the guitar-mode Results panel layout.
    ///
    /// Call this when `showingMultiTapComparison` is toggled by the Results panel.
    func applyMultiTapComparisonOverlays(enabled: Bool) {
        guard enabled else {
            comparisonSpectra = []
            comparisonSnapshots = []
            // Restore frozen display mode so the chart goes back to the averaged spectrum only.
            displayMode = .frozen
            return
        }
        guard !tapEntries.isEmpty else { return }

        // This populates `comparisonSpectra` only to feed the CHART overlay (magnitudes/colour/label).
        // The multi-tap Air/Top/Back table is MultiTapComparisonResultsView, not ComparisonResultsView,
        // so the `modeIDs` element is unused here — `[:]` is correct.
        var entries: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String, peaks: [ResonantPeak], guitarType: GuitarType?, modeIDs: [String: UUID])] = []
        var snapshots: [SpectrumSnapshot] = []

        for (index, entry) in tapEntries.enumerated() {
            let color = Self.multiTapPalette[index % Self.multiTapPalette.count]
            let selectedIDs = Set(entry.selectedPeakIDs)
            let selectedPeaks = entry.peaks.filter { selectedIDs.contains($0.id) }
            entries.append((
                magnitudes: entry.snapshot.magnitudes,
                frequencies: entry.snapshot.frequencies,
                color: color,
                label: "Tap \(entry.tapIndex)",
                peaks: selectedPeaks,
                guitarType: entry.snapshot.guitarType,
                modeIDs: [:]
            ))
            snapshots.append(entry.snapshot)
        }

        // Append the averaged result as the final overlay so it renders on top.
        // Use a bold yellow so it stands out against the per-tap palette (blue/orange/green/purple/teal).
        let avgColor = Self.multiTapAvgColor
        // The same rule the on-screen table and the PDF use — selection resolves over the durable
        // set, so the averaged overlay does not lose a selected peak when Peak Min rises above it.
        let avgSelectedPeaks = selectedPeaks
        let avgSnap = SpectrumSnapshot(
            frequencies: frozenFrequencies,
            magnitudes: frozenMagnitudes,
            minFreq: TapDisplaySettings.minFrequency,
            maxFreq: TapDisplaySettings.maxFrequency,
            minDB: TapDisplaySettings.minMagnitude,
            maxDB: 0,
            isLogarithmic: false,
            showUnknownModes: TapDisplaySettings.showUnknownModes,
            guitarType: TapDisplaySettings.guitarType,
            measurementType: TapDisplaySettings.measurementType
        )
        entries.append((
            magnitudes: frozenMagnitudes,
            frequencies: frozenFrequencies,
            color: avgColor,
            label: "Averaged",
            peaks: avgSelectedPeaks,
            guitarType: TapDisplaySettings.guitarType,
            modeIDs: [:]
        ))
        snapshots.append(avgSnap)

        comparisonSpectra = entries
        comparisonSnapshots = snapshots
        // Switch to comparison display mode so the chart's materialSpectra computed property
        // picks up the comparisonSpectra overlays. The Results panel uses showingMultiTapComparison
        // (not displayMode) to gate its content, so guitar summary etc. remain visible.
        displayMode = .comparison
    }
}
