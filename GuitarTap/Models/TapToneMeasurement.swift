//
//  TapToneMeasurement.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import SwiftUI

/// Represents a complete tap tone measurement
struct TapToneMeasurement: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let peaks: [ResonantPeak]
    let decayTime: Float?       // seconds
    let tapLocation: String?    // e.g., "Bridge", "Soundhole", "Upper Bout"
    let notes: String?
    let spectrumSnapshot: SpectrumSnapshot?  // Full spectrum data for guitar measurements
    let chartImageFilename: String?   // Filename of associated PNG image (e.g., "measurement-uuid.png")
    let peakAnnotationOffsets: [UUID: CGPoint]?  // Custom annotation positions
    let selectedPeakIDs: [UUID]?  // Peak IDs marked as significant results
    let annotationVisibilityMode: AnnotationVisibilityMode?  // Which annotations were visible when saved
    
    // Analysis settings (added for export/import)
    let tapDetectionThreshold: Float?  // dB
    let hysteresisMargin: Float?       // dB
    let numberOfTaps: Int?             // Number of taps averaged
    
    // Material measurement data (stored when measurementType is .material or .brace)
    let selectedLongitudinalPeakID: UUID?  // Peak selected as longitudinal mode
    let selectedCrossPeakID: UUID?         // Peak selected as cross-grain mode
    let selectedFlcPeakID: UUID?           // Peak selected as FLC (diagonal/shear) mode

    // Per-phase spectra for material/brace measurements (each tap orientation's averaged spectrum)
    let longitudinalSnapshot: SpectrumSnapshot?  // Spectrum from longitudinal (L) tap
    let crossSnapshot: SpectrumSnapshot?         // Spectrum from cross-grain (C) tap
    let flcSnapshot: SpectrumSnapshot?           // Spectrum from FLC (diagonal) tap

    // Per-peak user mode overrides (nil means all peaks use auto-classification on load)
    let peakModeOverrides: [UUID: UserAssignedMode]?

    // Microphone info at time of recording
    let microphoneName: String?   // Human-readable device name
    let microphoneUID: String?    // Unique device identifier for matching
    let calibrationName: String?  // Active calibration profile name, if any
    
    // Transient property - not saved in JSON, used for runtime image handling
    var chartImageData: Data?
    
    // Custom coding to exclude transient imageData from JSON
    enum CodingKeys: String, CodingKey {
        case id, timestamp, peaks, decayTime, tapLocation, notes
        case spectrumSnapshot, chartImageFilename, peakAnnotationOffsets
        case tapDetectionThreshold, hysteresisMargin, numberOfTaps
        case selectedLongitudinalPeakID, selectedCrossPeakID, selectedFlcPeakID
        case longitudinalSnapshot, crossSnapshot, flcSnapshot
        case selectedPeakIDs, annotationVisibilityMode
        case peakModeOverrides
        case microphoneName, microphoneUID, calibrationName
    }
    
    init(peaks: [ResonantPeak], 
         decayTime: Float? = nil, 
         tapLocation: String? = nil, 
         notes: String? = nil, 
         spectrum: SpectrumSnapshot? = nil,
         chartImageFilename: String? = nil,
         chartImageData: Data? = nil,
         annotationOffsets: [UUID: CGPoint]? = nil,
         tapDetectionThreshold: Float? = nil,
         hysteresisMargin: Float? = nil,
         numberOfTaps: Int? = nil,
         selectedLongitudinalPeakID: UUID? = nil,
         selectedCrossPeakID: UUID? = nil,
         selectedFlcPeakID: UUID? = nil,
         longitudinalSnapshot: SpectrumSnapshot? = nil,
         crossSnapshot: SpectrumSnapshot? = nil,
         flcSnapshot: SpectrumSnapshot? = nil,
         selectedPeakIDs: [UUID]? = nil,
         annotationVisibilityMode: AnnotationVisibilityMode? = nil,
         peakModeOverrides: [UUID: UserAssignedMode]? = nil,
         microphoneName: String? = nil,
         microphoneUID: String? = nil,
         calibrationName: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.peaks = peaks
        self.decayTime = decayTime
        self.tapLocation = tapLocation
        self.notes = notes
        self.spectrumSnapshot = spectrum
        self.chartImageFilename = chartImageFilename
        self.chartImageData = chartImageData
        self.peakAnnotationOffsets = annotationOffsets
        self.tapDetectionThreshold = tapDetectionThreshold
        self.hysteresisMargin = hysteresisMargin
        self.numberOfTaps = numberOfTaps
        self.selectedLongitudinalPeakID = selectedLongitudinalPeakID
        self.selectedCrossPeakID = selectedCrossPeakID
        self.selectedFlcPeakID = selectedFlcPeakID
        self.longitudinalSnapshot = longitudinalSnapshot
        self.crossSnapshot = crossSnapshot
        self.flcSnapshot = flcSnapshot
        self.selectedPeakIDs = selectedPeakIDs
        self.annotationVisibilityMode = annotationVisibilityMode
        self.peakModeOverrides = peakModeOverrides
        self.microphoneName = microphoneName
        self.microphoneUID = microphoneUID
        self.calibrationName = calibrationName
    }
    
    /// Get tap tone ratio (Top / Air)
    /// This ratio indicates the relationship between the main top resonance and the air cavity resonance
    var tapToneRatio: Float? {
        guard let airPeak = peaks.first(where: { GuitarMode.classify(frequency: $0.frequency).normalized == .air }),
              let topPeak = peaks.first(where: { GuitarMode.classify(frequency: $0.frequency).normalized == .top }) else {
            return nil
        }
        return topPeak.frequency / airPeak.frequency
    }
    
    /// Generate base filename (without extension) for this measurement
    var baseFilename: String {
        let locationPart = tapLocation?.replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .lowercased() ?? "measurement"
        let timestampPart = Int(timestamp.timeIntervalSince1970)
        return "\(locationPart)-\(timestampPart)"
    }
}
