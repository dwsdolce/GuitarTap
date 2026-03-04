//
//  TapToneAnalysisView+Actions.swift
//  GuitarTap
//

import SwiftUI
import AVFoundation

extension TapToneAnalysisView {

    // MARK: - Actions

    func toggleAnalyzer() {
        if fft.isRunning {
            tap.stop()
        } else {
            #if os(iOS)
            // On iOS, request microphone permission first
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.startAnalyzer()
                        } else {
                            print("❌ Microphone permission denied")
                        }
                    }
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.startAnalyzer()
                        } else {
                            print("❌ Microphone permission denied")
                        }
                    }
                }
            }
            #else
            // On macOS, start directly
            startAnalyzer()
            #endif
        }
    }

    func startAnalyzer() {
        // AVAudioEngine.start() is safe to call from the main thread
        // Don't dispatch to background - this can cause deadlocks when the engine
        // tries to update @Published properties on main thread
        do {
            #if os(iOS)
            // Configure audio session for iOS
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
            #endif

            try self.tapToneAnalyzer.start()
        } catch {
            print("❌ Failed to start analyzer: \(error)")
        }
    }

    func saveMeasurement() {
        isSavingMeasurement = true

        // Capture the spectrum image
        DispatchQueue.main.async {
            let spectrumView = self.createExportableSpectrumView()
            let renderer = ImageRenderer(content: spectrumView)

            // Use display scale from environment
            renderer.scale = self.displayScale

            var imageData: Data?

            #if os(iOS)
            if let uiImage = renderer.uiImage,
               let pngData = uiImage.pngData() {
                imageData = pngData
            }
            #elseif os(macOS)
            if let nsImage = renderer.nsImage,
               let tiffData = nsImage.tiffRepresentation,
               let bitmapImage = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                imageData = pngData
            }
            #endif

            let measurementType = TapDisplaySettings.measurementType

            // Build a helper to create a SpectrumSnapshot from a phase spectrum
            func makePhaseSnapshot(magnitudes: [Float], frequencies: [Float]) -> SpectrumSnapshot {
                SpectrumSnapshot(
                    frequencies: frequencies,
                    magnitudes: magnitudes,
                    minFreq: self.minFreq,
                    maxFreq: self.maxFreq,
                    minDB: self.minDB,
                    maxDB: self.maxDB,
                    isLogarithmic: false,
                    showUnknownModes: TapDisplaySettings.showUnknownModes,
                    guitarType: TapDisplaySettings.guitarType,
                    measurementType: measurementType,
                    maxPeaks: self.tap.maxPeaks,
                    materialLength: measurementType == .material ? TapDisplaySettings.materialLength
                                  : measurementType == .brace   ? TapDisplaySettings.braceLength : nil,
                    materialWidth: measurementType == .material ? TapDisplaySettings.materialWidth
                                 : measurementType == .brace   ? TapDisplaySettings.braceWidth : nil,
                    materialThickness: measurementType == .material ? TapDisplaySettings.materialThickness
                                     : measurementType == .brace   ? TapDisplaySettings.braceThickness : nil,
                    materialMass: measurementType == .material ? TapDisplaySettings.materialMass
                                : measurementType == .brace   ? TapDisplaySettings.braceMass : nil
                )
            }

            // For material/brace: build per-phase snapshots. For guitar: build a single snapshot.
            let longSnap: SpectrumSnapshot? = {
                guard !measurementType.isGuitar,
                      let spec = self.tap.longitudinalSpectrum else { return nil }
                return makePhaseSnapshot(magnitudes: spec.magnitudes, frequencies: spec.frequencies)
            }()
            let crossSnap: SpectrumSnapshot? = {
                guard measurementType == .material,
                      let spec = self.tap.crossSpectrum else { return nil }
                return makePhaseSnapshot(magnitudes: spec.magnitudes, frequencies: spec.frequencies)
            }()
            let flcSnap: SpectrumSnapshot? = {
                guard measurementType == .material,
                      let spec = self.tap.flcSpectrum else { return nil }
                return makePhaseSnapshot(magnitudes: spec.magnitudes, frequencies: spec.frequencies)
            }()

            // Save with all data
            self.tapToneAnalyzer.saveMeasurement(
                tapLocation: self.tapLocation.isEmpty ? nil : self.tapLocation,
                notes: self.notes.isEmpty ? nil : self.notes,
                includeSpectrum: true,
                chartImageData: imageData,
                longitudinalSnapshot: longSnap,
                crossSnapshot: crossSnap,
                flcSnapshot: flcSnap,
                annotationOffsets: self.tap.peakAnnotationOffsets,
                selectedLongitudinalPeakID: self.tap.effectiveLongitudinalPeakID,
                selectedCrossPeakID: self.tap.effectiveCrossPeakID,
                selectedFlcPeakID: self.tap.effectiveFlcPeakID,
                microphoneName: self.fft.selectedInputDevice?.name,
                microphoneUID: self.fft.selectedInputDevice?.uid,
                calibrationName: self.fft.activeCalibration?.name
            )

            self.tapLocation = ""
            self.notes = ""
            self.showingSaveSheet = false
            self.isSavingMeasurement = false
        }
    }

    // MARK: - Spectrum Display Helpers

    func updateFrequencyInputFields() {
        minFreqInput = String(format: "%.0f", minFreq)
        maxFreqInput = String(format: "%.0f", maxFreq)
    }

    /// Expand the frequency display range to ensure the given frequency is visible.
    /// Adds 10% padding above/below. Used when material/brace peaks are auto-selected
    /// to ensure they're always in view even if outside the persisted default range.
    func expandFreqRangeToInclude(_ frequency: Float) {
        guard !TapDisplaySettings.measurementType.isGuitar else { return }
        let padding = frequency * 0.10
        if frequency > maxFreq {
            maxFreq = frequency + padding
            maxFreqInput = String(format: "%.0f", maxFreq)
        }
        if frequency < minFreq {
            minFreq = max(1, frequency - padding)
            minFreqInput = String(format: "%.0f", minFreq)
        }
    }

    func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.1fk Hz", freq / 1000)
        } else {
            return String(format: "%.0f Hz", freq)
        }
    }

    /// Auto-scale the dB range to fit the current signal
    func autoScaleDB() {
        let mags = displayMagnitudes.filter { $0 > -100 && $0 < 20 }
        guard !mags.isEmpty else {
            print("⚠️ No valid magnitudes to auto-scale")
            return
        }

        let minMag = mags.min() ?? -100
        let maxMag = mags.max() ?? 0

        // Add 10% padding above and below
        let range = maxMag - minMag
        let padding = max(10, range * 0.1)  // At least 10 dB padding

        let newMinDB = max(-120, minMag - padding)
        let newMaxDB = min(20, maxMag + padding)

        // Ensure minimum 20 dB range
        if newMaxDB - newMinDB < 20 {
            let center = (newMinDB + newMaxDB) / 2
            minDB = center - 10
            maxDB = center + 10
        } else {
            minDB = newMinDB
            maxDB = newMaxDB
        }

        // Update input fields
        minDBInput = String(format: "%.0f", minDB)
        maxDBInput = String(format: "%.0f", maxDB)

        print("📏 Auto-scaled dB range: \(String(format: "%.1f", minDB)) to \(String(format: "%.1f", maxDB)) dB (signal range: \(String(format: "%.1f", minMag)) to \(String(format: "%.1f", maxMag)) dB)")
    }

    /// Toggles auto-scale mode on/off
    func toggleAutoScale() {
        isAutoScaleEnabled.toggle()

        if isAutoScaleEnabled {
            print("🔄 Auto-scale dB enabled - will scale on each update")
            // Perform initial auto-scale
            autoScaleDB()
        } else {
            print("🔄 Auto-scale dB disabled - resetting to default range")
            // Reset to default values
            resetDBToDefaults()
        }
    }

    /// Resets the dB range to default settings
    func resetDBToDefaults() {
        minDB = TapDisplaySettings.minMagnitude
        maxDB = TapDisplaySettings.maxMagnitude
        minDBInput = String(format: "%.0f", minDB)
        maxDBInput = String(format: "%.0f", maxDB)
        print("↩️ Reset dB range to defaults: \(minDB) to \(maxDB) dB")
    }

    // MARK: - Spectrum Export

    func exportCurrentSpectrum() {
        isExportingSpectrum = true

        DispatchQueue.main.async {
            let spectrumView = self.createExportableSpectrumView()
            let renderer = ImageRenderer(content: spectrumView)

            // Use display scale from environment
            renderer.scale = self.displayScale

            // Get PNG data using helper
            #if os(iOS)
            guard let uiImage = renderer.uiImage,
                  let pngData = uiImage.pngData() else {
                self.isExportingSpectrum = false
                return
            }
            #elseif os(macOS)
            guard let nsImage = renderer.nsImage,
                  let tiffData = nsImage.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
                self.isExportingSpectrum = false
                return
            }
            #endif

            // Export using platform-appropriate method
            let filename = "spectrum-\(Int(Date().timeIntervalSince1970)).png"
            FileExportHelper.exportFile(data: pngData, filename: filename, contentType: .png) { success in
                self.isExportingSpectrum = false
                if !success {
                    print("❌ Failed to export spectrum")
                }
            }
        }
    }
}
