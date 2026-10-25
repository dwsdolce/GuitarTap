//
//  DetectedPeaks.swift
//  GuitarTap
//
//  The detected peaks, published for the views that show them: the chart's dots and labels, the Results list and
//  the controls that need peaks.
//
// @parity model/detected-peaks tests=test/detected-peaks
//

import Combine
import Foundation

/// The detected peaks — all of them, their Peak Min projection, their modes and which are selected — owned by
/// ``TapToneAnalyzer`` as `peaks`, which reads and writes them through its own ``TapToneAnalyzer/allPeaks``,
/// ``TapToneAnalyzer/peaksAbovePeakMin``, ``TapToneAnalyzer/identifiedModes`` and
/// ``TapToneAnalyzer/selectedPeakIDs``.
///
/// While a sequence waits for a tap they are found again on every live frame, several times a second; once a
/// measurement completes they are its peaks. They are an object of their own so that only the views that show
/// peaks observe them: published on the analyzer, every frame would rebuild every view that observes the analyzer
/// for anything else — the whole main window among them, and on iOS a menu open anywhere in the window would be
/// rebuilt under the user's finger.
final class DetectedPeaks: ObservableObject {

    /// Every peak found, down to the detection floor, regardless of Peak Min.
    @Published var allPeaks: [ResonantPeak] = []

    /// ``allPeaks`` with Peak Min applied — set by the analyzer, which owns Peak Min.
    @Published var peaksAbovePeakMin: [ResonantPeak] = []

    /// Each peak paired with the mode it is classified as.
    @Published var identifiedModes: [(peak: ResonantPeak, mode: GuitarMode)] = []

    /// The peaks the user has marked as significant.
    @Published var selectedPeakIDs: Set<UUID> = []
}
