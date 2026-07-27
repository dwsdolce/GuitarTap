//
//  TapSettingsView+Actions.swift
//  GuitarTap
//

/// # TapSettingsView+Actions
///
/// Validation, persistence, and calibration-management actions for
/// `TapSettingsView`.
///
/// ## Responsibilities
///
/// | Action | Description |
/// |---|---|
/// | `applySettings()` | Validates all text-field inputs, persists to `TapDisplaySettings`, calls `onApply`, and dismisses the sheet |
/// | `saveCurrentView()` | Persists the current pan/zoom axis state without closing the sheet |
/// | `resetDisplaySettingsToDefaults()` | Restores display-range inputs to factory defaults for the active measurement type |
/// | `resetAnalysisSettings()` | Restores analysis-range, peak-threshold, and max-peaks inputs to factory defaults |
/// | `loadStoredCalibrations()` | Refreshes `storedCalibrations` from `CalibrationStorage` |
/// | `handleCalibrationImport(_:)` | Processes the file-importer result, parses the file, saves the calibration, and activates it |
/// | `deleteAllCalibrations()` | Removes all stored calibrations and clears the active calibration |
/// | `showError(_:)` | Shows the validation-error alert with the supplied message |
///
/// - SeeAlso: `TapSettingsView`, `TapDisplaySettings`, `CalibrationStorage`

import SwiftUI
internal import UniformTypeIdentifiers

extension TapSettingsView {

    // MARK: - Actions

    func applySettings() {
        // Capture the current values before overwriting so we can detect changes.
        let previousMeasurementType = TapDisplaySettings.measurementType
        let previousMeasureFlc = TapDisplaySettings.measureFlc

        // Save measurement type and unknown mode setting
        TapDisplaySettings.measurementType = selectedMeasurementType
        TapDisplaySettings.showUnknownModes = showUnknownModes
        TapDisplaySettings.dumpCaptureAudio = dumpCaptureAudio
        TapDisplaySettings.measureFlc = measureFlc

        // Detect whether the measurement type or FLC toggle changed.
        // Switching between guitar types only (e.g. acoustic → generic) does NOT require
        // a new tap sequence — the captured data is unchanged; only the mode classification
        // ranges and annotations differ.  A full reset IS needed for any *other* type change:
        // guitar ↔ material AND plate ↔ brace (different tap phases), or when the FLC toggle
        // changes.  (Mirrors Python `_needs_restart`, which restarts on any material-type
        // change; the earlier guitar↔material-only check wrongly skipped plate ↔ brace.)
        let typeChanged = selectedMeasurementType != previousMeasurementType
        let bothGuitar = previousMeasurementType.isGuitar && selectedMeasurementType.isGuitar
        let measurementChanged = (typeChanged && !bothGuitar) || measureFlc != previousMeasureFlc
        // A guitar-subtype change (e.g. Classical → Flamenco) keeps the captured data but changes the
        // mode bands, so it re-derives classification and selection without re-capturing. guitarType
        // is derived from measurementType, so this is exactly a guitar↔guitar type change.
        let guitarTypeChanged = typeChanged && bothGuitar

        // Save plate dimensions
        if selectedMeasurementType == .plate {
            if let length = Float(plateLengthInput), length > 0 {
                TapDisplaySettings.plateLength = FieldPrecision.rounded(length, FieldPrecision.linearDimensionMM)
            }
            if let width = Float(plateWidthInput), width > 0 {
                TapDisplaySettings.plateWidth = FieldPrecision.rounded(width, FieldPrecision.linearDimensionMM)
            }
            if let thickness = Float(plateThicknessInput), thickness > 0 {
                TapDisplaySettings.plateThickness = FieldPrecision.rounded(thickness, FieldPrecision.linearDimensionMM)
            }
            if let mass = Float(plateMassInput), mass > 0 {
                TapDisplaySettings.plateMass = FieldPrecision.rounded(mass, FieldPrecision.massG)
            }

            // Save Gore thicknessing settings (always save regardless of FLC state)
            if let bodyLength = Float(guitarBodyLengthInput), bodyLength > 0 {
                TapDisplaySettings.guitarBodyLength = FieldPrecision.rounded(bodyLength, FieldPrecision.bodyDimensionMM)
            }
            if let bodyWidth = Float(guitarBodyWidthInput), bodyWidth > 0 {
                TapDisplaySettings.guitarBodyWidth = FieldPrecision.rounded(bodyWidth, FieldPrecision.bodyDimensionMM)
            }
            TapDisplaySettings.plateStiffnessPreset = plateStiffnessPreset
            if plateStiffnessPreset == .custom,
               let customVal = Float(customPlateStiffnessInput), customVal > 0 {
                TapDisplaySettings.customPlateStiffness = FieldPrecision.rounded(customVal, FieldPrecision.stiffness)
            }
        }

        // Save brace dimensions (separate keys from plate)
        if selectedMeasurementType == .brace {
            if let length = Float(braceLengthInput), length > 0 {
                TapDisplaySettings.braceLength = FieldPrecision.rounded(length, FieldPrecision.linearDimensionMM)
            }
            if let width = Float(braceWidthInput), width > 0 {
                TapDisplaySettings.braceWidth = FieldPrecision.rounded(width, FieldPrecision.linearDimensionMM)
            }
            if let thickness = Float(braceThicknessInput), thickness > 0 {
                TapDisplaySettings.braceThickness = FieldPrecision.rounded(thickness, FieldPrecision.linearDimensionMM)
            }
            if let mass = Float(braceMassInput), mass > 0 {
                TapDisplaySettings.braceMass = FieldPrecision.rounded(mass, FieldPrecision.massG)
            }
        }

        // Parse and validate display frequency range
        guard let newMinFreq = Float(minFreqInput),
              let newMaxFreq = Float(maxFreqInput) else {
            showError("Invalid display frequency values. Please enter valid numbers.")
            return
        }

        let validatedFreq = TapDisplaySettings.validateFrequencyRange(
            minFreq: newMinFreq,
            maxFreq: newMaxFreq
        )

        // Parse and validate display magnitude range
        guard let newMinDB = Float(minDBInput),
              let newMaxDB = Float(maxDBInput) else {
            showError("Invalid display magnitude values. Please enter valid numbers.")
            return
        }

        let validatedDB = TapDisplaySettings.validateMagnitudeRange(
            minDB: newMinDB,
            maxDB: newMaxDB
        )

        // Parse and validate peak threshold
        guard let newPeakThreshold = Float(peakMinThresholdInput) else {
            showError("Invalid peak threshold value. Please enter a valid number.")
            return
        }

        // Clamp peak threshold to reasonable range
        let clampedThreshold = max(-120, min(newPeakThreshold, 0))

        // Apply validated values to bindings
        minFreq = validatedFreq.min
        maxFreq = validatedFreq.max
        minDB = validatedDB.min
        maxDB = validatedDB.max
        peakMinThreshold = clampedThreshold

        // Persist all settings to UserDefaults (frequency range is stored per measurement type)
        TapDisplaySettings.setMinFrequency(validatedFreq.min, for: selectedMeasurementType)
        TapDisplaySettings.setMaxFrequency(validatedFreq.max, for: selectedMeasurementType)
        TapDisplaySettings.minMagnitude = validatedDB.min
        TapDisplaySettings.maxMagnitude = validatedDB.max
        TapDisplaySettings.peakMinThreshold = clampedThreshold

        // Update input fields with validated values (in case they were clamped)
        minFreqInput = FieldPrecision.string(validatedFreq.min, FieldPrecision.frequencyHz)
        maxFreqInput = FieldPrecision.string(validatedFreq.max, FieldPrecision.frequencyHz)
        minDBInput = FieldPrecision.string(validatedDB.min, FieldPrecision.magnitudeDB)
        maxDBInput = FieldPrecision.string(validatedDB.max, FieldPrecision.magnitudeDB)
        peakMinThresholdInput = FieldPrecision.string(clampedThreshold, FieldPrecision.magnitudeDB)

        onApply?(measurementChanged, guitarTypeChanged)
        dismiss()
    }

    func saveCurrentView() {
        // Persist the current session axis range to UserDefaults
        TapDisplaySettings.setMinFrequency(minFreq, for: selectedMeasurementType)
        TapDisplaySettings.setMaxFrequency(maxFreq, for: selectedMeasurementType)
        TapDisplaySettings.minMagnitude = minDB
        TapDisplaySettings.maxMagnitude = maxDB
        // Reflect the saved values in the input fields
        minFreqInput = FieldPrecision.string(minFreq, FieldPrecision.frequencyHz)
        maxFreqInput = FieldPrecision.string(maxFreq, FieldPrecision.frequencyHz)
        minDBInput = FieldPrecision.string(minDB, FieldPrecision.magnitudeDB)
        maxDBInput = FieldPrecision.string(maxDB, FieldPrecision.magnitudeDB)
    }

    func resetDisplaySettingsToDefaults() {
        // Reset display settings to factory defaults (frequency defaults vary by measurement type)
        minFreqInput = FieldPrecision.string(TapDisplaySettings.defaultMinFrequency(for: selectedMeasurementType), FieldPrecision.frequencyHz)
        maxFreqInput = FieldPrecision.string(TapDisplaySettings.defaultMaxFrequency(for: selectedMeasurementType), FieldPrecision.frequencyHz)
        minDBInput = FieldPrecision.string(TapDisplaySettings.defaultMinMagnitude, FieldPrecision.magnitudeDB)
        maxDBInput = FieldPrecision.string(TapDisplaySettings.defaultMaxMagnitude, FieldPrecision.magnitudeDB)
    }

    func resetAnalysisSettings() {
        // Reset analysis settings to defaults. (The analysis frequency range is a fixed 30–2000 Hz
        // constant, no longer a user setting — nothing to reset there.)
        peakMinThresholdInput = FieldPrecision.string(TapDisplaySettings.defaultPeakMinThreshold, FieldPrecision.magnitudeDB)
    }

    // MARK: - Calibration Helpers

    func loadStoredCalibrations() {
        storedCalibrations = CalibrationStorage.shared.loadAll()
    }

    func handleCalibrationImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                calibrationImportError = "Could not access the selected file. Please try again."
                showingCalibrationError = true
                return
            }

            defer {
                url.stopAccessingSecurityScopedResource()
            }

            do {
                let calibration = try CalibrationFileParser.parse(url: url)
                CalibrationStorage.shared.save(calibration)

                // Activate the newly imported calibration
                fftAnalyzer.activeCalibration = calibration

                // Refresh the list
                loadStoredCalibrations()

                gtLog("✅ Imported calibration '\(calibration.name)' with \(calibration.correctionPoints.count) data points")
            } catch {
                calibrationImportError = error.localizedDescription
                showingCalibrationError = true
            }

        case .failure(let error):
            calibrationImportError = error.localizedDescription
            showingCalibrationError = true
        }
    }

    func deleteAllCalibrations() {
        // Clear active calibration first
        fftAnalyzer.activeCalibration = nil

        // Delete all stored calibrations
        for calibration in storedCalibrations {
            CalibrationStorage.shared.delete(calibration)
        }

        // Refresh the list
        loadStoredCalibrations()
    }

    // MARK: - Error Presentation

    func showError(_ message: String) {
        validationMessage = message
        showValidationError = true
    }
}
