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
/// Chart images are stored as separate PNG files in the same directory using
/// a filename derived from the tap location label and a Unix timestamp:
/// ```
/// <location-slug>-<timestamp>.png
/// ```
/// The filename is recorded in ``TapToneMeasurement/chartImageFilename`` so
/// that images can be loaded back alongside the JSON metadata.
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
    static var measurementsFileURL: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("saved_measurements.json")
    }
    
    /// Loads all persisted measurements from disk, including their associated
    /// chart images.
    ///
    /// Reads `saved_measurements.json` from the Documents directory, decodes
    /// the `[TapToneMeasurement]` array with ISO-8601 date decoding, and for
    /// each measurement attempts to load the PNG referenced by
    /// `chartImageFilename` from the same directory.
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
            
            // Load associated images for each measurement
            var loadedMeasurements = measurements
            let documentsDirectory = fileURL.deletingLastPathComponent()
            
            for i in 0..<loadedMeasurements.count {
                if let filename = loadedMeasurements[i].chartImageFilename {
                    let imageURL = documentsDirectory.appendingPathComponent(filename)
                    if let imageData = try? Data(contentsOf: imageURL) {
                        loadedMeasurements[i].chartImageData = imageData
                    }
                }
            }
            
            savedMeasurements = loadedMeasurements
            print("📂 Loaded \(measurements.count) persisted measurements")
        } catch {
            print("❌ Failed to load persisted measurements: \(error)")
        }
    }
    
    /// Writes all saved measurements to `saved_measurements.json` and saves
    /// any associated chart images as separate PNG files.
    ///
    /// Uses pretty-printed, sorted-key JSON encoding with ISO-8601 dates.
    /// `chartImageData` is **not** encoded in the JSON (it is excluded via
    /// `CodingKeys`); instead it is written to a sidecar PNG file whose name
    /// is recorded in `chartImageFilename`.
    ///
    /// Called automatically after every `saveMeasurement`, `deleteMeasurement`,
    /// and `importMeasurements` operation.
    func persistMeasurements() {
        let fileURL = TapToneAnalyzer.measurementsFileURL
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(savedMeasurements)
            try data.write(to: fileURL)
            
            // Also save any chart images
            let documentsDirectory = fileURL.deletingLastPathComponent()
            for measurement in savedMeasurements {
                if let filename = measurement.chartImageFilename,
                   let imageData = measurement.chartImageData {
                    let imageURL = documentsDirectory.appendingPathComponent(filename)
                    try? imageData.write(to: imageURL)
                }
            }
            
            print("💾 Persisted \(savedMeasurements.count) measurements to disk")
        } catch {
            print("❌ Failed to persist measurements: \(error)")
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
    ///     e.g. `"Top — Bridge"`. Used to derive the chart image filename.
    ///   - notes: Free-text user notes to attach to the measurement.
    ///   - includeSpectrum: When `true` and the measurement type is guitar,
    ///     a `SpectrumSnapshot` is generated from the current (frozen or live)
    ///     FFT data.
    ///   - chartImageData: Raw PNG data of the spectrum chart, or `nil` if no
    ///     chart is to be saved.
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
        chartImageData: Data? = nil,
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
                frequencies: isSpectrumFrozen ? frozenFrequencies : fftAnalyzer.frequencies,
                magnitudes: isSpectrumFrozen ? frozenMagnitudes : fftAnalyzer.magnitudes,
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
        
        // Generate filename if image data is provided.
        // Format: <location-slug>-<unix-timestamp>.png
        let imageFilename: String?
        if chartImageData != nil {
            let locationPart = tapLocation?.replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "/", with: "-")
                .lowercased() ?? "measurement"
            let timestampPart = Int(Date().timeIntervalSince1970)
            imageFilename = "\(locationPart)-\(timestampPart).png"
        } else {
            imageFilename = nil
        }
        
        let measurement = TapToneMeasurement(
            peaks: currentPeaks,
            decayTime: currentDecayTime,
            tapLocation: tapLocation,
            notes: notes,
            spectrum: snapshot,
            chartImageFilename: imageFilename,
            chartImageData: chartImageData,
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
            annotationVisibilityMode: annotationVisibilityMode,
            peakModeOverrides: peakModeOverrides.isEmpty ? nil : peakModeOverrides,
            microphoneName: microphoneName,
            microphoneUID: microphoneUID,
            calibrationName: calibrationName
        )
        
        savedMeasurements.append(measurement)
        print("💾 Saved measurement with \(currentPeaks.count) peaks, image: \(imageFilename ?? "none"), type: \(measurementType.shortName)")
        
        // Persist to disk
        persistMeasurements()
    }
    
    /// Removes a measurement from `savedMeasurements` and deletes its
    /// associated chart image file from the Documents directory.
    ///
    /// - Parameter measurement: The ``TapToneMeasurement`` to delete.
    func deleteMeasurement(_ measurement: TapToneMeasurement) {
        // Also delete the associated chart image file if it exists
        if let filename = measurement.chartImageFilename {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let imageURL = documentsDirectory.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: imageURL)
        }
        
        savedMeasurements.removeAll(where: { $0.id == measurement.id })
        
        // Persist to disk
        persistMeasurements()
    }
    
    /// Decodes a JSON data blob into ``TapToneMeasurement`` records and
    /// appends them to `savedMeasurements`.
    ///
    /// If `baseURL` is provided, each measurement's `chartImageFilename` is
    /// resolved relative to `baseURL.deletingLastPathComponent()` and its
    /// image data is loaded if found.
    ///
    /// After import, the UID of each measurement's recording microphone is
    /// compared against `fftAnalyzer.availableInputDevices`. If any microphone
    /// is missing, `microphoneWarning` is set with a list of missing device
    /// names.
    ///
    /// - Parameters:
    ///   - jsonData: Raw JSON data containing an array of encoded
    ///     ``TapToneMeasurement`` values.
    ///   - baseURL: Optional base URL for resolving sidecar image files (e.g.
    ///     the URL of the JSON file that was opened via document picker).
    /// - Returns: The array of newly decoded measurements.
    /// - Throws: A decoding error if `jsonData` is not a valid
    ///   `[TapToneMeasurement]` JSON array.
    func importMeasurements(from jsonData: Data, baseURL: URL? = nil) throws -> [TapToneMeasurement] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        var measurements = try decoder.decode([TapToneMeasurement].self, from: jsonData)
        
        // If baseURL is provided, try to load associated images
        if let baseURL = baseURL {
            for i in 0..<measurements.count {
                if let filename = measurements[i].chartImageFilename {
                    let imageURL = baseURL.deletingLastPathComponent().appendingPathComponent(filename)
                    if let imageData = try? Data(contentsOf: imageURL) {
                        measurements[i].chartImageData = imageData
                        print("📷 Loaded image: \(filename)")
                    }
                }
            }
        }
        
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
            isSpectrumFrozen = false
            frozenFrequencies = []
            frozenMagnitudes = []
            materialTapPhase = .complete
        } else if let snapshot = measurement.spectrumSnapshot {
            frozenFrequencies = snapshot.frequencies
            frozenMagnitudes = snapshot.magnitudes
            isSpectrumFrozen = true
        } else {
            isSpectrumFrozen = true
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
            
            // Restore guitarType setting if available
            if let guitarType = snapshot.guitarType {
                print("  🎸 Publishing guitarType: \(guitarType.rawValue)")
                loadedGuitarType = guitarType
            }
            
            // Restore measurementType setting if available
            if let measurementType = snapshot.measurementType {
                print("  📐 Publishing measurementType: \(measurementType.shortName)")
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
        
        // Stop tap detection when loading a measurement (frozen state)
        isDetecting = false
        currentTapCount = 0
        tapProgress = 0.0
        statusMessage = "Loaded measurement (frozen). Press 'Resume' or 'New Tap' to continue."
        print("  🧊 Spectrum frozen, tap detection disabled")
        
        // Restore annotation offsets
        if let offsets = measurement.peakAnnotationOffsets {
            peakAnnotationOffsets = offsets
            print("  🏷️ Restored \(offsets.count) annotation offsets")
        }
        
        // Restore selected peak IDs; if none saved, default to selecting all peaks
        if let saved = measurement.selectedPeakIDs {
            selectedPeakIDs = Set(saved)
        } else {
            selectedPeakIDs = Set(measurement.peaks.map { $0.id })
        }
        print("  ⭐ Restored \(selectedPeakIDs.count) selected peaks")

        // Restore annotation visibility mode; default to .all if not saved
        annotationVisibilityMode = measurement.annotationVisibilityMode ?? .all
        print("  👁️ Restored annotation visibility: \(annotationVisibilityMode.label)")

        // Restore per-peak mode overrides; nil / empty → all peaks auto-classify
        if let overrides = measurement.peakModeOverrides, !overrides.isEmpty {
            applyModeOverrides(overrides)
            print("  🏷️ Restored \(overrides.count) mode overrides")
        } else {
            peakModeOverrides = [:]
        }
        
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
    ///     original measurement (for accessing `chartImageData` to share as a
    ///     sidecar file).
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
}
