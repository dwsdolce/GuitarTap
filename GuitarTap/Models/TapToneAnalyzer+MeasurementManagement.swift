//
//  TapToneAnalyzer+MeasurementManagement.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import SwiftUI

extension TapToneAnalyzer {

    // MARK: - Measurement Persistence

    /// File URL for persisted measurements
    static var measurementsFileURL: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("saved_measurements.json")
    }
    
    /// Load measurements from persistent storage
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
    
    /// Save measurements to persistent storage
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
    
    /// Save current measurement with optional metadata and chart image
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
        // For material/brace: per-phase snapshots are used instead; no combined snapshot needed.
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
        
        // Generate filename if image data is provided
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
            // Include peak selections for material and brace measurements
            selectedLongitudinalPeakID: !measurementType.isGuitar ? selectedLongitudinalPeakID : nil,
            selectedCrossPeakID: measurementType == .material ? selectedCrossPeakID : nil,
            selectedFlcPeakID: measurementType == .material ? selectedFlcPeakID : nil,
            longitudinalSnapshot: !measurementType.isGuitar ? longitudinalSnapshot : nil,
            crossSnapshot: measurementType == .material ? crossSnapshot : nil,
            flcSnapshot: measurementType == .material ? flcSnapshot : nil,
            hiddenPeakIDs: hiddenPeakIDs.isEmpty ? nil : Array(hiddenPeakIDs),
            microphoneName: microphoneName,
            microphoneUID: microphoneUID,
            calibrationName: calibrationName
        )
        
        savedMeasurements.append(measurement)
        print("💾 Saved measurement with \(currentPeaks.count) peaks, image: \(imageFilename ?? "none"), type: \(measurementType.shortName)")
        
        // Persist to disk
        persistMeasurements()
    }
    
    /// Delete a saved measurement
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
    
    /// Import measurements from JSON data and optionally load associated images
    /// Returns the array of imported measurements
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
    
    /// Load a measurement's data into the current view (recreate the plot)
    func loadMeasurement(_ measurement: TapToneMeasurement) {
        print("🔄 Loading measurement...")

        // Track the original timestamp so the Results-panel PDF can use it
        sourceMeasurementTimestamp = measurement.timestamp

        // Restore peaks
        currentPeaks = measurement.peaks
        
        // Restore decay time
        currentDecayTime = measurement.decayTime
        
        // Determine if this is a material/brace measurement with per-phase spectra
        let hasMaterialSpectra = measurement.longitudinalSnapshot != nil
        
        // Restore per-phase spectra for material/brace measurements
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
        
        // For material/brace: use per-phase spectra for display (no frozen spectrum needed)
        // For guitar: restore the single frozen spectrum as before
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
        
        // Restore display settings from any available snapshot (prefer longitudinal for material)
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
            
            // Restore material dimensions if available (for material measurements)
            if let materialLength = snapshot.materialLength {
                print("  📏 Publishing material dimensions: L=\(materialLength)mm")
                loadedMaterialLength = materialLength
            }
            if let materialWidth = snapshot.materialWidth {
                loadedMaterialWidth = materialWidth
            }
            if let materialThickness = snapshot.materialThickness {
                loadedMaterialThickness = materialThickness
            }
            if let materialMass = snapshot.materialMass {
                loadedMaterialMass = materialMass
            }
        } else {
            print("  ⚠️ No spectrum snapshot in measurement")
        }
        
        // Restore material peak selections directly into the model properties
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
        
        // Restore hidden peak IDs
        hiddenPeakIDs = Set(measurement.hiddenPeakIDs ?? [])
        print("  👁️ Restored \(hiddenPeakIDs.count) hidden peaks")
        
        // Restore analysis settings if available - set both internal and published values
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

    /// Export a single measurement as JSON with image (calls completion with JSON and measurement)
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
    
    /// Import measurements from JSON
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
