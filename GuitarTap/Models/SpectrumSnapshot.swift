//
//  SpectrumSnapshot.swift
//  GuitarTap
//
//  Created on 1/25/26.
//

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
struct SpectrumSnapshot: Codable {

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

    /// `true` when the frequency axis was displayed on a logarithmic scale.
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

    /// Maximum number of peaks that the analyzer was configured to detect and annotate.
    ///
    /// `nil` in older snapshots without this field.
    let maxPeaks: Int?

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
    ///   - isLogarithmic: `true` if the frequency axis was logarithmic.
    ///   - showUnknownModes: Whether unknown-mode peaks were visible.
    ///   - guitarType: Guitar classification active at save time.
    ///   - measurementType: Measurement mode (guitar / plate / brace) at save time.
    ///   - maxPeaks: Peak count limit configured at save time.
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
         measurementType: MeasurementType? = nil, maxPeaks: Int? = nil,
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
        self.maxPeaks = maxPeaks
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
