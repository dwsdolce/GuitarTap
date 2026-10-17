//
//  MicrophoneCalibration.swift
//  GuitarTap
//
//  Microphone calibration support for measurement microphones like UMIK-1.
//  Parses calibration files and applies frequency-dependent corrections to FFT data.
//
// @parity dsp/calibration tests=test/file-playback,test/calibration,test/self-regression
/// # MicrophoneCalibration
///
/// Frequency-response correction for measurement microphones using externally-supplied
/// calibration data.
///
/// Most measurement microphones (e.g. MiniDSP UMIK-1) ship with a per-unit calibration file
/// that describes the deviation of the microphone's actual frequency response from a flat
/// 0 dB reference.  Applying these corrections to the raw FFT magnitudes yields a spectrum
/// that more closely represents the true acoustic pressure at the microphone diaphragm.
///
/// ## Supported File Format (UMIK-1 / REW)
///
/// ```
/// "Sens Factor =-18.39dB, SESSION REF=94.0dBSPL, ..."
///  20.0   0.12
///  25.0  -0.05
///  31.5   0.31
///  ...
/// 20000  -2.14
/// ```
///
/// Lines beginning with `"` or `*` are header/comment lines.  The optional header may contain
/// a `Sens Factor` and a `SESSION REF` value; both are stored but not currently applied
/// automatically — the correction array is used directly as additive dB offsets.
///
/// Columns are separated by tab, space, or comma.  Only frequencies in the range 1–24 000 Hz
/// are imported.
///
/// ## Interpolation Strategy
///
/// Corrections between data points are computed by **linear interpolation**.  Frequencies
/// below the lowest calibrated point use the first correction value (flat extrapolation);
/// frequencies above the highest use the last correction value.  This conservative strategy
/// avoids introducing artefacts from extrapolation beyond the calibrated range.
import Foundation
internal import UniformTypeIdentifiers

// MARK: - Custom UTType for Calibration Files

extension UTType {

    /// Custom UTType for `.cal` measurement microphone calibration files.
    ///
    /// Created as a text-conforming type so that document pickers accept `.cal` files
    /// from common measurement-microphone software (UMIK-1, REW).
    static var calibrationFile: UTType {
        UTType(filenameExtension: "cal", conformingTo: .text) ?? .text
    }
}

// MARK: - MicrophoneCalibration

/// A parsed microphone calibration curve containing frequency-dependent dB corrections.
///
/// After parsing a calibration file with ``CalibrationFileParser``, store the result via
/// ``CalibrationStorage`` and associate it with an input device so that
/// ``RealtimeFFTAnalyzer`` can apply it automatically whenever that device is selected.
///
/// - SeeAlso: ``CalibrationFileParser`` for parsing `.cal` files.
/// - SeeAlso: ``CalibrationStorage`` for persistence and device-mapping.
struct MicrophoneCalibration: Codable, Identifiable, Equatable {

    // MARK: - Properties

    /// Stable unique identifier for this calibration profile.
    let id: UUID

    /// Human-readable display name, typically the filename or the microphone serial number.
    let name: String

    /// Sensitivity factor extracted from the calibration file header, in dB.
    ///
    /// From the UMIK-1 header field `Sens Factor`.  Stored for provenance but not
    /// currently used in automatic correction application.  `nil` if the header did not
    /// contain this value.
    let sensitivityFactor: Float?

    /// Reference SPL level from the calibration file header, in dBSPL.
    ///
    /// From the UMIK-1 field `SESSION REF` or the REW field `SPL`.  Stored for
    /// provenance only.  `nil` if absent in the header.
    let referenceLevel: Float?

    /// Frequency-correction data points, sorted ascending by frequency.
    ///
    /// The ``correction(at:)`` method interpolates between these points to produce a
    /// correction value for any frequency in the analysis range.
    let correctionPoints: [CorrectionPoint]

    /// Wall-clock date on which this calibration file was imported into the app.
    let importDate: Date

    // MARK: - CorrectionPoint

    /// A single (frequency, correction) pair from the calibration data file.
    struct CorrectionPoint: Codable, Equatable {

        /// Frequency in Hz for this correction entry.
        let frequency: Float

        /// Additive magnitude correction in dB to apply to the FFT spectrum at ``frequency``.
        ///
        /// Positive values increase the displayed magnitude; negative values reduce it.
        let correction: Float
    }

    // MARK: - Initialization

    /// Creates a `MicrophoneCalibration` with the given correction data.
    ///
    /// ``correctionPoints`` is sorted ascending by frequency automatically regardless of
    /// the order supplied.
    ///
    /// - Parameters:
    ///   - id: Unique identifier.  Defaults to a new UUID.
    ///   - name: Display name for this calibration profile.
    ///   - sensitivityFactor: Optional sensitivity factor from the file header, in dB.
    ///   - referenceLevel: Optional reference SPL from the file header, in dBSPL.
    ///   - correctionPoints: Raw correction data points (will be sorted by frequency).
    ///   - importDate: Date the file was imported.  Defaults to now.
    init(id: UUID = UUID(),
         name: String,
         sensitivityFactor: Float? = nil,
         referenceLevel: Float? = nil,
         correctionPoints: [CorrectionPoint],
         importDate: Date = Date()) {
        self.id = id
        self.name = name
        self.sensitivityFactor = sensitivityFactor
        self.referenceLevel = referenceLevel
        // Sort correction points by frequency so binary-search-style lookups are valid.
        self.correctionPoints = correctionPoints.sorted { $0.frequency < $1.frequency }
        self.importDate = importDate
    }

    // MARK: - Correction Interpolation

    /// Returns the calibration correction for a specific frequency using linear interpolation.
    ///
    /// **Edge-case handling:**
    /// - Empty `correctionPoints` → returns 0 (no correction).
    /// - Single data point → returns that point's correction for all frequencies.
    /// - Frequency below lowest calibrated point → uses the lowest point's correction (flat extrapolation).
    /// - Frequency above highest calibrated point → uses the highest point's correction (flat extrapolation).
    ///
    /// - Parameter frequency: The FFT bin centre frequency, in Hz.
    /// - Returns: The additive dB correction to apply.  Add this value to the raw magnitude.
    func correction(at frequency: Float) -> Float {
        guard !correctionPoints.isEmpty else { return 0 }

        // Single-point calibration: apply the same correction at all frequencies.
        if correctionPoints.count == 1 {
            return correctionPoints[0].correction
        }

        // Flat extrapolation below the calibrated range.
        if frequency <= correctionPoints.first!.frequency {
            return correctionPoints.first!.correction
        }

        // Flat extrapolation above the calibrated range.
        if frequency >= correctionPoints.last!.frequency {
            return correctionPoints.last!.correction
        }

        // Linear interpolation between the two bracketing data points.
        for i in 0..<(correctionPoints.count - 1) {
            let low = correctionPoints[i]
            let high = correctionPoints[i + 1]

            if frequency >= low.frequency && frequency <= high.frequency {
                // t = normalised position in the [low, high] interval.
                let t = (frequency - low.frequency) / (high.frequency - low.frequency)
                return low.correction + t * (high.correction - low.correction)
            }
        }

        return 0  // Unreachable given the edge-case guards above, but required by the type system.
    }

    /// Returns calibration corrections for an array of frequencies in a single pass.
    ///
    /// Equivalent to calling ``correction(at:)`` for each element, but expressed as a map
    /// for convenient use in FFT pipelines.
    ///
    /// - Parameter frequencies: Array of FFT bin centre frequencies, in Hz.
    /// - Returns: Array of additive dB corrections, parallel to `frequencies`.
    func corrections(for frequencies: [Float]) -> [Float] {
        return frequencies.map { correction(at: $0) }
    }

    // MARK: - Equatable

    /// Two calibrations are equal when their ``id`` values match.
    static func == (lhs: MicrophoneCalibration, rhs: MicrophoneCalibration) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - CalibrationFileParser

/// Parses UMIK-1 style measurement-microphone calibration files into ``MicrophoneCalibration`` values.
///
/// Supports both the standard UMIK-1 format (header line starting with `"`) and the REW
/// (Room EQ Wizard) format (comment lines starting with `*`).  Data lines contain whitespace-,
/// tab-, or comma-separated frequency–correction pairs.
struct CalibrationFileParser {

    // MARK: - Errors

    /// Errors that can occur while parsing a calibration file.
    enum ParseError: Error, LocalizedError {

        /// The file at the specified URL could not be found or opened.
        case fileNotFound

        /// The file content does not match any recognised calibration format.
        case invalidFormat

        /// The file was parsed successfully but contained no valid data points.
        case noDataPoints

        /// A low-level file-read error with an associated message.
        case readError(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "Calibration file not found"
            case .invalidFormat:
                return "Invalid calibration file format"
            case .noDataPoints:
                return "No calibration data points found in file"
            case .readError(let message):
                return "Error reading file: \(message)"
            }
        }
    }

    // MARK: - Parsing

    /// Parses a UMIK-1 style calibration file at the given URL.
    ///
    /// The file name (without extension) is used as the default display name for the
    /// resulting calibration unless overridden by the `name` parameter.
    ///
    /// **File format:**
    /// ```
    /// "Sens Factor =-18.39dB, SESSION REF=94.0dBSPL, ..."
    ///  20.0   0.12
    ///  25.0  -0.05
    ///  ...
    /// ```
    /// Lines beginning with `"` or `*` are treated as header/comment lines.
    /// Data lines contain `frequency<separator>correction` where the separator may be
    /// a tab, space, or comma.
    ///
    /// - Parameters:
    ///   - url: File URL of the `.cal` calibration file.
    ///   - name: Optional display name override.  Defaults to the filename stem.
    /// - Returns: A fully parsed ``MicrophoneCalibration`` ready for storage.
    /// - Throws: ``ParseError`` if the file cannot be read or contains no valid data points.
    static func parse(url: URL, name: String? = nil) throws -> MicrophoneCalibration {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ParseError.readError(error.localizedDescription)
        }

        return try parse(content: content, name: name ?? url.deletingPathExtension().lastPathComponent)
    }

    /// Parses calibration data from a string, used when the content has already been read.
    ///
    /// - Parameters:
    ///   - content: The full calibration file content as a UTF-8 string.
    ///   - name: Display name for the resulting calibration profile.
    /// - Returns: A fully parsed ``MicrophoneCalibration``.
    /// - Throws: ``ParseError/noDataPoints`` if no valid frequency–correction pairs are found.
    static func parse(content: String, name: String) throws -> MicrophoneCalibration {
        let lines = content.components(separatedBy: .newlines)

        var sensitivityFactor: Float?
        var referenceLevel: Float?
        var correctionPoints: [MicrophoneCalibration.CorrectionPoint] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip blank lines.
            if trimmed.isEmpty {
                continue
            }

            // Header / comment lines (UMIK-1 uses ", REW uses *).
            if trimmed.hasPrefix("\"") || trimmed.hasPrefix("*") {
                // Extract optional sensitivity factor: "Sens Factor = -18.39dB"
                if let sensMatch = extractValue(from: trimmed, pattern: "Sens Factor\\s*=\\s*([+-]?[\\d.]+)\\s*dB") {
                    sensitivityFactor = sensMatch
                }

                // Extract optional reference SPL (UMIK-1 format): "SESSION REF=94.0dBSPL"
                if let refMatch = extractValue(from: trimmed, pattern: "SESSION REF\\s*=\\s*([\\d.]+)\\s*dBSPL") {
                    referenceLevel = refMatch
                }

                // Extract optional reference SPL (REW format): "SPL xxxx dB"
                if let splMatch = extractValue(from: trimmed, pattern: "SPL\\s+([\\d.]+)\\s*dB") {
                    referenceLevel = splMatch
                }

                continue
            }

            // Data line: parse frequency and correction, accepting tab, space, or comma separators.
            let components = trimmed.components(separatedBy: CharacterSet(charactersIn: "\t ,"))
                .filter { !$0.isEmpty }

            if components.count >= 2,
               let frequency = Float(components[0]),
               let correction = Float(components[1]) {
                // Only include frequencies within the audible range to avoid importing irrelevant data.
                if frequency >= 1 && frequency <= 24000 {
                    correctionPoints.append(
                        MicrophoneCalibration.CorrectionPoint(
                            frequency: frequency,
                            correction: correction
                        )
                    )
                }
            }
        }

        guard !correctionPoints.isEmpty else {
            throw ParseError.noDataPoints
        }

        return MicrophoneCalibration(
            name: name,
            sensitivityFactor: sensitivityFactor,
            referenceLevel: referenceLevel,
            correctionPoints: correctionPoints
        )
    }

    // MARK: - Private Helpers

    /// Extracts the first floating-point value captured by `pattern` from `string`.
    ///
    /// - Parameters:
    ///   - string: The string to search.
    ///   - pattern: A case-insensitive regex with one capture group surrounding the numeric value.
    /// - Returns: The parsed `Float`, or `nil` if the pattern does not match or parsing fails.
    private static func extractValue(from string: String, pattern: String) -> Float? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: string) else {
            return nil
        }

        return Float(string[valueRange])
    }
}

// MARK: - CalibrationStorage

/// Persists and retrieves ``MicrophoneCalibration`` profiles in `TapDisplaySettings.defaults`
/// (the standard defaults; an isolated suite under test).
///
/// Calibrations are associated with audio input devices by their UID, so
/// ``RealtimeFFTAnalyzer`` applies a device's profile whenever that device is selected: its
/// mapping (``setCalibration(_:forDeviceUID:)``), or no correction when it has none. The
/// global ``activeCalibrationID`` records the last calibration chosen.
class CalibrationStorage {

    // MARK: - Singleton

    /// Shared singleton instance used throughout the app.
    static let shared = CalibrationStorage()

    // MARK: - Private Keys

    /// `UserDefaults` key under which the JSON-encoded calibration array is stored.
    private let storageKey = "storedCalibrations"

    /// `UserDefaults` key under which the UUID string of the global active calibration is stored.
    private let activeCalibrationKey = "activeCalibrationID"

    private init() {}

    // MARK: - CRUD

    /// Saves or replaces a calibration in persistent storage.
    ///
    /// If a calibration with the same ``MicrophoneCalibration/id`` already exists it is
    /// replaced; otherwise the new entry is appended.
    ///
    /// - Parameter calibration: The calibration profile to save.
    func save(_ calibration: MicrophoneCalibration) {
        var calibrations = loadAll()

        // Replace any existing entry with the same ID.
        calibrations.removeAll { $0.id == calibration.id }
        calibrations.append(calibration)

        if let encoded = try? JSONEncoder().encode(calibrations) {
            TapDisplaySettings.defaults.set(encoded, forKey: storageKey)
        }
    }

    /// Loads and returns all stored calibration profiles.
    ///
    /// Returns an empty array if no calibrations have been saved or if decoding fails.
    func loadAll() -> [MicrophoneCalibration] {
        guard let data = TapDisplaySettings.defaults.data(forKey: storageKey),
              let calibrations = try? JSONDecoder().decode([MicrophoneCalibration].self, from: data) else {
            return []
        }
        return calibrations
    }

    /// Removes a calibration from persistent storage.
    ///
    /// Also clears ``activeCalibrationID`` if the deleted calibration was the active one.
    ///
    /// - Parameter calibration: The calibration profile to delete.
    func delete(_ calibration: MicrophoneCalibration) {
        var calibrations = loadAll()
        calibrations.removeAll { $0.id == calibration.id }

        if let encoded = try? JSONEncoder().encode(calibrations) {
            TapDisplaySettings.defaults.set(encoded, forKey: storageKey)
        }

        // Clear the global active calibration if we just deleted it.
        if activeCalibrationID == calibration.id {
            activeCalibrationID = nil
        }
    }

    // MARK: - Global Active Calibration

    /// The UUID of the global active calibration, persisted in `UserDefaults`.
    ///
    /// This is the fallback calibration applied when no device-specific mapping exists for
    /// the currently selected input device.  Set to `nil` to disable global correction.
    var activeCalibrationID: UUID? {
        get {
            guard let uuidString = TapDisplaySettings.defaults.string(forKey: activeCalibrationKey) else {
                return nil
            }
            return UUID(uuidString: uuidString)
        }
        set {
            if let id = newValue {
                TapDisplaySettings.defaults.set(id.uuidString, forKey: activeCalibrationKey)
            } else {
                TapDisplaySettings.defaults.removeObject(forKey: activeCalibrationKey)
            }
        }
    }

    /// The global active ``MicrophoneCalibration`` object, loaded on demand.
    ///
    /// Returns `nil` if no global active calibration is set or if the referenced ID is
    /// not found in storage.
    var activeCalibration: MicrophoneCalibration? {
        guard let id = activeCalibrationID else { return nil }
        return loadAll().first { $0.id == id }
    }

    // MARK: - Device-Specific Calibration Mapping

    /// `UserDefaults` key for the `[deviceUID: calibrationUUID]` string dictionary.
    private let deviceCalibrationMapKey = "deviceCalibrationMap"

    /// Associates a calibration with a specific audio input device.
    ///
    /// Once set, ``RealtimeFFTAnalyzer`` automatically loads this calibration whenever
    /// the specified device is selected, taking priority over the global ``activeCalibration``.
    ///
    /// - Parameters:
    ///   - calibrationID: The UUID of the calibration to associate, or `nil` to clear the mapping.
    ///   - deviceUID: The ``AVAudioDevice/uid`` of the target audio device.
    func setCalibration(_ calibrationID: UUID?, forDeviceUID deviceUID: String) {
        var mapping = loadDeviceCalibrationMap()

        if let id = calibrationID {
            mapping[deviceUID] = id.uuidString
        } else {
            mapping.removeValue(forKey: deviceUID)
        }

        if let encoded = try? JSONEncoder().encode(mapping) {
            TapDisplaySettings.defaults.set(encoded, forKey: deviceCalibrationMapKey)
        }
    }

    /// Returns the UUID of the calibration associated with a specific audio device, if any.
    ///
    /// - Parameter deviceUID: The ``AVAudioDevice/uid`` to look up.
    /// - Returns: The associated calibration UUID, or `nil` if no mapping exists.
    func calibrationID(forDeviceUID deviceUID: String) -> UUID? {
        let mapping = loadDeviceCalibrationMap()
        guard let uuidString = mapping[deviceUID] else { return nil }
        return UUID(uuidString: uuidString)
    }

    /// Returns the ``MicrophoneCalibration`` associated with a specific audio device, if any.
    ///
    /// - Parameter deviceUID: The ``AVAudioDevice/uid`` to look up.
    /// - Returns: The full calibration profile, or `nil` if no mapping exists or the
    ///   referenced calibration has been deleted.
    func calibration(forDeviceUID deviceUID: String) -> MicrophoneCalibration? {
        guard let id = calibrationID(forDeviceUID: deviceUID) else { return nil }
        return loadAll().first { $0.id == id }
    }

    /// Loads the raw `[deviceUID: calibrationUUIDString]` dictionary from `UserDefaults`.
    private func loadDeviceCalibrationMap() -> [String: String] {
        guard let data = TapDisplaySettings.defaults.data(forKey: deviceCalibrationMapKey),
              let mapping = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return mapping
    }
}
