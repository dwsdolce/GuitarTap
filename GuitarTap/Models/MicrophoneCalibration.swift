//
//  MicrophoneCalibration.swift
//  GuitarTap
//
//  Microphone calibration support for measurement microphones like UMIK-1.
//  Parses calibration files and applies frequency-dependent corrections to FFT data.
//

import Foundation
internal import UniformTypeIdentifiers

// MARK: - Custom UTType for Calibration Files

extension UTType {
    /// Calibration file type (.cal) used by measurement microphones
    static var calibrationFile: UTType {
        UTType(filenameExtension: "cal", conformingTo: .text) ?? .text
    }
}

/// Represents a microphone calibration curve with frequency-dependent corrections.
/// Supports UMIK-1 and similar measurement microphone calibration file formats.
struct MicrophoneCalibration: Codable, Identifiable, Equatable {
    
    /// Unique identifier for this calibration
    let id: UUID
    
    /// Display name for the calibration (typically the filename or microphone serial)
    let name: String
    
    /// Sensitivity factor in dB (from calibration file header, if available)
    let sensitivityFactor: Float?
    
    /// Reference SPL level in dB (from calibration file header, if available)
    let referenceLevel: Float?
    
    /// Frequency correction data points sorted by frequency
    /// Each point contains (frequency in Hz, correction in dB)
    let correctionPoints: [CorrectionPoint]
    
    /// Date the calibration was imported
    let importDate: Date
    
    /// A single frequency/correction data point
    struct CorrectionPoint: Codable, Equatable {
        let frequency: Float
        let correction: Float
    }
    
    // MARK: - Initialization
    
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
        self.correctionPoints = correctionPoints.sorted { $0.frequency < $1.frequency }
        self.importDate = importDate
    }
    
    // MARK: - Correction Interpolation
    
    /// Calculates the calibration correction for a given frequency using linear interpolation.
    /// - Parameter frequency: The frequency in Hz to get the correction for
    /// - Returns: The correction value in dB to add to the measured magnitude
    func correction(at frequency: Float) -> Float {
        guard !correctionPoints.isEmpty else { return 0 }
        
        // Handle edge cases
        if correctionPoints.count == 1 {
            return correctionPoints[0].correction
        }
        
        // Below lowest calibrated frequency
        if frequency <= correctionPoints.first!.frequency {
            return correctionPoints.first!.correction
        }
        
        // Above highest calibrated frequency
        if frequency >= correctionPoints.last!.frequency {
            return correctionPoints.last!.correction
        }
        
        // Find surrounding points and interpolate
        for i in 0..<(correctionPoints.count - 1) {
            let low = correctionPoints[i]
            let high = correctionPoints[i + 1]
            
            if frequency >= low.frequency && frequency <= high.frequency {
                // Linear interpolation
                let t = (frequency - low.frequency) / (high.frequency - low.frequency)
                return low.correction + t * (high.correction - low.correction)
            }
        }
        
        return 0
    }
    
    /// Pre-computes corrections for an array of frequencies (more efficient for FFT processing)
    /// - Parameter frequencies: Array of frequencies in Hz
    /// - Returns: Array of corrections in dB, same length as input
    func corrections(for frequencies: [Float]) -> [Float] {
        return frequencies.map { correction(at: $0) }
    }
    
    // MARK: - Equatable
    
    static func == (lhs: MicrophoneCalibration, rhs: MicrophoneCalibration) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Calibration File Parser

/// Parser for measurement microphone calibration files (UMIK-1 format and similar)
struct CalibrationFileParser {
    
    /// Errors that can occur during calibration file parsing
    enum ParseError: Error, LocalizedError {
        case fileNotFound
        case invalidFormat
        case noDataPoints
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
    
    /// Parses a UMIK-1 style calibration file
    /// 
    /// UMIK-1 calibration file format:
    /// - First line may contain metadata like: "Sens Factor =-18.39dB, SESSION REF=94.0dBSPL"
    /// - Subsequent lines contain: frequency<whitespace>correction
    /// - Frequency in Hz, correction in dB
    /// - Lines starting with * or " are comments/metadata
    ///
    /// - Parameters:
    ///   - url: URL of the calibration file
    ///   - name: Optional name override (defaults to filename)
    /// - Returns: Parsed MicrophoneCalibration object
    static func parse(url: URL, name: String? = nil) throws -> MicrophoneCalibration {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ParseError.readError(error.localizedDescription)
        }
        
        return try parse(content: content, name: name ?? url.deletingPathExtension().lastPathComponent)
    }
    
    /// Parses calibration data from a string
    /// - Parameters:
    ///   - content: The calibration file content as a string
    ///   - name: Name for the calibration
    /// - Returns: Parsed MicrophoneCalibration object
    static func parse(content: String, name: String) throws -> MicrophoneCalibration {
        let lines = content.components(separatedBy: .newlines)
        
        var sensitivityFactor: Float?
        var referenceLevel: Float?
        var correctionPoints: [MicrophoneCalibration.CorrectionPoint] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines
            if trimmed.isEmpty {
                continue
            }
            
            // Parse header/metadata lines
            if trimmed.hasPrefix("\"") || trimmed.hasPrefix("*") {
                // Try to extract sensitivity factor
                if let sensMatch = extractValue(from: trimmed, pattern: "Sens Factor\\s*=\\s*([+-]?[\\d.]+)\\s*dB") {
                    sensitivityFactor = sensMatch
                }
                
                // Try to extract reference level
                if let refMatch = extractValue(from: trimmed, pattern: "SESSION REF\\s*=\\s*([\\d.]+)\\s*dBSPL") {
                    referenceLevel = refMatch
                }
                
                // Also try REW format: "SPL xxxx dB"
                if let splMatch = extractValue(from: trimmed, pattern: "SPL\\s+([\\d.]+)\\s*dB") {
                    referenceLevel = splMatch
                }
                
                continue
            }
            
            // Parse data lines: frequency<whitespace>correction
            // Handle various separators: tabs, spaces, commas
            let components = trimmed.components(separatedBy: CharacterSet(charactersIn: "\t ,"))
                .filter { !$0.isEmpty }
            
            if components.count >= 2,
               let frequency = Float(components[0]),
               let correction = Float(components[1]) {
                // Only include frequencies in audible range
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
    
    /// Extracts a numeric value from a string using a regex pattern
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

// MARK: - Calibration Storage

/// Manages persistence of calibration files
class CalibrationStorage {
    
    /// Shared instance
    static let shared = CalibrationStorage()
    
    /// UserDefaults key for stored calibrations
    private let storageKey = "storedCalibrations"
    
    /// UserDefaults key for active calibration ID
    private let activeCalibrationKey = "activeCalibrationID"
    
    private init() {}
    
    /// Saves a calibration to persistent storage
    func save(_ calibration: MicrophoneCalibration) {
        var calibrations = loadAll()
        
        // Remove existing calibration with same ID if present
        calibrations.removeAll { $0.id == calibration.id }
        calibrations.append(calibration)
        
        if let encoded = try? JSONEncoder().encode(calibrations) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    /// Loads all stored calibrations
    func loadAll() -> [MicrophoneCalibration] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let calibrations = try? JSONDecoder().decode([MicrophoneCalibration].self, from: data) else {
            return []
        }
        return calibrations
    }
    
    /// Deletes a calibration from storage
    func delete(_ calibration: MicrophoneCalibration) {
        var calibrations = loadAll()
        calibrations.removeAll { $0.id == calibration.id }
        
        if let encoded = try? JSONEncoder().encode(calibrations) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
        
        // Clear active calibration if it was deleted
        if activeCalibrationID == calibration.id {
            activeCalibrationID = nil
        }
    }
    
    /// The ID of the currently active calibration (nil means no calibration applied)
    /// This is the fallback when no device-specific calibration is set
    var activeCalibrationID: UUID? {
        get {
            guard let uuidString = UserDefaults.standard.string(forKey: activeCalibrationKey) else {
                return nil
            }
            return UUID(uuidString: uuidString)
        }
        set {
            if let id = newValue {
                UserDefaults.standard.set(id.uuidString, forKey: activeCalibrationKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeCalibrationKey)
            }
        }
    }
    
    /// Gets the currently active calibration, if any
    var activeCalibration: MicrophoneCalibration? {
        guard let id = activeCalibrationID else { return nil }
        return loadAll().first { $0.id == id }
    }
    
    // MARK: - Device-Specific Calibration Mapping
    
    /// UserDefaults key for device-to-calibration mapping
    private let deviceCalibrationMapKey = "deviceCalibrationMap"
    
    /// Associates a calibration with a specific audio device
    /// - Parameters:
    ///   - calibrationID: The calibration ID to associate (nil to clear)
    ///   - deviceUID: The unique identifier of the audio device
    func setCalibration(_ calibrationID: UUID?, forDeviceUID deviceUID: String) {
        var mapping = loadDeviceCalibrationMap()
        
        if let id = calibrationID {
            mapping[deviceUID] = id.uuidString
        } else {
            mapping.removeValue(forKey: deviceUID)
        }
        
        if let encoded = try? JSONEncoder().encode(mapping) {
            UserDefaults.standard.set(encoded, forKey: deviceCalibrationMapKey)
        }
    }
    
    /// Gets the calibration ID associated with a specific device
    /// - Parameter deviceUID: The unique identifier of the audio device
    /// - Returns: The calibration ID if one is mapped, nil otherwise
    func calibrationID(forDeviceUID deviceUID: String) -> UUID? {
        let mapping = loadDeviceCalibrationMap()
        guard let uuidString = mapping[deviceUID] else { return nil }
        return UUID(uuidString: uuidString)
    }
    
    /// Gets the calibration associated with a specific device
    /// - Parameter deviceUID: The unique identifier of the audio device
    /// - Returns: The calibration if one is mapped, nil otherwise
    func calibration(forDeviceUID deviceUID: String) -> MicrophoneCalibration? {
        guard let id = calibrationID(forDeviceUID: deviceUID) else { return nil }
        return loadAll().first { $0.id == id }
    }
    
    /// Loads the device-to-calibration mapping from UserDefaults
    private func loadDeviceCalibrationMap() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: deviceCalibrationMapKey),
              let mapping = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return mapping
    }
    
    /// Clears all device-specific calibration mappings
    func clearAllDeviceMappings() {
        UserDefaults.standard.removeObject(forKey: deviceCalibrationMapKey)
    }
}
