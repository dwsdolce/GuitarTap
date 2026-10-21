//
//  TapToneAnalyzer+MeasurementManagement.swift
//  GuitarTap
//
//  Created on 1/25/26.
//
// @parity model/measurement-management tests=test/measurement-load,test/import-persistence,test/comparison

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
        if TestSandbox.isActive {
            // Per-process, so concurrent test runs never share or delete each other's measurements
            // file — see TestSandbox.
            return FileManager.default.temporaryDirectory
                .appendingPathComponent(TestSandbox.name("com.guitartap.tests"))
                .appendingPathComponent("saved_measurements.json")
        }
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("saved_measurements.json")
    }
    
    /// The queue every library write runs on, in order.
    nonisolated static let persistQueue = DispatchQueue(label: "com.guitartap.persistMeasurements", qos: .utility)

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

    /// A library or `.guitartap` file as read: the measurements that could be read, in the file's order,
    /// and why each of the others could not.
    struct DecodedLibrary {
        /// The entries that decoded.
        var measurements: [TapToneMeasurement]
        /// The reason each entry that did not decode could not be read, in the file's order.
        var unreadable: [Error]
    }

    /// The single JSON decoding of the measurement library.
    ///
    /// Every read path — loading `saved_measurements.json` and importing a `.guitartap`
    /// file or string — goes through this. Counterpart to ``encodeMeasurements(_:)``.
    ///
    /// The file must be a JSON list of measurements; anything else throws. Each entry is decoded on its
    /// own, so one that cannot be read — an id that is not a UUID, no spectrum — costs only itself: its
    /// reason is returned in `unreadable` and the rest are read.
    static func decodeLibrary(_ data: Data) throws -> DecodedLibrary {
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw DecodingError.typeMismatch([TapToneMeasurement].self, DecodingError.Context(
                codingPath: [], debugDescription: "A .guitartap file is a list of measurements."))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var library = DecodedLibrary(measurements: [], unreadable: [])
        for entry in entries {
            let json = try JSONSerialization.data(withJSONObject: entry, options: [.fragmentsAllowed])
            do {
                library.measurements.append(try decoder.decode(TapToneMeasurement.self, from: json))
            } catch let error as DecodingError {
                // An id that is not a UUID is named, as every edition names it.
                library.unreadable.append(InvalidIDError.from(error, in: json) ?? error)
            } catch {
                library.unreadable.append(error)
            }
        }
        return library
    }

    /// The file's measurements, every one of them: ``decodeLibrary(_:)``, throwing the first unreadable
    /// entry's reason if there is one.
    static func decodeMeasurements(_ data: Data) throws -> [TapToneMeasurement] {
        let library = try decodeLibrary(data)
        if let first = library.unreadable.first { throw first }
        return library.measurements
    }

    /// Why one entry of a file could not be read, in the words an import's message uses: the id that is
    /// not a UUID, or "no spectrum"; nil for any other reason.
    static func unreadableReason(_ error: Error) -> String? {
        if let invalid = error as? InvalidIDError { return "\(invalid)" }
        if let noSpectrum = error as? NoSpectrumError { return "\(noSpectrum)" }
        return nil
    }

    /// The message an import that failed shows, the same in every edition: the file is not a valid
    /// measurement (naming the id when that is why), the system denied access, or what went wrong.
    static func importErrorMessage(for error: Error, fileName: String) -> String {
        if let reason = unreadableReason(error) {
            return "Could not import \"\(fileName)\": the file is not a valid GuitarTap measurement (\(reason))."
        }
        let nsError = error as NSError
        let isPermissionError = (nsError.domain == NSPOSIXErrorDomain && nsError.code == 1) ||
                                (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError)
        if isPermissionError {
            return "Could not read \"\(fileName)\": the system denied access (error \(nsError.code))."
        }
        if error is DecodingError || (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadCorruptFileError) {
            return "Could not import \"\(fileName)\": the file is not a valid GuitarTap measurement."
        }
        return "Could not import \"\(fileName)\": \(error.localizedDescription)"
    }

    /// Loads all persisted measurements from disk.
    ///
    /// Reads `saved_measurements.json` from the Documents directory and decodes
    /// the `[TapToneMeasurement]` array with ISO-8601 date decoding.
    ///
    /// Populates `savedMeasurements` on the main thread. No-ops silently if
    /// the file does not yet exist.
    ///
    /// Entries that cannot be read are left out: the file is first copied aside as it was —
    /// ``keepCopyOfLibrary(at:unreadableCount:)`` — and the library is then saved without them. A file
    /// that cannot be read at all is set aside — ``setAsideUnreadableLibrary(at:)``.
    func loadPersistedMeasurements() {
        let fileURL = libraryFileURL

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            gtLog("📂 No persisted measurements file found")
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let library = try TapToneAnalyzer.decodeLibrary(data)
            let measurements = library.measurements
            savedMeasurements = measurements
            gtLog("📂 Loaded \(measurements.count) persisted measurements")

            if !library.unreadable.isEmpty {
                gtLog("❌ \(library.unreadable.count) persisted measurement(s) could not be read: \(library.unreadable)")
                keepCopyOfLibrary(at: fileURL, unreadableCount: library.unreadable.count)
                persistMeasurements()
                return
            }

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
            setAsideUnreadableLibrary(at: fileURL)
        }
    }

    /// The library holds entries that cannot be read. Before it is saved without them, it is copied —
    /// `<name>-unreadable-<date and time>.json` beside itself, as it was — and the user is told once how
    /// many were left out and where the copy is. If it cannot be copied, the library is not written this
    /// session, so the only copy of those entries is not replaced.
    func keepCopyOfLibrary(at fileURL: URL, unreadableCount: Int) {
        let keptURL = Self.unreadableLibraryURL(for: fileURL)
        let count = unreadableCount == 1 ? "1 saved measurement" : "\(unreadableCount) saved measurements"
        let was = unreadableCount == 1 ? "was" : "were"
        do {
            try FileManager.default.copyItem(at: fileURL, to: keptURL)
            gtLog("📂 Library with unreadable entries copied to \(keptURL.path)")
            libraryLoadFailure = "\(count) could not be read and \(was) removed from the list. The original file was kept as \(keptURL.lastPathComponent) \(Self.whereToFind(keptURL))."
        } catch {
            gtLog("❌ Could not copy the library aside: \(error) — the library is not written this session")
            isLibraryWriteBlocked = true
            libraryLoadFailure = "\(count) could not be read and \(was) left out of the list. The file, \(fileURL.lastPathComponent), was left as it is \(Self.whereToFind(fileURL)), and new measurements will not be saved to it this session."
        }
    }

    /// Where an unreadable library, or a copy of one, is kept: `<name>-unreadable-<date and time>.json`
    /// beside it.
    static func unreadableLibraryURL(for fileURL: URL) -> URL {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        return fileURL.deletingLastPathComponent().appendingPathComponent(
            "\(fileURL.deletingPathExtension().lastPathComponent)-unreadable-\(stamp.string(from: Date())).json")
    }

    /// The library could not be read. It is kept — renamed `<name>-unreadable-<date and time>.json`
    /// beside itself — so no save writes over it, the library starts empty, and the user is told once
    /// where it is: fixing the file and renaming it back restores it. If it cannot be renamed it stays
    /// where it is and the library is not written this session.
    func setAsideUnreadableLibrary(at fileURL: URL) {
        let keptURL = Self.unreadableLibraryURL(for: fileURL)
        do {
            try FileManager.default.moveItem(at: fileURL, to: keptURL)
            gtLog("📂 Unreadable library kept as \(keptURL.path)")
            libraryLoadFailure = Self.unreadableLibraryMessage(keptAs: keptURL, original: fileURL)
        } catch {
            gtLog("❌ Could not keep the unreadable library aside: \(error) — the library is not written this session")
            isLibraryWriteBlocked = true
            libraryLoadFailure = Self.unreadableLibraryMessage(keptAs: fileURL, original: fileURL)
        }
    }

    /// The message for a library that could not be read and was kept as `keptAs`.
    static func unreadableLibraryMessage(keptAs kept: URL, original: URL) -> String {
        if kept == original {
            return "Your saved measurements could not be read. The file, \(kept.lastPathComponent), was left as it is \(whereToFind(kept)), and new measurements will not be saved to it until it can be read."
        }
        return "Your saved measurements could not be read, so the library starts empty. The file was kept as \(kept.lastPathComponent) \(whereToFind(kept)) — fix it and rename it back to \(original.lastPathComponent) to restore it."
    }

    /// Where a file of the library's is, in the words a user finds it by: on iOS the app's folder in
    /// Files; on macOS its folder's path, from the home folder.
    static func whereToFind(_ file: URL) -> String {
        #if os(iOS)
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        return "in the GuitarTap folder in Files (On My \(device) › GuitarTap)"
        #else
        // The real home folder: in the sandbox NSHomeDirectory() is the app's container.
        var folder = file.deletingLastPathComponent().path
        if let account = getpwuid(getuid()), let home = String(validatingCString: account.pointee.pw_dir),
           folder.hasPrefix(home + "/") {
            folder = "~" + folder.dropFirst(home.count)
        }
        return "in GuitarTap's data folder, \(folder)"
        #endif
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
        guard !isLibraryWriteBlocked else {
            gtLog("📂 Library not written: it could not be read and is kept as it is")
            return
        }
        let fileURL = libraryFileURL
        // Snapshot the array on the main thread; encoding + disk I/O run in background
        // to avoid blocking the UI (spectrum data can be several MB). One serial queue, so the
        // writes land in the order they were made: on a concurrent queue an earlier, slower write
        // could finish last and leave an older library on disk.
        let snapshot = savedMeasurements
        TapToneAnalyzer.persistQueue.async {
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

    /// The guitar peak set to persist: the full set detected down to the −100 dB display floor, not just
    /// those above the current Peak Min. Filtering the saved set by Peak Min gives the same result as
    /// the live path re-detecting at that Peak Min — the local-maximum test is threshold-independent —
    /// so a reloaded measurement reveals peaks below its capture-time Peak Min exactly as the live one
    /// does. `allPeaks` is that set; the name states the intent: save the whole set, not what is shown.
    func guitarFullSavePeaks() -> [ResonantPeak] {
        allPeaks
    }

    /// Captures the current analyser state into a new ``TapToneMeasurement``
    /// and appends it to `savedMeasurements`.
    ///
    /// Everything but the view's own state is read from the model: the peaks and selection, the
    /// identified material peaks, overrides, annotation offsets, the ring-out, the spectra, and the
    /// capture's provenance (``captureMicrophoneName``, ``captureMicrophoneUID``,
    /// ``captureCalibrationName``, ``captureSampleRate``). For **guitar** a combined `SpectrumSnapshot`
    /// is built from the frozen or live spectrum; for **plate/brace** the per-phase snapshots are built
    /// from `longitudinalSpectrum`, `crossSpectrum` and `flcSpectrum` using `makePhaseSnapshot`.
    ///
    /// - Parameters:
    ///   - measurementName: A short label for where the measurement was taken, e.g. `"Top — Bridge"`.
    ///   - notes: Free-text user notes to attach to the measurement.
    ///   - minFreq: Lower bound of the saved display frequency range (Hz); `nil` uses `TapDisplaySettings.minFrequency`.
    ///   - maxFreq: Upper bound of the saved display frequency range (Hz); `nil` uses `TapDisplaySettings.maxFrequency`.
    ///   - minDB: Lower bound of the saved display magnitude range (dBFS); `nil` uses `TapDisplaySettings.minMagnitude`.
    ///   - maxDB: Upper bound of the saved display magnitude range (dBFS); `nil` uses `0.0`.
    func saveMeasurement(
        measurementName: String? = nil,
        notes: String? = nil,
        minFreq: Float? = nil,
        maxFreq: Float? = nil,
        minDB: Float? = nil,
        maxDB: Float? = nil
    ) {
        let measurement = makeMeasurement(measurementName: measurementName, notes: notes,
                                          minFreq: minFreq, maxFreq: maxFreq, minDB: minDB, maxDB: maxDB)

        savedMeasurements.append(measurement)
        // The result on screen is now this saved measurement: its exports show its date and are named by it.
        sourceMeasurementTimestamp = measurement.timestamp
        gtLog("💾 Saved measurement with \(measurement.peaks.count) peaks, type: \(TapDisplaySettings.measurementType.shortName)")

        // Persist to disk
        persistMeasurements()
    }

    /// The measurement the analyzer holds — what ``saveMeasurement(measurementName:notes:minFreq:maxFreq:minDB:maxDB:)``
    /// saves, built without saving it. A live export reads it too, so the live report and the report
    /// of the saved measurement are built from the same measurement by the same code.
    ///
    /// - Parameters:
    ///   - measurementName: The measurement's name, or `nil`.
    ///   - notes: The measurement's notes, or `nil`.
    ///   - minFreq: The chart's lower frequency, or `nil` for the setting.
    ///   - maxFreq: The chart's upper frequency, or `nil` for the setting.
    ///   - minDB: The chart's lower magnitude, or `nil` for the setting.
    ///   - maxDB: The chart's upper magnitude, or `nil` for 0 dB.
    ///   - timestamp: The measurement's time; now, by default.
    func makeMeasurement(
        measurementName: String? = nil,
        notes: String? = nil,
        minFreq: Float? = nil,
        maxFreq: Float? = nil,
        minDB: Float? = nil,
        maxDB: Float? = nil,
        timestamp: Date = Date()
    ) -> TapToneMeasurement {
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
        if measurementType.isGuitar {
            let freqs = isMeasurementComplete ? frozenFrequencies : fftAnalyzer.frequencies
            let mags  = isMeasurementComplete ? frozenMagnitudes  : fftAnalyzer.frame.magnitudes
            snapshot = SpectrumSnapshot(
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
            guard !measurementType.isGuitar,
                  let spec = longitudinalSpectrum else { return nil }
            return makePhaseSnapshot(magnitudes: spec.magnitudes, frequencies: spec.frequencies,
                                     minFreq: phaseArgs.minFreq, maxFreq: phaseArgs.maxFreq,
                                     minDB: phaseArgs.minDB, maxDB: phaseArgs.maxDB)
        }()
        let crossSnapshot: SpectrumSnapshot? = {
            guard measurementType == .plate,
                  let spec = crossSpectrum else { return nil }
            return makePhaseSnapshot(magnitudes: spec.magnitudes, frequencies: spec.frequencies,
                                     minFreq: phaseArgs.minFreq, maxFreq: phaseArgs.maxFreq,
                                     minDB: phaseArgs.minDB, maxDB: phaseArgs.maxDB)
        }()
        let flcSnapshot: SpectrumSnapshot? = {
            guard measurementType == .plate,
                  let spec = flcSpectrum else { return nil }
            return makePhaseSnapshot(magnitudes: spec.magnitudes, frequencies: spec.frequencies,
                                     minFreq: phaseArgs.minFreq, maxFreq: phaseArgs.maxFreq,
                                     minDB: phaseArgs.minDB, maxDB: phaseArgs.maxDB)
        }()

        // Guitar saves the full durable set with the user's selection. Material (plate/brace) has no
        // per-peak selection: its peaks ARE the identified L/C/FLC (`materialIdentifiedPeaks`, in
        // phase order), and every one is marked selected. (Matches the web/Python save path.)
        let savedPeaks = measurementType.isGuitar ? guitarFullSavePeaks() : materialIdentifiedPeaks
        let persistedSelectedIDs: Set<UUID> = measurementType.isGuitar
            ? selectedPeakIDs
            : Set(savedPeaks.map { $0.id })

        return TapToneMeasurement(
            timestamp: timestamp,
            peaks: savedPeaks,
            decayTime: currentDecayTime,
            measurementName: measurementName,
            notes: notes,
            spectrum: snapshot,
            // None dragged is none written, as an empty override map.
            annotationOffsets: peakAnnotationOffsets.isEmpty ? nil : peakAnnotationOffsets,
            tapDetectionThreshold: tapDetectionThreshold,
            numberOfTaps: numberOfTaps,
            peakMinThreshold: peakMinThreshold,
            // Include peak selections for plate and brace measurements
            selectedLongitudinalPeakID: !measurementType.isGuitar ? selectedLongitudinalPeak?.id : nil,
            selectedCrossPeakID: measurementType == .plate ? selectedCrossPeak?.id : nil,
            selectedFlcPeakID: measurementType == .plate ? selectedFlcPeak?.id : nil,
            longitudinalSnapshot: !measurementType.isGuitar ? longitudinalSnapshot : nil,
            crossSnapshot: measurementType == .plate ? crossSnapshot : nil,
            flcSnapshot: measurementType == .plate ? flcSnapshot : nil,
            // A guitar's selection is always written — empty when the user chose Select None, which must
            // read back as nothing selected. An absent selection is a legacy file's, healed on read.
            selectedPeakIDs: measurementType.isGuitar || !persistedSelectedIDs.isEmpty
                ? Array(persistedSelectedIDs) : nil,
            // Resolved over the saved set: a selected peak sitting below Peak Min is still selected.
            selectedPeakFrequencies: measurementType.isGuitar || !persistedSelectedIDs.isEmpty
                ? savedPeaks.filter { persistedSelectedIDs.contains($0.id) }.map { $0.frequency } : nil,
            // Persist whether the guitar selection was hand-modified, so a reloaded measurement offers
            // Reset to automatic selection as it did when saved. Guitar only.
            userModifiedSelection: measurementType.isGuitar ? userHasModifiedPeakSelection : nil,
            annotationVisibilityMode: annotationVisibilityMode,
            peakModeOverrides: peakModeOverrides.isEmpty ? nil : peakModeOverrides,
            microphoneName: captureMicrophoneName,
            microphoneUID: captureMicrophoneUID,
            calibrationName: captureCalibrationName,
            sampleRate: captureSampleRate,
            tapEntries: measurementType.isGuitar && !tapEntries.isEmpty ? tapEntries : nil
        )
    }
    
    /// Replaces the `measurementName` and `notes` fields of the measurement at a
    /// specific array index.
    ///
    /// All captured data is preserved, but the entry receives a **new `id`**: name and notes are
    /// part of a measurement's data, so an amended entry is a different dataset. See
    /// ``TapToneMeasurement/with(measurementName:notes:)``.
    ///
    /// Uses the caller-supplied index rather than `id` matching, because duplicate imports share
    /// an `id` until one of them is edited — so an id cannot address a row. Callers must pass the
    /// position in `savedMeasurements` itself, which is why the list is displayed in storage
    /// order.
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

    /// Removes every saved measurement and persists the empty library.
    func deleteAllMeasurements() {
        savedMeasurements.removeAll()
        persistMeasurements()
    }
    
    /// Decodes a JSON data blob into ``TapToneMeasurement`` records and
    /// appends them to `savedMeasurements`.
    ///
    /// An entry that cannot be read is skipped and the rest are imported; the file must hold at least
    /// one that can be read.
    ///
    /// A library operation only: it says nothing about microphones. Nothing is on screen yet, so
    /// there is nothing for a microphone difference to affect — the check belongs to
    /// ``loadMeasurement(_:)``, which is what shows the user data, so importing a library never
    /// warns about measurements the user has not opened.
    ///
    /// - Parameters:
    ///   - jsonData: Raw JSON data containing an array of encoded
    ///     ``TapToneMeasurement`` values.
    /// - Returns: The newly decoded measurements, and why each skipped entry could not be read.
    /// - Throws: A decoding error if `jsonData` is not a JSON array of measurements, or the first
    ///   entry's reason if none can be read.
    func importMeasurements(from jsonData: Data) throws -> DecodedLibrary {
        let library = try TapToneAnalyzer.decodeLibrary(jsonData)
        if library.measurements.isEmpty, let first = library.unreadable.first { throw first }
        let measurements = library.measurements

        // Add imported measurements
        savedMeasurements.append(contentsOf: measurements)
        
        // Persist to disk
        persistMeasurements()

        gtLog("📥 Imported \(measurements.count) measurements, skipped \(library.unreadable.count)")
        return library
    }

    /// Imports a `.guitartap` file and returns the one message the user sees for it.
    ///
    /// A single measurement is also loaded — so, and only then, the message carries the LOAD's
    /// microphone warning, folded in so one dialog appears rather than two, and consumed so the
    /// main view's alert does not show it again. A library import (Export All) only adds to the
    /// library and says nothing about microphones. Entries that could not be read and were skipped
    /// are named in the message.
    ///
    /// The warning is cleared first, so the message can only ever describe THIS import — whatever
    /// mechanism a view uses to clear an acknowledged warning, a stale one cannot ride along.
    /// Every import entry point calls this; the views only display the result.
    ///
    /// - Parameter jsonData: The file's contents.
    /// - Returns: The user-facing success message.
    /// - Throws: A decoding error if the file is not a valid `.guitartap` array.
    func importAndLoadMeasurements(from jsonData: Data) throws -> String {
        microphoneWarning = nil
        let library = try importMeasurements(from: jsonData)
        let imported = library.measurements
        var message: String
        if imported.count == 1, let measurement = imported.first {
            loadMeasurement(measurement)
            message = "Successfully imported and loaded 1 measurement"
        } else {
            message = "Successfully imported \(imported.count) measurements"
        }
        if let skipped = Self.skippedEntriesMessage(library.unreadable) {
            message += "\n\n" + skipped
        }
        if imported.count == 1, let warning = microphoneWarning {
            message += "\n\n⚠\u{FE0E} " + warning
            microphoneWarning = nil
        }
        return message
    }

    /// What an import's message says about the entries it skipped — nil when none were: how many, and
    /// why when there was one.
    static func skippedEntriesMessage(_ unreadable: [Error]) -> String? {
        guard let first = unreadable.first else { return nil }
        guard unreadable.count == 1 else {
            return "\(unreadable.count) measurements in the file could not be read and were not imported."
        }
        let reason = unreadableReason(first).map { " (\($0))" } ?? ""
        return "1 measurement in the file could not be read and was not imported\(reason)."
    }
    
    /// Restores the full analyser state from a saved measurement, entering
    /// a frozen "viewing" mode. The whole load is done here; the views only display the result.
    ///
    /// The restoration sequence:
    /// 1. The measurement's own settings — measurement type, guitar type, Show Unknown Modes, Peak
    ///    Min, the plate/brace dimensions — are applied and saved, before the peaks, so everything
    ///    is shown and classified under them. Its chart range is published in `loadedAxisRange`.
    /// 2. Peaks, decay time, and per-phase spectra are restored.
    /// 3. Phase-specific peak selections (`selectedLongitudinalPeak`,
    ///    `selectedCrossPeak`, `selectedFlcPeak`) are resolved by UUID into
    ///    the restored peak array.
    /// 4. Annotation offsets (none saved: none), selected peak IDs, annotation visibility mode,
    ///    and mode overrides are all restored.
    /// 5. Tap detection is disabled (`detectionState = .idle`, `currentTapCount = 0`).
    /// 6. The recording microphone is auto-selected if connected; otherwise
    ///    `microphoneWarning` is set. A file with no microphone clears any earlier warning.
    ///
    /// A saved comparison restores its overlays and stops detection and the session recording.
    ///
    /// - Parameter measurement: The ``TapToneMeasurement`` to load.
    func loadMeasurement(_ measurement: TapToneMeasurement) {
        gtLog("🔄 Loading measurement...")

        // Comparison records: restore the overlay spectra directly from the saved entries
        // and return early — no peak/spectrum restoration needed for the regular path.
        if let entries = measurement.comparisonEntries {
            comparisonSpectra = entries.enumerated().map { index, entry in
                let color = Palette.comparisonColor(index: index, label: entry.label)
                return (magnitudes: entry.snapshot.magnitudes,
                        frequencies: entry.snapshot.frequencies,
                        color: color, label: entry.label,
                        peaks: entry.peaks, guitarType: entry.guitarType,
                        modeIDs: entry.modePeakIDs ?? [:])   // healed on decode; [:] only if truly absent
            }
            comparisonSnapshots = entries.map(\.snapshot)
            // A saved comparison shows the range it was saved with, as a measurement does; one saved before
            // comparisons kept their range spans its entries' ranges, as a new comparison does.
            if let range = measurement.comparisonRange ?? DisplayRange.spanning(entries.map(\.snapshot)) {
                setLoadedAxisRange(minFreq: range.minFreq, maxFreq: range.maxFreq, minDB: range.minDB, maxDB: range.maxDB)
            }
            loadedMeasurementName = measurement.measurementName.flatMap { TapToneMeasurement.normalizedName($0) }
            loadedNotes = measurement.notes.flatMap { TapToneMeasurement.normalizedNotes($0) }
            // The saved comparison's own date, which its exports show and are named by.
            sourceMeasurementTimestamp = measurement.timestamp
            // Clear any per-tap entries from a previously loaded multi-tap measurement so
            // the PDF export routing doesn't misidentify this as a multi-tap measurement.
            tapEntries = []
            showingMultiTapComparison = false
            displayMode = .comparison
            resultProvenance = nil   // a comparison has no microphone of its own
            highlightedPeakID = nil
            detectionState = .idle
            abandonCapture()
            cancelSessionRecording()
            return
        }

        // Suppress recalculateFrozenPeaksIfNeeded() for the duration of the load.
        isLoadingMeasurement = true
        defer { isLoadingMeasurement = false }

        // Loading a new measurement ends any comparison; the loaded measurement displays because
        // `isMeasurementComplete` is set below, not because of the mode. Clear the frozen spectrum
        // at once, so no frame shows the previous measurement's spectrum under the new one — a
        // ghost spectrum in the chart.
        clearComparison()
        setFrozenSpectrum(frequencies: [], magnitudes: [])

        // Track the original timestamp so the Results-panel PDF can use it
        sourceMeasurementTimestamp = measurement.timestamp

        // Expose the measurement name so the chart title can reflect it
        let name = measurement.measurementName.flatMap { TapToneMeasurement.normalizedName($0) }
        loadedMeasurementName = name

        // Expose the notes so re-saving the loaded measurement keeps them (R10).
        loadedNotes = measurement.notes.flatMap { TapToneMeasurement.normalizedNotes($0) }

        // Restore display settings from any available snapshot (prefer longitudinal for plate/brace)
        let settingsSnapshot = measurement.longitudinalSnapshot ?? measurement.spectrumSnapshot
        if let snapshot = settingsSnapshot {
            // Restore display ranges - use setLoadedAxisRange so all four bounds are
            // published in a single objectWillChange notification, preventing transient
            // mismatched-axis states that cause SwiftUI Charts rendering artifacts.
            gtLog("  📊 Publishing display ranges: \(snapshot.minFreq)-\(snapshot.maxFreq) Hz, \(snapshot.minDB)-\(snapshot.maxDB) dB")
            setLoadedAxisRange(minFreq: snapshot.minFreq, maxFreq: snapshot.maxFreq,
                               minDB: snapshot.minDB, maxDB: snapshot.maxDB)
            
            // The measurement's own settings become the app's: Show Unknown Modes, guitar type and
            // measurement type. Applied here, before the peaks, so they are shown and classified
            // under this measurement's settings from the start.
            if let showUnknown = snapshot.showUnknownModes {
                TapDisplaySettings.showUnknownModes = showUnknown
            }
            if let guitarType = snapshot.guitarType {
                TapDisplaySettings.guitarType = guitarType
            }
            if let measurementType = snapshot.measurementType {
                TapDisplaySettings.measurementType = measurementType
            }
            
            // Store B ← the file's own material inputs (never the live Settings defaults). The calc,
            // Results panel, and Save all read this, so a loaded measurement's numbers come from the
            // file and loading never disturbs the Settings defaults (Store A).
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
        
        // Peak Min, before the peaks are assigned, so they are shown under this measurement's value.
        if let threshold = measurement.peakMinThreshold {
            peakMinThreshold = threshold
        }

        // Restore peaks. `allPeaks` is guitar-only: a material measurement's peaks are its identified
        // L/C/FLC, restored into the `selected…Peak`s below.
        allPeaks = measurement.isMaterial ? [] : measurement.peaks
        
        // Restore decay time
        currentDecayTime = measurement.decayTime
        
        // Determine if this is a plate/brace measurement with per-phase spectra
        let hasMaterialSpectra = measurement.longitudinalSnapshot != nil
        
        // Restore per-phase spectra for plate/brace measurements
        if let longSnap = measurement.longitudinalSnapshot {
            longitudinalSpectrum = (magnitudes: longSnap.magnitudes, frequencies: longSnap.frequencies)
        } else {
            longitudinalSpectrum = nil
        }
        if let crossSnap = measurement.crossSnapshot {
            crossSpectrum = (magnitudes: crossSnap.magnitudes, frequencies: crossSnap.frequencies)
        } else {
            crossSpectrum = nil
        }
        if let flcSnap = measurement.flcSnapshot {
            flcSpectrum = (magnitudes: flcSnap.magnitudes, frequencies: flcSnap.frequencies)
        } else {
            flcSpectrum = nil
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
        }
        
        // Restore the plate/brace identified peaks — the only material peak state — by id from the
        // saved peaks: which peak is L / C / FLC is a fact about the measurement.
        materialPeaksFromLoad = true
        selectedLongitudinalPeak = measurement.selectedLongitudinalPeakID
            .flatMap { id in measurement.peaks.first(where: { $0.id == id }) }
        selectedCrossPeak = measurement.selectedCrossPeakID
            .flatMap { id in measurement.peaks.first(where: { $0.id == id }) }
        selectedFlcPeak = measurement.selectedFlcPeakID
            .flatMap { id in measurement.peaks.first(where: { $0.id == id }) }
        gtLog("  🔵 Restored longitudinal peak: \(selectedLongitudinalPeak?.frequency ?? -1) Hz")
        gtLog("  🟠 Restored cross-grain peak: \(selectedCrossPeak?.frequency ?? -1) Hz")
        gtLog("  🟣 Restored FLC peak: \(selectedFlcPeak?.frequency ?? -1) Hz")
        
        // Stop tap detection when loading a measurement (frozen state).
        // `.idle` rather than `.paused` matters: if a tap sequence was paused before
        // loading, the analyzeMagnitudes loop would otherwise keep overwriting
        // peaksAbovePeakMin with fresh live-audio peaks on every FFT frame.
        detectionState = .idle
        // A capture under way when the load came is dropped, with all it scheduled — it would
        // otherwise land on the loaded measurement.
        abandonCapture()
        cancelSessionRecording()
        isMeasurementComplete = true
        currentTapCount = 0
        tapProgress = 0.0
        statusMessage = "Loaded measurement (frozen). Press \u{2018}New Tap\u{2019} to start a new measurement."
        gtLog("  🧊 Spectrum frozen, tap detection disabled")
        
        // Restore annotation offsets
        peakAnnotationOffsets = measurement.peakAnnotationOffsets ?? [:]
        // A newly loaded measurement has no highlighted peak.
        highlightedPeakID = nil
        
        // Restore selected peak IDs (guitar); if none saved, default to selecting all peaks.
        // Material has no per-peak selection, so it restores none — its saved `selectedPeakIDs`
        // aggregate is never read.
        if measurement.isMaterial {
            selectedPeakIDs = []
        } else if let saved = measurement.selectedPeakIDs {
            selectedPeakIDs = Set(saved)
        } else {
            selectedPeakIDs = Set(measurement.peaks.map { $0.id })
        }
        // Restore whether the selection was user-modified, which decides whether Reset to automatic
        // selection is offered. Files saved before this field default to `true` (manual).
        userHasModifiedPeakSelection = measurement.userModifiedSelection ?? true
        // The selected peaks' frequencies, kept with the selection.
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
            loadedTapDetectionThreshold = threshold
            tapDetectionThreshold = threshold
        } else {
            gtLog("  ⚠️ No tap threshold in measurement")
        }
        
        if let taps = measurement.numberOfTaps {
            gtLog("  🔢 Publishing number of taps: \(taps)")
            loadedNumberOfTaps = taps
            numberOfTaps = taps
        } else {
            gtLog("  ⚠️ No number of taps in measurement")
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
                // If it cannot be opened the current input is kept and the load says so.
                var switchFailed = false
                if fftAnalyzer.selectedInputDevice?.uid != match.uid {
                    do {
                        try fftAnalyzer.setInputDevice(match)
                        gtLog("🎤 Auto-selected microphone '\(name)' for loaded measurement")
                    } catch {
                        microphoneWarningTitle = "Microphone Unavailable"
                        microphoneWarning = RealtimeFFTAnalyzer.failedOpenMessage(for: match)
                        switchFailed = true
                    }
                }
                if !switchFailed {
                    // Same microphone — but flag a calibration or sample-rate difference,
                    // since a newly captured tap would then not match this saved measurement.
                    let calibrationDiffers = measurement.calibrationName != fftAnalyzer.activeCalibration?.name
                    let currentRate = Int(fftAnalyzer.actualSampleRate.rounded())
                    let recordedRate = measurement.sampleRate.map { Int($0.rounded()) }
                    let rateDiffers = recordedRate.map { $0 != currentRate } ?? false
                    microphoneWarningTitle = "Recording Setup Differs"
                    microphoneWarning = (calibrationDiffers || rateDiffers)
                        ? Self.setupDiffersMessage(
                            calibration: calibrationDiffers
                                ? (measurement.calibrationName, fftAnalyzer.activeCalibration?.name) : nil,
                            sampleRate: rateDiffers ? (recordedRate ?? 0, currentRate) : nil)
                        : nil
                }
            } else {
                // Report UNKNOWN, not "unplugged": a no-match can equally mean the device is attached
                // under a different name on this platform (the same UMIK-1 is "Umik-1  Gain: 18dB" here
                // and "Microphone (Umik-1  Gain: 18dB)" on Windows). Impact stated so the reader can
                // judge — frequencies are essentially mic-independent; levels, trigger and faint peaks
                // are not. Mirrors the Python + web wording.
                microphoneWarningTitle = "Microphone Not Found"
                microphoneWarning = Self.microphoneNotFoundMessage(
                    recorded: name, current: fftAnalyzer.selectedInputDevice?.name)
            }
        } else {
            microphoneWarning = nil
        }

        showLoadedSettingsWarning = true
        // The loaded result's provenance is what the file recorded; no microphone means unknown.
        resultProvenance = ResultProvenance(microphoneName: measurement.microphoneName,
                                            microphoneUID: measurement.microphoneUID,
                                            calibrationName: measurement.calibrationName,
                                            sampleRate: measurement.sampleRate)

        // Restore per-tap spectra so the multi-tap comparison toggle is available after reload.
        // tapEntries is nil for single-tap, plate/brace, and older saved measurements.
        tapEntries = measurement.tapEntries ?? []
        // Always start with the averaged view — the user can toggle to per-tap if desired.
        showingMultiTapComparison = false

        // The saved per-tap peaks are restored as-is and never re-detected. They are the
        // measurement's own record, exactly like `measurement.peaks`.
        // This previously called
        // `recalculateTapEntryPeaks()` to "re-run findPeaks with the saved threshold", which
        // re-analysed a loaded measurement and then wrote the filtered result back into
        // `tapEntries` — truncating the saved full set on the next save.

        gtLog("✅ Loaded measurement with \(measurement.peaks.count) peaks (frozen)")
        if !tapEntries.isEmpty {
            gtLog("  📋 Restored \(tapEntries.count) per-tap entries for multi-tap comparison")
        }
    }

    /// The load's warning when no connected microphone has the recorded name. Names both
    /// microphones — the recorded one and the one in use — and says why a measurement from another
    /// computer usually cannot find its microphone.
    static func microphoneNotFoundMessage(recorded: String, current: String?) -> String {
        "This measurement was recorded with a microphone named '\(recorded)'. No connected microphone has exactly that name, so the input has not been changed — you are still using '\(current ?? "no microphone")'.\n\n"
            + "Each computer names microphones its own way. A measurement made on another computer — especially one running a different operating system — will usually not find its microphone even when the same one is connected. If it is, choose it in Settings.\n\n"
            + "Peak frequencies are still comparable; input levels, the tap threshold, and faint peaks (such as FLC) may differ."
    }

    /// The load's warning when the recorded microphone is in use but the calibration and/or the
    /// sample rate differs — one line for each that differs, with both values.
    static func setupDiffersMessage(calibration: (recorded: String?, current: String?)?,
                                    sampleRate: (recorded: Int, current: Int)?) -> String {
        var lines = ["This measurement was made with a different setup from the current one:"]
        if let calibration {
            lines.append("• Calibration: recorded with \(calibration.recorded.map { "'\($0)'" } ?? "none"); the current microphone uses \(calibration.current.map { "'\($0)'" } ?? "none").")
        }
        if let sampleRate {
            lines.append("• Sample rate: recorded at \(sampleRate.recorded) Hz; audio is now captured at \(sampleRate.current) Hz.")
        }
        return lines.joined(separator: "\n")
            + "\n\nA tap captured now may not match the saved result. The sample rate is set outside Guitar Tap: in Audio MIDI Setup on a Mac, or Sound settings on Windows."
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
    
    // MARK: - Comparison Overlay


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
        // An unsaved comparison has no date of its own: its exports use the time of export.
        sourceMeasurementTimestamp = nil
        resultProvenance = nil   // a comparison has no microphone of its own
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
            let color = Palette.series(index)
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

        // A comparison spans its entries' ranges, whatever was shown before — use setLoadedAxisRange so
        // all four bounds are published atomically, preventing transient axis mismatches.
        if let range = DisplayRange.spanning(withSnapshots.compactMap(\.spectrumSnapshot)) {
            setLoadedAxisRange(minFreq: range.minFreq, maxFreq: range.maxFreq, minDB: range.minDB, maxDB: range.maxDB)
        }

        displayMode = comparisonSpectra.isEmpty ? .live : .comparison

        // An overlay is frozen, exactly like a loaded measurement — so stand the detector down,
        // as `loadMeasurement` does above for the same reason.  Left armed, `analyzeMagnitudes`
        // goes on overwriting the displayed peaks from live audio underneath the overlay, and a
        // tap captures and completes a measurement the user never sees being made.  Empty data
        // means we stayed `.live`, so there is nothing to freeze and nothing to disarm.
        // Mirrors web `loadComparison`.
        if !comparisonSpectra.isEmpty {
            detectionState = .idle
            abandonCapture()
            cancelSessionRecording()
        }
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
    ///   - minFreq, maxFreq, minDB, maxDB: The chart's range, saved with the comparison and shown when it
    ///     is loaded, as a measurement's; `nil` spans the entries' ranges, as a new comparison does.
    func saveComparison(measurementName: String? = nil, notes: String? = nil,
                        minFreq: Float? = nil, maxFreq: Float? = nil,
                        minDB: Float? = nil, maxDB: Float? = nil) {
        guard !comparisonSpectra.isEmpty,
              comparisonSnapshots.count == comparisonSpectra.count,
              let spanned = DisplayRange.spanning(comparisonSnapshots) else { return }

        let entries: [ComparisonEntry] = comparisonSpectra.enumerated().map { index, entry in
            // Resolve Color → RGBA components using CGColor.
            // The fixed 5-color palette (blue/orange/green/purple/teal) round-trips exactly.
            let cgColor: CGColor = entry.color.resolve(in: Palette.lightEnvironment).cgColor
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
            comparisonEntries: entries,
            comparisonRange: DisplayRange.ChartRange(minFreq: minFreq ?? spanned.minFreq,
                                                     maxFreq: maxFreq ?? spanned.maxFreq,
                                                     minDB: minDB ?? spanned.minDB,
                                                     maxDB: maxDB ?? spanned.maxDB)
        )
        savedMeasurements.append(record)
        // The comparison on screen is now this saved one: its exports show its date and are named by it.
        sourceMeasurementTimestamp = record.timestamp
        persistMeasurements()
    }

    /// Ends a comparison: its overlay spectra and their snapshots go, and the chart is live. The one
    /// place a comparison ends — a load, New Tap, and turning the per-tap overlay off call it.
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
    /// When turned off, `comparisonSpectra` is cleared and `displayMode` returns to `.live`; the
    /// chart reverts to the averaged spectrum on its own, because the measurement is complete.
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
        showingMultiTapComparison = enabled
        guard enabled else {
            // Leave comparison; the chart goes back to the averaged spectrum on its own, because
            // the measurement is complete.
            clearComparison()
            return
        }
        guard !tapEntries.isEmpty else { return }

        // The measurement's tap comparison — the same entries its report and its saved form show. This
        // feeds the CHART overlay (magnitudes/colour/label); the multi-tap Air/Top/Back table is
        // MultiTapComparisonResultsView, so the `modeIDs` element is unused here — `[:]` is correct.
        let comparison = makeMeasurement().multiTapComparisonEntries
        let entries: [(magnitudes: [Float], frequencies: [Float], color: Color, label: String, peaks: [ResonantPeak], guitarType: GuitarType?, modeIDs: [String: UUID])] =
            comparison.enumerated().map { index, entry in
                (magnitudes: entry.snapshot.magnitudes, frequencies: entry.snapshot.frequencies,
                 color: Palette.comparisonColor(index: index, label: entry.label), label: entry.label,
                 peaks: entry.peaks, guitarType: entry.guitarType, modeIDs: [:])
            }
        let snapshots = comparison.map(\.snapshot)

        comparisonSpectra = entries
        comparisonSnapshots = snapshots
        // Switch to comparison display mode so the chart's materialSpectra computed property
        // picks up the comparisonSpectra overlays. The Results panel uses showingMultiTapComparison
        // (not displayMode) to gate its content, so guitar summary etc. remain visible.
        displayMode = .comparison
    }
}
