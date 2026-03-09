//
//  SpectrumSnapshot.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

import Foundation

/// Complete spectrum snapshot with all data needed to recreate the plot
struct SpectrumSnapshot: Codable {
    let frequencies: [Float]
    let magnitudes: [Float]
    let minFreq: Float
    let maxFreq: Float
    let minDB: Float
    let maxDB: Float
    let isLogarithmic: Bool
    let showUnknownModes: Bool?  // Added for controlling unknown mode display in exports
    let guitarType: GuitarType?  // Added for storing guitar type setting
    let measurementType: MeasurementType?  // Added for storing measurement type (guitar vs material)
    let maxPeaks: Int?  // Maximum number of peaks to detect and store

    // Material-specific settings (stored when measurementType is .material)
    let materialLength: Float?      // mm - plate length (along grain)
    let materialWidth: Float?       // mm - plate width (cross grain)
    let materialThickness: Float?   // mm - plate thickness
    let materialMass: Float?        // grams - plate mass

    // Gore thicknessing settings (stored when measurementType is .material)
    let guitarBodyLength: Float?    // mm - guitar body length
    let guitarBodyWidth: Float?     // mm - guitar body width
    let plateStiffnessPreset: PlateStiffnessPreset?  // Panel Type selection
    let customPlateStiffness: Float?  // Custom f_vs value (used when preset is .custom)
    let measureFlc: Bool?           // Whether FLC diagonal tap is included

    // Brace-specific settings (stored when measurementType is .brace)
    let braceLength: Float?         // mm
    let braceWidth: Float?          // mm
    let braceThickness: Float?      // mm
    let braceMass: Float?           // grams

    init(frequencies: [Float], magnitudes: [Float], minFreq: Float, maxFreq: Float,
         minDB: Float, maxDB: Float, isLogarithmic: Bool,
         showUnknownModes: Bool? = nil, guitarType: GuitarType? = nil,
         measurementType: MeasurementType? = nil, maxPeaks: Int? = nil,
         materialLength: Float? = nil, materialWidth: Float? = nil,
         materialThickness: Float? = nil, materialMass: Float? = nil,
         guitarBodyLength: Float? = nil, guitarBodyWidth: Float? = nil,
         plateStiffnessPreset: PlateStiffnessPreset? = nil,
         customPlateStiffness: Float? = nil, measureFlc: Bool? = nil,
         braceLength: Float? = nil, braceWidth: Float? = nil,
         braceThickness: Float? = nil, braceMass: Float? = nil) {
        self.frequencies = frequencies
        self.magnitudes = magnitudes
        self.minFreq = minFreq
        self.maxFreq = maxFreq
        self.minDB = minDB
        self.maxDB = maxDB
        self.isLogarithmic = isLogarithmic
        self.showUnknownModes = showUnknownModes
        self.guitarType = guitarType
        self.measurementType = measurementType
        self.maxPeaks = maxPeaks
        self.materialLength = materialLength
        self.materialWidth = materialWidth
        self.materialThickness = materialThickness
        self.materialMass = materialMass
        self.guitarBodyLength = guitarBodyLength
        self.guitarBodyWidth = guitarBodyWidth
        self.plateStiffnessPreset = plateStiffnessPreset
        self.customPlateStiffness = customPlateStiffness
        self.measureFlc = measureFlc
        self.braceLength = braceLength
        self.braceWidth = braceWidth
        self.braceThickness = braceThickness
        self.braceMass = braceMass
    }
}
