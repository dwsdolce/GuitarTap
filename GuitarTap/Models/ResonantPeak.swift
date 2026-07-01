//
//  ResonantPeak.swift
//  GuitarTap
//
//  Created on 1/25/26.
//
// @parity dsp/find-peaks tests=test/peaks

/// # ResonantPeak
///
/// A single detected spectral peak extracted from a frequency-domain analysis of an acoustic tap.
///
/// Each `ResonantPeak` captures the essential characteristics of a resonance: its centre frequency,
/// signal level, sharpness (Q factor), and optional musical pitch context.  Peaks are produced by
/// ``TapToneAnalyzer/TapToneAnalyzer+PeakAnalysis`` using parabolic interpolation for sub-bin
/// frequency accuracy and a -3 dB bandwidth method for Q-factor estimation.
///
/// A peak is `Identifiable` so that SwiftUI lists and dictionaries (e.g. annotation offsets,
/// mode overrides) can track it across redraws.  It is `Codable` for JSON persistence inside
/// ``TapToneMeasurement``.
import Foundation

/// A single resonant peak detected in the frequency spectrum of an acoustic tap tone measurement.
///
/// Peaks are produced by parabolic interpolation across adjacent FFT bins, giving sub-bin
/// frequency accuracy that is roughly 10× finer than the raw bin spacing. The `quality` and
/// `bandwidth` fields are derived from the -3 dB points surrounding the peak centre.
///
/// - SeeAlso: ``TapToneAnalyzer`` for the detection pipeline.
/// - SeeAlso: ``GuitarMode`` for how a peak's frequency maps to a resonance mode.
struct ResonantPeak: Identifiable, Codable {

    /// Stable unique identifier used by SwiftUI and dictionaries (annotation offsets, mode overrides).
    let id: UUID

    /// Centre frequency of this resonance, in Hz.
    ///
    /// Determined by parabolic interpolation through the peak bin and its two neighbours,
    /// yielding accuracy well below the FFT bin spacing.
    let frequency: Float

    /// Peak signal level, in dBFS (decibels relative to full scale).
    ///
    /// The parabolic interpolation also corrects the magnitude to reflect the true peak
    /// amplitude rather than the sampled bin value.  Typical values range from roughly
    /// -80 dB (weak overtone) to -20 dB (strong resonance).
    let magnitude: Float

    /// Q factor (quality factor) — a dimensionless measure of resonance sharpness.
    ///
    /// Computed as `Q = f₀ / Δf₋₃dB`, where `Δf₋₃dB` is the bandwidth between the
    /// two -3 dB points flanking the peak.  Higher Q values indicate a narrower,
    /// more sustained resonance.  Values below ~3 typically indicate a broad impact
    /// thud rather than a true structural resonance, and are filtered out during
    /// gated-FFT analysis.
    let quality: Float

    /// Bandwidth of this resonance at its -3 dB points, in Hz.
    ///
    /// Relates to ``quality`` by `bandwidth = frequency / quality`.
    let bandwidth: Float

    /// Wall-clock time at which this peak was detected.
    let timestamp: Date

    // MARK: - Pitch Information

    /// The nearest equal-temperament note name, e.g. `"A4"` or `"C#3"`.
    ///
    /// `nil` when pitch detection is unavailable or disabled.
    let pitchNote: String?

    /// Signed offset from the nearest equal-temperament pitch, in cents (¹⁄₁₀₀ semitone).
    ///
    /// Ranges from -50 to +50.  Negative values mean the peak is flat; positive values
    /// mean it is sharp.  `nil` when ``pitchNote`` is `nil`.
    let pitchCents: Double?

    /// Frequency of the nearest equal-temperament pitch, in Hz.
    ///
    /// Useful for displaying the reference note alongside the measured ``frequency``.
    /// `nil` when ``pitchNote`` is `nil`.
    let pitchFrequency: Double?

    // MARK: - Initializer

    /// Creates a new `ResonantPeak` with the given acoustic measurements.
    ///
    /// A fresh `UUID` and the current wall-clock time are assigned automatically.
    ///
    /// - Parameters:
    ///   - frequency: Centre frequency in Hz.
    ///   - magnitude: Peak level in dBFS.
    ///   - quality: Q factor (dimensionless).  Defaults to `0` when not computed.
    ///   - bandwidth: -3 dB bandwidth in Hz.  Defaults to `0` when not computed.
    ///   - pitchNote: Nearest note name string, e.g. `"A4"`.  Pass `nil` if unknown.
    ///   - pitchCents: Signed cents offset from `pitchNote`.  Pass `nil` if unknown.
    ///   - pitchFrequency: Frequency in Hz of `pitchNote`.  Pass `nil` if unknown.
    init(frequency: Float, magnitude: Float, quality: Float = 0, bandwidth: Float = 0,
         pitchNote: String? = nil, pitchCents: Double? = nil, pitchFrequency: Double? = nil) {
        self.id = UUID()
        self.frequency = frequency
        self.magnitude = magnitude
        self.quality = quality
        self.bandwidth = bandwidth
        self.timestamp = Date()
        self.pitchNote = pitchNote
        self.pitchCents = pitchCents
        self.pitchFrequency = pitchFrequency
    }

    // MARK: - Computed Properties

    /// A human-readable pitch string combining the note name and cents deviation.
    ///
    /// Returns a string in the form `"A4 (+12 ¢)"` or `"C#3 (-5 ¢)"`.
    /// Returns `"N/A"` when pitch information is unavailable.
    var formattedPitch: String {
        guard let note = pitchNote, let cents = pitchCents else {
            return "N/A"
        }
        let sign = cents >= 0 ? "+" : ""
        return "\(note) (\(sign)\(String(format: "%.0f", cents)) ¢)"
    }
}
