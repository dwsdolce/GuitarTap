//
//  MicSelectionTests.swift
//  GuitarTapTests
//
//  Tests for which input device the engine uses and which it saves: the rule
//  inputDeviceToUse (MS1–MS5), the engine driven through applyInputDeviceList,
//  chooseInputDevice and setInputDevice (MS6–MS11), and a measurement load switching to its
//  recorded microphone (MS14–MS17), and choosing a calibration for the selected device
//  (MS18–MS20). MS12–MS13 are Python only.
//
//  The rule: the saved choice when it is present, otherwise the system default input,
//  otherwise the first device. Only a choice — picked in Settings, or plugged in while the
//  app runs — is saved; the startup selection, a fallback and a loaded measurement's
//  microphone are not.
//
//  The saved choice and the calibration store live in TapDisplaySettings.defaults, an isolated
//  suite under test.
//
//  Test plan coverage: MS1–MS11, MS14–MS20 — the same list, ids and devices as Python
//  test_mic_selection.py and web test/mic-selection.test.ts.
//
// @parity test/mic-selection

#if os(macOS)
import Testing
import Foundation
@testable import GuitarTap

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

private func device(_ name: String, _ id: UInt32) -> AVAudioDevice {
    AVAudioDevice(name: name, uid: "\(name)-uid", sampleRate: 48000, deviceID: id)
}

private let builtIn = device("MacBook Pro Microphone", 1)
private let blackHole = device("BlackHole 2ch", 2)
private let umik = device("UMIK-1", 3)

/// A fresh engine with `saved` as the saved choice (nil: nothing saved).
@MainActor
private func makeSUT(saved: AVAudioDevice?) -> RealtimeFFTAnalyzer {
    TapDisplaySettings.selectedInputDeviceUID = saved?.uid
    return RealtimeFFTAnalyzer.forTesting()
}

/// Waits for work the engine dispatched to the main queue.
private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

@Suite("MicSelection", .serialized)
@MainActor
struct MicSelectionTests {

    // MARK: - The rule

    // MS1: The saved device wins when it is present — over the system default, and over any
    //      other device (the built-in mic is kept although a USB mic and BlackHole are listed).
    @Test func MS1_savedPresent_wins() {
        let chosen = RealtimeFFTAnalyzer.inputDeviceToUse(
            in: [blackHole, builtIn, umik], savedUID: builtIn.uid, systemDefaultUID: umik.uid)
        #expect(chosen == builtIn)
    }

    // MS2: The saved device is not connected — the system default.
    @Test func MS2_savedAbsent_usesSystemDefault() {
        let chosen = RealtimeFFTAnalyzer.inputDeviceToUse(
            in: [blackHole, builtIn], savedUID: umik.uid, systemDefaultUID: builtIn.uid)
        #expect(chosen == builtIn)
    }

    // MS3: Nothing saved — the system default, not a device listed ahead of it (BlackHole).
    @Test func MS3_nothingSaved_usesSystemDefault() {
        let chosen = RealtimeFFTAnalyzer.inputDeviceToUse(
            in: [blackHole, builtIn], savedUID: nil, systemDefaultUID: builtIn.uid)
        #expect(chosen == builtIn)
    }

    // MS4: No usable system default — the first device.
    @Test func MS4_noDefault_usesFirstDevice() {
        let chosen = RealtimeFFTAnalyzer.inputDeviceToUse(
            in: [umik, builtIn], savedUID: nil, systemDefaultUID: nil)
        #expect(chosen == umik)
    }

    // MS5: No devices — nothing.
    @Test func MS5_noDevices_selectsNothing() {
        #expect(RealtimeFFTAnalyzer.inputDeviceToUse(in: [], savedUID: builtIn.uid,
                                                     systemDefaultUID: builtIn.uid) == nil)
    }

    // MARK: - The engine: what is selected, and what is saved

    // MS6: The startup selection is not saved: nothing saved, the default is selected, and
    //      nothing is saved afterwards.
    @Test func MS6_startupSelection_isNotSaved() {
        let sut = makeSUT(saved: nil)
        sut.applyInputDeviceList([blackHole, builtIn], systemDefaultUID: builtIn.uid)
        #expect(sut.selectedInputDevice == builtIn)
        #expect(TapDisplaySettings.selectedInputDeviceUID == nil)
    }

    // MS7: A device the user chooses is selected and saved.
    @Test func MS7_choice_isSaved() {
        let sut = makeSUT(saved: builtIn)
        sut.applyInputDeviceList([builtIn, umik], systemDefaultUID: builtIn.uid)
        sut.chooseInputDevice(umik)
        #expect(sut.selectedInputDevice == umik)
        #expect(TapDisplaySettings.selectedInputDeviceUID == umik.uid)
    }

    // MS8: A device plugged in while running is switched to and saved.
    @Test func MS8_pluggedIn_isSelectedAndSaved() {
        let sut = makeSUT(saved: builtIn)
        sut.applyInputDeviceList([builtIn], systemDefaultUID: builtIn.uid)
        sut.applyInputDeviceList([builtIn, umik], systemDefaultUID: builtIn.uid)
        #expect(sut.selectedInputDevice == umik)
        #expect(TapDisplaySettings.selectedInputDeviceUID == umik.uid)
    }

    // MS9: The saved device unplugged — the system default for the session; the saved choice
    //      is still the unplugged device, so it comes back at the next launch.
    @Test func MS9_savedUnplugged_fallsBack_withoutSaving() {
        let sut = makeSUT(saved: umik)
        sut.applyInputDeviceList([builtIn, umik], systemDefaultUID: builtIn.uid)
        #expect(sut.selectedInputDevice == umik)
        sut.applyInputDeviceList([builtIn], systemDefaultUID: builtIn.uid)
        #expect(sut.selectedInputDevice == builtIn)
        #expect(TapDisplaySettings.selectedInputDeviceUID == umik.uid)
    }

    // MS10: A device used for the session only (not the saved one) unplugged — back to the
    //       saved device, which is present.
    @Test func MS10_sessionDeviceUnplugged_returnsToSaved() {
        let sut = makeSUT(saved: builtIn)
        sut.applyInputDeviceList([builtIn, blackHole, umik], systemDefaultUID: blackHole.uid)
        sut.selectedInputDevice = umik
        sut.applyInputDeviceList([builtIn, blackHole], systemDefaultUID: blackHole.uid)
        #expect(sut.selectedInputDevice == builtIn)
        #expect(TapDisplaySettings.selectedInputDeviceUID == builtIn.uid)
    }

    // MS11: The switch a measurement load makes to its recorded microphone is not saved.
    @Test func MS11_loadSwitch_isNotSaved() async throws {
        let sut = makeSUT(saved: builtIn)
        sut.applyInputDeviceList([builtIn, umik], systemDefaultUID: builtIn.uid)
        try sut.setInputDevice(umik)
        await drainMainQueue()
        #expect(sut.selectedInputDevice == umik)
        #expect(TapDisplaySettings.selectedInputDeviceUID == builtIn.uid)
    }

    // MARK: - Loading a measurement recorded with another connected microphone

    /// An analyzer on the built-in mic (saved) with a calibration, the USB mic connected, and a
    /// measurement recorded with `mic` and `calibrationName`, loaded.
    private func load(recordedWith mic: AVAudioDevice, calibrationName: String? = nil) -> TapToneAnalyzer {
        TapDisplaySettings.selectedInputDeviceUID = builtIn.uid
        let sut = TapToneAnalyzer.forTesting()
        sut.fftAnalyzer.applyInputDeviceList([builtIn, umik], systemDefaultUID: builtIn.uid)
        sut.fftAnalyzer.setCalibrationWithoutSavingDeviceMapping(
            MicrophoneCalibration(name: "Built-in room", correctionPoints: []))
        sut.loadMeasurement(TapToneMeasurement(peaks: [], measurementName: "Loaded",
                                               microphoneName: mic.name, microphoneUID: mic.uid,
                                               calibrationName: calibrationName))
        return sut
    }

    private func loadRecordedWithUSBMic() -> TapToneAnalyzer { load(recordedWith: umik) }

    // MS14: The load has switched to the recorded microphone by the time it returns.
    @Test func MS14_loadSwitch_isInPlaceWhenTheLoadReturns() {
        let sut = loadRecordedWithUSBMic()
        #expect(sut.fftAnalyzer.selectedInputDevice == umik)
    }

    // MS15: The calibration check compares the recorded microphone's calibration (none) — not
    //       that of the microphone switched away from ("Built-in room") — so no warning.
    @Test func MS15_loadCheck_readsTheRecordedMicrophone() {
        let sut = loadRecordedWithUSBMic()
        #expect(sut.fftAnalyzer.activeCalibration == nil)
        #expect(sut.microphoneWarning == nil, "warned: \(sut.microphoneWarning ?? "")")
    }

    // MS16: No connected microphone matches — the not-found warning; the input is unchanged.
    @Test func MS16_noMatch_warnsAndKeepsTheInput() {
        let sut = load(recordedWith: device("Absent Mic", 9))
        #expect(sut.fftAnalyzer.selectedInputDevice == builtIn)
        #expect(sut.microphoneWarning?.hasPrefix(
            "Recorded with 'Absent Mic'. No connected microphone matches that name") == true)
    }

    // MS17: The recorded microphone is the current one but its calibration differs — the warning.
    @Test func MS17_sameMicrophone_differentCalibration_warns() {
        let sut = load(recordedWith: builtIn, calibrationName: "Other")
        #expect(sut.microphoneWarning ==
            "This measurement was recorded with a different calibration. A newly captured tap may not match the saved result.")
    }

    // MARK: - Choosing a calibration

    /// An engine on the built-in mic with the USB mic connected, an empty calibration store, and
    /// `room` saved in it.
    private func engineWithStoredCalibration() -> (RealtimeFFTAnalyzer, MicrophoneCalibration) {
        let storage = CalibrationStorage.shared
        storage.loadAll().forEach { storage.delete($0) }
        storage.activeCalibrationID = nil
        [builtIn, umik].forEach { storage.setCalibration(nil, forDeviceUID: $0.uid) }
        let room = MicrophoneCalibration(name: "Room", correctionPoints: [])
        storage.save(room)
        let sut = makeSUT(saved: builtIn)
        sut.applyInputDeviceList([builtIn, umik], systemDefaultUID: builtIn.uid)
        return (sut, room)
    }

    // MS18: A calibration chosen for the selected device is saved for it (and as the last
    //       chosen); switching to another device and back restores it.
    @Test func MS18_chosenCalibration_isSavedForTheDevice() {
        let (sut, room) = engineWithStoredCalibration()
        sut.activeCalibration = room
        #expect(CalibrationStorage.shared.calibration(forDeviceUID: builtIn.uid)?.id == room.id)
        #expect(CalibrationStorage.shared.activeCalibrationID == room.id)
        sut.chooseInputDevice(umik)
        #expect(sut.activeCalibration == nil)
        sut.chooseInputDevice(builtIn)
        #expect(sut.activeCalibration?.id == room.id)
    }

    // MS19: Choosing no calibration removes the device's: switching away and back gives none.
    @Test func MS19_choosingNone_removesTheDevicesCalibration() {
        let (sut, room) = engineWithStoredCalibration()
        sut.activeCalibration = room
        sut.activeCalibration = nil
        #expect(CalibrationStorage.shared.calibration(forDeviceUID: builtIn.uid) == nil)
        #expect(CalibrationStorage.shared.activeCalibrationID == nil)
        sut.chooseInputDevice(umik)
        sut.chooseInputDevice(builtIn)
        #expect(sut.activeCalibration == nil)
    }

    // MS20: A file playback's calibration (temporary) is applied but saves nothing.
    @Test func MS20_temporaryCalibration_savesNothing() {
        let (sut, room) = engineWithStoredCalibration()
        sut.setTemporaryCalibration(room)
        #expect(sut.activeCalibration?.id == room.id)
        #expect(CalibrationStorage.shared.calibration(forDeviceUID: builtIn.uid) == nil)
        #expect(CalibrationStorage.shared.activeCalibrationID == nil)
    }
}
#endif
