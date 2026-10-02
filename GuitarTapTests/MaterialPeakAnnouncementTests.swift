//
//  MaterialPeakAnnouncementTests.swift
//  GuitarTapTests
//
// @parity test/display-range
//
// The chart widens onto a newly identified plate / brace peak by observing the analyzer's three
// material peaks. These pin that each write of a peak is announced to observers: a load announces
// the measurement's peaks, and a redo announces the cleared one. The widening decision itself is in
// DisplayRangeExpansionTests.

import Combine
import Foundation
import Testing
@testable import GuitarTap

@Suite("MaterialPeakAnnouncement", .serialized)
struct MaterialPeakAnnouncementTests {

    private func plateMeasurement(l: ResonantPeak, c: ResonantPeak, flc: ResonantPeak) -> TapToneMeasurement {
        let snap = SpectrumSnapshot(
            frequencies: [100, 200], magnitudes: [-10, -20],
            minFreq: 50, maxFreq: 300, minDB: -100, maxDB: 0, isLogarithmic: false,
            measurementType: .plate)
        return TapToneMeasurement(peaks: [l, c, flc],
                                  selectedLongitudinalPeakID: l.id,
                                  selectedCrossPeakID: c.id,
                                  selectedFlcPeakID: flc.id,
                                  longitudinalSnapshot: snap)
    }

    /// The non-nil frequencies each publisher announced after subscription, in order.
    private final class Announcements {
        var longitudinal: [Float?] = []
        var cross: [Float?] = []
        var flc: [Float?] = []
        var bag: Set<AnyCancellable> = []

        init(_ sut: TapToneAnalyzer) {
            sut.$selectedLongitudinalPeak.dropFirst().sink { [unowned self] in longitudinal.append($0?.frequency) }.store(in: &bag)
            sut.$selectedCrossPeak.dropFirst().sink { [unowned self] in cross.append($0?.frequency) }.store(in: &bag)
            sut.$selectedFlcPeak.dropFirst().sink { [unowned self] in flc.append($0?.frequency) }.store(in: &bag)
        }
    }

    @Test func loadingAPlate_announcesEachOfItsPeaks() {
        let sut = TapToneAnalyzer.forTesting()
        let heard = Announcements(sut)
        sut.loadMeasurement(plateMeasurement(l: ResonantPeak(frequency: 1500, magnitude: -20),
                                             c: ResonantPeak(frequency: 180, magnitude: -25),
                                             flc: ResonantPeak(frequency: 410, magnitude: -30)))
        #expect(heard.longitudinal.last == 1500)
        #expect(heard.cross.last == 180)
        #expect(heard.flc.last == 410)
    }

    @Test func loadedPeaks_areMarkedAsFromALoad_untilANewSequence() {
        let sut = TapToneAnalyzer.forTesting()
        sut.loadMeasurement(plateMeasurement(l: ResonantPeak(frequency: 1500, magnitude: -20),
                                             c: ResonantPeak(frequency: 180, magnitude: -25),
                                             flc: ResonantPeak(frequency: 410, magnitude: -30)))
        #expect(sut.materialPeaksFromLoad)
        sut.startTapSequence()
        #expect(sut.materialPeaksFromLoad == false)
    }

    @Test func redoingAPhase_announcesItsPeakCleared() {
        let sut = TapToneAnalyzer.forTesting()
        sut.selectedLongitudinalPeak = ResonantPeak(frequency: 1500, magnitude: -20)
        sut.materialTapPhase = .reviewingLongitudinal
        let heard = Announcements(sut)
        sut.redoCurrentPhase()
        #expect(heard.longitudinal == [nil])
    }
}
