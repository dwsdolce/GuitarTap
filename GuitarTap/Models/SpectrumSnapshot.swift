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
    
    init(frequencies: [Float], magnitudes: [Float], minFreq: Float, maxFreq: Float, minDB: Float, maxDB: Float, isLogarithmic: Bool, showUnknownModes: Bool? = nil, guitarType: GuitarType? = nil, measurementType: MeasurementType? = nil, maxPeaks: Int? = nil, materialLength: Float? = nil, materialWidth: Float? = nil, materialThickness: Float? = nil, materialMass: Float? = nil) {
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
    }
}
