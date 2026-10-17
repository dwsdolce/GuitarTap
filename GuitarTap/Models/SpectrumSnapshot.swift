//
//  SpectrumSnapshot.swift
//  GuitarTap
//
//  Created on 1/25/26.
//
// @parity model/measurement-codable tests=test/measurement-codable,test/peak-heal,test/peak-selection-persistence

/// # SpectrumSnapshot
///
/// An immutable, serialisable copy of the frequency-domain data and all display/analysis settings
/// needed to faithfully reproduce a spectrum plot.
///
/// `SpectrumSnapshot` serves two roles:
///
/// 1. **Guitar measurements** — a single snapshot stored in ``TapToneMeasurement/spectrumSnapshot``
///    captures the averaged spectrum from all taps together with the chart axis ranges and guitar
///    type in use at save time.
///
/// 2. **Plate/brace material measurements** — three optional per-phase snapshots
///    (``TapToneMeasurement/longitudinalSnapshot``, ``TapToneMeasurement/crossSnapshot``,
///    ``TapToneMeasurement/flcSnapshot``) each hold the spectrum from one tap orientation,
///    enabling the material property calculations to be replayed after loading.
///
/// Fields that are not relevant to a particular measurement type are stored as `nil` and simply
/// ignored when the snapshot is later consumed.
import Foundation

/// An immutable record of a complete frequency spectrum together with the chart settings
/// and measurement parameters that were active when it was captured.
///
/// A snapshot contains everything needed to recreate the spectrum chart exactly as it appeared
/// at the time of saving.  Measurement-type-specific fields (plate dimensions, Gore thicknessing
/// parameters, brace dimensions) are `nil` when not applicable.
///
/// - SeeAlso: ``TapToneMeasurement`` which embeds one or more snapshots per saved measurement.
struct SpectrumSnapshot: Codable { // Codable satisfied by custom encode/init below

    // MARK: - Coding Keys

    private enum CodingKeys: String, CodingKey {
        // Compact binary (new format) — Base64-encoded little-endian IEEE-754 float32 arrays
        case frequenciesData, magnitudesData
        // Legacy text arrays (old format) — kept for decode fallback only
        case frequencies, magnitudes
        // All other scalar fields
        case minFreq, maxFreq, minDB, maxDB, isLogarithmic
        case showUnknownModes, guitarType, measurementType
        case plateLength, plateWidth, plateThickness, plateMass
        case guitarBodyLength, guitarBodyWidth
        case plateStiffnessPreset, customPlateStiffness, measureFlc
        case braceLength, braceWidth, braceThickness, braceMass
    }

    // MARK: - Encoding

    /// Encodes float arrays as compact Base64 binary (`frequenciesData` / `magnitudesData`).
    ///
    /// Each array is stored as raw little-endian IEEE-754 float32 bytes and then
    /// Base64-encoded into a JSON string.  This is ~10× smaller than pretty-printed
    /// decimal text and keeps AirDrop transfers well within reliable size limits.
    ///
    /// The legacy `frequencies` / `magnitudes` keys are **not** written; the decoder
    /// falls back to them only for files created by older builds.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        // Encode float arrays as Base64 binary blobs
        try c.encode(Self.floatsToBase64(frequencies), forKey: .frequenciesData)
        try c.encode(Self.floatsToBase64(magnitudes),  forKey: .magnitudesData)

        // All scalar fields
        try c.encode(minFreq,       forKey: .minFreq)
        try c.encode(maxFreq,       forKey: .maxFreq)
        try c.encode(minDB,         forKey: .minDB)
        try c.encode(maxDB,         forKey: .maxDB)
        try c.encode(isLogarithmic, forKey: .isLogarithmic)
        try c.encodeIfPresent(showUnknownModes,    forKey: .showUnknownModes)
        try c.encodeIfPresent(guitarType,          forKey: .guitarType)
        try c.encodeIfPresent(measurementType,     forKey: .measurementType)
        try c.encodeIfPresent(plateLength,         forKey: .plateLength)
        try c.encodeIfPresent(plateWidth,          forKey: .plateWidth)
        try c.encodeIfPresent(plateThickness,      forKey: .plateThickness)
        try c.encodeIfPresent(plateMass,           forKey: .plateMass)
        try c.encodeIfPresent(guitarBodyLength,    forKey: .guitarBodyLength)
        try c.encodeIfPresent(guitarBodyWidth,     forKey: .guitarBodyWidth)
        try c.encodeIfPresent(plateStiffnessPreset,  forKey: .plateStiffnessPreset)
        try c.encodeIfPresent(customPlateStiffness,  forKey: .customPlateStiffness)
        try c.encodeIfPresent(measureFlc,          forKey: .measureFlc)
        try c.encodeIfPresent(braceLength,         forKey: .braceLength)
        try c.encodeIfPresent(braceWidth,          forKey: .braceWidth)
        try c.encodeIfPresent(braceThickness,      forKey: .braceThickness)
        try c.encodeIfPresent(braceMass,           forKey: .braceMass)
    }

    // MARK: - Decoding

    /// Decodes spectrum data, accepting both the new compact binary format and the
    /// legacy plain-`[Float]` format for backward compatibility with older files.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Try compact binary first; fall back to legacy text arrays
        if let freqB64 = try c.decodeIfPresent(String.self, forKey: .frequenciesData),
           let magB64  = try c.decodeIfPresent(String.self, forKey: .magnitudesData) {
            frequencies = Self.base64ToFloats(freqB64)
            magnitudes  = Self.base64ToFloats(magB64)
        } else {
            frequencies = try c.decode([Float].self, forKey: .frequencies)
            magnitudes  = try c.decode([Float].self, forKey: .magnitudes)
        }

        minFreq       = try c.decode(Float.self, forKey: .minFreq)
        maxFreq       = try c.decode(Float.self, forKey: .maxFreq)
        minDB         = try c.decode(Float.self, forKey: .minDB)
        maxDB         = try c.decode(Float.self, forKey: .maxDB)
        isLogarithmic = try c.decode(Bool.self,  forKey: .isLogarithmic)
        showUnknownModes   = try c.decodeIfPresent(Bool.self,               forKey: .showUnknownModes)
        guitarType         = try c.decodeIfPresent(GuitarType.self,         forKey: .guitarType)
        measurementType    = try c.decodeIfPresent(MeasurementType.self,    forKey: .measurementType)
        plateLength        = try c.decodeIfPresent(Float.self,              forKey: .plateLength)
        plateWidth         = try c.decodeIfPresent(Float.self,              forKey: .plateWidth)
        plateThickness     = try c.decodeIfPresent(Float.self,              forKey: .plateThickness)
        plateMass          = try c.decodeIfPresent(Float.self,              forKey: .plateMass)
        guitarBodyLength   = try c.decodeIfPresent(Float.self,              forKey: .guitarBodyLength)
        guitarBodyWidth    = try c.decodeIfPresent(Float.self,              forKey: .guitarBodyWidth)
        plateStiffnessPreset = try c.decodeIfPresent(PlateStiffnessPreset.self, forKey: .plateStiffnessPreset)
        customPlateStiffness = try c.decodeIfPresent(Float.self,            forKey: .customPlateStiffness)
        measureFlc         = try c.decodeIfPresent(Bool.self,               forKey: .measureFlc)
        braceLength        = try c.decodeIfPresent(Float.self,              forKey: .braceLength)
        braceWidth         = try c.decodeIfPresent(Float.self,              forKey: .braceWidth)
        braceThickness     = try c.decodeIfPresent(Float.self,              forKey: .braceThickness)
        braceMass          = try c.decodeIfPresent(Float.self,              forKey: .braceMass)
    }

    // MARK: - Binary Helpers

    /// Packs a `[Float]` into raw little-endian IEEE-754 bytes and Base64-encodes them.
    private static func floatsToBase64(_ floats: [Float]) -> String {
        var copy = floats  // ensure native (LE on all Apple silicon + x86) byte order
        let data = Data(bytes: &copy, count: copy.count * MemoryLayout<Float>.size)
        return data.base64EncodedString()
    }

    /// Decodes a Base64 string produced by `floatsToBase64(_:)` back into `[Float]`.
    ///
    /// Returns an empty array if the string is not valid Base64 or has an unexpected length.
    private static func base64ToFloats(_ base64: String) -> [Float] {
        guard let data = Data(base64Encoded: base64),
              data.count % MemoryLayout<Float>.size == 0 else { return [] }
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Float.self).prefix(count))
        }
    }


    // MARK: - Spectrum Data

    /// FFT frequency bins, in Hz, from low to high.
    ///
    /// Parallel array with ``magnitudes``; index *i* gives the frequency of bin *i*.
    let frequencies: [Float]

    /// FFT magnitude values in dBFS, one per entry in ``frequencies``.
    ///
    /// Values are averaged across taps in linear power space before conversion back to dB,
    /// so phase is discarded (appropriate for impulse-response averages).
    let magnitudes: [Float]

    // MARK: - Chart Axis Ranges

    /// Lower bound of the displayed frequency range, in Hz.
    let minFreq: Float

    /// Upper bound of the displayed frequency range, in Hz.
    let maxFreq: Float

    /// Lower bound of the displayed magnitude range, in dBFS.
    let minDB: Float

    /// Upper bound of the displayed magnitude range, in dBFS.
    let maxDB: Float

    /// Legacy field retained for `.guitartap` format compatibility; always `false`.
    /// The frequency axis is linear on all platforms (log-axis support was removed).
    let isLogarithmic: Bool

    // MARK: - Display Settings

    /// Whether peaks classified as ``GuitarMode/unknown`` were shown in the chart annotations.
    ///
    /// `nil` in snapshots created before this field was added (treated as `false` on load).
    let showUnknownModes: Bool?

    /// The guitar type classification (classical, flamenco, acoustic) active at save time.
    ///
    /// Determines which mode frequency bands are drawn on the chart.
    /// `nil` in older snapshots without this field.
    let guitarType: GuitarType?

    /// The measurement type (guitar, plate, or brace) active at save time.
    ///
    /// Controls which sections of the results panel are displayed on load.
    /// `nil` in older snapshots without this field.
    let measurementType: MeasurementType?

    // MARK: - Plate Measurement Settings

    /// Plate length along the grain direction, in mm.
    ///
    /// Populated only when ``measurementType`` is `.plate`.
    let plateLength: Float?

    /// Plate width across the grain direction, in mm.
    ///
    /// Populated only when ``measurementType`` is `.plate`.
    let plateWidth: Float?

    /// Plate thickness, in mm.
    ///
    /// Populated only when ``measurementType`` is `.plate`.
    let plateThickness: Float?

    /// Plate mass, in grams.
    ///
    /// Combined with the dimensions to compute density for the Young's modulus formula.
    /// Populated only when ``measurementType`` is `.plate`.
    let plateMass: Float?

    // MARK: - Gore Thicknessing Settings

    /// Guitar body length used for the Gore target-thickness calculation, in mm.
    ///
    /// Populated only when ``measurementType`` is `.plate`.
    let guitarBodyLength: Float?

    /// Guitar body width used for the Gore target-thickness calculation, in mm.
    ///
    /// Populated only when ``measurementType`` is `.plate`.
    let guitarBodyWidth: Float?

    /// The ``PlateStiffnessPreset`` (panel type) selected for the Gore calculation at save time.
    ///
    /// Populated only when ``measurementType`` is `.plate`.
    let plateStiffnessPreset: PlateStiffnessPreset?

    /// The custom target vibrational stiffness (`f_vs`) used when ``plateStiffnessPreset``
    /// is `.custom`, in N·m.
    ///
    /// `nil` when a non-custom preset was in use.
    let customPlateStiffness: Float?

    /// Whether the optional FLC (diagonal / shear) third tap was included in this plate measurement.
    ///
    /// When `true`, a third tap at 45° to the grain was captured and stored in
    /// ``TapToneMeasurement/flcSnapshot``.
    let measureFlc: Bool?

    // MARK: - Brace Measurement Settings

    /// Brace length along its main axis, in mm.
    ///
    /// Populated only when ``measurementType`` is `.brace`.
    let braceLength: Float?

    /// Brace width (cross-section dimension perpendicular to height), in mm.
    ///
    /// Populated only when ``measurementType`` is `.brace`.
    let braceWidth: Float?

    /// Brace height (cross-section dimension), in mm.
    ///
    /// Populated only when ``measurementType`` is `.brace`.
    let braceThickness: Float?

    /// Brace mass, in grams.
    ///
    /// Combined with dimensions to compute density for the Young's modulus calculation.
    /// Populated only when ``measurementType`` is `.brace`.
    let braceMass: Float?

    // MARK: - Initializer

    /// Creates a `SpectrumSnapshot` with the given spectrum data and settings.
    ///
    /// All measurement-type-specific parameters default to `nil` and should be supplied
    /// only when applicable to the measurement type being saved.
    ///
    /// - Parameters:
    ///   - frequencies: FFT frequency bins in Hz.
    ///   - magnitudes: Corresponding dBFS magnitudes.
    ///   - minFreq: Lower displayed frequency bound, in Hz.
    ///   - maxFreq: Upper displayed frequency bound, in Hz.
    ///   - minDB: Lower displayed magnitude bound, in dBFS.
    ///   - maxDB: Upper displayed magnitude bound, in dBFS.
    ///   - isLogarithmic: Legacy format-compatibility flag; always `false`.
    ///   - showUnknownModes: Whether unknown-mode peaks were visible.
    ///   - guitarType: Guitar classification active at save time.
    ///   - measurementType: Measurement mode (guitar / plate / brace) at save time.
    ///   - plateLength: Plate length in mm (plate measurements only).
    ///   - plateWidth: Plate width in mm (plate measurements only).
    ///   - plateThickness: Plate thickness in mm (plate measurements only).
    ///   - plateMass: Plate mass in grams (plate measurements only).
    ///   - guitarBodyLength: Body length in mm for Gore calculation (plate only).
    ///   - guitarBodyWidth: Body width in mm for Gore calculation (plate only).
    ///   - plateStiffnessPreset: Gore panel-type preset (plate only).
    ///   - customPlateStiffness: Custom `f_vs` value when preset is `.custom` (plate only).
    ///   - measureFlc: Whether a third diagonal tap was included (plate only).
    ///   - braceLength: Brace length in mm (brace measurements only).
    ///   - braceWidth: Brace width in mm (brace measurements only).
    ///   - braceThickness: Brace height in mm (brace measurements only).
    ///   - braceMass: Brace mass in grams (brace measurements only).
    init(frequencies: [Float], magnitudes: [Float], minFreq: Float, maxFreq: Float,
         minDB: Float, maxDB: Float, isLogarithmic: Bool,
         showUnknownModes: Bool? = nil, guitarType: GuitarType? = nil,
         measurementType: MeasurementType? = nil,
         plateLength: Float? = nil, plateWidth: Float? = nil,
         plateThickness: Float? = nil, plateMass: Float? = nil,
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
        self.plateLength = plateLength
        self.plateWidth = plateWidth
        self.plateThickness = plateThickness
        self.plateMass = plateMass
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
