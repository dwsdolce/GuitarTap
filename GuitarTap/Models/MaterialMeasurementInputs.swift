//
//  MaterialMeasurementInputs.swift
//  GuitarTap
//
// @parity model/material-measurement-inputs tests=test/material-measurement-inputs

/// The material inputs of the **current measurement** — "Store B" in the measurement-dimensions
/// design (`GuitarTapWeb/Development/MEASUREMENT-DIMENSIONS-SPEC.md`).
///
/// This is the *sole* source for a material measurement's derived properties, its Results-panel
/// display/edit, and Save. It is distinct from `TapDisplaySettings`, which holds only the **defaults
/// for a new measurement** (Store A). A measurement's values are seeded from the settings *at
/// completion*, restored from the file's snapshot on load, and edited in the Results panel — none of
/// which touch the settings. The analyzer holds it as `materialInputs` (`nil` for guitar, and before
/// a material measurement completes).
struct MaterialMeasurementInputs: Equatable {
    var lengthMM: Float
    var widthMM: Float
    var thicknessMM: Float
    var massG: Float
    // Plate-only (Gore target thickness); carried but unused for brace. These affect only the
    // calculated Gore target thickness — nothing about capture — so they are editable per-measurement.
    // (measureFlc is deliberately NOT here: it decides *at capture* whether the FLC phase is tapped;
    // the completed calc then keys on whether an FLC peak was captured, not on this flag. Editing it
    // post-capture could only *ignore a captured FLC* — not worth supporting — so it stays a
    // Settings-only capture setting.)
    var bodyLengthMM: Float
    var bodyWidthMM: Float
    var stiffnessPreset: PlateStiffnessPreset
    var customStiffness: Float

    /// The four sample dimensions as a `MaterialDimensions` for the property calculations.
    var dimensions: MaterialDimensions {
        MaterialDimensions(lengthMM: lengthMM, widthMM: widthMM, thicknessMM: thicknessMM, massGrams: massG)
    }

    /// Effective vibrational stiffness f_vs — the custom value when the preset is Custom, else the
    /// preset's value. Mirrors `TapDisplaySettings.plateStiffness`.
    var stiffness: Float {
        stiffnessPreset == .custom ? customStiffness : stiffnessPreset.value
    }

    /// Snapshot the current Settings defaults (Store A) for a measurement of `type` — used to seed the
    /// measurement's own values when it completes.
    static func fromSettings(for type: MeasurementType) -> MaterialMeasurementInputs {
        let brace = type.isBrace
        return MaterialMeasurementInputs(
            lengthMM:    brace ? TapDisplaySettings.braceLength    : TapDisplaySettings.plateLength,
            widthMM:     brace ? TapDisplaySettings.braceWidth     : TapDisplaySettings.plateWidth,
            thicknessMM: brace ? TapDisplaySettings.braceThickness : TapDisplaySettings.plateThickness,
            massG:       brace ? TapDisplaySettings.braceMass      : TapDisplaySettings.plateMass,
            bodyLengthMM: TapDisplaySettings.guitarBodyLength,
            bodyWidthMM:  TapDisplaySettings.guitarBodyWidth,
            stiffnessPreset: TapDisplaySettings.plateStiffnessPreset,
            customStiffness: TapDisplaySettings.customPlateStiffness
        )
    }
}
