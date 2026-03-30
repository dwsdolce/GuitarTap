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
            print("📂 No persisted measurements file found")
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let measurements = try decoder.decode([TapToneMeasurement].self, from: data)
            savedMeasurements = measurements
            print("📂 Loaded \(measurements.count) persisted measurements")
        } catch {
            print("❌ Failed to load persisted measurements: \(error)")
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
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: fileURL, options: .atomic)
                print("💾 Persisted \(snapshot.count) measurements to disk")
            } catch {
                print("❌ Failed to persist measurements: \(error)")
            }
        }
    }

    // MARK: - Measurement Management
    
    /// Captures the current analyser state into a new ``TapToneMeasurement``
    /// and appends it to `savedMeasurements`.
    ///
    /// For **guitar** measurements a combined `SpectrumSnapshot` is built from
    /// the frozen or live spectrum. For **plate/brace** measurements the
    /// combined snapshot is `nil`; per-phase snapshots should be passed in
    /// `longitudinalSnapshot`, `crossSnapshot`, and `flcSnapshot`.
    ///
    /// - Parameters:
    ///   - tapLocation: A short label for where the measurement was taken,
    ///     e.g. `"Top — Bridge"`.
    ///   - notes: Free-text user notes to attach to the measurement.
    ///   - includeSpectrum: When `true` and the measurement type is guitar,
    ///     a `SpectrumSnapshot` is generated from the current (frozen or live)
    ///     FFT data.
    ///   - spectrumSnapshot: Pre-built guitar spectrum snapshot. If `nil` and
    ///     `includeSpectrum` is `true`, one is built from the live/frozen FFT.
    ///   - longitudinalSnapshot: Pre-built spectrum snapshot for the
    ///     longitudinal phase (plate/brace measurements).
    ///   - crossSnapshot: Pre-built spectrum snapshot for the cross-grain
    ///     phase (plate measurements).
    ///   - flcSnapshot: Pre-built spectrum snapshot for the FLC phase (plate
    ///     measurements with FLC enabled).
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
    func saveMeasurement(
        tapLocation: String? = nil,
        notes: String? = nil,
        includeSpectrum: Bool = true,
        spectrumSnapshot: SpectrumSnapshot? = nil,
        longitudinalSnapshot: SpectrumSnapshot? = nil,
        crossSnapshot: SpectrumSnapshot? = nil,
        flcSnapshot: SpectrumSnapshot? = nil,
        annotationOffsets: [UUID: CGPoint]? = nil,
        selectedLongitudinalPeakID: UUID? = nil,
        selectedCrossPeakID: UUID? = nil,
        selectedFlcPeakID: UUID? = nil,
        microphoneName: String? = nil,
        microphoneUID: String? = nil,
        calibrationName: String? = nil
    ) {
        let measurementType = TapDisplaySettings.measurementType
        
        // For guitar measurements: save a single spectrum snapshot as before.
        // For plate/brace: per-phase snapshots are used instead; no combined snapshot needed.
        let snapshot: SpectrumSnapshot?
        if includeSpectrum && measurementType.isGuitar {
            snapshot = spectrumSnapshot ?? SpectrumSnapshot(
                frequencies: isMeasurementComplete ? frozenFrequencies : fftAnalyzer.frequencies,
                magnitudes: isMeasurementComplete ? frozenMagnitudes : fftAnalyzer.magnitudes,
                minFreq: TapDisplaySettings.minFrequency,
                maxFreq: TapDisplaySettings.maxFrequency,
                minDB: TapDisplaySettings.minMagnitude,
                maxDB: TapDisplaySettings.maxMagnitude,
                isLogarithmic: false,
                showUnknownModes: TapDisplaySettings.showUnknownModes,
                guitarType: TapDisplaySettings.guitarType,
                measurementType: measurementType,
                maxPeaks: maxPeaks
            )
        } else {
            snapshot = nil
        }
        
        let measurement = TapToneMeasurement(
            peaks: currentPeaks,
            decayTime: currentDecayTime,
            tapLocation: tapLocation,
            notes: notes,
            spectrum: snapshot,
            annotationOffsets: annotationOffsets ?? peakAnnotationOffsets,
            tapDetectionThreshold: tapDetectionThreshold,
            hysteresisMargin: hysteresisMargin,
            numberOfTaps: numberOfTaps,
            peakThreshold: peakThreshold,
            // Include peak selections for plate and brace measurements
            selectedLongitudinalPeakID: !measurementType.isGuitar ? selectedLongitudinalPeakID : nil,
            selectedCrossPeakID: measurementType == .plate ? selectedCrossPeakID : nil,
            selectedFlcPeakID: measurementType == .plate ? selectedFlcPeakID : nil,
            longitudinalSnapshot: !measurementType.isGuitar ? longitudinalSnapshot : nil,
            crossSnapshot: measurementType == .plate ? crossSnapshot : nil,
            flcSnapshot: measurementType == .plate ? flcSnapshot : nil,
            selectedPeakIDs: selectedPeakIDs.isEmpty ? nil : Array(selectedPeakIDs),
            selectedPeakFrequencies: selectedPeakIDs.isEmpty ? nil : currentPeaks
                .filter { selectedPeakIDs.contains($0.id) }
                .map { $0.frequency },
            annotationVisibilityMode: annotationVisibilityMode,
            peakModeOverrides: peakModeOverrides.isEmpty ? nil : peakModeOverrides,
            microphoneName: microphoneName,
            microphoneUID: microphoneUID,
            calibrationName: calibrationName
        )
        
        savedMeasurements.append(measurement)
        print("💾 Saved measurement with \(currentPeaks.count) peaks, type: \(measurementType.shortName)")
        
        // Persist to disk
        persistMeasurements()
    }
    
    /// Replaces the `tapLocation` and `notes` fields of the measurement at a
    /// specific array index, preserving all other data unchanged.
    ///
    /// Uses the caller-supplied index rather than `id` matching so that
    /// duplicate imports (which share the same `id`) are treated independently.
    ///
    /// - Parameters:
    ///   - index: Position in `savedMeasurements` to update.
    ///   - tapLocation: New location label, or `nil` to clear it.
    ///   - notes: New free-form notes, or `nil` to clear them.
    func updateMeasurement(at index: Int,
                           tapLocation: String?,
                           notes: String?) {
        guard savedMeasurements.indices.contains(index) else { return }
        savedMeasurements[index] = savedMeasurements[index].with(tapLocation: tapLocation, notes: notes)
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
    ///   - baseURL: Unused. Kept for API compatibility.
    /// - Returns: The array of newly decoded measurements.
    /// - Throws: A decoding error if `jsonData` is not a valid
    ///   `[TapToneMeasurement]` JSON array.
    func importMeasurements(from jsonData: Data, baseURL: URL? = nil) throws -> [TapToneMeasurement] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let measurements = try decoder.decode([TapToneMeasurement].self, from: jsonData)
        
        // Add imported measurements
        savedMeasurements.append(contentsOf: measurements)
        
        // Persist to disk
        persistMeasurements()

        // Warn if any imported measurement's microphone is not currently available
        let available = Set(fftAnalyzer.availableInputDevices.map(\.uid))
        var missingNames: [String] = []
        for m in measurements {
            if let uid = m.microphoneUID, !available.contains(uid) {
                let name = m.microphoneName ?? uid
                if !missingNames.contains(name) {
                    missingNames.append(name)
                }
            }
        }
        if !missingNames.isEmpty {
            let list = missingNames.joined(separator: ", ")
            microphoneWarning = "Recorded with \(list), which is not currently connected. Attach it and select it in the microphone settings for accurate analysis."
        }

        print("📥 Imported \(measurements.count) measurements")
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
        print("🔄 Loading measurement...")
        // Suppress recalculateFrozenPeaksIfNeeded() for the duration of the load.
        // The saved peaks are already correct; re-running findPeaks() would
        // generate wrong UUIDs and may classify with a stale guitar type.
        isLoadingMeasurement = true
        defer { isLoadingMeasurement = false }

        // Loading a new measurement exits comparison mode.
        comparisonSpectra = []
        displayMode = .frozen

        // Track the original timestamp so the Results-panel PDF can use it
        sourceMeasurementTimestamp = measurement.timestamp

        // Restore peaks
        currentPeaks = measurement.peaks
        
        // Restore decay time
        currentDecayTime = measurement.decayTime
        
        // Determine if this is a plate/brace measurement with per-phase spectra
        let hasMaterialSpectra = measurement.longitudinalSnapshot != nil
        
        // Restore per-phase spectra for plate/brace measurements
        if let longSnap = measurement.longitudinalSnapshot {
            longitudinalSpectrum = (magnitudes: longSnap.magnitudes, frequencies: longSnap.frequencies)
            longitudinalPeaks = [] // peaks come from currentPeaks
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
        if hasMaterialSpectra {
            frozenFrequencies = []
            frozenMagnitudes = []
            materialTapPhase = .complete
        } else if let snapshot = measurement.spectrumSnapshot {
            frozenFrequencies = snapshot.frequencies
            frozenMagnitudes = snapshot.magnitudes
        } else {
            frozenFrequencies = []
            frozenMagnitudes = []
        }
        
        // Restore display settings from any available snapshot (prefer longitudinal for plate/brace)
        let settingsSnapshot = measurement.longitudinalSnapshot ?? measurement.spectrumSnapshot
        if let snapshot = settingsSnapshot {
            // Restore display ranges - publish these to trigger view updates
            print("  📊 Publishing display ranges: \(snapshot.minFreq)-\(snapshot.maxFreq) Hz, \(snapshot.minDB)-\(snapshot.maxDB) dB")
            loadedMinFreq = snapshot.minFreq
            loadedMaxFreq = snapshot.maxFreq
            loadedMinDB = snapshot.minDB
            loadedMaxDB = snapshot.maxDB
            
            // Restore showUnknownModes setting if available
            if let showUnknown = snapshot.showUnknownModes {
                print("  👁️ Publishing showUnknownModes: \(showUnknown)")
                loadedShowUnknownModes = showUnknown
            }
            
            // Restore guitarType setting if available.
            // Apply directly to TapDisplaySettings now (synchronous) so that
            // reclassifyPeaks() below uses the correct mode ranges.  Also
            // publish loadedGuitarType so the view's bound control updates.
            if let guitarType = snapshot.guitarType {
                print("  🎸 Publishing guitarType: \(guitarType.rawValue)")
                TapDisplaySettings.guitarType = guitarType
                loadedGuitarType = guitarType
            }
            
            // Restore measurementType setting if available.
            // Apply directly so that reclassifyPeaks() uses the correct type.
            if let measurementType = snapshot.measurementType {
                print("  📐 Publishing measurementType: \(measurementType.shortName)")
                TapDisplaySettings.measurementType = measurementType
                loadedMeasurementType = measurementType
            }
            
            // Restore plate dimensions if available (for plate measurements)
            if let plateLength = snapshot.plateLength {
                print("  📏 Publishing plate dimensions: L=\(plateLength)mm")
                loadedPlateLength = plateLength
            }
            if let plateWidth = snapshot.plateWidth {
                loadedPlateWidth = plateWidth
            }
            if let plateThickness = snapshot.plateThickness {
                loadedPlateThickness = plateThickness
            }
            if let plateMass = snapshot.plateMass {
                loadedPlateMass = plateMass
            }

            // Restore Gore thicknessing / panel type settings (plate mode)
            if let bodyLength = snapshot.guitarBodyLength {
                loadedGuitarBodyLength = bodyLength
            }
            if let bodyWidth = snapshot.guitarBodyWidth {
                loadedGuitarBodyWidth = bodyWidth
            }
            if let preset = snapshot.plateStiffnessPreset {
                print("  🪵 Publishing plateStiffnessPreset: \(preset.shortName)")
                loadedPlateStiffnessPreset = preset
            }
            if let customStiffness = snapshot.customPlateStiffness {
                loadedCustomPlateStiffness = customStiffness
            }
            if let flc = snapshot.measureFlc {
                loadedMeasureFlc = flc
            }

            // Restore brace dimensions (brace mode)
            if let braceLength = snapshot.braceLength {
                loadedBraceLength = braceLength
            }
            if let braceWidth = snapshot.braceWidth {
                loadedBraceWidth = braceWidth
            }
            if let braceThickness = snapshot.braceThickness {
                loadedBraceThickness = braceThickness
            }
            if let braceMass = snapshot.braceMass {
                loadedBraceMass = braceMass
            }
        } else {
            print("  ⚠️ No spectrum snapshot in measurement")
        }
        
        // Restore plate/brace peak selections directly into the model properties
        // that effectiveLongitudinalPeakID etc. read from.
        selectedLongitudinalPeak = measurement.selectedLongitudinalPeakID
            .flatMap { id in currentPeaks.first(where: { $0.id == id }) }
        selectedCrossPeak = measurement.selectedCrossPeakID
            .flatMap { id in currentPeaks.first(where: { $0.id == id }) }
        selectedFlcPeak = measurement.selectedFlcPeakID
            .flatMap { id in currentPeaks.first(where: { $0.id == id }) }
        userSelectedLongitudinalPeakID = nil
        userSelectedCrossPeakID = nil
        userSelectedFlcPeakID = nil
        print("  🔵 Restored longitudinal peak: \(selectedLongitudinalPeak?.frequency ?? -1) Hz")
        print("  🟠 Restored cross-grain peak: \(selectedCrossPeak?.frequency ?? -1) Hz")
        print("  🟣 Restored FLC peak: \(selectedFlcPeak?.frequency ?? -1) Hz")
        
        // Stop tap detection when loading a measurement (frozen state).
        // Clear isDetectionPaused too — if a tap sequence was paused before loading,
        // the analyzeMagnitudes loop would otherwise keep overwriting currentPeaks
        // with fresh live-audio peaks on every FFT frame.
        isDetecting = false
        isDetectionPaused = false
        isMeasurementComplete = true
        currentTapCount = 0
        tapProgress = 0.0
        statusMessage = "Loaded measurement (frozen). Press 'Resume' or 'New Tap' to continue."
        print("  🧊 Spectrum frozen, tap detection disabled")
        
        // Restore annotation offsets
        if let offsets = measurement.peakAnnotationOffsets {
            peakAnnotationOffsets = offsets
            print("  🏷️ Restored \(offsets.count) annotation offsets")
        }
        
        // Retain the original saved peaks so recalculateFrozenPeaksIfNeeded() can
        // remap selectedPeakIDs, peakAnnotationOffsets, and peakModeOverrides by
        // frequency when Peak Min changes generate new UUIDs.
        loadedMeasurementPeaks = measurement.peaks

        // Restore selected peak IDs; if none saved, default to selecting all peaks.
        if let saved = measurement.selectedPeakIDs {
            selectedPeakIDs = Set(saved)
        } else {
            selectedPeakIDs = Set(measurement.peaks.map { $0.id })
        }
        // Mark as user-modified so recalculateFrozenPeaksIfNeeded uses frequency-proximity
        // carry-forward (referencing loadedMeasurementPeaks) rather than auto-selection.
        userHasModifiedPeakSelection = true
        // Seed the stable frequency cache from the loaded selection so that
        // recalculateFrozenPeaksIfNeeded() can carry forward selections even
        // after Peak Min is raised above all peaks (at which point selectedPeakIDs
        // holds stale UUIDs that no longer exist in the re-analyzed peak set).
        selectedPeakFrequencies = measurement.peaks
            .filter { selectedPeakIDs.contains($0.id) }
            .map { $0.frequency }
        print("  ⭐ Restored \(selectedPeakIDs.count) selected peaks")

        // Restore annotation visibility mode; default to .all if not saved
        annotationVisibilityMode = measurement.annotationVisibilityMode ?? .all
        TapDisplaySettings.annotationVisibilityMode = annotationVisibilityMode
        print("  👁️ Restored annotation visibility: \(annotationVisibilityMode.label)")

        // Restore per-peak mode overrides; nil / empty → all peaks auto-classify
        if let overrides = measurement.peakModeOverrides, !overrides.isEmpty {
            applyModeOverrides(overrides)
            print("  🏷️ Restored \(overrides.count) mode overrides")
        } else {
            peakModeOverrides = [:]
        }

        // Rebuild identifiedModes from the restored peaks so that calculateTapToneRatio()
        // and other helpers work correctly immediately after load (without needing a new tap).
        // This must run after peakModeOverrides is set so reclassifyPeaks() can incorporate them.
        reclassifyPeaks()
        print("  🔬 Reclassified \(identifiedModes.count) modes after load")
        
        // Restore analysis settings if available — set both internal and published values
        if let threshold = measurement.tapDetectionThreshold {
            print("  🎯 Publishing tap threshold: \(threshold) dB")
            tapDetectionThreshold = threshold
            loadedTapDetectionThreshold = threshold
        } else {
            print("  ⚠️ No tap threshold in measurement")
        }
        
        if let hysteresis = measurement.hysteresisMargin {
            print("  🔄 Publishing hysteresis: \(hysteresis) dB")
            hysteresisMargin = hysteresis
            loadedHysteresisMargin = hysteresis
        } else {
            print("  ⚠️ No hysteresis in measurement")
        }
        
        if let taps = measurement.numberOfTaps {
            print("  🔢 Publishing number of taps: \(taps)")
            numberOfTaps = taps
            loadedNumberOfTaps = taps
        } else {
            print("  ⚠️ No number of taps in measurement")
        }

        if let threshold = measurement.peakThreshold {
            print("  📊 Publishing peak threshold: \(threshold) dB")
            peakThreshold = threshold
            loadedPeakThreshold = threshold
        } else {
            print("  ⚠️ No peak threshold in measurement")
        }
        
        // Auto-select the recorded microphone if it is connected; warn if it is not.
        if let uid = measurement.microphoneUID {
            let name = measurement.microphoneName ?? uid
            if let match = fftAnalyzer.availableInputDevices.first(where: { $0.uid == uid }) {
                // Device is connected — switch to it; its paired calibration loads automatically.
                if fftAnalyzer.selectedInputDevice?.uid != uid {
                    try? fftAnalyzer.setInputDevice(match)
                    print("🎤 Auto-selected microphone '\(name)' for loaded measurement")
                }
                microphoneWarning = nil
            } else {
                microphoneWarning = "This measurement was recorded with '\(name)', which is not currently connected. Attach it and select it in the microphone settings for accurate analysis."
            }
        }

        print("✅ Loaded measurement with \(measurement.peaks.count) peaks (frozen)")
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
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            if let data = try? encoder.encode([measurement]),
               let json = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    completion(json, measurement)
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
    /// - SeeAlso: ``importMeasurements(from:baseURL:)`` for the full import
    ///   path with image loading and microphone warning support.
    func importMeasurements(json: String) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let data = json.data(using: .utf8),
              let measurements = try? decoder.decode([TapToneMeasurement].self, from: data) else {
            return false
        }
        
        savedMeasurements.append(contentsOf: measurements)
        return true
    }

    // MARK: - Comparison Overlay

    /// Color palette for comparison overlays (cycles if more than 5 measurements).
    private static let comparisonPalette: [Color] = [.blue, .orange, .green, .purple, .teal]

    /// Short label for a measurement in the comparison legend.
    private func comparisonLabel(for measurement: TapToneMeasurement) -> String {
        if let location = measurement.tapLocation, !location.isEmpty {
            return location
        }
        return measurement.timestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute())
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
        let withSnapshots = measurements.filter { $0.spectrumSnapshot != nil }
        comparisonSpectra = withSnapshots.enumerated().map { index, measurement in
            let snap = measurement.spectrumSnapshot!
            let color = Self.comparisonPalette[index % Self.comparisonPalette.count]
            return (magnitudes: snap.magnitudes, frequencies: snap.frequencies,
                    color: color, label: comparisonLabel(for: measurement))
        }

        // Broadcast the union axis ranges so TapToneAnalysisView updates its display
        let snapshots = withSnapshots.compactMap { $0.spectrumSnapshot }
        if !snapshots.isEmpty {
            loadedMinFreq = snapshots.map(\.minFreq).min()
            loadedMaxFreq = snapshots.map(\.maxFreq).max()
            loadedMinDB   = snapshots.map(\.minDB).min()
            loadedMaxDB   = snapshots.map(\.maxDB).max()
        }

        displayMode = .comparison
    }

    /// Removes all comparison overlay spectra from the main chart.
    func clearComparison() {
        comparisonSpectra = []
        displayMode = .live
    }
}
